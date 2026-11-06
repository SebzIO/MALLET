extends SceneTree
## Screenshot: a two-way sloped 8 m cube with a 0.5 m and a 1 m shaft pushed through its slope (exact cut pieces), outlines on.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/split_shot.gd -- <out.png>

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var w := CubeWorld.new()
	var c: PackedByteArray
	for s in load("res://tests/split_accuracy_test.gd").shapes():
		if s[0] == "two-way 6,2":
			c = s[1]
	w.set_cell(Vector3i.ZERO, 3, c, CubeWorld.blank_tex("ambientcg/Tiles101"))
	for y in range(0, 64, 4):                                    # a 0.5 m shaft straight down through the slope
		w.push(CubeWorld.make_sel(Vector3i(20, y, 28), -1, 3))
	for y in range(0, 64, 8):                                    # and a 1 m one
		w.push(CubeWorld.make_sel(Vector3i(40, y, 40), 0, 3))
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
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.9)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(-5, 11, -7), Vector3(4, 3, 4))
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("saved")
	quit()
