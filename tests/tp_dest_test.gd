extends SceneTree
## Teleports to a destination (0.19.9): a teleport can send you to a "Teleport destination" instead of a stage. You
## keep your speed (its direction too, as SurfsUp's point teleport does) and look along the destination's arrow; no
## stage is reached, so dying after it sends you back to where you'd respawn anyway (here: the start). The SurfsUp
## export makes it a point teleport to a marker, CS:S a trigger_teleport to an info_teleport_destination, and a
## teleport to a destination that isn't there is flagged.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/tp_dest_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var map := {"entities": [
		{"kind": "start", "position": [0.0, 100.0, 0.0], "size": [20.0, 2.0, 26.0], "yaw": 0.0},
		{"kind": "stage", "position": [300.0, 100.0, 0.0], "size": [24.0, 2.0, 24.0], "yaw": 0.0, "number": 2},
		{"kind": "teleport", "position": [0.0, 60.0, -100.0], "size": [30.0, 30.0, 10.0], "yaw": 0.0, "number": 1, "to": "destination", "keep_speed": true},
		{"kind": "destination", "position": [150.0, 81.75, 50.0], "size": [2.0, 3.5, 2.0], "yaw": 90.0, "number": 1},
		{"kind": "kill", "position": [150.0, 40.0, 50.0], "size": [40.0, 20.0, 40.0], "yaw": 0.0}]}
	ed._load_dict(map)
	await process_frame
	var tp: EntityNode = ed.entities_root.get_child(2)
	check("a teleport can go to a destination", tp.to_dest and tp.label() == "Teleport to destination 1" and tp.to_dict()["to"] == "destination")
	ed._play_clicked()
	for i in 5:
		await physics_frame
	var p: SUCC = ed.play.player
	p.global_position = Vector3(0, 70, -60)               # (off the start: the run is on, no start speed cap)
	for i in 3:
		await physics_frame
	var v := Vector3(5.0, -2.0, -30.0)
	p.global_position = Vector3(0, 55, -100)              # (in the teleport's box)
	p.velocity = v
	for i in 3:
		await physics_frame
	var feet := p.global_position
	check("it puts you at the destination", feet.distance_to(Vector3(150, 80, 50)) < 3.0, str(feet))
	check("...with your speed, its direction kept", p.velocity.length() > v.length() * 0.9 and p.velocity.normalized().dot(v.normalized()) > 0.95,
		str(p.velocity))
	check("...looking along the destination's arrow", absf(rad_to_deg(p.rotation.y) - 90.0) < 1.0, "(%.1f°)" % rad_to_deg(p.rotation.y))
	check("...without reaching a stage", ed.play._reached.is_empty() or not 2 in ed.play._reached)
	p.global_position = Vector3(150, 40, 50)               # (into the kill zone after it)
	for i in 3:
		await physics_frame
	check("dying after it sends you back to the start", p.global_position.distance_to(Vector3(0, 100, 0)) < 15.0, str(p.global_position))
	ed.play.stop()
	await process_frame
	# exports
	check("the SurfsUp check is happy", not "\\n".join(SurfsUpExporter.check(map)).contains("destination"))
	var bad := map.duplicate(true)
	bad["entities"].remove_at(3)
	check("...and flags a teleport to a destination that isn't there", "\\n".join(SurfsUpExporter.check(bad)).contains("no destination 1"))
	var scene := SurfsUpExporter.build_scene(map, "surf_test")
	var marker := scene.find_child("Dest1", true, false)
	var zone: Node = null
	for a in scene.find_children("*", "Area3D", true, false):
		if String(a.get_meta("target", "")) == "Dest1":
			zone = a
	var su_ok: bool = marker != null and marker is Marker3D
	su_ok = su_ok and (marker as Marker3D).position.is_equal_approx(Vector3(150, 80, 50)) and zone != null
	su_ok = su_ok and zone.get_meta("sdk_zone") == "point_tp" and zone.get_meta("reset_velocity_on_teleport") == false
	su_ok = su_ok and is_equal_approx(float(zone.get_meta("horizontal_view_override")), 90.0)
	check("SurfsUp: a point teleport to a marker where the feet land, keeping speed", su_ok)
	scene.free()
	var vmf_path := out + "/tp_dest.vmf"
	var vmap := map.duplicate(true)                       # (CS:S needs something solid to compile: a ramp off to one side)
	vmap["ramps"] = [{"points": [[600, 90, 0], [600, 70, -60], [600, 50, -120]]}]
	vmap["entities"].append({"kind": "finish", "position": [600.0, 20.0, -200.0], "size": [40.0, 2.0, 40.0], "yaw": 0.0})
	var vres := VmfExporter.export_vmf(vmap, vmf_path)
	if String(vres.get("error", "")) != "":
		print("  vmf: ", vres["error"])
	var vmf := FileAccess.get_file_as_string(vmf_path)
	check("CS:S: a trigger_teleport to an info_teleport_destination", vmf.contains('"targetname" "dest_1"') and vmf.contains('"target" "dest_1"'))
	print("tp_dest_test: ", "PASS" if ok else "FAIL")
	quit()
