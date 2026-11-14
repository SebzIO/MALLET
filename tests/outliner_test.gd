extends SceneTree
## The Outliner: lists every object by name, renames, folders (and folders in folders), selecting a folder selects
## everything in it and dragging it in a view moves the lot, drag-and-drop filing, hiding (and hidden things can't be
## clicked), deleting a folder keeps what's in it, prefabs land in a folder of their own, save / load keeps it all.
## Screenshot: outliner.png
## Run: godot --path . --resolution 1600x900 -s res://tests/outliner_test.gd -- <out>

var ok := true
var ed
var ol: Outliner


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func settle() -> void:
	await process_frame
	for i in 3:
		await physics_frame


func items() -> Array:
	var out := []
	var it := ol.tree.get_root()
	while it:
		if it != ol.tree.get_root():
			out.append(it)
		it = it.get_next_in_tree()
	return out


func item_for(o) -> TreeItem:
	for it in items():
		var m = it.get_metadata(0)
		if m is Dictionary and ((o is String and m.get("folder", "") == o) or (o is Object and m.get("object") == o)):
			return it
	return null


## A left click on a row of the list (Shift / Ctrl like in Windows).
func click_row(it: TreeItem, shift := false, ctrl := false, double := false) -> void:
	var r := ol.tree.get_item_area_rect(it, 0)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.double_click = double and pressed
		ev.shift_pressed = shift
		ev.ctrl_pressed = ctrl
		ev.position = r.position + Vector2(r.size.x * 0.6, r.size.y * 0.5)
		ol.tree.gui_input.emit(ev)


func mouse(pane: ViewPane, world: Vector3, pressed: bool, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = pane.camera.unproject_position(world)
	ed.pane_input(pane, ev)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._load_dict({})
	ed.snap_enabled = false
	ol = ed.outliner
	var r1: RampNode = ed._make_ramp(Vector3(-40, 60, 0), Vector3(40, 40, 0))
	var r2: RampNode = ed._make_ramp(Vector3(-40, 60, 60), Vector3(40, 40, 60))
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [0, 0, -80], "size": [16, 8, 16]})
	var l := LightNode.new()
	ed.lights_root.add_child(l)
	l.from_dict({"position": [0, 20, -80]})
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.begin()
	cm.world.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), 0, 3, Vector3i(3, 1, 3)))
	cm.world.commit()
	cm.position = Vector3(60, 0, -80)
	ed._rebuild_blocks()
	await settle()
	ol.refresh(true)
	var names := items().map(func(it): return it.get_text(0))
	check("every object is listed by name", names.has("Ramp 1") and names.has("Ramp 2") and names.size() == 5, "(%s)" % [names])

	# rename
	ol.rename(item_for(r1).get_metadata(0), "Stage 1 drop")
	await process_frame
	check("rename: double-click, type a name", ol.name_of(r1) == "Stage 1 drop" and r1.get_meta("name") == "Stage 1 drop")

	# a folder with both ramps, inside a folder for the stage
	ed._set_selection([r1, r2])
	var fid := ol.new_folder_from_selection()
	var outer := ol.new_folder("Stage 1")
	ol.folder(fid)["parent"] = outer
	ol.folder(fid)["name"] = "Ramps"
	ol.refresh(true)
	check("+ Folder: the selection goes into a new folder", r1.get_meta("folder", "") == fid and r2.get_meta("folder", "") == fid)
	check("folders inside folders", item_for(fid) != null and item_for(fid).get_parent() == item_for(outer)
		and item_for(r1).get_parent() == item_for(fid))

	# clicking the outer folder selects everything in it
	ed._set_selection([])
	ol.tree.deselect_all()
	item_for(outer).select(0)
	ol._tree_selection_changed()
	var sel: Array = ed.selection()
	check("click a folder: everything in it (and its folders) is selected", sel.size() == 2 and r1 in sel and r2 in sel, "(%d)" % sel.size())

	# drag the folder in the top view: both ramps move together
	await settle()
	var topv: ViewPane = ed.panes[1]
	topv.frame(Vector3(0, 0, 30), 140.0)
	await settle()
	var p0 := r1.points[0]
	var p2 := r2.points[0]
	var grab := r1.points[0].lerp(r1.points[1], 0.5)       # on the ramp, between two handles
	ed._set_selection([r1, r2])
	mouse(topv, grab, true)
	mouse(topv, grab + Vector3(20, 0, 0), false, true)
	mouse(topv, grab + Vector3(20, 0, 0), false)
	check("drag in a view: the whole folder moves together", absf(r1.points[0].x - p0.x - 20.0) < 0.5 and absf(r2.points[0].x - p2.x - 20.0) < 0.5,
		"(%.1f, %.1f)" % [r1.points[0].x - p0.x, r2.points[0].x - p2.x])

	# drag and drop: the light onto the Stage 1 folder
	ol.tree.deselect_all()
	item_for(l).select(0)
	var data = ol._get_drag(Vector2.ZERO)
	var fit := item_for(outer)
	var at := ol.tree.get_item_area_rect(fit).get_center()
	ol._drop(at, data)
	check("drag and drop: the light into the Stage 1 folder", l.get_meta("folder", "") == outer)

	# hide the block: it's hidden and can't be clicked
	ol.set_hidden([b], true)
	await settle()
	var persp: ViewPane = ed.panes[0]
	var pcam := persp.camera as OrbitCamera
	pcam.focus = b.center()
	pcam.distance = 60
	pcam._apply()
	await settle()
	var picked = ed._pick_object(persp, persp.camera.unproject_position(b.center() + Vector3(0, 4, 0)))
	check("the eye hides it, and a click goes straight through", not b.visible and picked != b)

	# save / load
	ed.save_map(out + "/outliner_test.mallet")
	ed._load_dict({})
	ed.load_map(out + "/outliner_test.mallet")
	await settle()
	ol.refresh(true)
	var r1b: RampNode = null
	for r in ed.ramps_root.get_children():
		if r.get_meta("name", "") == "Stage 1 drop":
			r1b = r
	var bb: BlockNode = ed.blocks_root.get_child(0)
	check("save / load: names, folders and hidden things come back", r1b != null and ol.folder(r1b.get_meta("folder", "")).get("name") == "Ramps"
		and ol.folder(ol.folder(r1b.get_meta("folder", "")).get("parent", "")).get("name") == "Stage 1" and not bb.visible)

	# delete the inner folder: its ramps move up into Stage 1
	var inner: String = r1b.get_meta("folder")
	var outer2: String = ol.folder(inner)["parent"]
	ol.delete_folder(inner)
	check("deleting a folder keeps what's in it (moved up a level)", r1b.get_meta("folder", "") == outer2 and ol.folder(inner).is_empty())

	# prefabs land in their own folder
	var pf := ""
	for p in Prefabs.list():
		if p["name"] == "Lamp post":
			pf = p["path"]
	var placed: Array = ed.place_prefab(pf)
	var pfolder := String(placed[0].get_meta("folder", "")) if not placed.is_empty() else ""
	check("a prefab lands in a folder named after it", pfolder != "" and ol.folder(pfolder).get("name") == "Lamp post"
		and placed.all(func(o): return o.get_meta("folder", "") == pfolder))

	# Windows-style clicks: five ramps in a row (with other things below them), click the first, Shift+click the fifth
	ed._load_dict({})
	var ramps := []
	for i in 5:
		ramps.append(ed._make_ramp(Vector3(-40, 60, i * 30), Vector3(40, 40, i * 30)))
	var lb := LightNode.new()
	ed.lights_root.add_child(lb)
	var bb2 := BlockNode.new()
	ed.blocks_root.add_child(bb2)
	ed._rebuild_blocks()
	await settle()
	ol.refresh(true)
	click_row(item_for(ramps[0]))
	click_row(item_for(ramps[4]), true)
	var got: Array = ed.selection()
	check("click Ramp 1, Shift+click Ramp 5: exactly Ramps 1-5", got.size() == 5 and ramps.all(func(r): return r in got),
		"(%d selected)" % got.size())
	click_row(item_for(ramps[2]), false, true)
	got = ed.selection()
	check("Ctrl+click takes one out again", got.size() == 4 and not ramps[2] in got)
	click_row(item_for(lb))
	check("a plain click selects just that one", ed.selection() == [lb])

	# double-click a row in the middle: that row (not the last one) gets the name box
	await process_frame
	var mid_row := item_for(ramps[2])
	click_row(mid_row)
	click_row(mid_row, false, false, true)
	var open_now := ol.is_renaming()
	var edited_row := ol.tree.get_selected()
	ol.sync_selection()
	ol.refresh()
	check("double-click opens the name box on the row you clicked", open_now and edited_row == mid_row,
		"(on %s)" % (edited_row.get_text(0) if edited_row else "nothing"))
	check("...and the list leaves it open while you type", ol.is_renaming() == open_now and ol.tree.get_selected() == mid_row)
	# (a background test window has no focus, so the box closes itself a frame later - in the real window it stays)

	# dropping into a folder works every time (Godot resets the tree's drop mode after each drop)
	var df := ol.new_folder("Drop here")
	for r in [ramps[0], ramps[1]]:
		ol.refresh(true)
		click_row(item_for(r))
		var dd = ol._get_drag(Vector2.ZERO)
		ol.tree.drop_mode_flags = Tree.DROP_MODE_DISABLED         # as Godot leaves it after a drop
		var fpos := ol.tree.get_item_area_rect(item_for(df)).get_center()
		check("dragging over a folder says it can drop (and shows where)", ol._can_drop(fpos, dd)
			and ol.tree.drop_mode_flags == (Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN))
		ol._drop(fpos, dd)
		check("...and the drop goes into the folder, first time", r.get_meta("folder", "") == df)

	# the panel
	ol.refresh(true)
	ed._set_selection([ramps[0], ramps[1]])
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/outliner.png")
	print("OUTLINER: ", "PASS" if ok else "FAIL")
	quit()
