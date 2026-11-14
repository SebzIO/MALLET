extends SceneTree
## Locking (0.24.0): the Outliner's padlock locks an object (or a folder and everything in it). A locked object can't
## be picked in the views, box-selected or Select all'd; selected from the Outliner it can't be dragged, nudged,
## turned, deleted, extended or edited in the panel (a cover says so, with Unlock); build mode leaves a locked cube
## object alone. Locks save with the map and undo; a copy of a locked object isn't locked.
## Run: godot --path . --resolution 1280x720 -s res://tests/lock_objects_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame


func item_of(o) -> TreeItem:
	var it: TreeItem = ed.outliner.tree.get_root()
	while it:
		var m = it.get_metadata(0)
		if m is Dictionary and ((m.has("object") and is_same(m["object"], o)) or (o is String and m.get("folder", "") == o)):
			return it
		it = it.get_next_in_tree()
	return null


## A real left click on a row's button (column 1 the eye, 2 the padlock), through the window like a mouse.
func left_click(tree: Tree, item: TreeItem, col: int) -> void:
	var r := tree.get_item_area_rect(item, col)
	var at := tree.get_global_transform_with_canvas() * (r.position + r.size * 0.5)
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		m.position = at
		m.global_position = at
		Input.warp_mouse(at)
		Input.parse_input_event(m)
		Input.flush_buffered_events()
		await process_frame


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await frames(2)
	ed.welcome.hide()
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 40, -60]]}],
		"blocks": [{"shape": "box", "position": [40.0, 0.0, 0.0], "size": [4.0, 4.0, 4.0]}],
		"lights": [{"kind": "point", "position": [60.0, 10.0, 0.0], "folder": "f1"}],
		"folders": [{"id": "f1", "name": "Lamps", "parent": "", "open": true}]})
	await frames(3)
	var ramp: RampNode = ed.ramps_root.get_child(0)
	var block: BlockNode = ed.blocks_root.get_child(0)
	var lamp: LightNode = ed.lights_root.get_child(0)
	ed.outliner.refresh(true)
	# the padlock in the Outliner
	var it := item_of(ramp)
	check("the Outliner has a padlock column", it != null and it.get_button_count(2) == 1)
	await frames(2)
	await left_click(ed.outliner.tree, it, 2)
	check("a real left click on the padlock locks the ramp", ed.is_locked(ramp) and ramp.get_meta("locked", false))
	ed.outliner.refresh(true)
	await frames(1)
	await left_click(ed.outliner.tree, item_of(ramp), 2)
	check("...and another unlocks it", not ed.is_locked(ramp))
	ed.outliner.refresh(true)
	await frames(1)
	await left_click(ed.outliner.tree, item_of(ramp), 1)
	check("(the eye still works with a left click)", not ramp.visible)
	ed.outliner.set_hidden([ramp], false)
	ed.outliner.refresh(true)
	await frames(1)
	await left_click(ed.outliner.tree, item_of(ramp), 2)
	check("locked again by a left click", ed.is_locked(ramp))
	# picking
	var top: ViewPane = null
	for p in ed.panes:
		if p.is_ortho() and absf(p.camera.global_basis.z.y) > 0.9:
			top = p
	top.frame(Vector3(0, 45, -30), 60.0)
	await frames(3)
	var at: Vector2 = top.camera.unproject_position(Vector3(0, 45, -30))
	check("a locked ramp can't be picked in the views (clicks go through)", ed._pick_object(top, at) != ramp)
	ed._set_selection(ed._all_objects().filter(func(o): return not ed.is_locked(o)))
	check("Select all leaves it out", not ramp in ed.selection())
	# selected from the Outliner: nothing changes it
	ed._set_selection([ramp])
	await frames(1)
	var before: Dictionary = ramp.to_dict()
	ed._nudge(KEY_LEFT)
	ed._rotate_selected(15.0)
	ed._extend_clicked()
	ed._edit_prop("angle", 70.0)
	ed._delete_clicked()
	await frames(1)
	check("nudge, turn, extend, a panel edit and Delete all leave it alone", is_instance_valid(ramp) and not ramp.is_queued_for_deletion()
		and JSON.stringify(ramp.to_dict()) == JSON.stringify(before))
	check("...the side panel is covered, with Unlock", ed._lock_cover.visible)
	ed._begin_drag(top, ed.Drag.OBJECT, at, false)
	check("...and a drag doesn't start", ed._drag == ed.Drag.NONE)
	# copies aren't locked
	ed._duplicate_clicked()
	await frames(1)
	var copy = ed.ramps_root.get_child(ed.ramps_root.get_child_count() - 1)
	check("a copy of a locked ramp isn't locked", copy != ramp and not ed.is_locked(copy))
	# saving
	var d: Dictionary = ed._map_dict()
	ed._load_dict(JSON.parse_string(JSON.stringify(d)))
	await frames(2)
	ramp = ed.ramps_root.get_child(0)
	check("the lock saves with the map", ed.is_locked(ramp))
	# unlock from the cover, and undo
	ed._set_selection([ramp])
	ed.unlock_selection()
	check("the cover's Unlock unlocks it", not ed.is_locked(ramp) and not ed._lock_cover.visible)
	ed.undo()
	await frames(1)
	ramp = ed.ramps_root.get_child(0)
	check("undo locks it again", ed.is_locked(ramp))
	# a locked folder
	lamp = ed.lights_root.get_child(0)
	ed.outliner.set_folder_locked("f1", true)
	check("a locked folder locks what's in it", ed.is_locked(lamp))
	ed.outliner.refresh(true)
	var lit := item_of(lamp)
	ed.outliner._button_clicked(lit, 2, 1, MOUSE_BUTTON_LEFT)
	check("...and its padlock can't be undone from inside", ed.is_locked(lamp))
	ed._set_selection([lamp])
	ed.unlock_selection()
	check("Unlock on something locked by its folder unlocks the folder", not ed.is_locked(lamp) and not ed.outliner.folder_locked("f1"))
	# build mode
	block = ed.blocks_root.get_child(0)
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.begin()
	cm.world.set_cell(Vector3i.ZERO, 0, CubeWorld.FULL, CubeWorld.blank_tex(""))
	cm.world.commit()
	ed.outliner.set_locked([cm], true)
	ed._build_clicked()
	await frames(2)
	var bm: BuildMode = ed.build
	var s := CubeWorld.make_sel(Vector3i.ZERO, 0, 3)
	s["model"] = cm
	var n0 := cm.world.count()
	var out = bm._edit(s, func(w: CubeWorld): return w.pull(s, ""))
	check("build mode leaves a locked cube object alone", out == null and cm.world.count() == n0)
	bm.stop()
	print("lock_objects_test: ", "PASS" if ok else "FAIL")
	quit()
