extends SceneTree
## 0.16 playtest session: the editor opens a session against a real relay, a tester joins with its secret, live
## positions and attempts reach the panel and the map, a repeated attempt is kept once, the secret never reaches
## the map, and a test build's tester.cfg carries the session. Window: this instantiates the editor.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/playtest_test.gd -- <out>

const PORT := 8798
const URL := "ws://127.0.0.1:8798/ws"

var ok := true
var relay_pid := -1
var ed
var co_got := []                      ## cursor messages a second editor received from the maker
var co_edits := []                    ## edit messages a second editor received from the maker
var co_states := []                   ## pieces of the map a newcomer asked for


func _note_co(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"cursor": co_got.append(m)
		"edit": co_edits.append(m)
		"state": co_states.append(m)


func _has_uid(msgs: Array, uid: String, act: String) -> bool:
	for m in msgs:
		var op = m.get("op", {})
		if op is Dictionary and String(op.get("act", "edit")) == act and String(op.get("uid", "")) == uid:
			return true
	return false


func _has_act(msgs: Array, act: String) -> bool:
	for m in msgs:
		var op = m.get("op", {})
		if op is Dictionary and String(op.get("act", "edit")) == act:
			return true
	return false


func _vec(a) -> Vector3:
	return Vector3(a[0], a[1], a[2]) if a is Array and (a as Array).size() >= 3 else Vector3.ZERO


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-58s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func wait_for(f: Callable, ms := 6000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if f.call():
			return true
		await process_frame
	return f.call()


var kicked_by := ""


func _note_kick(m: Dictionary) -> void:
	if String(m.get("t", "")) == "kicked":
		kicked_by = String(m.get("by", ""))


func wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


## The first row of the panel's list (fresh each time: a refresh rebuilds the tree).
func row():
	var r = ed._playtest_panel._tree.get_root()
	if r == null or r.get_child_count() == 0:
		return null
	return r.get_child(0)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var log_path := OS.get_environment("TEMP").path_join("playtest_relay.log")
	DirAccess.remove_absolute(log_path)
	relay_pid = OS.create_process("python", ["relay/relay.py", "--port", str(PORT), "--quiet", "--log", log_path])
	check("the relay starts", relay_pid > 0, "pid %d" % relay_pid)
	await wait_ms(1200)

	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._select(null)

	# --- the editor opens a session
	check("starting a session is accepted", ed.start_playtest(URL, "", "", "Maker"))
	var opened := await wait_for(func(): return ed.relay != null and ed.relay.is_open())
	var secret: String = ed.relay.secret if ed.relay != null else ""
	check("the session opens", opened, ed.relay.session if ed.relay != null else "")
	check("the relay gave a code and a secret", ed.relay.session.length() == 6 and secret.length() == 32, ed.relay.session)
	check("the panel is up", ed._playtest_panel.visible)
	check("the secret stays out of the map", not JSON.stringify(ed._map_dict()).contains(secret))
	check("the panel shows the code", ed._playtest_panel._title.text.contains(ed.relay.session))

	# --- a tester joins with that secret
	var tester := Relay.new()
	root.add_child(tester)
	tester.connect_to(URL, {"t": "hello", "v": 1, "role": "tester", "session": ed.relay.session, "secret": secret,
		"name": "Sam", "map": "playtest test", "map_version": 7, "client": MalletVersion.full()})
	check("a tester joins", await wait_for(func(): return tester.is_open()))
	var listed := await wait_for(func(): return row() != null)
	check("the maker's panel lists them", listed and row().get_text(0) == "Sam", row().get_text(0) if listed else "")

	# --- where they are
	tester.send({"t": "live", "attempt": 1, "p": [10, 20, 30], "speed": 640, "stage": 2, "state": "run"})
	check("live positions arrive", await wait_for(func(): return not ed.live_peers.is_empty()))
	check("their trail is kept for the views", not ed.live_trails.is_empty() and (ed.live_trails.values()[0] as Array).size() >= 1)
	check("testers keep one color", ed._tester_color("Sam") == ed._tester_color("Sam"))
	await process_frame
	var where: String = row().get_text(1)
	check("the panel shows where they are", where.contains("stage 2") and where.contains("640"), where)

	# --- their runs
	var attempt := {"outcome": "finish", "time": 12.5, "started": 1000.0, "splits": [[2, 5.0]], "deaths": [[1, 2, 3]],
		"route": [[0.0, 0.0, 0.0, 500], [4, 1, 2, 700], [9, 3, 5, 850]], "top_speed": 900, "finish_speed": 850}
	tester.send({"t": "attempt", "attempt": attempt})
	var kept := await wait_for(func(): return ed.tester_runs.size() == 1 and ed.tester_runs[0]["attempts"].size() == 1)
	check("an attempt is kept with the map", kept)
	tester.send({"t": "attempt", "attempt": attempt})
	await wait_ms(400)
	check("the same attempt is not kept twice", ed.tester_runs[0]["attempts"].size() == 1)
	check("it is in the saved map", JSON.stringify(ed._map_dict()).contains("tester_runs"))
	await process_frame
	var counts: String = "%s / %s / %s" % [row().get_text(2), row().get_text(3), row().get_text(4)]
	check("the panel counts it", row().get_text(2) == "1" and row().get_text(3) == PlayMode.format_time(12.5)
		and row().get_text(4) == "850 u/s", counts)

	# --- it follows them
	tester.send({"t": "live", "attempt": 1, "p": [11, 20, 30], "speed": 700, "stage": 3, "state": "run"})
	var moved := await wait_for(func(): return row().get_text(1).contains("stage 3"), 3000)
	check("the panel follows them", moved, row().get_text(1))
	ed._redraw_overlays()
	await process_frame
	await process_frame
	check("the views draw live testers and their paths", ed.live_trails.size() == 1 and ed.show_tester_paths)

	# --- the invite: what the owner sends so someone else can join
	var invite: String = ed._playtest_invite()
	check("the invite carries the address, the code and the secret", invite.contains(ed.relay.session)
		and secret != "" and invite.contains(secret) and (invite.contains("ws://") or invite.contains("wss://")),
		"session %s, secret %d chars" % [ed.relay.session, secret.length()])
	ed._refresh_playtest()
	check("the panel shows the invite", ed._playtest_panel._invite.visible and ed._playtest_panel._invite.text == invite)
	var parsed_invite: Dictionary = ed.parse_invite(invite)
	check("the invite parses back into the address, the code and the secret",
		String(parsed_invite["url"]) == ed.relay.url and String(parsed_invite["code"]) == ed.relay.session
		and String(parsed_invite["secret"]) == secret, String(parsed_invite["code"]))
	var messy: Dictionary = ed.parse_invite("  here you go:\n MALLET co-editing - relay %s - session %s - secret %s\n" % [ed.relay.url, ed.relay.session, secret])
	check("an invite with a greeting and line breaks parses too", String(messy["secret"]) == secret
		and String(messy["code"]) == ed.relay.session, String(messy["code"]))
	check("text that is not an invite parses to nothing", String(ed.parse_invite("hello")["code"]) == ""
		and String(ed.parse_invite("")["secret"]) == "")

	# --- a second MALLET joins as a co-editor
	var co := Relay.new()
	root.add_child(co)
	co_got.clear()
	co.message.connect(_note_co)
	co.connect_to(URL, {"t": "hello", "v": 1, "role": "editor", "session": ed.relay.session, "secret": secret,
		"name": "Alex", "map": "playtest test", "map_version": 7, "client": MalletVersion.full()})
	check("a co-editor joins the session", await wait_for(func(): return co.is_open()))
	co.send({"t": "cursor", "pos": [5, 6, 7], "aim": [0, 0, -1], "sel": []})
	check("the maker sees where they are", await wait_for(func(): return ed.co_cursors.has(co.you)))
	var got: Dictionary = ed.co_cursors.get(co.you, {})
	check("their camera arrives as a place and an aim", _vec(got.get("pos", [])) == Vector3(5, 6, 7)
		and got.get("aim") is Array, str(got.get("pos", [])))
	check("our own camera goes out to them", await wait_for(func(): return not co_got.is_empty()))
	var ramp := RampNode.new()
	ed.ramps_root.add_child(ramp)
	ramp.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 24)])
	ramp.rebuild()
	ed._select(ramp)
	var wire: Array = ed._co_sel()
	check("our selection is sent as kind and place", wire.size() == 1 and String(wire[0][0]) == "ramp", str(wire))
	var mid: Vector3 = ramp.center()
	check("their selection finds the same object here", ed._co_object_at("ramp", mid) == ramp)
	ramp.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 30)])
	ramp.rebuild()
	ed._map_changed()
	check("our own change goes out as an edit", await wait_for(func(): return not co_edits.is_empty(), 4000))
	var sent_op: Dictionary = co_edits[0].get("op", {}) if not co_edits.is_empty() else {}
	check("an edit carries the object's new state", String(sent_op.get("kind", "")) == "ramp"
		and (sent_op.get("obj", {}) as Dictionary).has("points"), String(sent_op.get("kind", "")))
	# and an edit from them lands here without touching our undo history
	var op := {"kind": "ramp", "uid": ed._co_uid(ramp), "at": [mid.x, mid.y, mid.z], "obj": ed._with_group(ramp)}
	op["obj"]["points"] = [[0, 0, 4], [0, 0, 28]]
	var undo_before: int = ed._undo.size()
	co.send({"t": "edit", "seq": 1, "op": op})
	var moved_here := await wait_for(func(): return ramp.points.size() == 2 and ramp.points[0].is_equal_approx(Vector3(0, 0, 4)), 4000)
	check("a remote edit moves the ramp here", moved_here, str(ramp.points))
	check("it does not go into our undo history", ed._undo.size() == undo_before, "%d -> %d" % [undo_before, ed._undo.size()])
	co.send({"t": "cursor", "pos": [5, 6, 7], "aim": [0, 0, -1], "sel": [["ramp", mid.x, mid.y, mid.z]]})
	check("their selection arrives", await wait_for(func(): return not (ed.co_cursors.get(co.you, {}).get("sel", []) as Array).is_empty(), 3000))
	co.send({"t": "cursor", "pos": [5, 6, 7], "aim": [0, 0, -1], "sel": [], "mouse": [1, 2, 3], "doing": "dragging"})
	check("their mouse and what they are doing arrive", await wait_for(func(): return (ed.co_cursors.get(co.you, {}).get("mouse", []) as Array).size() == 3)
		and String(ed.co_cursors.get(co.you, {}).get("doing", "")) == "dragging")
	var cursor_has_doing := false
	for m in co_got:
		if String(m.get("t", "")) == "cursor" and (m as Dictionary).has("mouse") and (m as Dictionary).has("doing"):
			cursor_has_doing = true
	check("our mouse goes out with what we are doing", cursor_has_doing)
	ed._redraw_overlays()
	await process_frame
	await process_frame
	check("co-editors draw in the views", ed.show_co_editors and ed.co_cursors.size() == 1)
	# --- new objects and deletions
	var count_before: int = ed.ramps_root.get_child_count()
	var add_op := {"act": "add", "kind": "ramp", "uid": "zz1", "at": [0, 0, 60], "obj": ed._with_group(ramp).duplicate(true)}
	add_op["obj"]["points"] = [[0, 0, 60], [0, 0, 90]]
	var undo_before_add: int = ed._undo.size()
	co.send({"t": "edit", "seq": 2, "op": add_op})
	check("a ramp added on their side appears here", await wait_for(func(): return ed.ramps_root.get_child_count() == count_before + 1, 4000))
	var added: Node3D = ed._co_find_uid("ramp", "zz1")
	check("it keeps their id and their shape", added != null and added.points.size() == 2
		and added.points[1].is_equal_approx(Vector3(0, 0, 90)))
	check("adding does not go into our undo history", ed._undo.size() == undo_before_add)
	co.send({"t": "edit", "seq": 3, "op": {"act": "del", "kind": "ramp", "uid": "zz1"}})
	check("a deletion on their side removes it here", await wait_for(func(): return ed.ramps_root.get_child_count() == count_before, 4000))
	check("it cannot be found any more", ed._co_find_uid("ramp", "zz1") == null)
	var extra := RampNode.new()
	ed.ramps_root.add_child(extra)
	extra.points = PackedVector3Array([Vector3(0, 0, 120), Vector3(0, 0, 150)])
	extra.rebuild()
	var extra_uid: String = ed._co_uid(extra)
	ed._map_changed()
	check("our own new ramp goes out", await wait_for(func(): return _has_uid(co_edits, extra_uid, "add"), 4000))
	ed.ramps_root.remove_child(extra)
	extra.free()
	check("our own deletion goes out", await wait_for(func(): return _has_uid(co_edits, extra_uid, "del"), 4000))

	# --- undo lands in both copies
	co_edits.clear()
	var u_ramp := RampNode.new()
	ed.ramps_root.add_child(u_ramp)
	u_ramp.points = PackedVector3Array([Vector3(0, 0, 200), Vector3(0, 0, 220)])
	u_ramp.rebuild()
	ed._select(u_ramp)
	ed._map_changed()
	check("a ramp we add goes out first", await wait_for(func(): return _has_act(co_edits, "add"), 4000))
	var u_uid: String = ed._co_uid(u_ramp)
	ed._checkpoint()
	u_ramp.points = PackedVector3Array([Vector3(0, 0, 200), Vector3(0, 0, 260)])
	u_ramp.rebuild()
	ed._map_changed()
	check("our change to it goes out", await wait_for(func(): return _has_uid(co_edits, u_uid, "edit"), 4000))
	co_edits.clear()
	ed.undo()
	check("our undo goes out as the same object", await wait_for(func(): return _has_uid(co_edits, u_uid, "edit"), 4000))
	var undone := {}
	for m in co_edits:
		var uop = m.get("op", {})
		if uop is Dictionary and String(uop.get("uid", "")) == u_uid:
			undone = uop.get("obj", {})
	var undone_len := 0.0
	if undone.get("points") is Array and (undone["points"] as Array).size() >= 2:
		undone_len = float(((undone["points"] as Array)[1] as Array)[2])
	check("and with the shape from before the change", undone_len > 0.0 and undone_len < 240.0, str(undone.get("points", "")))

	# --- a rename in the outliner reaches them too
	var r2 := RampNode.new()
	ed.ramps_root.add_child(r2)
	r2.points = PackedVector3Array([Vector3(0, 0, 300), Vector3(0, 0, 320)])
	r2.rebuild()
	ed._select(null)
	ed._map_changed()
	await wait_ms(400)
	var r2_uid: String = ed._co_uid(r2)
	co_edits.clear()
	ed.outliner.rename({"object": r2}, "Their new name")
	var named := await wait_for(func(): return not co_edits.is_empty(), 4000)
	var name_sent := ""
	for m in co_edits:
		var nop = m.get("op", {})
		if nop is Dictionary and String(nop.get("uid", "")) == r2_uid:
			name_sent = String((nop.get("obj", {}) as Dictionary).get("name", ""))
	check("a rename in the outliner goes out", named and name_sent == "Their new name", name_sent)

	# --- the map's look (the Map panel) travels too
	co_edits.clear()
	ed.environment["aurora"] = 0.42
	ed._map_changed()
	var env_sent := await wait_for(func(): return _has_act(co_edits, "env"), 4000)
	var env_value := -1.0
	for m in co_edits:
		var eop = m.get("op", {})
		if eop is Dictionary and String(eop.get("act", "")) == "env":
			env_value = float((eop.get("environment", {}) as Dictionary).get("aurora", -1.0))
	check("a change to the map's look goes out", env_sent and absf(env_value - 0.42) < 0.001, str(env_value))
	co.send({"t": "edit", "seq": 90, "op": {"act": "env", "environment": {"aurora": 0.11}}})
	check("theirs is taken without an undo step", await wait_for(func(): return absf(float(ed.environment.get("aurora", -1.0)) - 0.11) < 0.001, 4000))

	# --- the map's owner can put someone out of the session
	var kickee := Relay.new()
	root.add_child(kickee)
	kickee.message.connect(_note_kick)
	kickee.connect_to(URL, {"t": "hello", "v": 1, "role": "editor", "session": ed.relay.session, "secret": secret,
		"name": "Rob", "map": "playtest test", "map_version": 7, "client": MalletVersion.full()})
	check("a third person joins", await wait_for(func(): return kickee.is_open()))
	await wait_ms(300)
	check("the owner is offered who to remove", ed._playtest_panel._remove.visible)
	co.send({"t": "kick", "id": kickee.you})          # (only the map's owner may remove anyone)
	await wait_ms(500)
	check("a co-editor cannot remove anyone", kickee.state != "closed")
	ed._remove_from_session(kickee.you)
	check("removing someone closes their connection", await wait_for(func(): return kickee.state == "closed", 5000))
	check("and tells them who did it", kicked_by == "Maker", kicked_by)
	check("the session carries on for us", await wait_for(func(): return ed.relay != null and ed.relay.is_open() and not ed.relay.peers.has(kickee.you), 3000))
	kickee.queue_free()

	# --- an editor joining after work started asks for the session's map
	co_states.clear()
	co.send({"t": "state_please"})
	var pieces := await wait_for(func(): return not co_states.is_empty() and co_states.size() == int(co_states[0].get("of", 0)), 5000)
	check("a newcomer can ask for the session's map", pieces, "%d part(s)" % co_states.size())
	var whole := ""
	var only_them := true
	for part in co_states:
		whole += String(part.get("map", ""))
		only_them = only_them and String(part.get("to", "")) == co.you
	check("it goes to the newcomer alone", pieces and only_them)
	var parsed = JSON.parse_string(whole) if pieces else null
	check("their map arrives whole", parsed is Dictionary and (parsed.get("ramps", []) as Array).size() == ed.ramps_root.get_child_count()
		and String(parsed.get("format", "")) == String(ed._map_dict().get("format", "")))

	co.close()
	check("leaving takes their cursor away", await wait_for(func(): return not ed.co_cursors.has(co.you), 3000))

	# --- a dropped connection gets back into the same session
	var code_now: String = ed.relay.session
	ed._reconnect_wait = 200
	ed._playtest_lost(1006, "test")
	check("a dropped connection is retried", ed._reconnect_at > 0)
	check("it comes back to the same session", await wait_for(func(): return ed.relay != null and ed.relay.is_open() and ed.relay.session == code_now, 9000))
	check("and the retries stop once it is back", ed._reconnect_at == 0 and not ed._rejoining,
		"%d / %s" % [ed._reconnect_at, str(ed._rejoining)])
	ed._select(null)                                      # (the undo above rebuilt the map: `ramp` is that old node)

	# --- and what a newcomer does with that map: load it whole, and send none of it back
	var probe := RampNode.new()
	ed.ramps_root.add_child(probe)
	probe.points = PackedVector3Array([Vector3(0, 0, 44), Vector3(0, 0, 48)])
	probe.rebuild()
	var theirs: Dictionary = ed._map_dict()
	theirs["ramps"] = [ed._with_group(probe)]
	theirs["entities"] = []
	theirs["blocks"] = []
	theirs["texts"] = []
	theirs["cube_models"] = []
	ed.ramps_root.remove_child(probe)
	probe.free()
	var map_text := JSON.stringify(theirs)
	var half := int(map_text.length() / 2.0)
	co_edits.clear()
	ed.session_role = "editor"                     # (what a newcomer is: only editors take the session's map)
	ed._co_state_chunk({"t": "state", "name": "Alex", "part": 0, "of": 2, "map": map_text.substr(0, half)})
	var early: bool = ed.ramps_root.get_child_count() == 1 and (ed.ramps_root.get_child(0) as RampNode).points[1].is_equal_approx(Vector3(0, 0, 48))
	check("half a map changes nothing", not early)
	ed._co_state_chunk({"t": "state", "name": "Alex", "part": 1, "of": 2, "map": map_text.substr(half)})
	var landed: bool = ed.ramps_root.get_child_count() == 1 and (ed.ramps_root.get_child(0) as RampNode).points[1].is_equal_approx(Vector3(0, 0, 48))
	check("their map replaces ours, whole", landed, "%d ramp(s)" % ed.ramps_root.get_child_count())
	check("loading their map is not an undo step", ed._undo.is_empty())
	ed.session_role = "maker"
	await wait_ms(700)
	check("none of it goes back out as new", not _has_act(co_edits, "add"))

	# --- a test build made now carries the session
	var dir: String = String(out) + "/build"
	DirAccess.make_dir_recursive_absolute(dir)
	var cf := ConfigFile.new()
	cf.set_value("test", "map_name", "playtest test")
	cf.set_value("test", "version", 2)
	cf.set_value("relay", "url", URL)
	cf.set_value("relay", "session", ed.relay.session)
	cf.set_value("relay", "secret", secret)
	check("the tester.cfg writes", cf.save(dir.path_join(Tester.CONFIG)) == OK)
	var cfg := Tester.config(dir)
	check("a test build reads the session back", cfg["relay"] == URL and cfg["session"] == ed.relay.session
		and cfg["secret"] == secret, "%s / %s" % [cfg["relay"], cfg["session"]])

	# --- and the build itself carries it
	var fake := String(out) + "/fake"
	DirAccess.make_dir_recursive_absolute(fake)
	for p in [fake + "/MALLET.exe", fake + "/MALLET.pck"]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer("x".to_utf8_buffer())
		f.close()
	var made: Dictionary = Tester.make_build({}, "session test", 1, fake + "/MALLET.exe", String(out) + "/builds",
		{"url": URL, "session": ed.relay.session, "secret": secret})
	check("a test build is made", made.get("error", "x") == "" and FileAccess.file_exists(String(made.get("zip", ""))), String(made.get("error", "")))
	var text := ""
	var zr := ZIPReader.new()
	if zr.open(String(made.get("zip", ""))) == OK:
		for f in zr.get_files():
			if f.ends_with("tester.cfg"):
				text = zr.read_file(f).get_string_from_utf8()
		zr.close()
	check("the build's tester.cfg carries the session", text.contains(ed.relay.session) and text.contains(URL))

	# --- leaving keeps what came in
	ed._leave_playtest()
	await wait_ms(200)
	check("leaving closes the connection", ed.relay == null)
	check("the runs stay after leaving", ed.tester_runs.size() == 1 and ed.tester_runs[0]["attempts"].size() == 1)

	tester.close()
	if relay_pid > 0:
		OS.kill(relay_pid)
	print("PLAYTEST: ", "PASS" if ok else "FAIL")
	quit()
