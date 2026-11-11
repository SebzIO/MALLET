extends SceneTree
## Hovering and selecting in build mode stay cheap over big shapes (0.18.9): a grid cell over many small cubes is
## highlighted as its plain square instead of outlining thousands of cubes every frame; a cell with few cubes still
## shows their true faces.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/hover_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var g := ShapeGen.generate("sphere", {"r": 8.0}, 0, 2)
	var w := CubeWorld.new()
	ShapeGen.place(w, g["cells"], Vector3i.ZERO, "")
	ed._load_dict({"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}]})
	await process_frame
	var bm: BuildMode = ed.build
	var cm: CubeModelNode = ed.cube_models_root.get_child(0)
	bm.start(Transform3D(Basis(), Vector3(8, 8, 40)), cm)
	await process_frame
	var aim := Transform3D(Basis(), Vector3(8, 8, 40))
	for p in [0, 2, 3, 4]:
		bm.grid_p = p
		bm.sel = {}
		bm.cam.global_transform = aim
		bm.update_target()
		for selected in [false, true]:
			if selected:
				bm.sel = (bm.target["sel"] as Dictionary).duplicate()
			var t := Time.get_ticks_usec()
			bm._draw()
			var ms := (Time.get_ticks_usec() - t) / 1000.0
			var verts: int = (bm._im.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			check("grid %.0f m%s: a few lines, not one per small cube" % [CubeWorld.metres(p), ", selected" if selected else ""],
				bool(bm.target["hit"]) and verts <= 200 and ms < 8.0, "%.2f ms, %d line points" % [ms, verts])
	var one := Vector3i(0, 0, 0)
	var w2 := CubeWorld.new()
	w2.set_cell(one, 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex(""), PackedByteArray(), [])
	var small := CubeModelNode.new()
	ed.cube_models_root.add_child(small)
	small.world = w2
	bm._im.clear_surfaces()
	bm._im.surface_begin(Mesh.PRIMITIVE_LINES)
	var sel := CubeWorld.make_sel(one, 0, 3)
	sel["model"] = small
	check("a cell with few cubes still shows its true face", bm._true_face(small.global_transform, sel, Color.WHITE))
	bm._line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)
	bm._im.surface_end()
	ed.queue_free()
	await process_frame
	print("hover_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
