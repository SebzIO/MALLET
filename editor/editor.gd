extends Node3D
## SurfForge main editor: four views (perspective / top / front / side), ramp + platform tools,
## properties panel, undo/redo, save/load and play mode.
##
## Mouse (any view):  left-click selects. Drag a yellow handle to reshape a ramp; drag the object itself to move it.
##                    Perspective: drag = across the ground, Shift+drag = up/down. Ortho views move along what you see.
##                    Double-click a selected ramp to add a bend point there.
## Navigation:        perspective: right-drag orbit, middle-drag pan, wheel zoom, right-drag + WASD/QE fly.
##                    ortho: right/middle-drag pan, wheel zoom.
## Keys:              N ramp · B start platform · M finish platform · Del delete · Ctrl+D duplicate · F frame
##                    arrows / PgUp PgDn nudge · [ ] rotate 15° · V one/four views · G snap · P play
##                    Ctrl+Z / Ctrl+Y undo/redo · Ctrl+S save · Ctrl+O open

const MAP_FORMAT := "surfforge-map"
const MAP_VERSION := 2
const HANDLE_RADIUS := 6.0          ## px
const PICK_PIXELS := 12.0

var ramps_root := Node3D.new()
var entities_root := Node3D.new()
var selected: Node3D = null          ## a RampNode or an EntityNode
var selected_point := -1
var snap_enabled := true
var snap_step := 4.0
var current_path := ""
var play := PlayMode.new()
var panes: Array[ViewPane] = []
var active_pane: ViewPane
var quad_view := true

var _undo: Array = []
var _redo: Array = []
var _coalesce_key := ""
var _coalesce_time := 0.0
# drag state
enum Drag { NONE, POINT, OBJECT }
var _drag := Drag.NONE
var _drag_pane: ViewPane
var _drag_plane := Plane()
var _drag_vertical := false
var _drag_start_hit := Vector3.ZERO
var _drag_origin := {}               ## snapshot of the dragged object before the drag
var _drag_moved := false

# ui
var _ui := CanvasLayer.new()
var _view_grid: GridContainer
var _props_panel: PanelContainer
var _ramp_props: VBoxContainer
var _entity_props: VBoxContainer
var _booster_props: VBoxContainer
var _status: Label
var _info: Label
var _fields := {}
var _updating_ui := false
var _file_dialog: FileDialog
var _export_dialog: ConfirmationDialog
var _export_name: LineEdit
var _export_dir: LineEdit
var _dir_dialog: FileDialog
const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	_build_world()
	_build_ui()
	add_child(play)
	play.stopped.connect(_on_play_stopped)
	_new_map()
	get_window().title = "SurfForge"


# ================================================================================================= world
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.46, 0.68)
	sky_mat.sky_horizon_color = Color(0.68, 0.74, 0.82)
	sky_mat.ground_bottom_color = Color(0.18, 0.19, 0.22)
	sky_mat.ground_horizon_color = Color(0.5, 0.53, 0.58)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 1500.0
	add_child(sun)

	var grid := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12000, 12000)
	grid.mesh = plane
	var gm := ShaderMaterial.new()
	gm.shader = load("res://editor/grid.gdshader")
	grid.material_override = gm
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.layers = 2                                     # perspective only: the ortho views draw their own grid
	add_child(grid)
	add_child(ramps_root)
	add_child(entities_root)


# ================================================================================================= ui
func _build_ui() -> void:
	add_child(_ui)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	_ui.add_child(root)

	var bar_panel := PanelContainer.new()
	root.add_child(bar_panel)
	var bar := HFlowContainer.new()                    # wraps onto a second row on narrower windows
	bar.add_theme_constant_override("h_separation", 5)
	bar.add_theme_constant_override("v_separation", 2)
	bar_panel.add_child(bar)
	var title := Label.new()
	title.text = "  SurfForge  "
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	for spec in [["New", _new_map_clicked], ["Open…", _open_clicked], ["Save", _save_clicked], ["|", null],
			["+ Ramp (N)", _add_ramp_clicked], ["+ Start (B)", func(): _add_entity("start")],
			["+ Finish (M)", func(): _add_entity("finish")], ["+ Kill zone (K)", func(): _add_entity("kill")],
			["+ Booster (J)", func(): _add_entity("booster")], ["|", null],
			["Extend", _extend_clicked], ["Add Bend", _bend_clicked], ["Duplicate", _duplicate_clicked],
			["Delete", _delete_clicked], ["|", null], ["Undo", undo], ["Redo", redo], ["|", null],
			["Frame (F)", _frame_clicked], ["1 / 4 Views (V)", _toggle_views], ["|", null], ["▶ Play (P)", _play_clicked],
			["Export to SurfsUp", _export_clicked]]:
		if spec[0] == "|":
			bar.add_child(VSeparator.new())
			continue
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	var snap := CheckButton.new()
	snap.text = "Snap"
	snap.button_pressed = snap_enabled
	snap.focus_mode = Control.FOCUS_NONE
	snap.toggled.connect(func(on): snap_enabled = on; _set_status("Grid snap %s" % ("on" if on else "off")))
	bar.add_child(snap)
	_fields["snap_button"] = snap
	var step := OptionButton.new()
	for s in [1, 2, 4, 8, 16]:
		step.add_item("%d m" % s, s)
	step.select(2)
	step.focus_mode = Control.FOCUS_NONE
	step.item_selected.connect(func(i): snap_step = float(step.get_item_id(i)))
	bar.add_child(step)

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	root.add_child(middle)
	_view_grid = GridContainer.new()
	_view_grid.columns = 2
	_view_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_grid.add_theme_constant_override("h_separation", 2)
	_view_grid.add_theme_constant_override("v_separation", 2)
	middle.add_child(_view_grid)
	for k in [ViewPane.Kind.PERSPECTIVE, ViewPane.Kind.TOP, ViewPane.Kind.FRONT, ViewPane.Kind.SIDE]:
		var pane := ViewPane.new(k, self)
		panes.append(pane)
		_view_grid.add_child(pane)
	active_pane = panes[0]

	_props_panel = PanelContainer.new()
	_props_panel.custom_minimum_size = Vector2(300, 0)
	middle.add_child(_props_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_props_panel.add_child(margin)
	var props := VBoxContainer.new()
	props.add_theme_constant_override("separation", 8)
	margin.add_child(props)
	_build_props(props)

	var status_panel := PanelContainer.new()
	root.add_child(status_panel)
	_status = Label.new()
	status_panel.add_child(_status)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.sfmap ; SurfForge map"])
	_file_dialog.current_dir = ProjectSettings.globalize_path("res://maps") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	_file_dialog.file_selected.connect(_on_file_chosen)
	_ui.add_child(_file_dialog)
	_build_export_dialog()


func _build_props(props: VBoxContainer) -> void:
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	props.add_child(head)
	_fields["head"] = head

	_ramp_props = VBoxContainer.new()
	_ramp_props.add_theme_constant_override("separation", 6)
	props.add_child(_ramp_props)
	var style := OptionButton.new()
	style.add_item("Hollow (open V underneath)", 0)
	style.add_item("Solid (flat bottom)", 1)
	style.focus_mode = Control.FOCUS_NONE
	style.item_selected.connect(func(i): _edit_prop("solid", i == 1))
	_add_row(_ramp_props, "Style", style)
	_fields["solid"] = style
	_add_slider(_ramp_props, "width", "Width (m)", 4.0, 60.0, 0.5)
	_add_slider(_ramp_props, "height", "Height (m)", 2.0, 40.0, 0.25)
	_add_slider(_ramp_props, "base_depth", "Base depth (m, solid only)", 0.0, 60.0, 0.5)
	_add_slider(_ramp_props, "detail", "Smoothness (segments / m)", 0.1, 4.0, 0.05)
	_add_slider(_ramp_props, "roll", "Tilt (°)", -45.0, 45.0, 1.0)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("color", c))
	_add_row(_ramp_props, "Colour", cp)
	_fields["color"] = cp

	_entity_props = VBoxContainer.new()
	_entity_props.add_theme_constant_override("separation", 6)
	props.add_child(_entity_props)
	_add_slider(_entity_props, "size_x", "Width (m)", 4.0, 200.0, 1.0)
	_add_slider(_entity_props, "size_z", "Depth (m)", 4.0, 200.0, 1.0)
	_add_slider(_entity_props, "size_y", "Height (m)", 2.0, 200.0, 1.0)
	_add_slider(_entity_props, "yaw", "Facing (°)", -180.0, 180.0, 5.0)
	_booster_props = VBoxContainer.new()
	_booster_props.add_theme_constant_override("separation", 6)
	_entity_props.add_child(_booster_props)
	_add_slider(_booster_props, "pitch", "Push angle above horizontal (°)", -89.0, 89.0, 1.0)
	_add_slider(_booster_props, "strength", "Strength (u/s)", 50.0, 5000.0, 50.0)
	var mode := OptionButton.new()
	mode.add_item("Add to the player's speed", 0)
	mode.add_item("Set the player's speed", 1)
	mode.focus_mode = Control.FOCUS_NONE
	mode.item_selected.connect(func(i): _edit_prop("mode", i))
	_add_row(_booster_props, "Mode", mode)
	_fields["mode"] = mode

	props.add_child(HSeparator.new())
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	props.add_child(_info)
	props.add_child(HSeparator.new())
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	help.text = ("Drag yellow handles to reshape · drag the object to move it (Shift = up/down in 3D view)\n"
		+ "Double-click a ramp to add a bend\nArrows / PgUp PgDn nudge · [ ] rotate\n"
		+ "N ramp · B start · M finish · K kill zone · J booster · P play\nSpace maximise the view under the mouse · V 3D / four views\nF frame · G snap\n"
		+ "Del delete · Ctrl+D duplicate · Ctrl+Z undo · Ctrl+S save")
	props.add_child(help)


func _add_row(parent: Container, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	parent.add_child(control)


func _add_slider(parent: Container, key: String, label: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.custom_minimum_size = Vector2(86, 0)
	s.value_changed.connect(func(v): if not _updating_ui: box.set_value_no_signal(v); _edit_prop(key, v))
	box.value_changed.connect(func(v): if not _updating_ui: s.set_value_no_signal(v); _edit_prop(key, v))
	row.add_child(s)
	row.add_child(box)
	_add_row(parent, label, row)
	_fields[key] = [s, box]


func _set_field(key: String, v: float) -> void:
	_fields[key][0].value = v
	_fields[key][1].value = v


func _refresh_props() -> void:
	_props_panel.visible = selected != null
	if selected == null:
		return
	_updating_ui = true
	var is_ramp := selected is RampNode
	_ramp_props.visible = is_ramp
	_entity_props.visible = not is_ramp
	if is_ramp:
		var r := selected as RampNode
		_fields["head"].text = "Ramp"
		_fields["solid"].select(1 if r.solid else 0)
		for key in ["width", "height", "base_depth", "detail", "roll"]:
			_set_field(key, r.get(key))
		_fields["color"].color = r.color
	else:
		var e := selected as EntityNode
		_fields["head"].text = e.label()
		_set_field("size_x", e.size.x)
		_set_field("size_z", e.size.z)
		_set_field("size_y", e.size.y)
		_set_field("yaw", e.yaw)
		_fields["size_y"][0].get_parent().get_parent().get_child(_fields["size_y"][0].get_parent().get_index() - 1).visible = e.is_volume()
		_fields["size_y"][0].get_parent().visible = e.is_volume()
		_booster_props.visible = e.kind == "booster"
		if e.kind == "booster":
			_set_field("pitch", e.pitch)
			_set_field("strength", e.strength)
			_fields["mode"].select(e.mode)
	_updating_ui = false
	_refresh_info()


func _refresh_info() -> void:
	if selected == null:
		return
	if selected is RampNode:
		var r := selected as RampNode
		var face_angle := rad_to_deg(atan2(r.height, r.width * 0.5))
		var surfable := "surfable" if face_angle > 45.6 else "too flat: players will stand on it"
		var drop := r.points[0].y - r.points[r.points.size() - 1].y
		_info.text = ("Length: %.0f m\nDrop: %.0f m\nFace angle: %.1f° (%s)\nControl points: %d\nTriangles: %d"
			% [r.length, drop, face_angle, surfable, r.points.size(), r.triangle_count])
	else:
		var e := selected as EntityNode
		var about := {
			"start": "Players spawn here facing the arrow. The timer starts when they leave the green zone.",
			"finish": "Landing in the blue zone finishes the run.",
			"kill": "Touching this sends the player back to their spawn. Players fly through it; it is invisible in game.",
			"booster": "Players passing through are pushed along the arrow. Add = extra speed on top of theirs; Set = this exact speed.",
		}
		_info.text = "Position: (%.0f, %.0f, %.0f)\n%s" % [e.position.x, e.position.y, e.position.z, about.get(e.kind, "")]


func _set_status(t: String) -> void:
	_status.text = "  " + t


func _toggle_views() -> void:
	quad_view = not quad_view
	for i in panes.size():
		panes[i].visible = quad_view or i == 0
	_view_grid.columns = 2 if quad_view else 1
	_set_status("Four views" if quad_view else "Single 3D view")


## Space: fill the editor with the view under the mouse; press again to go back to four views.
func _toggle_maximise_hovered() -> void:
	var mouse := get_viewport().get_mouse_position()
	var hovered: ViewPane = active_pane
	for p in panes:
		if p.visible and p.get_global_rect().has_point(mouse):
			hovered = p
	var maximised: bool = panes.filter(func(p): return p.visible).size() == 1
	for p in panes:
		p.visible = maximised or p == hovered
	_view_grid.columns = 2 if maximised else 1
	quad_view = maximised
	active_pane = hovered
	_set_status("Four views" if maximised else "%s view - Space to go back to four views" % ViewPane.NAMES[hovered.kind].get_slice(" ", 0))


func set_active_pane(p: ViewPane) -> void:
	active_pane = p


# ================================================================================================= map data
func _map_dict() -> Dictionary:
	var rs := []
	for r in ramps_root.get_children():
		rs.append(r.to_dict())
	var es := []
	for e in entities_root.get_children():
		es.append(e.to_dict())
	return {"format": MAP_FORMAT, "version": MAP_VERSION, "ramps": rs, "entities": es}


func _load_dict(data: Dictionary) -> void:
	_select(null)
	for root in [ramps_root, entities_root]:
		for c in root.get_children():
			root.remove_child(c)
			c.queue_free()
	for rd in data.get("ramps", []):
		var r := RampNode.new()
		ramps_root.add_child(r)
		r.from_dict(rd)
	for ed in data.get("entities", []):
		var e := EntityNode.new()
		entities_root.add_child(e)
		e.from_dict(ed)


func _new_map() -> void:
	_load_dict({})
	_undo.clear()
	_redo.clear()
	current_path = ""
	var s := EntityNode.create("start")
	s.position = Vector3(-84, 128, 0)
	s.yaw = -90.0
	entities_root.add_child(s)
	var r := _make_ramp(Vector3(-60, 120, 0), Vector3(60, 90, 0))
	var f := EntityNode.create("finish")
	f.position = Vector3(110, 60, 0)
	entities_root.add_child(f)
	_select(r)
	for p in panes:
		p.frame(Vector3(20, 100, 0), 110)
	_set_status("New map: a start platform, one ramp and a finish. Shape the ramp, then press P to play.")


func _make_ramp(a: Vector3, b: Vector3) -> RampNode:
	var r := RampNode.new()
	r.points = PackedVector3Array([a, a.lerp(b, 0.5), b])
	ramps_root.add_child(r)
	return r


func _all_objects() -> Array:
	return ramps_root.get_children() + entities_root.get_children()


# ================================================================================================= undo / redo
## Call before any change. `key` lets rapid repeats of the same edit (slider drags) share one undo step.
func _checkpoint(key := "") -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if key != "" and key == _coalesce_key and now - _coalesce_time < 0.8:
		_coalesce_time = now
		return
	_coalesce_key = key
	_coalesce_time = now
	_undo.append(_snapshot())
	if _undo.size() > 300:
		_undo.pop_front()
	_redo.clear()


func _snapshot() -> Dictionary:
	var sel := _all_objects().find(selected) if selected else -1
	return {"map": _map_dict(), "sel": sel, "pt": selected_point}


func _restore(s: Dictionary) -> void:
	_load_dict(s["map"])
	var objs := _all_objects()
	var sel: int = s["sel"]
	if sel >= 0 and sel < objs.size():
		_select(objs[sel], s["pt"])


func undo() -> void:
	if _undo.is_empty():
		_set_status("Nothing to undo")
		return
	_redo.append(_snapshot())
	_restore(_undo.pop_back())
	_coalesce_key = ""
	_set_status("Undo")


func redo() -> void:
	if _redo.is_empty():
		_set_status("Nothing to redo")
		return
	_undo.append(_snapshot())
	_restore(_redo.pop_back())
	_coalesce_key = ""
	_set_status("Redo")


# ================================================================================================= selection
func _select(obj: Node3D, point := -1) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
		if selected is RampNode and selected.changed.is_connected(_refresh_info):
			selected.changed.disconnect(_refresh_info)
	selected = obj
	selected_point = point if obj is RampNode else -1
	if selected:
		selected.set_selected(true)
		if selected is RampNode:
			selected.changed.connect(_refresh_info)
	_refresh_props()


## Handles and helper lines, drawn in 2D on top of each view so they stay a constant size.
func draw_pane_overlay(pane: ViewPane, ov: Control) -> void:
	if play.active or selected == null:
		return
	var cam := pane.camera
	var lines: Array[PackedVector3Array] = selected.outline if selected is RampNode else selected.outline_lines()
	for line in lines:                           # selection outline (keeps the object's real colour visible)
		for i in range(1, line.size()):
			if cam.is_position_behind(line[i]) or cam.is_position_behind(line[i - 1]):
				continue
			ov.draw_line(cam.unproject_position(line[i - 1]), cam.unproject_position(line[i]), Color(0.3, 0.75, 1.0, 0.95), 2.0)
	if selected is RampNode:
		var pts: PackedVector3Array = selected.points
		for i in pts.size():
			if cam.is_position_behind(pts[i]):
				continue
			var s := cam.unproject_position(pts[i])
			if pane.kind == ViewPane.Kind.PERSPECTIVE and not cam.is_position_behind(Vector3(pts[i].x, 0, pts[i].z)):
				ov.draw_line(s, cam.unproject_position(Vector3(pts[i].x, 0, pts[i].z)), Color(1, 0.85, 0.15, 0.25), 1.0)
			if i > 0 and not cam.is_position_behind(pts[i - 1]):
				ov.draw_line(cam.unproject_position(pts[i - 1]), s, Color(1, 0.85, 0.15, 0.35), 1.0)
		for i in pts.size():
			if cam.is_position_behind(pts[i]):
				continue
			var s := cam.unproject_position(pts[i])
			var col := Color(1.0, 0.35, 0.1) if i == selected_point else Color(1.0, 0.85, 0.15)
			ov.draw_circle(s, HANDLE_RADIUS + 1.5, Color(0, 0, 0, 0.7))
			ov.draw_circle(s, HANDLE_RADIUS, col)
	else:
		var e := selected as EntityNode
		if not cam.is_position_behind(e.global_position):
			var s := cam.unproject_position(e.global_position)
			ov.draw_rect(Rect2(s - Vector2(6, 6), Vector2(12, 12)), Color(1, 0.85, 0.15), true)
			ov.draw_rect(Rect2(s - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7), false, 1.5)


# ================================================================================================= view input
## Mouse input from a view (after its own camera navigation). Returns true if used.
func pane_input(pane: ViewPane, event: InputEvent) -> bool:
	if play.active:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click and selected is RampNode:
				_insert_point_at_mouse(pane, event.position)
				return true
			var hp := _pick_handle(pane, event.position)
			if hp >= 0:
				_begin_drag(pane, Drag.POINT, event.position, event.shift_pressed, hp)
				return true
			var obj := _pick_object(pane, event.position)
			if obj != selected:
				_select(obj)
			elif obj is RampNode:
				selected_point = -1
			if obj:
				_begin_drag(pane, Drag.OBJECT, event.position, event.shift_pressed)
				_set_status("Selected %s - drag to move it" % ("ramp" if obj is RampNode else obj.label().to_lower()))
			else:
				_set_status("")
			return true
		elif _drag != Drag.NONE:
			_end_drag()
			return true
	elif event is InputEventMouseMotion and _drag != Drag.NONE and pane == _drag_pane:
		_drag_to(event.position, event.shift_pressed)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if play.handle_input(event):
		return
	if event is InputEventKey and event.pressed:
		_handle_key(event)


func _handle_key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	if e.echo and not e.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN]:
		return
	match e.keycode:
		KEY_Z when ctrl:
			if e.shift_pressed: redo()
			else: undo()
		KEY_Y when ctrl: redo()
		KEY_S when ctrl: _save_clicked()
		KEY_O when ctrl: _open_clicked()
		KEY_D when ctrl: _duplicate_clicked()
		KEY_N: _add_ramp_clicked()
		KEY_B: _add_entity("start")
		KEY_M: _add_entity("finish")
		KEY_K: _add_entity("kill")
		KEY_J: _add_entity("booster")
		KEY_P: _play_clicked()
		KEY_V: _toggle_views()
		KEY_SPACE: _toggle_maximise_hovered()
		KEY_DELETE, KEY_BACKSPACE: _delete_clicked()
		KEY_F: _frame_clicked()
		KEY_G:
			snap_enabled = not snap_enabled
			_fields["snap_button"].button_pressed = snap_enabled
		KEY_BRACKETLEFT: _rotate_selected(-15.0)
		KEY_BRACKETRIGHT: _rotate_selected(15.0)
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			_nudge(e.keycode)


func _pick_handle(pane: ViewPane, mouse: Vector2) -> int:
	if not selected is RampNode:
		return -1
	var best := -1
	var best_d := PICK_PIXELS
	var pts: PackedVector3Array = selected.points
	for i in pts.size():
		if pane.camera.is_position_behind(pts[i]):
			continue
		var d := pane.camera.unproject_position(pts[i]).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pick_object(pane: ViewPane, mouse: Vector2) -> Node3D:
	var r := pane.ray(mouse)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 20000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		if hit.collider.has_meta("ramp"):
			return hit.collider.get_meta("ramp")
		if hit.collider.has_meta("entity"):
			return hit.collider.get_meta("entity")
	# fallback: the ridge line on screen (thin ramps seen edge-on in the side views, clicks on the ridge seam)
	var best: Node3D = null
	var best_d := PICK_PIXELS
	for ramp in ramps_root.get_children():
		var path := RampShape.sample_path(ramp.points, 4.0)
		for i in range(1, path.size()):
			if pane.camera.is_position_behind(path[i]) or pane.camera.is_position_behind(path[i - 1]):
				continue
			var a := pane.camera.unproject_position(path[i - 1])
			var b := pane.camera.unproject_position(path[i])
			var d := Geometry2D.get_closest_point_to_segment(mouse, a, b).distance_to(mouse)
			if d < best_d:
				best_d = d
				best = ramp
	return best


func _begin_drag(pane: ViewPane, kind: int, mouse: Vector2, vertical: bool, point := -1) -> void:
	_drag = kind
	_drag_pane = pane
	_drag_moved = false
	if kind == Drag.POINT:
		selected_point = point
	_set_drag_plane(mouse, vertical)


func _drag_anchor() -> Vector3:
	return selected.points[selected_point] if _drag == Drag.POINT else selected.center()


func _set_drag_plane(mouse: Vector2, vertical: bool) -> void:
	_drag_vertical = vertical
	var anchor := _drag_anchor()
	_drag_plane = _drag_pane.drag_plane(anchor, vertical)
	var r := _drag_pane.ray(mouse)
	var hit = _drag_plane.intersects_ray(r[0], r[1])
	_drag_start_hit = hit if hit != null else anchor
	_drag_origin = selected.to_dict()                    # re-based so switching Shift mid-drag doesn't jump


func _drag_to(mouse: Vector2, vertical: bool) -> void:
	if vertical != _drag_vertical and not _drag_pane.is_ortho():
		_set_drag_plane(mouse, vertical)
		return
	var r := _drag_pane.ray(mouse)
	var hit = _drag_plane.intersects_ray(r[0], r[1])
	if hit == null:
		return
	var delta: Vector3 = (hit - _drag_start_hit) * _drag_pane.drag_axes(_drag_vertical)
	if not _drag_moved:
		if delta.length() < 0.01:
			return
		_checkpoint()                                    # first real movement: the object is still in its pre-drag state
		_drag_moved = true
	selected.from_dict(_drag_origin)
	if _drag == Drag.POINT:
		var pts: PackedVector3Array = selected.points
		var p: Vector3 = pts[selected_point] + delta
		pts[selected_point] = _snap_axes(p, _drag_pane.drag_axes(_drag_vertical))
		selected.points = pts
		selected.rebuild()
		_set_status("Point %d: (%.0f, %.0f, %.0f)" % [selected_point, pts[selected_point].x, pts[selected_point].y, pts[selected_point].z])
	else:
		delta = _snap_axes(delta, _drag_pane.drag_axes(_drag_vertical))
		selected.translate_by(delta)
		var c: Vector3 = selected.center()
		_set_status("Moved by (%.0f, %.0f, %.0f) - centre now (%.0f, %.0f, %.0f)" % [delta.x, delta.y, delta.z, c.x, c.y, c.z])
	_refresh_info()


func _snap_axes(v: Vector3, axes: Vector3) -> Vector3:
	if not snap_enabled:
		return v
	for i in 3:
		if axes[i] > 0.5:
			v[i] = snappedf(v[i], snap_step)
	return v


func _end_drag() -> void:
	_drag = Drag.NONE
	_drag_pane = null


## Double-click on the selected ramp: add a control point on the path where you clicked.
func _insert_point_at_mouse(pane: ViewPane, mouse: Vector2) -> void:
	if _pick_object(pane, mouse) != selected:
		return
	var r := pane.ray(mouse)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 20000.0))
	if not hit:
		return
	var ramp := selected as RampNode
	var best := RampShape.nearest_on_path(ramp.points, hit.position)
	_checkpoint()
	var pts := ramp.points
	pts.insert(best["span"] + 1, best["point"])
	ramp.points = pts
	ramp.rebuild()
	selected_point = best["span"] + 1
	_set_status("Added a bend point. Drag it to curve the ramp.")


func _nudge(key: int) -> void:
	if selected == null:
		return
	var step := snap_step if snap_enabled else 1.0
	var d := Vector3.ZERO
	match key:
		KEY_LEFT: d = Vector3(-step, 0, 0)
		KEY_RIGHT: d = Vector3(step, 0, 0)
		KEY_UP: d = Vector3(0, 0, -step)
		KEY_DOWN: d = Vector3(0, 0, step)
		KEY_PAGEUP: d = Vector3(0, step, 0)
		KEY_PAGEDOWN: d = Vector3(0, -step, 0)
	_checkpoint("nudge")
	if selected is RampNode and selected_point >= 0:
		var pts: PackedVector3Array = selected.points
		pts[selected_point] += d
		selected.points = pts
		selected.rebuild()
	else:
		selected.translate_by(d)
	_refresh_info()
	_set_status("Nudged %s" % ["point" if selected is RampNode and selected_point >= 0 else "object"])


func _rotate_selected(deg: float) -> void:
	if selected == null:
		return
	_checkpoint("rotate")
	selected.rotate_by(deg)
	_refresh_props()
	_set_status("Rotated %+.0f°" % deg)


# ================================================================================================= toolbar actions
func _view_center() -> Vector3:
	return (panes[0].camera as OrbitCamera).focus


func _add_ramp_clicked() -> void:
	_checkpoint()
	var cam := panes[0].camera as OrbitCamera
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var c := _view_center()
	c.y = max(c.y, 40.0)
	var a := c - right * 60 + Vector3(0, 15, 0)
	var b := c + right * 60 - Vector3(0, 15, 0)
	if snap_enabled:
		a = a.snapped(Vector3.ONE * snap_step)
		b = b.snapped(Vector3.ONE * snap_step)
	_select(_make_ramp(a, b))
	_set_status("New ramp added at the view centre.")


func _add_entity(kind: String) -> void:
	_checkpoint()
	var c := _view_center()
	if snap_enabled:
		c = c.snapped(Vector3.ONE * snap_step)
	for e in entities_root.get_children():         # a map has one start and one finish: move the existing one
		if e.kind == kind and kind in ["start", "finish"]:
			e.position = c
			_select(e)
			_set_status("Moved the %s to the view centre (a map has one)." % e.label().to_lower())
			return
	var n := EntityNode.create(kind)
	n.position = c
	entities_root.add_child(n)
	_select(n)
	_set_status("Added %s at the view centre." % n.label().to_lower())


func _extend_clicked() -> void:
	if not selected is RampNode:
		return
	_checkpoint()
	var r := selected as RampNode
	var pts := r.points
	var n := pts.size()
	var dir := pts[n - 1] - pts[n - 2]
	pts.append(pts[n - 1] + dir.normalized() * max(dir.length(), 30.0))
	r.points = pts
	r.rebuild()
	selected_point = pts.size() - 1
	_set_status("Ramp extended. Drag the new end point.")


func _bend_clicked() -> void:
	if not selected is RampNode:
		return
	_checkpoint()
	var r := selected as RampNode
	var pts := r.points
	var i: int = clamp(selected_point if selected_point >= 0 else 0, 0, pts.size() - 2)
	pts.insert(i + 1, pts[i].lerp(pts[i + 1], 0.5))
	r.points = pts
	r.rebuild()
	selected_point = i + 1
	_set_status("Bend point added between points %d and %d." % [i, i + 2])


func _duplicate_clicked() -> void:
	if selected is EntityNode and selected.is_volume():
		_checkpoint()
		var copy := EntityNode.new()
		entities_root.add_child(copy)
		copy.from_dict(selected.to_dict())
		copy.translate_by(Vector3(selected.size.x + 8, 0, 0))
		_select(copy)
		_set_status("Duplicated %s." % copy.label().to_lower())
		return
	if not selected is RampNode:
		_set_status("A map has one start and one finish." if selected else "")
		return
	_checkpoint()
	var r := RampNode.new()
	ramps_root.add_child(r)
	r.from_dict(selected.to_dict())
	r.translate_by(Vector3(0, -30, 40))
	_select(r)
	_set_status("Duplicated ramp (moved 30 m down, 40 m over).")


func _delete_clicked() -> void:
	if selected == null:
		return
	_checkpoint()
	if selected is RampNode and selected_point >= 0 and selected.points.size() > 2:
		var r := selected as RampNode
		var pts := r.points
		pts.remove_at(selected_point)
		r.points = pts
		r.rebuild()
		selected_point = -1
		_set_status("Removed control point.")
		return
	var obj := selected
	_select(null)
	obj.get_parent().remove_child(obj)
	obj.queue_free()
	_set_status("Deleted.")


func _frame_clicked() -> void:
	var aabb := AABB()
	var first := true
	var targets := [selected] if selected else _all_objects()
	for o in targets:
		var pts: Array = Array(o.points) if o is RampNode else [o.position]
		for p in pts:
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if not first:
		for p in panes:
			p.frame(aabb.get_center(), max(aabb.size.length() * 0.5, 30.0))


func _edit_prop(key: String, value) -> void:
	if selected == null or _updating_ui:
		return
	_checkpoint("prop:%s:%d" % [key, _all_objects().find(selected)])
	if selected is RampNode:
		selected.set(key, value)
		selected.rebuild()
	else:
		var e := selected as EntityNode
		match key:
			"size_x": e.size.x = value
			"size_z": e.size.z = value
			"yaw": e.yaw = value
			"size_y": e.size.y = value
			"pitch": e.pitch = value
			"strength": e.strength = value
			"mode": e.mode = value
		e.rebuild()
	_refresh_info()


func _new_map_clicked() -> void:
	_checkpoint()
	_new_map()


func _open_clicked() -> void:
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.popup_centered_ratio(0.6)


func _save_clicked() -> void:
	if current_path == "":
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.popup_centered_ratio(0.6)
	else:
		save_map(current_path)


func _on_file_chosen(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		if not path.ends_with(".sfmap"):
			path += ".sfmap"
		save_map(path)
	else:
		load_map(path)


func save_map(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("Could not save %s" % path)
		return
	f.store_string(JSON.stringify(_map_dict(), "  "))
	f.close()
	current_path = path
	get_window().title = "SurfForge - " + path.get_file()
	_set_status("Saved %s" % path)


func load_map(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("format", "") != MAP_FORMAT:
		_set_status("%s is not a SurfForge map" % path.get_file())
		return
	_checkpoint()
	_load_dict(data)
	current_path = path
	get_window().title = "SurfForge - " + path.get_file()
	_frame_clicked()
	_set_status("Opened %s (%d ramps)" % [path.get_file(), ramps_root.get_child_count()])


# ================================================================================================= play mode
func _find_entity(kind: String) -> EntityNode:
	for e in entities_root.get_children():
		if e.kind == kind:
			return e
	return null


## Play from the start platform if there is one, otherwise from the selected (or first) ramp's start.
func _play_clicked() -> void:
	var start := _find_entity("start")
	var finish := _find_entity("finish")
	var at := Transform3D(Basis(), _view_center() + Vector3(0, 2, 0))
	if start:
		at = start.spawn_transform()
	else:
		var r: RampNode = selected if selected is RampNode else (ramps_root.get_child(0) if ramps_root.get_child_count() > 0 else null)
		if r and r.points.size() >= 2:
			var p0 := r.points[0]
			var t := r.points[1] - p0
			t.y = 0.0
			t = t.normalized()
			var side := Vector3.UP.cross(t).normalized()
			var out := 2.5
			var pos := p0 + t * 3.0 + side * out + Vector3(0, -out * r.height / (r.width * 0.5) + 0.3, 0)
			at = Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.z)), pos)
	_end_drag()
	if selected:
		selected.set_selected(false)
	_ui.visible = false
	var volumes := entities_root.get_children().filter(func(x): return x.is_volume())
	play.start(at, start.zone_aabb() if start else AABB(), finish.zone_aabb() if finish else AABB(),
		SurfsUpExporter.kill_floor_y(_map_dict()), volumes)


func _on_play_stopped() -> void:
	_ui.visible = true
	if selected:
		selected.set_selected(true)
	var t := " Best time: %s" % PlayMode.format_time(play.best_time) if play.best_time > 0.0 else ""
	_set_status("Back in the editor. Top speed %d u/s.%s" % [roundi(play.top_speed), t])


# ================================================================================================= export
func _build_export_dialog() -> void:
	_export_dialog = ConfirmationDialog.new()
	_export_dialog.title = "Export to SurfsUp"
	_export_dialog.ok_button_text = "Export"
	_export_dialog.min_size = Vector2i(560, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_export_dialog.add_child(box)
	var l1 := Label.new()
	l1.text = "Map name (letters, numbers, _ and - only). In SurfsUp, open the console (~) and type:  map <name>"
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l1)
	_export_name = LineEdit.new()
	box.add_child(_export_name)
	var l2 := Label.new()
	l2.text = "SurfsUp's Maps folder"
	box.add_child(l2)
	var row := HBoxContainer.new()
	box.add_child(row)
	_export_dir = LineEdit.new()
	_export_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_export_dir)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(func(): _dir_dialog.current_dir = _export_dir.text; _dir_dialog.popup_centered_ratio(0.6))
	row.add_child(browse)
	var note := Label.new()
	note.text = "If SurfsUp is running and you are replacing a map you already loaded, restart SurfsUp before loading it again."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	box.add_child(note)
	_export_dialog.confirmed.connect(_do_export)
	_ui.add_child(_export_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(d): _export_dir.text = d)
	_ui.add_child(_dir_dialog)


func _export_clicked() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var default_name := current_path.get_file().get_basename() if current_path != "" else "surf_mymap"
	_export_name.text = cfg.get_value("export", "name_" + current_path.md5_text(), default_name)
	_export_dir.text = cfg.get_value("export", "maps_dir", SurfsUpExporter.guess_maps_dir())
	_export_dialog.popup_centered()
	_export_name.grab_focus()


func _do_export() -> void:
	var map_name := _export_name.text.strip_edges()
	var dir := _export_dir.text.strip_edges()
	var err := SurfsUpExporter.export_pack(_map_dict(), map_name, dir)
	if err != "":
		var a := AcceptDialog.new()
		a.title = "Can't export yet"
		a.dialog_text = err
		_ui.add_child(a)
		a.popup_centered()
		_set_status("Export failed: " + err.get_slice("
", 0))
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("export", "maps_dir", dir)
	cfg.set_value("export", "name_" + current_path.md5_text(), map_name)
	cfg.save(SETTINGS_PATH)
	_set_status("Exported %s.pck to %s - in SurfsUp press ~ and type:  map %s" % [map_name, dir, map_name])
