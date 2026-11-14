extends SceneTree
## The Geometry menu (0.19.8): shapes turn (yaw, pitch, roll) and stay exact (a box turned 30 degrees has the same
## surface as before); shapes the octree can't make whole are refused with the reason (too many sides for the size,
## thinner than the finest cube); quarter pipes and halfpipes are concave, with their curve where it should be and
## no holes; and a shape with its settings is kept as a preset.
## Run: godot --path . --resolution 1280x720 -s res://tests/geo_gen_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


## The surface as built (the cubes in a CubeWorld, meshed as build mode draws them), m2.
func area(cells: Array) -> float:
	var w := CubeWorld.new()
	ShapeGen.place(w, cells, Vector3i.ZERO, "")
	var a := 0.0
	for ck in w.render_chunks():
		var c: PackedVector3Array = w.chunk_mesh(ck)[1]
		for i in range(0, c.size(), 3):
			a += (c[i + 1] - c[i]).cross(c[i + 2] - c[i]).length() * 0.5
	return a


## Where a ray straight down at (x, z) first meets the shape's surface (preview triangles), or -INF.
func surface_y(cells: Array, x: float, z: float) -> float:
	var v: PackedVector3Array = ShapeGen.preview_arrays(cells)[0]
	var best := -INF
	for i in range(0, v.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(Vector3(x, 1000.0, z), Vector3.DOWN, v[i], v[i + 1], v[i + 2])
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best


func _run() -> void:
	# turning
	var pr := ShapeGen.generate("prism", {"w": 4.0, "h": 3.0, "l": 12.0}, 0, 1)
	check("a prism is as long as its Length (it used to stay 4)", pr.has("size") and is_equal_approx((pr["size"] as Vector3).z, 12.0), str(pr.get("size")))
	var plain := ShapeGen.generate("box", {"w": 4.0, "h": 2.0, "d": 3.0}, 0, 2)
	var turned := ShapeGen.generate("box", {"w": 4.0, "h": 2.0, "d": 3.0, "yaw": 30.0, "pitch": 10.0}, 0, 3)
	var a0 := area(plain["cells"])
	var a1 := area(turned["cells"])
	check("a turned box comes out whole: the same surface as the plain one (52 m2)", absf(a0 - 52.0) < 0.05 and absf(a1 - 52.0) < 52.0 * 0.03,
		"(%.2f / %.2f m2)" % [a0, a1])
	check("...and is bigger in its box (it's turned)", (turned["size"] as Vector3).x > 4.2)
	check("spheres and stairs don't offer turning", not "yaw" in ShapeGen.defaults("sphere") and not "yaw" in ShapeGen.defaults("stairs")
		and "yaw" in ShapeGen.defaults("cone"))
	# the octree's own test: what it can make whole is shown, what it can't is refused with the reason
	check("a thin slab and a many-sided cone are fine (cut cubes hold them exactly)",
		String(ShapeGen.generate("box", {"w": 4.0, "h": 0.25, "d": 4.0}, 0, 1)["error"]) == ""
		and String(ShapeGen.generate("cone", {"r": 1.0, "h": 4.0, "sides": 64.0}, 0, 0)["error"]) == "")
	var tiny := ShapeGen.generate("quarter_pipe", {"l": 4.0, "r": 0.5, "t": 0.0, "deck": 0.0}, 0, 0)
	check("a curve too small for the cubes it's cut from is refused, with the reason", (tiny["cells"] as Array).is_empty()
		and String(tiny["error"]).contains("can't make this whole"), String(tiny["error"]))
	check("...and fine with more detail", String(ShapeGen.generate("quarter_pipe", {"l": 4.0, "r": 0.5, "t": 0.0, "deck": 0.0}, 0, 3)["error"]) == "")
	# quarter pipe: R 4, floor 0.5, the curve's center at y 4.5, z 0
	var qp := ShapeGen.generate("quarter_pipe", {"l": 4.0, "r": 4.0, "t": 0.5, "deck": 1.0}, 0, 3)
	check("a quarter pipe is built", String(qp["error"]) == "" and (qp["cells"] as Array).size() > 10, String(qp["error"]))
	var ok_curve := true
	var worst := 0.0
	for z in [0.5, 1.5, 2.5, 3.2]:
		var want := 4.5 - sqrt(16.0 - z * z)
		var got := surface_y(qp["cells"], 2.0, z)
		worst = maxf(worst, absf(got - want))
		ok_curve = ok_curve and absf(got - want) < 0.15
	check("...its curve is where the circle is (concave, rising to the back)", ok_curve, "(off by up to %.2f m)" % worst)
	check("...with the deck flat behind it", absf(surface_y(qp["cells"], 2.0, 4.5) - 4.5) < 0.05)
	# halfpipe: R 3, flat 2, floor 0.5
	var hp := ShapeGen.generate("halfpipe", {"l": 4.0, "r": 3.0, "flat": 2.0, "t": 0.5}, 0, 3)
	var mid_y := surface_y(hp["cells"], 2.0, 4.0)
	var wall_y := surface_y(hp["cells"], 2.0, 0.6)
	var other_y := surface_y(hp["cells"], 2.0, 7.4)
	check("a halfpipe: flat in the middle, the same curve up both sides", absf(mid_y - 0.5) < 0.05 and absf(wall_y - other_y) < 0.1 and wall_y > 1.5,
		"(middle %.2f, sides %.2f / %.2f)" % [mid_y, wall_y, other_y])
	var holes := 0
	for i in 40:
		var z := 0.1 + i * 0.195
		if surface_y(hp["cells"], 1.3, z) == -INF:
			holes += 1
	check("...and no holes across it", holes == 0, "(%d rays fell through)" % holes)
	# presets
	Presets.PATH = "user://presets_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Presets.PATH))
	Presets.save("shape", "Big pipe", {"shape": "halfpipe", "values": {"l": 12.0, "r": 6.0, "flat": 4.0, "t": 1.0, "yaw": 90.0}, "detail": 3})
	var p: Dictionary = Presets.all("shape")["Big pipe"]
	check("a shape preset keeps the shape, its values and its turn", p["shape"] == "halfpipe" and float(p["values"]["yaw"]) == 90.0 and int(p["detail"]) == 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Presets.PATH))
	print("geo_gen_test: ", "PASS" if ok else "FAIL")
	quit()
