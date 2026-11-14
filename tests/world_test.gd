extends SceneTree
## 0.5: lights (point and spot), water (see-through, pass-through, deadly lava), glowing blocks, prefabs (the starter
## ones, saving your own, placing them), save / load, both exports and a CS:S compile.
## Screenshot: world.png
## Run: godot --path . --resolution 1600x900 -s res://tests/world_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return ed.get_world_3d().direct_space_state.intersect_ray(q)


func settle() -> void:
	await process_frame
	for i in 3:
		await physics_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(0, 0, -150)
	cam._apply()
	await process_frame

	# lights
	ed._add_light("point")
	var pl: LightNode = ed.selected
	check("Add > Light makes a point light", pl is LightNode and pl._light is OmniLight3D)
	ed._edit_prop("light_energy", 6.0)
	ed._edit_prop("light_color", Color.html("ff0000"))
	check("brightness and color edit the real light", is_equal_approx(pl._light.light_energy, 6.0) and pl._light.light_color.r > 0.99 and pl._light.light_color.g < 0.01)
	ed._edit_prop("light_kind", "spot")
	check("switching to a spot light", pl._light is SpotLight3D and ed._fields["light_spot_box"].visible)
	ed._edit_prop("light_kind", "point")
	ed._duplicate_clicked()
	check("duplicate a light", ed.lights_root.get_child_count() == 2)
	ed._add_light("spot")
	check("Add > Spot light", ed.lights_root.get_child_count() == 3 and ed.selected._light is SpotLight3D)

	# water: you pass through it
	ed._add_water_clicked()
	var water: BlockNode = ed.selected
	water.from_dict({"position": [0, 0, -150], "size": [40, 6, 40], "water": true})
	ed._rebuild_blocks()
	await settle()
	var hit := ray(Vector3(0, 30, -150), Vector3(0, -30, -150))
	check("water isn't solid", hit.is_empty())
	check("water panel shown, material controls hidden", ed._fields["block_water_box"].visible and not ed._fields["block_mat"].visible)
	ed._edit_prop("block_deadly", true)
	check("deadly water (lava)", water.data["deadly"] == true and water.label() == "Deadly liquid")
	# a glowing block
	ed._add_block_clicked()
	var neon: BlockNode = ed.selected
	ed._edit_prop("block_glow", 3.0)
	await settle()
	check("block glow", float(neon.data["glow"]) == 3.0)
	check("normal block shows its material controls again", ed._fields["block_mat"].visible and not ed._fields["block_water_box"].visible and ed._fields["block_cutter"].visible)

	# prefabs
	var pfs := Prefabs.list()
	check("starter prefabs are there", pfs.filter(func(p): return p["builtin"]).size() >= 7, "(%d)" % pfs.size())
	var before: int = ed._all_objects().size()
	var house_path := ""
	for p in pfs:
		if p["name"] == "Small house":
			house_path = p["path"]
	var house: Array = ed.place_prefab(house_path)
	await settle()
	check("placing the house prefab", house.size() >= 6 and ed._all_objects().size() == before + house.size(), "(%d objects)" % house.size())
	check("...as one group", house.all(func(o): return o.has_meta("group") and o.get_meta("group") == house[0].get_meta("group")))
	var c := Vector3.ZERO
	for o in house:
		c += o.center()
	c /= house.size()
	var vc: Vector3 = ed._view_center()
	check("...in the middle of the view", Vector2(c.x, c.z).distance_to(Vector2(vc.x, vc.z)) < 2.0)
	# save my own
	ed._set_selection([neon, pl])
	var mine: String = ed.save_prefab("Test neon thing", "made by world_test")
	check("save selection as a prefab", FileAccess.file_exists(mine))
	check("...and it's listed under yours", Prefabs.list().any(func(p): return p["path"] == mine and not p["builtin"]))
	var copy: Array = ed.place_prefab(mine)
	check("...and places back (block + light)", copy.size() == 2 and copy.any(func(o): return o is LightNode))
	Prefabs.remove(mine)
	check("...removed again", not FileAccess.file_exists(mine))
	for p in pfs:
		if p["builtin"]:
			var n: Array = ed.place_prefab(p["path"])
			for o in n:
				o.translate_by(Vector3(0, 0, 60.0 * pfs.find(p)))
	ed._rebuild_blocks()

	# save / load
	ed.save_map(out + "/world_test.mallet")
	var nl: int = ed.lights_root.get_child_count()
	var nb: int = ed.blocks_root.get_child_count()
	ed._new_map()
	ed.load_map(out + "/world_test.mallet")
	await settle()
	check("lights and water come back with the map", ed.lights_root.get_child_count() == nl and ed.blocks_root.get_child_count() == nb
		and ed.blocks_root.get_children().any(func(b): return b.data.get("water", false)))

	# exports
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_world")
	check("SurfsUp export has the lights", scene.get_node("Lights").get_child_count() == nl)
	scene.free()
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := OS.get_user_data_dir().path_join("test_exports/css/sf_world.vmf")
		var res := VmfExporter.export_vmf(map, vmf)
		var txt := FileAccess.get_file_as_string(vmf)
		check("VMF: light and light_spot entities", txt.contains("\"light\"") and txt.contains("\"light_spot\""))
		check("VMF: water brushes", txt.to_upper().contains("LIQUIDS/AZTECWATER"))
		check("VMF: deadly lava sends you back", txt.contains("trigger_teleport"))
		var cc := VmfExporter.compile(vmf, css, "fast", res.get("materials", []))
		var bad := 0
		for line in String(cc["log"]).split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("duplicate") or l.contains("out of range")):
				bad += 1
				if bad <= 4:
					print("      ", line.strip_edges())
		check("CS:S: prefabs, water and lights compile cleanly", res["error"] == "" and cc["error"] == "" and bad == 0,
			"(%d brushes) %s %s" % [res["brushes"], res["error"], cc["error"]])
	cam.focus = Vector3(0, 6, -60)
	cam.distance = 140.0
	cam.yaw = deg_to_rad(35)
	cam.pitch = deg_to_rad(-25)
	cam._apply()
	ed._select(null)
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/world.png")
	print("WORLD: ", "PASS" if ok else "FAIL")
	quit()
