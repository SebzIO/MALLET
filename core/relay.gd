class_name Relay
extends Node
## MALLET's side of the relay (docs/RELAY.md): JSON messages over Godot's WebSocketPeer.
## Add it to the tree, call connect_to() with the hello message, then listen to `opened`, `message`, `failed` and
## `closed`. Everything sent while connecting is queued and goes out as soon as the relay says hello.

signal opened(welcome: Dictionary)      ## the relay accepted us: session code, secret (maker only), peers
signal message(msg: Dictionary)         ## every message after that: live, attempt, peer_join, edge, runs...
signal failed(code: String, message: String)   ## refused (bad secret, unknown session...) or unreachable
signal closed(code: int, reason: String)       ## the connection ended after it was open

const MAX_MESSAGE := 4 << 20            # (the relay refuses anything bigger too)
const SEND_PER_FRAME := 32              # (a burst is spread over frames rather than one long stall)

var state := "idle"                     ## idle / connecting / open / closed
var url := ""
var you := ""                           ## our id at the relay
var session := ""                       ## the session code
var secret := ""                        ## only a maker gets one: it goes into test builds, never into a map
var map_version := 0
var peers := {}                         ## id -> {id, name, role, map_version}

var _ws: WebSocketPeer = null
var _hello: Dictionary = {}
var _queue: Array[String] = []
var _greeted := false


## Connect and say hello. `hello` is the protocol's hello object: role, session, secret, name, map, map_version.
func connect_to(u: String, hello: Dictionary) -> Error:
	close()
	url = u
	_hello = hello.duplicate(true)
	_queue.clear()
	_greeted = false
	state = "connecting"
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = MAX_MESSAGE
	_ws.outbound_buffer_size = MAX_MESSAGE * 2          # (a whole map for a joining editor still fits to send)
	var err := _ws.connect_to_url(u)
	if err != OK:
		_ws = null
		state = "closed"
		failed.emit("connect", "Can't reach the relay at %s." % u)
	return err


func _process(_delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var rs := _ws.get_ready_state()
	if rs == WebSocketPeer.STATE_OPEN:
		if not _greeted:
			_greeted = true
			_ws.send_text(JSON.stringify(_hello))
		_flush()
	# what arrived is read even when the relay closed the socket in the same poll: a refusal (error, then close)
	# must be reported as a refusal, not as "couldn't reach the relay"
	while _ws != null and _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			_on_text(pkt.get_string_from_utf8())
	if _ws == null:
		return                                          # (a refusal closed it; nothing more to poll)
	if rs == WebSocketPeer.STATE_CLOSED and state in ["connecting", "open"]:
		var was := state
		var code := _ws.get_close_code()
		var why := _ws.get_close_reason()
		state = "closed"
		_ws = null
		if was == "open":
			closed.emit(code, why)
		else:
			failed.emit("connect", "Couldn't reach the relay at %s." % url)


## Send a message. While connecting it waits in the queue; once the relay has refused us it is dropped.
func send(d: Dictionary) -> void:
	if state in ["idle", "closed"]:
		return
	_queue.append(JSON.stringify(d))
	_flush()


func is_open() -> bool:
	return state == "open"


func close() -> void:
	if _ws != null:
		_ws.close()
		_ws = null
	state = "closed"
	_queue.clear()


func _flush() -> void:
	if _ws == null or state != "open":
		return
	var n := 0
	while not _queue.is_empty() and n < SEND_PER_FRAME:
		if _ws.send_text(_queue[0]) != OK:
			return                                       # (outbound buffer full: the rest goes next frame)
		_queue.pop_front()
		n += 1


func _on_text(text: String) -> void:
	var d = JSON.parse_string(text)
	if not d is Dictionary:
		return
	var t := String(d.get("t", ""))
	if t == "welcome" and state == "connecting":
		you = String(d.get("you", ""))
		session = String(d.get("session", ""))
		secret = String(d.get("secret", ""))
		map_version = int(d.get("map_version", 0))
		peers.clear()
		for p in (d.get("peers", []) as Array):
			if p is Dictionary:
				peers[String(p.get("id", ""))] = p
		state = "open"
		opened.emit(d)
		return
	if t == "error":
		state = "closed"
		failed.emit(String(d.get("code", "error")), String(d.get("message", "")))
		if _ws != null:
			_ws.close()
			_ws = null
		return
	if t == "peer_join" and d.get("peer") is Dictionary:
		var peer: Dictionary = d["peer"]
		peers[String(peer.get("id", ""))] = peer
	elif t == "peer_leave":
		peers.erase(String(d.get("id", "")))
	message.emit(d)


## A short description of the connection for status lines.
func status_text() -> String:
	match state:
		"connecting": return "Connecting to the relay..."
		"open": return "Connected (session %s, %d other(s) here)" % [session, peers.size()]
		"closed": return "Not connected to the relay"
	return "No playtest session"
