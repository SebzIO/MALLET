extends SceneTree
## CS:S export: the templates and a map with every kind of object are written as .vmf and compiled with the
## vbsp / vvis / vrad that ship with CS:S. Every map must compile without a leak or brush errors, and the hull
## code must wind faces the way Hammer expects (a cube's top face points up).
## Run: godot --path D:/SurfForge --headless -s res://tests/vmf_test.gd -- <out dir>

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-60s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	# Hammer's rule: (p3 - p1) x (p2 - p1) points out. A 128 cube's top face from a real Hammer file:
	var top := [Vector3(-64, 64, 64), Vector3(64, 64, 64), Vector3(64, -64, 64)]
	check("reference: Hammer's cube top face points up", (top[2] - top[0]).cross(top[1] - top[0]).normalized().is_equal_approx(Vector3(0, 0, 1)))   # Source is Z-up
	var cube := VmfExporter._hull(VmfExporter._aabb_corners(Vector3(-64, -64, -64), Vector3(64, 64, 64)))
	var good_faces := cube.size() == 6
	for sd in cube:
		var nrm: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var centre: Vector3 = (sd[0] + sd[1] + sd[2]) / 3.0
		good_faces = good_faces and nrm.dot(centre) > 0.0          # outward from the cube's middle
	check("our hull: 6 faces, all pointing outwards", good_faces)

	var css := VmfExporter.find_css()
	check("CS:S found", css != "", css)
	var maps := {}
	for t in ["2_first_surf", "3_three_stages", "4_aurora_night"]:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://templates/%s.sfmap" % t))
		d.erase("template")
		maps["sf_" + t.substr(2)] = d
	# every kind of object, a locked ramp and a half ramp
	var every := {"format": "surfforge-map", "version": 2, "environment": Look.preset_environment("sunset"), "props": [],
		"ramps": [
			{"points": [[-60, 120, 0], [0, 105, -10], [60, 90, 0], [120, 75, 20]], "frozen": [{"end": 1, "angle": 56.0, "face_length": 10.5,
				"end_ghost": [60, 90, 0], "tangent_lock": true}], "angle": 60.0, "face_length": 12.0},
			{"points": [[-60, 120, 200], [60, 90, 200]], "style": "half_left", "solid": true, "base_depth": 5.0}],
		"entities": [
			{"kind": "start", "position": [-84, 128, 0], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "finish", "position": [200, 40, 0], "size": [40, 2, 40], "yaw": 0.0},
			{"kind": "stage", "number": 2, "position": [-84, 128, 200], "size": [24, 2, 24], "yaw": -90.0},
			{"kind": "teleport", "number": 2, "position": [160, 60, 20], "size": [30, 30, 10], "yaw": 0.0, "keep_speed": true},
			{"kind": "kill", "position": [40, 40, 100], "size": [40, 20, 40], "yaw": 0.0},
			{"kind": "booster", "position": [140, 70, 200], "size": [20, 12, 20], "yaw": 30.0, "pitch": 20.0, "strength": 800.0, "mode": 0}]}
	maps["sf_every_object"] = every
	# sloped cubes with smaller cubes pushed out of them: the exact cut pieces must make valid brushes
	var cw := CubeWorld.new()
	var shapes: Array = load("res://tests/split_accuracy_test.gd").shapes()
	var at := 0
	for s in shapes:
		if s[0] in ["slope 3/8", "slope 5/8", "two-way 6,2", "corner 5/8", "lean 7/8"]:
			var o := Vector3i(at * 80, 0, 0)
			cw.set_cell(o, 3, s[1], CubeWorld.blank_tex())
			cw.push(CubeWorld.make_sel(o + Vector3i(24, 40, 8), -1, 3))
			cw.push(CubeWorld.make_sel(o + Vector3i(32, 32, 32), 0, 3))
			at += 1
	var cuts := 0
	for k in cw.leaves:
		if not CubeWorld._cut_of(cw.leaves[k]).is_empty():
			cuts += 1
	check("split slopes map has exact cut pieces", cuts > 0, "(%d of %d cubes)" % [cuts, cw.leaves.size()])
	maps["sf_split_slopes"] = {"format": "surfforge-map", "version": 2, "environment": Look.preset_environment("sunset"),
		"props": [], "ramps": [], "cube_models": [{"cubes": cw.to_dict(), "position": [-200, 20, -40], "yaw": 0.0}],
		"entities": [{"kind": "start", "position": [-220, 40, 0], "size": [20, 2, 20], "yaw": 0.0},
			{"kind": "finish", "position": [300, 10, 0], "size": [20, 2, 20], "yaw": 0.0}]}
	for name in maps:
		var vmf: String = out + "/css/%s.vmf" % name
		var res := VmfExporter.export_vmf(maps[name], vmf)
		check("%s: written" % name, res["error"] == "", "(%d brushes) %s" % [res["brushes"], res["error"]])
		if res["error"] != "" or css == "":
			continue
		for w in res["warnings"]:
			print("      note: ", w)
		var c := VmfExporter.compile(vmf, css, "fast")
		var log: String = c["log"]
		FileAccess.open(out + "/css/%s.log" % name, FileAccess.WRITE).store_string(log)
		var brush_errors := 0
		for line in log.split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("coplanar") or l.contains("mixed")):
				brush_errors += 1
		check("%s: compiles, no leak, no brush errors" % name, c["error"] == "" and brush_errors == 0,
			"%s %s" % [c["error"], ("(%d brush problems, see log)" % brush_errors) if brush_errors else ""])
	print("VMF: ", "PASS" if ok else "FAIL")
	quit()
