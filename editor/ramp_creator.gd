class_name RampCreator
extends Control
## The ramp creator: design a ramp's cross-section (drag points on its faces, a flat top, style, angle, face
## length, body) and its two ends (taper / round / flare, a diagonal cut, a lip, closed), see it live in 3D, and
## keep designs as ramp prefabs (RampPrefabs) with thumbnails, shareable as .malletramp files. A design is applied to
## the selected ramp (which keeps its points) or added as a new ramp. Shown over the editor like the welcome screen.

signal apply_requested(design: Dictionary, name: String)
signal new_ramp_requested(design: Dictionary, name: String)

const PREVIEW_SPINE := [Vector3(-45, 18, 0), Vector3(0, 12, 12), Vector3(45, 6, 0)]
const THUMB_SIZE := Vector2i(192, 108)
const STAND_ANGLE := 45.57                              ## Source: flatter than this, players stand instead of surfing
## Face shapes offered as a starting point: [label, points along the face (see RampShape.PROFILE_DEFAULTS)]
const FACE_SHAPES := [
	["Straight", []],
	["Curved in (steeper at the top)", [[0.125, -0.0175], [0.25, -0.03], [0.5, -0.04], [0.75, -0.03], [0.875, -0.0175]]],
	["Bulged out (steeper at the edge)", [[0.125, 0.0175], [0.25, 0.03], [0.5, 0.04], [0.75, 0.03], [0.875, 0.0175]]],
	["Two-step (bends halfway)", [[0.5, 0.05]]],
	["Lip near the edge", [[0.8, 0.0], [0.92, 0.07]]],
]

var design: Dictionary = {}                             ## the full design being edited (RampPrefabs.design_of)
var design_name := ""                                   ## the prefab it came from / was saved as
var env: Dictionary = {}                                ## the map's sky and sun, for the preview
var has_target := false                                 ## a ramp is selected (Apply is offered)
var target_locked := false                              ## ...but it has locks (designs change it all: refused)

var canvas: ProfileCanvas
var library: ItemList
var _lib_items: Array = []
var _ctl := {}
var _view := {}                                         ## the live preview: {vp, mesh, cam, ...}
var _thumb_view := {}                                   ## an offscreen view for thumbnails
var _orbit := Vector3(deg_to_rad(-20.0), deg_to_rad(-26.0), 100.0)    ## yaw, pitch, distance
const THUMB_ORBIT := Vector3(-0.3, -0.62, 80.0)                       ## (thumbnails: from higher up, broadside)
var _syncing := false
var _status: Label
var _summary: Label
var _apply: Button
var _save_dialog: ConfirmationDialog
var _file_dialog: FileDialog
var _thumbs_running := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.07, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.15)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	sb.border_color = Color(0.25, 0.28, 0.35)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	var title := Label.new()
	title.text = "Ramp creator"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 14)
	root.add_child(main)
	main.add_child(_build_library())
	main.add_child(_build_middle())
	main.add_child(_build_ends())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(info)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	info.add_child(_summary)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_status)
	_apply = _button(bottom, "Apply to the selected ramp", func(): apply_requested.emit(design.duplicate(true), design_name))
	_button(bottom, "Add as a new ramp", func(): new_ramp_requested.emit(design.duplicate(true), design_name))
	_button(bottom, "Close", hide)
	_build_dialogs()
	_view = _make_view(_ctl["preview"])
	_thumb_view = _make_view(null)
	if design.is_empty():
		set_design(RampPrefabs.design_of({}), "")


# ------------------------------------------------------------------------------------------------ building
func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	parent.add_child(l)


func _build_library() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(250, 0)
	_heading(box, "Ramp prefabs")
	var tip := Label.new()
	tip.text = "Click one to load it."
	tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	box.add_child(tip)
	library = ItemList.new()
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.fixed_icon_size = Vector2i(96, 54)
	library.icon_mode = ItemList.ICON_MODE_LEFT
	library.item_selected.connect(_library_picked)
	box.add_child(library)
	_button(box, "Save as a prefab…", func(): _save_dialog.popup_centered())
	var row := HBoxContainer.new()
	box.add_child(row)
	_ctl["delete"] = _button(row, "Delete", _delete_picked)
	_button(row, "Import…", func(): _open_file(true))
	_ctl["share"] = _button(row, "Share…", func(): _open_file(false))
	_ctl["delete"].tooltip_text = "Delete one of your prefabs (the starter ones stay)."
	_ctl["share"].tooltip_text = "Save the selected prefab as a .malletramp file to send to someone (they Import it)."
	return box


func _build_middle() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	var pv := SubViewportContainer.new()
	pv.stretch = true
	pv.custom_minimum_size = Vector2(0, 260)
	pv.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.gui_input.connect(_preview_input)
	pv.tooltip_text = "Drag to turn the view, mouse wheel to zoom."
	box.add_child(pv)
	_ctl["preview"] = pv
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cbox)
	_heading(cbox, "Cross-section")
	var help := Label.new()
	help.text = "Drag the yellow points · double-click a face to add one · right-click a point to remove it"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	cbox.add_child(help)
	canvas = ProfileCanvas.new()
	canvas.creator = self
	canvas.custom_minimum_size = Vector2(360, 230)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cbox.add_child(canvas)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(270, 0)
	row.add_child(side)
	var face := OptionButton.new()
	for fs in FACE_SHAPES:
		face.add_item(fs[0])
	face.add_item("Your own (the points below)")
	face.focus_mode = Control.FOCUS_NONE
	face.item_selected.connect(func(i):
		if _syncing or i >= FACE_SHAPES.size():
			return
		var p: Dictionary = _profile()
		p["left"] = (FACE_SHAPES[i][1] as Array).duplicate(true)
		if p["same"]:
			p["right"] = p["left"].duplicate(true)
		_set_profile(p))
	_row(side, "Face shape", face)
	_ctl["face"] = face
	var same := CheckButton.new()
	same.text = "Both faces the same"
	same.focus_mode = Control.FOCUS_NONE
	same.toggled.connect(func(on):
		if _syncing:
			return
		var p: Dictionary = _profile()
		p["same"] = on
		if on:
			p["right"] = p["left"].duplicate(true)
		_set_profile(p))
	side.add_child(same)
	_ctl["same"] = same
	var style := OptionButton.new()
	style.add_item("V ramp (surf either side)")
	style.add_item("Half ramp (surf the left side)")
	style.add_item("Half ramp (surf the right side)")
	style.focus_mode = Control.FOCUS_NONE
	style.item_selected.connect(func(i): _set_key("style", RampShape.STYLES[i]))
	_row(side, "Shape", style)
	_ctl["style"] = style
	var body := OptionButton.new()
	body.add_item("Hollow (open underneath)")
	body.add_item("Solid (flat bottom)")
	body.focus_mode = Control.FOCUS_NONE
	body.item_selected.connect(func(i): _set_key("solid", i == 1))
	_row(side, "Body", body)
	_ctl["solid"] = body
	_num(side, "angle", "Slope angle (°)", 30.0, 80.0, 0.5, func(v): _set_key("angle", v))
	_num(side, "face_length", "Face length (m)", 2.0, 60.0, 0.25, func(v): _set_key("face_length", v))
	_num(side, "top", "Flat top width (m)", 0.0, 20.0, 0.25, func(v):
		var p: Dictionary = _profile()
		p["top"] = v
		_set_profile(p))
	return box


func _build_ends() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(290, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 5)
	scroll.add_child(box)
	for which in ["start", "end"]:
		_heading(box, "Start of the ramp" if which == "start" else "End of the ramp")
		var shape := OptionButton.new()
		for lbl in ["Square", "Tapered (grows from a point)", "Rounded", "Flared (wider at the end)"]:
			shape.add_item(lbl)
		shape.focus_mode = Control.FOCUS_NONE
		shape.item_selected.connect(func(i): _set_end(which, "shape", RampShape.END_SHAPES[i]))
		_row(box, "Shape", shape)
		_ctl[which + "_shape"] = shape
		_num(box, which + "_length", "Over (m)", 1.0, 60.0, 0.5, func(v): _set_end(which, "length", v))
		_num(box, which + "_amount", "How much wider", 0.05, 2.0, 0.05, func(v): _set_end(which, "amount", v))
		_num(box, which + "_cut", "Diagonal cut (°)", -60.0, 60.0, 1.0, func(v): _set_end(which, "cut", v))
		_num(box, which + "_lip", "Lip height (m)", -4.0, 8.0, 0.1, func(v): _set_end(which, "lip", v))
		_num(box, which + "_lip_length", "Lip length (m)", 1.0, 40.0, 0.5, func(v): _set_end(which, "lip_length", v))
		var closed := CheckButton.new()
		closed.text = "Closed (hollow ramps)"
		closed.focus_mode = Control.FOCUS_NONE
		closed.tooltip_text = "Shut the open end of a hollow ramp, so nobody sees (or flies) into it."
		closed.toggled.connect(func(on): _set_end(which, "closed", on))
		box.add_child(closed)
		_ctl[which + "_closed"] = closed
		box.add_child(HSeparator.new())
	return scroll


func _row(parent: Control, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	parent.add_child(control)


func _num(parent: Control, key: String, label: String, lo: float, hi: float, step: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	var b := SpinBox.new()
	for r in [s, b]:
		r.min_value = lo
		r.max_value = hi
		r.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(80, 0)
	s.value_changed.connect(func(v):
		b.set_value_no_signal(v)
		if not _syncing:
			cb.call(v))
	b.value_changed.connect(func(v):
		s.set_value_no_signal(v)
		if not _syncing:
			cb.call(v))
	row.add_child(s)
	row.add_child(b)
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	parent.add_child(row)
	_ctl[key] = [s, b, l, row]


func _set_num(key: String, v: float) -> void:
	_ctl[key][0].set_value_no_signal(v)
	_ctl[key][1].set_value_no_signal(v)


func _show_num(key: String, on: bool) -> void:
	_ctl[key][2].visible = on
	_ctl[key][3].visible = on


func _build_dialogs() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "Save as a ramp prefab"
	var box := VBoxContainer.new()
	_save_dialog.add_child(box)
	var l1 := Label.new()
	l1.text = "Name"
	box.add_child(l1)
	var name_edit := LineEdit.new()
	name_edit.custom_minimum_size = Vector2(320, 0)
	box.add_child(name_edit)
	var l2 := Label.new()
	l2.text = "What it's for (optional)"
	box.add_child(l2)
	var desc := LineEdit.new()
	box.add_child(desc)
	_ctl["save_name"] = name_edit
	_ctl["save_desc"] = desc
	_save_dialog.about_to_popup.connect(func():
		name_edit.text = design_name if design_name != "" else "My ramp"
		desc.text = "")
	_save_dialog.confirmed.connect(func(): save_prefab(name_edit.text, desc.text))
	add_child(_save_dialog)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.malletramp ; MALLET ramp prefabs"])
	_file_dialog.file_selected.connect(_file_chosen)
	add_child(_file_dialog)


# ------------------------------------------------------------------------------------------------ the design
## Load a design to edit (`name`: the prefab it came from, if any).
func set_design(d: Dictionary, name: String) -> void:
	design = RampPrefabs.design_of(d)
	design_name = name
	_changed()


func _spec() -> Dictionary:
	return RampShape.spec(design)


func _profile() -> Dictionary:
	return RampShape.profile_spec(design.get("profile", {}))


func _set_profile(p: Dictionary) -> void:
	design["profile"] = RampShape.profile_spec(p)
	_changed()


func _set_key(key: String, v) -> void:
	if _syncing:
		return
	design[key] = v
	if key in ["angle", "face_length"] and not design.get("freeform", false):
		design[key + "_right"] = v
	_changed()


func _set_end(which: String, key: String, v) -> void:
	if _syncing:
		return
	var e: Dictionary = _spec()["ends"]
	e[which][key] = v
	design["ends"] = e
	_changed()


## Something changed: tidy the design, redraw everything.
func _changed() -> void:
	design = RampPrefabs.design_of(design)
	if is_inside_tree():
		_sync_controls()
		_update_preview(_view, design)
		canvas.queue_redraw()


func _sync_controls() -> void:
	_syncing = true
	var s := _spec()
	var p: Dictionary = s["profile"]
	_ctl["style"].select(RampShape.STYLES.find(s["style"]))
	_ctl["solid"].select(1 if s["solid"] else 0)
	_ctl["same"].set_pressed_no_signal(p["same"])
	_set_num("angle", s["angle"])
	_set_num("face_length", s["face_length"])
	_set_num("top", p["top"])
	var fi := FACE_SHAPES.size()
	for i in FACE_SHAPES.size():
		if FACE_SHAPES[i][1] == p["left"]:
			fi = i
	_ctl["face"].select(fi)
	for which in ["start", "end"]:
		var e: Dictionary = s["ends"][which]
		_ctl[which + "_shape"].select(RampShape.END_SHAPES.find(e["shape"]))
		for k in ["length", "amount", "cut", "lip", "lip_length"]:
			_set_num(which + "_" + k, e[k])
		_show_num(which + "_length", e["shape"] != "square")
		_show_num(which + "_amount", e["shape"] == "flare")
		_show_num(which + "_lip_length", e["lip"] != 0.0)
		_ctl[which + "_closed"].set_pressed_no_signal(e["closed"])
		_ctl[which + "_closed"].disabled = s["solid"]
	_apply.disabled = not has_target or target_locked
	_apply.tooltip_text = ("Select a ramp in the map first." if not has_target else
		"Unlock the selected ramp first: a design changes the whole ramp, locked part too." if target_locked else
		"The selected ramp keeps its points and takes this design.")
	_summary.text = ("%s: " % design_name if design_name != "" else "") + RampPrefabs.describe(design)
	_status.text = _warnings()
	_syncing = false


## Plain-language warnings: faces too flat to surf, folds in the preview.
func _warnings() -> String:
	var s := _spec()
	var surf := RampShape.surface(s)
	var flat := 0
	for i in surf.size() - 1:
		var d := surf[i + 1] - surf[i]
		if d.length() > 1e-4 and rad_to_deg(atan2(absf(d.y), absf(d.x))) < STAND_ANGLE:
			flat += 1
	var out := []
	if flat > 0 and not (s["profile"]["top"] > 0.0 and flat == 1):
		out.append("Orange parts of the cross-section are flatter than 45.6°: players stand there instead of surfing.")
	if not (_view.get("geo", {}) as Dictionary).get("folds", PackedInt32Array()).is_empty():
		out.append("The preview's bend folds the faces over: on a tighter bend this design needs a shorter face.")
	return " ".join(out) if not out.is_empty() else "Surfable everywhere (green)."


# ------------------------------------------------------------------------------------------------ preview
func _make_view(container: SubViewportContainer) -> Dictionary:
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	if container:
		container.add_child(vp)
	else:
		vp.size = THUMB_SIZE * 2
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = Look.build_environment(env if not env.is_empty() else Look.default_environment())
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	Look.apply_sun(sun, env if not env.is_empty() else Look.default_environment())
	vp.add_child(sun)
	var mesh := MeshInstance3D.new()
	vp.add_child(mesh)
	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	cam.current = true
	var v := {"vp": vp, "mesh": mesh, "cam": cam, "we": we, "sun": sun, "geo": {}, "thumb": container == null}
	_place_camera(v)
	return v


## Refresh the preview's sky and sun (the map's own, set before opening).
func refresh_environment() -> void:
	for v in [_view, _thumb_view]:
		if v.is_empty():
			continue
		v["we"].environment = Look.build_environment(env if not env.is_empty() else Look.default_environment())
		Look.apply_sun(v["sun"], env if not env.is_empty() else Look.default_environment())


func _update_preview(v: Dictionary, d: Dictionary) -> void:
	if v.is_empty():
		return
	var s := RampShape.spec(d)
	var geo := RampShape.build(PackedVector3Array(PREVIEW_SPINE), s)
	v["geo"] = geo
	var mesh: ArrayMesh = geo["mesh"]
	(v["mesh"] as MeshInstance3D).mesh = mesh
	(v["mesh"] as MeshInstance3D).material_override = Look.ramp_material("grid", Color(0.78, 0.8, 0.86))


func _place_camera(v: Dictionary) -> void:
	var cam: Camera3D = v["cam"]
	var o: Vector3 = THUMB_ORBIT if v.get("thumb", false) else _orbit
	var target := Vector3(0, 8, 5)
	var dir := Vector3(0, 0, 1).rotated(Vector3.RIGHT, o.y).rotated(Vector3.UP, o.x)
	cam.position = target + dir * o.z
	cam.look_at(target)


func _preview_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and (e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)):
		_orbit.x -= e.relative.x * 0.008
		_orbit.y = clampf(_orbit.y - e.relative.y * 0.008, deg_to_rad(-85.0), deg_to_rad(60.0))
		_place_camera(_view)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit.z = maxf(_orbit.z * 0.9, 30.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit.z = minf(_orbit.z * 1.1, 400.0)
		_place_camera(_view)


## A picture of a design (for prefab thumbnails), rendered offscreen.
func render_thumb(d: Dictionary) -> Image:
	_update_preview(_thumb_view, d)
	_place_camera(_thumb_view)
	var vp: SubViewport = _thumb_view["vp"]
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	return img


# ------------------------------------------------------------------------------------------------ library
## Show the creator: the library refreshed, thumbnails made for any prefab without one.
func open() -> void:
	refresh_environment()
	show()
	refresh_library()
	_changed()
	_make_missing_thumbs()


func refresh_library() -> void:
	library.clear()
	_lib_items = RampPrefabs.list()
	for it in _lib_items:
		var i := library.add_item(String(it["name"]) + ("" if it["builtin"] else "  (yours)"), RampPrefabs.thumbnail(it["path"]))
		library.set_item_tooltip(i, String(it["description"]) if it["description"] != "" else RampPrefabs.describe(it["design"]))


func _make_missing_thumbs() -> void:
	if _thumbs_running:
		return
	_thumbs_running = true
	var made := false
	for it in _lib_items.duplicate():
		var tp := RampPrefabs.thumb_path(it["path"])
		if FileAccess.file_exists(tp):
			continue
		DirAccess.make_dir_recursive_absolute(tp.get_base_dir())
		var img: Image = await render_thumb(it["design"])
		img.save_png(tp)
		made = true
	_thumbs_running = false
	if made and is_inside_tree():
		refresh_library()


func _library_picked(i: int) -> void:
	if i < 0 or i >= _lib_items.size():
		return
	set_design(_lib_items[i]["design"], _lib_items[i]["name"])
	_ctl["delete"].disabled = _lib_items[i]["builtin"]


## Save the design as one of your prefabs (with a thumbnail). Returns the file.
func save_prefab(name: String, description := "") -> String:
	if name.strip_edges() == "":
		_status.text = "Give the prefab a name first."
		return ""
	var img: Image = await render_thumb(design)
	var path := RampPrefabs.save(name, design, description, img)
	design_name = name.strip_edges()
	refresh_library()
	_sync_controls()
	_status.text = "Saved as a ramp prefab: %s" % name.strip_edges()
	return path


func _delete_picked() -> void:
	var sel := library.get_selected_items()
	if sel.is_empty() or _lib_items[sel[0]]["builtin"]:
		_status.text = "Pick one of your own prefabs to delete (the starter ones stay)."
		return
	RampPrefabs.remove(_lib_items[sel[0]]["path"])
	refresh_library()


var _file_import := true


func _open_file(importing: bool) -> void:
	_file_import = importing
	if not importing:
		var sel := library.get_selected_items()
		if sel.is_empty():
			_status.text = "Pick the prefab to share in the list first."
			return
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.current_file = String(_lib_items[sel[0]]["path"]).get_file()
	else:
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.popup_centered_ratio(0.6)


func _file_chosen(path: String) -> void:
	if _file_import:
		var p := RampPrefabs.import_file(path)
		_status.text = ("Imported %s." % path.get_file()) if p != "" else "%s isn't a MALLET ramp prefab." % path.get_file()
		refresh_library()
		_make_missing_thumbs()
	else:
		var sel := library.get_selected_items()
		if sel.is_empty():
			return
		var ok := RampPrefabs.export_file(_lib_items[sel[0]]["path"], path)
		_status.text = ("Saved %s - send it to anyone with MALLET (Import… in the ramp creator)." % path) if ok else "Couldn't write %s." % path


# ------------------------------------------------------------------------------------------------ cross-section
## The editable cross-section: the profile drawn to scale on a 1 m grid, the riding surface green where it's
## surfable and orange where it's flat enough to stand on, the face points draggable.
class ProfileCanvas extends Control:
	var creator: RampCreator
	var _drag := []                                     ## [side, index] while dragging a point
	var _hover := []
	var _xf := Transform2D.IDENTITY                     ## profile meters -> canvas pixels

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _faces(s: Dictionary) -> Dictionary:
		## side -> [origin, along, out, length] for each face the style has
		var a := deg_to_rad(s["angle"])
		var b := deg_to_rad(s["angle_right"])
		var half := float(s["profile"]["top"]) * 0.5
		var out := {}
		if s["style"] != "half_right":
			out["left"] = [Vector2(-half, 0), Vector2(-cos(a), -sin(a)), Vector2(-sin(a), cos(a)), float(s["face_length"])]
		if s["style"] != "half_left":
			out["right"] = [Vector2(half, 0), Vector2(cos(b), -sin(b)), Vector2(sin(b), cos(b)), float(s["face_length_right"])]
		return out

	func _point_pos(f: Array, q: Array) -> Vector2:
		return f[0] + f[1] * f[3] * float(q[0]) + f[2] * f[3] * float(q[1])

	func _fit(pts: PackedVector2Array) -> void:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
		lo -= Vector2(2, 2)
		hi += Vector2(2, 2)
		var k := minf(size.x / (hi.x - lo.x), size.y / (hi.y - lo.y))
		var mid := (lo + hi) * 0.5
		_xf = Transform2D(Vector2(k, 0), Vector2(0, -k), size * 0.5 - Vector2(mid.x * k, -mid.y * k))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.08, 0.1))
		if creator == null or creator.design.is_empty():
			return
		var s := creator._spec()
		var prof := RampShape.profile(s)
		var pts: PackedVector2Array = prof["pts"]
		_fit(pts)
		var inv := _xf.affine_inverse()
		var a := inv * Vector2.ZERO
		var b := inv * size
		for x in range(int(floor(minf(a.x, b.x))), int(ceil(maxf(a.x, b.x))) + 1):
			var c := Color(1, 1, 1, 0.10 if x % 5 == 0 else 0.04)
			draw_line(_xf * Vector2(x, a.y), _xf * Vector2(x, b.y), c)
		for y in range(int(floor(minf(a.y, b.y))), int(ceil(maxf(a.y, b.y))) + 1):
			var c := Color(1, 1, 1, 0.10 if y % 5 == 0 else 0.04)
			draw_line(_xf * Vector2(a.x, y), _xf * Vector2(b.x, y), c)
		var screen := PackedVector2Array()
		for q in pts:
			screen.append(_xf * q)
		if not Geometry2D.triangulate_polygon(screen).is_empty():
			draw_colored_polygon(screen, Color(0.32, 0.34, 0.4))
		var closed := screen.duplicate()
		closed.append(screen[0])
		draw_polyline(closed, Color(0.55, 0.58, 0.65), 1.0, true)
		var surf := RampShape.surface(s)
		for i in surf.size() - 1:
			var d := surf[i + 1] - surf[i]
			var ok := d.length() < 1e-4 or rad_to_deg(atan2(absf(d.y), absf(d.x))) >= RampCreator.STAND_ANGLE
			draw_line(_xf * surf[i], _xf * surf[i + 1], Color(0.35, 0.95, 0.5) if ok else Color(1.0, 0.6, 0.2), 3.0, true)
		var faces := _faces(s)
		for side in faces:
			var f: Array = faces[side]
			var list: Array = s["profile"][side]
			for i in list.size():
				var p := _xf * _point_pos(f, list[i])
				var hot := _hover == [side, i] or _drag == [side, i]
				draw_circle(p, 7.0 if hot else 5.5, Color(1.0, 0.85, 0.2) if side == "left" or not s["profile"]["same"] else Color(1.0, 0.85, 0.2, 0.55))
		var font := get_theme_default_font()
		draw_string(font, Vector2(8, size.y - 8), "grid: 1 m · width %.1f m · height %.1f m" % [_extent(pts).x, _extent(pts).y],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.64, 0.7))

	func _extent(pts: PackedVector2Array) -> Vector2:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
		return hi - lo

	func _pick(pos: Vector2) -> Array:
		var s := creator._spec()
		var faces := _faces(s)
		var best := []
		var bd := 12.0
		for side in faces:
			var list: Array = s["profile"][side]
			for i in list.size():
				var d := (_xf * _point_pos(faces[side], list[i])).distance_to(pos)
				if d < bd:
					bd = d
					best = [side, i]
		return best

	## The face position [t, n] under the mouse on one face.
	func _tn(side: String, pos: Vector2) -> Array:
		var f: Array = _faces(creator._spec())[side]
		var rel: Vector2 = _xf.affine_inverse() * pos - f[0]
		return [rel.dot(f[1]) / f[3], rel.dot(f[2]) / f[3]]

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.double_click:
			add_point_at(e.position)
			accept_event()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag = _pick(e.position) if e.pressed else []
			queue_redraw()
			accept_event()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			var hit := _pick(e.position)
			if not hit.is_empty():
				remove_point(hit[0], hit[1])
			accept_event()
		elif e is InputEventMouseMotion:
			if not _drag.is_empty():
				move_point(_drag[0], _drag[1], _tn(_drag[0], e.position))
			else:
				var h := _pick(e.position)
				if h != _hover:
					_hover = h
					queue_redraw()

	## Edits (also used by tests). With "same", the right face follows the left.
	func _edit(side: String, fn: Callable) -> void:
		var p: Dictionary = creator._profile()
		var key := "left" if p["same"] else side
		var list: Array = (p[key] as Array).duplicate(true)
		fn.call(list)
		p[key] = list
		if p["same"]:
			p["right"] = list.duplicate(true)
		creator._set_profile(p)
		queue_redraw()

	func move_point(side: String, i: int, tn: Array) -> void:
		_edit(side, func(list: Array):
			if i >= list.size():
				return
			var lo := float(list[i - 1][0]) + 0.01 if i > 0 else 0.01
			var hi := float(list[i + 1][0]) - 0.01 if i + 1 < list.size() else 0.99
			list[i] = [clampf(tn[0], lo, hi), clampf(tn[1], -0.6, 0.6)])

	func remove_point(side: String, i: int) -> void:
		_edit(side, func(list: Array): if i < list.size(): list.remove_at(i))

	func add_point_at(pos: Vector2) -> void:
		var s := creator._spec()
		var best := ""
		var bn := INF
		for side in _faces(s):
			var tn := _tn(side, pos)
			if tn[0] > 0.02 and tn[0] < 0.98 and absf(tn[1]) < bn:
				bn = absf(tn[1])
				best = side
		if best == "":
			return
		var tn := _tn(best, pos)
		_edit(best, func(list: Array):
			list.append([clampf(tn[0], 0.02, 0.98), clampf(tn[1], -0.6, 0.6)])
			list.sort_custom(func(x, y): return x[0] < y[0]))
