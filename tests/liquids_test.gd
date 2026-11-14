extends SceneTree
## Better water, lava and glass (0.11): every preset builds, a block's liquid preset sets its look and whether it's
## deadly, build mode's water / lava / glass follow the Map panel's looks, and CS:S gets the preset's water material,
## lava as a glowing pass-through surface, glass tinted. Saves pictures: water (sunny, over a sloping floor), lava, glass.
## Run: godot --path . --resolution 1280x720 -s res://tests/liquids_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func block(root3: Node3D, d: Dictionary) -> BlockNode:
	var b := BlockNode.new()
	root3.add_child(b)
	b.from_dict(d)
	b.rebuild()
	return b


func shot(root3: Node3D, cam_from: Vector3, at: Vector3, path: String) -> Image:
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(cam_from, at)
	cam.make_current()
	for i in 10:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	cam.queue_free()
	return img


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var made := 0
	for id in Look.LIQUID_ORDER:
		var m := Look.liquid_material(id)
		made += 1 if m.shader != null and m.shader.code != "" else 0
	for id in Look.GLASS_ORDER:
		made += 1 if Look.glass_material(id).shader != null else 0
	check("every liquid and glass preset builds a material", made == Look.LIQUID_ORDER.size() + Look.GLASS_ORDER.size())

	# the editor: a block's preset sets its look and deadliness; build mode's looks come from the Map panel
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	var wb := BlockNode.new()
	ed.blocks_root.add_child(wb)
	wb.from_dict({"position": [0, 0, 0], "size": [8, 2, 8], "water": true})
	ed._select(wb)
	ed._edit_prop("block_liquid", "lava")
	check("picking Lava for a water block makes it lava, and deadly", wb.data["liquid"] == "lava" and wb.data["deadly"] == true)
	ed._edit_prop("block_liquid", "pool")
	check("...picking Swimming pool makes it water, not deadly", wb.data["liquid"] == "pool" and wb.data["deadly"] == false
		and wb.data["water_color"] == Look.LIQUIDS["pool"]["color"])
	ed._edit_mat_look("water_look", "swamp")
	var wm := CubeWorld.material_look("water") as ShaderMaterial
	check("Map panel: build mode water turns into the swamp", CubeWorld.mat_looks["water"] == "swamp"
		and is_equal_approx(float(wm.get_shader_parameter("clarity")), float(Look.LIQUIDS["swamp"]["clarity"])))
	ed.environment = Look.default_environment()
	ed._apply_environment()
	var e1: Dictionary = ed.environment.duplicate()
	e1["water_look"] = "tropical"
	ed.environment = e1
	ed._fields["env_preset"].item_selected.emit(1)
	check("a sky preset keeps the build mode water look", ed.environment.get("water_look", "") == "tropical")

	# CS:S
	var cw := CubeWorld.new()
	cw.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3, Vector3i(2, 1, 2)), "water")
	cw.set_material(CubeWorld.make_sel(Vector3i(0, 0, 32), 0, 3, Vector3i(2, 1, 2)), "glass")
	cw.set_material(CubeWorld.make_sel(Vector3i(0, 0, 64), 0, 3, Vector3i(2, 1, 2)), "lava")
	var env := Look.default_environment()
	env["water_look"] = "tropical"
	env["glass_look"] = "smoked"
	env["lava_look"] = "plasma"
	var map := {"format": "mallet-map", "version": 2, "environment": env, "ramps": [], "props": [], "texts": [], "lights": [],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 200], "size": [40, 2, 40], "yaw": 0.0}],
		"blocks": [{"position": [40, 0, 0], "size": [8, 2, 8], "water": true, "liquid": "lake"},
			{"position": [60, 0, 0], "size": [8, 2, 8], "water": true, "liquid": "magma", "deadly": true}],
		"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": cw.to_dict()}]}
	var vx := VmfExporter.new()
	var text := vx.build(map)
	check("CS:S: a 'Dark lake' block is CS:S's Militia water", text.contains("\"material\" \"liquids/militiawater\""))
	check("CS:S: build mode water uses the map's look (tropical: coastal water)", text.contains("\"material\" \"nature/water_coast01\""))
	check("CS:S: a magma block is a glowing pass-through surface, not water", text.contains("MALLET/SF_LAVA_MAGMA")
		and text.contains("func_illusionary"))
	check("CS:S: build mode lava and glass follow their looks", text.contains("MALLET/SF_LAVA_PLASMA") and vx.variant_materials.has("sf_glass")
		and String(vx.variant_materials["sf_glass"]["color"]) == Look.GLASS["smoked"]["color"])

	# pictures
	ed.queue_free()
	await process_frame
	var root3 := Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	we.environment = Look.build_environment(Look.preset_environment("day"))
	root3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	root3.add_child(sun)
	# a sloping sandy floor going down under the water, a wall, water over it
	block(root3, {"position": [0, -3, 0], "size": [30, 2, 30], "pitch": 8.0, "material": "Gravel043"})
	block(root3, {"position": [6, 0, -8], "size": [10, 6, 2], "material": "Bricks104"})
	block(root3, {"position": [0, -2, 0], "size": [30, 3, 30], "water": true, "liquid": "tropical"})
	var img_w: Image = await shot(root3, Vector3(-12, 7, 14), Vector3(2, -1, -2), out + "/water.png")
	for c in root3.get_children():
		if c is BlockNode:
			c.queue_free()
	block(root3, {"position": [0, -2, 0], "size": [30, 3, 30], "water": true, "liquid": "lava", "deadly": true})
	await shot(root3, Vector3(-10, 6, 12), Vector3(0, -1, 0), out + "/lava.png")
	for c in root3.get_children():
		if c is BlockNode:
			c.queue_free()
	block(root3, {"position": [0, 0, 0], "size": [20, 2, 20], "material": "Tiles107"})
	var gw := CubeWorld.new()
	gw.set_material(CubeWorld.make_sel(Vector3i(-16, 8, -8), 1, 3, Vector3i(1, 2, 2)), "glass")
	var gm := CubeModelNode.new()
	gm.world = gw
	root3.add_child(gm)
	CubeWorld.set_mat_looks({"glass_look": "frosted"})
	gm.rebuild_all()
	block(root3, {"position": [2, 1, -6], "size": [3, 4, 3], "material": "Bricks094"})
	await shot(root3, Vector3(0, 3, 9), Vector3(0, 2, -4), out + "/glass.png")
	var c0 := img_w.get_pixel(640, 500)
	check("the water picture isn't blank", c0.a > 0.0 and (c0.r + c0.g + c0.b) > 0.05, "(%s)" % c0)
	print("LIQUIDS: ", "PASS" if ok else "FAIL")
	quit()
