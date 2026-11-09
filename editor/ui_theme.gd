class_name UiTheme
extends RefCounted
## One look for every menu, panel and button MALLET draws. Installed once on the window (editor.gd _ready), so every
## popup, dialog, panel and button inherits it instead of each one hand-rolling its own colors. Dark surfaces, a
## visible 1 px outline with a lighter edge, clear hover and pressed states, and dimmed section headers.

const BG := Color("1b1e24")
const BG_DARK := Color("15171c")
const BG_HOVER := Color("2b303b")
const BG_PRESSED := Color("363d4c")
const BG_DISABLED := Color("1a1c22")
const BORDER := Color("39404e")
const BORDER_LIGHT := Color("535d71")
const ACCENT := Color("5a9bdc")
const TEXT := Color("e2e6ee")
const TEXT_DIM := Color("98a1b1")
const TEXT_OFF := Color("6c7482")

const BUTTONS := ["Button", "MenuButton", "OptionButton", "CheckButton", "CheckBox"]

static var _shared: Theme


## The one Theme instance: on the window (dialogs and popups) and on the panels that sit under a CanvasLayer, where
## a window's theme does not reach.
static func shared() -> Theme:
	if _shared == null:
		_shared = make()
	return _shared


static func box(bg: Color, border: Color, width := 1, radius := 4, margin := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## A panel's own background: the playtest panel, build mode's texture and entity menus, the ramp creator.
static func panel_box(radius := 8, margin := 10) -> StyleBoxFlat:
	return box(BG, BORDER_LIGHT, 1, radius, margin)


## A dimmed header over a group of controls (it sits above what it names, like a menu's own separators).
static func header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", TEXT_DIM)
	return l


static func make() -> Theme:
	var t := Theme.new()
	var normal := box(BG, BORDER, 1, 4, 6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 5
	normal.content_margin_bottom = 5
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BG_HOVER
	hover.border_color = BORDER_LIGHT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BG_PRESSED
	pressed.border_color = ACCENT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = BG_DISABLED
	disabled.border_color = BORDER
	var focused := box(Color(0, 0, 0, 0), ACCENT, 1, 4, 0)
	for type in BUTTONS:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focused)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, TEXT_OFF)
		t.set_font_size("font_size", type, 14)
	# menus: a bordered panel, roomier rows, a lit row under the pointer, a visible separator
	t.set_stylebox("panel", "PopupMenu", panel_box(6, 6))
	t.set_stylebox("hover", "PopupMenu", box(BG_HOVER, Color(0, 0, 0, 0), 0, 3, 4))
	var sep := StyleBoxLine.new()
	sep.color = BORDER
	sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", TEXT_OFF)
	t.set_color("font_separator_color", "PopupMenu", TEXT_DIM)
	t.set_font_size("font_size", "PopupMenu", 14)
	t.set_constant("v_separation", "PopupMenu", 5)
	# panels and text fields
	t.set_stylebox("panel", "PanelContainer", box(BG, BORDER, 1, 6, 6))
	t.set_stylebox("panel", "Panel", box(BG, BORDER, 1, 6, 6))
	t.set_stylebox("normal", "LineEdit", box(BG_DARK, BORDER, 1, 3, 5))
	t.set_stylebox("focus", "LineEdit", box(BG_DARK, ACCENT, 1, 3, 5))
	t.set_stylebox("read_only", "LineEdit", box(BG_DISABLED, BORDER, 1, 3, 5))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_font_size("font_size", "LineEdit", 14)
	# lists (the outliner, the playtest panel)
	t.set_stylebox("panel", "Tree", box(BG_DARK, BORDER, 1, 4, 4))
	t.set_stylebox("selected", "Tree", box(Color(0.20, 0.33, 0.50, 0.85), Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("selected_focus", "Tree", box(Color(0.24, 0.40, 0.60, 0.95), Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("cursor", "Tree", box(Color(0, 0, 0, 0), ACCENT, 1, 3, 0))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_font_size("font_size", "Tree", 14)
	# dividers
	t.set_stylebox("separator", "HSeparator", sep)
	var vsep := StyleBoxLine.new()
	vsep.color = BORDER
	vsep.thickness = 1
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	return t
