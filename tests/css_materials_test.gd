extends SceneTree
## CS:S's own materials, read from the CS:S install (0.11): they're listed and drawn in MALLET, CS:S exports use the
## game's material as it is (right texture scale, nothing written or packed), and SurfsUp exports copy them in only
## when the map maker turns that on (otherwise a similar MALLET material stands in). Skipped without CS:S.
## Run: godot --path . --resolution 1600x900 -s res://tests/css_materials_test.gd -- <out folder>

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	if not CssLibrary.available():
		print("CS:S isn't installed here: skipped")
		print("CSS MATERIALS: PASS")
		quit()
		return
	var list := CssLibrary.entries()
	check("thousands of CS:S world materials are listed", list.size() > 2000, "(%d)" % list.size())
	var id := "css:brick/brickwall045j"
	check("a CS:S material is in the library like any other", MaterialLibrary.has(id) and MaterialLibrary.entry(id)["surface"] == "brick")
	var img := MaterialLibrary.image(id, "color")
	check("its texture is read from the game (512 px)", img != null and img.get_width() == 512 and MaterialLibrary.texture_px(id) == 512)
	check("its size is the game's: 512 texels x 0.25 units = 3.25 m", absf(MaterialLibrary.world_size(id) - 128.0 / 39.37) < 0.01)
	var m := MaterialLibrary.material(id)
	check("it builds a material (drawn in the editor)", m.albedo_texture != null and MaterialLibrary.preview(id) != null)
	var with_bump := list.filter(func(e): return (e["maps"] as Dictionary).has("normal"))
	check("materials with bump maps get them", not with_bump.is_empty() and MaterialLibrary.image(with_bump[0]["id"], "normal") != null,
		"(%d with bump)" % with_bump.size())

	# a map: a block in CS:S brick, a cube in tinted CS:S concrete
	var map := {"format": "mallet-map", "version": 2, "environment": Look.preset_environment("day"), "ramps": [], "props": [],
		"texts": [], "lights": [], "cube_models": [],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 200], "size": [40, 2, 40], "yaw": 0.0}],
		"blocks": [{"position": [0, -4, 100], "size": [16, 8, 16], "material": id}]}
	var cw := CubeWorld.new()
	var t := PackedStringArray()
	for f in 6:
		t.append("css:concrete/concretefloor005a|c=ff8080")
	cw.set_cell(Vector3i(0, 0, 0), 3, CubeWorld.FULL, t)
	map["cube_models"] = [{"position": [40.0, 0.0, 100.0], "yaw": 0.0, "cubes": cw.to_dict()}]
	check("the map counts its CS:S materials", SurfsUpExporter.css_count(map) == 2, "(%d)" % SurfsUpExporter.css_count(map))

	# CS:S export: the game's own materials by name, at the game's scale; only the tinted copy's .vmt is written
	var res := VmfExporter.export_vmf(map, out + "/sf_css_mats.vmf")
	var vmf := FileAccess.get_file_as_string(out + "/sf_css_mats.vmf")
	check("CS:S: exports", res["error"] == "", res["error"])
	check("CS:S: the block uses the game's brick material by its own name", vmf.contains("\"material\" \"brick/brickwall045j\""))
	check("CS:S: ...at the game's texture scale (0.25)", vmf.contains("] 0.25\""))
	var vexp := VmfExporter.new()
	vexp.build(map)
	var written := VmfExporter.write_materials(vexp.used_materials.keys() + vexp.variant_materials.values(), out + "/css_written")
	var tinted := written.filter(func(w): return String(w[0]).ends_with(".vmt"))
	check("CS:S: nothing of Valve's is written, just the tinted copy's .vmt", written.size() == 1 and tinted.size() == 1
		and FileAccess.get_file_as_string(tinted[0][1]).contains("\"$basetexture\" \"concrete/concretefloor005a\""), "(%s)" % [written])

	# a real compile with Valve's tools: the game's materials are found, the tinted copy is packed in
	var cvmf := OS.get_user_data_dir().path_join("test_exports/css/sf_css_mats.vmf")
	var cres := VmfExporter.export_vmf(map, cvmf)
	var c := VmfExporter.compile(cvmf, CssLibrary.root(), "fast", cres.get("materials", []))
	var clog: String = String(c["log"]).to_lower()
	check("CS:S compile: the tools find the game's materials and the tinted copy", c["error"] == "" and clog.count("not found") == 0,
		"%s (%d 'not found')" % [c["error"], clog.count("not found")])

	# SurfsUp: off = a similar MALLET material; on = the real texture
	var off := SurfsUpExporter.without_css(map)
	check("SurfsUp, off: CS:S brick becomes MALLET brick", off["blocks"][0]["material"] == "Bricks104" and SurfsUpExporter.css_count(off) == 0)
	check("SurfsUp, off: the cube keeps its tint on the stand-in", (off["cube_models"][0]["cubes"]["palette"] as Array).has("Concrete034|c=ff8080"),
		"(%s)" % [off["cube_models"][0]["cubes"]["palette"]])
	check("SurfsUp: the map itself is left alone", map["blocks"][0]["material"] == id)
	var scene_on: Node3D = SurfsUpExporter.build_scene(map, "sf_css_on")
	var found_css := false
	for n in scene_on.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat = mi.get_active_material(si)
			if mat is StandardMaterial3D and mat.resource_name == id:
				found_css = true
	check("SurfsUp, on: the block carries the real CS:S texture", found_css)
	scene_on.free()

	# the picker: CS:S folders, filled when searched
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._open_picker(func(_x): pass)
	await process_frame
	check("the picker lists CS:S folders (closed until opened)", not ed._fields.has("pick_" + id))
	var search: LineEdit = ed._fields["picker_search"]
	search.text = "brickwall045j"
	search.text_changed.emit("brickwall045j")
	# (the button and its folder, not the popup window itself: a popup closes when another window - the compiler's
	# console above - takes the focus)
	check("searching opens the right folder and shows it", ed._fields.has("pick_" + id) and (ed._fields["pick_" + id] as Button).visible
		and (ed._fields["pick_" + id] as Button).get_parent().visible)
	ed._picker.hide()
	print("CSS MATERIALS: ", "PASS" if ok else "FAIL")
	quit()
