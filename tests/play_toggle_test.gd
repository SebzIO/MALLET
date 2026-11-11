extends SceneTree
## P and Esc only re-mesh what looks different (0.18.7): a chunk with invisible materials (clip, death...) is redrawn,
## every other chunk is left alone, so entering and leaving play mode stays instant however big the cube objects are.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/play_toggle_test.gd -- <out folder>

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
	ShapeGen.place(w, ShapeGen.generate("cone", {"r": 4.0, "h": 4.0, "sides": 25}, 0, 0)["cells"], Vector3i.ZERO, "")
	w.set_material(CubeWorld.make_sel(Vector3i(0, 1600, 0), 0, 3), "clip")
	ed._load_dict({"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}]})
	await process_frame
	var cm: CubeModelNode = ed.cube_models_root.get_child(0)
	var hidden: Array = cm.world.hidden_mat_chunks()
	check("the clip cube's chunk is the only one with hidden materials", hidden.size() == 1 and cm._chunks.size() > 1, "%d of %d chunks" % [hidden.size(), cm._chunks.size()])
	var meshes := {}
	for ck in cm._chunks:
		meshes[ck] = cm._chunks[ck][0].mesh
	ed._play_clicked()
	await process_frame
	var redone := 0
	for ck in meshes:
		if ck in hidden:
			continue
		if not cm._chunks.has(ck) or cm._chunks[ck][0].mesh != meshes[ck]:
			redone += 1
	check("P leaves every other chunk alone", redone == 0, "%d redrawn" % redone)
	var gone: bool = not cm._chunks.has(hidden[0]) or not is_instance_valid(cm._chunks[hidden[0]][0]) or (cm._chunks[hidden[0]][0].mesh as ArrayMesh).get_surface_count() == 0
	check("...and the clip cube is not drawn while playing", gone)
	ed.play.stop()
	await process_frame
	check("Esc draws the clip cube again", cm._chunks.has(hidden[0]) and (cm._chunks[hidden[0]][0].mesh as ArrayMesh).get_surface_count() > 0)
	redone = 0
	for ck in meshes:
		if not ck in hidden and cm._chunks[ck][0].mesh != meshes[ck]:
			redone += 1
	check("...and leaves every other chunk alone", redone == 0, "%d redrawn" % redone)
	# build mode's 7: outlines were made with the mesh, so toggling only shows or hides them
	ed.build.start(Transform3D(Basis(), Vector3(4, 4, 20)), cm)
	await process_frame
	var before: Mesh = cm._chunks[meshes.keys()[0]][0].mesh
	var was := CubeModelNode.outline_mode
	var t := Time.get_ticks_usec()
	ed.build._toggle("outline")
	var us := Time.get_ticks_usec() - t
	var part: Array = cm._chunks[meshes.keys()[0]]
	check("7 shows the outlines without rebuilding anything", CubeModelNode.outline_mode != was and part[0].mesh == before and part[3].visible
		and (part[3].mesh as ArrayMesh).get_surface_count() > 0, "%.2f ms" % (us / 1000.0))
	ed.build._toggle("outline")
	check("...and 7 again hides them", not part[3].visible and part[0].mesh == before)
	ed.build.stop()
	await process_frame
	ed.queue_free()
	await process_frame
	print("play_toggle_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
