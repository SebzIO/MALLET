class_name WelcomeScreen
extends Control
## The "start a new map" screen: a card per ready-made template (res://templates/*.mallet with a matching .png
## thumbnail), plus "Open existing map…". Shown on launch and when New is pressed.

signal template_chosen(path: String)
signal open_requested

const TEMPLATE_DIR := "res://templates/"
const CARD_W := 300                         ## a template card's width (three a row)
const THUMB := Vector2(284, 124)

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
	sb.set_content_margin_all(18)
	sb.border_color = Color(0.25, 0.28, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Start a new map"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Pick a starting point. Every template is a complete map you can play straight away (P) and export to SurfsUp."
	sub.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	box.add_child(sub)
	var news := Label.new()
	news.text = "New in %s: %s" % [MalletVersion.VERSION, MalletVersion.NEWS]
	news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	news.custom_minimum_size.x = CARD_W * 3 + 32
	news.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	box.add_child(news)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 12)
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
	var guide := Button.new()
	guide.text = "  New here? Read the guide  "
	guide.tooltip_text = "The MALLET guide: a first map in ten minutes, then everything else (opens in your browser)."
	guide.pressed.connect(func(): MalletVersion.open_doc())
	row.add_child(guide)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var ver := Label.new()
	ver.text = MalletVersion.full() + "   "
	ver.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	row.add_child(ver)
	_close = Button.new()
	_close.text = "  Keep the current map (Esc)  "
	_close.pressed.connect(hide)
	row.add_child(_close)


static func template_paths() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(TEMPLATE_DIR):
		if f.ends_with(".mallet"):
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
	b.custom_minimum_size = Vector2(CARD_W, 0)
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
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# through the importer, not the raw file: an exported MALLET only has the converted texture
	var picture := path.get_basename() + ".png"
	if ResourceLoader.exists(picture):
		thumb.texture = load(picture)
	v.add_child(thumb)
	var t := Label.new()
	t.text = info["title"]
	t.add_theme_font_size_override("font_size", 17)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var d := Label.new()
	d.text = info["description"]
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(THUMB.x, 0)
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	# the button's own size must hold the card contents (children of a Button don't size it)
	b.custom_minimum_size = Vector2(CARD_W, THUMB.y + 16 + 6 * 2 + 24 + 74)
	b.pressed.connect(func(): template_chosen.emit(path))
	return b


## close_text names what Esc / the close button leaves you with (the starter map on launch, your map after New).
func popup(close_text: String) -> void:
	_close.text = "  %s (Esc)  " % close_text
	show()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
