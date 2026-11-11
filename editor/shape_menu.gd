class_name ShapeMenu
extends RefCounted
## Build mode's Geometry menu (F6): pick a shape, set its sizes in grid units, watch it in a small 3D preview, then
## place it in the map. Placing shows the shape as a ghost that follows where you look (snapped to the build grid),
## moves a cell at a time with right-drag, and is built by Enter or left as it was by Esc, which goes back to the menu.
## What it builds is plain CubeWorld cells - the same cubes every other build mode tool edits.

const ACCENT := Color(0.45, 0.72, 1.0)
const SETTLE := 0.15                            ## how long a value has to hold still before the exact shape is built
const LIVE_MS := 40.0                           ## an exact rebuild cheaper than this runs while a slider still moves

var host                                        ## BuildMode (not typed: build mode and this refer to each other)
var panel: PanelContainer
var _list: ItemList
var _params: VBoxContainer
var _detail: HSlider
var _detail_lbl: Label
var _info: Label
var _place: Button
var _shape := "box"
var _values := {}
var _rows := {}
var _updating := false
var _cells: Array = []
var _size := Vector3.ONE
var _cubes := 0
var _error := ""
var _detail_value := 2

var _preview_box: SubViewportContainer
var _view: SubViewport
var _cam: Camera3D
var _mesh_root: Node3D
var _yaw := -35.0
var _pitch := 22.0
var _zoom := 1.0
var _preview_drag := false

var _mesh_inst: MeshInstance3D
var _dirty := false                             ## a value changed and the shape has not caught up yet
var _cheap := false                             ## what is on screen is the quick preview, not the exact shape
var _quiet := 0.0                               ## seconds since the last change: the exact rebuild waits for it
var _since := 0.0                               ## seconds since the last rebuild: paces the quick ones
var _cost_ms := 0.0                             ## how long the last exact rebuild took
var _cheap_ms := 0.0                            ## how long the last quick rebuild took
var _task := -1                                 ## a rebuild running off the main thread (-1 when none)
var _task_result := {}                          ## what that rebuild produced, filled in by the thread
var _seq := 0                                   ## every rebuild gets a number, so an older result never wins
var _shown_seq := -1                            ## the rebuild number the mesh on screen came from

var _placing := false
var _ghost: Node3D
var _drag := false
var _drag_acc := Vector2.ZERO
var _move := Vector3i.ZERO
var _confirm: PanelContainer


func build(mode) -> void:
	host = mode
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	panel.custom_minimum_size = Vector2(620, 0)
	panel.visible = false
	panel.theme = UiTheme.shared()
	host._hud.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Geometry"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var say := Label.new()
	say.text = "sizes in grid units"
	say.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	say.add_theme_font_size_override("font_size", 12)
	head.add_child(say)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "Close (F6 opens it again)"
	close.pressed.connect(close_panel)
	head.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	box.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	left.add_child(UiTheme.header("Shape"))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(190, 300)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_shape_selected)
	left.add_child(_list)
	for s in ShapeGen.defs():
		_list.add_item(String(s["name"]))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_preview_box = SubViewportContainer.new()
	_preview_box.custom_minimum_size = Vector2(370, 210)
	_preview_box.stretch = true
	_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_box.gui_input.connect(_on_preview_input)
	_preview_box.tooltip_text = "Drag to turn it; the wheel zooms."
	right.add_child(_preview_box)
	_view = SubViewport.new()
	_view.size = Vector2i(370, 210)
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.msaa_3d = Viewport.MSAA_4X
	_preview_box.add_child(_view)
	_mesh_root = Node3D.new()
	_view.add_child(_mesh_root)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	_cam.far = 2000.0
	_mesh_root.add_child(_cam)
	_cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 32, 0)
	key.light_energy = 1.1
	_mesh_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -140, 0)
	fill.light_energy = 0.45
	_mesh_root.add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 0.6
	env.environment = e
	_mesh_root.add_child(env)

	_params = VBoxContainer.new()
	_params.add_theme_constant_override("separation", 3)
	right.add_child(_params)
	var detail_row := HBoxContainer.new()
	var dl := Label.new()
	dl.text = "Detail"
	dl.custom_minimum_size = Vector2(96, 0)
	detail_row.add_child(dl)
	_detail = HSlider.new()
	_detail.min_value = 0.0
	_detail.max_value = 4.0
	_detail.step = 1.0
	_detail.value = _detail_value
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_detail.tooltip_text = "How many levels finer than the grid the surface may be cut. More is rounder and more cubes."
	_detail.value_changed.connect(_on_detail)
	detail_row.add_child(_detail)
	_detail_lbl = Label.new()
	_detail_lbl.custom_minimum_size = Vector2(112, 0)
	_detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	detail_row.add_child(_detail_lbl)
	right.add_child(detail_row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(370, 34)
	_info.add_theme_font_size_override("font_size", 13)
	right.add_child(_info)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	_place = Button.new()
	_place.text = "Place in map"
	_place.tooltip_text = "Show it in the map as a ghost you can move, then press Enter to build it."
	_place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place.pressed.connect(start_placing)
	buttons.add_child(_place)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(close_panel)
	buttons.add_child(cancel)

	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", UiTheme.panel_box())
	_confirm.theme = UiTheme.shared()
	_confirm.visible = false
	host._hud.add_child(_confirm)
	var cl := Label.new()
	cl.text = "Enter: build it   ·   Esc: back to the shape menu   ·   right-drag: move it   ·   left mouse: turn the camera"
	cl.add_theme_font_size_override("font_size", 15)
	_confirm.add_child(cl)

	_values = ShapeGen.defaults(_shape)
	_list.select(0)
	for i in 6:
		CubeWorld.face_corners(i)                # (built here, so a rebuild on a thread only ever reads that table)
	_build_params()
	_regen()


# ------------------------------------------------------------------------------------------------ opening / closing
func is_open() -> bool:
	return panel != null and panel.visible


func is_placing() -> bool:
	return _placing


func open_panel() -> void:
	if _placing:
		return
	panel.visible = true
	host._ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cells.is_empty() or _cheap or _dirty:
		_ask_regen()
	layout(host.get_viewport().get_visible_rect().size)


func close_panel() -> void:
	if _placing:
		dismiss()
	panel.visible = false
	host._ui_closed()


## F6 again, E / Esc out of build mode, or play mode: leave nothing behind.
func dismiss() -> void:
	_poll()                                      # (take a finished rebuild so it does not land later)
	_clear_ghost()
	_placing = false
	_confirm.visible = false
	panel.visible = false


func layout(vp: Vector2) -> void:
	if panel.visible:
		panel.reset_size()
		panel.position = Vector2(maxf(20.0, vp.x * 0.5 - panel.size.x * 0.5),
			maxf(40.0, vp.y * 0.5 - panel.size.y * 0.5))
	if _confirm.visible:
		_confirm.reset_size()
		_confirm.position = Vector2(vp.x * 0.5 - _confirm.size.x * 0.5, vp.y - 96)


# ------------------------------------------------------------------------------------------------ parameters
func _on_shape_selected(i: int) -> void:
	var def: Dictionary = ShapeGen.defs()[i]
	_shape = String(def["id"])
	_values = ShapeGen.defaults(_shape)
	_build_params()
	if _mesh_inst != null:
		_mesh_inst.mesh = null                   # (the old shape goes at once; the new one lands when it is built)
	_ask_regen()


func _build_params() -> void:
	for c in _params.get_children():
		_params.remove_child(c)
		c.queue_free()
	_rows.clear()
	for p in ShapeGen.def_of(_shape)["params"]:
		var key := String(p[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := Label.new()
		l.text = String(p[1])
		l.custom_minimum_size = Vector2(96, 0)
		row.add_child(l)
		var sl := HSlider.new()
		sl.min_value = float(p[3])
		sl.max_value = float(p[4])
		sl.step = float(p[5])
		sl.value = float(_values.get(key, p[2]))
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sl)
		var num := DragNumber.new()
		num.per_pixel = float(p[5])
		num.custom_minimum_size = Vector2(76, 0)
		num.show_value(float(_values.get(key, p[2])))
		row.add_child(num)
		sl.value_changed.connect(func(v): _set_value(key, v, "slider"))
		num.typed.connect(func(v): _set_value(key, v, "number"))
		num.changed_by.connect(func(amount: float): _set_value(key, float(_values.get(key, p[2])) + amount, "drag"))
		_params.add_child(row)
		_rows[key] = {"slider": sl, "number": num, "def": p}


func _set_value(key: String, v: float, from: String) -> void:
	if _updating:
		return
	var p: Array = _rows[key]["def"]
	var value := clampf(v, float(p[3]), float(p[4]))
	if int(p[5]) == int(p[5]) and float(p[5]) >= 1.0:
		value = roundf(value)
	_values[key] = value
	_updating = true
	if from != "slider":
		(_rows[key]["slider"] as HSlider).value = value
	# (always, so a typed value shows the clamped / rounded number it really took, never the old one)
	(_rows[key]["number"] as DragNumber).show_value(value)
	_updating = false
	_ask_regen()


func _on_detail(v: float) -> void:
	if _updating:
		return
	_detail_value = int(v)
	_ask_regen()


## A value moved: rebuild when the frame allows it, never in the middle of the slider's own signal, so dragging a
## slider can't stack rebuilds up into a hitch.
func _ask_regen() -> void:
	_dirty = true
	_quiet = 0.0


## Build the shape now, on this thread. Used where the result has to be in hand: the first build, opening the menu,
## and placing, where the exact cells are what gets built - never for a value that is still moving.
func _regen(cheap := false) -> void:
	_seq += 1
	var t0 := Time.get_ticks_usec()
	var got := _build(_shape, _values, 0 if cheap else _detail_value, cheap)
	got["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	got["seq"] = _seq
	_apply(got)


## The heavy part: cells, then the preview's geometry as plain arrays. Touches nothing but its arguments and reads
## CubeWorld's shared tables, so a big shape can run on a worker thread while the sliders stay responsive.
func _build(shape: String, values: Dictionary, detail: int, cheap: bool) -> Dictionary:
	var res: Dictionary = ShapeGen.generate(shape, values, host.grid_p, detail)
	return {"res": res, "arrays": ShapeGen.preview_arrays(res["cells"]), "cheap": cheap}


## Put a built shape on screen. `cheap` is the moving preview: it skips the finer octree levels (a solid's shape is
## the same, only its surface is blockier), which is many times quicker, so a slider stays smooth; the exact shape
## follows as soon as the value holds still. Cheap passes leave the size / cube count text as the last exact pass
## left it.
func _apply(got: Dictionary) -> void:
	var seq := int(got.get("seq", -1))
	if seq <= _shown_seq:
		return                                   # (a newer shape is already on screen)
	_shown_seq = seq
	var res: Dictionary = got["res"]
	_cells = res["cells"]
	_size = res.get("size", Vector3.ONE)
	_error = String(res.get("error", ""))
	_place.disabled = _error != "" or _cells.is_empty()
	_dirty = bool(got["cheap"])
	_since = 0.0
	_cheap = bool(got["cheap"])
	_show_arrays(got["arrays"])
	if _cheap:
		_cheap_ms = float(got["ms"])
		return
	_cost_ms = float(got["ms"])
	_cubes = int(res.get("count", 0))
	var finest := float(res.get("finest", CubeWorld.metres(host.grid_p)))
	_detail_lbl.text = "%.3f m" % finest
	if _error != "":
		_info.text = _error
		_info.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
	else:
		_info.text = "%.2f × %.2f × %.2f m   ·   %s cubes   ·   finest %.3f m   ·   built on the %s grid" % [
			_size.x, _size.y, _size.z, _thousands(_cubes), finest, _metres_text(CubeWorld.metres(host.grid_p))]
		_info.add_theme_color_override("font_color", UiTheme.TEXT)


## Start a rebuild on a worker thread. Only one ever runs: a value that moves while it works is picked up by the
## build that follows, so heavy shapes can't pile up into a stall.
func _start(cheap: bool) -> void:
	_seq += 1
	var req := {"shape": _shape, "values": _values.duplicate(), "detail": 0 if cheap else _detail_value,
		"cheap": cheap, "seq": _seq}
	_dirty = cheap                             # (a cheap pass leaves the shape marked dirty: the exact one still comes)
	_since = 0.0
	_task = WorkerThreadPool.add_task(_work.bind(req), false, "geometry preview")


func _work(req: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var got := _build(String(req["shape"]), req["values"], int(req["detail"]), bool(req["cheap"]))
	got["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	got["seq"] = int(req["seq"])
	_task_result = got


## Take a finished rebuild, if there is one, without waiting for a running one.
func _poll() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var got: Dictionary = _task_result
	_task_result = {}
	if not got.is_empty():
		_apply(got)


## Build the exact shape now: placing needs the cells themselves, never a quick preview.
func settle() -> void:
	_regen(false)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


static func _metres_text(m: float) -> String:
	return ("%.3f m" % m).trim_suffix("0").trim_suffix("0").trim_suffix(".")


# ------------------------------------------------------------------------------------------------ 3D preview
func _show_arrays(arrays: Array) -> void:
	if _mesh_inst == null:
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.material_override = CubeWorld.material_for("")     # (the same look the chunk meshes gave)
		_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_root.add_child(_mesh_inst)
	_mesh_inst.mesh = null if (_cells.is_empty() or (arrays[0] as PackedVector3Array).is_empty()) else ShapeGen.mesh_of(arrays)
	_frame_preview()


func _frame_preview() -> void:
	if _cam == null:
		return
	var centre := _size * 0.5
	var dist := (_size.length() * 1.35 + 1.0) * _zoom
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	_cam.position = centre + Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y)) * dist
	_cam.look_at(centre, Vector3.UP)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_preview_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.88, 0.35, 3.0)
			_frame_preview()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.14, 0.35, 3.0)
			_frame_preview()
	elif event is InputEventMouseMotion and _preview_drag:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.4
		_pitch = clampf(_pitch + mm.relative.y * 0.3, -80.0, 80.0)
		_frame_preview()
	_preview_box.accept_event()


# ------------------------------------------------------------------------------------------------ placing
func start_placing() -> void:
	if _dirty or _cheap or _cells.is_empty():
		settle()                                 # (never place the quick preview: build the exact cells first)
	if _error != "" or _cells.is_empty():
		return
	panel.visible = false
	_placing = true
	_move = Vector3i.ZERO
	_drag = false
	_drag_acc = Vector2.ZERO
	_confirm.visible = true
	host._ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_build_ghost()
	layout(host.get_viewport().get_visible_rect().size)
	tick(0.0)
	host.say("Move it with right-drag, then Enter to build it. Esc goes back to the shapes.")


func _build_ghost() -> void:
	_clear_ghost()
	_ghost = Node3D.new()
	host.add_child(_ghost)
	var got := ShapeGen.preview_mesh(_cells)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.42)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = got[0]
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(mi)
	var edges: PackedVector3Array = got[1]
	if not edges.is_empty():
		var line := StandardMaterial3D.new()
		line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.albedo_color = Color(0.85, 0.93, 1.0, 0.85)
		var lm := ArrayMesh.new()
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = edges
		lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		var li := MeshInstance3D.new()
		li.mesh = lm
		li.material_override = line
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghost.add_child(li)


func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


func _anchor() -> Vector3:
	var g := CubeWorld.metres(host.grid_p)
	var at: Vector3
	if host.target.get("hit", false):
		at = host.target["point"]
	else:
		at = host.cam.global_position - host.cam.global_basis.z * g * 8.0
	var base := Vector3(floorf(at.x / g) * g, floorf(at.y / g) * g, floorf(at.z / g) * g)
	return base + Vector3(_move) * g


func tick(delta: float) -> void:
	_poll()                                      # (a rebuild from a worker thread lands here)
	if _dirty:
		_quiet += delta
		_since += delta
		if _task < 0:                            # (only one at a time: a new value is picked up by the next one)
			if _quiet >= SETTLE or _cost_ms <= LIVE_MS:
				if _cost_ms <= LIVE_MS:
					_regen(false)                # (cheap enough to just do it: no thread, no lag)
				else:
					_start(false)
			elif _since >= 0.10:
				_start(true)                     # (a cheap pass leaves _dirty set, so the exact one still comes)
	if not _placing or _ghost == null or not is_instance_valid(_ghost):
		return
	_ghost.position = _anchor()


func handle_input(event: InputEvent) -> bool:
	if _placing:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					confirm_place()
					return true
				KEY_ESCAPE:
					cancel_place()
					return true
		elif event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_drag = mb.pressed
				_drag_acc = Vector2.ZERO
				return true
		elif event is InputEventMouseMotion and _drag:
			_drag_acc += (event as InputEventMouseMotion).relative
			_apply_drag()
			return true
		return false
	if panel.visible and event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close_panel()
		return true
	return false


## Right-drag moves the ghost a cell at a time: left / right along the view's sideways axis, up / down on Y.
func _apply_drag() -> void:
	if not _placing:
		return
	var per := 26.0
	var sx := int(_drag_acc.x / per)
	var sy := int(_drag_acc.y / per)
	if sx == 0 and sy == 0:
		return
	_drag_acc -= Vector2(float(sx) * per, float(sy) * per)
	var right: Vector3 = host.cam.global_basis.x
	var step := Vector3i(0, -sy, 0)
	var a := right.abs()
	if a.x >= a.y and a.x >= a.z:
		step.x = signi(roundi(right.x)) * sx
	elif a.z >= a.y:
		step.z = signi(roundi(right.z)) * sx
	else:
		step.y = -sy
	_move += step


func confirm_place() -> void:
	if not _placing or _cells.is_empty():
		return
	var at := _ghost.position if _ghost != null and is_instance_valid(_ghost) else _anchor()
	var m := CubeModelNode.new()
	host.models.add_child(m)
	m.position = at
	var n := ShapeGen.place(m.world, _cells, Vector3i.ZERO, host.texture)
	m.set_meta("name", String(ShapeGen.def_of(_shape)["name"]))
	m.rebuild_all()
	host._push_history({"t": "new", "m": m})
	host._push_history({"t": "cubes", "m": m})
	host.model = m
	host.say("Placed %d cubes as one cube object: push, paint or shape them like any others." % n)
	dismiss()
	host._ui_closed()


func cancel_place() -> void:
	if not _placing:
		return
	_clear_ghost()
	_placing = false
	_confirm.visible = false
	open_panel()
	host.say("Back to the shapes.")
