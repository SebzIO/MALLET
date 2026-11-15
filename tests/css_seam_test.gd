extends SceneTree
## CS:S ramp seams (0.30.1): where a curving ramp's next piece would tilt up against the face being ridden (a valley
## at the seam), Source's player box caught the next piece's front and stopped dead. The exporter now starts such a
## piece a little lower (VmfExporter._seam_drops). Checks: a straight ramp gets no steps, curved ones do, every step is
## enough (the next face stays below the ridden one under the whole box), none hits the limit on ordinary bends, the
## end slabs sit outside the ramp, the ramp you see is a separate non-solid copy (0.30.3), straight stretches are one
## piece, and the maps compile with CS:S's vbsp. (A Source movement check that rides the
## exported ramps: tools/css_ramp_ride.py.)
##   godot --path . --headless -s res://tests/css_seam_test.gd -- <out dir>

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("_run")


func _map(points: Array) -> Dictionary:
	return {"format": "mallet-map", "version": 2, "ramps": [{"points": points}],
		"entities": [{"kind": "start", "position": [-100, 210, 0], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "finish", "position": [0, 60, 200], "size": [40, 2, 40], "yaw": 0.0}]}


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var shapes := {"sf_seam_straight": [[-80, 200, 0], [80, 160, 0]], "sf_seam_curve": [[-80, 200, 0], [0, 170, 0], [0, 140, 80]],
		"sf_seam_s": [[-120, 220, 0], [-40, 200, 30], [40, 180, -30], [120, 160, 0]]}
	var css := VmfExporter.find_css()
	var counts := {}
	for k in shapes:
		var ex := VmfExporter.new()
		var text := ex.build(_map(shapes[k]))
		check(text != "", "%s: exported (%d brushes)" % [k, ex.brushes])
		check(text.contains("\"classname\" \"func_illusionary\"") and text.contains("TOOLS/TOOLSNODRAW"),
			"%s: the ramp you see is not solid, the one you ride is invisible (no slits, no black edges)" % k)
		counts[k] = ex.brushes
		var drops := Array(ex.seam_drops).filter(func(x: float) -> bool: return x > 0.0)
		if k == "sf_seam_straight":
			check(drops.is_empty(), "straight ramp: no steps (%d)" % drops.size())
		else:
			check(drops.size() > 5, "%s: valleys get a step down (%d steps, largest %.2f units)" % [k, drops.size(), drops.max() if not drops.is_empty() else 0.0])
			check(ex.seam_left <= VmfExporter.SEAM_WARN, "%s: every valley is (nearly) covered by its step (%.2f units left)" % [k, ex.seam_left])
			check(Array(ex.warnings).filter(func(w: String) -> bool: return w.contains("bend")).is_empty(), "%s: no sharp-bend warning" % k)
		var path := out.path_join(k + ".vmf")
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		if css != "" and k != "sf_seam_straight":
			var res := VmfExporter.compile(path, css, "fast")
			check(res["error"] == "", "%s: vbsp / vvis / vrad compile it (%s)" % [k, res["error"] if res["error"] != "" else res["bsp"].get_file()])
	check(counts["sf_seam_straight"] * 4 < counts["sf_seam_curve"], "a straight ramp takes far fewer pieces than a bend (%d vs %d brushes; pieces up to %d m)" % [
		counts["sf_seam_straight"], counts["sf_seam_curve"], VmfExporter.PIECE_MAX])
	# the check itself: a seam's next face stays below the ridden one once lowered (and not before)
	var ex2 := VmfExporter.new()
	var p := PackedVector3Array([Vector3(0, 10, 0), Vector3(0, 0, 10), Vector3(0, 0, -10)])
	var m := PackedVector3Array([Vector3(2, 9.8, 0.3), Vector3(2, -0.2, 10.3), Vector3(2, -0.2, -9.7)])
	var q := PackedVector3Array([Vector3(4, 9.6, 0.9), Vector3(4, -0.4, 10.9), Vector3(4, -0.4, -9.1)])
	var pp := PackedVector2Array([Vector2(0, 0), Vector2(1, -1), Vector2(-1, -1)])
	var before := ex2._seam_above(p, m, q, pp, 0.0, 0.0)
	var drops2 := ex2._seam_drops([p, m, q], [0, 1, 2], pp)
	var after := ex2._seam_above(p, m, q, pp, 0.0, drops2[1])
	check(before > 0.0 and after <= -VmfExporter.SEAM_MARGIN / VmfExporter.U + 1e-6,
		"a bend's valley: the next face rises %.3f units over the ridden one, %.3f after a %.2f-unit step" % [before * VmfExporter.U, after * VmfExporter.U, drops2[1] * VmfExporter.U])
	print("css_seam_test: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
