extends SceneTree
## Materials: the library loads; a block takes a material for all sides, one side its own, Alt+click paints a face;
## texture size / turn change the UVs; a ramp wears a library material; the SurfsUp export carries the textures
## (read back from the saved scene); the CS:S export converts the used materials to VTF/VMT, the compile finds them
## (no "material not found") and packs them into the .bsp. Screenshots: materials.png, picker.png
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/material_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func block(d: Dictionary) -> BlockNode:
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict(d)
	return b


func surface_names(b: BlockNode) -> Array:
	var m: ArrayMesh = b._mesh.mesh
	var out := []
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		out.append(mat.resource_name if mat and mat.resource_name != "" else "look")
	return out


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var built_in := MaterialLibrary.entries().filter(func(e): return String(e["dir"]).begins_with("res://"))
	var cc0 := built_in.filter(func(e): return not e.has("credit"))
	check("library: 19 ambientCG materials + 170 by Getridou + 18 by LURKing", cc0.size() == 19 and built_in.size() == 207, "(%d, %d)" % [cc0.size(), built_in.size()])
	var m := MaterialLibrary.material("Bricks104")
	check("a material has color, normal and roughness maps", m.albedo_texture != null and m.normal_texture != null and m.roughness_texture != null)
	check("metals get a metalness map", MaterialLibrary.material("Metal009").metallic_texture != null)

	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var floor_b := block({"position": [0, 50, -80], "size": [40, 1, 40], "material": "WoodFloor051", "color": "ffffff"})
	var room := block({"position": [0, 51, -80], "size": [24, 10, 24], "hollow": true, "wall": 1.0, "material": "Bricks104", "color": "ffffff"})
	ed._rebuild_blocks()
	check("whole block in one material", surface_names(floor_b) == ["WoodFloor051"], str(surface_names(floor_b)))
	# give the room's top its own material through the panel
	ed._select(room)
	ed._block_side = "top"
	ed._edit_prop("block_mat", "CorrugatedSteel009")
	check("one side its own material (the roof)", "CorrugatedSteel009" in surface_names(room) and "Bricks104" in surface_names(room),
		str(surface_names(room)))
	# Alt+click paints the front face of the floor
	for i in 3:
		await physics_frame
	var front: ViewPane = ed.panes[2]                     # looks along X: sees the floor's +X side
	front.frame(Vector3(0, 50, -80), 40.0)
	await process_frame
	ed._paint = "Marble012"
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.alt_pressed = true
	ev.position = front.camera.unproject_position(Vector3(20, 50.5, -70))
	ed.pane_input(front, ev)
	check("Alt+click paints the face under the mouse", floor_b.data["faces"].get("right", {}).get("material", "") == "Marble012",
		str(floor_b.data["faces"]))
	# texture size and turn change the UVs (a 2x bigger texture halves them)
	var s := BlockShape.spec(floor_b.data)
	var uv1 := BlockShape.face_uv(Vector3(3, 51, 7), Vector3.UP, BlockShape.face_settings(s, "top"))
	s["uv_scale"] = 2.0
	var uv2 := BlockShape.face_uv(Vector3(3, 51, 7), Vector3.UP, BlockShape.face_settings(s, "top"))
	check("texture size x2 halves the texture coordinates", uv1.distance_to(uv2 * 2.0) < 1e-4, "%s vs %s" % [uv1, uv2])
	# a ramp in a library material
	var r: RampNode = ed.ramps_root.get_child(0)
	ed._select(r)
	ed._edit_prop("look", "material")
	ed._edit_prop("material", "Metal009")
	var rm: Material = r._mesh_instance.material_override
	check("a ramp can wear a library material", rm is StandardMaterial3D and (rm as StandardMaterial3D).albedo_texture != null)

	# SurfsUp export: the textures go inside the map
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_mat")
	var packed := PackedScene.new()
	packed.pack(scene)
	scene.free()
	ResourceSaver.save(packed, "user://mat_check.tscn")
	var back: PackedScene = ResourceLoader.load("user://mat_check.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var inst := back.instantiate()
	var mesh: ArrayMesh = inst.get_node("Blocks/Block0/Mesh").mesh
	var mat: StandardMaterial3D = mesh.surface_get_material(0)
	var img: Image = mat.albedo_texture.get_image() if mat and mat.albedo_texture else null
	check("SurfsUp export carries the material's pixels", img != null and img.get_width() >= 512, str(img.get_size()) if img else "none")
	inst.free()

	# CS:S: VTF + VMT, found by the compiler, packed into the map
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := "D:/SurfForge_exports/css/sf_materials.vmf"
		var res := VmfExporter.export_vmf(map, vmf)
		var mats: Array = res.get("materials", [])
		check("CS:S export lists the materials it uses", mats.size() == 5, str(mats))
		var c := VmfExporter.compile(vmf, css, "fast", mats)
		var log: String = c["log"]
		var missing := log.count("not found")
		check("compiles; the tools find every material", c["error"] == "" and not log.to_lower().contains('material "mallet'),
			"%s (%d 'not found' lines)" % [c["error"], missing])
		var listing := []
		var bin := css + "/bin/x64/bspzip.exe"
		OS.execute(bin, PackedStringArray(["-game", css + "/cstrike", "-dir", c["bsp"] if c["bsp"] != "" else vmf.get_basename() + ".bsp"]), listing, true)
		var inside: String = "".join(listing).to_lower()
		check("the textures are packed inside the .bsp", inside.contains("materials/mallet/bricks104.vtf") and inside.contains("materials/mallet/metal009.vmt"))
		var vtf := FileAccess.get_file_as_bytes(css + "/cstrike/materials/mallet/bricks104.vtf")
		check("VTF header: 'VTF', v7.2, 512x512, DXT1", vtf.size() > 80 and vtf.slice(0, 3).get_string_from_ascii() == "VTF"
			and vtf.decode_u32(4) == 7 and vtf.decode_u32(8) == 2 and vtf.decode_u16(16) == 512 and vtf.decode_u32(52) == 13)
	# your own image becomes a material
	var own := Image.create(64, 64, false, Image.FORMAT_RGB8)
	own.fill(Color(0.2, 0.6, 0.9))
	own.save_png(out + "/my_logo.png")
	ed._select(floor_b)
	ed._block_side = "all"
	ed._picker_cb = func(id): ed._edit_prop("block_mat", id)
	var oid: String = ed.add_own_material(out + "/my_logo.png")
	check("your own image becomes a material and is applied", oid.begins_with("user_") and floor_b.data["material"] == oid
		and MaterialLibrary.entry(oid).get("category", "") == "Your images")
	MaterialLibrary.remove_user(oid)                     # leave your own library as it was
	check("...and can be removed again", not MaterialLibrary.has(oid))
	ed._select(room)
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(0, 55, -80)
	cam.distance = 55.0
	cam.yaw = deg_to_rad(35)
	cam.pitch = deg_to_rad(-25)
	cam._apply()
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/materials.png")
	ed._open_picker(func(_id): pass)
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/picker.png")
	print("MATERIALS: ", "PASS" if ok else "FAIL")
	quit()
