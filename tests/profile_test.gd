extends SceneTree
## Ramp profile rules: every case is built and run through RampShape.self_check (level right vector, upright
## profile, face lengths and angles exactly as set, level bar, apex above the middle, no NaNs, no folds), plus:
## a too-tight bend must be caught, faces must face outwards (a downward ray hits the riding face from above with
## back faces ignored), arc-length spacing must be even, and the width/height <-> angle/length conversion holds.
## Run: godot --path D:/SurfForge --headless -s res://tests/profile_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func pts(a: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in a:
		out.append(Vector3(p[0], p[1], p[2]))
	return out


func case(name: String, points: PackedVector3Array, settings: Dictionary, expect_folds := false) -> Dictionary:
	var sp := RampShape.spec(settings)
	var res := RampShape.build(points, sp)
	var problems := RampShape.self_check(sp, res)
	var folded: bool = not res["folds"].is_empty()
	if expect_folds:
		problems = PackedStringArray(Array(problems).filter(func(p): return not p.contains("folds")))
	var good := problems.is_empty() and folded == expect_folds
	# even spacing by arc length: every gap within 2% of the average (the spine is a curve, so chords are a hair
	# shorter than the arc on bends)
	var ridge: PackedVector3Array = res["ridge"]
	var avg := RampShape.path_length(ridge) / (ridge.size() - 1)
	var worst := 0.0
	for i in range(1, ridge.size()):
		worst = maxf(worst, absf(ridge[i].distance_to(ridge[i - 1]) - avg) / avg)
	good = good and worst < 0.02
	print("%-34s stations %4d  spacing spread %.2f%%  folds %3d  %s" % [name, ridge.size(), worst * 100.0, res["folds"].size(),
		"OK" if good else "FAIL " + str(problems)])
	ok = ok and good
	return res


func _run() -> void:
	var straight := pts([[0, 100, 0], [0, 80, -80], [0, 60, -160]])
	var curved := pts([[0, 100, 0], [40, 90, -80], [-20, 80, -160], [30, 70, -240]])
	var climb := pts([[0, 0, 0], [0, 40, -40], [0, 80, -80]])               # 45 degree climb
	var spiral: PackedVector3Array = RampGenerator.generate("spiral", {"radius": 60.0, "turns": 1.2, "drop": -60.0, "hand": 0.0, "run_in": 20.0},
		Vector3(0, 50, 0), 30.0)["points"]                                   # turning while climbing
	var vertical := pts([[0, 100, 0], [0, 60, -0.001], [0, 20, -40]])      # a stretch that points straight down
	var tight := pts([[0, 100, 0], [10, 98, -10], [0, 96, -20]])           # hairpin far tighter than the face width

	case("straight V hollow", straight, {})
	case("curved V solid + base", curved, {"solid": true, "base_depth": 6.0})
	case("45 deg climb, vertical slice", climb, {})
	case("45 deg climb, perpendicular", climb, {"slice": "perpendicular"})
	case("spiral climbing (combined)", spiral, {"angle": 60.0, "face_length": 9.0})
	case("half ramp, left face, solid", curved, {"style": "half_left", "solid": true, "base_depth": 4.0})
	case("half ramp, right face, hollow", curved, {"style": "half_right"})
	case("near-vertical stretch (no NaN)", vertical, {})
	case("Freeform: uneven faces", curved, {"freeform": true, "angle": 50.0, "angle_right": 65.0, "face_length_right": 14.0})
	# a twist in an old file is ignored: ramps never roll, even in Freeform
	case("old twist value is ignored (stays level)", straight, {"freeform": true, "twist": 30.0})
	case("too-tight bend is caught", tight, {}, true)
	# Freeform off ignores right-face values
	var sp := RampShape.spec({"angle_right": 70.0})
	var snapped: bool = sp["angle_right"] == sp["angle"] and not sp.has("twist")
	print("Freeform off snaps the right face back (and there is no twist setting): ", snapped)
	ok = ok and snapped

	# width / height conversion (tests and older files still describe ramps that way)
	var conv := RampShape.spec({"width": 13.0, "height": 8.125})
	var back_w: float = 2.0 * conv["face_length"] * cos(deg_to_rad(conv["angle"]))
	var good_conv := absf(back_w - 13.0) < 1e-4 and absf(conv["face_length"] * sin(deg_to_rad(conv["angle"])) - 8.125) < 1e-4
	print("width/height conversion: angle %.2f, face %.3f  %s" % [conv["angle"], conv["face_length"], "OK" if good_conv else "FAIL"])
	ok = ok and good_conv

	# outward-facing riding surfaces: with back faces ignored, a ray straight down onto the middle of each face
	# must hit it (it would pass through a face wound the wrong way)
	var root3d := Node3D.new()
	root.add_child(root3d)
	var hits := []
	for style in ["v", "half_left", "half_right"]:
		for solid in [false, true]:
			var r := RampNode.new()
			root3d.add_child(r)
			r.from_dict({"points": [[0, 100, 0], [0, 80, -80], [0, 60, -160]], "style": style, "solid": solid})
			r.position = Vector3(hits.size() * 100.0, 0, 0)
			hits.append([style, solid, r])
	for i in 3:
		await physics_frame
	var space := root3d.get_world_3d().direct_space_state
	for h in hits:
		var r: RampNode = h[2]
		var good := true
		for side in ([-1.0, 1.0] if h[0] == "v" else ([-1.0] if h[0] == "half_left" else [1.0])):
			var mid := r.position + Vector3(side * 3.0, 100, -80)
			var q := PhysicsRayQueryParameters3D.create(mid, mid + Vector3.DOWN * 200.0)
			q.hit_back_faces = false
			var hit := space.intersect_ray(q)
			var on_face: bool = not hit.is_empty() and hit["normal"].y > 0.3 and absf(hit["position"].y - (80.0 - 3.0 * tan(deg_to_rad(56.0)))) < 0.6
			good = good and on_face
		print("faces point outwards: %-10s %-6s %s" % [h[0], "solid" if h[1] else "hollow", "OK" if good else "FAIL"])
		ok = ok and good
	print("PROFILE: ", "PASS" if ok else "FAIL")
	quit()
