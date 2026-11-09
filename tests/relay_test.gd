extends SceneTree
## The relay (docs/RELAY.md), both ends: it starts relay/relay.py, a maker opens a session, a tester with the wrong
## secret is refused, the right one joins and is announced, live positions and a finished attempt reach the maker,
## collect hands back the stored run, an oversized message disconnects only its sender, and the server answers
## /health. Nothing here needs a window (headless is fine).
## Run: godot --headless --path D:/SurfForge -s res://tests/relay_test.gd -- <out>

const PORT := 8799
const URL := "ws://127.0.0.1:8799/ws"

var ok := true
var relay_pid := -1


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


func wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _client(name: String, role: String, session := "", secret := "") -> Relay:
	var r := Relay.new()
	root.add_child(r)
	r.connect_to(URL, {"t": "hello", "v": 1, "role": role, "session": session, "secret": secret, "name": name,
		"map": "relay test", "map_version": 3, "client": MalletVersion.full()})
	return r


func _run() -> void:
	var log_path := OS.get_environment("TEMP").path_join("relay_test.log")
	DirAccess.remove_absolute(log_path)
	relay_pid = OS.create_process("python", ["relay/relay.py", "--port", str(PORT), "--quiet", "--log", log_path])
	check("the relay starts", relay_pid > 0, "pid %d" % relay_pid)
	await wait_ms(1200)

	# --- a maker opens a session
	var maker := _client("Maker", "maker")
	var took := [{}]
	maker.opened.connect(func(w): took[0] = w)
	var made := await wait_for(func(): return maker.is_open())
	check("the maker opens a session", made and maker.session.length() >= 4 and maker.secret != "",
		"%s / secret %d chars" % [maker.session, maker.secret.length()])
	check("the relay reports no peers yet", (took[0].get("peers", []) as Array).is_empty())

	# --- a wrong secret is refused
	var refused := [{}]
	var bad := _client("Mallory", "tester", maker.session, "not-the-secret")
	bad.failed.connect(func(c, m): refused[0] = {"code": c, "message": m})
	var was_refused := await wait_for(func(): return bad.state == "closed")
	check("a wrong secret is refused", was_refused and refused[0].get("code", "") == "bad_secret",
		String(refused[0].get("code", "")))
	bad.queue_free()

	# --- the right one joins, and the maker is told
	var tester := _client("Sam", "tester", maker.session, maker.secret)
	var joined := await wait_for(func(): return tester.is_open())
	check("the tester joins with the session's secret", joined)
	var seen := await wait_for(func(): return maker.peers.has(tester.you))
	check("the maker sees the tester arrive", seen, String(maker.peers.get(tester.you, {}).get("name", "")))

	# --- live positions reach the maker
	var live := [{}]
	maker.message.connect(func(m): if m.get("t") == "live": live[0] = m)
	tester.send({"t": "live", "attempt": 2, "p": [128.5, 96.0, -32.25], "speed": 683, "stage": 2, "state": "run"})
	var got_live := await wait_for(func(): return not live[0].is_empty())
	check("a live position reaches the maker", got_live and live[0].get("name") == "Sam" and live[0].get("speed") == 683,
		str(live[0].get("p", [])))

	# --- a finished attempt reaches the maker and is kept
	var got := []
	maker.message.connect(func(m): if m.get("t") == "attempt": got.append(m))
	tester.send({"t": "attempt", "attempt": {"outcome": "finish", "time": 24.517, "started": 1762600000.0,
		"splits": [[2, 9.2]], "deaths": [[1.0, 2.0, 3.0]], "route": [[0.0, 1.0, 2.0, 700]],
		"top_speed": 1180, "finish_speed": 902}})
	var got_attempt := await wait_for(func(): return got.size() == 1)
	check("a finished attempt reaches the maker", got_attempt and got[0]["attempt"]["time"] == 24.517)

	# --- the maker collects what the relay is holding (for runs made while MALLET was closed)
	var collected := [{}]
	maker.message.connect(func(m): if m.get("t") == "runs": collected[0] = m)
	maker.send({"t": "collect"})
	var got_runs := await wait_for(func(): return not collected[0].is_empty())
	var runs: Array = collected[0].get("runs", [])
	check("collect returns the stored run", got_runs and runs.size() == 1 and runs[0]["tester"] == "Sam"
		and runs[0]["attempt"]["outcome"] == "finish", "%d run(s)" % runs.size())

	# --- nonsense is refused without taking the session down
	var before := maker.peers.size()
	tester.send({"t": "live", "p": "not a position", "speed": "fast"})
	tester.send({"t": "nonsense"})
	await wait_ms(300)
	check("bad messages are ignored", maker.peers.size() == before and tester.is_open(),
		"%d peer(s) (was %d), tester %s" % [maker.peers.size(), before, tester.state])
	check("traffic keeps flowing after them", await wait_for(func(): return true))

	# --- an oversized message closes only that sender
	var dropped := [false]
	tester.closed.connect(func(_c, _r): dropped[0] = true)
	tester.send({"t": "live", "attempt": 1, "p": [0, 0, 0], "speed": 1, "stage": 1, "state": "run",
		"pad": "x".repeat(5 << 20)})
	var gone := await wait_for(func(): return dropped[0], 8000)
	check("an oversized message disconnects the sender", gone)
	check("the maker is told when they leave", await wait_for(func(): return not maker.peers.has(tester.you)))
	check("the maker's own connection is still up", maker.is_open())

	maker.close()
	await wait_ms(200)
	if relay_pid > 0:
		OS.kill(relay_pid)
	print("RELAY: ", "PASS" if ok else "FAIL")
	quit()
