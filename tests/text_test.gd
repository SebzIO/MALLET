extends SceneTree
## Text: solid 3D letters you can stand on, a flat sign you pass through, old engraved text loading as 3D letters,
## "place on a surface", a font file from disk, save / load, both exports and a CS:S compile.
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
	var old := text({"text": "O", "font": "Arial Black", "height": 8.0, "depth": 1.0, "mode": "engrave", "position": [0, 44, -98]})
	ed._rebuild_blocks()
	await settle()
	var top := ray(Vector3(60, 60, -100), Vector3(60, 20, -100))
	check("3D letters are solid (stand on the I)", not top.is_empty() and absf(top["position"].y - 42.0) < 0.05,
		"(hit at %.2f)" % (top["position"].y if not top.is_empty() else -1.0))
	var through := ray(Vector3(0, 52.8, -90), Vector3(0, 52.8, -97.95))
	check("a flat sign isn't solid", through.is_empty() or through["collider"].has_meta("block"))
	check("old engraved text loads as 3D letters, the wall stays whole", old.data["mode"] == "3d" and wall.pieces.size() == 1)

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

	# multi-line: a second line makes the text taller, and each line is aligned
	var one := text({"text": "AB", "height": 2.0, "position": [0, 100, 0]})
	var two := text({"text": "AB
CD", "height": 2.0, "position": [0, 120, 0]})
	await settle()
	check("multi-line text: two lines are about twice as tall", two.local_box.size.y > one.local_box.size.y * 1.7,
		"(%.2f vs %.2f m)" % [two.local_box.size.y, one.local_box.size.y])
	# centring on a face: the wall's front face is 40 x 16, centre (0, 48, -98)
	var sn := text({"text": "MID", "height": 2.0, "depth": 0.3, "position": [0, 0, 0]})
	await settle()
	var put := func(x: float, y: float) -> void:
		var bc: Vector3 = sn.local_box.get_center()
		sn.from_dict(sn.data.merged({"position": [x - bc.x, y - bc.y, -97.995]}, true))
	put.call(0.4, 48.3)
	await settle()
	var r1: String = ed._centre_text_on_face(sn)
	var c1: Vector3 = sn.center()
	check("near the middle of a face: snaps to its centre", r1 == "centre" and absf(c1.x) < 0.01 and absf(c1.y - 48.0) < 0.01,
		"(%s, %.2f, %.2f)" % [r1, c1.x, c1.y])
	put.call(6.0, 48.4)
	await settle()
	var r2: String = ed._centre_text_on_face(sn)
	var c2: Vector3 = sn.center()
	check("off to one side: only the middle line snaps", r2.begins_with("middle") and absf(c2.x - 6.0) < 0.01 and absf(c2.y - 48.0) < 0.01,
		"(%s, %.2f, %.2f)" % [r2, c2.x, c2.y])
	put.call(10.0, 55.0)
	await settle()
	check("far from both centre lines: left alone", ed._centre_text_on_face(sn) == "")
	for t in [one, two, sn]:
		t.queue_free()
	await settle()

	# a font file from disk
	var impact := "C:/Windows/Fonts/impact.ttf"
	if FileAccess.file_exists(impact):
		var ff := text({"text": "AB", "font": impact, "height": 3.0, "position": [30, 60, -100]})
		check("a font file from disk works", ff._mesh.mesh.get_surface_count() > 0 and TextShape.convex_polygons(TextShape.spec(ff.data)).size() > 2)

	# save / load
	ed.save_map(out + "/text_test.mallet")
	var n: int = ed.texts_root.get_child_count()
	ed._new_map()
	ed.load_map(out + "/text_test.mallet")
	await settle()
	check("texts come back with the map", ed.texts_root.get_child_count() == n)

	# exports
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_text")
	check("SurfsUp export: every text", scene.get_node("Texts").get_child_count() == n)
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
		check("CS:S: letters and the wall compile cleanly", res["error"] == "" and c["error"] == "" and bad == 0,
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
