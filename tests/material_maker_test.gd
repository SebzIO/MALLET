extends SceneTree
## The material maker (0.21.0): a material from a starting material (or a plain color) plus layers. A ridge line
## (a stripe in the middle, "fit across a ramp") lands on a ramp's ridge; painting, adjusting and saving over work;
## a starting material's surface detail comes along; your materials travel inside the maps that use them.
## Run: godot --path . --resolution 1280x720 -s res://tests/material_maker_test.gd -- <out folder>

var ok := true
var made: Array = []


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func lum(img: Image, u: float, v: float) -> float:
	return img.get_pixel(int(u * (img.get_width() - 1)), int(v * (img.get_height() - 1))).get_luminance()


func color_of(id: String) -> Image:
	return Image.load_from_file(String(MaterialLibrary.entry(id)["dir"]) + "color.jpg")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	# a plain gray one with a ridge line
	var got := []
	var mm: MaterialMakerDialog = ed.open_material_maker("", func(id: String): got.append(id))
	mm.canvas.recipe["name"] = "Test ridge"
	mm.canvas.recipe["color"] = "b0b0b0"
	mm.add_ridge_line()
	var id: String = await mm.save_material(true)
	made.append(id)
	check("saved as a new material in \"Made by you\"", id.begins_with("made_") and MaterialLibrary.has(id)
		and MaterialLibrary.entry(id)["category"] == "Made by you" and MaterialLibrary.is_made(id), id)
	check("...and handed to where the picker was opened from", got == [id])
	var img := color_of(id)
	check("the ridge line is dark down the middle, the rest gray", img != null and lum(img, 0.5, 0.3) < 0.1 and lum(img, 0.2, 0.3) > 0.5,
		"(middle %.2f, side %.2f)" % [lum(img, 0.5, 0.3), lum(img, 0.2, 0.3)] if img else "")
	check("...and fits across a ramp", MaterialLibrary.ramp_fit(id))
	var rm := Look.ramp_material("material", Color.WHITE, "", 20.0, id, 10.5) as StandardMaterial3D
	check("on a ramp one repeat spans the riding surface (ridge in the middle)", rm != null and is_equal_approx(rm.uv1_scale.x, 1.0),
		str(rm.uv1_scale if rm else ""))
	# a real ramp: the ridge's u is the middle
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 50, -40]], "look": "material", "material": id}]})
	await process_frame
	var ramp: RampNode = ed.ramps_root.get_child(0)
	var mesh: ArrayMesh = ramp.geometry["mesh"]
	var top_u := -1.0
	if mesh:
		var arr := mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var best := -INF
		for i in vs.size():
			if vs[i].y > best:
				best = vs[i].y
				top_u = uvs[i].x
	check("...a ramp's ridge is at the middle of the texture", mesh == null or absf(top_u - 0.5) < 0.02, "(u %.3f%s)" % [top_u, "" if mesh else ", mesh not found"])
	# paint, then save over
	var pl: Dictionary = mm.add_layer("paint")
	mm.brush_color = Color(1, 0, 0)
	mm.brush_size = 40
	mm.paint_line(Vector2(0.2, 0.8), Vector2(0.3, 0.8))
	check("painting marks the paint layer", (mm.canvas.images[pl["file"]] as Image).get_pixel(256, 819).a > 0.9)
	var id2: String = await mm.save_material(false)
	img = color_of(id2)
	var px := img.get_pixel(256, 819) if img else Color.BLACK
	check("Save saves over it (same material), with the paint", id2 == id and px.r > 0.7 and px.g < 0.3, str(px))
	check("...its paint kept as a file, to change later", FileAccess.file_exists(String(MaterialLibrary.entry(id)["dir"]) + String(pl["file"])))
	# opening it again
	mm.open_from(id)
	check("opening it again brings its layers back", mm.editing_id == id and mm.canvas.recipe["layers"].size() == 2
		and mm.canvas.images.has(pl["file"]))
	# adjust: brightness down
	var adj: Dictionary = mm.add_layer("adjust")
	adj["bright"] = -1.0
	mm.canvas.recipe["name"] = "Test dark"
	var id3: String = await mm.save_material(true)
	made.append(id3)
	img = color_of(id3)
	check("an adjust layer changes what is under it (brightness down: black)", img != null and lum(img, 0.2, 0.3) < 0.05, "(%.2f)" % (lum(img, 0.2, 0.3) if img else -1.0))
	# from a starter material: its surface detail comes along; multiply darkens
	var starter := ""
	for e in MaterialLibrary.entries():
		if not MaterialLibrary.is_own(e["id"]) and (e.get("maps", {}) as Dictionary).has("normal"):
			starter = e["id"]
			break
	mm.open_from(starter)
	var before: Image = await mm.canvas.capture()
	var f: Dictionary = mm.add_layer("fill")
	f["blend"] = "multiply"
	f["color"] = "404040"
	f["opacity"] = 1.0
	mm.canvas.rebuild()
	var after: Image = await mm.canvas.capture()
	check("a multiply fill darkens the starting material", lum(after, 0.4, 0.4) < lum(before, 0.4, 0.4) * 0.5,
		"(%.2f -> %.2f)" % [lum(before, 0.4, 0.4), lum(after, 0.4, 0.4)])
	var id4: String = await mm.save_material(true)
	made.append(id4)
	var maps: Dictionary = MaterialLibrary.entry(id4)["maps"]
	check("starting from %s keeps its surface detail (normal map)" % starter, maps.has("normal") and MaterialLibrary.material(id4).normal_enabled)
	# text and a shape draw
	mm.open_from("")
	var t: Dictionary = mm.add_layer("text")
	t["text"] = "XX"
	t["size"] = 0.4
	t["color"] = "000000"
	mm.canvas.rebuild()
	var ti: Image = await mm.canvas.capture()
	var dark := 0
	for y in range(200, 312, 4):
		for x in range(150, 362, 4):
			if ti.get_pixel(x, y).get_luminance() < 0.2:
				dark += 1
	check("a text layer draws its words", dark > 40, "(%d dark samples)" % dark)
	# maps carry them
	var path := out + "/own_mats.mallet"
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 50, -40]], "look": "material", "material": id}]})
	await process_frame
	ed.save_map(path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check("a saved map carries the materials of yours it uses (and only those)", saved.has("own_materials")
		and (saved["own_materials"] as Dictionary).has(id) and not (saved["own_materials"] as Dictionary).has(id3))
	MaterialLibrary.remove_user(id)
	check("(removed here, as on a friend's PC)", not MaterialLibrary.has(id))
	ed.load_map(path)
	await process_frame
	check("opening the map puts it back in the library, recipe and all", MaterialLibrary.has(id) and MaterialLibrary.is_made(id))
	# co-editing: a package arriving installs and is drawn
	var pkg := MaterialLibrary.package(id3)
	MaterialLibrary.remove_user(id3)
	ed.session_role = "editor"
	ed._co_apply({"t": "edit", "op": {"act": "mats", "mats": {id3: pkg}}, "name": "Friend"})
	ed.session_role = ""
	check("a co-editor's new material arrives", MaterialLibrary.has(id3))
	check("an older copy doesn't replace a newer one", not MaterialLibrary.install(pkg))
	# exports read it like any material
	var vimg := MaterialLibrary.image(id, "color")
	check("exports read it like any material (CS:S converts its color map)", vimg != null and vimg.get_width() == MaterialMaker.SIZE)
	# CS:S: the riding faces' texture axes put the ridge in the middle of the texture
	var vmap := {"ramps": [{"points": [[0, 50, 0], [0, 50, -40]], "look": "material", "material": id}],
		"entities": [{"kind": "start", "position": [0.0, 60.0, 30.0], "size": [20.0, 2.0, 20.0], "yaw": 0.0},
			{"kind": "finish", "position": [0.0, 10.0, -80.0], "size": [20.0, 2.0, 20.0], "yaw": 0.0}]}
	VmfExporter.export_vmf(vmap, out + "/fit.vmf")
	var vmf := FileAccess.get_file_as_string(out + "/fit.vmf")
	var mid_hits := 0
	var fitted := 0
	var rx := RegEx.create_from_string(r'"plane" "\(([^)]*)\) \(([^)]*)\) \(([^)]*)\)"\s*"material" "mallet/%s"\s*"uaxis" "\[([^\]]*)\] ([0-9.e-]+)"' % id.to_lower())
	var pxs := float(MaterialLibrary.texture_px(id))
	for m in rx.search_all(vmf):
		if is_equal_approx(float(m.get_string(5)), 0.25):
			continue
		fitted += 1
		var axv := m.get_string(4).split_floats(" ")
		for g in [1, 2, 3]:
			var p := m.get_string(g).split_floats(" ")
			var u := (p[0] * axv[0] + p[1] * axv[1] + p[2] * axv[2]) / float(m.get_string(5)) + axv[3]
			if absf(u - pxs * 0.5) < pxs * 0.01:
				mid_hits += 1
	check("CS:S: the riding faces are fitted, the ridge at the texture's middle", fitted >= 2 and mid_hits >= 2, "(%d fitted sides, %d ridge points)" % [fitted, mid_hits])
	mm.hide()
	for m in made:
		MaterialLibrary.remove_user(m)
	print("material_maker_test: ", "PASS" if ok else "FAIL")
	quit()
