extends SceneTree
## Merging cubes (0.19.0): wherever 8 cubes of a bigger cell are the same full cube they become that one bigger cube,
## and nothing you can see or touch changes: the drawn area of every texture and the collision are the same before
## and after, folded, cut, painted and differently textured cubes are left alone, and fills still hold. A map opens
## with its cubes merged.
## Run: godot --path . --resolution 1280x720 -s res://tests/merge_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


## {material: drawn area m2} and the collision area, over every chunk.
func picture(w: CubeWorld) -> Array:
	var by := {}
	var col := 0.0
	for ck in w.render_chunks():
		var got: Array = w.chunk_mesh(ck)
		var m: ArrayMesh = got[0]
		for si in m.get_surface_count():
			var mat = m.surface_get_material(si)
			var key := str(mat.get_instance_id()) if mat != null else "none"
			var v: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			var a := 0.0
			for i in range(0, v.size(), 3):
				a += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
			by[key] = by.get(key, 0.0) + a
		var c: PackedVector3Array = got[1]
		for i in range(0, c.size(), 3):
			col += (c[i + 1] - c[i]).cross(c[i + 2] - c[i]).length() * 0.5
	return [by, col]


func same_picture(a: Array, b: Array) -> String:
	# (collision may only grow: next to a folded small cube, a merged 1 m cube's wall is one whole square, three
	#  quarters of it flat against solid small cubes inside the build - as any 1 m cube beside small ones; less
	#  would be a hole)
	if float(b[1]) < float(a[1]) - 0.01 or float(b[1]) > float(a[1]) + 3.0:
		return "collision %.2f vs %.2f m2" % [a[1], b[1]]
	for k in a[0]:                                        # (the same hidden squares are drawn too, facing into solid)
		var d := float(b[0].get(k, 0.0)) - float(a[0][k])
		if d < -0.01 or d > 3.0:
			return "a texture's area %.2f vs %.2f m2" % [a[0][k], b[0].get(k, 0.0)]
	for k in b[0]:
		if not a[0].has(k):
			return "a texture drawn only after"
	return ""


func _run() -> void:
	var w := CubeWorld.new()
	var tex_a := CubeWorld.blank_tex("Bricks104")
	var tex_b := CubeWorld.blank_tex("Metal009")
	for x in 16:                                          # a 2 x 1 x 2 m slab of small cubes, two textures (halves)
		for y in 8:
			for z in 16:
				w.set_cell(Vector3i(x, y, z), -3, CubeWorld.FULL.duplicate(), tex_a if x < 8 else tex_b)
	for x in 4:                                           # a 2 m block of 0.5 m cubes with one folded
		for y in 4:
			for z in 4:
				w.set_cell(Vector3i(40 + x * 4, y * 4, z * 4), -1, CubeWorld.FULL.duplicate(), tex_a)
	var bent := CubeWorld.FULL.duplicate()
	bent[7 * 3 + 1] = 4                                   # (one top corner pushed halfway down)
	w.set_cell(Vector3i(44, 4, 4), -1, bent, tex_a)
	ShapeGen.place(w, ShapeGen.generate("cone", {"r": 2.0, "h": 3.0}, -1, 2)["cells"], Vector3i(80, 0, 0), "")   # cut cubes
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 16), -3, 3, Vector3i(16, 8, 4)), "water")              # a fill beside
	var n0 := w.count()
	var before := picture(w)
	var saved := w.merge_cubes()
	var after := picture(w)
	print("  %d cubes -> %d" % [n0, w.count()])
	check("same textures in 8s merge into bigger cubes", saved > 0 and w.count() < n0 / 3, "(%d -> %d)" % [n0, w.count()])
	var diff := same_picture(before, after)
	check("nothing you can see or touch changes (textures, collision)", diff == "", diff)
	check("the folded cube is left as it was", w.leaves.has(Vector4i(44, 4, 4, -1)))
	check("the two textures stay apart", w.leaf_at(Vector3(2, 2, 2)) != null and w.leaf_at(Vector3(12, 2, 2)) != null
		and w.leaves[w.leaf_at(Vector3(2, 2, 2))][1] != w.leaves[w.leaf_at(Vector3(12, 2, 2))][1])
	check("the fill is still there", w.mat_at(Vector3(4, 4, 18)) == "water")
	check("merging again changes nothing", w.merge_cubes() == 0)
	# a map opens merged
	var d := w.to_dict()
	var w2 := CubeWorld.from_dict(d)
	check("a map's cubes open merged", w2.count() == w.count())
	print("merge_test: ", "PASS" if ok else "FAIL")
	quit()
