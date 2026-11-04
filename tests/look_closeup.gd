extends SceneTree
func _init():
	call_deferred("_run")
func _run():
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._toggle_views()
	var first: RampNode = ed.ramps_root.get_child(0)
	var colors := {"color": Color(0.93, 0.92, 0.89), "ceramic": Color(0.13, 0.25, 0.59), "steel": Color(0.8, 0.82, 0.86),
		"grid": Color(0.62, 0.66, 0.72), "aurora": Color(0.15, 1.0, 0.6), "nebula": Color(0.85, 0.2, 0.9), "neon": Color(0.1, 0.9, 1.0), "texture": Color.WHITE}
	var i := 0
	for look in Look.LOOK_ORDER:
		var r: RampNode = first if i == 0 else RampNode.new()
		if i > 0: ed.ramps_root.add_child(r)
		var z := -105.0 + i * 30.0
		r.points = PackedVector3Array([Vector3(-60, 120, z), Vector3(0, 105, z), Vector3(60, 90, z)])
		r.width = 20.0
		r.height = 12.5
		r.look = look
		r.color = colors[look]
		if look == "texture":
			r.texture = out + "/test_texture.png"
			r.tex_scale = 30.0
		r.rebuild()
		i += 1
	ed._select(null)
	for preset in ["aurora", "day"]:
		ed.environment = Look.preset_environment(preset)
		ed._apply_environment()
		var cam := ed.panes[0].camera as OrbitCamera
		cam.focus = Vector3(10, 104, 0)
		cam.distance = 120.0
		cam.yaw = deg_to_rad(65)
		cam.pitch = deg_to_rad(-12)
		cam._apply()
		for k in 8: await process_frame
		root.get_viewport().get_texture().get_image().save_png(out + "/closeup_" + preset + ".png")
	quit()
