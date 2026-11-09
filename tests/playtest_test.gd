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
	await process_frame
	var where: String = row().get_text(1)
	check("the panel shows where they are", where.contains("stage 2") and where.contains("640"), where)

	# --- their runs
	var attempt := {"outcome": "finish", "time": 12.5, "started": 1000.0, "splits": [[2, 5.0]], "deaths": [],
		"route": [[0.0, 0.0, 0.0, 500]], "top_speed": 900, "finish_speed": 850}
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
