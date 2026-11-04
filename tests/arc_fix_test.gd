extends SceneTree
## Regression test for: outline drift (interpolation), arc lag while dragging, arcs ignoring the finish zone.
func _init():
	call_deferred("_run")
func _run():
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	for i in 3: await physics_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	var fin: EntityNode = ed._find_entity("finish")

	# 1. drawn position == true position right after a move (no interpolation lag)
	fin.position += Vector3(37, 0, 11)
	await process_frame
	print("1. drawn vs true position gap: %.3f m" % fin.get_global_transform_interpolated().origin.distance_to(fin.global_position))

	# 2. drag the ramp's end handle through the real mouse path, arcs must follow on the next frame
	ed._select(r)
	var top: ViewPane = ed.panes[1]
	var end_s := top.camera.unproject_position(r.points[2])
	var e := InputEventMouseButton.new(); e.button_index = MOUSE_BUTTON_LEFT; e.pressed = true; e.position = end_s
	top._gui_input(e)
	var m := InputEventMouseMotion.new(); m.position = end_s + Vector2(0, 60)
	top._gui_input(m)
	await process_frame
	var arc_start: Vector3 = ed._arcs[0]["runs"][0]["points"][0]
	print("2. one frame after the drag: arc starts %.1f m from the moved ramp end" % arc_start.distance_to(JumpCheck.exit_of(r.ridge)[0]))
	e.pressed = false
	top._gui_input(e)

	# 3. finish placed so the arc crosses its zone but not the slab -> counts as reaching the finish
	ed._undo.clear()
	r.points = PackedVector3Array([Vector3(-60, 120, 0), Vector3(0, 105, 0), Vector3(60, 90, 0)])
	r.rebuild()
	fin.position = Vector3(500, 0, 0)
	for i in 3: await physics_frame
	ed._update_arcs()
	var pts: PackedVector3Array = ed._arcs[0]["runs"][0]["points"]
	var p := pts[int(pts.size() * 0.5)]
	fin.position = p - Vector3(0, 6, 0)            # arc passes 6 m above the slab: inside the 10 m zone
	for i in 3: await physics_frame
	ed._update_arcs()
	print("3. arc through the finish zone: ", ed._arcs[0]["runs"][0]["label"])
	quit()
