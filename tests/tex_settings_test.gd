extends SceneTree
## Cube faces with F3 texture settings (tint, see-through, scroll) must still show their texture (the user's #7: a
## shader that didn't compile turned them all plain white). Renders four brick cubes and samples their pixels.
## Run: godot --path . --resolution 1280x720 -s res://tests/tex_settings_test.gd -- <out folder>

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var w := CubeWorld.new()
	var slots := ["Bricks104", "Bricks104|c=ff8080", "Bricks104|a=0.9", "Bricks104|su=0.25"]
	for i in slots.size():
		var t := PackedStringArray()
		for f in 6:
			t.append(slots[i])
		w.set_cell(Vector3i(i * 16, 0, 0), 0, CubeWorld.FULL, t)
	var root3 := Node3D.new()
	root.add_child(root3)
	for ck in w.render_chunks():
		var mi := MeshInstance3D.new()
		mi.mesh = w.chunk_mesh(ck)[0]
		root3.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.3, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(3.5, 2.5, 4.5), Vector3(3.5, 0.5, 0.5))
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + "/tex_settings.png")
	var ok := true
	var names := ["plain", "tinted", "see-through", "scrolling"]
	for i in 4:
		var p := cam.unproject_position(Vector3(i * 2.0 + 0.5, 1.0, 1.0)) * Vector2(img.get_size()) / Vector2(root.get_viewport().get_visible_rect().size)
		var sum := Color(0, 0, 0)
		var n := 0
		for dx in range(-12, 13, 3):
			for dy in range(4, 30, 3):
				var c := img.get_pixelv(Vector2i(p) + Vector2i(dx, dy))
				sum += c
				n += 1
		var avg := sum / n
		var textured := avg.r > avg.b * 1.25                  # bricks are red-brown; the white fallback is gray
		print("%-56s %s (avg %s)" % ["%s bricks show their texture" % names[i], "OK  " if textured else "FAIL", avg])
		ok = ok and textured
	print("TEX SETTINGS: ", "PASS" if ok else "FAIL")
	quit()
