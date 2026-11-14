extends SceneTree
## Screenshot of a sky preset, looking up and toward the horizon (look check for sky.gdshader).
## Run: godot --path . --resolution 1280x720 -s res://tests/sky_shot.gd -- <out.png> [preset]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var preset: String = args[1] if args.size() > 1 else "space"
	var root3 := Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	we.environment = Look.build_environment(Look.preset_environment(preset))
	root3.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 80
	root3.add_child(cam)
	cam.rotation_degrees = Vector3(20, 30, 0)
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	print("saved")
	quit()
