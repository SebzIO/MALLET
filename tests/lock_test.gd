extends SceneTree
## Locking keypoints into sections. Checks:
##  - locking changes nothing on screen (the surface stays where it was)
##  - the locked part is bit-for-bit unchanged after dragging later points and changing the editable section's
##    slope angle / face length (vertex hash before and after)
##  - every seam: same position, no kink (tangent yaw and pitch continue), same `right`, same profile
##  - tangent lock off really does allow a crease (and on prevents it)
##  - the geometry self-check still passes (level right, upright, angles/lengths as set per station, no folds)
##  - locks can't be placed inside a locked part or on the last point; unlock merges; undo/redo round-trips
##  - frozen points can't be dragged, nudged, deleted; Flip is refused; moving the whole ramp is rigid
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/lock_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func shot(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


## Hash of every vertex of the rings from station 0 to `upto` (inclusive).
func frozen_hash(r: RampNode, upto: int) -> int:
	var parts := PackedStringArray()
	for i in upto + 1:
		for q in r.geometry["rings"][i]:
			parts.append("%.4f,%.4f,%.4f" % [q.x, q.y, q.z])
	return "|".join(parts).hash()


## Largest distance from the ridge and both face edges of `a` to the same lines of `b` (point to polyline, so
## differently spaced cross-sections along the same surface measure as zero).
func surface_gap(a: Array, b: Array) -> float:
	var worst := 0.0
	for k in [0, 1, 2]:
		var line := PackedVector3Array()
		for ring in b:
			line.append(ring[k])
		for i in range(0, a.size(), 3):
			var p: Vector3 = a[i][k]
			var best := INF
			for j in range(1, line.size()):
				var c := Geometry3D.get_closest_point_to_segment(p, line[j - 1], line[j])
				best = minf(best, p.distance_to(c))
			worst = maxf(worst, best)
	return worst


func max_diff(a: Array, b: Array) -> float:
	var worst := 0.0
	for i in mini(a.size(), b.size()):
		for k in a[i].size():
			worst = maxf(worst, a[i][k].distance_to(b[i][k]))
	return worst


func turn_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


func move_point(r: RampNode, i: int, by: Vector3) -> void:
	var pts := r.points.duplicate()
	pts[i] += by
	r.points = pts
	r.rebuild()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	r.points = PackedVector3Array([Vector3(0, 200, 0), Vector3(0, 185, -60), Vector3(30, 170, -120), Vector3(10, 155, -180),
		Vector3(40, 140, -240), Vector3(20, 125, -300)])
	r.rebuild()
	ed._select(r)

	# --- lock at point 2: nothing moves
	var before_rings: Array = r.geometry["rings"].duplicate()
	var before_dict: Dictionary = r.to_dict()
	ed.selected_point = 2
	ed._lock_clicked()
	check("locked at point 2", r.frozen.size() == 1 and r.lock_index() == 2)
	var g := maxf(surface_gap(before_rings, r.geometry["rings"]), surface_gap(r.geometry["rings"], before_rings))
	check("locking leaves the surface where it was", g < 0.05, "(moved at most %.3f m)" % g)
	var seam: int = r.geometry["seams"][0]
	var h0 := frozen_hash(r, seam)

	# --- edit the editable section: drag points, change its slope and face
	move_point(r, 3, Vector3(25, 4, 0))
	move_point(r, 5, Vector3(-30, -10, 0))
	ed._select(r)
	ed.selected_point = 4
	ed._edit_prop("angle", 63.0)
	ed._edit_prop("face_length", 13.0)
	seam = r.geometry["seams"][0]
	check("locked section unchanged after editing the rest (vertex hash)", frozen_hash(r, seam) == h0)

	# --- seam continuity
	var ridge: PackedVector3Array = r.geometry["ridge"]
	var tans: PackedVector3Array = r.geometry["tan"]
	var rights: PackedVector3Array = r.geometry["rights"]
	check("seam sits exactly on the locked point", ridge[seam].distance_to(r.points[2]) < 1e-4)
	var kink := turn_deg(ridge[seam] - ridge[seam - 1], ridge[seam + 1] - ridge[seam])
	var before_kink := turn_deg(ridge[seam - 1] - ridge[seam - 2], ridge[seam] - ridge[seam - 1])
	check("no kink at the seam (yaw and pitch carry on)", kink < before_kink + 1.0, "(turn %.2f deg at the seam vs %.2f just before)" % [kink, before_kink])
	var tyaw := absf(rad_to_deg(Vector2(tans[seam - 1].x, tans[seam - 1].z).angle_to(Vector2(tans[seam + 1].x, tans[seam + 1].z))))
	var tpitch := absf(rad_to_deg(asin(tans[seam - 1].y) - asin(tans[seam + 1].y)))
	check("tangent yaw and pitch match across the seam", tyaw < 2.0 and tpitch < 1.0, "(yaw %.2f, pitch %.2f deg over 2 m)" % [tyaw, tpitch])
	check("right vector continues across the seam", rights[seam - 1].dot(rights[seam + 1]) > 0.999)
	var v_seam: Array = r.geometry["values"][seam]
	var v_frozen := [float(r.frozen[0]["angle"]), float(r.frozen[0]["face_length"])]
	check("profile at the seam = the locked section's (56 deg, 10.5 m)", absf(v_seam[0] - v_frozen[0]) < 1e-4 and absf(v_seam[1] - v_frozen[1]) < 1e-4)
	var far: Array = r.geometry["values"][ridge.size() - 1]
	check("editable section reaches its own settings (63 deg, 13 m)", absf(far[0] - 63.0) < 1e-4 and absf(far[1] - 13.0) < 1e-4)
	var problems := RampShape.self_check(r.shape_spec(), r.geometry)
	check("geometry self-check passes on the locked ramp", problems.is_empty(), str(problems.slice(0, 3)))

	# --- tangent lock off allows a crease
	ed._edit_prop("seam_tangent_lock", false)
	move_point(r, 3, Vector3(40, 0, 0))
	seam = r.geometry["seams"][0]
	ridge = r.geometry["ridge"]
	var crease := turn_deg(ridge[seam] - ridge[seam - 1], ridge[seam + 1] - ridge[seam])
	ed._edit_prop("seam_tangent_lock", true)
	ridge = r.geometry["ridge"]
	var smooth := turn_deg(ridge[seam] - ridge[seam - 1], ridge[seam + 1] - ridge[seam])
	check("tangent lock off -> crease, on -> smooth", crease > 5.0 and smooth < 1.5, "(%.1f deg vs %.2f deg)" % [crease, smooth])
	check("locked section still unchanged", frozen_hash(r, seam) == h0)
	await shot(out + "/lock_one.png")

	# --- where locks are allowed
	check("can't lock inside the locked part", r.lock_problem(1) != "")
	check("can't lock the last point", r.lock_problem(r.points.size() - 1) != "")
	check("can lock a later point", r.lock_problem(4) == "")

	# --- frozen points are protected
	var pts_before := r.points.duplicate()
	ed._select(r)
	ed.selected_point = 1
	ed._nudge(KEY_LEFT)
	ed.selected_point = 1
	ed._delete_clicked()
	ed._flip_clicked()
	check("frozen points can't be nudged or deleted; Flip refused", r.points == pts_before and ed.selected == r)

	# --- second lock, undo/redo, unlock
	var one_lock: Dictionary = r.to_dict()
	ed.selected_point = 4
	ed._lock_clicked()
	var two_locks: Dictionary = r.to_dict()
	check("second lock at point 4", r.frozen.size() == 2 and r.geometry["seams"].size() == 2)
	await shot(out + "/lock_two.png")
	ed.undo()
	r = ed.ramps_root.get_child(0)
	check("undo restores exactly one lock", r.to_dict() == one_lock)
	ed.redo()
	r = ed.ramps_root.get_child(0)
	check("redo restores both locks exactly", r.to_dict() == two_locks)
	ed._select(r)
	ed.selected_point = -1
	ed._unlock_clicked()                                # the most recent
	check("unlock the last lock merges it back", r.frozen.size() == 1)
	ed.undo()
	r = ed.ramps_root.get_child(0)
	check("undo after unlocking brings the lock back exactly", r.to_dict() == two_locks)
	ed._select(r)
	ed.selected_point = 2
	ed._do_unlock(0)                                    # what the confirmation dialog runs for an earlier lock
	check("unlocking the first lock clears everything after it", r.frozen.is_empty())
	ed.undo()
	r = ed.ramps_root.get_child(0)
	check("...and undo brings both back", r.to_dict() == two_locks)

	# --- the whole ramp can still be moved and turned as one piece
	ed._select(r)
	var rings0: Array = r.geometry["rings"].duplicate()
	r.translate_by(Vector3(100, 20, -50))
	r.rotate_by(30.0)
	r.rotate_by(-30.0)
	r.translate_by(Vector3(-100, -20, 50))
	var md := max_diff(rings0, r.geometry["rings"])
	check("moving + turning the ramp is rigid (moving it back restores it)", md < 5e-3, "(%.5f m)" % md)

	# --- export
	var p := SurfsUpExporter.check(ed._map_dict())
	var scene: Node = SurfsUpExporter.build_scene(ed._map_dict(), "sf_lock_test")
	check("exports as one ramp", p.is_empty() and scene.get_node("Ramps").get_child_count() == 1)
	scene.free()
	print("LOCKS: ", "PASS" if ok else "FAIL")
	quit()
