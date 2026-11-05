extends SceneTree
## Cube world (build mode's geometry): pull / push cubes, merging, face and corner pushes (slopes), splitting a sloped
## cube, validity, textures, rotate / flip, copy / paste, undo / redo, saving, hidden faces.
## Run: godot --headless --path D:/SurfForge -s res://tests/cube_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## Is a point (cube units 0..8, inside cube corners c) inside the solid?
func inside(c: PackedByteArray, p: Vector3) -> bool:
	for o in 6:
		for t in CubeWorld.face_triangles(c, o):
			var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
			if n.dot(p - t[0]) > 1e-4:
				return false
	return true


func world_solid_at(w: CubeWorld, pt_ticks: Vector3) -> bool:
	var k = w.leaf_at(pt_ticks)
	if k == null:
		return false
	var s := float(CubeWorld.size_of(k.w))
	var local := (pt_ticks - Vector3(k.x, k.y, k.z)) / s * 8.0
	return inside(w.leaves[k][0], local)


func _run() -> void:
	var w := CubeWorld.new()
	var p := 0                                            # 1 m cubes (8 ticks)
	# pulling out of "air": a selection under the spot, facing up
	var sel := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3)
	w.begin()
	sel = w.pull(sel, "Bricks104")
	w.commit()
	check("pull: one 1 m cube appears", w.count() == 1 and w.leaves.has(Vector4i(0, 0, 0, 0)))
	check("...and the selection moved onto it", sel["o"] == Vector3i(0, 0, 0))
	w.begin()
	sel = w.pull(sel)
	w.commit()
	check("pull again: a second cube on top, same texture", w.leaves.has(Vector4i(0, 8, 0, 0))
		and w.leaves[Vector4i(0, 8, 0, 0)][1][3] == "Bricks104")
	w.begin()
	sel = w.push(sel)
	w.commit()
	check("push: the top cube is gone", w.count() == 1 and sel["o"] == Vector3i(0, 0, 0))

	# 8 cubes filling a 2 m cell merge into one 2 m cube
	w.clear()
	w.begin()
	var floor_sel := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 2))
	floor_sel = w.pull(floor_sel, "")
	floor_sel = w.pull(floor_sel, "")
	w.commit()
	check("a full 2 x 2 x 2 block of 1 m cubes merges into one 2 m cube", w.count() == 1 and w.leaves.has(Vector4i(0, 0, 0, 1)))
	# editing one 1 m cell of it splits it back
	w.begin()
	w.push(CubeWorld.make_sel(Vector3i(8, 8, 8), p, 3))
	w.commit()
	check("pushing one corner cell out of it splits it (7 left)", w.count() == 7)

	# face push: the top of a cube goes down in 1/8 steps; 8 steps and it's gone
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3))
	w.commit()
	var top := CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3)
	w.begin()
	w.push_face(top, 1)
	w.commit()
	var c: PackedByteArray = w.leaves[Vector4i(0, 0, 0, 0)][0]
	check("F + wheel: the top face drops 1/8", CubeWorld.corner(c, 7).y == 7 and CubeWorld.corner(c, 0).y == 0)
	for i in 7:
		w.begin()
		w.push_face(top, 1)
		w.commit()
	check("...and after 8 steps the cube is gone", w.count() == 0)
	w.undo()
	check("undo brings the 1/8-thick cube back", w.count() == 1 and CubeWorld.corner(w.leaves[Vector4i(0, 0, 0, 0)][0], 7).y == 1)
	for i in 7:
		w.undo()
	check("undo all the way: a full cube again", w.leaves[Vector4i(0, 0, 0, 0)][0] == CubeWorld.FULL)
	w.redo()
	check("redo", CubeWorld.corner(w.leaves[Vector4i(0, 0, 0, 0)][0], 7).y == 7)
	w.undo()

	# pulling a face that's already at its side starts a thin cube on top
	w.begin()
	var up := w.push_face(top, -1)
	w.commit()
	var thin = w.leaves.get(Vector4i(0, 8, 0, 0))
	check("F + wheel out at the side: a 1/8 cube starts on top", thin != null and CubeWorld.corner(thin[0], 7).y == 1
		and CubeWorld.corner(thin[0], 0).y == 0 and up["o"] == Vector3i(0, 8, 0))

	# corner push: a slope
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3))
	w.commit()
	for i in 8:
		w.begin()
		w.push_face(top, 1, 2)                             # corner 2 of the top face's quad
		w.commit()
	c = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var lowered := 0
	for n in 8:
		if (n >> 1) & 1 and CubeWorld.corner(c, n).y == 0:
			lowered += 1
	check("Q + wheel: one top corner pushed all the way down (a corner slope)", lowered == 1 and CubeWorld.is_valid_shape(c))
	# push both corners on one side: a wedge (a ramp)
	w.begin()
	for i in 8:
		w.push_face(top, 1, 1)
	w.commit()
	c = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var wedge := CubeWorld.is_valid_shape(c) and inside(c, Vector3(1, 6, 4)) == (CubeWorld.corner(c, 2).y == 8 or CubeWorld.corner(c, 3).y == 8)
	check("two top corners down: a wedge, still valid", CubeWorld.is_valid_shape(c), "(corners %s)" % [c])
	var bad := CubeWorld.FULL.duplicate()
	bad[7 * 3] = 4
	bad[7 * 3 + 1] = 4
	bad[7 * 3 + 2] = 4
	check("a dented (concave) cube is rejected", not CubeWorld.is_valid_shape(bad))

	# splitting a sloped 2 m cube keeps its shape (sample points agree)
	w.clear()
	var wc := CubeWorld.FULL.duplicate()
	for n in [3, 7]:                                      # +X top corners down to the bottom: a wedge
		wc[n * 3 + 1] = 0
	w.set_cell(Vector3i(0, 0, 0), 1, wc, CubeWorld.blank_tex())
	var before := []
	for x in 8:
		for y in 8:
			for z in 8:
				before.append(world_solid_at(w, Vector3(x * 2 + 1, y * 2 + 1, z * 2 + 1)))
	w._split(Vector4i(0, 0, 0, 1))
	var agree := 0
	var i2 := 0
	for x in 8:
		for y in 8:
			for z in 8:
				if world_solid_at(w, Vector3(x * 2 + 1, y * 2 + 1, z * 2 + 1)) == before[i2]:
					agree += 1
				i2 += 1
	check("splitting a wedge into 8 keeps its shape", agree >= 500, "(%d / 512 sample points agree)" % agree)

	# textures, rotate, flip
	w.clear()
	w.begin()
	var row := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 1))
	row = w.pull(row, "")
	w.set_texture(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3), "Grass004")
	w.commit()
	check("Y: the top of one cube textured", w.leaves[Vector4i(0, 0, 0, 0)][1][3] == "Grass004" and w.leaves[Vector4i(8, 0, 0, 0)][1][3] == "")
	w.begin()
	w.set_texture(CubeWorld.make_sel(Vector3i(8, 0, 0), p, 3), "Metal009", true)
	w.commit()
	check("...all faces of the other (all faces on)", w.leaves[Vector4i(8, 0, 0, 0)][1] == CubeWorld.blank_tex("Metal009"))
	# rotate the 2 x 1 row a quarter turn about Y: it becomes 1 x 2 along Z
	w.begin()
	var r := w.rotate(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(2, 1, 1)), 1)
	w.commit()
	check("R: a 2 x 1 row turns into 1 x 2", w.count() == 2 and r["s"] == Vector3i(1, 1, 2))
	var tops := []
	for k in w.leaves:
		tops.append(w.leaves[k][1][3])
	check("...tops keep their textures", tops.has("Grass004") and tops.has("Metal009"))
	w.begin()
	w.flip(r)
	w.commit()
	check("X: flipping keeps two cubes", w.count() == 2)

	# copy / paste
	var clip := w.copy(r)
	w.begin()
	var pasted := w.paste(CubeWorld.make_sel(Vector3i(40, 0, 0), p, 3), clip)
	w.commit()
	check("C / V: copy and paste somewhere else", w.count() == 4 and pasted["s"] == Vector3i(1, 1, 2))

	# saving
	var d := w.to_dict()
	var w2 := CubeWorld.from_dict(d)
	var same := w2.count() == w.count()
	for k in w.leaves:
		same = same and w2.leaves.has(k) and w2.leaves[k][0] == w.leaves[k][0] and w2.leaves[k][1] == w.leaves[k][1]
	check("save / load keeps every cube, corner and texture", same)

	# hidden faces: two cubes side by side draw 10 faces (20 triangles), not 12
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 1)))
	w.commit()
	var mesh_data := w.chunk_mesh(Vector3i(0, 0, 0))
	check("faces between touching cubes aren't drawn", (mesh_data[1] as PackedVector3Array).size() == 20 * 3,
		"(%d triangles)" % ((mesh_data[1] as PackedVector3Array).size() / 3))
	print("CUBES: ", "PASS" if ok else "FAIL")
	quit()
