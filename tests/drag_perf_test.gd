extends SceneTree
## Dragging any object must stay smooth (the user's #3: cube objects and ramps dragged at a low frame rate while
## platforms were smooth). Drags each kind of object with mouse moves on a busy map and times each move + frame.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/drag_perf_test.gd -- <out folder>

var ed
var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # (time the work, not the screen's refresh)
	Engine.max_fps = 0
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed.snap_enabled = false
	ed.show_all_arcs = true
	var ramps := []
	for i in 6:
		ramps.append(ed._make_ramp(Vector3(-60, 80 - i * 10, i * 40), Vector3(60, 60 - i * 10, i * 40)))
	ed._add_entity("start")
	ed._add_entity("finish")
	var plate: Node3D = ed.entities_root.get_child(0)
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.begin()
	cm.world.set_cell(Vector3i(0, -64, 0), 3, CubeWorld.FULL, CubeWorld.blank_tex())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 60:                                          # bumpy 0.125 m details: a few thousand cubes
		var o := Vector3i(rng.randi_range(0, 50), -1, rng.randi_range(0, 50))
		cm.world.pull_n({"o": o, "s": Vector3i(rng.randi_range(2, 13), 1, rng.randi_range(2, 13)), "p": -3, "orient": 3}, rng.randi_range(1, 3), "")
	cm.world.commit()
	cm.position = Vector3(0, 0, -120)
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [80, 10, -80], "size": [16, 8, 16]})
	await process_frame
	await process_frame
	print("  cube object: %d cubes" % cm.world.count())
	var pane: ViewPane = ed.panes[0]
	var t_idle := Time.get_ticks_usec()
	for i in 20:
		await process_frame
	var idle := (Time.get_ticks_usec() - t_idle) / 20000.0
	print("  idle frame (4 views drawn): %.1f ms" % idle)
	for item in [["start platform", plate], ["ramp", ramps[2]], ["cube object", cm], ["block", b]]:
		var o: Node3D = item[1]
		ed._select(o)
		await process_frame
		var c := pane.camera.unproject_position(ed._move_handle_point(o))
		ed._begin_drag(pane, ed.Drag.OBJECT, c, false)
		var worst := 0.0
		var total := 0.0
		var n := 30
		for i in n:
			var t0 := Time.get_ticks_usec()
			ed._drag_to(c + Vector2(i * 3.0, i * 1.5), false)
			await process_frame
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if i > 2:
				worst = maxf(worst, ms)
				total += ms
		ed._end_drag()
		await process_frame
		var avg := total / (n - 3)
		print("  %-16s avg %.1f ms per mouse move + frame, worst %.1f ms" % [item[0], avg, worst])
		check("dragging a %s costs under 5 ms a move more than an idle frame" % item[0], avg - idle < 5.0, "(%.1f ms)" % avg)
		if o is RampNode:
			check("the dragged ramp is rebuilt in place when let go", o.position == Vector3.ZERO and o.ridge[0].distance_to(o.points[0]) < 30.0)
	print("DRAG PERF: ", "PASS" if ok else "FAIL")
	quit()
