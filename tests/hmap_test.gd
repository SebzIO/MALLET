extends SceneTree
## Heightmap terrain must stay a height field: raising / lowering with the brushes may never leave a cube hanging
## over empty space (the "floating sheets" the user reported in 0.8.9: a cube built on top of one that was only partly
## full). Like Sauerbraten, a column's corners are kept to one layer of cubes (or one corner diagonally into the next)
## and cubes on a slope only cover the part of their cell that's full underneath.
## Raises and lowers bumps with every brush on a 1 m grid block, then scans hundreds of vertical lines: each must be
## solid from the ground up to the surface in one piece.
## Run: godot --headless --path . -s res://tests/hmap_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-66s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func solid_at(w: CubeWorld, pt: Vector3) -> bool:
	var k = w.leaf_at(pt)
	if k == null:
		return false
	var u: Vector3 = (pt - Vector3(k.x, k.y, k.z)) / CubeWorld.size_of(k.w) * 8.0
	for pl in CubeWorld.leaf_planes(w.leaves[k]):
		if (pl[0] as Vector3).dot(u) - float(pl[1]) > 1e-4:
			return false
	return true


## [lines checked, lines with a gap under solid, worst gap description]
func scan(w: CubeWorld, lo: Vector2, hi: Vector2, y0: float, y1: float) -> Array:
	var bad := 0
	var lines := 0
	var first := ""
	var x := lo.x + 0.37
	while x < hi.x:
		var z := lo.y + 0.61
		while z < hi.y:
			lines += 1
			var was_air := false
			var y := y1
			var top := -INF
			while y > y0:                                 # downwards: once solid, never air again
				var s := solid_at(w, Vector3(x, y, z))
				if s and top == -INF:
					top = y
				if top != -INF and not s:
					was_air = true
				if was_air and s:
					bad += 1
					if first == "":
						first = "(x %.2f z %.2f: air under the surface below y %.2f ticks)" % [x, z, top]
					break
				y -= 0.5
			z += 3.0
		x += 3.0
	return [lines, bad, first]


## The height (ticks) of the surface at a point, like build mode's aim.
func surface_y(w: CubeWorld, x: int, z: int) -> int:
	var y := 200.0
	while y > -128.0:
		if solid_at(w, Vector3(x + 0.5, y, z + 0.5)):
			return int(y)
		y -= 0.5
	return 0


func _run() -> void:
	var p := 0                                            # 1 m grid (8 ticks)
	for b in [0, 1, 2, 5]:                                # Point, Small round, Round, Big square
		var w := CubeWorld.new()
		w.set_cell(Vector3i(0, -128, 0), 4, CubeWorld.FULL, CubeWorld.blank_tex())    # a 16 m block (on its grid), top at y 0
		var brush: Array = CubeWorld.BRUSHES[b][1]
		var rng := RandomNumberGenerator.new()
		rng.seed = 11 + b
		for n in 10:
			var cx := rng.randi_range(3, 13) * 8
			var cz := rng.randi_range(3, 13) * 8
			var dir := -1 if n < 7 else 1                 # raise mostly, then lower some
			for i in rng.randi_range(3, 10):
				w.hmap_edit(Vector3i(cx, 0, cz), surface_y(w, cx, cz), p, brush, dir)   # aimed at the surface, as in build mode
		for i in 2:
			w.hmap_edit(Vector3i(64, 0, 64), surface_y(w, 64, 64), p, [], 1)   # and smooth the middle
		var all_valid := true
		for k in w.leaves:
			all_valid = all_valid and CubeWorld.is_valid_shape(w.leaves[k][0])
		var raised := 0
		for k in w.leaves:
			if k.y >= 0:
				raised += 1
		check("%s brush: the terrain was raised" % CubeWorld.BRUSHES[b][0], raised > 10, "(%d cubes above the block)" % raised)
		var r := scan(w, Vector2(4, 4), Vector2(124, 124), -60.0, 200.0)
		check("%s brush: every cube valid" % CubeWorld.BRUSHES[b][0], all_valid)
		check("%s brush: terrain is solid all the way down (%d lines)" % [CubeWorld.BRUSHES[b][0], r[0]], r[1] == 0,
			"%d lines with air under the surface %s" % [r[1], r[2]])
	print("HMAP: ", "PASS" if ok else "FAIL")
	quit()
