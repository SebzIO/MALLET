extends SceneTree
## glTF props: a model written to .glb here (an arch with a textured material) is imported, placed, turned, sized,
## duplicated, undone, saved and loaded; solid props block players and jump arcs (collision layer 1), decorative
## ones don't; a missing file shows a stand-in and blocks export; the exported scene carries the meshes with
## compressed textures and collision, no scripts and no reference back to the .glb, and loads on its own.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/prop_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## An arch: two pillars and a beam, 12 m wide and 10 m tall, with a striped texture. Written as .glb.
func make_model(path: String) -> void:
	var root := Node3D.new()
	root.name = "Arch"
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			img.set_pixel(x, y, Color(0.85, 0.55, 0.3) if (x / 32) % 2 == 0 else Color(0.35, 0.25, 0.2))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	for spec in [[Vector3(-5, 4, 0), Vector3(2, 8, 2)], [Vector3(5, 4, 0), Vector3(2, 8, 2)], [Vector3(0, 9, 0), Vector3(12, 2, 2)]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		box.material = mat
		mi.mesh = box
		mi.position = spec[0]
		root.add_child(mi)
		mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, path)
	root.free()


func ray_hits(from: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 100.0)
	q.collision_mask = mask
	return ed.get_world_3d().direct_space_state.intersect_ray(q)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var path := out + "/test_arch.glb"
	make_model(path)
	check("test model written", FileAccess.file_exists(path))
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame

	var pr: PropNode = ed.add_prop(path, Vector3(0, 50, -60))
	var sz := pr.world_size()
	check("model imported", pr.error == "" and pr.triangles > 0, "(%d triangles)" % pr.triangles)
	check("size as modelled (12 x 10 x 2 m)", sz.distance_to(Vector3(12, 10, 2)) < 0.05, str(sz.snapped(Vector3.ONE * 0.01)))
	for i in 3:
		await physics_frame
	var hit := ray_hits(Vector3(0, 80, -60), 1)
	check("solid: the beam stops players and jump arcs (layer 1)", not hit.is_empty() and absf(hit["position"].y - 60.0) < 0.05,
		"(hit at y %.2f)" % (hit["position"].y if not hit.is_empty() else -1.0))
	check("the gap under the arch is open", ray_hits(Vector3(0, 57, -60), 1).is_empty() or ray_hits(Vector3(0, 57, -60), 1)["position"].y < 50.1)

	# size, facing, decoration
	ed._select(pr)
	ed._edit_prop("prop_size", 2.0)
	check("Size x2 doubles it", pr.world_size().distance_to(Vector3(24, 20, 4)) < 0.1)
	ed._edit_prop("prop_yaw", 90.0)
	var edges := pr.outline_lines()
	var xs := []
	for e in edges:
		xs.append(e[0].x)
	check("turned 90 deg: now thin along x", absf(xs.max() - xs.min() - 4.0) < 0.1, "(x span %.1f)" % (xs.max() - xs.min()))
	ed._edit_prop("prop_solid", false)
	for i in 3:
		await physics_frame
	check("decoration: players fly through (nothing on layer 1)", ray_hits(Vector3(0, 100, -60), 1).is_empty())
	check("...but the editor can still click it", not ray_hits(Vector3(0, 100, -60), PropNode.PICK_ONLY_LAYER).is_empty())
	ed._edit_prop("prop_solid", true)

	# undo, duplicate, save / load
	var before: Dictionary = pr.to_dict()
	ed._checkpoint()
	pr.translate_by(Vector3(30, 0, 0))
	ed.undo()
	var back: PropNode = ed.props_root.get_child(0)
	check("undo puts it back", back.to_dict() == before)
	ed._select(back)
	ed._duplicate_clicked()
	check("duplicate", ed.props_root.get_child_count() == 2)
	var map_path := out + "/prop_test.mallet"
	ed.save_map(map_path)
	ed._new_map()
	check("a new map has no props", ed.props_root.get_child_count() == 0)
	ed.load_map(map_path)
	check("props come back with the map", ed.props_root.get_child_count() == 2 and ed.props_root.get_child(0).to_dict() == before)

	# export
	var map: Dictionary = ed._map_dict()
	check("export check passes", SurfsUpExporter.check(map).is_empty())
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_props")
	var p0: Node = scene.get_node_or_null("Props/Prop0")
	check("exported: meshes + collision", p0 is StaticBody3D and p0.get_node_or_null("Collision") != null and p0.get_child_count() == 4)
	var packed := PackedScene.new()
	packed.pack(scene)
	scene.free()
	ResourceSaver.save(packed, "user://prop_check.tscn")
	var text := FileAccess.get_file_as_string("user://prop_check.tscn")
	check("no scripts, no link back to the .glb", not text.contains("script") and not text.contains(".glb") and not text.contains("ext_resource"))
	check("textures embedded and compressed", text.contains("PortableCompressedTexture2D"))
	var reloaded: PackedScene = ResourceLoader.load("user://prop_check.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var inst := reloaded.instantiate()
	var mi: MeshInstance3D = inst.get_node("Props/Prop0/Mesh0")
	var tex: Texture2D = mi.mesh.surface_get_material(0).albedo_texture if mi and mi.mesh else null
	var img: Image = tex.get_image() if tex else null
	check("the exported scene loads on its own, texture pixels included", img != null and img.get_width() == 256,
		"(%s)" % (str(img.get_size()) if img else "no image"))
	inst.free()

	# a missing model
	var lost: PropNode = ed.add_prop(out + "/does_not_exist.glb", Vector3(80, 50, 0))
	check("missing file: a magenta stand-in, and a clear message", lost.error.contains("not found") and lost.world_size().y > 3.0)
	check("missing file blocks export with a reason", not SurfsUpExporter.check(ed._map_dict()).is_empty())
	ed._select(ed.props_root.get_child(0))
	ed._toggle_views()
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(10, 60, -60)
	cam.distance = 90.0
	cam._apply()
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/prop.png")
	print("PROPS: ", "PASS" if ok else "FAIL")
	quit()
