extends SceneTree
## The side panel has what build mode's panels have (0.27.2): a light's color cycle and your light presets (F4), and
## texture settings for all of a cube object's faces (F3), each face keeping its own texture; undo works.
## Run: godot --path . --resolution 1280x720 -s res://tests/side_panel_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({"lights": [{"kind": "point", "position": [0.0, 10.0, 0.0], "color": "ff0000", "effect": "pulse"}]})
	await process_frame
	var ln: LightNode = ed.lights_root.get_child(0)
	ed._select(ln)
	await process_frame
	ed._light_color_add(1)
	ed._light_color_add(1)
	await process_frame
	check("a light's panel adds colors to its cycle", (LightNode.spec(ln.data)["colors"] as Array).size() == 2
		and ed._fields["light_swatches"].get_child_count() == 2)
	ed._edit_prop("light_speed", 2.5)
	ed._edit_prop("light_random", true)
	check("...seconds per color and random order", is_equal_approx(float(ln.data["speed"]), 2.5) and bool(ln.data["random"]))
	Presets.remove("light", "side panel test")
	Presets.save("light", "side panel test", ed._light_preset_now())
	ed._edit_prop("light_energy", 9.0)
	ed._edit_prop("light_user_preset", Presets.all("light")["side panel test"])
	check("...and your light presets apply (shared with build mode's F4)", is_equal_approx(float(ln.data["energy"]), 2.0)
		and (ln.data["colors"] as Array).size() == 2)
	Presets.remove("light", "side panel test")
	# a cube object's texture settings
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.begin()
	cm.world.set_cell(Vector3i.ZERO, 0, CubeWorld.FULL, CubeWorld.blank_tex("Bricks104"))
	cm.world.set_cell(Vector3i(8, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex("Metal032"))
	cm.world.commit()
	cm.rebuild_all()
	ed._select(cm)
	await process_frame
	check("a cube object's panel has texture settings", ed._cube_panel.visible and ed._fields.has("cube_tex_sp"))
	ed._edit_prop("cube_tex_sp", 45.0)
	ed._edit_prop("cube_tex_s", 2.0)
	var all_set := true
	var ids := {}
	for k in cm.world.leaves:
		for s in (cm.world.leaves[k][1] as PackedStringArray):
			var d := CubeWorld.parse_slot(s)
			all_set = all_set and is_equal_approx(float(d["sp"]), 45.0) and is_equal_approx(float(d["s"]), 2.0)
			ids[d["id"]] = true
	check("...setting one applies to all its faces", all_set)
	check("...each face keeping its own texture", ids.has("Bricks104") and ids.has("Metal032"), str(ids.keys()))
	ed._edit_prop("cube_tex_stop", true)
	var still := true
	for k in cm.world.leaves:
		for s in (cm.world.leaves[k][1] as PackedStringArray):
			still = still and float(CubeWorld.parse_slot(s)["sp"]) == 0.0
	check("...Stop moving", still)
	ed.undo()
	await process_frame
	var cm2: CubeModelNode = ed.cube_models_root.get_child(0)
	var back := float(CubeWorld.parse_slot(cm2.world.leaves[cm2.world.leaves.keys()[0]][1][0])["sp"])
	check("...and undo puts it back", is_equal_approx(back, 45.0), str(back))
	print("side_panel_test: ", "PASS" if ok else "FAIL")
	quit()
