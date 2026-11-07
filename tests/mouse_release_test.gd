extends SceneTree
## After orbiting a view with the right / middle mouse button (which hides and holds the mouse), clicks must reach the
## rest of the window again (the Outliner, other views) without alt-tabbing. And a fire can be picked by clicking its
## flames, not just its base.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/mouse_release_test.gd -- <out folder>

var ok := true
var outliner_got := 0


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func button(at: Vector2, idx: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = idx
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if (down and idx == MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func move(at: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = rel
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		Input.flush_buffered_events()


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	for i in 3:
		await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._outliner_panel.visible = true
	ed.outliner.tree.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: outliner_got += 1)
	await process_frame
	await process_frame
	var pane: Control = ed.panes[0]
	var mid := pane.get_global_rect().get_center()
	for b in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		button(mid, b, true)
		await process_frame
		for i in 5:
			move(mid, Vector2(6, 2))
			await process_frame
		button(mid, b, false)
		await process_frame
		await process_frame
		var tr: Rect2 = ed.outliner.tree.get_global_rect()
		var at := tr.position + Vector2(tr.size.x * 0.5, 12)
		var before := outliner_got
		button(at, MOUSE_BUTTON_LEFT, true)
		await process_frame
		button(at, MOUSE_BUTTON_LEFT, false)
		await process_frame
		check("after a %s drag in the 3D view, a click reaches the Outliner" % ("right" if b == MOUSE_BUTTON_RIGHT else "middle"),
			outliner_got > before and tr.has_point(at), "(%d clicks seen, tree at %s)" % [outliner_got - before, tr])

	# a grab whose release went somewhere else: the view lets go by itself
	pane._begin_grab(MOUSE_BUTTON_RIGHT)
	await process_frame
	await process_frame
	check("a view holding the mouse lets go once the button isn't held", not pane.is_grabbing()
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)

	# flying (right mouse held) and pressing E (fly up): must not open build mode with the mouse still held
	for k in [KEY_E, KEY_P]:
		button(mid, MOUSE_BUTTON_RIGHT, true)
		await process_frame
		move(mid, Vector2(4, 0))
		var kd := InputEventKey.new()
		kd.keycode = k
		kd.physical_keycode = k
		kd.pressed = true
		Input.parse_input_event(kd)
		Input.flush_buffered_events()
		for i in 5:
			await process_frame
		var opened: bool = ed.build.active or ed.play.active
		var ku := kd.duplicate()
		ku.pressed = false
		Input.parse_input_event(ku)
		Input.flush_buffered_events()
		button(mid, MOUSE_BUTTON_RIGHT, false)
		await process_frame
		if ed.build.active:
			ed.build.stop()
		if ed.play.active:
			ed.play.stop()
		await process_frame
		await process_frame
		var tr3: Rect2 = ed.outliner.tree.get_global_rect()
		var at3 := tr3.position + Vector2(tr3.size.x * 0.5, 12)
		var before3 := outliner_got
		button(at3, MOUSE_BUTTON_LEFT, true)
		await process_frame
		button(at3, MOUSE_BUTTON_LEFT, false)
		await process_frame
		check("flying with %s held: no mode switch, and the Outliner takes clicks after" % OS.get_keycode_string(k),
			not opened and outliner_got > before3, "(opened a mode: %s, clicks %d)" % [opened, outliner_got - before3])

	# build mode: Tab menu -> Particles, click / drag in the world, E back out, then the Outliner still takes clicks
	for how in ["E key", "Escape key"]:
		ed._build_clicked()
		await process_frame
		await process_frame
		key(KEY_TAB)
		await process_frame
		await process_frame
		var menu: PopupMenu = ed.build._menu
		var idx := menu.get_item_index(110)
		var item_at := Vector2(menu.position) + Vector2(40, 0)
		for i in menu.item_count:
			pass
		# click the Particles item (its row: rows are equal height)
		var row_h := float(menu.size.y) / maxf(menu.item_count, 1)
		item_at = Vector2(menu.position) + Vector2(menu.size.x * 0.5, row_h * (idx + 0.5))
		button(item_at, MOUSE_BUTTON_LEFT, true)
		await process_frame
		button(item_at, MOUSE_BUTTON_LEFT, false)
		await process_frame
		await process_frame
		var c := Vector2(800, 450)
		button(c, MOUSE_BUTTON_LEFT, true)
		for i in 5:
			move(c, Vector2(5, 0))
			await process_frame
		button(c, MOUSE_BUTTON_LEFT, false)
		await process_frame
		key(KEY_E if how == "E key" else KEY_ESCAPE)
		await process_frame
		await process_frame
		var tr2: Rect2 = ed.outliner.tree.get_global_rect()
		var at2 := tr2.position + Vector2(tr2.size.x * 0.5, 12)
		var before2 := outliner_got
		button(at2, MOUSE_BUTTON_LEFT, true)
		await process_frame
		button(at2, MOUSE_BUTTON_LEFT, false)
		await process_frame
		check("build mode (placed particles, left %s): the Outliner takes clicks" % how, not ed.build.active and outliner_got > before2,
			"(menu was at %s, %d particles, mouse mode %d)" % [menu.position, ed.particles_root.get_child_count(), Input.mouse_mode])

	# Outliner right-click menu: opens at the mouse, and has Duplicate and Delete
	ed._load_dict({})
	ed._add_light("point")
	await process_frame
	await process_frame
	ed.outliner.refresh(true)
	await process_frame
	var t: Tree = ed.outliner.tree
	var row: TreeItem = t.get_root().get_first_child()
	var rr := t.get_item_area_rect(row)
	var rat := t.get_global_rect().position + rr.get_center()
	move(rat, Vector2.ZERO)
	await process_frame
	button(rat, MOUSE_BUTTON_RIGHT, true)
	await process_frame
	button(rat, MOUSE_BUTTON_RIGHT, false)
	await process_frame
	await process_frame
	var om: PopupMenu = ed.outliner._menu
	check("Outliner right-click: the menu opens at the mouse", om.visible and Vector2(om.position).distance_to(rat) < 4.0,
		"(menu at %s, mouse %s)" % [om.position, rat])
	check("...with Duplicate and Delete", om.get_item_index(8) >= 0 and om.get_item_index(9) >= 0)
	om.id_pressed.emit(8)
	await process_frame
	check("...Duplicate makes a second light", ed.lights_root.get_child_count() == 2)
	om.hide()
	ed._select(ed.lights_root.get_child(1))
	om.id_pressed.emit(9)
	await process_frame
	await process_frame
	check("...Delete removes it", ed.lights_root.get_child_count() == 1)
	var far: Vector2i = Outliner.menu_position(root, Vector2(100, 100))
	check("menus open inside the window (not shifted by where the window is)", far == Vector2i(100, 100) or not root.gui_embed_subwindows)

	# a fire is picked by its flames, not only by its base
	for c in ed.particles_root.get_children():
		c.free()
	ed._add_particles("fire")
	var fire: ParticleNode = ed.selected
	await process_frame
	var cam: Camera3D = pane.camera
	var flame: Vector3 = fire.global_position + Vector3(0, 1.8, 0)
	ed._select(null)
	var p := cam.unproject_position(flame)
	var picked = ed._pick_object(pane, p)
	check("clicking the flames 1.8 m above a fire picks the fire", picked == fire, "(%s)" % picked)
	var base_hit = ed._pick_object(pane, cam.unproject_position(fire.global_position + Vector3(0, 6.0, 0)))
	check("...but not well above them", base_hit != fire)
	# build mode can pick particles (it didn't know them)
	check("build mode recognizes a particle effect", ed.build._entity_of(fire._body) == fire)
	print("MOUSE RELEASE: ", "PASS" if ok else "FAIL")
	quit()
