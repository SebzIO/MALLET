class_name WelcomeScreen
extends Control
## The "start a new map" screen: a card per ready-made template (res://templates/*.sfmap with a matching .png
## thumbnail), plus "Open existing map…". Shown on launch and when New is pressed.

signal template_chosen(path: String)
signal open_requested

const TEMPLATE_DIR := "res://templates/"

var _grid: GridContainer
var _close: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP            # nothing behind the screen reacts while it is up
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.15)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(24)
	sb.border_color = Color(0.25, 0.28, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Start a new map"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Pick a starting point. Every template is a complete map you can play straight away (P) and export to SurfsUp."
	sub.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	box.add_child(sub)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	box.add_child(_grid)
	for path in template_paths():
		_grid.add_child(_card(path))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var open := Button.new()
	open.text = "  Open existing map…  "
	open.pressed.connect(func(): open_requested.emit())
	row.add_child(open)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var ver := Label.new()
	ver.text = SurfForgeVersion.full() + "   "
	ver.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	row.add_child(ver)
	_close = Button.new()
	_close.text = "  Keep the current map (Esc)  "
	_close.pressed.connect(hide)
	row.add_child(_close)


static func template_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(TEMPLATE_DIR):
		if f.ends_with(".sfmap"):
			out.append(TEMPLATE_DIR + f)
	out.sort()
	return out


static func template_info(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var info: Dictionary = data.get("template", {}) if data is Dictionary else {}
	return {"title": info.get("title", path.get_file().get_basename()), "description": info.get("description", "")}


func _card(path: String) -> Button:
	var info := template_info(path)
	var b := Button.new()
	b.custom_minimum_size = Vector2(384, 0)
	b.tooltip_text = info["description"]
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(368, 207)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bytes := FileAccess.get_file_as_bytes(path.get_basename() + ".png")
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_png_from_buffer(bytes) == OK:
			thumb.texture = ImageTexture.create_from_image(img)
	v.add_child(thumb)
	var t := Label.new()
	t.text = info["title"]
	t.add_theme_font_size_override("font_size", 18)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := Label.new()
	d.text = info["description"]
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(368, 0)
	d.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	# the button's own size must hold the card contents (children of a Button don't size it)
	b.custom_minimum_size = Vector2(384, 207 + 16 + 6 * 2 + 26 + 72)
	b.pressed.connect(func(): template_chosen.emit(path))
	return b


## close_text names what Esc / the close button leaves you with (the starter map on launch, your map after New).
func popup(close_text: String) -> void:
	_close.text = "  %s (Esc)  " % close_text
	show()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
