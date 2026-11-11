extends SceneTree
## Big edits on big cube objects don't hitch (0.18.12): finding the cubes in a cell walks the octree (and gives exactly
## what scanning everything gives), clearing a layer of a big sphere is quick, and redrawing it runs on worker threads
## and goes in a few chunks a frame, so no frame stalls.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/bulk_edit_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0


func brute(w: CubeWorld, o: Vector3i, size: Vector3i) -> Array:
	var out := []
	for k in w.leaves:
		var s := CubeWorld.size_of(k.w)
		if k.x < o.x + size.x and k.x + s > o.x and k.y < o.y + size.y and k.y + s > o.y and k.z < o.z + size.z and k.z + s > o.z:
			out.append(k)
	out.sort()
	return out


func _run() -> void:
	var g := ShapeGen.generate("sphere", {"r": 8.0}, 0, 2)
	var src := CubeWorld.new()
	ShapeGen.place(src, g["cells"], Vector3i.ZERO, "")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var same := true
	for i in 60:
		var o := Vector3i(rng.randi_range(-40, 140), rng.randi_range(-40, 140), rng.randi_range(-40, 140))
		var size := Vector3i(rng.randi_range(1, 70), rng.randi_range(1, 70), rng.randi_range(1, 70))
		var got := src.leaves_in(o, size)
		got.sort()
		same = same and got == brute(src, o, size)
	check("leaves_in walking the octree finds exactly what a full scan finds", same)
	var cm := CubeModelNode.new()
	root.add_child(cm)
	cm.from_dict({"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": src.to_dict()})
	var w: CubeWorld = cm.world
	var before := w.count()
	var t := Time.get_ticks_usec()
	w.begin()
	w.push(CubeWorld.make_sel(Vector3i(4, 15, 4) * 8, 0, 3, Vector3i(8, 1, 8)))
	w.commit()
	var edit := ms(t)
	check("pushing an 8 x 8 layer of a 32,000-cube sphere is quick", edit < 100.0 and w.count() < before, "%.1f ms" % edit)
	var worst := 0.0
	var frames := 0
	while frames < 2000:
		t = Time.get_ticks_usec()
		cm._process(0.016)
		worst = maxf(worst, ms(t))
		frames += 1
		if w.dirty.is_empty() and cm._bg_keys.is_empty() and cm._bg_ready.is_empty():
			break
		await process_frame
	check("...redrawing it never stalls a frame", worst < 25.0, "worst %.1f ms over %d frames" % [worst, frames])
	var fresh := CubeWorld.from_dict(w.to_dict())
	var tris_bg := 0
	var tris_new := 0
	for ck in cm._chunks:
		tris_bg += (cm._chunks[ck][2].shape as ConcavePolygonShape3D).get_faces().size()
	for ck in fresh._render:
		tris_new += (fresh.chunk_mesh(ck)[1] as PackedVector3Array).size()
	check("...and the background redraw gives the same collision as drawing it fresh", tris_bg == tris_new, "%d vs %d" % [tris_bg, tris_new])
	w.begin()
	w.delete(CubeWorld.make_sel(Vector3i(4, 8, 4) * 8, 0, 3, Vector3i(8, 8, 8)))
	w.commit()
	cm._process(0.016)
	w.begin()                                            # (editing while a redraw reads the world waits for it: no crash)
	w.push(CubeWorld.make_sel(Vector3i(4, 4, 4) * 8, 0, 3, Vector3i(4, 1, 4)))
	w.commit()
	cm.rebuild_dirty()
	check("editing during a background redraw is safe and ends up complete", w.dirty.is_empty() and cm._bg_keys.is_empty() and cm._bg_ready.is_empty())
	cm.queue_free()
	await process_frame
	print("bulk_edit_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
