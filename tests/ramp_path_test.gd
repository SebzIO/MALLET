extends SceneTree
## Ramp paths and frames (0.19.6): the "corners" path (new ramps) runs straight from point to point and is rounded
## only near each one (the smooth curve sags under the lines and flares up at the end); a steep drop keeps its shape
## around the spine instead of collapsing (a vertical slice can't hold one), while ramps under 40 degrees ride exactly
## as before; the ramp creator starts straight; a ramp turns around its middle (pitch, yaw) and banks (roll); maps
## made before keep their smooth curves.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/ramp_path_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func ridge_y_at(geo: Dictionary, x: float) -> float:
	var ridge: PackedVector3Array = geo["ridge"]
	for i in range(1, ridge.size()):                     # (between the two stations around x)
		var a: Vector3 = ridge[i - 1]
		var b: Vector3 = ridge[i]
		if (a.x - x) * (b.x - x) <= 0.0 and absf(b.x - a.x) > 1e-6:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return INF


func _run() -> void:
	var pts := PackedVector3Array([Vector3(0, 0, 0), Vector3(30, -15, 0), Vector3(60, -15, 0)])
	var corners := RampShape.build(pts, RampShape.spec({"path": "corners"}))
	var smooth := RampShape.build(pts, RampShape.spec({}))
	var yc := ridge_y_at(corners, 48.0)
	var ys := ridge_y_at(smooth, 48.0)
	check("corners: straight along the flat stretch (no sag under the line)", absf(yc + 15.0) < 0.05, "(y %.2f)" % yc)
	check("...where the smooth curve dips under it", ys < -15.3, "(y %.2f)" % ys)
	check("...and straight down the first stretch too", absf(ridge_y_at(corners, 12.0) + 6.0) < 0.05, "(y %.2f)" % ridge_y_at(corners, 12.0))
	check("...rounded near the middle point (not a sharp kink)", ridge_y_at(corners, 30.0) > -15.0 + 0.3, "(y %.2f)" % ridge_y_at(corners, 30.0))
	# a straight drop: the cross-section turns with the spine instead of collapsing
	var drop := RampShape.build(PackedVector3Array([Vector3(0, 40, 0), Vector3(0.05, 0, 0), Vector3(40, 0, 0)]),
		RampShape.spec({"path": "corners"}))
	var rings: Array = drop["rings"]
	var ring: PackedVector3Array = rings[rings.size() / 5]
	var span := 0.0
	for a in ring:
		for b in ring:
			span = maxf(span, (a as Vector3).distance_to(b))
	check("a straight drop keeps its width (the cross-section turns with it)", span > 10.0, "(%.1f m)" % span)
	var gentle := RampShape.build(PackedVector3Array([Vector3(0, 20, 0), Vector3(40, 5, 3), Vector3(80, 0, 0)]), RampShape.spec({}))
	var all_up := true
	for u in (gentle["ups"] as PackedVector3Array):
		all_up = all_up and (u as Vector3).is_equal_approx(Vector3.UP)
	check("a ramp under 40 degrees: vertical slices, exactly as before", all_up)
	# the creator starts straight
	var z_flat := true
	for p in RampCreator.PREVIEW_SPINE:
		z_flat = z_flat and is_zero_approx((p as Vector3).z)
	check("the ramp creator starts with a straight ramp", z_flat)
	# turning and banking
	var r := RampNode.new()
	root.add_child(r)
	r.from_dict({"points": [[0, 10, 0], [20, 5, 0], [40, 0, 0]], "path": "corners"})
	r.turn_to(0.0, 90.0)
	check("yaw 90: the ramp turns around its middle", (r.points[2] - r.points[0]).normalized().is_equal_approx(Vector3(0, -0.2425, -0.9701).normalized())
		or absf((r.points[2] - r.points[0]).x) < 0.01, str(r.points))
	check("...and remembers it", is_equal_approx(r.turn.y, 90.0) and is_equal_approx(float(r.to_dict()["turn"][1]), 90.0))
	r.roll = 20.0
	r.rebuild()
	var up0: Vector3 = (r.geometry["ups"] as PackedVector3Array)[3]
	check("roll banks the cross-section", absf(rad_to_deg(up0.angle_to(Vector3.UP)) - 20.0) < 1.0, "(%.1f°)" % rad_to_deg(up0.angle_to(Vector3.UP)))
	# old maps stay smooth, new ramps are even (0.28.0)
	var old := RampNode.new()
	root.add_child(old)
	old.from_dict({"points": [[0, 10, 0], [20, 5, 0], [40, 0, 0]]})
	check("a ramp from an older map keeps its smooth curve", old.path == "smooth")
	var fresh := RampNode.new()
	check("a brand-new ramp uses the even path (0.28.0; corners before)", fresh.path == "even")
	fresh.free()
	print("ramp_path_test: ", "PASS" if ok else "FAIL")
	quit()
