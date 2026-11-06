extends SceneTree
## Splitting a shaped cube into smaller ones must keep its shape exactly (0.8.9: pieces that 8 corners can't show
## keep the original's exact planes). Builds sloped / cornered / two-way cubes the way F / Q + wheel make them, then
## pushes smaller cubes out of them (1-5 levels down, what editing at a smaller grid does) and checks every piece:
## its corners are exactly the original's solid inside its cell (no rounding anywhere), and the pieces' volumes add
## up to the original's minus what was pushed out. Also: save / load, rotate x4, flip x2 and copy / paste keep the
## pieces, and the meshes / collision points come out of them.
## Run: godot --headless --path D:/SurfForge -s res://tests/split_accuracy_test.gd

const N := 48
var ok := true


func _init() -> void:
	call_deferred("_run")


static func shapes() -> Array:   ## (static: other tests use these shapes without running this test)
	var out := []
	for k in range(1, 9):                       # ramp: top-front edge pushed down k / 8
		var c := CubeWorld.FULL.duplicate()
		for n in CubeWorld.face_corners(3):
			if not (n >> 2) & 1:
				CubeWorld._nudge(c, 3, n, k)
		out.append(["slope %d/8" % k, c])
	for k in range(1, 9):                       # one top corner pushed down k / 8
		var c := CubeWorld.FULL.duplicate()
		CubeWorld._nudge(c, 3, 2, k)
		out.append(["corner %d/8" % k, c])
	for pair in [[8, 4], [6, 2], [5, 3], [3, 1]]: # sloped two ways at once
		var c := CubeWorld.FULL.duplicate()
		for n in CubeWorld.face_corners(3):
			var amt := 0
			if not (n >> 2) & 1:
				amt += pair[0]
			if not n & 1:
				amt += pair[1]
			CubeWorld._nudge(c, 3, n, mini(amt, 8))
		if CubeWorld.is_valid_shape(c):
			out.append(["two-way %d,%d" % pair, c])
	for k in range(1, 9):                       # side face slope (x) - a wall leaning in
		var c := CubeWorld.FULL.duplicate()
		for n in CubeWorld.face_corners(1):
			if (n >> 1) & 1:
				CubeWorld._nudge(c, 1, n, k)
		out.append(["lean %d/8" % k, c])
	return out


## The original's exact solid inside a cell (o ticks, power p) of a big cube (power big): a cut in the cell's units.
func expected_cut(c: PackedByteArray, big: int, o: Vector3i, p: int) -> Array:
	var S := CubeWorld.size_of(big)
	var L := CubeWorld.size_of(p)
	var out := []
	for pl in CubeWorld.cut_from_corners(c):
		var n: Vector3i = pl[0]
		out.append([n, (int(pl[1]) * S - 8 * CubeWorld._idot(n, o)) / L, pl[2]])
	return out


## A leaf's solid as a cut (corner cubes converted; a whole cube is an empty cut).
func leaf_cut(v: Array) -> Array:
	var cut := CubeWorld._cut_of(v)
	if not cut.is_empty():
		return cut
	return [] if v[0] == CubeWorld.FULL else CubeWorld.cut_from_corners(v[0])


func volume(cut: Array) -> float:
	var pts := CubeWorld.cut_vertices(cut)
	var cen := Vector3.ZERO
	for p in pts:
		cen += p
	cen /= maxf(pts.size(), 1.0)
	var vol := 0.0
	for f in CubeWorld.cut_faces(cut):
		var poly: PackedVector3Array = f[2]
		for i in range(1, poly.size() - 1):
			vol += absf((poly[0] - cen).dot((poly[i] - cen).cross(poly[i + 1] - cen))) / 6.0
	return vol


## Push a cube of power sub out of an 8 m shaped cube at `cell` (ticks); returns [ok, detail].
func push_check(c: PackedByteArray, sub: int, cell: Vector3i) -> Array:
	var big := 3
	var w := CubeWorld.new()
	w.set_cell(Vector3i.ZERO, big, c, CubeWorld.blank_tex())
	w.push(CubeWorld.make_sel(cell, sub, 3))
	var scale_big := pow(CubeWorld.size_of(big) / 8.0, 3.0)
	var want := volume(expected_cut(c, big, Vector3i.ZERO, big)) * scale_big
	var gone_shape := CubeWorld.shape_from_cut(expected_cut(c, big, cell, sub))
	if not gone_shape.is_empty():
		want -= volume(leaf_cut([gone_shape[0], [], [], gone_shape[1]])) * pow(CubeWorld.size_of(sub) / 8.0, 3.0)
	var got := 0.0
	for k in w.leaves:
		var v: Array = w.leaves[k]
		var exp := CubeWorld.shape_from_cut(expected_cut(c, big, Vector3i(k.x, k.y, k.z), k.w))
		if exp.is_empty():
			return [false, "piece %s shouldn't exist" % k]
		var a := CubeWorld.cut_vertices(leaf_cut(v))
		var b := CubeWorld.cut_vertices(leaf_cut([exp[0], [], [], exp[1]]))
		if not CubeWorld._same_points(a, b):
			return [false, "piece %s is the wrong shape" % k]
		got += volume(leaf_cut(v)) * pow(CubeWorld.size_of(k.w) / 8.0, 3.0)
	if absf(got - want) > 1e-3 * maxf(want, 1.0):
		return [false, "pieces add up to %.4f, want %.4f (a piece is missing)" % [got, want]]
	return [true, "%d pieces" % w.leaves.size()]


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all := shapes()
	# 1) push cubes 1-5 levels smaller out of every shape: every piece exact, nothing missing
	for s in all:
		var bad := ""
		var tries := 0
		for sub in [2, 1, 0, -1, -2]:
			var g := CubeWorld.size_of(sub)
			var n := 64 / g
			for t in (8 if sub >= 1 else 6):
				var cell := Vector3i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1), rng.randi_range(0, n - 1)) * g
				var r := push_check(s[1], sub, cell)
				tries += 1
				if not r[0]:
					bad = "%.3f m cube at %s: %s" % [CubeWorld.metres(sub), cell, r[1]]
					break
			if bad != "":
				break
		await process_frame                              # keep the window responding (Windows flags it otherwise)
		check("%s: %d pushes 4 m - 0.25 m, every piece exact" % [s[0], tries], bad == "", bad)
	# 2) a split slope survives save / load, rotate x4, flip x2, copy / paste, and draws + collides
	var c: PackedByteArray = all[2][1]                    # slope 3/8: pieces need exact cuts
	var w := CubeWorld.new()
	w.set_cell(Vector3i.ZERO, 3, c, CubeWorld.blank_tex())
	w.push(CubeWorld.make_sel(Vector3i(24, 40, 8), -1, 3))
	var cuts := 0
	for k in w.leaves:
		if not CubeWorld._cut_of(w.leaves[k]).is_empty():
			cuts += 1
	check("a 3/8 slope split down to 0.5 m keeps exact pieces", cuts > 0, "(%d exact pieces of %d)" % [cuts, w.leaves.size()])
	var before := w.leaves.duplicate(true)
	var w2 := CubeWorld.from_dict(w.to_dict())
	check("save / load keeps every piece exactly", w2.leaves == before)
	var sel := CubeWorld.make_sel(Vector3i.ZERO, 3, 3)
	for i in 4:
		sel = w.rotate(sel, 1)
	check("rotating a quarter turn 4 times gives the same pieces back", w.leaves == before)
	w.flip(sel)
	var flipped_differs := w.leaves != before
	w.flip(sel)
	check("flipping twice gives the same pieces back (and once changes them)", w.leaves == before and flipped_differs)
	var clip := w.copy(sel)
	var w3 := CubeWorld.new()
	w3.paste(CubeWorld.make_sel(Vector3i(128, 0, 0), 3, 3), clip)
	var moved_ok := true
	for k in before:
		if w3.leaves.get(Vector4i(k.x + 128, k.y, k.z, k.w)) != before[k]:
			moved_ok = false
	check("copy / paste somewhere else keeps every piece", moved_ok and w3.leaves.size() == before.size())
	var tris := 0
	var col_pts := 0
	for ck in w.render_chunks():
		var m: Array = w.chunk_mesh(ck, true)
		tris += (m[1] as PackedVector3Array).size() / 3
	for k in w.leaves:
		col_pts += w.cube_points(k).size()
	var outward := true
	for k in w.leaves:
		var cut := CubeWorld._cut_of(w.leaves[k])
		if cut.is_empty():
			continue
		var pts := CubeWorld.cut_vertices(cut)
		var cen := Vector3.ZERO
		for p in pts:
			cen += p
		cen /= pts.size()
		for f in CubeWorld.cut_faces(cut):
			var poly: PackedVector3Array = f[2]
			var fc := Vector3.ZERO
			for p in poly:
				fc += p
			fc /= poly.size()
			for i in range(1, poly.size() - 1):
				if (poly[i] - poly[0]).cross(poly[i + 1] - poly[0]).dot(fc - cen) <= 0.0:
					outward = false
	check("every face of an exact piece faces outwards", outward)
	check("pieces draw, collide and give collision / brush points", tris > 0 and col_pts > 0, "(%d collision triangles)" % tris)
	print("SPLIT ACCURACY: ", "PASS" if ok else "FAIL")
	quit()


func check(label: String, good: bool, detail := "") -> void:
	print("%-70s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good
