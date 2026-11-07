extends SceneTree
## Picture of 0.13's shader UI: the example sky with its controls in the Map panel, then a ramp wearing the example
## surface with its controls. Saves shader_sky.png and shader_ramp.png. (Uses a shaders folder of its own.)
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/shader_ui_shot.gd -- <out folder>


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	UserShaders.dir = out.path_join("shot_shaders") + "/"
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._pick_sky_shader("example_sky")
	ed._add_ramp_clicked()
	ed._edit_prop("look", "shader")
	ed._frame_clicked()
	for i in 20:
		await process_frame
	ed._select(null)
	ed._refresh_props()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("shader_sky.png"))
	ed._select(ed.ramps_root.get_child(0))
	ed._refresh_props()
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("shader_ramp.png"))
	print("shader_ui_shot: done")
	quit()
