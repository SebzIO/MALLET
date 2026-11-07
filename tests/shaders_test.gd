extends SceneTree
## Your own shaders (0.13): the shaders folder (examples copied in), sky / surface shaders compiled with their errors
## caught (line + message, never used), uniforms read into controls, the Map panel's sky choice and controls, ramps
## and blocks with "Your own shader", saving the code into the map (and loading it on a computer without the file),
## the SurfsUp export (embedded, no scripts), the CS:S export (base image / color, baked skybox VTFs facing the right
## way). Saves the baked skybox faces as a picture.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/shaders_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func has_script(n: Node) -> bool:
	if n.get_script() != null:
		return true
	for c in n.get_children():
		if has_script(c):
			return true
	return false


func write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var dir := out.path_join("shaders") + "/"
	DirAccess.remove_absolute(dir + "example_sky.gdshader")
	DirAccess.remove_absolute(dir + "example_surface.gdshader")
	for f in ["test_broken", "test_type", "test_dir", "test_glow"]:
		DirAccess.remove_absolute(dir + f + ".gdshader")
	DirAccess.remove_absolute(dir)
	UserShaders.dir = dir

	# ---- the folder and the library
	UserShaders.folder()
	check("first use makes the folder with both examples", FileAccess.file_exists(dir + "example_sky.gdshader")
		and FileAccess.file_exists(dir + "example_surface.gdshader"))
	write(dir + "test_broken.gdshader", "shader_type spatial;\nuniform float a = 1.0;\nvoid fragment() {\n\tALBEDO = vec3(a) + oops;\n}\n")
	write(dir + "test_type.gdshader", "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0); }\n")
	# a sky colored by direction: red = Godot +X (Source east), green = up, blue = Godot -Z (Source north)
	write(dir + "test_dir.gdshader", "shader_type sky;\nvoid sky() { COLOR = vec3(max(EYEDIR.x, 0.0), max(EYEDIR.y, 0.0), max(-EYEDIR.z, 0.0)) * 4.0; }\n")
	write(dir + "test_glow.gdshader", "shader_type spatial;\nrender_mode cull_disabled;\nuniform vec4 tint : source_color = vec4(0.2, 0.4, 0.6, 1.0); // The tint\n"
		+ "uniform int bands : hint_range(1, 9) = 3;\nuniform bool shiny = true;\nuniform vec2 shift = vec2(0.5, 0.25);\nuniform float free_num = -2.0;\n"
		+ "uniform float _hidden = 1.0;\nuniform sampler2D pic : source_color;\nvoid fragment() { ALBEDO = tint.rgb * texture(pic, UV).rgb; }\n")
	var changed := UserShaders.scan()
	check("scanning finds all six files", changed.size() == 6, str(changed))
	check("the examples compile", UserShaders.ok("example_sky") and UserShaders.ok("example_surface"))
	check("...a sky is a sky, a spatial shader a surface", UserShaders.ids("sky") == ["example_sky", "test_dir"]
		and UserShaders.ids("surface") == ["example_surface", "test_glow"], "%s %s" % [UserShaders.ids("sky"), UserShaders.ids("surface")])
	check("a broken shader isn't used and says which line is wrong", not UserShaders.ok("test_broken")
		and UserShaders.problem("test_broken").begins_with("Line 4:") and UserShaders.problem("test_broken").contains("oops"), UserShaders.problem("test_broken"))
	check("a canvas_item shader is refused with a reason", not UserShaders.ok("test_type") and UserShaders.problem("test_type").contains("canvas_item"))
	check("an unknown shader says it isn't there", UserShaders.problem("nope").contains("isn't in your shaders folder"))
	check("scanning again finds nothing new", UserShaders.scan().is_empty())
	var us: Array = UserShaders.entry("test_glow")["uniforms"]
	var by := {}
	for u in us:
		by[u["name"]] = u
	check("uniforms become controls (\"_hidden\" left out)", by.keys() == ["tint", "bands", "shiny", "shift", "free_num", "pic"], str(by.keys()))
	check("...a vec4 source_color is a color with alpha, its // comment the tooltip", by["tint"]["type"] == "color" and by["tint"]["alpha"]
		and by["tint"]["tip"] == "The tint" and (by["tint"]["default"] as Color).is_equal_approx(Color(0.2, 0.4, 0.6, 1.0)))
	check("...hint_range ints keep their range", by["bands"]["type"] == "int" and by["bands"]["min"] == 1.0 and by["bands"]["max"] == 9.0
		and by["bands"]["default"] == 3.0)
	check("...bools, vectors, images", by["shiny"]["type"] == "bool" and by["shiny"]["default"] == true and by["shift"]["type"] == "vec2"
		and by["shift"]["default"] == Vector2(0.5, 0.25) and by["pic"]["type"] == "image")
	check("...a float without a range gets one around its default", by["free_num"]["min"] < -2.0 and by["free_num"]["max"] > 2.0 and by["free_num"]["free"])
	var sky_u: Array = UserShaders.entry("example_sky")["uniforms"]
	check("the example sky offers its settings (no _seed)", sky_u.size() == 10 and not sky_u.any(func(u): return u["name"] == "_seed"))
	check("the example sky moves (uses TIME)", UserShaders.entry("example_sky")["animated"] and not UserShaders.entry("test_dir")["animated"])

	# ---- the editor
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._select(null)
	ed._refresh_props()
	var sky_ob: OptionButton = ed._fields["env_sky_shader"]
	var labels := []
	for i in sky_ob.item_count:
		labels.append(sky_ob.get_item_text(i))
	check("the Map panel lists MALLET's sky and your sky shaders", labels.size() == 3 and labels[1] == "example_sky" and labels[2] == "test_dir", str(labels))
	check("...with the built-in sky's colors showing", ed._fields["env_sky_builtin"].visible)
	ed._pick_sky_shader("example_sky")
	await process_frame
	var sm = ed.world_env.environment.sky.sky_material
	check("picking a sky shader puts it in the sky", sm is ShaderMaterial and sm.shader == UserShaders.entry("example_sky")["shader"])
	check("...and redraws it every frame (it moves)", ed.world_env.environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME)
	var box: VBoxContainer = ed._fields["env_sky_params"]
	var sliders := []
	var pickers := []
	_collect(box, sliders, pickers)
	check("...its settings show as sliders and color pickers", sliders.size() == 6 and pickers.size() == 4, "%d sliders %d colors" % [sliders.size(), pickers.size()])
	check("...and the built-in sky's colors hide", not ed._fields["env_sky_builtin"].visible)
	var undo_n: int = ed._undo.size()
	(sliders[0] as HSlider).value = 0.9                  # cloud amount
	check("dragging a slider stores the setting in the map", is_equal_approx(float(ed.environment["sky_params"].get("cloud_amount", 0.0)), 0.9),
		str(ed.environment["sky_params"]))
	check("...sets it on the sky that's showing", is_equal_approx(float(ed.world_env.environment.sky.sky_material.get_shader_parameter("cloud_amount")), 0.9))
	check("...and can be undone", ed._undo.size() == undo_n + 1)
	ed._refresh_props()
	check("refreshing the panel keeps the same controls (no rebuild mid-drag)", box.get_meta("setters").size() == 10 and sliders[0].is_inside_tree())
	ed.undo()
	await process_frame
	check("undo brings the old value back", not ed.environment.get("sky_params", {}).has("cloud_amount"))
	ed._pick_sky_shader("test_broken")
	check("a broken sky falls back to the built-in sky", ed.world_env.environment.sky.sky_material.shader == Look.shader("sky"))
	ed._refresh_props()
	var err := _find_text(ed._fields["env_sky_params"])
	check("...and the panel shows its error", err.contains("Line 4") and err.contains("built-in sky"), err)
	ed._pick_sky_shader("example_sky")
	ed._set_sky_param("cloud_color", "ff0000")
	check("a color setting is stored as hex", ed.environment["sky_params"]["cloud_color"] == "ff0000")

	# ramps and blocks with your own shader
	ed._add_ramp_clicked()
	var r: RampNode = ed.selected
	ed._edit_prop("look", "shader")
	await process_frame
	check("a ramp set to \"Your own shader\" takes the first surface shader", r.shader == "example_surface"
		and r._mesh_instance.material_override is ShaderMaterial and ed._fields["shader_box"].visible)
	ed._edit_prop("shader", "test_glow")
	ed._edit_prop("shader_param", ["tint", "ff000080"])
	var rm: ShaderMaterial = r._mesh_instance.material_override
	check("...switching shader and setting a color shows on the ramp", rm.shader == UserShaders.entry("test_glow")["shader"]
		and (rm.get_shader_parameter("tint") as Color).is_equal_approx(Color.html("ff000080")))
	ed._edit_prop("shader", "test_broken")
	check("...a broken one leaves the ramp a plain color (no white faces)", r._mesh_instance.material_override is StandardMaterial3D
		and (r._mesh_instance.material_override as StandardMaterial3D).albedo_color.is_equal_approx(r.color))
	ed._edit_prop("shader", "test_glow")
	ed._edit_prop("shader_param", ["tint", "336699ff"])
	ed._add_block_clicked()
	var b: BlockNode = ed.selected
	ed._edit_prop("block_look", "shader")
	await process_frame
	check("a block with \"Your own shader\" uses it", b.data["shader"] == "example_surface" and ed._fields["block_shader_box"].visible
		and b._mesh.mesh.surface_get_material(0) is ShaderMaterial)
	ed._edit_prop("block_look", "material")
	check("the block Look list picks the right look (Library material)", b.data["look"] == "material")
	ed._edit_prop("block_look", "shader")

	# saving the code into the map, loading it where the file isn't
	var md: Dictionary = ed._map_dict()
	check("the map carries the code of the shaders it uses", md.has("shaders") and md["shaders"].keys().size() == 3
		and String(md["shaders"]["test_glow"]).contains("uniform int bands"), str(md.get("shaders", {}).keys()))
	var md_json := JSON.stringify(md)
	DirAccess.remove_absolute(dir + "test_glow.gdshader")
	ed._rescan_shaders()
	check("deleting a used shader file keeps the map's copy", UserShaders.ok("test_glow") and UserShaders.entry("test_glow")["path"] == "")
	ed._load_dict(JSON.parse_string(md_json))
	await process_frame
	var r2: RampNode = ed.ramps_root.get_child(0)
	check("...the map loads with it", r2.shader == "test_glow" and r2._mesh_instance.material_override is ShaderMaterial
		and (r2._mesh_instance.material_override.get_shader_parameter("tint") as Color).is_equal_approx(Color.html("336699")))
	ed._select(r2)
	ed._refresh_props()
	var ob: OptionButton = ed._fields["shader"]
	check("...and marks it as only in this map", ob.get_item_text(ob.selected).contains("only in this map"), ob.get_item_text(ob.selected))

	# a shader changed on disk while MALLET runs (the user saves it and switches back)
	write(dir + "example_sky.gdshader", FileAccess.get_file_as_string(dir + "example_sky.gdshader") + "
// edited
")
	var v0 := UserShaders.version("example_sky")
	ed.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check("switching back to MALLET reloads a changed shader", UserShaders.version("example_sky") > v0
		and ed.world_env.environment.sky.sky_material.shader == UserShaders.entry("example_sky")["shader"])

	# ---- SurfsUp: embedded, no scripts
	var map: Dictionary = ed._map_dict()
	map["entities"] = [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
		{"kind": "finish", "position": [0, 10, 200], "size": [40, 2, 40], "yaw": 0.0}]
	var scene := SurfsUpExporter.build_scene(map, "shaders_test")
	var we: WorldEnvironment = scene.get_node("WorldEnvironment")
	var esky: ShaderMaterial = we.environment.sky.sky_material
	check("SurfsUp: the map's sky is your shader, embedded (no file path)", esky.shader.code.contains("MALLET example sky")
		and esky.shader.resource_path == "")
	var rmesh: MeshInstance3D = scene.get_node("Ramps").get_child(0).get_node("Mesh")
	var rmat: Material = (rmesh.mesh as ArrayMesh).surface_get_material(0)
	check("SurfsUp: the ramp wears your shader", rmat is ShaderMaterial and (rmat as ShaderMaterial).shader.code.contains("uniform int bands"))
	check("SurfsUp: no scripts anywhere", not has_script(scene))
	var ps := PackedScene.new()
	check("SurfsUp: the scene packs", ps.pack(scene) == OK)
	scene.free()

	# ---- CS:S: surfaces as their base, the sky baked
	var vx := VmfExporter.new()
	var faces: Dictionary = await Look.bake_skybox({"sky_shader": "test_dir", "sun_energy": 0.0}, ed, 64)
	var text := vx.build(map, {"skyname": "mallet_shaders_test", "sky_faces": faces})
	if text == "":
		print("VMF warnings: ", vx.warnings)
	check("CS:S: a shader ramp gets its color as a plain material", text.contains("MALLET/SHADER_336699"))
	check("CS:S: the skyname is the baked sky", text.contains("\"skyname\" \"mallet_shaders_test\""))
	var mats: Array = vx.used_materials.keys() + vx.variant_materials.values()
	var files := VmfExporter.write_materials(mats, out.path_join("css"))
	var sky_files := files.filter(func(p): return String(p[0]).begins_with("materials/skybox/mallet_shaders_test"))
	check("CS:S: six skybox VTFs + VMTs are written", sky_files.size() == 12, str(sky_files.size()))
	var vtf := FileAccess.get_file_as_bytes(out.path_join("css/materials/skybox/mallet_shaders_testrt.vtf"))
	check("CS:S: a skybox face is an uncompressed 64 x 64 VTF", vtf.size() == 80 + 64 * 64 * 3 and vtf.decode_u16(16) == 64 and vtf.decode_u32(52) == 3)
	# which way each face looks: the middle of rt = east (red), bk = north (blue), up = up (green), the top of up = west
	var mid := func(sfx: String, x: int, y: int) -> Color: return (faces[sfx] as Image).get_pixel(x, y)
	check("CS:S: rt looks east, bk north, up up", mid.call("rt", 32, 32).r > 0.5 and mid.call("rt", 32, 32).b < 0.1 and mid.call("bk", 32, 32).b > 0.5
		and mid.call("bk", 32, 32).r < 0.5 and mid.call("up", 32, 32).g > 0.5, "%s %s %s" % [mid.call("rt", 32, 32), mid.call("bk", 32, 32), mid.call("up", 32, 32)])
	check("CS:S: lf, ft and dn look west, south, down (dark)", mid.call("lf", 32, 32).r < 0.1 and mid.call("ft", 32, 32).b < 0.1 and mid.call("dn", 32, 32).g < 0.1)
	check("CS:S: the top of the up face is west, its bottom east", mid.call("up", 32, 1).r < 0.1 and mid.call("up", 32, 62).r > 0.3,
		"%s %s" % [mid.call("up", 32, 1), mid.call("up", 32, 62)])
	check("CS:S: the right side of rt is south (no blue), its left north", mid.call("rt", 62, 32).b < 0.1 and mid.call("rt", 1, 32).b > 0.3)
	var real_sky: Dictionary = await Look.bake_skybox(ed.environment, ed, 256)
	var sheet := Image.create(256 * 4, 256 * 3, false, Image.FORMAT_RGB8)   # the usual cross layout
	for spec in [["up", 1, 0], ["bk", 0, 1], ["rt", 1, 1], ["ft", 2, 1], ["lf", 3, 1], ["dn", 1, 2]]:
		sheet.blit_rect(real_sky[spec[0]], Rect2i(0, 0, 256, 256), Vector2i(spec[1] * 256, spec[2] * 256))
	sheet.save_png(out.path_join("skybox_cross.png"))

	ed.queue_free()
	await process_frame
	print("shaders_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _collect(n: Node, sliders: Array, pickers: Array) -> void:
	for c in n.get_children():
		if c is HSlider:
			sliders.append(c)
		elif c is ColorPickerButton:
			pickers.append(c)
		_collect(c, sliders, pickers)


func _find_text(n: Node) -> String:
	var t := ""
	for c in n.get_children():
		if c is Label:
			t += (c as Label).text
		t += _find_text(c)
	return t
