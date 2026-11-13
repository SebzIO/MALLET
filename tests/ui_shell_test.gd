extends SceneTree
## Batch A: one theme for the menus, panels and buttons; the playtest panel's own toolbar button; the minimize that
## remembers itself; and no playtest-panel entry left in the Export menu.

var ed
var fails := 0


func _init() -> void:
	call_deferred("_run")


func check(what: String, ok: bool, extra := "") -> void:
	if ok:
		print("OK    ", what)
	else:
		fails += 1
		print("FAIL  ", what, ("  (" + extra + ")") if extra != "" else "")


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame

	# ---- one theme, on the window, so every control and popup gets it
	var win: Window = ed.get_window()
	check("a theme covers the window", win.theme != null)
	check("and the UI's Control root, so popups and dialogs get it", ed._ui_root.theme != null)
	var b := Button.new()
	ed._ui_root.add_child(b)
	await process_frame
	var normal := b.get_theme_stylebox("normal")
	var hover := b.get_theme_stylebox("hover")
	var pressed := b.get_theme_stylebox("pressed")
	check("buttons have a 1 px outline", normal is StyleBoxFlat and (normal as StyleBoxFlat).border_width_top == 1
		and (normal as StyleBoxFlat).border_color != (normal as StyleBoxFlat).bg_color, str(normal) + "  b.theme=" + str(b.theme != null))
	check("hovering a button changes its fill and outline", hover is StyleBoxFlat
		and (hover as StyleBoxFlat).bg_color != (normal as StyleBoxFlat).bg_color
		and (hover as StyleBoxFlat).border_color != (normal as StyleBoxFlat).border_color)
	check("pressing one shows it", pressed is StyleBoxFlat and (pressed as StyleBoxFlat).bg_color != (normal as StyleBoxFlat).bg_color)
	var pm: PopupMenu = (ed._fields["menu_View"] as MenuButton).get_popup()
	var pp := pm.get_theme_stylebox("panel")
	check("menus are a bordered panel", pp is StyleBoxFlat and (pp as StyleBoxFlat).border_width_top == 1, str(pp) + "  pm.theme=" + str(pm.theme != null))
	check("menu rows are roomier than the default", pm.get_theme_constant("v_separation") >= 4)
	b.queue_free()

	# ---- the menus (0.27.0): File | Add, Edit, View | Undo, Redo | Build, Play | Playtest | Options, Help
	var items := func(key: String) -> Array:
		var out := []
		var m = ed._fields[key]
		var p: PopupMenu = m.get_popup() if m is MenuButton else m
		for i in p.item_count:
			out.append(p.get_item_text(i))
		return out
	var file_items: Array = items.call("menu_File")
	check("File has New, Open, Save and Export", "New" in file_items and "Open…" in file_items and "Save" in file_items and "Export" in file_items, str(file_items))
	var export_items: Array = items.call("menu_Export")
	check("...Export opens beside it with To SurfsUp and To CS:S", export_items == ["To SurfsUp…", "To Counter-Strike: Source…"], str(export_items))
	var pt_items: Array = items.call("menu_Playtest")
	check("Playtest has the session, test builds and tester runs", "Playtest session…" in pt_items and "Test build for testers…" in pt_items
		and "Import tester runs…" in pt_items, str(pt_items))
	var opt_items: Array = items.call("menu_Options")
	var view_items: Array = items.call("menu_View")
	check("Options has fullscreen, mouse sensitivity and the shaders folder (not View)", "Fullscreen" in opt_items
		and "Mouse sensitivity…" in opt_items and "Your shaders folder…" in opt_items and not "Fullscreen" in view_items, str(opt_items))
	check("the playtest panel is in View, its toolbar button gone", "Playtest panel" in view_items and not ed._fields.has("playtest_button"))
	var order := []
	for c in (ed._fields["menu_File"] as Control).get_parent().get_children():
		if c is Button and (c as Button).text != "":
			order.append((c as Button).text.get_slice(" ", 0))
	var want := ["File", "Add", "Edit", "View", "Undo", "Redo", "Build", "▶", "Playtest", "Options", "Help"]
	check("the toolbar's order", order.slice(0, want.size()) == want, str(order))
	# ---- the side panel's titled sections (0.27.1)
	var titles := func(box: Node) -> Array:
		return box.find_children("*", "VBoxContainer", true, false).filter(func(c): return c.has_meta("section")).map(func(c): return c.get_meta("section"))
	var want_sections := {"_ramp_props": ["Shape", "Path and turning", "Look"], "_light_props": ["Kind and effect", "Brightness and reach"],
		"_block_props": ["Shape and size", "Material", "Look", "Liquid"], "_map_props": ["Sky", "Sun and light", "Fog and reflections"],
		"_particle_props": ["Effect", "Area"], "_text_props": ["Text", "Size and facing", "Look"], "_entity_props": ["Size and facing"],
		"_cube_panel": ["Cube object"], "_prop_props": ["Model"]}
	var missing_sections := []
	for k in want_sections:
		var got: Array = titles.call(ed.get(k))
		for t in want_sections[k]:
			if not t in got:
				missing_sections.append("%s: %s" % [k, t])
	check("every side panel is split into titled sections", missing_sections.is_empty(), str(missing_sections))
	ed._set_playtest_panel(true)
	await process_frame
	check("View > Playtest panel shows it", ed._playtest_panel.visible)
	ed._playtest_panel.close_requested.emit()
	await process_frame
	check("its close button hides it", not ed._playtest_panel.visible)
	ed._set_playtest_panel(true)
	await process_frame

	# ---- minimize / expand, remembered
	var panel = ed._playtest_panel
	panel.set_minimized(true)
	await process_frame
	await process_frame
	check("− collapses it to its title", panel.minimized and not panel._body.visible, str(panel.size))
	check("collapsed, it is one row tall", panel.size.y < 72, str(panel.size.y))
	check("collapsing is remembered", bool(Settings.value("playtest_minimized")))
	panel.set_minimized(false)
	await process_frame
	check("expanding brings the list back", not panel.minimized and panel._body.visible and panel.size.y > 120, str(panel.size))
	ed._set_playtest_panel(false)
	await process_frame
	check("View > Playtest panel hides it again", not panel.visible and not bool(Settings.value("playtest_minimized")))

	# ---- the F2 texture picker: wide enough that nothing scrolls sideways
	ed._open_picker(func(_id): pass)
	await process_frame
	await process_frame
	var scroll := ed._picker.get_child(0) as ScrollContainer
	check("the texture picker is at least 700 px wide", ed._picker.size.x >= 700, str(ed._picker.size))
	check("...and never scrolls sideways", scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	var library := scroll.get_child(0) as Control
	check("the thumbnails fit the width", library.get_combined_minimum_size().x <= scroll.size.x,
		"%s vs %s" % [library.get_combined_minimum_size().x, scroll.size.x])
	ed._picker.hide()
	print("UI SHELL: " + ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
