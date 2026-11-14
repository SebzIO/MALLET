extends SceneTree
## Build-mode aiming jumps over empty space (0.18.18): at a 0.125 m grid on a big object with many material cells,
## finding what you aim at took up to 436 ms a frame (every empty cell scanned every material cell). The jump must
## find exactly what the plain cell-by-cell walk finds, for any ray, grid size, cube size, material and cut shape.
## Run: godot --path . --resolution 1280x720 -s res://tests/aim_skip_test.gd -- <out folder>

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
	var w := CubeWorld.new()
	ShapeGen.place(w, ShapeGen.generate("sphere", {"r": 3.0}, -2, 2)["cells"], Vector3i.ZERO, "")      # small cubes
	ShapeGen.place(w, ShapeGen.generate("cone", {"r": 4.0, "h": 6.0}, 0, 2)["cells"], Vector3i(160, 0, 0), "")   # cut cubes
	for i in 6:                                                                                       # big blocks, spread out
		w.set_cell(Vector3i(-400 + i * 128, -64, -320 + (i % 3) * 200), 3, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	w.begin()
	w.set_material(CubeWorld.make_sel(Vector3i(-200, 40, 200), 0, 3, Vector3i(6, 3, 6)), "lava")       # materials
	w.set_material(CubeWorld.make_sel(Vector3i(300, 0, -100), -3, 3, Vector3i(5, 5, 5)), "glass")
	w.commit()
	ed._load_dict({"cube_models": [{"position": [3.0, 1.0, -2.0], "yaw": 30.0, "cubes": w.to_dict()}]})
	await process_frame
	var bm: BuildMode = ed.build
	var cm: CubeModelNode = ed.cube_models_root.get_child(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := 0
	var found := 0
	var bad := []
	var t_jump := 0
	var t_walk := 0
	var center := cm.global_transform * Vector3(0, 2, 0)
	var things: Array = cm.world.leaves.keys() + cm.world.mats.keys()
	for n in 600:
		var from := center + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(10.0, 90.0)
		var k: Vector4i = things[rng.randi() % things.size()]
		var to: Vector3 = cm.global_transform * ((Vector3(k.x, k.y, k.z) + Vector3.ONE * CubeWorld.size_of(k.w) * rng.randf_range(0.1, 0.9)) * CubeWorld.TICK)
		if n % 4 == 3:                                     # (and some anywhere)
			to = center + Vector3(rng.randf_range(-60, 60), rng.randf_range(-12, 12), rng.randf_range(-60, 60))
		var dir := (to - from).normalized()
		var p: int = [-3, -2, -1, 0, 2][n % 5]
		bm.aim_jumps = true
		var t0 := Time.get_ticks_usec()
		var a: Dictionary = bm._first_occupied(cm, from, dir, 300.0, p)
		t_jump += Time.get_ticks_usec() - t0
		bm.aim_jumps = false
		t0 = Time.get_ticks_usec()
		var b: Dictionary = bm._first_occupied(cm, from, dir, 300.0, p)
		t_walk += Time.get_ticks_usec() - t0
		if not b.is_empty():
			found += 1
		var eq := a.is_empty() == b.is_empty()
		if eq and not a.is_empty():
			eq = a["cell"] == b["cell"] and a["orient"] == b["orient"] and (a["point"] as Vector3).distance_to(b["point"]) < 0.01
		if eq:
			same += 1
		elif bad.size() < 5:
			bad.append("grid %d: %s vs %s" % [p, a, b])
	print("  600 rays (%d hit something): jumping %.1f ms, walking %.1f ms" % [found, t_jump / 1000.0, t_walk / 1000.0])
	check("jumping over empty space finds exactly what the plain walk finds", same == 600, "(%d / 600) %s" % [same, bad])
	check("...and it hits things (the test means something)", found > 200, "(%d)" % found)
	check("...and is much quicker", t_jump * 3 < t_walk, "(%.1f vs %.1f ms)" % [t_jump / 1000.0, t_walk / 1000.0])
	# the material count is kept right through undo
	w = cm.world
	var before := w._mocc.size()
	w.begin()
	w.set_material(CubeWorld.make_sel(Vector3i(0, 400, 0), -1, 3, Vector3i(3, 3, 3)), "water")
	w.commit()
	var grew := w._mocc.size() > before
	w.undo()
	check("material counts follow an edit and its undo", grew and w._mocc.size() == before and not w.cell_occupied(Vector3i(0, 400, 0), 2))
	print("aim_skip_test: ", "PASS" if ok else "FAIL")
	quit()
