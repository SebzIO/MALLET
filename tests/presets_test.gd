extends SceneTree
## Presets for light and texture settings (0.19.3): saved under a name, they come back on any light or face (a light
## keeps where it is and which way it points; a face keeps its texture), deleting one forgets it, and they live in a
## file of their own, so they work in every map.
## Run: godot --path . --resolution 1280x720 -s res://tests/presets_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Presets.PATH = "user://presets_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Presets.PATH))
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var w := CubeWorld.new()
	w.set_cell(Vector3i.ZERO, 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("Bricks104"))
	ed._load_dict({"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}],
		"lights": [{"kind": "point", "position": [3.0, 2.0, 1.0], "color": "ff8800", "energy": 4.0, "range": 25.0, "effect": "candle"}]})
	await process_frame
	var bm: BuildMode = ed.build
	var cm: CubeModelNode = ed.cube_models_root.get_child(0)
	bm.start(Transform3D(Basis(), Vector3(0.5, 0.5, 4)), cm)
	await process_frame
	# a light preset
	var l: LightNode = ed.lights_root.get_child(0)
	bm.ent_sel = [l]
	bm._open_light_panel()
	var got := bm._light_preset_now()
	check("a light's preset leaves out where it is", not got.has("position") and got["color"] == "ff8800" and float(got["energy"]) == 4.0)
	Presets.save("light", "Torch", got)
	var d := l.to_dict()
	d["color"] = "0000ff"
	d["energy"] = 1.0
	d["effect"] = "none"
	l.from_dict(d)
	bm._light_preset_apply(Presets.all("light")["Torch"])
	var back := LightNode.spec(l.data)
	check("applying it brings the settings back, the light stays where it is", back["color"] == "ff8800" and float(back["energy"]) == 4.0
		and back["effect"] == "candle" and l.position.is_equal_approx(Vector3(3, 2, 1)), str(back))
	bm._close_light_panel()
	# a texture-settings preset
	bm.ent_sel = []
	bm.sel = CubeWorld.make_sel(Vector3i.ZERO, 0, 4)
	bm.sel["model"] = cm
	bm._tex_param("s", 2.5)
	bm._tex_param("r", 1)
	var tp := bm._tex_preset_now()
	check("a texture preset keeps the settings, not the texture", not tp.has("id") and float(tp["s"]) == 2.5 and int(tp["r"]) == 1)
	check("...and reading it doesn't change what faces show (a copy)", CubeWorld.parse_slot(bm._slot_here())["id"] == "Bricks104")
	Presets.save("texture", "Big bricks", tp)
	bm._tex_param("s", 1.0)
	bm._tex_param("r", 0)
	bm._tex_preset_apply(Presets.all("texture")["Big bricks"])
	var sd := CubeWorld.parse_slot(bm._slot_here())
	check("applying it sets them on the selected faces, keeping their texture", float(sd["s"]) == 2.5 and int(sd["r"]) == 1 and sd["id"] == "Bricks104", str(sd))
	Presets.remove("texture", "Big bricks")
	check("deleting a preset forgets it", not Presets.all("texture").has("Big bricks") and Presets.all("light").has("Torch"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Presets.PATH))
	print("presets_test: ", "PASS" if ok else "FAIL")
	quit()
