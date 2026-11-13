extends SceneTree
## Test builds (0.15): the zip (MALLET renamed, the map, tester.cfg, only the used materials, READ ME), tester mode
## (map loaded, editor hidden, straight into play), every attempt written to the runs file (restart / finish / quit
## with time, deaths, route), the pause menu, and importing runs (checked, summarized, kept with the map).
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/tester_test.gd -- <out folder>

var ok := true
const BUILT_EXE := "D:/SurfForge_builds/MALLET/MALLET.exe"


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var map := {"format": "mallet-map", "version": 2, "environment": Look.default_environment(), "props": [], "texts": [],
		"blocks": [{"position": [0, 0, 0], "size": [20, 2, 20], "material": "Bricks104"}],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 60], "size": [20, 2, 20], "yaw": 0.0}], "ramps": []}

	# ---- the zip
	var res := Tester.make_build(map, "tester_map", 3, BUILT_EXE, out.path_join("builds"))
	check("a test build zip is made from MALLET.exe", res["error"] == "" and FileAccess.file_exists(res["zip"]), str(res))
	var zr := ZIPReader.new()
	zr.open(res["zip"])
	var files := zr.get_files()
	var top := "tester_map test v3/"
	check("...with the renamed program, the map, tester.cfg and a READ ME", files.has(top + "Play tester_map.exe")
		and files.has(top + "Play tester_map.pck") and files.has(top + "map.mallet") and files.has(top + "tester.cfg")
		and files.has(top + "READ ME FIRST.txt"))
	check("...and only the materials the map uses", res["materials"] == 1 and files.has(top + "materials/library.json")
		and Array(files).filter(func(f): return f.begins_with(top + "materials/") and f.ends_with("library.json") == false).all(func(f): return f.contains("Bricks104")))
	var cfg_text := zr.read_file(top + "tester.cfg").get_string_from_utf8()
	check("...the map's version is stamped in", cfg_text.contains("version=3"))
	check("from the development Godot it says to use the MALLET program", Tester.make_build(map, "x", 1, OS.get_executable_path(), out)["error"] != "")
	# unzip the map + config into a tester folder (not the 100 MB program)
	var dir := out.path_join("tester_folder")
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["map.mallet", "tester.cfg"]:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_buffer(zr.read_file(top + f))
		fa.close()
	zr.close()
	DirAccess.remove_absolute(dir.path_join("tester_profile.cfg"))
	if DirAccess.dir_exists_absolute(dir.path_join(Tester.RUNS_DIR)):
		for f in DirAccess.get_files_at(dir.path_join(Tester.RUNS_DIR)):
			DirAccess.remove_absolute(dir.path_join(Tester.RUNS_DIR).path_join(f))

	# ---- tester mode
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._start_tester(dir)
	await process_frame
	check("tester mode: the map is loaded, the editor hidden", ed.entities_root.get_child_count() == 2 and not ed._ui.visible)
	check("...first it asks for a name and consent (not playing yet)", ed._fields.has("tester_name") and not ed.play.active)
	ed._fields["tester_name"].text = "Sam"
	var dlg: ConfirmationDialog = ed._fields["tester_name"].get_parent().get_parent()
	dlg.confirmed.emit()
	await process_frame
	check("...then straight into play mode, and the name is remembered", ed.play.active and Tester.tester_name(dir) == "Sam")
	var play: PlayMode = ed.play
	play.run_state = PlayMode.Run.RUNNING
	play.run_time = 4.2
	play._to_checkpoint()                                # a fall
	play.run_state = PlayMode.Run.RUNNING
	play.run_time = 6.0
	play.respawn()                                       # R: a restart
	play.run_state = PlayMode.Run.RUNNING
	play.run_time = 9.5
	play.finish_speed = 1234.0
	play._end_attempt("finish")
	play.run_state = PlayMode.Run.FINISHED
	play.respawn()                                       # (after a finish R starts a new run: not another attempt)
	play.run_state = PlayMode.Run.RUNNING
	play.run_time = 2.0
	play.stop()                                          # Esc mid-run: a quit, and the pause menu
	await process_frame
	var runs := Tester.read_runs(ed.tester["file"])
	var outs: Array = runs.get("attempts", []).map(func(a): return a["outcome"])
	check("every attempt is in the runs file: fall, restart, finish, quit", outs == ["restart", "restart", "finish", "quit"], str(outs))
	check("...with the fall, the finish time and speed, and the tester's name", runs["attempts"][0]["deaths"].size() == 1
		and is_equal_approx(runs["attempts"][2]["time"], 9.5) and runs["attempts"][2]["finish_speed"] == 1234.0
		and runs["tester"] == "Sam" and runs["map_version"] == 3)
	check("Esc shows the pause menu, not the editor", not ed._ui.visible and not ed.play.active)
	ed.queue_free()
	await process_frame

	# ---- importing runs
	var ed2 = load("res://editor/main.tscn").instantiate()
	root.add_child(ed2)
	await process_frame
	ed2.welcome.hide()
	ed2._load_dict(map)
	var junk := out.path_join("junk.json")
	var jf := FileAccess.open(junk, FileAccess.WRITE)
	jf.store_string("{\"hello\": 1}")
	jf.close()
	var n: int = ed2.import_runs(PackedStringArray([runs_path(dir), junk]))
	check("importing a runs file adds it, a stray file is skipped", n == 1 and ed2.tester_runs.size() == 1)
	check("...importing the same file again adds nothing", ed2.import_runs(PackedStringArray([runs_path(dir)])) == 0)
	check("...the summary counts testers, attempts, finishes and falls", Tester.summary(ed2.tester_runs).begins_with("1 tester(s), 4 attempt(s), 1 finished, 1 fall"),
		Tester.summary(ed2.tester_runs))
	var made := [{"tester": "Ana", "attempts": [
		{"outcome": "finish", "splits": [[2, 10.0], [3, 21.5]], "deaths": []},
		{"outcome": "fall", "splits": [[2, 9.0]], "deaths": []},
		{"outcome": "quit", "splits": [], "deaths": []}]},
		{"tester": "Bo", "attempts": [{"outcome": "fall", "splits": [[2, 8.5]], "deaths": []}]}]
	var rep := Tester.stage_report(made)
	check("stage report: each stage's reach and best split, and where unfinished runs ended",
		rep.contains("Stage 2: reached in 3 of 4 attempt(s), best split") and rep.contains("by Bo")
		and rep.contains("Stage 3: reached in 1 of 4") and rep.contains("1 before stage 2, 2 on stage 2"), rep)
	var md: Dictionary = ed2._map_dict()
	ed2._load_dict(JSON.parse_string(JSON.stringify(md)))
	check("imported runs are saved with the map", ed2.tester_runs.size() == 1 and ed2.tester_runs[0]["tester"] == "Sam")
	ed2.queue_free()
	await process_frame
	print("tester_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func runs_path(dir: String) -> String:
	var d := dir.path_join(Tester.RUNS_DIR)
	return d.path_join(DirAccess.get_files_at(d)[0])
