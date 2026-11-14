extends SceneTree
## Build-mode selection as in Sauerbraten (0.19.2): picking goes by the real geometry (a row of pushed-in cubes is
## picked on their pushed faces, never the air in front), right-pressing another face of the selection turns it to
## that face before moving it, any face of the selection can be right-clicked even where it holds only air, the
## number of selected blocks is shown, a paste keeps the copy's air, and a kill zone placed from the T menu fills the
## selection. Saves a picture of the selection (white face square, red origin marker) for a look.
## Run: godot --path . --resolution 1280x720 -s res://tests/selection_test.gd -- <out folder>

var ok := true
var ed
var bm: BuildMode


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame
	await physics_frame


func look(from: Vector3, at: Vector3) -> void:
	bm.cam.global_position = from
	var f := (at - from).normalized()
	bm.yaw = atan2(-f.x, -f.z)
	bm.pitch = asin(clampf(f.y, -0.9999, 0.9999))
	bm._apply_cam()


func right(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = down
	bm._input(e)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	# a row of 1 m cubes along x with their +z faces pushed in halfway
	var w := CubeWorld.new()
	var pushed := CubeWorld.FULL.duplicate()
	for n in 8:
		if (n >> 2) & 1:
			pushed[n * 3 + 2] = 4
	for i in 4:
		w.set_cell(Vector3i(i * 8, 0, 0), 0, pushed, CubeWorld.blank_tex("Bricks104"))
	for i in 4:
		w.set_cell(Vector3i(i * 8, -8, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("Bricks104"))
	ed._load_dict({"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}]})
	await frames(2)
	bm = ed.build
	var cm: CubeModelNode = ed.cube_models_root.get_child(0)
	bm.start(Transform3D(Basis(), Vector3(1.5, 0.5, 6)), cm)
	bm.grid_p = 0
	await frames(3)
	# S5: aiming at the pushed-in +z faces picks the cube's own cell, on its +z face
	look(Vector3(1.5, 0.5, 6), Vector3(1.5, 0.5, 0))
	await frames(3)
	bm.update_target()
	var ts: Dictionary = bm.target["sel"]
	check("a pushed-in face is picked on the cube itself, not the air in front", bm.target["on_cube"] and ts["o"] == Vector3i(8, 0, 0)
		and int(ts["orient"]) == 5, "(cell %s, face %d)" % [ts["o"], ts["orient"]])
	# select 3 x 2 x 1 cubes on that face
	bm.sel = CubeWorld.make_sel(Vector3i(0, -8, 0), 0, 5, Vector3i(3, 2, 1))
	bm.sel["model"] = cm
	await frames(2)
	check("the number of selected blocks is shown", String(bm._info.text).contains("6 blocks selected"), String(bm._info.text).get_slice("·", 3))
	root.get_viewport().get_texture().get_image().save_png(out + "/selection.png")
	# S4: right-press on the top face of the selection (from above): it turns to the top before moving
	look(Vector3(1.5, 4, 1.5), Vector3(1.5, 0.9, 0.5))
	await frames(2)
	bm.update_target()
	var face := bm._sel_face_aimed()
	check("aiming at the selection's top: its top face", face == 3, "(%d)" % face)
	right(true)
	await frames(1)
	check("right-pressing another face turns the selection to it", int(bm.sel["orient"]) == 3 and bm._drag == "selmove")
	right(false)
	await frames(1)
	check("...and letting go without moving keeps the selection where it was", bm.sel["o"] == Vector3i(0, -8, 0) and bm._drag == "")
	# S9: a selection over air: its faces can be right-clicked too
	bm.sel = CubeWorld.make_sel(Vector3i(0, 0, 40), 0, 5, Vector3i(2, 2, 2))
	bm.sel["model"] = cm
	look(Vector3(1, 1, 12), Vector3(1, 1, 5))
	await frames(2)
	bm.update_target()
	check("a selection holding only air: aiming at it finds its face", bm._sel_face_aimed() == 5, "(%d)" % bm._sel_face_aimed())
	# S8: a paste keeps the copy's air (here: the gap row above is copied over full cubes)
	var src := CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3, Vector3i(2, 2, 1))       # pushed row + the air above it
	var clip: Dictionary = cm.world.copy(src)
	var dst := CubeWorld.make_sel(Vector3i(0, -16, 16), 0, 3)
	for i in 2:
		for j in 2:
			cm.world.set_cell(Vector3i(i * 8, -16 + j * 8, 16), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	cm.world.set_cell(Vector3i(0, -8, 24), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	cm.world.paste(dst, clip)
	var hole = cm.world.leaf_at(Vector3(4, -4, 20))                                 # (the copy's top row was air)
	check("a paste keeps the copy's air: what was there doesn't show through", hole == null)
	# I2: a kill zone placed from the T menu fills the selection
	bm.sel = CubeWorld.make_sel(Vector3i(0, 0, 40), 0, 3, Vector3i(3, 2, 4))
	bm.sel["model"] = cm
	var before: int = ed.entities_root.get_child_count()
	bm._place(106)
	var kz: EntityNode = ed.entities_root.get_child(ed.entities_root.get_child_count() - 1) if ed.entities_root.get_child_count() > before else null
	check("a kill zone from the T menu fills the selection", kz != null and kz.kind == "kill" and kz.size.is_equal_approx(Vector3(3, 2, 4))
		and kz.position.is_equal_approx(Vector3(1.5, 1, 7)), "(%s at %s)" % [kz.size if kz else Vector3.ZERO, kz.position if kz else Vector3.ZERO])
	print("selection_test: ", "PASS" if ok else "FAIL")
	quit()
