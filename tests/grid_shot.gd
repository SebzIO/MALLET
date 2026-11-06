extends SceneTree
## Screenshot: blank cubes and a block side by side, to see the Dev grid is even squares (1 m) on both.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/grid_shot.gd -- <out.png>

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var w := CubeWorld.new()
	for x in 2:
		for y in 2:
			w.set_cell(Vector3i(x * 16, y * 16, 0), 1, CubeWorld.FULL, CubeWorld.blank_tex())   # 2 m cubes, a 4 m wall
	var root3 := Node3D.new()
	root.add_child(root3)
	for ck in w.render_chunks():
		var m: Array = w.chunk_mesh(ck, true)
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		root3.add_child(mi)
		var li := MeshInstance3D.new()
		li.mesh = m[2]
		root3.add_child(li)
	var b := BlockNode.new()
	root3.add_child(b)
	b.from_dict({"position": [7, 2, 1], "size": [4, 4, 2]})
	b.rebuild()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(4.5, 2, 9), Vector3(4.5, 2, 0))
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("saved")
	quit()
