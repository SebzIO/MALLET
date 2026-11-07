extends SceneTree
## Getridou's materials (0.11): every one loads with its maps and its credit, glow maps make parts shine in the
## editor (library materials and cube faces with texture settings) and in CS:S ($selfillum over a DXT5 alpha mask),
## and the material picker can be searched. Saves a screenshot of a few on cubes, at night so the glow shows.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/getridou_test.gd -- <out folder>

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ids := []
	for e in MaterialLibrary.entries():
		if String(e["id"]).begins_with("getridou_"):
			ids.append(e["id"])
	check("170 Getridou materials, all credited to him", ids.size() == 170
		and ids.all(func(id): return MaterialLibrary.entry(id).get("credit", "") == "Getridou"), "(%d)" % ids.size())
	var lurk := MaterialLibrary.entries().filter(func(e): return String(e["id"]).begins_with("lurking_"))
	check("18 LURKing materials, credited to LURKing in their own section", lurk.size() == 18
		and lurk.all(func(e): return e.get("credit", "") == "LURKing" and e["category"] == "LURKing"), "(%d)" % lurk.size())
	var bad := []
	var glowing := []
	for id in ids:
		for map in MaterialLibrary.entry(id)["maps"]:
			if map != "glow_pulse" and MaterialLibrary.image(id, map) == null:
				bad.append("%s/%s" % [id, map])
		if MaterialLibrary.entry(id)["maps"].has("glow"):
			glowing.append(id)
	check("every map of every Getridou material loads", bad.is_empty(), "%s" % [bad.slice(0, 5)])
	check("Tesseract's scale: a 1024 px texture repeats every 8 m", is_equal_approx(MaterialLibrary.world_size("getridou_artbark"), 8.0))
	var m := MaterialLibrary.material("getridou_traflight")
	check("a glow map makes the material shine (emission)", m.emission_enabled and m.emission_texture != null and glowing.size() >= 20,
		"(%d glowing)" % glowing.size())
	var sm = CubeWorld.material_for("getridou_traflight|c=ffd0d0")
	check("...also on cube faces with texture settings", sm is ShaderMaterial and sm.get_shader_parameter("has_glow") == true)

	# CS:S: DXT5 with the glow in alpha, and $selfillum
	var dir := out + "/css"
	VmfExporter.write_materials(["getridou_traflight", "getridou_artbark"], dir)
	var vt := FileAccess.get_file_as_bytes(dir + "/materials/mallet/getridou_traflight.vtf")
	var fmt := vt.decode_u32(52) if vt.size() > 56 else -1
	var plain := FileAccess.get_file_as_bytes(dir + "/materials/mallet/getridou_artbark.vtf")
	check("CS:S: a glowing texture is DXT5 (its alpha holds the glow)", fmt == 15, "(format %d)" % fmt)
	check("CS:S: ...its material has $selfillum, a plain one doesn't", FileAccess.get_file_as_string(dir + "/materials/mallet/getridou_traflight.vmt").contains("$selfillum")
		and not FileAccess.get_file_as_string(dir + "/materials/mallet/getridou_artbark.vmt").contains("$selfillum") and plain.decode_u32(52) == 13)

	# the picker: credit line and search
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._open_picker(func(_id): pass)
	await process_frame
	var search: LineEdit = ed._fields["picker_search"]
	search.text = "brick"
	search.text_changed.emit("brick")
	var shown: Array = ids.filter(func(id): return (ed._fields["pick_" + id] as Button).visible)
	check("the picker's search finds Getridou's bricks (and hides the rest)", shown.size() >= 5 and shown.size() < 30
		and not (ed._fields["pick_getridou_artbark"] as Button).visible, "(%d shown)" % shown.size())
	check("hovering one says who made it", (ed._fields["pick_getridou_artbark"] as Button).tooltip_text.contains("by Getridou"))
	ed._picker.hide()
	ed.queue_free()
	await process_frame

	# a screenshot: a row of cubes at night
	var w := CubeWorld.new()
	var show := ["getridou_traflight", "getridou_officefacade3", "getridou_sydbrick1", "getridou_lightpadbrise", "getridou_warflame", "getridou_brushsteel"]
	show = show.filter(func(id): return MaterialLibrary.has(id))
	for i in show.size():
		var t := PackedStringArray()
		for f in 6:
			t.append(show[i])
		w.set_cell(Vector3i(i * 40, 0, 0), 2, CubeWorld.FULL, t)      # 4 m cubes, 1 m apart
	var root3 := Node3D.new()
	root.add_child(root3)
	for ck in w.render_chunks():
		var mi := MeshInstance3D.new()
		mi.mesh = w.chunk_mesh(ck)[0]
		root3.add_child(mi)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.04, 0.07)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.35, 0.4)
	env.environment.glow_enabled = true
	root3.add_child(env)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(14.5, 5, 18), Vector3(14.5, 2, 2))
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/getridou.png")
	print("GETRIDOU: ", "PASS" if ok else "FAIL")
	quit()
