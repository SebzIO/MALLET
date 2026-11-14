extends SceneTree
## 0.29.1, a tester's sky report: (1) the Map panel's sky list picks skies with real clicks, (2) a shader saved into
## the folder shows up without restarting (when the list opens, and by itself within a few seconds; files saved
## without .gdshader or of an unused type are listed grayed out with why), (3) canvas_item shaders work as skies
## (a live picture wrapped around the world, a still picture in the SurfsUp export; screen effects refused), (4) play
## mode hides the 3D ground grid and the lights' bulbs and brings them back, (5) every sky keeps its own settings
## (switch away and back, undo, save and load). Opens a MALLET window. Uses a shaders folder of its own.
## Run: godot --path . --resolution 1600x900 -s res://tests/sky_fixes_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func click(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = p
	ev.global_position = p
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await process_frame


## Open an OptionButton's list and click item `k`, the way a user does.
func pick_by_click(ob: OptionButton, k: int) -> void:
	await click(ob.get_global_rect().get_center())
	await frames(3)
	var pop := ob.get_popup()
	if not pop.visible:                                  # (the very first click of a session can be eaten)
		await click(ob.get_global_rect().get_center())
		await frames(3)
	var h := pop.size.y / float(pop.item_count)
	await click(Vector2(pop.position) + Vector2(pop.size.x * 0.5, h * (k + 0.5)))
	await frames(3)


func labels(ob: OptionButton) -> Array:
	var out := []
	for i in ob.item_count:
		out.append(ob.get_item_text(i))
	return out


func index_of(ob: OptionButton, id: String) -> int:
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == id and not ob.is_item_disabled(i):
			return i
	return -1


## The sky's color straight ahead (what the perspective view would show with nothing in the way).
func sky_pixel(we: Environment) -> Color:
	var vp := SubViewport.new()
	vp.size = Vector2i(32, 32)
	vp.own_world_3d = true
	var w := WorldEnvironment.new()
	w.environment = we
	vp.add_child(w)
	var cam := Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	root.add_child(vp)
	cam.current = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await frames(6)
	var c := vp.get_texture().get_image().get_pixel(16, 16)
	vp.queue_free()
	return c


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var dir := out.path_join("sky_fix_shaders") + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + f)
	UserShaders.dir = dir
	UserShaders.folder()
	write(dir + "sky_a.gdshader", "shader_type sky;\nuniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 1.0);\nuniform float glow : hint_range(0, 4) = 1.0;\n"
		+ "void sky() { COLOR = tint.rgb * glow; }\n")
	write(dir + "sky_b.gdshader", "shader_type sky;\nuniform float level : hint_range(0, 1) = 0.5;\nvoid sky() { COLOR = vec3(level); }\n")

	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._select(null)
	ed._refresh_props()
	await frames(3)
	var ob: OptionButton = ed._fields["env_sky_shader"]

	# ---- (1) picking skies with the mouse
	var ia := index_of(ob, "sky_a")
	check("the sky list has MALLET's sky and both sky shaders", ob.get_item_text(0).begins_with("MALLET") and ia > 0 and index_of(ob, "sky_b") > 0, str(labels(ob)))
	await pick_by_click(ob, ia)
	check("clicking sky_a in the list puts it in the map and the sky", ed.environment.get("sky_shader", "") == "sky_a"
		and ed.world_env.environment.sky.sky_material.shader == UserShaders.entry("sky_a")["shader"], str(ed.environment.get("sky_shader")))
	check("...the list shows it and its settings show", ob.get_item_text(ob.selected) == "sky_a" and not ed._fields["env_sky_builtin"].visible)
	await pick_by_click(ob, index_of(ob, "sky_b"))
	check("clicking sky_b switches to it", ed.environment.get("sky_shader", "") == "sky_b" and ob.get_item_text(ob.selected) == "sky_b")
	await pick_by_click(ob, 0)
	check("clicking MALLET's sky goes back to the built-in sky", ed.environment.get("sky_shader", "x") == ""
		and ed.world_env.environment.sky.sky_material.shader == Look.shader("sky") and ed._fields["env_sky_builtin"].visible)

	# ---- (2) a new file shows up without restarting
	write(dir + "sky_new.gdshader", "shader_type sky;\nvoid sky() { COLOR = vec3(0.0, 0.0, 1.0); }\n")
	ob.button_down.emit()                                # (pressing the list, before it opens)
	await frames(2)
	check("a file saved into the folder is in the list when it opens", index_of(ob, "sky_new") > 0, str(labels(ob)))
	write(dir + "sky_later.gdshader", "shader_type sky;\nvoid sky() { COLOR = vec3(0.0, 1.0, 0.0); }\n")
	write(dir + "plain_n64", "shader_type sky;\nvoid sky() { COLOR = vec3(1.0); }\n")
	write(dir + "fog_one.gdshader", "shader_type fog;\nvoid fog() { DENSITY = 0.1; }\n")
	var t0 := Time.get_ticks_msec()
	while index_of(ob, "sky_later") < 0 and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	check("...and by itself within a few seconds (no focus change)", index_of(ob, "sky_later") > 0, "%d ms" % (Time.get_ticks_msec() - t0))
	var all := " | ".join(labels(ob))
	check("a file saved without .gdshader is listed, grayed, with what to do", all.contains("plain_n64  (rename it to plain_n64.gdshader)"), all)
	check("a shader of a type MALLET can't use is listed, grayed, with why", all.contains("fog_one  (can't be used"), all)
	var grayed := true
	for i in ob.item_count:
		if ob.get_item_text(i).contains("plain_n64") or ob.get_item_text(i).contains("fog_one"):
			grayed = grayed and ob.is_item_disabled(i)
	check("...and those can't be picked", grayed)
	var surf_ob: OptionButton = ed._fields["shader"]
	check("the ramp / block shader list opens with a rescan too", surf_ob.button_down.is_connected(ed._rescan_shaders))

	# ---- (3) canvas_item skies
	write(dir + "flat.gdshader", "shader_type canvas_item;\nuniform vec4 paint : source_color = vec4(0.0, 1.0, 0.0, 1.0); // The color\n"
		+ "void fragment() { COLOR = vec4(paint.rgb * (0.5 + 0.5 * step(0.5, UV.y)), 1.0); }\n")
	write(dir + "vhs.gdshader", "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture;\nvoid fragment() { COLOR = texture(screen_tex, SCREEN_UV); }\n")
	write(dir + "waves.gdshader", "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(vec3(0.5 + 0.5 * sin(TIME + UV.x * 20.0)), 1.0); }\n")
	ed._rescan_shaders()
	check("a canvas_item shader is a sky", UserShaders.ok("flat") and UserShaders.entry("flat")["kind"] == "sky" and UserShaders.is_canvas("flat")
		and index_of(ob, "flat") > 0, str(labels(ob)))
	check("...with its settings read like any shader's", UserShaders.entry("flat")["uniforms"].size() == 1
		and UserShaders.entry("flat")["uniforms"][0]["tip"] == "The color")
	check("a canvas_item screen effect is refused, with why", not UserShaders.ok("vhs") and UserShaders.problem("vhs").contains("screen effect"), UserShaders.problem("vhs"))
	check("...and only moving canvas skies redraw every frame", UserShaders.entry("waves")["animated"] and not UserShaders.entry("flat")["animated"])
	ed._pick_sky_shader("flat")
	await frames(6)
	var sm = ed.world_env.environment.sky.sky_material
	var pano = sm.get_shader_parameter("panorama") if sm is ShaderMaterial else null
	check("picking it wraps its live picture around the world", sm is ShaderMaterial and pano is ViewportTexture, str(pano))
	var top := await sky_pixel(ed.world_env.environment)
	check("...and the sky shows it (green, the picture's lower half straight ahead)", top.g > 0.5 and top.r < 0.2 and top.b < 0.2, str(top))
	var paint_sliders := []
	var params_box: VBoxContainer = ed._fields["env_sky_params"]
	var pickers := params_box.find_children("*", "ColorPickerButton", true, false)
	check("its setting has a control in the Map panel", pickers.size() == 1, str(pickers.size()))
	ed._set_sky_param("paint", "ff0000")
	await frames(4)
	var red := await sky_pixel(ed.world_env.environment)
	check("changing it redraws the picture without a new sky", red.r > 0.5 and red.g < 0.2 and ed.world_env.environment.sky.sky_material == sm, str(red))
	var scene: Node3D = SurfsUpExporter.build_scene(ed._map_dict(), "sky_fix")
	var we: WorldEnvironment = scene.get_node("WorldEnvironment")
	var still = we.environment.sky.sky_material.get_shader_parameter("panorama")
	check("the SurfsUp export takes it as a still picture (no viewport in the file)", still is PortableCompressedTexture2D and not (still is ViewportTexture), str(still))
	var packed := PackedScene.new()
	check("...and the scene packs", packed.pack(scene) == OK)
	scene.free()
	var css_sky: Dictionary = await Look.bake_skybox(ed.environment, ed, 32)
	var ft: Image = css_sky.get("ft")
	check("the CS:S skybox bake renders it too", ft != null and ft.get_pixel(16, 24).r > 0.4, str(ft.get_pixel(16, 24)) if ft else "none")
	paint_sliders.clear()

	# ---- (5) every sky keeps its own settings
	ed._pick_sky_shader("sky_a")
	ed._set_sky_param("glow", 2.5)
	ed._pick_sky_shader("sky_b")
	check("another sky starts from its own settings, not sky_a's", not ed.environment["sky_params"].has("glow"), str(ed.environment["sky_params"]))
	ed._set_sky_param("level", 0.9)
	ed._pick_sky_shader("sky_a")
	check("back on sky_a: its setting is still there", is_equal_approx(float(ed.environment["sky_params"].get("glow", 0.0)), 2.5), str(ed.environment["sky_params"]))
	check("...shown on the sky", is_equal_approx(float(ed.world_env.environment.sky.sky_material.get_shader_parameter("glow")), 2.5))
	ed._refresh_props()
	var spins := (ed._fields["env_sky_params"] as Node).find_children("*", "SpinBox", true, false)
	check("...and in its control", spins.size() >= 1 and is_equal_approx((spins[0] as SpinBox).value, 2.5), str(spins.map(func(x): return x.value)))
	check("sky_b's and flat's settings are kept for them", ed.environment.get("sky_params_by", {}).has("sky_b") and ed.environment["sky_params_by"].has("flat"),
		str(ed.environment.get("sky_params_by")))
	ed._pick_sky_shader("sky_b")
	check("back on sky_b: its setting too", is_equal_approx(float(ed.environment["sky_params"].get("level", 0.0)), 0.9))
	ed.undo()
	check("undo takes back the switch, settings and all", ed.environment["sky_shader"] == "sky_a"
		and is_equal_approx(float(ed.environment["sky_params"].get("glow", 0.0)), 2.5))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(ed._map_dict()))
	ed._load_dict({})
	ed._load_dict(saved)
	ed._pick_sky_shader("sky_b")
	check("the settings are saved with the map", is_equal_approx(float(ed.environment["sky_params"].get("level", 0.0)), 0.9), str(ed.environment["sky_params"]))
	ed._fields["env_preset"].item_selected.emit(1)
	ed._pick_sky_shader("sky_a")
	check("a sky preset keeps them", is_equal_approx(float(ed.environment["sky_params"].get("glow", 0.0)), 2.5), str(ed.environment))

	# ---- (4) play mode hides the editor's grid and bulbs
	ed._add_light("point")
	ed._select(null)
	ed._ground_grid.visible = true
	var bulbs_before := not LightNode.hide_bulbs
	ed._play_clicked()
	await frames(4)
	check("play mode hides the 3D ground grid", ed.play.active and not ed._ground_grid.visible)
	check("...and the lights' bulbs", LightNode.hide_bulbs)
	ed.play.stop()
	await frames(4)
	check("back in the editor the grid shows again", ed._ground_grid.visible)
	check("...and the bulbs as they were", (not LightNode.hide_bulbs) == bulbs_before)
	ed._ground_grid.visible = false
	ed._play_clicked()
	await frames(2)
	ed.play.stop()
	await frames(2)
	check("a grid you'd turned off stays off", not ed._ground_grid.visible)
	ed._ground_grid.visible = bool(Settings.value("ground_grid"))

	print("sky_fixes_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
