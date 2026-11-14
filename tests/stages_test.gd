extends SceneTree
## Stages: plates + teleports in the editor, a full staged run in play mode, export validation and tags.
## Run: godot --path . --resolution 1600x900 -s res://tests/stages_test.gd -- <out_dir>

const U := 39.37
var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func place(kind: String, pos: Vector3, yaw := 0.0) -> EntityNode:
	ed._add_entity(kind)
	var e: EntityNode = ed.selected
	e.position = pos
	e.yaw = yaw
	e.rebuild()
	return e


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var tp1 := place("teleport", Vector3(80, 80, 0), 0.0)
	var s2 := place("stage", Vector3(-60, 160, 160), -90.0)
	var tp2 := place("teleport", Vector3(60, 120, 160), 0.0)
	var s3 := place("stage", Vector3(-60, 140, 320), -90.0)
	print("numbers: stage plates %d, %d   teleports -> %d, %d" % [s2.number, s3.number, tp1.number, tp2.number])
	tp1.number = 2
	tp2.number = 3
	ed._select(tp1)
	ed._frame_clicked()
	ed._select(null)
	ed._frame_clicked()
	ed._select(tp1)
	await shot("s01_editor")

	ed._play_clicked()
	await physics_frame
	var p: SUCC = ed.play.player
	p.teleport(Transform3D(Basis(), Vector3(0, 140, 0)))          # leave the start: run begins
	for i in 20: await physics_frame
	# straight to the finish: must be blocked (stages 2 and 3 not reached)
	var fin: EntityNode = ed._find_entity("finish")
	p.teleport(Transform3D(Basis(), fin.global_position + Vector3(0, 1, 0)))
	for i in 5: await physics_frame
	print("finish before stages -> state %d, message '%s'" % [ed.play.run_state, ed.play._message])
	# fly into teleport 1 at speed: arrive on stage 2 still moving
	p.teleport(Transform3D(Basis(), tp1.global_position + Vector3(-20, -0.9, 0)))
	p.velocity = Vector3(1500.0 / U, 0, 0)
	for i in 3: await physics_frame
	print("speed right after the keep-speed teleport: %d u/s" % roundi(p.velocity.length() * U))
	for i in 27: await physics_frame
	print("after teleport 1: near stage 2 plate %s, speed %d u/s, reached %s" % [p.global_position.distance_to(s2.global_position) < 40, roundi(p.velocity.length() * U), ed.play._reached])
	await shot("s02_stage2")
	# kill floor: back to stage 2, not the start
	p.teleport(Transform3D(Basis(), Vector3(0, ed.play._kill_y - 5, 0)))
	for i in 3: await physics_frame
	print("fell: back on stage 2 = ", p.global_position.distance_to(s2.global_position) < 15)
	# teleport 2 without keeping speed
	tp2.keep_speed = false
	p.teleport(Transform3D(Basis(), tp2.global_position + Vector3(0, -0.9, 0)))
	p.velocity = Vector3(1500.0 / U, 0, 0)
	for i in 3: await physics_frame
	print("after teleport 2 (stop): on stage 3 = %s, speed %d u/s" % [p.global_position.distance_to(s3.global_position) < 15, roundi(Vector2(p.velocity.x, p.velocity.z).length() * U)])
	p.teleport(Transform3D(Basis(), fin.global_position + Vector3(0, 1, 0)))
	p.velocity = Vector3.ZERO
	for i in 5: await physics_frame
	print("finish after stages -> state %d, splits %s" % [ed.play.run_state, ed.play._splits])
	await shot("s03_finished")
	ed.play.stop()

	# export: validation then tags
	var bad: Dictionary = ed._map_dict()
	bad["entities"].append({"kind": "teleport", "position": [0, 0, 0], "size": [10, 10, 10], "yaw": 0.0, "number": 7})
	print("validation: ", SurfsUpExporter.check(bad))
	var maps := OS.get_user_data_dir().path_join("test_maps")
	print("export: '", SurfsUpExporter.export_pack(ed._map_dict(), "sf_stages_test", maps), "'")
	ProjectSettings.load_resource_pack(maps + "/sf_stages_test.pck")
	var scene: Node = (load("res://Levels/sf_stages_test.tscn") as PackedScene).instantiate()
	for n in scene.get_children():
		if n.has_meta("sdk_zone") or n is Marker3D:
			var meta := []
			for k in n.get_meta_list(): meta.append("%s=%s" % [k, n.get_meta(k)])
			print("  ", n.name, " ", " ".join(meta))
	quit()
