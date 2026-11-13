extends SceneTree
## Typing boxes (0.23.2): clicking anywhere outside the box you are typing in ends the typing and takes the value
## (the booster's "Push angle above horizontal" kept the cursor before), number boxes refuse letters, text boxes
## keep them, and the same holds in the material maker's window.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/field_guard_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func type_text(t: String) -> void:
	for ch in t:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(ch.to_upper()) if ch.to_upper() != ch.to_lower() else KEY_NONE
		Input.parse_input_event(e)
		Input.flush_buffered_events()
		await process_frame


func click_at(p: Vector2) -> void:
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.position = p
		m.global_position = p
		Input.warp_mouse(p)
		Input.parse_input_event(m)
		Input.flush_buffered_events()
		await process_frame


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._add_entity("booster")
	await process_frame
	var b: EntityNode = ed.selected
	ed._refresh_props()
	await process_frame
	var box: SpinBox = ed._fields["pitch"][1]
	var le := box.get_line_edit()
	le.grab_focus()
	await process_frame
	le.select_all()
	await type_text("3a5x")
	check("a number box refuses letters (typed 3a5x)", le.text == "35", "(%s)" % le.text)
	var view: Control = ed.panes[0]
	await click_at(view.get_global_rect().get_center())
	check("clicking outside it ends the typing", root.gui_get_focus_owner() != le)
	check("...and takes the value (push angle 35)", is_equal_approx(float(b.to_dict().get("pitch", 0.0)), 35.0) and is_equal_approx(box.value, 35.0),
		"(box %s, booster %s)" % [box.value, b.to_dict().get("pitch")])
	# a text box keeps letters
	var name_box: LineEdit = null
	for n in root.find_children("*", "LineEdit", true, false):
		if n.is_visible_in_tree() and not n.has_meta("numbers_only") and n.editable and not n.get_parent() is SpinBox:
			name_box = n
			break
	if name_box:
		name_box.grab_focus()
		name_box.text = ""
		await type_text("Ab1")
		check("a text box keeps letters", name_box.text == "Ab1", "(%s: %s)" % [name_box.name, name_box.text])
		await click_at(view.get_global_rect().get_center())
	# the material maker's window
	var mm: MaterialMakerDialog = ed.open_material_maker("")
	await process_frame
	await process_frame
	var sp: SpinBox = mm._size
	check("number boxes in other windows are guarded too", sp.get_line_edit().has_meta("numbers_only") and mm.has_node("FieldGuard"))
	mm.hide()
	print("field_guard_test: ", "PASS" if ok else "FAIL")
	quit()
