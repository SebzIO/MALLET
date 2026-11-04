extends SceneTree
## Look & feel showcase: one ramp per material look under every sky preset; then export and check the pack
## carries the shaders and the image inline. Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/look_test.gd -- <out>

var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	# a test image for the "texture" look: a checker with a stripe
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var c := Color(0.95, 0.75, 0.2) if ((x / 32) + (y / 32)) % 2 == 0 else Color(0.2, 0.25, 0.35)
			if abs(x - 128) < 6:
				c = Color(0.9, 0.2, 0.3)
			img.set_pixel(x, y, c)
	var tex_path := out + "/test_texture.png"
	img.save_png(tex_path)

	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._toggle_views()                                  # one big 3D view
	var first: RampNode = ed.ramps_root.get_child(0)
	var colors := {"color": Color(0.93, 0.92, 0.89), "ceramic": Color(0.13, 0.25, 0.59), "steel": Color(0.8, 0.82, 0.86),
		"grid": Color(0.62, 0.66, 0.72), "aurora": Color(0.15, 1.0, 0.6), "nebula": Color(0.85, 0.2, 0.9),
		"neon": Color(0.1, 0.9, 1.0), "texture": Color.WHITE}
	var i := 0
	for look in Look.LOOK_ORDER:
		var r: RampNode = first if i == 0 else RampNode.new()
		if i > 0:
			ed.ramps_root.add_child(r)
		var z := -105.0 + i * 30.0
		r.points = PackedVector3Array([Vector3(-60, 120, z), Vector3(0, 105, z), Vector3(60, 90, z)])
		r.width = 20.0
		r.height = 12.5
		r.look = look
		r.color = colors[look]
		if look == "texture":
			r.texture = tex_path
			r.tex_scale = 30.0
		r.rebuild()
		i += 1
	ed._select(null)
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(0, 100, 0)
	cam.distance = 230.0
	cam.yaw = deg_to_rad(20)
	cam.pitch = deg_to_rad(-22)
	cam._apply()
	for preset in Look.ENV_PRESETS:
		ed.environment = Look.preset_environment(preset)
		ed._apply_environment()
		ed._refresh_props()
		await shot("look_" + preset)
	# ramp panel with the texture look selected
	ed._toggle_views()
	ed._select(ed.ramps_root.get_child(7))
	await shot("look_panel_texture")

	# export: shaders + image must be embedded
	ed.environment = Look.preset_environment("aurora")
	var maps := "D:/SurfForge_downloads/maps_test"
	print("export: '", SurfsUpExporter.export_pack(ed._map_dict(), "sf_look_test", maps), "'")
	var pck_files := []
	var f := FileAccess.open(ProjectSettings.globalize_path("user://export/sf_look_test.tscn"), FileAccess.READ)
	var text := f.get_as_text()
	print("scene: %d KB, embedded shaders: %d, embedded image: %s, references to res://core: %d" % [text.length() / 1024,
		text.count("[sub_resource type=\"Shader\""), text.contains("PortableCompressedTexture2D"), text.count("res://core")])
	# the image must really be in there: reload the exported scene and read the texture back
	var ps: PackedScene = ResourceLoader.load("user://export/sf_look_test.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var inst := ps.instantiate()
	var tex_size := Vector2.ZERO
	for body in inst.get_node("Ramps").get_children():
		var mat = body.get_node("Mesh").mesh.surface_get_material(0)
		if mat is StandardMaterial3D and mat.albedo_texture:
			var back: Image = mat.albedo_texture.get_image()
			tex_size = Vector2(back.get_size()) if back else Vector2.ZERO
	inst.free()
	print("image texture read back from the export: %s  %s" % [tex_size, "OK" if tex_size.x > 0 else "FAIL"])
	quit()
