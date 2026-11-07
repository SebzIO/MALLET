extends SceneTree
## Ramp creator (0.14): custom cross-sections and shaped ends (geometry rules, following angle / face length /
## stretching), every starter ramp prefab builds cleanly, the creator window (profile points, ends, apply / new ramp,
## locked ramps refused), saving / sharing / importing prefabs with thumbnails, save + load + undo, the jump
## checker's exit, and both exports. Saves pictures of the creator.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/ramp_creator_test.gd -- <out folder>

var ok := true
const SPINE := [Vector3(-60, 40, 0), Vector3(0, 30, 10), Vector3(60, 20, 0)]


func check(label: String, good: bool, detail := "") -> void:
	print("%-76s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func build(d: Dictionary, pts := SPINE) -> Dictionary:
	return RampShape.build(PackedVector3Array(pts), RampShape.spec(d))


func no_nan(geo: Dictionary) -> bool:
	for ring in geo["rings"]:
		for q in ring:
			if is_nan(q.x) or is_nan(q.y) or is_nan(q.z):
				return false
	return true


func width_at(geo: Dictionary, i: int) -> float:
	var ring: PackedVector3Array = geo["rings"][i]
	var lo := INF
	var hi := -INF
	var r: Vector3 = geo["rights"][i]
	for q in ring:
		lo = minf(lo, q.dot(r))
		hi = maxf(hi, q.dot(r))
	return hi - lo


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	RampPrefabs.user_dir = out.path_join("ramp_prefabs") + "/"
	for f in DirAccess.get_files_at(RampPrefabs.user_dir) if DirAccess.dir_exists_absolute(RampPrefabs.user_dir) else []:
		DirAccess.remove_absolute(RampPrefabs.user_dir + f)
	for f in DirAccess.get_files_at(RampPrefabs.user_dir + ".thumbs") if DirAccess.dir_exists_absolute(RampPrefabs.user_dir + ".thumbs") else []:
		DirAccess.remove_absolute(RampPrefabs.user_dir + ".thumbs/" + f)

	# ---- geometry
	var plain := build({})
	var plain2 := build(RampPrefabs.design_of({}))
	check("a plain design builds exactly the old ramp", plain["rings"] == plain2["rings"] and plain["triangles"] == plain2["triangles"])
	var starters := RampPrefabs.list()
	check("eleven starter ramp prefabs", starters.size() == 11, str(starters.size()))
	var bad := []
	for it in starters:
		for solid in [false, true]:
			var d: Dictionary = it["design"].duplicate(true)
			d["solid"] = solid
			var geo := build(d)
			var probs := RampShape.self_check(RampShape.spec(d), geo)
			if geo["triangles"] == 0 or not no_nan(geo) or not probs.is_empty():
				bad.append("%s%s: %s" % [it["name"], " (solid)" if solid else "", probs])
	check("every starter builds hollow and solid: no NaN, no folds, rules hold", bad.is_empty(), str(bad))
	var bulge := {"profile": {"left": [[0.5, 0.05]]}}
	var g56 := build(bulge)
	var spec70 := RampShape.spec({"profile": {"left": [[0.5, 0.05]]}, "angle": 70.0, "face_length": 14.0})
	var pts70: PackedVector2Array = RampShape.profile(spec70)["pts"]
	var a := deg_to_rad(70.0)
	var want := Vector2(-cos(a), -sin(a)) * 14.0 * 0.5 + Vector2(-sin(a), cos(a)) * 14.0 * 0.05
	var found := false
	for q in pts70:
		found = found or q.distance_to(want) < 1e-3
	check("a face point follows the angle and face length (t, n of the face)", found)
	check("...and the edges stay where the angle / face length put them", absf(pts70[0].x - 14.0 * cos(a)) < 1e-3
		and absf(pts70[0].y + 14.0 * sin(a)) < 1e-3)
	var flat := RampShape.spec({"profile": {"top": 4.0}})
	var fp: PackedVector2Array = RampShape.profile(flat)["pts"]
	check("a flat top adds its width between the faces", absf(fp[0].x - fp[3].x - (plain["profile"]["pts"][0].x - plain["profile"]["pts"][2].x) - 4.0) < 1e-3)
	check("a custom cross-section reaches deeper when it bulges down", RampShape.depth_below_spine(RampShape.spec({"profile": {"left": [[0.9, -0.3]]}, "solid": true}))
		> RampShape.depth_below_spine(RampShape.spec({"solid": true})))
	var taper := build({"ends": {"start": {"shape": "taper", "length": 25.0}}})
	var full := width_at(plain, 40)
	check("a tapered start begins as a sliver and is full width 25 m in", width_at(taper, 0) < full * 0.1 and absf(width_at(taper, 40) - full) < 0.01,
		"%.2f / %.2f / %.2f" % [width_at(taper, 0), width_at(taper, 40), full])
	var rounded := build({"ends": {"end": {"shape": "round", "length": 10.0}}})
	var n: int = rounded["ridge"].size()
	check("a rounded end is half width a little before the end (quarter circle)", width_at(rounded, n - 2) < full * 0.6 and width_at(rounded, n - 11) > full * 0.95)
	var flare := build({"ends": {"end": {"shape": "flare", "length": 18.0, "amount": 0.6}}})
	check("a flared end is 60% wider at the very end", absf(width_at(flare, n - 1) - full * 1.6) < 0.05)
	var lip := build({"ends": {"end": {"lip": 2.0, "lip_length": 12.0}}})
	check("a lip lifts the end 2 m and nothing 12 m back", absf(lip["ridge"][n - 1].y - plain["ridge"][n - 1].y - 2.0) < 1e-3
		and absf(lip["ridge"][n - 15].y - plain["ridge"][n - 15].y) < 1e-3)
	check("...so the jump checker launches riders upward", JumpCheck.exit_of(lip["ridge"])[1].y > JumpCheck.exit_of(plain["ridge"])[1].y + 0.05)
	var cut := build({"ends": {"end": {"cut": 35.0}}})
	var e := n - 1
	var th: Vector3 = Vector3(cut["tan"][e].x, 0, cut["tan"][e].z).normalized()
	var nrm := th.rotated(Vector3.UP, deg_to_rad(35.0))
	var on_plane := true
	var beyond := 0
	for i in n:
		for q in cut["rings"][i]:
			var sd: float = (q - cut["ridge"][e]).dot(nrm)
			if i == e and absf(sd) > 1e-3:
				on_plane = false
			if sd > 1e-3:
				beyond += 1
	check("a diagonal cut lays the end on a plane turned 35°", on_plane)
	check("...and nothing sticks out past it", beyond == 0)
	check("...without false fold warnings", cut["folds"].is_empty())
	var closed := build({"ends": {"start": {"closed": true}, "end": {"closed": true}}})
	check("closed ends add two caps to a hollow ramp", closed["closures"].size() == 2 and closed["triangles"] > plain["triangles"])
	var closed_half := build({"style": "half_left", "ends": {"end": {"closed": true}}})
	check("...a half ramp too (down its back wall)", closed_half["closures"].size() == 1 and (closed_half["closures"][0] as PackedVector3Array).size() == 3)
	var stretched := build({"ends": {"start": {"shape": "taper", "length": 25.0}}}, [Vector3(-120, 40, 0), Vector3(0, 30, 30), Vector3(120, 20, 0)])
	check("stretching a ramp keeps the taper 25 m long (meters from its end)", width_at(stretched, 0) < full * 0.1
		and absf(width_at(stretched, 30) - full) < 0.01)

	# ---- the editor and the creator
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._add_ramp_clicked()
	var r: RampNode = ed.selected
	var pts_before := r.points
	ed._open_ramp_creator()
	await process_frame
	var rc: RampCreator = ed.ramp_creator
	check("the ramp creator opens over the editor with the ramp's design", rc.visible and rc.has_target and not rc._apply.disabled)
	check("...listing the starter prefabs", rc.library.item_count == 11)
	for i in 30:
		await process_frame
	check("...and makes their thumbnails", FileAccess.file_exists(RampPrefabs.user_dir + ".thumbs/04_booster_lip.png")
		and rc.library.get_item_icon(3) != null)
	rc._library_picked(3)
	check("picking 'Booster lip' loads it", rc.design_name == "Booster lip" and rc.design["ends"]["end"]["lip"] == 2.0)
	var undo_n: int = ed._undo.size()
	rc._apply.pressed.emit()
	await process_frame
	check("Apply gives the selected ramp the design, keeping its points", r.ends["end"]["lip"] == 2.0 and r.points == pts_before
		and r.design == "Booster lip" and not rc.visible)
	check("...as one undo step", ed._undo.size() == undo_n + 1)
	check("...and the panel names it", String(ed._fields["ramp_design"].text).begins_with("Booster lip:") and not ed._fields["ramp_plain"].disabled)
	var lifted: float = r.ridge[r.ridge.size() - 1].y - r.points[r.points.size() - 1].y
	r.points[r.points.size() - 1] += Vector3(30, -5, 10)
	r.rebuild()
	check("dragging its end point: still lifted 2 m at the end", absf(r.ridge[r.ridge.size() - 1].y - r.points[r.points.size() - 1].y - lifted) < 1e-3)
	r.angle = 64.0
	r.angle_right = 64.0
	r.rebuild()
	check("changing its angle keeps the lip", absf(r.ridge[r.ridge.size() - 1].y - r.points[r.points.size() - 1].y - 2.0) < 1e-3)
	var md: Dictionary = ed._map_dict()
	ed._load_dict(JSON.parse_string(JSON.stringify(md)))
	await process_frame
	var r2: RampNode = ed.ramps_root.get_child(0)
	check("saved and loaded, the ramp keeps its design", r2.ends.get("end", {}).get("lip", 0.0) == 2.0 and r2.design == "Booster lip")
	ed._select(r2)
	ed.undo()
	await process_frame
	var r3: RampNode = ed.ramps_root.get_child(0)
	check("undo takes the design off again", r3.ends.is_empty())
	ed._select(r3)
	ed._open_ramp_creator()
	rc._library_picked(5)                                 # curved faces
	check("'Curved faces' loads a mirrored cross-section", rc.design["profile"]["left"].size() == 5 and rc.design["profile"]["same"])
	rc.canvas.size = Vector2(400, 260)
	rc.canvas.queue_redraw()
	await process_frame
	rc.canvas.move_point("right", 2, [0.5, -0.1])
	check("dragging a right-face point with 'same' on moves both faces", is_equal_approx(rc.design["profile"]["left"][2][1], -0.1)
		and is_equal_approx(rc.design["profile"]["right"][2][1], -0.1))
	rc.canvas.remove_point("left", 0)
	check("right-click removes a point", rc.design["profile"]["left"].size() == 4)
	var mid_left: Vector2 = rc.canvas._xf * (Vector2(-cos(deg_to_rad(56.0)), -sin(deg_to_rad(56.0))) * 10.5 * 0.1)
	rc.canvas.add_point_at(mid_left)
	check("double-click on a face adds a point there", rc.design["profile"]["left"].size() == 5 and absf(rc.design["profile"]["left"][0][0] - 0.1) < 0.02,
		str(rc.design["profile"]["left"][0]))
	rc._ctl["same"].button_pressed = false
	rc.canvas.move_point("right", 0, [0.3, 0.1])
	check("with 'same' off the faces differ", rc.design["profile"]["left"] != rc.design["profile"]["right"])
	rc._ctl["end_cut"][1].value = 30.0
	rc._ctl["start_shape"].select(1)
	rc._ctl["start_shape"].item_selected.emit(1)
	check("the end controls change the design", rc.design["ends"]["end"]["cut"] == 30.0 and rc.design["ends"]["start"]["shape"] == "taper")
	check("...and show only what applies (no 'how much wider' for a taper)", not rc._ctl["start_amount"][3].visible and rc._ctl["start_length"][3].visible)
	rc.canvas.move_point("left", 2, [0.5, 0.55])
	check("a point pulled far out leaves a part too flat to surf: warned", rc._status.text.contains("flatter than 45.6"), rc._status.text)
	rc.canvas.move_point("left", 2, [0.5, -0.03])
	var path: String = await rc.save_prefab("My test ramp", "for the test")
	check("Save as a prefab writes the file and its thumbnail", FileAccess.file_exists(path) and FileAccess.file_exists(path.get_basename() + ".png"))
	check("...and it shows in the list as yours", rc.library.item_count == 12 and rc.library.get_item_text(11).contains("(yours)"))
	var shared := out.path_join("shared.malletramp")
	check("sharing it writes a .malletramp file", RampPrefabs.export_file(path, shared) and RampPrefabs.read(shared)["name"] == "My test ramp")
	var imported := RampPrefabs.import_file(shared)
	check("importing it gives a second copy (no overwrite)", imported.ends_with("my_test_ramp_2.malletramp"))
	check("a file that isn't a ramp prefab is refused", RampPrefabs.import_file(out.path_join("ramp_prefabs/my_test_ramp.png")) == "")
	RampPrefabs.remove(imported)
	check("deleting one of yours removes it", not FileAccess.file_exists(imported))
	ed._fields["head"].text = ""
	await _shot(ed, out.path_join("ramp_creator.png"))
	rc.new_ramp_requested.emit(rc.design.duplicate(true), "My test ramp")
	await process_frame
	check("Add as a new ramp makes a second ramp with the design", ed.ramps_root.get_child_count() == 2
		and (ed.selected as RampNode).design == "My test ramp" and RampShape.custom_profile((ed.selected as RampNode).shape_spec()))
	var nr: RampNode = ed.selected
	ed._plain_ramp_clicked()
	check("Plain again clears the design", nr.profile.is_empty() and nr.ends.is_empty() and nr.design == "")
	# a locked ramp is refused
	nr.points = PackedVector3Array([Vector3(-60, 40, 0), Vector3(0, 30, 0), Vector3(60, 20, 0)])
	nr.rebuild()
	ed.selected_point = 1
	ed._lock_clicked()
	ed._open_ramp_creator()
	check("a locked ramp: Apply is off and says why", rc._apply.disabled and rc._apply.tooltip_text.contains("Unlock"))
	ed.apply_design(RampPrefabs.read("res://ramp_prefabs/04_booster_lip.malletramp")["design"], "x")
	check("...and refused if asked anyway", nr.ends.is_empty())
	rc.hide()

	# ---- exports
	var map := {"format": "mallet-map", "version": 2, "environment": Look.default_environment(), "props": [], "texts": [], "blocks": [],
		"entities": [{"kind": "start", "position": [0, 60, -150], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 150], "size": [40, 2, 40], "yaw": 0.0}], "ramps": []}
	var z := -100.0
	for it in starters:
		var rd: Dictionary = it["design"].duplicate(true)
		rd["points"] = [[-40, 40, z], [0, 34, z + 4], [40, 28, z]]
		map["ramps"].append(rd)
		z += 22.0
	var scene := SurfsUpExporter.build_scene(map, "ramp_creator_test")
	check("SurfsUp: every starter ramp is in the map with collision", scene.get_node("Ramps").get_child_count() == 11
		and scene.get_node("Ramps").get_child(3).get_node("Collision").shape != null)
	var ps := PackedScene.new()
	check("SurfsUp: the scene packs", ps.pack(scene) == OK)
	scene.free()
	var vx := VmfExporter.new()
	var text := vx.build(map)
	check("CS:S: the map with every starter exports", text != "", str(vx.warnings))
	var plain_vx := VmfExporter.new()
	var plain_map := map.duplicate(true)
	plain_map["ramps"] = [map["ramps"][0]]
	plain_vx.build(plain_map)
	var closed_map := map.duplicate(true)
	closed_map["ramps"] = [map["ramps"][9]]
	var closed_vx := VmfExporter.new()
	closed_vx.build(closed_map)
	check("CS:S: closed ends become two extra brushes", closed_vx.brushes == plain_vx.brushes + 2, "%d vs %d" % [closed_vx.brushes, plain_vx.brushes])

	ed.queue_free()
	await process_frame
	print("ramp_creator_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _shot(ed, path: String) -> void:
	ed.ramp_creator.show()
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
