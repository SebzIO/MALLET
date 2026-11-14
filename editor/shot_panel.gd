class_name ShotPanel
extends PanelContainer
## Camera shots (0.30.0): the strip under the views (View > Camera shots). A map can have several named shots, each
## a list of camera keys; the camera glides through them on a smooth path (CameraPath). Keys are added from the 3D
## view's camera, fine-tuned in the number fields, and dragged in every view. Play and the time bar preview the shot
## in the 3D view; Render video... makes it a video file (RenderDialog). Shots are saved with the map (key "shots") and
## never exported.

const KEY_COLOR := Color(0.95, 0.95, 1.0, 0.85)
const SEL_COLOR := Color(1.0, 0.55, 0.15)
const PATH_COLOR := Color(0.35, 0.85, 1.0, 0.9)
const HEAD_COLOR := Color(1.0, 0.3, 0.75)
const PICK_PX := 11.0

var ed: Node                                 ## the editor
var cur := -1                                ## the shot being edited (index into ed.shots)
var key := -1                                ## its selected key
var time := 0.0                              ## the time bar's position (seconds into the shot)
var playing := false
var looking := false                         ## the 3D view shows the shot (scrubbing, playing, looking through a key)
var aspect := 16.0 / 9.0                     ## the render's shape: the frame drawn in the 3D view
var _path: CameraPath = null
var _updating := false
var _drag_pane: ViewPane = null
var _drag_what := ""                         ## "key" or "look"
var _drag_plane := Plane()
var _drag_axes := Vector3.ONE
var _drag_from := Vector3.ZERO
var _drag_hit := Vector3.ZERO
var _shown := Transform3D()                  ## where the preview last put the 3D camera (moved since = not looking)

var _shot_list: OptionButton
var _name_edit: LineEdit
var _keys: ItemList
var _scrub: HSlider
var _ticks: Control
var _time_label: Label
var _play_button: Button
var _f := {}                                 ## key fields and shot fields by name
var _key_box: Control
var _shot_box: Control
var _look_point_row: Control
var _look_object_row: Control
var _look_object_label: Label

signal render_requested
signal close_requested


func setup(editor: Node) -> void:
	ed = editor


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG, UiTheme.BORDER, 1, 0, 8))
	var sz := String(Settings.value("render_size")).split("x")
	if sz.size() == 2 and int(sz[1]) > 0:
		aspect = float(sz[0]) / float(sz[1])          # (the frame in the 3D view: the last render's shape)
	custom_minimum_size = Vector2(0, 236)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	# --- the top row: which shot, the time bar, play, render
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	var title := Label.new()
	title.text = "Camera shots"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	top.add_child(title)
	_shot_list = OptionButton.new()
	_shot_list.custom_minimum_size = Vector2(150, 0)
	_shot_list.focus_mode = Control.FOCUS_NONE
	_shot_list.tooltip_text = "The shot you are editing. Each shot renders as its own video."
	_shot_list.item_selected.connect(func(i: int): _pick_shot(i))
	top.add_child(_shot_list)
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(130, 0)
	_name_edit.placeholder_text = "Shot name"
	_name_edit.tooltip_text = "The shot's name (also the video's file name)"
	_name_edit.text_submitted.connect(func(_t: String): _rename())
	_name_edit.focus_exited.connect(_rename)
	top.add_child(_name_edit)
	_button(top, "New shot", new_shot, "A new, empty shot. Then fly the 3D view to where it starts and press Add key here.")
	_button(top, "Copy", _copy_shot, "A copy of this shot, to try a variation")
	_button(top, "Delete shot", _delete_shot, "Delete this shot (Undo brings it back)")
	top.add_child(VSeparator.new())
	_button(top, "|◀", func(): stop(); scrub_to(0.0), "Back to the start of the shot")
	_play_button = _button(top, "▶ Play", toggle_play, "Play the shot in the 3D view (Esc stops)")
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(110, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_time_label)
	var scrub_box := VBoxContainer.new()
	scrub_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_box.add_theme_constant_override("separation", 0)
	top.add_child(scrub_box)
	_ticks = Control.new()
	_ticks.custom_minimum_size = Vector2(0, 10)
	_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticks.draw.connect(_draw_ticks)
	scrub_box.add_child(_ticks)
	_scrub = HSlider.new()
	_scrub.step = 0.001
	_scrub.focus_mode = Control.FOCUS_NONE
	_scrub.tooltip_text = "Drag through the shot: the 3D view shows it. The marks above are the keys."
	_scrub.value_changed.connect(func(v: float):
		if not _updating:
			playing = false
			scrub_to(v))
	scrub_box.add_child(_scrub)
	top.add_child(VSeparator.new())
	_button(top, "Render video…", func(): render_requested.emit(), "Make a video file of your shots")
	_button(top, "×", func(): close_requested.emit(), "Close the strip (View > Camera shots brings it back). Shots stay with the map.")
	# --- below: keys | the selected key | the shot's settings
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	col.add_child(row)
	var keys_col := VBoxContainer.new()
	keys_col.custom_minimum_size = Vector2(250, 0)
	row.add_child(keys_col)
	var kb := HBoxContainer.new()
	keys_col.add_child(kb)
	_button(kb, "+ Add key here", add_key_here, "A key where the 3D view's camera is now (position, angle, field of view), after the selected key")
	_button(kb, "Set from view", set_key_from_view, "Move the selected key to where the 3D view's camera is now")
	var kb2 := HBoxContainer.new()
	keys_col.add_child(kb2)
	_button(kb2, "Look through", look_through, "Show the 3D view from the selected key")
	_button(kb2, "▲", func(): move_key(-1), "Move the key earlier in the shot")
	_button(kb2, "▼", func(): move_key(1), "Move the key later in the shot")
	_button(kb2, "Delete", delete_key, "Delete the selected key")
	_keys = ItemList.new()
	_keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_keys.focus_mode = Control.FOCUS_NONE
	_keys.item_selected.connect(func(i: int): select_key(i, true))
	keys_col.add_child(_keys)
	row.add_child(VSeparator.new())
	_key_box = _key_fields()
	row.add_child(_key_box)
	row.add_child(VSeparator.new())
	_shot_box = _shot_fields()
	row.add_child(_shot_box)
	refresh()


func _button(parent: Container, text: String, action: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _number(grid: Container, label: String, field: String, per_px: float, tip: String) -> DragNumber:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	var dn := DragNumber.new()
	dn.per_pixel = per_px
	dn.custom_minimum_size = Vector2(78, 0)
	dn.tooltip_text = tip + "\nDrag left / right (Shift: fine, Ctrl: fast), or click to type."
	grid.add_child(dn)
	_f[field] = dn
	return dn


func _key_fields() -> Control:
	var box := VBoxContainer.new()
	box.add_child(UiTheme.header("Selected key"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	box.add_child(grid)
	var specs := [["X", "x", 0.05, "Position, meters"], ["Y", "y", 0.05, "Height, meters"], ["Z", "z", 0.05, "Position, meters"],
		["Yaw", "yaw", 0.2, "Turn left / right, degrees"], ["Pitch", "pitch", 0.2, "Look up (+) / down (-), degrees"],
		["Roll", "roll", 0.2, "Tilt the picture, degrees (0 = level)"],
		["FOV", "fov", 0.1, "Field of view, degrees (top to bottom): smaller zooms in"],
		["Time", "dur", 0.01, "Seconds from this key to the next (timed shots)"],
		["Ease in", "ease_in", 0.005, "Slow down arriving at this key: 0 = no, 1 = come to a stop"],
		["Ease out", "ease_out", 0.005, "Start slowly leaving this key: 0 = no, 1 = from a stop"]]
	for s in specs:
		var dn := _number(grid, s[0], s[1], s[2], s[3])
		var field: String = s[1]
		dn.drag_started.connect(func(): ed._checkpoint())
		dn.changed_by.connect(func(a: float): _key_add(field, a))
		dn.typed.connect(func(v: float): ed._checkpoint(); _key_set(field, v))
	return box


func _shot_fields() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UiTheme.header("This shot"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	box.add_child(grid)
	var tl := Label.new()
	tl.text = "Speed"
	grid.add_child(tl)
	var timing := OptionButton.new()
	timing.add_item("Timed keys (each key's Time)")
	timing.add_item("Even speed (the whole shot)")
	timing.focus_mode = Control.FOCUS_NONE
	timing.tooltip_text = "Timed keys: each key says how long to the next one.\nEven speed: the camera keeps one speed all the way and the shot lasts Length (ease still slows it at a key)."
	timing.item_selected.connect(func(i: int): _shot_set("timing", ["timed", "even"][i]))
	grid.add_child(timing)
	_f["timing"] = timing
	var len_n := _number(grid, "Length (s)", "length", 0.02, "How long the whole shot lasts (Even speed)")
	len_n.drag_started.connect(func(): ed._checkpoint())
	len_n.changed_by.connect(func(a: float): _shot_set("length", maxf(float(shot().get("length", 10.0)) + a, 0.1), false))
	len_n.typed.connect(func(v: float): _shot_set("length", maxf(v, 0.1)))
	var cl := Label.new()
	cl.text = "Curve"
	grid.add_child(cl)
	var curve := HSlider.new()
	curve.min_value = 0.0
	curve.max_value = 1.0
	curve.step = 0.01
	curve.focus_mode = Control.FOCUS_NONE
	curve.custom_minimum_size = Vector2(150, 0)
	curve.tooltip_text = "Left: a smooth curve through the keys. Right: straight lines from key to key."
	curve.drag_started.connect(func(): ed._checkpoint("shot_tension"))
	curve.value_changed.connect(func(v: float):
		if not _updating:
			ed._checkpoint("shot_tension")
			_shot_set("tension", v, false))
	grid.add_child(curve)
	_f["tension"] = curve
	var ll := Label.new()
	ll.text = "Look at"
	grid.add_child(ll)
	var look := OptionButton.new()
	look.add_item("Where each key looks")
	look.add_item("A point (drag it in the views)")
	look.add_item("An object")
	look.focus_mode = Control.FOCUS_NONE
	look.tooltip_text = "Keep the camera turned toward a point or an object the whole shot (keys then only set position, roll and FOV)."
	look.item_selected.connect(func(i: int): _set_look(["none", "point", "object"][i]))
	grid.add_child(look)
	_f["look"] = look
	var pr := HBoxContainer.new()
	box.add_child(pr)
	for a in 3:
		var l := Label.new()
		l.text = ["X", "Y", "Z"][a]
		pr.add_child(l)
		var dn := DragNumber.new()
		dn.per_pixel = 0.05
		dn.custom_minimum_size = Vector2(70, 0)
		dn.tooltip_text = "Where the camera looks (meters). You can also drag the pink cross in the views."
		dn.drag_started.connect(func(): ed._checkpoint())
		dn.changed_by.connect(func(d: float): _look_add(a, d))
		dn.typed.connect(func(v: float): ed._checkpoint(); _look_add(a, v - _look_point()[a]))
		pr.add_child(dn)
		_f["look_" + str(a)] = dn
	var here := _button(pr, "To view center", _look_at_view_center, "Put the point where the 3D view is looking")
	here.tooltip_text += " (the middle of the 3D view, on the first thing it hits)"
	_look_point_row = pr
	var orow := HBoxContainer.new()
	box.add_child(orow)
	_look_object_label = Label.new()
	_look_object_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_look_object_label.clip_text = true
	orow.add_child(_look_object_label)
	_button(orow, "Use the selected object", _look_at_selected, "Follow the object selected in the views (by its name in the Outliner)")
	_look_object_row = orow
	return box


# ================================================================================================= data
func shots() -> Array:
	return ed.shots


func shot() -> Dictionary:
	return ed.shots[cur] if cur >= 0 and cur < ed.shots.size() else {}


func shot_keys() -> Array:
	return shot().get("keys", [])


## The current shot's path (rebuilt after any change).
func path() -> CameraPath:
	if _path == null:
		_path = path_of(shot(), ed)
	return _path


## A shot's path, with its look-at target found in the map (an object by its Outliner name).
static func path_of(s: Dictionary, editor: Node) -> CameraPath:
	return CameraPath.new(s, look_target(s, editor))


static func look_target(s: Dictionary, editor: Node):
	match String(s.get("look", "none")):
		"point":
			var p: Array = s.get("look_point", [0, 0, 0])
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
		"object":
			var want := String(s.get("look_object", ""))
			if want != "" and editor != null:
				for o in editor._all_objects():
					if editor.outliner.name_of(o) == want and o.has_method("center"):
						return o.center()
	return null


## Called after anything changed the shots (an edit here, undo, a co-editor, a map opened): show them again.
func refresh() -> void:
	if _shot_list == null:
		return
	_path = null
	if cur >= ed.shots.size():
		cur = ed.shots.size() - 1
	if cur < 0 and not ed.shots.is_empty():
		cur = 0
	var ks := shot_keys()
	key = clampi(key, -1, ks.size() - 1)
	if key < 0 and not ks.is_empty():
		key = 0
	_updating = true
	_shot_list.clear()
	for s in ed.shots:
		_shot_list.add_item(String(s.get("name", "Shot")))
	if ed.shots.is_empty():
		_shot_list.add_item("(no shots yet)")
		_shot_list.disabled = true
	else:
		_shot_list.disabled = false
		_shot_list.select(cur)
	if not _name_edit.has_focus():
		_name_edit.text = String(shot().get("name", ""))
	_name_edit.editable = cur >= 0
	_keys.clear()
	var p := path()
	for i in ks.size():
		var k: Dictionary = ks[i]
		_keys.add_item("Key %d   at %.2f s   FOV %.0f" % [i + 1, p.key_time(i), float(k.get("fov", 70.0))])
	if key >= 0:
		_keys.select(key)
		_keys.ensure_current_is_visible()
	_refresh_fields()
	_updating = false


func _refresh_fields() -> void:
	_updating = true
	var ks := shot_keys()
	var k: Dictionary = ks[key] if key >= 0 and key < ks.size() else {}
	for field in ["x", "y", "z", "yaw", "pitch", "roll", "fov", "dur", "ease_in", "ease_out"]:
		var dn: DragNumber = _f[field]
		(dn.get_parent().get_child(dn.get_index() - 1) as Control).modulate.a = 1.0 if not k.is_empty() else 0.4
		dn.modulate.a = 1.0 if not k.is_empty() else 0.4
		if k.is_empty():
			dn.show_value(0.0)
		elif field in ["x", "y", "z"]:
			dn.show_value(CameraPath.key_pos(k)["xyz".find(field)])
		else:
			dn.show_value(float(k.get(field, 0.0)))
	var even := String(shot().get("timing", "timed")) == "even"
	(_f["dur"] as DragNumber).modulate.a = 0.4 if even or key == ks.size() - 1 else (_f["dur"] as DragNumber).modulate.a
	var s := shot()
	_shot_box.modulate.a = 1.0 if not s.is_empty() else 0.4
	(_f["timing"] as OptionButton).select(1 if even else 0)
	(_f["length"] as DragNumber).show_value(float(s.get("length", 10.0)))
	(_f["length"] as DragNumber).modulate.a = 1.0 if even else 0.4
	(_f["tension"] as HSlider).value = float(s.get("tension", 0.0))
	var look := String(s.get("look", "none"))
	(_f["look"] as OptionButton).select(["none", "point", "object"].find(look) if look in ["none", "point", "object"] else 0)
	_look_point_row.visible = look == "point"
	_look_object_row.visible = look == "object"
	var lp := _look_point()
	for a in 3:
		(_f["look_" + str(a)] as DragNumber).show_value(lp[a])
	var on := String(s.get("look_object", ""))
	_look_object_label.text = ("Following: " + on) if on != "" else "Select an object, then:"
	var d := path().duration()
	_scrub.max_value = maxf(d, 0.001)
	time = clampf(time, 0.0, d)
	_scrub.set_value_no_signal(time)
	_time_label.text = "%.2f / %.2f s" % [time, d]
	_ticks.queue_redraw()
	_updating = false


## Something about the shots changed here: forget the path, tell co-editors, show it.
func _changed(full := false) -> void:
	_path = null
	ed._map_changed()
	if full:
		refresh()
	else:
		_refresh_fields()
		var ks := shot_keys()
		var p := path()
		for i in mini(ks.size(), _keys.item_count):
			_keys.set_item_text(i, "Key %d   at %.2f s   FOV %.0f" % [i + 1, p.key_time(i), float((ks[i] as Dictionary).get("fov", 70.0))])
	if looking and not playing:
		_show_time()
	ed._redraw_overlays()


func _key_add(field: String, amount: float) -> void:
	var ks := shot_keys()
	if key < 0 or key >= ks.size():
		return
	var k: Dictionary = ks[key]
	if field in ["x", "y", "z"]:
		var i := "xyz".find(field)
		var p: Array = k["pos"]
		p[i] = snappedf(float(p[i]) + amount, 0.0001)
	else:
		_key_set(field, float(k.get(field, 0.0)) + amount, false)
		return
	_changed()


func _key_set(field: String, v: float, _undo_done := true) -> void:
	var ks := shot_keys()
	if key < 0 or key >= ks.size():
		return
	var k: Dictionary = ks[key]
	match field:
		"x", "y", "z":
			(k["pos"] as Array)[ "xyz".find(field)] = v
		"fov": k["fov"] = clampf(v, 5.0, 150.0)
		"dur": k["dur"] = maxf(v, 0.05)
		"ease_in", "ease_out": k[field] = clampf(v, 0.0, 1.0)
		_: k[field] = v
	_changed()


func _shot_set(field: String, v, checkpoint := true) -> void:
	if shot().is_empty():
		return
	if checkpoint:
		ed._checkpoint()
	shot()[field] = v
	_changed()


func _look_point() -> Vector3:
	var p: Array = shot().get("look_point", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _look_add(axis: int, amount: float) -> void:
	if shot().is_empty():
		return
	var p := _look_point()
	p[axis] += amount
	shot()["look_point"] = [snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)]
	_changed()


func _set_look(mode: String) -> void:
	if shot().is_empty() or _updating:
		return
	ed._checkpoint()
	var s := shot()
	s["look"] = mode
	if mode == "point" and _look_point() == Vector3.ZERO:
		var c := _view_center()
		s["look_point"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]
	if mode == "object" and String(s.get("look_object", "")) == "" and ed.selected != null:
		s["look_object"] = ed.outliner.name_of(ed.selected)
	_changed()


func _view_center() -> Vector3:
	var cam: Camera3D = ed.panes[0].camera
	var from := cam.global_position
	var to := from - cam.global_basis.z * 4000.0
	var hit: Dictionary = (ed as Node3D).get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if not hit.is_empty():
		return hit["position"]
	return (cam as OrbitCamera).focus if cam is OrbitCamera else from - cam.global_basis.z * 50.0


func _look_at_view_center() -> void:
	if shot().is_empty():
		return
	ed._checkpoint()
	var c := _view_center()
	shot()["look_point"] = [snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]
	_changed()


func _look_at_selected() -> void:
	if shot().is_empty():
		return
	if ed.selected == null:
		ed._set_status("Select the object to follow first (click it in a view or in the Outliner).")
		return
	ed._checkpoint()
	shot()["look_object"] = ed.outliner.name_of(ed.selected)
	_changed()


# ================================================================================================= shots and keys
func new_shot() -> void:
	ed._checkpoint()
	var n: int = ed.shots.size() + 1
	var names: Array = ed.shots.map(func(s: Dictionary) -> String: return String(s.get("name", "")))
	while names.has("Shot %d" % n):
		n += 1
	ed.shots.append(CameraPath.new_shot("Shot %d" % n))
	cur = ed.shots.size() - 1
	key = -1
	time = 0.0
	_changed(true)
	ed._set_status("New shot: fly the 3D view to where it starts and press Add key here; then to the next spot, and again.")


func _copy_shot() -> void:
	if shot().is_empty():
		return
	ed._checkpoint()
	var c := shot().duplicate(true)
	c["name"] = String(c.get("name", "Shot")) + " copy"
	ed.shots.insert(cur + 1, c)
	cur += 1
	_changed(true)


func _delete_shot() -> void:
	if shot().is_empty():
		return
	ed._checkpoint()
	var gone := String(shot().get("name", ""))
	ed.shots.remove_at(cur)
	cur = mini(cur, ed.shots.size() - 1)
	key = -1
	_changed(true)
	ed._set_status("Deleted the shot %s (Undo brings it back)." % gone)


func _pick_shot(i: int) -> void:
	if _updating:
		return
	stop()
	cur = i
	key = -1
	time = 0.0
	refresh()
	ed._redraw_overlays()


func _rename() -> void:
	var s := shot()
	var t := _name_edit.text.strip_edges()
	if s.is_empty() or t == "" or t == String(s.get("name", "")):
		_name_edit.text = String(s.get("name", ""))
		return
	ed._checkpoint()
	s["name"] = t
	_changed(true)


## A key where the 3D view's camera is now, after the selected key (a new shot if there is none yet).
func add_key_here() -> void:
	var cam: Camera3D = ed.panes[0].camera
	if shot().is_empty():
		new_shot()                                      # (its own undo step: the shot, then the key)
	ed._checkpoint()
	var ks: Array = shot()["keys"]
	var at := key + 1 if key >= 0 else ks.size()
	var dur := CameraPath.DEFAULT_DUR
	if key >= 0 and key < ks.size():
		dur = float((ks[key] as Dictionary).get("dur", dur))
	ks.insert(at, CameraPath.key_from(cam.global_transform, cam.fov, dur))
	key = at
	_changed(true)
	time = path().key_time(key)
	_refresh_fields()
	ed._set_status("Key %d added. Move the 3D view to the next spot and add another; the path between them is drawn in every view." % (key + 1))


func set_key_from_view() -> void:
	var ks := shot_keys()
	if key < 0 or key >= ks.size():
		ed._set_status("Select a key first (or press Add key here).")
		return
	ed._checkpoint()
	var cam: Camera3D = ed.panes[0].camera
	var old: Dictionary = ks[key]
	var k := CameraPath.key_from(cam.global_transform, cam.fov, float(old.get("dur", CameraPath.DEFAULT_DUR)))
	k["ease_in"] = old.get("ease_in", 0.0)
	k["ease_out"] = old.get("ease_out", 0.0)
	ks[key] = k
	_changed(true)


func delete_key() -> void:
	var ks := shot_keys()
	if key < 0 or key >= ks.size():
		return
	ed._checkpoint()
	ks.remove_at(key)
	key = mini(key, ks.size() - 1)
	_changed(true)


func move_key(dir: int) -> void:
	var ks := shot_keys()
	var to := key + dir
	if key < 0 or to < 0 or to >= ks.size():
		return
	ed._checkpoint()
	var k = ks[key]
	ks[key] = ks[to]
	ks[to] = k
	key = to
	_changed(true)


func select_key(i: int, look := false) -> void:
	key = i
	if not _updating and i >= 0 and i < _keys.item_count:
		_keys.select(i)
	_refresh_fields()
	if look:
		look_through()
	ed._redraw_overlays()


func look_through() -> void:
	if key < 0 or key >= shot_keys().size():
		return
	stop()
	scrub_to(path().key_time(key))


# ================================================================================================= preview
func scrub_to(t: float) -> void:
	time = clampf(t, 0.0, path().duration())
	looking = not shot_keys().is_empty()
	_show_time()


func _show_time() -> void:
	if shot_keys().is_empty():
		return
	var s := path().sample(time)
	(ed.panes[0].camera as OrbitCamera).set_view(s["xf"], s["fov"])
	_shown = s["xf"]
	_updating = true
	_scrub.set_value_no_signal(time)
	_updating = false
	_time_label.text = "%.2f / %.2f s" % [time, path().duration()]
	ed._redraw_overlays()


func toggle_play() -> void:
	if playing:
		stop()
		return
	if shot_keys().size() < 2:
		ed._set_status("A shot needs two keys or more to play: fly the 3D view somewhere and press Add key here.")
		return
	if time >= path().duration() - 1e-3:
		time = 0.0
	playing = true
	looking = true
	_play_button.text = "■ Stop"
	ed.panes[0].overlay.visible = false               # (the shot as it will look: no handles or outlines)


func stop() -> void:
	if not playing:
		return
	playing = false
	if _play_button:
		_play_button.text = "▶ Play"
	ed.panes[0].overlay.visible = true


## The strip closed (or the map is being played): the 3D view goes back to a normal camera.
func leave() -> void:
	stop()
	looking = false
	(ed.panes[0].camera as Camera3D).fov = 70.0


func _process(delta: float) -> void:
	if looking and not playing and not (ed.panes[0].camera as Camera3D).global_transform.is_equal_approx(_shown):
		looking = false                                  # (the view was moved: it shows the editor's camera again)
		ed._redraw_overlays()
	if not playing:
		return
	time += delta
	if time >= path().duration():
		time = path().duration()
		_show_time()
		stop()
		return
	_show_time()


# ================================================================================================= in the views
func _draw_ticks() -> void:
	var p := path()
	var d := p.duration()
	if d <= 0.0:
		return
	var w := _ticks.size.x - 16.0
	for i in shot_keys().size():
		var x := 8.0 + w * p.key_time(i) / d
		var c := SEL_COLOR if i == key else KEY_COLOR
		_ticks.draw_colored_polygon(PackedVector2Array([Vector2(x - 4, 0), Vector2(x + 4, 0), Vector2(x, 8)]), c)


func _frustum(cam: Camera3D, ov: Control, xf: Transform3D, fov: float, col: Color, size_m: float, width: float) -> void:
	var h := tan(deg_to_rad(fov) * 0.5) * size_m
	var w := h * aspect
	var apex := xf.origin
	var corners: Array[Vector3] = []
	for c in [Vector2(-w, h), Vector2(w, h), Vector2(w, -h), Vector2(-w, -h)]:
		corners.append(xf * Vector3(c.x, c.y, -size_m))
	var lines: Array = []
	for i in 4:
		lines.append([apex, corners[i]])
		lines.append([corners[i], corners[(i + 1) % 4]])
	lines.append([xf * Vector3(-w * 0.4, h * 1.15, -size_m), xf * Vector3(0, h * 1.5, -size_m)])   # (which way is up)
	lines.append([xf * Vector3(0, h * 1.5, -size_m), xf * Vector3(w * 0.4, h * 1.15, -size_m)])
	for l in lines:
		if cam.is_position_behind(l[0]) or cam.is_position_behind(l[1]):
			continue
		ov.draw_line(cam.unproject_position(l[0]), cam.unproject_position(l[1]), col, width)


func _gizmo_size(pane: ViewPane, at: Vector3) -> float:
	if pane.is_ortho():
		return pane.camera.size * 0.04
	return maxf(pane.camera.global_position.distance_to(at) * 0.07, 0.5)


## Drawn by the editor in every view while the strip is open.
func draw_overlay(pane: ViewPane, ov: Control) -> void:
	var cam := pane.camera
	var persp := pane.kind == ViewPane.Kind.PERSPECTIVE
	if persp:
		_draw_frame_guide(pane, ov)
	var ks := shot_keys()
	if ks.is_empty():
		return
	var p := path()
	var pts := p.polyline()
	for i in range(1, pts.size()):
		if cam.is_position_behind(pts[i]) or cam.is_position_behind(pts[i - 1]):
			continue
		ov.draw_line(cam.unproject_position(pts[i - 1]), cam.unproject_position(pts[i]), PATH_COLOR, 2.0)
	var font := ov.get_theme_default_font()
	for i in ks.size():
		var k: Dictionary = ks[i]
		var xf := CameraPath.key_transform(k)
		if cam.is_position_behind(xf.origin) or (persp and cam.global_position.distance_to(xf.origin) < 0.5):
			continue
		var col := SEL_COLOR if i == key else KEY_COLOR
		_frustum(cam, ov, xf, float(k.get("fov", 70.0)), col, _gizmo_size(pane, xf.origin), 2.0 if i == key else 1.2)
		var s := cam.unproject_position(xf.origin)
		ov.draw_circle(s, 6.5, Color(0, 0, 0, 0.75))
		ov.draw_circle(s, 5.0, col)
		ov.draw_string_outline(font, s + Vector2(8, -8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, s + Vector2(8, -8), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	var target = look_target(shot(), ed)
	if target is Vector3 and not cam.is_position_behind(target):
		var s := cam.unproject_position(target)
		for d in [Vector2(9, 9), Vector2(9, -9)]:
			ov.draw_line(s - d, s + d, Color(0, 0, 0, 0.8), 4.0)
			ov.draw_line(s - d, s + d, HEAD_COLOR, 2.0)
	if not (persp and looking):                         # (the camera at the time bar's moment)
		var at := p.sample(time)
		var hx: Transform3D = at["xf"]
		if not cam.is_position_behind(hx.origin):
			_frustum(cam, ov, hx, at["fov"], HEAD_COLOR, _gizmo_size(pane, hx.origin) * 1.2, 2.0)


## The render's frame in the 3D view: what fits in the video (the rest is shaded).
func _draw_frame_guide(pane: ViewPane, ov: Control) -> void:
	var sz := pane.size
	var w := sz.y * aspect
	var h := sz.y
	if w > sz.x:                                         # (a narrow view: the video is cropped top and bottom here)
		w = sz.x
		h = sz.x / aspect
	var r := Rect2((sz - Vector2(w, h)) * 0.5, Vector2(w, h))
	var shade := Color(0, 0, 0, 0.45 if looking else 0.2)
	ov.draw_rect(Rect2(0, 0, r.position.x, sz.y), shade)
	ov.draw_rect(Rect2(r.end.x, 0, sz.x - r.end.x, sz.y), shade)
	ov.draw_rect(Rect2(r.position.x, 0, w, r.position.y), shade)
	ov.draw_rect(Rect2(r.position.x, r.end.y, w, sz.y - r.end.y), shade)
	ov.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)


## Mouse in a view while the strip is open: drag keys and the look-at point. True when it took the event.
func pane_input(pane: ViewPane, event: InputEvent) -> bool:
	if playing and event is InputEventMouseButton and event.pressed:
		stop()                                           # (any click in a view stops the preview)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			return _begin_drag(pane, event.position, event.shift_pressed)
		if _drag_pane != null:
			_drag_pane = null
			return true
	if event is InputEventMouseMotion and _drag_pane == pane:
		_drag_to(event.position)
		return true
	return false


func _begin_drag(pane: ViewPane, mouse: Vector2, vertical: bool) -> bool:
	var cam := pane.camera
	var best := PICK_PX
	var what := ""
	var idx := -1
	var at := Vector3.ZERO
	var ks := shot_keys()
	for i in ks.size():
		var p := CameraPath.key_pos(ks[i])
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(mouse)
		if d < best:
			best = d
			what = "key"
			idx = i
			at = p
	var target = look_target(shot(), ed)
	if String(shot().get("look", "")) == "point" and target is Vector3 and not cam.is_position_behind(target):
		var d := cam.unproject_position(target).distance_to(mouse)
		if d < best:
			what = "look"
			at = target
	if what == "":
		return false
	stop()
	if what == "key":
		select_key(idx)
	ed._checkpoint()
	_drag_pane = pane
	_drag_what = what
	_drag_plane = pane.drag_plane(at, vertical)
	_drag_axes = pane.drag_axes(vertical)
	_drag_from = at
	var r := pane.ray(mouse)
	var hit = _drag_plane.intersects_ray(r[0], r[1])
	_drag_hit = hit if hit != null else at
	ed._set_status("Dragging %s (Shift while pressing in the 3D view: up and down)." % ("key %d" % (idx + 1) if what == "key" else "the look-at point"))
	return true


func _drag_to(mouse: Vector2) -> void:
	var r := _drag_pane.ray(mouse)
	var hit = _drag_plane.intersects_ray(r[0], r[1])
	if hit == null:
		return
	var p: Vector3 = _drag_from + ((hit as Vector3) - _drag_hit) * _drag_axes
	var arr := [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]
	if _drag_what == "key":
		var ks := shot_keys()
		if key < 0 or key >= ks.size():
			return
		(ks[key] as Dictionary)["pos"] = arr
	else:
		shot()["look_point"] = arr
	_changed()
