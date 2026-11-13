class_name FieldGuard
extends Node
## Typing boxes behave (0.23.2): a mouse press anywhere outside the box you are typing in ends the typing, and the
## value you typed is taken (a number box takes it when it loses focus; one that doesn't parse goes back to what it
## was). Number boxes (every SpinBox, every DragNumber) only accept a number: letters never get in. Text boxes (names,
## search, a sign's words) are untouched.
##
## One guard watches the main window; `install` also puts one in every window that opens (the material maker...),
## since a window's clicks never reach the main window's input.

const NUMBER_CHARS := "0123456789.-+"
static var _installed := false


## Watch the whole tree: every number box gets the filter, every window its own guard. Once per run.
static func install(tree: SceneTree) -> void:
	if _installed:
		return
	_installed = true
	var g := FieldGuard.new()
	g.name = "FieldGuard"
	tree.root.add_child.call_deferred(g)
	tree.node_added.connect(_on_node_added)
	for n in tree.root.find_children("*", "", true, false):
		_on_node_added(n)


static func _on_node_added(n: Node) -> void:
	if n is SpinBox:
		numbers_only((n as SpinBox).get_line_edit())
	elif n is DragNumber:
		numbers_only(n as LineEdit)
	elif n is Window and not n is Popup and not n.has_node("FieldGuard"):
		var g := FieldGuard.new()
		g.name = "FieldGuard"
		n.add_child.call_deferred(g)


## Typing in this box keeps only what can be part of a number (a comma becomes a point).
static func numbers_only(le: LineEdit) -> void:
	if le == null or le.has_meta("numbers_only"):
		return
	le.set_meta("numbers_only", true)
	le.text_changed.connect(func(t: String): _filter(le, t))


static func _filter(le: LineEdit, t: String) -> void:
	var clean := ""
	for ch in t.replace(",", "."):
		if NUMBER_CHARS.contains(ch):
			clean += ch
	if clean == t:
		return
	var caret := le.caret_column - (t.length() - clean.length())
	le.text = clean
	le.caret_column = clampi(caret, 0, clean.length())


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit or f is TextEdit):
		return
	var area: Control = f.get_parent() if f.get_parent() is SpinBox else f   # (a number box's arrows are part of it)
	if not area.get_global_rect().has_point(area.get_global_mouse_position()):
		f.release_focus()                                # (the box takes what was typed as it loses focus)
