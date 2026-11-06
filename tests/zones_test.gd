extends SceneTree
## Custom zones (the user's #13): start / finish / stage zones without the built-in plate, on a platform the mapper
## built, and zones of any shape made of several boxes. Editor, save, play mode timing, SurfsUp and CS:S export.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/zones_test.gd -- <out folder>

const U := 39.37
var ed
var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func block(pos: Vector3, size: Vector3) -> BlockNode:
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [pos.x, pos.y, pos.z], "size": [size.x, size.y, size.z]})
	return b


func zone(kind: String, floor_pos: Vector3, size := Vector3(16, 10, 16)) -> EntityNode:
	ed._add_entity(kind, true)
	var e: EntityNode = ed.selected
	e.position = floor_pos
	e.size = size
	e.rebuild()
	return e


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed.snap_enabled = false
	# an L-shaped start platform made of two blocks (their tops at y 100), and a finish block far below
	block(Vector3(0, 98, 0), Vector3(16, 4, 16))
	block(Vector3(16, 98, 0), Vector3(16, 4, 16))
	block(Vector3(0, 18, 300), Vector3(30, 4, 30))
	var s1 := zone("start", Vector3(0, 100, 0))
	var s2 := zone("start", Vector3(16, 100, 0))
	var f := zone("finish", Vector3(0, 20, 300), Vector3(30, 8, 30))
	check("two start zones can be added (a zone of any shape)", ed.entities_root.get_children().filter(func(e): return e.kind == "start").size() == 2)
	check("a zone box is labelled as a zone", s1.label() == "Start zone" and f.label() == "Finish zone", "(%s, %s)" % [s1.label(), f.label()])
	check("its zone is the box itself (16 x 10 x 16 from its floor)", s1.zone_aabb().is_equal_approx(AABB(Vector3(-8, 100, -8), Vector3(16, 10, 16))), "(%s)" % s1.zone_aabb())
	check("it has no platform the player could stand on", s1._body.collision_layer == EntityNode.PICK_ONLY_LAYER and not s1._mesh.visible)
	ed._add_entity("start")
	check("B still adds the start plate as well (one plate + zones)", ed._find_plate("start") != null and ed._find_entity("start") == ed._find_plate("start"))
	ed._delete_clicked()
	check("without a plate, the first start zone is where you spawn", ed._find_entity("start") == s1)

	# save / load
	ed.save_map(out + "/zones.sfmap")
	ed.load_map(out + "/zones.sfmap")
	var zs: Array = ed.entities_root.get_children().filter(func(e): return e.is_zone_box())
	check("zone boxes survive saving and opening", zs.size() == 3)
	var map: Dictionary = ed._map_dict()
	check("the map passes the export check (zones count as start / finish)", SurfsUpExporter.check(map).is_empty(), "%s" % SurfsUpExporter.check(map))

	# SurfsUp: two start areas, one finish area, no platform bodies
	var scene: Node3D = SurfsUpExporter.build_scene(map, "sf_zones_test")
	var starts := []
	var finishes := 0
	var plates := 0
	for n in scene.find_children("*", "", true, false):
		if n is Area3D and n.get_meta("sdk_zone", "") == "start":
			starts.append(n.name)
		if n is Area3D and n.get_meta("sdk_zone", "") == "finish":
			finishes += 1
		if n is StaticBody3D and String(n.name).ends_with("Platform"):
			plates += 1
	check("SurfsUp: both start boxes are start zones", starts.size() == 2 and starts[0] != starts[1], "(%s)" % [starts])
	check("SurfsUp: one finish zone, and no built-in platforms", finishes == 1 and plates == 0, "(%d finish, %d platforms)" % [finishes, plates])
	var sp: Marker3D = scene.get_node("SpawnPoint")
	check("SurfsUp: the spawn is on the first zone's floor", sp.position.distance_to(Vector3(0, 100.1, 4)) < 0.2, "(%s)" % sp.position)
	scene.free()

	# CS:S: two map_start triggers, one spawn destination
	var res := VmfExporter.export_vmf(map, out + "/sf_zones_test.vmf")
	var vmf := FileAccess.get_file_as_string(out + "/sf_zones_test.vmf")
	check("CS:S: exports", res["error"] == "", res["error"])
	check("CS:S: both start boxes are map_start triggers", vmf.count("\"targetname\" \"map_start\"") == 2)
	check("CS:S: one spawn for the start zone", vmf.count("\"targetname\" \"spawn_map_start\"") == 1)

	# play: leave the L through the second box -> timer runs only once outside both; finish box stops it
	ed._play_clicked()
	await physics_frame
	var p: SUCC = ed.play.player
	p.teleport(Transform3D(Basis(), Vector3(16, 100.5, 0)))       # in the second start box
	for i in 10: await physics_frame
	check("play: standing in the second start box, the run hasn't started", ed.play.run_state == 0, "(state %d)" % ed.play.run_state)
	p.teleport(Transform3D(Basis(), Vector3(40, 100.5, 0)))       # off the end of the L
	for i in 10: await physics_frame
	check("play: leaving both boxes starts the run", ed.play.run_state == 1, "(state %d)" % ed.play.run_state)
	p.teleport(Transform3D(Basis(), Vector3(0, 21, 300)))
	for i in 5: await physics_frame
	check("play: the finish zone box finishes it", ed.play.run_state == 2, "(state %d)" % ed.play.run_state)
	ed.play.stop()
	print("ZONES: ", "PASS" if ok else "FAIL")
	quit()
