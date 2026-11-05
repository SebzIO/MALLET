extends SceneTree
## Multi-select, groups, copy / paste, through real clicks in the views: Ctrl+click adds, a box drawn on empty space
## in a 2D view selects what's inside, dragging moves the whole selection, [ ] turns it around its middle, Ctrl+G
## groups (a click then selects the group), Ctrl+C / Ctrl+V go through the system clipboard (skipping a second
## start platform), Delete removes them all, undo brings them back. Screenshots: multi.png, menu_add.png
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/multi_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func click(pane: ViewPane, world: Vector3, ctrl := false, drag_to = null) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.position = pane.camera.unproject_position(world)
	ed.pane_input(pane, ev)
	if drag_to != null:
		var mv := InputEventMouseMotion.new()
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		mv.position = pane.camera.unproject_position(drag_to)
		ed.pane_input(pane, mv)
		ev = ev.duplicate()
		ev.position = mv.position
	var up: InputEventMouseButton = ev.duplicate()
	up.pressed = false
	ed.pane_input(pane, up)


func block(at: Vector3) -> BlockNode:
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [at.x, at.y, at.z], "size": [8, 8, 8]})
	return b


func key(code: Key, ctrl := false, shift := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	ed._handle_key(ev)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var a := block(Vector3(0, 0, -200))
	var b := block(Vector3(30, 0, -200))
	var c := block(Vector3(60, 0, -200))
	ed._rebuild_blocks()
	var top: ViewPane = ed.panes[1]
	top.frame(Vector3(30, 0, -200), 60.0)
	await process_frame
	for i in 2:
		await physics_frame

	click(top, a.center())
	click(top, b.center(), true)
	check("click + Ctrl+click: two selected", ed.selection().size() == 2 and a in ed.selection() and b in ed.selection())
	click(top, b.center(), true)
	check("Ctrl+click again takes one out", ed.selection() == [a])
	# box select all three
	click(top, Vector3(-10, 0, -215), false, Vector3(70, 0, -185))
	check("box drawn in the top view selects all three", ed.selection().size() == 3)
	# drag them together by one of them
	var before := [a.global_position, b.global_position, c.global_position]
	click(top, b.center(), false, b.center() + Vector3(0, 0, 20))
	var moved: Vector3 = a.global_position - before[0]
	check("dragging one moves the whole selection", moved.distance_to(Vector3(0, 0, 20)) < 0.01
		and (c.global_position - before[2]).distance_to(Vector3(0, 0, 20)) < 0.01, str(moved))
	# turn around the middle
	key(KEY_BRACKETRIGHT)
	key(KEY_BRACKETRIGHT)
	key(KEY_BRACKETRIGHT)
	key(KEY_BRACKETRIGHT)
	key(KEY_BRACKETRIGHT)
	key(KEY_BRACKETRIGHT)
	var mid: Vector3 = (a.center() + c.center()) * 0.5
	check("[ ] turns them around their middle (90 deg: the row now runs along z)", absf(a.global_position.x - c.global_position.x) < 0.1
		and absf(b.center().distance_to(mid)) < 0.1)
	# group, then a plain click selects the whole group
	key(KEY_G, true)
	await process_frame                                 # blocks rebuild their collision on the next frame
	for i in 2:
		await physics_frame
	click(top, Vector3(500, 0, 500))                    # empty: deselect
	ed._select(null)
	click(top, a.center())
	check("Ctrl+G groups: clicking one selects all three", ed.selection().size() == 3)
	# copy / paste through the clipboard
	ed._new_map()                                       # the starter has a start and a finish
	var start: EntityNode = ed._find_entity("start")
	ed._set_selection([start, ed.ramps_root.get_child(0)])
	key(KEY_C, true)
	var n_ramps: int = ed.ramps_root.get_child_count()
	key(KEY_V, true)
	check("Ctrl+V pastes the ramp but not a second start platform", ed.ramps_root.get_child_count() == n_ramps + 1
		and ed.entities_root.get_children().filter(func(e): return e.kind == "start").size() == 1)
	ed._select(ed.ramps_root.get_child(0))
	key(KEY_D, true)
	check("Ctrl+D duplicates", ed.ramps_root.get_child_count() == n_ramps + 2)
	# delete several, then undo
	ed._set_selection(ed.ramps_root.get_children())
	var count: int = ed.ramps_root.get_child_count()
	ed._delete_clicked()
	check("Delete removes the whole selection", ed.ramps_root.get_child_count() == 0)
	ed.undo()
	check("undo brings them all back", ed.ramps_root.get_child_count() == count)
	# group survives save / load
	ed._new_map()
	var g1 := block(Vector3(0, 0, -100))
	var g2 := block(Vector3(20, 0, -100))
	ed._rebuild_blocks()
	ed._set_selection([g1, g2])
	key(KEY_G, true)
	ed.save_map(out + "/multi.sfmap")
	ed._new_map()
	ed.load_map(out + "/multi.sfmap")
	await process_frame
	ed._select_with_group(ed.blocks_root.get_child(0))
	check("a group is still a group after save / load", ed.selection().size() == 2)
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/multi.png")
	var mb: MenuButton = ed._fields["menu_Add"]
	mb.show_popup()
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/menu_add.png")
	print("MULTI: ", "PASS" if ok else "FAIL")
	quit()
