extends SceneTree
## Screenshot: a hill raised with the Round brush on a 1 m grid block (heightmap mode), outlines on.
## Run: godot --path . --resolution 1280x720 -s res://tests/hmap_shot.gd -- <out.png>

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var w := CubeWorld.new()
	w.set_cell(Vector3i(0, -128, 0), 4, CubeWorld.FULL, CubeWorld.blank_tex())
	for spot in [[64, 64, 14], [40, 80, 8], [88, 48, 10]]:
		for i in spot[2]:
			w.hmap_edit(Vector3i(spot[0], 0, spot[1]), 8 + i * 2, 0, CubeWorld.BRUSHES[2][1], -1)
	var root3 := Node3D.new()
	root.add_child(root3)
	for ck in w.render_chunks():
		var m: Array = w.chunk_mesh(ck, true)
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.scale = Vector3.ONE * CubeWorld.TICK * 8.0
		root3.add_child(mi)
		var li := MeshInstance3D.new()
		li.mesh = m[2]
		li.scale = mi.scale
		root3.add_child(li)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(-4, 16, -4), Vector3(8, 1, 8))
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("saved")
	quit()
