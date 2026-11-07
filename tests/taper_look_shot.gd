extends SceneTree
## Picture: ramp looks on shaped ends (taper, round, flare, diagonal cut), to see textures stay straight.
## Saves taper_looks.png. Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/taper_look_shot.gd -- <out>


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var w := Node3D.new()
	root.add_child(w)
	var we := WorldEnvironment.new()
	we.environment = Look.build_environment(Look.default_environment())
	w.add_child(we)
	var sun := DirectionalLight3D.new()
	Look.apply_sun(sun, Look.default_environment())
	w.add_child(sun)
	var looks := [["ceramic", Color(0.75, 0.2, 0.3), ""], ["grid", Color(0.62, 0.66, 0.72), ""], ["neon", Color(0.1, 0.9, 1.0), ""],
		["material", Color.WHITE, "Bricks104"]]
	var ends := [{"start": {"shape": "taper", "length": 12.0}}, {"start": {"shape": "round", "length": 10.0}},
		{"start": {"shape": "flare", "length": 14.0, "amount": 0.8}}, {"start": {"cut": 40.0}}]
	for li in looks.size():
		for ei in ends.size():
			var x := ei * 40.0
			var z := li * 30.0
			var s := RampShape.spec({"ends": ends[ei]})
			var geo := RampShape.build(PackedVector3Array([Vector3(x, 0, z), Vector3(x + 25, -3, z), Vector3(x + 50, -6, z)]), s)
			var mi := MeshInstance3D.new()
			mi.mesh = geo["mesh"]
			mi.material_override = Look.ramp_material(looks[li][0], looks[li][1], "", 20.0, looks[li][2])
			w.add_child(mi)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.position = Vector3(70, 75, 40)
	cam.look_at(Vector3(70, -5, 44))
	cam.fov = 70.0
	cam.current = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out.path_join("taper_looks.png"))
	# close-ups: [camera, target, file]: the ceramic taper, the neon and the bricks diagonal cuts
	for c in [[Vector3(-7, 9, 13), Vector3(6, -2, 0), "close_ceramic_taper.png"],
			[Vector3(109, 9, 73), Vector3(123, -2, 60), "close_neon_cut.png"],
			[Vector3(109, 9, 103), Vector3(123, -2, 90), "close_bricks_cut.png"]]:
		cam.position = c[0]
		cam.look_at(c[1])
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join(c[2]))
	quit()
