extends SceneTree
## 0.9.0 fixes from the user's list (docs/PLAN_0.9.md): one section per item, added slice by slice.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/fixes09_test.gd -- <out folder>

var ed
var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func key(k: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	ed._unhandled_input(e)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await frames(2)
	ed.welcome.hide()
	ed._load_dict({})
	ed.snap_enabled = false
	var persp: ViewPane = ed.panes[0]
	var top: ViewPane = null
	for p in ed.panes:
		if p.is_ortho():
			top = p
			break

	# ---- #14: D while flying (right mouse held) doesn't toggle draw blocks; E doesn't open build mode
	(persp.camera as OrbitCamera)._orbiting = true
	key(KEY_D)
	key(KEY_E)
	check("#14 D and E while flying do nothing but fly", not ed._draw_mode and not ed.build.active)
	(persp.camera as OrbitCamera)._orbiting = false
	root.warp_mouse(persp.get_global_rect().get_center())
	await frames(1)
	key(KEY_D)
	check("#14 D over the perspective view doesn't toggle draw blocks", not ed._draw_mode)
	root.warp_mouse(top.get_global_rect().get_center())
	await frames(1)
	key(KEY_D)
	check("#14 D over a 2D view does", ed._draw_mode)
	key(KEY_ESCAPE)

	# ---- #1: F in the Outliner focuses the selection
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [300, 20, -500], "size": [16, 8, 16]})
	ed.outliner.refresh()
	ed._select(b)
	await frames(1)
	var e := InputEventKey.new()
	e.keycode = KEY_F
	e.pressed = true
	ed.outliner.tree.gui_input.emit(e)
	var f: Vector3 = (persp.camera as OrbitCamera).focus
	check("#1 F in the Outliner focuses the selected object", f.distance_to(b.center()) < 1.0, "(focus %s)" % f)

	# ---- #15: unsaved changes
	ed._load_dict({})
	ed.current_path = ""
	ed._mark_saved()
	check("#15 an empty never-saved map has nothing to lose", not ed.has_unsaved_changes())
	ed._make_ramp(Vector3(-40, 60, 0), Vector3(40, 40, 0))
	check("#15 a never-saved map with a ramp asks before closing", ed.has_unsaved_changes())
	ed.save_map(out + "/unsaved.sfmap")
	check("#15 after saving nothing is lost", not ed.has_unsaved_changes())
	(ed.ramps_root.get_child(0) as RampNode).translate_by(Vector3(5, 0, 0))
	check("#15 moving the ramp after saving counts as a change", ed.has_unsaved_changes())
	ed.load_map(out + "/unsaved.sfmap")
	check("#15 opening the map again: no changes", not ed.has_unsaved_changes())

	# ---- #5: ground grid on / off (remembered)
	var was: bool = ed._ground_grid.visible
	ed._toggle_ground_grid()
	check("#5 View > Ground grid hides / shows the 3D grid", ed._ground_grid.visible != was and bool(Settings.value("ground_grid")) == ed._ground_grid.visible)
	ed._toggle_ground_grid()

	# ---- #6: right mouse + wheel = fly speed; the wheel alone still zooms
	var cam: OrbitCamera = persp.camera
	var sp0 := cam.fly_speed
	var d0 := cam.distance
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	cam._orbiting = true
	cam.handle_input(w)
	cam.handle_input(w)
	check("#6 right mouse + wheel up: faster flying, no zoom", cam.fly_speed > sp0 * 1.3 and cam.distance == d0, "(%.0f -> %.0f m/s)" % [sp0, cam.fly_speed])
	w.button_index = MOUSE_BUTTON_WHEEL_DOWN
	cam.handle_input(w)
	cam.handle_input(w)
	check("#6 and down again: back to the old speed", absf(cam.fly_speed - sp0) < 0.01)
	cam._orbiting = false
	cam.handle_input(w)
	check("#6 the wheel alone still zooms", cam.distance > d0 and absf(cam.fly_speed - sp0) < 0.01)

	# ---- #4: clear the best run
	ed._select(null)
	ed.best_ghost = {"time": 12.5, "hz": 20.0, "samples": [0.0, 0.0, 0.0, 10.0]}
	ed._refresh_info()
	check("#4 a 'Clear best run' button shows when there is one", ed._fields["clear_best"].visible)
	ed.clear_best_run()
	check("#4 clearing forgets it (and hides the button)", ed.best_ghost.is_empty() and not ed._fields["clear_best"].visible)

	print("FIXES 0.9: ", "PASS" if ok else "FAIL")
	quit()
