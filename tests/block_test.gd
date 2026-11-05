extends SceneTree
## Structure blocks end to end: a floor, a hollow room with a doorway cut by a cutter, stairs, a pillar; drawing a
## block with the Draw tool and resizing it by a side handle (real mouse events through the views); collision,
## the live cutter, undo, save / load, the SurfsUp export and a real CS:S compile.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/block_test.gd -- <out>

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


func ray_down(at: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 200.0)
	q.collision_mask = 1
	return ed.get_world_3d().direct_space_state.intersect_ray(q)


func ray_along(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	return ed.get_world_3d().direct_space_state.intersect_ray(q)


func mouse(pane: ViewPane, world: Vector3, pressed: bool, motion := false) -> void:
	var p: Vector2 = pane.camera.unproject_position(world)
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = p
	ed.pane_input(pane, ev)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var floor_b := block({"position": [0, 50, -80], "size": [60, 2, 60], "look": "grid"})
	var room := block({"position": [0, 52, -80], "size": [24, 10, 24], "hollow": true, "wall": 1.0, "look": "ceramic", "color": "3a5fa8"})
	var door := block({"position": [0, 51, -68], "size": [4, 6, 6], "cutter": true})
	var stairs := block({"shape": "stairs", "position": [20, 52, -80], "size": [6, 6, 12], "steps": 8, "yaw": 90.0})
	var pillar := block({"shape": "cylinder", "position": [-20, 52, -95], "size": [4, 14, 4], "sides": 20})
	ed._rebuild_blocks()
	for i in 3:
		await physics_frame
	check("room is hollow (6 walls) and the doorway cut its front wall", room.pieces.size() > 6, "(%d pieces)" % room.pieces.size())
	var top := ray_down(Vector3(-25, 70, -60))
	check("players stand on the floor block", not top.is_empty() and absf(top["position"].y - 52.0) < 0.05)
	var through := ray_along(Vector3(0, 54, -60), Vector3(0, 54, -75))
	check("the doorway is open (nothing in the way at head height)", through.is_empty())
	var wall_hit := ray_along(Vector3(8, 54, -60), Vector3(8, 54, -75))
	check("...but the wall beside it is solid", not wall_hit.is_empty())
	# move the cutter: the hole follows
	ed._select(door)
	ed._checkpoint()
	door.translate_by(Vector3(6, 0, 0))
	ed._mark_blocks()
	await process_frame
	for i in 3:
		await physics_frame
	check("moving the cutter moves the hole", not ray_along(Vector3(0, 54, -60), Vector3(0, 54, -75)).is_empty()
		and ray_along(Vector3(6, 54, -60), Vector3(6, 54, -75)).is_empty())
	ed.undo()
	await process_frame
	for i in 3:
		await physics_frame
	check("undo puts the doorway back", ray_along(Vector3(0, 54, -60), Vector3(0, 54, -75)).is_empty())
	var st_top := ray_down(Vector3(14.5, 70, -80))         # turned 90 deg: the steps climb towards -X
	check("stairs climb (the top step is 6 m up)", not st_top.is_empty() and st_top["position"].y > 57.0, "(hit %.2f)" % (st_top["position"].y if not st_top.is_empty() else -1.0))

	# draw a block in the top view, then resize it from its side handle
	var topv: ViewPane = ed.panes[1]
	topv.frame(Vector3(60, 50, -80), 60.0)
	await process_frame
	var n_before: int = ed.blocks_root.get_child_count()
	ed._toggle_draw_mode()
	mouse(topv, Vector3(52, 50, -92), true)
	mouse(topv, Vector3(64, 50, -86), false, true)
	mouse(topv, Vector3(68, 50, -72), false, true)
	mouse(topv, Vector3(68, 50, -72), false)
	ed._toggle_draw_mode()
	var drawn: BlockNode = ed.blocks_root.get_child(ed.blocks_root.get_child_count() - 1)
	var dsz := drawn.size()
	check("Draw block: a 16 x 20 m footprint drawn in the top view", ed.blocks_root.get_child_count() == n_before + 1
		and absf(dsz.x - 16.0) < 0.01 and absf(dsz.z - 20.0) < 0.01, "(%s)" % dsz)
	ed._select(drawn)
	var fh: Array = drawn.face_handles()[1]                 # +X side
	mouse(topv, fh[0], true)
	mouse(topv, fh[0] + Vector3(8, 0, 0), false, true)
	mouse(topv, fh[0] + Vector3(8, 0, 0), false)
	check("dragging its side handle makes it 8 m wider, other side fixed", absf(drawn.size().x - 24.0) < 0.01
		and absf(drawn.global_position.x - 64.0) < 0.01, "(%s at x %.1f)" % [drawn.size(), drawn.global_position.x])

	# save / load
	var path := out + "/block_test.sfmap"
	ed.save_map(path)
	var count: int = ed.blocks_root.get_child_count()
	ed._new_map()
	ed.load_map(path)
	await process_frame
	check("blocks come back with the map", ed.blocks_root.get_child_count() == count)

	# exports
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_blocks")
	var bl: Node = scene.get_node("Blocks")
	check("SurfsUp export: every solid block, none of the cutters", bl.get_child_count() == count - 1)
	scene.free()
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := "D:/SurfForge_exports/css/sf_blocks.vmf"
		var res := VmfExporter.export_vmf(map, vmf)
		check("CS:S: written", res["error"] == "", "(%d brushes) %s" % [res["brushes"], res["error"]])
		var c := VmfExporter.compile(vmf, css, "fast")
		var bad := 0
		for line in String(c["log"]).split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("coplanar") or l.contains("duplicate")):
				bad += 1
		check("CS:S: compiles, no leak, no brush errors", c["error"] == "" and bad == 0, "%s (%d brush problems)" % [c["error"], bad])
	ed._select(ed.blocks_root.get_child(1))
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(10, 55, -80)
	cam.distance = 75.0
	cam.yaw = deg_to_rad(25)
	cam.pitch = deg_to_rad(-28)
	cam._apply()
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/blocks.png")
	print("BLOCKS: ", "PASS" if ok else "FAIL")
	quit()
