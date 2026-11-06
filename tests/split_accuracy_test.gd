extends SceneTree
## How faithfully splitting a shaped cube into smaller ones keeps its shape. Builds sloped / cornered cubes the way
## F / Q + wheel make them, splits them 1-3 levels deep (what pushing a smaller cube out of a big one does), then
## samples the parent's volume on a fine grid and counts points where the pieces disagree with the original:
## "gap" = original is solid there but no piece is, "bulge" = a piece is solid there but the original wasn't.
## Run: godot --headless --path D:/SurfForge -s res://tests/split_accuracy_test.gd [-- verbose]

const N := 48
var ok := true


func _init() -> void:
	call_deferred("_run")


func shapes() -> Array:
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


## [corners, offset (parent units), size (parent units)] for every piece after `levels` splits.
func pieces(c: PackedByteArray, levels: int, off := Vector3.ZERO, size := 8.0) -> Array:
	if levels == 0:
		return [[c, off, size]]
	var out := []
	for o in 8:
		var cc := CubeWorld.child_corners(c, o)
		if cc.is_empty():
			continue
		var h := size * 0.5
		out.append_array(pieces(cc, levels - 1, off + Vector3(o & 1, (o >> 1) & 1, (o >> 2) & 1) * h, h))
	return out


func inside(c: PackedByteArray, planes: Array, u: Vector3) -> bool:
	if c == CubeWorld.FULL:
		return true
	for pl in planes:
		if (pl[0] as Vector3).dot(u) - float(pl[1]) > 1e-4:
			return false
	return true


func measure(c: PackedByteArray, levels: int) -> Array:
	var parent_planes := CubeWorld.solid_planes(c)
	var ps := pieces(c, levels)
	for p in ps:
		p.append(CubeWorld.solid_planes(p[0]))
	var cell := 8.0 / pow(2.0, levels)
	var gap := 0
	var bulge := 0
	var solid := 0
	for i in N:
		for j in N:
			for k in N:
				var pt := (Vector3(i, j, k) + Vector3(0.5, 0.5, 0.5)) * (8.0 / N)
				var a := inside(c, parent_planes, pt)
				var b := false
				var ci := Vector3(floorf(pt.x / cell), floorf(pt.y / cell), floorf(pt.z / cell)) * cell
				for p in ps:
					if (p[1] as Vector3).is_equal_approx(ci):
						b = inside(p[0], p[3], (pt - p[1]) * (8.0 / p[2]))
						break
				if a:
					solid += 1
				if a and not b:
					gap += 1
				if b and not a:
					bulge += 1
	return [gap, bulge, solid]


func _run() -> void:
	var verbose := "verbose" in OS.get_cmdline_user_args()
	# 1) the real edit on slopes that land on the smaller cubes' grid: what's left must match exactly
	for s in shapes():
		if s[0] in ["slope 4/8", "lean 4/8", "slope 8/8", "slope 2/8"]:
			for sub in [2, 1]:
				var r := world_check(s[1], sub)
				check("%s: push a %d m cube out of an 8 m one, every position" % [s[0], CubeWorld.metres(sub)], r[0] < 0.01,
					"(worst %.2f%% wrong at cell %s)" % r)
	# 2) every shape, split 1-3 deep: overall error (other slopes can't be exact: the cubes only have 1/8 steps)
	var total := [0, 0, 0]
	for s in shapes():
		for levels in [1, 2, 3]:
			var r := measure(s[1], levels)
			for i in 3:
				total[i] += r[i]
			if verbose:
				print("%-14s %d deep: gap %5.2f%%  bulge %5.2f%%" % [s[0], levels, r[0] * 100.0 / r[2], r[1] * 100.0 / r[2]])
	var err: float = float(total[0] + total[1]) / float(total[2]) * 100.0
	check("all shapes split 1-3 deep: %.2f%% of the volume off (was 3.54%% before 0.8.8)" % err, err < 1.2)
	print("SPLIT ACCURACY: ", "PASS" if ok else "FAIL")
	quit()


func check(label: String, good: bool, detail := "") -> void:
	print("%-70s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## The real edit: a shaped 8 m cube, push out one smaller cube (every position in turn), compare what's left with
## (original minus that cell).
func world_check(c: PackedByteArray, sub_p: int) -> Array:
	var w := CubeWorld.new()
	var big := 3
	var S := CubeWorld.size_of(big)
	var s := CubeWorld.size_of(sub_p)
	var parent_planes := CubeWorld.solid_planes(c)
	var worst := [0.0, Vector3i.ZERO]
	var cells := S / s
	for cx in cells:
		for cy in cells:
			for cz in cells:
				w.clear()
				w.set_cell(Vector3i.ZERO, big, c, CubeWorld.blank_tex())
				var cell := Vector3i(cx, cy, cz) * s
				w.push(CubeWorld.make_sel(cell, sub_p, 3))
				var ps := {}
				for k in w.leaves:
					var cc: PackedByteArray = w.leaves[k][0]
					ps[k] = [cc, Vector3(k.x, k.y, k.z), float(CubeWorld.size_of(k.w)), CubeWorld.solid_planes(cc)]
				var bad := 0
				var solid := 0
				var M := 16
				for i in M:
					for j in M:
						for k in M:
							var pt := (Vector3(i, j, k) + Vector3(0.5, 0.5, 0.5)) * (float(S) / M)
							var in_cell := pt.x >= cell.x and pt.x < cell.x + s and pt.y >= cell.y and pt.y < cell.y + s and pt.z >= cell.z and pt.z < cell.z + s
							var a := inside(c, parent_planes, pt * (8.0 / S)) and not in_cell
							var b := false
							for q in range(sub_p, big + 1):
								var qs := CubeWorld.size_of(q)
								var key := Vector4i(floori(pt.x / qs) * qs, floori(pt.y / qs) * qs, floori(pt.z / qs) * qs, q)
								if ps.has(key):
									var p: Array = ps[key]
									b = inside(p[0], p[3], (pt - p[1]) * (8.0 / p[2]))
									break
							if a:
								solid += 1
							if a != b:
								bad += 1
				var e := float(bad) / maxf(solid, 1.0) * 100.0
				if e > worst[0]:
					worst = [e, Vector3i(cx, cy, cz)]
	return worst
