class_name PickerCssFolder
extends RefCounted
## One CS:S folder in the material picker: a row you click to open, with its thumbnails made the first time it's
## opened (or when the search box finds something in it).

var editor: Node
var toggle: Button
var grid: GridContainer
var entries: Array = []
var buttons := {}                        ## id -> Button
var _open := false


func setup(ed: Node, box: VBoxContainer, category: String, list: Array) -> void:
	editor = ed
	entries = list
	toggle = Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(func(): set_open(not _open))
	box.add_child(toggle)
	grid = GridContainer.new()
	grid.columns = 4
	grid.visible = false
	box.add_child(grid)
	_label(category)


func _label(category: String) -> void:
	toggle.set_meta("category", category)
	toggle.text = "%s %s  (%d)" % ["▾" if _open else "▸", category.trim_prefix("CS:S · "), entries.size()]


func set_open(on: bool) -> void:
	_open = on
	if on:
		_fill()
	grid.visible = on
	_label(toggle.get_meta("category"))


func _fill() -> void:
	if not buttons.is_empty():
		return
	for e in entries:
		var b := Button.new()
		b.icon = CssLibrary.preview(e["id"])
		b.text = e["name"]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true
		b.custom_minimum_size = Vector2(128, 132)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.tooltip_text = "%s - CS:S material (Valve's), one repeat covers %.1f m" % [String(e["id"]).substr(4), float(e["size"])]
		var id: String = e["id"]
		b.pressed.connect(func(): editor._picker_pick(id))
		grid.add_child(b)
		buttons[id] = b
		editor._fields["pick_" + id] = b


## The search box: "" (or under 3 letters: too many matches to show) closes the folder again; otherwise it opens
## when something in it matches.
func search(q: String) -> void:
	if q.length() < 3:
		toggle.visible = true
		for b in buttons.values():
			b.visible = true
		set_open(false)
		return
	var hits := entries.filter(func(e): return (String(e["id"]) + " " + String(e.get("surface", ""))).to_lower().contains(q))
	toggle.visible = not hits.is_empty()
	if hits.is_empty():
		grid.visible = false
		return
	_fill()
	var ids := {}
	for e in hits:
		ids[e["id"]] = true
	for id in buttons:
		buttons[id].visible = ids.has(id)
	_open = true
	grid.visible = true
	_label(toggle.get_meta("category"))
