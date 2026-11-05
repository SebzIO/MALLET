extends SceneTree
## Build mode, driven like a player: E into first person, wheel cubes out of thin air and out of faces, F / Q + wheel
## slopes, G + wheel grid, Y + wheel textures, select / copy / paste, undo, E back to the editor; then save / load,
## play on the cubes, both exports and a CS:S compile. Screenshots: build_fp.png (first person), build_editor.png.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/build_test.gd -- <out>

var ok := true
var ed
var bm: BuildMode


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func key(k: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func wheel(dir: int, times := 1) -> void:
	for i in times:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		Input.parse_input_event(e)
		await frames(2)


func click(button: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame
	await physics_frame


func look_at_point(from: Vector3, at: Vector3) -> void:
	bm.cam.global_position = from
	var f := (at - from).normalized()
	bm.yaw = atan2(-f.x, -f.z)
	bm.pitch = asin(f.y)
	bm._apply_cam()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._load_dict({})                                     # an empty map: nothing but what we build
	bm = ed.build
	key(KEY_E)
	key(KEY_E, false)
	await frames(2)
	check("E: into build mode (editor UI hidden, first-person camera)", bm.active and not ed._ui.visible and bm.cam.current)

	# out of thin air: look ahead, wheel towards you
	look_at_point(Vector3(0.5, 12.5, 12), Vector3(0.5, 12.5, 0))
	await frames(2)
	check("aiming at nothing: the target is a spot in the air", not bm.target.is_empty() and not bm.target["hit"])
	await wheel(-1)
	check("wheel towards you: a cube appears in the air", ed.cubes.world.count() == 1)
	await frames(3)
	var t1: Dictionary = bm.target
	check("...and now the crosshair is on its face", t1["hit"] and t1["sel"]["orient"] == 5, "(%s)" % t1)
	await wheel(-1, 3)
	check("three more: a row of 4 coming towards you", ed.cubes.world.count() == 4)
	await wheel(1)
	check("wheel away: the nearest one is pushed back in", ed.cubes.world.count() == 3)

	# a floor to build on: G + wheel to 4 m, look down at it
	key(KEY_G)
	await wheel(1, 2)
	key(KEY_G, false)
	check("G + wheel: the grid goes up to 4 m", bm.grid_p == 2, "(%s m)" % CubeWorld.metres(bm.grid_p))
	look_at_point(Vector3(0, 30, 30), Vector3(0, 0, 0))
	await frames(2)
	# select a 3 x 3 area of air cells by dragging, then pull it out: a floor
	look_at_point(Vector3(-8, 20, 0), Vector3(-8, 0, 0))
	await frames(2)
	click(MOUSE_BUTTON_LEFT, true)
	await frames(1)
	look_at_point(Vector3(8, 20, 0), Vector3(8, 0, 0))
	await frames(2)
	click(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	check("drag: a selection across the air below", not bm.sel.is_empty() and (bm.sel["s"] as Vector3i).x >= 4, "(%s)" % bm.sel.get("s"))
	await wheel(-1)
	var floor_cubes: int = ed.cubes.world.count() - 3
	check("wheel towards you: the whole selection fills (a floor)", floor_cubes >= 4, "(%d cubes)" % floor_cubes)
	key(KEY_SPACE)
	key(KEY_SPACE, false)
	check("Space drops the selection", bm.sel.is_empty())

	# F + wheel: push the face you aim at down 1/8 at a time (a lower step)
	await frames(3)
	look_at_point(Vector3(0.5, 20, -1.5), Vector3(0.5, 0, -1.5))
	await frames(3)
	var before_top = bm.target
	key(KEY_F)
	await wheel(1, 4)
	key(KEY_F, false)
	var lk = ed.cubes.world.leaf_at(Vector3(0.5, -0.5, -1.5) / CubeWorld.TICK)
	var c: PackedByteArray = ed.cubes.world.leaves[lk][0] if lk != null else PackedByteArray()
	check("F + wheel: the face you aim at went down 4/8", lk != null and CubeWorld.corner(c, 7).y == 4, "(%s)" % [c])
	# Q + wheel: one corner down - a slope
	await frames(3)
	key(KEY_Q)
	await wheel(1, 4)
	key(KEY_Q, false)
	c = ed.cubes.world.leaves[lk][0]
	var lows := 0
	for n in 8:
		if (n >> 1) & 1 and CubeWorld.corner(c, n).y == 0:
			lows += 1
	check("Q + wheel: the corner you aim at went down (a slope)", lows == 1 and CubeWorld.is_valid_shape(c), "(%s)" % [c])

	# Y + wheel: texture the face you aim at; 0 = all faces
	key(KEY_Y)
	await wheel(1, 5)
	key(KEY_Y, false)
	check("Y + wheel: a texture on the face you aim at", bm.texture != "" and ed.cubes.world.leaves[lk][1][3] == bm.texture,
		"(%s)" % bm.texture)

	# copy a cube from the row and paste it on the floor
	look_at_point(Vector3(0.5, 12.5, 12), Vector3(0.5, 12.5, 0))
	key(KEY_G)
	await wheel(-1, 2)
	key(KEY_G, false)
	await frames(3)
	var n_before: int = ed.cubes.world.count()
	key(KEY_C)
	key(KEY_C, false)
	check("C copies what you aim at", not bm.clip.is_empty())
	look_at_point(Vector3(6, 6, -2), Vector3(6, 0, -2))
	await frames(3)
	key(KEY_V)
	key(KEY_V, false)
	await frames(2)
	check("V pastes it where you aim", ed.cubes.world.count() > n_before)
	key(KEY_Z)
	key(KEY_Z, false)
	check("Z undoes it", ed.cubes.world.count() == n_before)

	# a look in first person
	look_at_point(Vector3(14, 10, 22), Vector3(0, 2, 0))
	await frames(6)
	root.get_viewport().get_texture().get_image().save_png(out + "/build_fp.png")

	# back to the editor
	key(KEY_E)
	key(KEY_E, false)
	await frames(2)
	check("E: back to the editor", not bm.active and ed._ui.visible)
	var total: int = ed.cubes.world.count()
	ed.save_map(out + "/build_test.sfmap")
	ed._new_map()
	check("a new map has no cubes", ed.cubes.world.count() == 0)
	ed.load_map(out + "/build_test.sfmap")
	await frames(3)
	check("cubes come back with the map (every one)", ed.cubes.world.count() == total, "(%d)" % total)
	ed._undo_clicked() if ed.has_method("_undo_clicked") else ed.undo()
	await frames(2)

	# play on them: drop a player above the floor; it should land on it
	ed.load_map(out + "/build_test.sfmap")
	await frames(3)
	ed.play.start(Transform3D(Basis(), Vector3(0, 12, 0)))
	for i in 150:
		await physics_frame
	var py: float = ed.play.player.global_position.y
	ed.play.stop()
	check("play: the player lands on the cube floor", py > -1.0 and py < 6.0, "(y %.2f)" % py)

	# exports (a CS:S map needs a start and a finish)
	var st := EntityNode.create("start")
	st.position = Vector3(20, 4, 20)
	ed.entities_root.add_child(st)
	var fin := EntityNode.create("finish")
	fin.position = Vector3(-20, 4, 20)
	ed.entities_root.add_child(fin)
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_build")
	var cnode: Node = scene.get_node_or_null("Cubes")
	check("SurfsUp export: cubes with a convex shape each", cnode != null and cnode.get_child_count() > 0)
	scene.free()
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := "D:/SurfForge_exports/css/sf_build.vmf"
		var res := VmfExporter.export_vmf(map, vmf)
		var cc := VmfExporter.compile(vmf, css, "fast", res.get("materials", []))
		var bad := 0
		for line in String(cc["log"]).split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("duplicate") or l.contains("out of range")):
				bad += 1
				if bad <= 4:
					print("      ", line.strip_edges())
		check("CS:S: every cube a brush, compiles cleanly", res["error"] == "" and cc["error"] == "" and bad == 0,
			"(%d brushes) %s %s" % [res["brushes"], res["error"], cc["error"]])
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(0, 4, 4)
	cam.distance = 40.0
	cam.yaw = deg_to_rad(30)
	cam.pitch = deg_to_rad(-30)
	cam._apply()
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/build_editor.png")
	print("BUILD: ", "PASS" if ok else "FAIL")
	quit()
