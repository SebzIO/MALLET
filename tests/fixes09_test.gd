extends SceneTree
## 0.9.0 fixes: one section per item, added slice by slice.
## Run: godot --path . --resolution 1600x900 -s res://tests/fixes09_test.gd -- <out folder>

var ed
var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func key(k: int, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
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

	# ---- #14: Shift+O (draw blocks, D until 0.19.5) while flying (right mouse held) does nothing; E doesn't open build mode
	(persp.camera as OrbitCamera)._orbiting = true
	key(KEY_O, false, true)
	key(KEY_E)
	check("#14 Shift+O and E while flying do nothing but fly", not ed._draw_mode and not ed.build.active)
	(persp.camera as OrbitCamera)._orbiting = false
	root.warp_mouse(persp.get_global_rect().get_center())
	await frames(1)
	key(KEY_O, false, true)
	check("#14 Shift+O over the perspective view doesn't toggle draw blocks", not ed._draw_mode)
	root.warp_mouse(top.get_global_rect().get_center())
	await frames(1)
	key(KEY_D)
	check("D does nothing now (it's for flying)", not ed._draw_mode)
	key(KEY_O, false, true)
	check("#14 Shift+O over a 2D view does", ed._draw_mode)
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
	ed.save_map(out + "/unsaved.mallet")
	check("#15 after saving nothing is lost", not ed.has_unsaved_changes())
	(ed.ramps_root.get_child(0) as RampNode).translate_by(Vector3(5, 0, 0))
	check("#15 moving the ramp after saving counts as a change", ed.has_unsaved_changes())
	ed.load_map(out + "/unsaved.mallet")
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

	# ---- #11: inside a block in build mode, aim at the side you're looking out through
	ed._load_dict({})
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.set_cell(Vector3i(0, 0, 0), 2, CubeWorld.FULL, CubeWorld.blank_tex())   # a 4 m block (32 ticks)
	await frames(2)
	var bm = ed.build
	var found: Dictionary = bm._first_occupied(cm, Vector3(1.0, 1.5, 2.0), Vector3(1, 0, 0), 600.0, 0)
	check("#11 from inside, aim at the face you look out through (+x side)", not found.is_empty()
		and found["cell"] == Vector3i(24, 8, 16) and found["orient"] == 1, "(%s)" % found)
	found = bm._first_occupied(cm, Vector3(1.0, 1.5, 2.0), Vector3(0, -1, 0), 600.0, 0)
	check("#11 looking down from inside: the bottom face", not found.is_empty() and found["cell"] == Vector3i(8, 0, 16) and found["orient"] == 2, "(%s)" % found)
	found = bm._first_occupied(cm, Vector3(1.0, 1.5, 9.0), Vector3(0, 0, -1), 600.0, 0)
	check("#11 from outside it's still the face you look into", not found.is_empty() and found["cell"] == Vector3i(8, 8, 24) and found["orient"] == 5, "(%s)" % found)

	# ---- #12: the aimed face is drawn where the cube's face really is (pushed down half way)
	var half := CubeWorld.FULL.duplicate()
	for n in [2, 3, 6, 7]:                                # the top corners down to 4 of 8
		half[n * 3 + 1] = 4
	cm.world.set_cell(Vector3i(0, 32, 0), 0, half, CubeWorld.blank_tex())
	var ts := CubeWorld.make_sel(Vector3i(0, 32, 0), 0, 3)
	ts["model"] = cm
	bm._im.clear_surfaces()
	bm._im.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew: bool = bm._true_face(cm.global_transform, ts, Color.YELLOW)
	bm._line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)
	bm._im.surface_end()
	var ys := []
	for v in (bm._im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if v != Vector3.ZERO:
			ys.append(snappedf(v.y, 0.01))
	check("#12 the yellow outline sits on the real (pushed-down) top", drew and not ys.is_empty() and ys.max() < 4.6 and ys.min() > 4.4,
		"(heights %s; the cell's top would be 5.0)" % [ys.slice(0, 4)])

	# ---- #8: a face covered by smaller cubes isn't drawn (inside solid it was)
	var cw := CubeWorld.new()
	cw.set_cell(Vector3i(0, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())          # a 1 m cube
	for y in [0, 4]:                                                                  # four 0.5 m cubes against its +x side
		for z in [0, 4]:
			cw.set_cell(Vector3i(8, y, z), -1, CubeWorld.FULL, CubeWorld.blank_tex())
	var big := Vector4i(0, 0, 0, 0)
	check("#8 a big cube's side covered by small cubes is hidden", cw._face_hidden(big, CubeWorld.FULL, 1))
	cw.set_cell(Vector3i(8, 4, 4), -2, CubeWorld.FULL, CubeWorld.blank_tex())        # one small cube gets a smaller piece
	cw._clear_cell(Vector3i(8, 4, 4), -1)
	cw.set_cell(Vector3i(8, 4, 4), -2, CubeWorld.FULL, CubeWorld.blank_tex())
	check("#8 one corner only part covered: the side shows", not cw._face_hidden(big, CubeWorld.FULL, 1))
	var cw2 := CubeWorld.new()
	cw2.set_cell(Vector3i(0, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	for y in [0, 4]:
		for z in [0, 4]:
			cw2.set_cell(Vector3i(8, y, z), -1, CubeWorld.FULL, CubeWorld.blank_tex())
	var area := 0.0
	var v := PackedVector3Array()
	for ck in cw2.render_chunks():                       # (the 1 m cube and the 0.5 m ones are in different chunks)
		v.append_array(cw2.chunk_mesh(ck, true)[1])
	for i in range(0, v.size(), 3):
		area += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
	check("#8 the 1 m cube + 0.5 m slab draws only its outside (a 1.5 x 1 x 1 box: 8 m2)", absf(area - 8.0) < 0.01,
		"(%.2f m2 drawn)" % area)

	# ---- 0.9.1: right / middle drag captures the mouse (no running into the screen edge) and gives it back after
	ed._load_dict({})
	for pane in [persp, top]:
		var start: Vector2 = pane.get_global_rect().get_center()
		root.warp_mouse(start)
		await frames(1)
		var dn := InputEventMouseButton.new()
		dn.button_index = MOUSE_BUTTON_RIGHT
		dn.pressed = true
		dn.position = pane.get_local_mouse_position()
		pane._gui_input(dn)
		var was_yaw: float = (pane.camera as OrbitCamera).yaw if pane == persp else 0.0
		var was_c: Vector3 = pane._ortho_center
		check("grab: right mouse in the %s view hides and holds the cursor" % ("3D" if pane == persp else "Top"),
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and pane.is_grabbing())
		for i in 40:                                        # far more than the screen is wide
			var mv := InputEventMouseMotion.new()
			mv.relative = Vector2(120, 0)
			Input.parse_input_event(mv)
			Input.flush_buffered_events()
		var turned: bool = absf((pane.camera as OrbitCamera).yaw - was_yaw) > 1.0 if pane == persp else pane._ortho_center.distance_to(was_c) > 1.0
		check("grab: moving it keeps turning / panning (no edge to stop it)", turned)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_RIGHT
		up.pressed = false
		Input.parse_input_event(up)
		Input.flush_buffered_events()
		await frames(1)
		check("grab: letting go shows the cursor again, where the drag started", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
			and not pane.is_grabbing() and root.get_mouse_position().distance_to(start) < 2.0
			and (pane != persp or not (persp.camera as OrbitCamera).flying()), "(at %s)" % root.get_mouse_position())

	# ---- 0.9.2: real key presses while flying (they used to reach the menus' shortcuts, which skipped the check)
	ed._load_dict({})
	if ed._draw_mode:
		ed._toggle_draw_mode()
	(persp.camera as OrbitCamera)._orbiting = true
	for k in [KEY_D, KEY_E, KEY_N, KEY_B, KEY_O]:
		var ke := InputEventKey.new()
		ke.keycode = k
		ke.physical_keycode = k
		ke.pressed = true
		Input.parse_input_event(ke)
		Input.flush_buffered_events()
		var ku := ke.duplicate()
		ku.pressed = false
		Input.parse_input_event(ku)
		Input.flush_buffered_events()
	await frames(1)
	(persp.camera as OrbitCamera)._orbiting = false
	check("flying: real D / E / N / B / O presses do nothing but fly", not ed._draw_mode and not ed.build.active
		and ed._all_objects().is_empty(), "(draw %s, build %s, %d objects)" % [ed._draw_mode, ed.build.active, ed._all_objects().size()])
	var kn := InputEventKey.new()
	kn.keycode = KEY_N
	kn.physical_keycode = KEY_N
	kn.pressed = true
	Input.parse_input_event(kn)
	Input.flush_buffered_events()
	await frames(1)
	check("not flying: a real N press still adds a ramp (once)", ed.ramps_root.get_child_count() == 1, "(%d ramps)" % ed.ramps_root.get_child_count())

	print("FIXES 0.9: ", "PASS" if ok else "FAIL")
	quit()
