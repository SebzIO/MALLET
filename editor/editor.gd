extends Node3D
## SurfForge main editor: viewport, ramp tools, properties panel, undo/redo and save/load.
##
## Mouse:   left-click a ramp to select it; drag its yellow handles to reshape it
##          (drag = move across the ground plane, Shift+drag = raise/lower);
##          double-click a selected ramp to add a bend point there.
##          Right-drag orbit, middle-drag pan, wheel zoom, right-drag + WASD/QE fly.
## Keys:    N new ramp, Delete remove point/ramp, Ctrl+D duplicate, F frame selection,
##          G toggle grid snap, Ctrl+Z / Ctrl+Y undo/redo, Ctrl+S save, Ctrl+O open.

const MAP_FORMAT := "surfforge-map"
const MAP_VERSION := 1
const HANDLE_PIXELS := 9.0          ## handle radius on screen
const PICK_PIXELS := 14.0

var camera: OrbitCamera
var ramps_root := Node3D.new()
var handles_root := Node3D.new()
var selected: RampNode = null
var selected_point := -1
var snap_enabled := true
var snap_step := 4.0
var current_path := ""

var _undo: Array = []
var _redo: Array = []
var _coalesce_key := ""
var _coalesce_time := 0.0
var _dragging := false
var _drag_plane := Plane()
var _drag_vertical := false
var _drag_start_point := Vector3.ZERO
var _handle_mat := StandardMaterial3D.new()
var _handle_sel_mat := StandardMaterial3D.new()
var _line_mesh := ImmediateMesh.new()

# UI
var _ui := CanvasLayer.new()
var _props: VBoxContainer
var _props_panel: PanelContainer
var _status: Label
var _info: Label
var _fields := {}
var _updating_ui := false
var _file_dialog: FileDialog
var play := PlayMode.new()


func _ready() -> void:
	_build_world()
	_build_ui()
	add_child(play)
	play.stopped.connect(_on_play_stopped)
	_new_map()
	get_window().title = "SurfForge"


# ------------------------------------------------------------------------------------------------- world
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
	add_child(grid)

	add_child(ramps_root)
	add_child(handles_root)
	var lines := MeshInstance3D.new()
	lines.mesh = _line_mesh
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.no_depth_test = true
	lm.vertex_color_use_as_albedo = true
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines.material_override = lm
	add_child(lines)

	for m in [_handle_mat, _handle_sel_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
	_handle_mat.albedo_color = Color(1.0, 0.85, 0.15)
	_handle_sel_mat.albedo_color = Color(1.0, 0.35, 0.1)

	camera = OrbitCamera.new()
	add_child(camera)
	camera.current = true


# ------------------------------------------------------------------------------------------------- ui
func _build_ui() -> void:
	add_child(_ui)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var bar_panel := PanelContainer.new()
	root.add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar_panel.add_child(bar)
	var title := Label.new()
	title.text = "  SurfForge  "
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	for spec in [["New Map", _new_map_clicked], ["Open…", _open_clicked], ["Save", _save_clicked], ["|", null],
			["+ Ramp", _add_ramp_clicked], ["Extend", _extend_clicked], ["Add Bend", _bend_clicked],
			["Duplicate", _duplicate_clicked], ["Delete", _delete_clicked], ["|", null],
			["Undo", undo], ["Redo", redo], ["Frame (F)", _frame_clicked], ["|", null], ["▶ Play (P)", _play_clicked]]:
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
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(middle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(spacer)
	_props_panel = PanelContainer.new()
	_props_panel.custom_minimum_size = Vector2(300, 0)
	middle.add_child(_props_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_props_panel.add_child(margin)
	_props = VBoxContainer.new()
	_props.add_theme_constant_override("separation", 8)
	margin.add_child(_props)
	_build_props()

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


func _build_props() -> void:
	var head := Label.new()
	head.text = "Ramp"
	head.add_theme_font_size_override("font_size", 20)
	_props.add_child(head)
	_fields["head"] = head
	_add_slider("width", "Width (m)", 4.0, 60.0, 0.5)
	_add_slider("height", "Height (m)", 2.0, 40.0, 0.25)
	_add_slider("detail", "Smoothness (segments / m)", 0.1, 4.0, 0.05)
	_add_slider("roll", "Tilt (°)", -45.0, 45.0, 1.0)
	var cl := Label.new()
	cl.text = "Colour"
	_props.add_child(cl)
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 28)
	cp.color_changed.connect(func(c): _edit_prop("color", c))
	_props.add_child(cp)
	_fields["color"] = cp
	_props.add_child(HSeparator.new())
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_props.add_child(_info)
	_props.add_child(HSeparator.new())
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	help.text = ("Drag yellow handles to shape the ramp.\nShift+drag raises/lowers a handle.\n"
		+ "Double-click the ramp to add a bend there.\nRight-drag orbit · middle-drag pan · wheel zoom\n"
		+ "Right-drag + WASD/QE to fly.\nN new ramp · Del delete · Ctrl+D duplicate\nCtrl+Z undo · Ctrl+S save · F frame · G snap")
	_props.add_child(help)


func _add_slider(key: String, label: String, lo: float, hi: float, step: float) -> void:
	var l := Label.new()
	l.text = label
	_props.add_child(l)
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.focus_mode = Control.FOCUS_NONE
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v): if not _updating_ui: box.set_value_no_signal(v); _edit_prop(key, v))
	box.value_changed.connect(func(v): if not _updating_ui: s.set_value_no_signal(v); _edit_prop(key, v))
	row.add_child(s)
	row.add_child(box)
	_props.add_child(row)
	_fields[key] = [s, box]


func _refresh_props() -> void:
	_props_panel.visible = selected != null
	if selected == null:
		return
	_updating_ui = true
	for key in ["width", "height", "detail", "roll"]:
		var v: float = selected.get(key)
		_fields[key][0].value = v
		_fields[key][1].value = v
	_fields["color"].color = selected.color
	_updating_ui = false
	_refresh_info()


func _refresh_info() -> void:
	if selected == null:
		return
	var face_angle := rad_to_deg(atan2(selected.height, selected.width * 0.5))
	var surfable := "surfable" if face_angle > 45.6 else "too flat: players will stand on it"
	var drop := selected.points[0].y - selected.points[selected.points.size() - 1].y
	_info.text = ("Length: %.0f m\nDrop: %.0f m\nFace angle: %.1f° (%s)\nControl points: %d\nTriangles: %d"
		% [selected.length, drop, face_angle, surfable, selected.points.size(), selected.triangle_count])


func _set_status(t: String) -> void:
	_status.text = "  " + t


# ------------------------------------------------------------------------------------------------- map data
func _map_dict() -> Dictionary:
	var rs := []
	for r in ramps_root.get_children():
		rs.append(r.to_dict())
	return {"format": MAP_FORMAT, "version": MAP_VERSION, "ramps": rs}


func _load_dict(data: Dictionary) -> void:
	for r in ramps_root.get_children():
		ramps_root.remove_child(r)
		r.queue_free()
	_select(null)
	for rd in data.get("ramps", []):
		var r := RampNode.new()
		ramps_root.add_child(r)
		r.from_dict(rd)


func _new_map() -> void:
	_load_dict({"ramps": []})
	_undo.clear()
	_redo.clear()
	current_path = ""
	var r := _make_ramp(Vector3(-60, 120, 0), Vector3(60, 90, 0))
	_select(r)
	camera.frame(Vector3(0, 100, 0), 90)
	_set_status("New map. Drag the yellow handles to shape your first ramp.")


func _make_ramp(a: Vector3, b: Vector3) -> RampNode:
	var r := RampNode.new()
	r.points = PackedVector3Array([a, a.lerp(b, 0.5), b])
	ramps_root.add_child(r)
	return r


# ------------------------------------------------------------------------------------------------- undo / redo
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
	var sel := selected.get_index() if selected else -1
	return {"map": _map_dict(), "sel": sel, "pt": selected_point}


func _restore(s: Dictionary) -> void:
	_load_dict(s["map"])
	var sel: int = s["sel"]
	if sel >= 0 and sel < ramps_root.get_child_count():
		_select(ramps_root.get_child(sel), s["pt"])


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


# ------------------------------------------------------------------------------------------------- selection + handles
func _select(r: RampNode, point := -1) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
		if selected.changed.is_connected(_on_ramp_changed):
			selected.changed.disconnect(_on_ramp_changed)
	selected = r
	selected_point = point
	if selected:
		selected.set_selected(true)
		selected.changed.connect(_on_ramp_changed)
	_rebuild_handles()
	_refresh_props()


func _on_ramp_changed() -> void:
	_refresh_info()


func _rebuild_handles() -> void:
	for h in handles_root.get_children():
		h.queue_free()
	if selected == null:
		return
	for i in selected.points.size():
		var h := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		h.mesh = sm
		h.material_override = _handle_sel_mat if i == selected_point else _handle_mat
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		handles_root.add_child(h)
	_update_handles()


func _update_handles() -> void:
	_line_mesh.clear_surfaces()
	if selected == null:
		return
	var pts := selected.points
	var hs := handles_root.get_children()
	for i in min(hs.size(), pts.size()):
		var h: MeshInstance3D = hs[i]
		h.global_position = pts[i]
		var dist := camera.global_position.distance_to(pts[i])
		var world_per_px := 2.0 * dist * tan(deg_to_rad(camera.fov * 0.5)) / get_viewport().get_visible_rect().size.y
		h.scale = Vector3.ONE * HANDLE_PIXELS * world_per_px
		h.material_override = _handle_sel_mat if i == selected_point else _handle_mat
	# dashed drop lines from each handle to the ground: makes heights readable
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in pts:
		_line_mesh.surface_set_color(Color(1, 0.85, 0.15, 0.55))
		_line_mesh.surface_add_vertex(p)
		_line_mesh.surface_set_color(Color(1, 0.85, 0.15, 0.1))
		_line_mesh.surface_add_vertex(Vector3(p.x, 0, p.z))
	_line_mesh.surface_end()


func _process(_delta: float) -> void:
	if not play.active:
		_update_handles()


# ------------------------------------------------------------------------------------------------- viewport input
func _unhandled_input(event: InputEvent) -> void:
	if play.handle_input(event):
		return
	if camera.handle_input(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click and selected:
				_insert_point_at_mouse(event.position)
				return
			var hp := _pick_handle(event.position)
			if hp >= 0:
				_begin_drag(hp, event.position, event.shift_pressed)
				return
			var r := _pick_ramp(event.position)
			_select(r)
			_set_status("Selected ramp" if r else "")
		elif _dragging:
			_dragging = false
			_set_status("Moved point %d to (%.0f, %.0f, %.0f)" % [selected_point, selected.points[selected_point].x,
				selected.points[selected_point].y, selected.points[selected_point].z])
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.position, event.shift_pressed)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_Z when ctrl:
			if e.shift_pressed: redo()
			else: undo()
		KEY_Y when ctrl: redo()
		KEY_S when ctrl: _save_clicked()
		KEY_O when ctrl: _open_clicked()
		KEY_D when ctrl: _duplicate_clicked()
		KEY_N: _add_ramp_clicked()
		KEY_P: _play_clicked()
		KEY_DELETE, KEY_BACKSPACE: _delete_clicked()
		KEY_F: _frame_clicked()
		KEY_G:
			snap_enabled = not snap_enabled
			_fields["snap_button"].button_pressed = snap_enabled


func _pick_handle(mouse: Vector2) -> int:
	if selected == null:
		return -1
	var best := -1
	var best_d := PICK_PIXELS
	for i in selected.points.size():
		var p := selected.points[i]
		if camera.is_position_behind(p):
			continue
		var d := camera.unproject_position(p).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best


func _pick_ramp(mouse: Vector2) -> RampNode:
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 10000.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit and hit.collider.has_meta("ramp"):
		return hit.collider.get_meta("ramp")
	return null


func _begin_drag(i: int, mouse: Vector2, vertical: bool) -> void:
	_checkpoint()
	selected_point = i
	_dragging = true
	_drag_start_point = selected.points[i]
	_setup_drag_plane(vertical)
	_set_status("Dragging point %d  (hold Shift to raise/lower)" % i)


func _setup_drag_plane(vertical: bool) -> void:
	_drag_vertical = vertical
	var p := selected.points[selected_point]
	if vertical:
		var n := camera.global_basis.z
		n.y = 0.0
		if n.length() < 1e-3:
			n = Vector3.FORWARD
		_drag_plane = Plane(n.normalized(), p)
	else:
		_drag_plane = Plane(Vector3.UP, p)


func _drag_to(mouse: Vector2, vertical: bool) -> void:
	if vertical != _drag_vertical:
		_setup_drag_plane(vertical)                    # switch mode mid-drag without jumping
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var hit = _drag_plane.intersects_ray(from, dir)
	if hit == null:
		return
	var p := selected.points[selected_point]
	if _drag_vertical:
		p.y = hit.y
	else:
		p.x = hit.x
		p.z = hit.z
	if snap_enabled:
		if _drag_vertical:
			p.y = snappedf(p.y, snap_step)
		else:
			p.x = snappedf(p.x, snap_step)
			p.z = snappedf(p.z, snap_step)
	var pts := selected.points
	pts[selected_point] = p
	selected.points = pts
	selected.rebuild()
	_set_status("Point %d: (%.0f, %.0f, %.0f)%s" % [selected_point, p.x, p.y, p.z, "  [height]" if _drag_vertical else ""])


## Double-click on the selected ramp: add a control point on the path where you clicked.
func _insert_point_at_mouse(mouse: Vector2) -> void:
	var r := _pick_ramp(mouse)
	if r != selected:
		return
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 10000.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if not hit:
		return
	# find the point on the curved ridge nearest the click, and which span between control points it is in
	var pts := selected.points
	var best := RampShape.nearest_on_path(pts, hit.position)
	_checkpoint()
	var best_i: int = best["span"]
	pts.insert(best_i + 1, best["point"])
	selected.points = pts
	selected.rebuild()
	selected_point = best_i + 1
	_rebuild_handles()
	_refresh_info()
	_set_status("Added a bend point. Drag it to curve the ramp.")


# ------------------------------------------------------------------------------------------------- toolbar actions
func _add_ramp_clicked() -> void:
	_checkpoint()
	var fwd := -camera.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP).normalized()
	var c := camera.focus
	c.y = max(c.y, 40.0)
	var a := c - right * 60 + Vector3(0, 15, 0)
	var b := c + right * 60 - Vector3(0, 15, 0)
	if snap_enabled:
		a = a.snapped(Vector3.ONE * snap_step)
		b = b.snapped(Vector3.ONE * snap_step)
	var r := _make_ramp(a, b)
	_select(r)
	_set_status("New ramp added at the view centre.")


func _extend_clicked() -> void:
	if selected == null:
		return
	_checkpoint()
	var pts := selected.points
	var n := pts.size()
	var dir := (pts[n - 1] - pts[n - 2])
	pts.append(pts[n - 1] + dir.normalized() * max(dir.length(), 30.0))
	selected.points = pts
	selected.rebuild()
	selected_point = pts.size() - 1
	_rebuild_handles()
	_set_status("Ramp extended. Drag the new end point.")


func _bend_clicked() -> void:
	if selected == null:
		return
	_checkpoint()
	var pts := selected.points
	var i: int = clamp(selected_point if selected_point >= 0 else 0, 0, pts.size() - 2)
	pts.insert(i + 1, pts[i].lerp(pts[i + 1], 0.5))
	selected.points = pts
	selected.rebuild()
	selected_point = i + 1
	_rebuild_handles()
	_set_status("Bend point added between points %d and %d." % [i, i + 2])


func _duplicate_clicked() -> void:
	if selected == null:
		return
	_checkpoint()
	var d := selected.to_dict()
	var r := RampNode.new()
	ramps_root.add_child(r)
	r.from_dict(d)
	var pts := r.points
	for i in pts.size():
		pts[i] += Vector3(0, -30, 40)
	r.points = pts
	r.rebuild()
	_select(r)
	_set_status("Duplicated ramp (moved 30 m down, 40 m over).")


func _delete_clicked() -> void:
	if selected == null:
		return
	_checkpoint()
	if selected_point >= 0 and selected.points.size() > 2:
		var pts := selected.points
		pts.remove_at(selected_point)
		selected.points = pts
		selected.rebuild()
		selected_point = -1
		_rebuild_handles()
		_set_status("Removed control point.")
	else:
		var r := selected
		_select(null)
		ramps_root.remove_child(r)
		r.queue_free()
		_set_status("Deleted ramp.")


func _frame_clicked() -> void:
	var aabb := AABB()
	var first := true
	var targets := [selected] if selected else ramps_root.get_children()
	for r in targets:
		for p in r.points:
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	if not first:
		camera.frame(aabb.get_center(), max(aabb.size.length() * 0.5, 30.0))


func _edit_prop(key: String, value) -> void:
	if selected == null or _updating_ui:
		return
	_checkpoint("prop:%s:%d" % [key, selected.get_index()])
	selected.set(key, value)
	selected.rebuild()


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
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY or data.get("format", "") != MAP_FORMAT:
		_set_status("%s is not a SurfForge map" % path.get_file())
		return
	_checkpoint()
	_load_dict(data)
	current_path = path
	get_window().title = "SurfForge - " + path.get_file()
	_frame_clicked()
	_set_status("Opened %s (%d ramps)" % [path.get_file(), ramps_root.get_child_count()])


# ------------------------------------------------------------------------------------------------- play mode
## Play from the selected ramp's start (on its face, facing down it), or from the view centre if none is selected.
func _play_clicked() -> void:
	var at := Transform3D(Basis(Vector3.UP, camera.yaw + PI), camera.focus + Vector3(0, 2, 0))
	var r: RampNode = selected if selected else (ramps_root.get_child(0) if ramps_root.get_child_count() > 0 else null)
	if r and r.points.size() >= 2:
		var p0 := r.points[0]
		var t := r.points[1] - p0
		t.y = 0.0
		t = t.normalized()
		var side := Vector3.UP.cross(t).normalized()
		var out := 2.5                                   # metres out from the ridge, on one face
		var face_drop := out * r.height / (r.width * 0.5)
		var pos := p0 + t * 3.0 + side * out + Vector3(0, -face_drop + 0.3, 0)
		at = Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.z)), pos)
	_dragging = false
	if selected:
		selected.set_selected(false)
	_ui.visible = false
	handles_root.visible = false
	_line_mesh.clear_surfaces()
	play.start(at)


func _on_play_stopped() -> void:
	camera.current = true
	_ui.visible = true
	handles_root.visible = true
	if selected:
		selected.set_selected(true)
	_set_status("Back in the editor. Top speed that run: %d u/s" % roundi(play.top_speed))
