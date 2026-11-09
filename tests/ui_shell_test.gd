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

	# ---- the playtest panel: its own button at the top, and gone from Export
	check("the playtest panel has its own toolbar button", ed._fields.has("playtest_button"))
	var names := []
	var export_menu: PopupMenu = (ed._fields["menu_Export"] as MenuButton).get_popup()
	for i in export_menu.item_count:
		names.append(export_menu.get_item_text(i))
	check("Export still starts a session", names.has("Playtest session…"), str(names))
	check("the panel is not in the Export menu any more", not names.has("Playtest panel"))
	var pb: CheckButton = ed._fields["playtest_button"]
	pb.button_pressed = true
	await process_frame
	check("its button shows the panel", ed._playtest_panel.visible and pb.button_pressed)

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
	pb.button_pressed = false
	await process_frame
	check("the button hides it again", not panel.visible and not pb.button_pressed and not bool(Settings.value("playtest_minimized")))
	print("UI SHELL: " + ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
