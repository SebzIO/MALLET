extends SceneTree
## Kill zones + boosters: editor placement, play-mode behavior, export tags.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/volumes_test.gd -- <out_dir>

const U := 39.37
var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	# kill zone under the ramp's end, booster just past the start
	ed._add_entity("kill")
	var kill: EntityNode = ed.selected
	kill.position = Vector3(40, 60, 0)
	ed._add_entity("booster")
	var boost: EntityNode = ed.selected
	boost.position = Vector3(-20, 140, 60)
	boost.yaw = -90.0               # push towards +X
	boost.pitch = 30.0
	boost.strength = 1000.0
	boost.rebuild()
	ed._refresh_props()
	ed._frame_clicked()
	ed._select(null)
	ed._frame_clicked()
	ed._select(boost)
	await shot("v01_editor")
	print("booster direction ", boost.boost_direction().snapped(Vector3.ONE * 0.01), " (expect ~(0.87, 0.5, 0))")

	ed._play_clicked()
	await physics_frame
	var p: SUCC = ed.play.player
	var spawn: Vector3 = p.global_position
	# kill zone: teleport in -> back at spawn
	p.teleport(Transform3D(Basis(), kill.global_position - Vector3(0, 0.9, 0)))
	for i in 3: await physics_frame
	print("kill zone: back at spawn = ", p.global_position.distance_to(spawn) < 3.0)
	# booster, Add mode: standing still in mid air, entering adds 1000 u/s along the arrow
	p.teleport(Transform3D(Basis(), boost.global_position + Vector3(0, -0.9, 0)))
	p.velocity = Vector3.ZERO
	for i in 2: await physics_frame
	var v := p.velocity
	print("booster add: %d u/s, direction %s" % [roundi(v.length() * U), v.normalized().snapped(Vector3.ONE * 0.01)])
	# Set mode: arrive fast the wrong way, leave at exactly the booster speed
	boost.mode = 1
	p.teleport(Transform3D(Basis(), boost.global_position + Vector3(-30, -0.9, 0)))
	for i in 3: await physics_frame
	p.teleport(Transform3D(Basis(), boost.global_position + Vector3(0, -0.9, 0)))
	p.velocity = Vector3(0, 0, -60)
	for i in 2: await physics_frame
	print("booster set: %d u/s (expect ~1000), direction %s" % [roundi(p.velocity.length() * U), p.velocity.normalized().snapped(Vector3.ONE * 0.01)])
	ed.play.stop()

	# export and read the tags back
	var maps := "D:/SurfForge_downloads/maps_test"
	DirAccess.make_dir_recursive_absolute(maps)
	print("export: '", SurfsUpExporter.export_pack(ed._map_dict(), "sf_volumes_test", maps), "'")
	ProjectSettings.load_resource_pack(maps + "/sf_volumes_test.pck")
	var scene: Node = (load("res://Levels/sf_volumes_test.tscn") as PackedScene).instantiate()
	for n in scene.get_children():
		if n.has_meta("sdk_zone"):
			var meta := []
			for k in n.get_meta_list(): meta.append("%s=%s" % [k, n.get_meta(k)])
			print("  ", n.name, " ", " ".join(meta))
	quit()
