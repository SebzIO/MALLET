extends SceneTree
## Build mode gathers the wheel notches of one frame into one edit (pull_n / push_n, laid down as big aligned cubes).
## That must give exactly the same cubes and textures as the notches one by one, and be fast on big selections at the
## 0.125 m grid. Also checks greedy meshing draws the same surface area as before.
## Run: godot --headless --path D:/SurfForge -s res://tests/wheel_batch_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-70s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## Every tick cell in the box: solid? and its leaf's texture of the face facing `o`.
func sample(w: CubeWorld, lo: Vector3i, hi: Vector3i, o: int) -> Array:
	var out := []
	for x in range(lo.x, hi.x):
		for y in range(lo.y, hi.y):
			for z in range(lo.z, hi.z):
				var k = w.leaf_at(Vector3(x, y, z) + Vector3.ONE * 0.5)
				out.append("" if k == null else (w.leaves[k][1] as PackedStringArray)[o])
	return out


## [visible area m2, triangles, collision area m2]
func mesh_area(w: CubeWorld, unmerged: bool) -> Array:
	var area := 0.0
	var carea := 0.0
	var tris := 0
	for ck in w.render_chunks():
		var got := w.chunk_mesh(ck, unmerged)
		var m: ArrayMesh = got[0]
		for si in m.get_surface_count():
			var v: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			tris += v.size() / 3
			for i in range(0, v.size(), 3):
				area += (v[1 + i] - v[i]).cross(v[2 + i] - v[i]).length() * 0.5
		var c: PackedVector3Array = got[1]
		for i in range(0, c.size(), 3):
			carea += (c[1 + i] - c[i]).cross(c[2 + i] - c[i]).length() * 0.5
	return [area, tris, carea]


func world(two_tex: bool) -> CubeWorld:
	var w := CubeWorld.new()
	w.set_cell(Vector3i(0, -128, 0), 4, CubeWorld.FULL, CubeWorld.blank_tex("grass"))
	if two_tex:                                           # a stripe of another texture, off the 1 m grid
		for x in range(5, 11):
			for z in range(0, 40):
				w.set_cell(Vector3i(x, -1, z), -3, CubeWorld.FULL, CubeWorld.blank_tex("rock"))
	return w


func _run() -> void:
	for two in [false, true]:
		for orient in [3, 0, 5]:
			for n in [2, 3, 9]:
				var o := Vector3i(3, -1, 2)
				var s := Vector3i(13, 1, 21)
				if orient == 0:
					o = Vector3i(0, -20, 3)
					s = Vector3i(1, 11, 17)
				elif orient == 5:
					o = Vector3i(2, -30, 127)
					s = Vector3i(19, 13, 1)
				var sel := {"o": o, "s": s, "p": -3, "orient": orient}
				var a := world(two)
				var b := world(two)
				var sa := sel
				for i in n:
					sa = a.pull(sa, "")
				var sb := b.pull_n(sel, n, "")
				var lo := o - Vector3i(12, 12, 12)
				var hi := o + s + Vector3i(12, 12, 12)
				var same := sample(a, lo, hi, orient) == sample(b, lo, hi, orient) and sa == sb
				check("pull %d at once = %d one by one (face %d%s)" % [n, n, orient, ", two textures" if two else ""], same,
					"(%d vs %d cubes)" % [a.count(), b.count()])
				for i in n - 1:
					sa = a.push(sa)
				sb = b.push_n(sb, n - 1)
				same = sample(a, lo, hi, orient) == sample(b, lo, hi, orient) and sa == sb
				check("push %d at once = %d one by one (face %d%s)" % [n - 1, n - 1, orient, ", two textures" if two else ""], same)
	# greedy meshing: same visible area as one quad per face
	var w := world(true)
	var sel := {"o": Vector3i(0, -1, 0), "s": Vector3i(40, 1, 33), "p": -3, "orient": 3}
	sel = w.pull(sel, "")
	sel = w.pull(sel, "")
	var r_merged := mesh_area(w, false)
	var r_plain := mesh_area(w, true)                     # (outline mode draws every face on its own)
	check("greedy mesh covers the same area (%.2f m2, %d vs %d triangles)" % [r_merged[0], r_merged[1], r_plain[1]],
		absf(r_merged[0] - r_plain[0]) < 0.01 and r_merged[1] * 10 < r_plain[1], "(unmerged %.2f m2)" % r_plain[0])
	check("greedy mesh collision covers the same area", absf(r_merged[2] - r_plain[2]) < 0.01)
	# speed: an 8 m face at 0.125 m
	var big := world(false)
	var bs := {"o": Vector3i(0, -1, 0), "s": Vector3i(64, 1, 64), "p": -3, "orient": 3}
	var t0 := Time.get_ticks_usec()
	big.begin()
	var bs2 := big.pull_n(bs, 8, "")
	big.commit()
	var t1 := Time.get_ticks_usec()
	for ck in big.dirty:
		big.chunk_mesh(ck)
	var t2 := Time.get_ticks_usec()
	print("  8 notches on an 8 m face at 0.125 m: edit %.0f ms, mesh %.0f ms, %d cubes" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, big.count()])
	check("8 notches at once on an 8 m face stay under 150 ms", (t2 - t0) / 1000.0 < 150.0)
	big.push_n(bs2, 8)
	check("and pushing them back leaves the plain block", big.count() <= 8, "(%d cubes)" % big.count())
	print("WHEEL BATCH: ", "PASS" if ok else "FAIL")
	quit()
