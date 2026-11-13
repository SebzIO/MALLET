extends SceneTree
## Material finish, spiral motion and per-pool looks (0.23.0). A made material's finish (brightness x, light of its
## own, gloss, reflections) shows on library materials, cube faces and turned ramp textures, and in the CS:S export;
## gamma in the adjust layer; spin and swirl on cube faces and ramps (and spin in CS:S); water / lava / glass cells
## with a look of their own that still count as water / lava / glass; the map's Reflections setting.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/finish_test.gd -- <out folder>

var ok := true
var made: Array = []


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	# a shiny, bright, glowing material
	var mm: MaterialMakerDialog = ed.open_material_maker("")
	mm.canvas.recipe["name"] = "Test chrome"
	mm.canvas.recipe["color"] = "808080"
	for kv in [["bright", 3.0], ["glow", 25.0], ["gloss", 0.9], ["reflect", 1.0]]:
		mm._finish_changed(kv[0], kv[1])
	var id: String = await mm.save_material(true)
	made.append(id)
	var m := MaterialLibrary.material(id)
	check("brightness goes past 1 (x3)", is_equal_approx(m.albedo_color.r, 3.0), str(m.albedo_color))
	check("light of its own has no cap (25)", m.emission_enabled and is_equal_approx(m.emission_energy_multiplier, 25.0))
	check("gloss 0.9 = roughness 0.1, reflect 1 = metal", is_equal_approx(m.roughness, 0.1) and is_equal_approx(m.metallic, 1.0))
	check("the maker's ball shows the finish", mm._ball.material_override is StandardMaterial3D
		and is_equal_approx((mm._ball.material_override as StandardMaterial3D).metallic, 1.0))
	# gamma
	mm.open_from("")
	mm.canvas.recipe["color"] = "808080"
	var before: Image = await mm.canvas.capture()
	var adj: Dictionary = mm.add_layer("adjust")
	adj["gamma"] = 2.0
	mm.canvas.rebuild()
	var after: Image = await mm.canvas.capture()
	var b0 := before.get_pixel(100, 100).r
	var b1 := after.get_pixel(100, 100).r
	check("gamma 2 in the adjust layer darkens the middle tones", absf(b1 - b0 * b0) < 0.04, "(%.2f -> %.2f)" % [b0, b1])
	mm.hide()
	# cube faces: spin, swirl and the finish
	var slot := CubeWorld.make_slot({"id": id, "sp": 90.0, "sw": 180.0})
	var cm := CubeWorld.material_for(slot)
	check("a cube face can spin and swirl", cm is ShaderMaterial and is_equal_approx(float(cm.get_shader_parameter("spin")), 90.0)
		and is_equal_approx(float(cm.get_shader_parameter("swirl")), 180.0))
	check("...and keeps the material's finish there", is_equal_approx(float(cm.get_shader_parameter("bright")), 3.0)
		and is_equal_approx(float(cm.get_shader_parameter("reflect")), 1.0))
	check("the slot keeps spin / swirl", CubeWorld.parse_slot(slot)["sp"] == 90.0 and CubeWorld.parse_slot(slot)["sw"] == 180.0, slot)
	# ramps
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 50, -40]], "look": "material", "material": id, "tex": {"sp": 45.0}}]})
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	var rm: Material = r._textured.surface_get_material(0) if r._textured else null
	check("a ramp's texture can spin", rm is ShaderMaterial and is_equal_approx(float(rm.get_shader_parameter("spin")), 45.0))
	ed._select(r)
	ed._edit_prop("tex_sw", 5000.0)
	check("...and swirl, any amount typed", is_equal_approx(float(r.tex.get("sw", 0.0)), 5000.0))
	# per-pool looks
	var w := CubeWorld.new()
	var sel := CubeWorld.make_sel(Vector3i.ZERO, 2, 3)
	w.set_material(sel, CubeWorld.mat_name("water", "pool"))
	var sel2 := CubeWorld.make_sel(Vector3i(64, 0, 0), 2, 3)
	w.set_material(sel2, "water")
	var sel3 := CubeWorld.make_sel(Vector3i(128, 0, 0), 2, 3)
	w.set_material(sel3, CubeWorld.mat_name("lava", "magma"))
	var boxes := w.material_boxes()
	check("a pool with its own look is still water (and lava still kills)", boxes.has("water") and (boxes["water"] as Array).size() >= 2
		and boxes.has("lava") and not boxes.has("water:pool"), str(boxes.keys()))
	check("...but looks its own way", CubeWorld.material_look("water:pool") != CubeWorld.material_look("water"))
	ed._build_clicked()
	await process_frame
	var bm: BuildMode = ed.build
	bm.fill_looks["glass"] = "frosted"
	check("the T menu's look choice goes into the fill", CubeWorld.mat_name("glass", bm.fill_looks["glass"]) == "glass:frosted")
	ed.build.stop()
	# the map's reflections
	check("the map's Reflections setting turns on screen-space reflections",
		Look.build_environment({"reflections": true}).ssr_enabled and not Look.build_environment({}).ssr_enabled)
	# CS:S
	var files := VmfExporter.write_materials([id], out)
	var vmt := ""
	for f in files:
		if String(f[0]).ends_with("%s.vmt" % id.to_lower()):
			vmt = FileAccess.get_file_as_string(f[1])
	check("CS:S: reflections as the cubemap, brightness as $color, its own light", vmt.contains("$envmap") and vmt.contains("$color")
		and vmt.contains("$selfillum"), vmt.replace("\n", " "))
	for i in made:
		MaterialLibrary.remove_user(i)
	print("finish_test: ", "PASS" if ok else "FAIL")
	quit()
