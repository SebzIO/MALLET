extends SceneTree
## The "even" ramp path (0.28.0, new ramps): exactly straight along the line between two points (no dip or bulge),
## one circular arc at each point (constant curvature), arcs that never overlap, and moving a point only reshapes
## the corners next to it. Ramps already on maps keep the path they had.
## Run: godot --path . --resolution 1280x720 -s res://tests/ramp_even_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func path_of(pts: Array, corner := 0.25) -> PackedVector3Array:
	return RampShape._corner_path(PackedVector3Array(pts), 0.25, RampShape.path_corner("even", corner))["pos"]


func dist_to_line(p: Vector3, a: Vector3, b: Vector3) -> float:
	var d := (b - a).normalized()
	var v := p - a
	return (v - d * v.dot(d)).length()


func circumradius(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area := (b - a).cross(c - a).length() * 0.5
	return ab * bc * ca / (4.0 * area) if area > 1e-9 else INF


func _run() -> void:
	# points in a line: the spine is exactly that line
	var line := path_of([Vector3(0, 50, 0), Vector3(50, 45, 0), Vector3(100, 40, 0), Vector3(180, 32, 0)])
	var worst := 0.0
	for p in line:
		worst = maxf(worst, dist_to_line(p, Vector3(0, 50, 0), Vector3(180, 32, 0)))
	check("points in a line: the spine is exactly on the line", worst < 1e-4, "(%.6f m off)" % worst)
	# the first screenshot: points level in the plan (same Z), the slope changing - the spine stays on that line from above
	var plan := path_of([Vector3(-120, 60, 0), Vector3(-40, 52, 0), Vector3(40, 50, 0), Vector3(120, 30, 0)])
	var zoff := 0.0
	for p in plan:
		zoff = maxf(zoff, absf(p.z))
	check("points sharing a Z: seen from above the spine never leaves that line", zoff < 1e-4, "(%.6f m)" % zoff)
	# the second screenshot: a 45° diagonal, then a straight run; the corner is one circular arc
	var a := Vector3(100, 60, -100)
	var b := Vector3(0, 50, 0)
	var c := Vector3(-200, 40, 0)
	var turn := path_of([a, b, c])
	var on_lines := 0
	var arc := []
	for p in turn:
		if dist_to_line(p, a, b) < 1e-4 or dist_to_line(p, b, c) < 1e-4:
			on_lines += 1
		else:
			arc.append(p)
	check("a corner: the rest of each stretch lies exactly on its line", on_lines > turn.size() * 0.5, "(%d of %d points)" % [on_lines, turn.size()])
	var radii := []
	var span: int = maxi(arc.size() / 6, 2)              # (points well apart: 0.25 m apart on a 150 m circle is just float noise)
	for i in range(span, arc.size() - span, maxi(span / 3, 1)):
		radii.append(circumradius(arc[i - span], arc[i], arc[i + span]))
	var rmin := 1e9
	var rmax := 0.0
	for r in radii:
		rmin = minf(rmin, r)
		rmax = maxf(rmax, r)
	check("...and turns in one circular arc (the same radius all the way)", radii.size() >= 3 and rmax / rmin < 1.01,
		"(radius %.2f - %.2f m over %d samples)" % [rmin, rmax, radii.size()])
	var gaps := 0.0
	for i in range(1, turn.size()):
		gaps = maxf(gaps, turn[i].distance_to(turn[i - 1]))
	check("...with no jump between the straights and the arc", gaps < 0.5, "(largest step %.3f m)" % gaps)
	# moving one point only reshapes its neighbors' corners
	var pts := [Vector3(0, 80, 0), Vector3(0, 70, -60), Vector3(40, 60, -120), Vector3(40, 50, -180), Vector3(0, 40, -240), Vector3(0, 30, -300)]
	var before := path_of(pts)
	var moved := pts.duplicate()
	moved[4] = Vector3(-30, 40, -240)
	var after := path_of(moved)
	var same := 0
	var limit := 0
	for i in before.size():                              # (up to where the arc at point 2 ends: untouched)
		if before[i].z > -150.0:
			limit += 1
			if i < after.size() and before[i].is_equal_approx(after[i]):
				same += 1
	check("moving point 4 leaves the spine before point 3's corner as it was", same == limit and limit > 20, "(%d of %d)" % [same, limit])
	# arcs never overlap, even on short stretches
	var tight := path_of([Vector3(0, 50, 0), Vector3(10, 50, 0), Vector3(12, 50, 8), Vector3(30, 50, 8)], 0.5)
	var back := false
	for i in range(2, tight.size()):
		if (tight[i] - tight[i - 1]).dot(tight[i - 1] - tight[i - 2]) < -1e-6:
			back = true
	check("short stretches: the arcs never overlap or double back", not back)
	# new ramps are even, ramps on maps keep theirs
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._add_ramp_clicked()
	await process_frame
	check("a new ramp uses the even path", (ed.selected as RampNode).path == "even")
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 40, -60], [30, 30, -120]]},
		{"points": [[60, 50, 0], [60, 40, -60], [90, 30, -120]], "path": "corners"}]})
	await process_frame
	check("ramps already on a map keep their path (smooth, corners)", ed.ramps_root.get_child(0).path == "smooth"
		and ed.ramps_root.get_child(1).path == "corners")
	var geo := RampShape.build(PackedVector3Array([Vector3(0, 80, 0), Vector3(0, 60, -60), Vector3(60, 40, -120), Vector3(60, 20, -200)]),
		RampShape.spec({"path": "even"}))
	check("an even ramp builds", int(geo["triangles"]) > 50, "(%d triangles)" % int(geo["triangles"]))
	print("ramp_even_test: ", "PASS" if ok else "FAIL")
	quit()
