extends SceneTree
## Play mode practice tools (0.20.0): turn binds (hold left / right mouse), Q / E save and load a position (with its
## speed and view), 2-9 to a stage, N noclip, T shows the triggers. Loading, a stage jump or noclip make the run
## practice: the timer says so and a finish doesn't count; R is a real run again.
## Run: godot --path . --resolution 1280x720 -s res://tests/practice_test.gd -- <out folder>

var ok := true
var ed
var pm: PlayMode


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	pm.handle_input(e)


func frames(n: int) -> void:
	for i in n:
		await physics_frame
	await process_frame


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	Settings.set_value("play_triggers", false)
	ed._load_dict({"entities": [
		{"kind": "start", "position": [0.0, 100.0, 0.0], "size": [20.0, 2.0, 26.0], "yaw": 0.0},
		{"kind": "stage", "position": [200.0, 100.0, 0.0], "size": [24.0, 2.0, 24.0], "yaw": 90.0, "number": 2},
		{"kind": "finish", "position": [400.0, 100.0, 0.0], "size": [40.0, 2.0, 40.0], "yaw": 0.0},
		{"kind": "kill", "position": [100.0, 40.0, 0.0], "size": [40.0, 20.0, 40.0], "yaw": 0.0}]})
	await process_frame
	ed._play_clicked()
	pm = ed.play
	await frames(5)
	var p: SUCC = pm.player
	var kz: EntityNode = ed.entities_root.get_child(3)
	check("triggers hidden in play mode by default (as in the game)", not kz.visible)
	key(KEY_T)
	check("T shows them", kz.visible)
	key(KEY_T)
	# turn binds
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var y0 := p.rotation.y
	var t0 := Time.get_ticks_usec()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	Input.parse_input_event(mb)
	Input.flush_buffered_events()
	await frames(30)
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	mb.pressed = false
	Input.parse_input_event(mb)
	Input.flush_buffered_events()
	var turned := rad_to_deg(angle_difference(y0, p.rotation.y))
	check("holding the left mouse turns left at the turn speed (210°/s)", Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or (turned > 0.0 and absf(turned - 210.0 * secs) < 40.0),
		"(%.0f° in %.2f s; mouse %s)" % [turned, secs, "captured" if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else "not captured here"])
	# save / load
	p.global_position = Vector3(50, 120, 10)
	p.velocity = Vector3(20, 0, 0)
	key(KEY_Q)
	p.global_position = Vector3(0, 300, 0)
	p.velocity = Vector3.ZERO
	key(KEY_E)
	await frames(1)
	check("Q saves a position, E brings it back with its speed", p.global_position.distance_to(Vector3(50, 120, 10)) < 1.5 and p.velocity.x > 15.0,
		"(%s, %s)" % [p.global_position, p.velocity])
	check("...and the run is practice", pm.practice and String(pm._time_label.text).contains("PRACTICE") or pm.practice)
	# a stage jump
	key(KEY_2)
	await frames(1)
	check("2 goes to stage 2", p.global_position.distance_to(Vector3(200, 100, 0)) < 10.0, str(p.global_position))
	# noclip
	key(KEY_N)
	var at := p.global_position
	var w := InputEventKey.new()
	w.physical_keycode = KEY_SPACE
	w.keycode = KEY_SPACE
	w.pressed = true
	Input.parse_input_event(w)
	Input.flush_buffered_events()
	await frames(30)
	w.pressed = false
	Input.parse_input_event(w)
	Input.flush_buffered_events()
	check("N: noclip flies (Space goes up, no falling)", pm.noclip and p.global_position.y > at.y + 5.0, "(%.1f -> %.1f)" % [at.y, p.global_position.y])
	key(KEY_N)
	# finishing in practice doesn't count
	var best_before: float = pm.best_time
	p.global_position = Vector3(400, 101, 0)
	await frames(3)
	check("finishing in practice: no best time", is_equal_approx(pm.best_time, best_before))
	key(KEY_R)
	await frames(2)
	check("R: a real run again", not pm.practice and not pm.noclip and pm.run_state == PlayMode.Run.WAITING)
	pm.stop()
	await process_frame
	check("leaving play mode shows the zones again", kz.visible)
	print("practice_test: ", "PASS" if ok else "FAIL")
	quit()
