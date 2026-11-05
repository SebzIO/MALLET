extends SceneTree
## Text: solid 3D letters you can stand on, a flat sign you pass through, an engraving that cuts into a wall (and
## follows when moved), "place on a surface", a font file from disk, save / load, both exports and a CS:S compile.
## Screenshot: text.png
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/text_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func text(d: Dictionary) -> TextNode:
	var t := TextNode.new()
	ed.texts_root.add_child(t)
	t.from_dict(d)
	return t


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
	# a wall, facing +Z (its front face at z = -98)
	var wall := BlockNode.new()
	ed.blocks_root.add_child(wall)
	wall.from_dict({"position": [0, 40, -100], "size": [40, 16, 4], "material": "Concrete034", "color": "ffffff"})
	# solid 3D letters lying flat, as a platform: an "I" is one solid bar
	var bar := text({"text": "I", "font": "Arial Black", "height": 8.0, "depth": 2.0, "mode": "3d", "position": [60, 40, -100],
		"pitch": -90.0})
	var sign := text({"text": "STAGE 2", "font": "Impact", "height": 3.0, "mode": "flat", "position": [0, 52, -97.9]})
	var eng := text({"text": "O", "font": "Arial Black", "height": 8.0, "depth": 1.0, "mode": "engrave", "position": [0, 44, -98]})
	ed._rebuild_blocks()
	await settle()
	var top := ray(Vector3(60, 60, -100), Vector3(60, 20, -100))
	check("3D letters are solid (stand on the I)", not top.is_empty() and absf(top["position"].y - 42.0) < 0.05,
		"(hit at %.2f)" % (top["position"].y if not top.is_empty() else -1.0))
	var through := ray(Vector3(0, 52.8, -90), Vector3(0, 52.8, -97.95))
	check("a flat sign isn't solid", through.is_empty() or through["collider"].has_meta("block"))
	# engraving: inside the O's ring the wall is cut 1 m deep; in its hole (the middle) it isn't
	var ring_x: float = eng.local_box.position.x + eng.local_box.size.x * 0.12
	var in_stroke := ray(Vector3(ring_x, 44 + 4.0 * 0.5 * 0.0 + eng.local_box.get_center().y, -80), Vector3(ring_x, 44 + eng.local_box.get_center().y, -110))
	var in_hole := ray(Vector3(0, 44 + eng.local_box.get_center().y, -80), Vector3(0, 44 + eng.local_box.get_center().y, -110))
	check("engraving cuts the letter 1 m into the wall", not in_stroke.is_empty() and absf(in_stroke["position"].z - (-99.0)) < 0.1,
		"(stroke hit at z %.2f)" % (in_stroke["position"].z if not in_stroke.is_empty() else 0.0))
	check("...but leaves the O's middle alone", not in_hole.is_empty() and absf(in_hole["position"].z - (-98.0)) < 0.05,
		"(hole hit at z %.2f)" % (in_hole["position"].z if not in_hole.is_empty() else 0.0))
	var pieces_before: int = wall.pieces.size()
	ed._select(eng)
	ed._checkpoint()
	eng.translate_by(Vector3(12, 0, 0))
	ed._mark_blocks()
	await settle()
	var old_spot := ray(Vector3(ring_x, 44 + eng.local_box.get_center().y, -80), Vector3(ring_x, 44 + eng.local_box.get_center().y, -110))
	check("moving the engraving moves the cut", not old_spot.is_empty() and absf(old_spot["position"].z - (-98.0)) < 0.05)
	ed.undo()
	await settle()
	check("wall carved into many convex pieces", pieces_before > 10, "(%d)" % pieces_before)

	# place on a surface: the top of the wall, facing up
	var tag := text({"text": "GO", "font": "Impact", "height": 2.0, "depth": 0.3, "mode": "3d", "position": [0, 100, 0]})
	ed._select(tag)
	await settle()
	var topv: ViewPane = ed.panes[1]
	topv.frame(Vector3(0, 48, -100), 30.0)
	await process_frame
	ed._place_on_surface = true
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = topv.camera.unproject_position(Vector3(5, 56, -100))
	ed.pane_input(topv, ev)
	var up: Vector3 = tag.global_basis.z
	check("place on a surface: on the wall top, letters facing up", absf(tag.global_position.y - 56.0) < 0.05 and up.dot(Vector3.UP) > 0.99,
		"(y %.2f, facing %s)" % [tag.global_position.y, up.snapped(Vector3.ONE * 0.01)])

	# a font file from disk
	var impact := "C:/Windows/Fonts/impact.ttf"
	if FileAccess.file_exists(impact):
		var ff := text({"text": "AB", "font": impact, "height": 3.0, "position": [30, 60, -100]})
		check("a font file from disk works", ff._mesh.mesh.get_surface_count() > 0 and TextShape.convex_polygons(TextShape.spec(ff.data)).size() > 2)

	# save / load
	ed.save_map(out + "/text_test.sfmap")
	var n: int = ed.texts_root.get_child_count()
	ed._new_map()
	ed.load_map(out + "/text_test.sfmap")
	await settle()
	check("texts come back with the map", ed.texts_root.get_child_count() == n)

	# exports
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_text")
	check("SurfsUp export: every text but the engraving", scene.get_node("Texts").get_child_count() == n - 1)
	scene.free()
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := "D:/SurfForge_exports/css/sf_text.vmf"
		var res := VmfExporter.export_vmf(map, vmf)
		var c := VmfExporter.compile(vmf, css, "fast", res.get("materials", []))
		var bad := 0
		for line in String(c["log"]).split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("duplicate") or l.contains("out of range")):
				bad += 1
				if bad <= 4:
					print("      ", line.strip_edges())
		check("CS:S: letters and the engraved wall compile cleanly", res["error"] == "" and c["error"] == "" and bad == 0,
			"(%d brushes) %s %s" % [res["brushes"], res["error"], c["error"]])
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(15, 48, -100)
	cam.distance = 60.0
	cam.yaw = deg_to_rad(15)
	cam.pitch = deg_to_rad(-15)
	cam._apply()
	ed._select(null)
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/text.png")
	print("TEXT: ", "PASS" if ok else "FAIL")
	quit()
