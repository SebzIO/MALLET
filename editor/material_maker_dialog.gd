class_name MaterialMakerDialog
extends Window
## The material maker's window (0.21.0): the picture on the left (paint on it when a paint layer is chosen), the
## starting material, size and layers on the right. Opened from the material picker ("Make / edit a material…",
## or right-click a material to start from it). See MaterialMaker for the layers.

signal saved(id: String)

var editor: Node                              ## for the material picker (Start from…)
var canvas: MaterialMaker
var editing_id := ""                          ## one of your made materials being changed ("" = a new one)
var selected := -1                            ## index into recipe.layers

var brush_color := Color.BLACK
var brush_size := 12.0                        ## pixels of the saved 1024 texture
var brush_hardness := 0.8
var erasing := false
var _stroke_undo: Array = []                  ## [[file, Image]] before each stroke (Ctrl+Z)
var _painting := false
var _last_uv := Vector2(-1, -1)

var _view: TextureRect
var _overlay: Control
var _tiles: GridContainer
var _list: ItemList
var _props: GridContainer
var _name: LineEdit
var _base_btn: Button
var _tint: ColorPickerButton
var _size: SpinBox
var _fit: CheckBox
var _guide: CheckBox
var _tiled: CheckBox
var _paint_row: HBoxContainer
var _paint_help: Label
var _save_over: Button
var _status: Label
var _file_dialog: FileDialog
var _finish_fields := {}                      ## key -> [HSlider, SpinBox]
var _ball_view: SubViewport
var _ball: MeshInstance3D

const VIEW := 512.0


func _init() -> void:
	title = "Material maker"
	size = Vector2i(1100, 680)
	min_size = Vector2i(900, 640)
	wrap_controls = true
	transient = true
	close_requested.connect(hide)
	canvas = MaterialMaker.new()
	add_child(canvas)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.15)
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	margin.add_child(hb)
	_build_left(hb)
	_build_right(hb)


func _build_left(hb: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	hb.add_child(left)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(VIEW, VIEW)
	left.add_child(holder)
	_view = TextureRect.new()
	_view.texture = canvas.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.size = Vector2(VIEW, VIEW)
	holder.add_child(_view)
	_tiles = GridContainer.new()
	_tiles.columns = 2
	_tiles.add_theme_constant_override("h_separation", 0)
	_tiles.add_theme_constant_override("v_separation", 0)
	for i in 4:
		var t := TextureRect.new()
		t.texture = canvas.get_texture()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.custom_minimum_size = Vector2(VIEW, VIEW) * 0.5
		_tiles.add_child(t)
	_tiles.visible = false
	holder.add_child(_tiles)
	_overlay = Control.new()
	_overlay.size = Vector2(VIEW, VIEW)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_view_input)
	_overlay.mouse_exited.connect(_overlay.queue_redraw)
	holder.add_child(_overlay)
	var row := HBoxContainer.new()
	left.add_child(row)
	_tiled = CheckBox.new()
	_tiled.text = "Tiled 2 × 2"
	_tiled.tooltip_text = "See it repeat, as it will on a surface (painting works here too)."
	_tiled.toggled.connect(func(on: bool): _tiles.visible = on; _view.visible = not on; _overlay.queue_redraw())
	row.add_child(_tiled)
	_guide = CheckBox.new()
	_guide.text = "Ramp guide"
	_guide.tooltip_text = "With \"Fit across a ramp\" on: the dashed line is the ridge (top) of a ramp, the sides are its\nedges. Left to right is across the ramp, up and down is along it."
	_guide.toggled.connect(func(_on: bool): _overlay.queue_redraw())
	row.add_child(_guide)
	_paint_row = HBoxContainer.new()
	left.add_child(_paint_row)
	var pc := ColorPickerButton.new()
	pc.color = brush_color
	pc.custom_minimum_size = Vector2(44, 28)
	pc.tooltip_text = "Brush color"
	pc.color_changed.connect(func(c: Color): brush_color = c)
	_paint_row.add_child(pc)
	_paint_row.add_child(_small_label("Size"))
	var bs := HSlider.new()
	bs.min_value = 1
	bs.max_value = 120
	bs.value = brush_size
	bs.custom_minimum_size.x = 110
	bs.value_changed.connect(func(v: float): brush_size = v; _overlay.queue_redraw())
	_paint_row.add_child(bs)
	_paint_row.add_child(_small_label("Hard"))
	var bh := HSlider.new()
	bh.min_value = 0.0
	bh.max_value = 1.0
	bh.step = 0.05
	bh.value = brush_hardness
	bh.custom_minimum_size.x = 80
	bh.value_changed.connect(func(v: float): brush_hardness = v)
	_paint_row.add_child(bh)
	var er := CheckBox.new()
	er.text = "Eraser"
	er.toggled.connect(func(on: bool): erasing = on)
	_paint_row.add_child(er)
	var clear := Button.new()
	clear.text = "Clear"
	clear.tooltip_text = "Wipe this paint layer"
	clear.pressed.connect(_clear_paint)
	_paint_row.add_child(clear)
	var help := Label.new()
	help.text = "Paint: left-drag on the picture. Shift+drag paints a straight line. Ctrl+Z undoes a stroke."
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.custom_minimum_size.x = VIEW
	_paint_help = help
	left.add_child(help)


func _build_right(hb: HBoxContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	var r1 := HBoxContainer.new()
	right.add_child(r1)
	r1.add_child(_small_label("Name"))
	_name = LineEdit.new()
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(t: String): canvas.recipe["name"] = t)
	r1.add_child(_name)
	var r2 := HBoxContainer.new()
	right.add_child(r2)
	r2.add_child(_small_label("Start from"))
	_base_btn = Button.new()
	_base_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_btn.tooltip_text = "The material underneath your layers (its surface detail comes along too). Pick one of your\nmade materials to open it and change it."
	_base_btn.pressed.connect(_pick_base)
	r2.add_child(_base_btn)
	var plain := Button.new()
	plain.text = "Plain color"
	plain.pressed.connect(func(): canvas.recipe["base"] = ""; _refresh_all())
	r2.add_child(plain)
	_tint = ColorPickerButton.new()
	_tint.custom_minimum_size = Vector2(44, 28)
	_tint.tooltip_text = "Plain color: the color. A starting material: its tint (white = as it is)."
	_tint.color_changed.connect(_tint_changed)
	r2.add_child(_tint)
	var r3 := HBoxContainer.new()
	right.add_child(r3)
	r3.add_child(_small_label("One repeat"))
	_size = SpinBox.new()
	_size.min_value = 0.25
	_size.max_value = 64.0
	_size.step = 0.25
	_size.suffix = "m"
	_size.tooltip_text = "Meters one copy of the picture covers on a surface (at texture scale 1)."
	_size.value_changed.connect(func(v: float): canvas.recipe["size"] = v)
	r3.add_child(_size)
	_fit = CheckBox.new()
	_fit.text = "Fit across a ramp"
	_fit.tooltip_text = "On ramps, the picture spans the whole riding surface once from edge to edge (the ridge is the\nmiddle, see the Ramp guide), repeating every \"One repeat\" along the ramp. For lines on the ridge\nor along the edges. Blocks and cubes still repeat it every \"One repeat\"."
	_fit.toggled.connect(func(on: bool): canvas.recipe["ramp_fit"] = on)
	r3.add_child(_fit)
	_build_finish(right)
	right.add_child(HSeparator.new())
	var lh := HBoxContainer.new()
	right.add_child(lh)
	var lt := Label.new()
	lt.text = "Layers (top of the list is drawn on top)"
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lt)
	var ridge := Button.new()
	ridge.text = "+ Ridge line"
	ridge.tooltip_text = "A black line along a ramp's ridge: a stripe in the middle, and \"Fit across a ramp\" on."
	ridge.pressed.connect(add_ridge_line)
	lh.add_child(ridge)
	var add := MenuButton.new()
	add.text = "+ Add layer"
	add.flat = false
	for i in MaterialMaker.TYPES.size():
		add.get_popup().add_item(MaterialMaker.TYPE_NAMES[MaterialMaker.TYPES[i]], i)
	add.get_popup().id_pressed.connect(func(i: int): add_layer(MaterialMaker.TYPES[i]))
	lh.add_child(add)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 150
	_list.item_selected.connect(func(i: int): _select(_list_to_layer(i)))
	right.add_child(_list)
	var lb := HBoxContainer.new()
	right.add_child(lb)
	for spec in [["Up", func(): _move(1)], ["Down", func(): _move(-1)], ["Show / hide", _toggle_on],
			["Copy", _duplicate], ["Delete", _delete]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		lb.add_child(b)
	var ps := ScrollContainer.new()
	ps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ps.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(ps)
	_props = GridContainer.new()
	_props.columns = 2
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ps.add_child(_props)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size.x = 440
	right.add_child(_status)
	var bb := HBoxContainer.new()
	bb.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(bb)
	_save_over = Button.new()
	_save_over.text = "Save"
	_save_over.tooltip_text = "Save over this material: everything using it changes."
	_save_over.pressed.connect(func(): save_material(false))
	bb.add_child(_save_over)
	var sn := Button.new()
	sn.text = "Save as new"
	sn.pressed.connect(func(): save_material(true))
	bb.add_child(sn)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide)
	bb.add_child(close)


## The finish: brightness, light of its own, gloss and reflections, with a turning ball that shows them in 3D.
func _build_finish(right: VBoxContainer) -> void:
	right.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	right.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	for spec in [["bright", "Brightness ×", 0.0, 4.0, 0.01, "How much light it gives back: 1 = as it is. Type any number (10, 100...) for more."],
			["glow", "Light of its own", 0.0, 8.0, 0.05, "It shines by itself, even in the dark: 0 = not at all. Type any number for more."],
			["gloss", "Glossiness", 0.0, 1.0, 0.01, "0 = as photographed, 1 = mirror-smooth (sharp reflections)."],
			["reflect", "Reflectiveness", 0.0, 1.0, 0.01, "0 = none, 1 = a perfect mirror (like polished metal). With glossiness 1 it
reflects the sky sharply; the Map panel's Reflections setting adds the map itself."]]:
		var key: String = spec[0]
		var l := _small_label(spec[1])
		l.tooltip_text = spec[5]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(l)
		var h := HBoxContainer.new()
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var s := HSlider.new()
		s.min_value = spec[2]
		s.max_value = spec[3]
		s.step = spec[4]
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.tooltip_text = spec[5]
		var sp := SpinBox.new()
		sp.min_value = spec[2]
		sp.max_value = spec[3]
		sp.step = spec[4]
		sp.allow_greater = key in ["bright", "glow"]           # (no upper limit on light)
		sp.custom_minimum_size.x = 84
		s.value_changed.connect(func(v: float): sp.set_value_no_signal(v); _finish_changed(key, v))
		sp.value_changed.connect(func(v: float): s.set_value_no_signal(v); _finish_changed(key, v))
		h.add_child(s)
		h.add_child(sp)
		grid.add_child(h)
		_finish_fields[key] = [s, sp]
	_ball_view = SubViewport.new()
	_ball_view.size = Vector2i(132, 132)
	_ball_view.own_world_3d = true
	_ball_view.transparent_bg = false
	_ball_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ball_view)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var ps := ProceduralSkyMaterial.new()
	ps.sky_top_color = Color(0.25, 0.45, 0.85)
	ps.sky_horizon_color = Color(0.8, 0.85, 0.9)
	ps.ground_bottom_color = Color(0.12, 0.1, 0.08)
	ps.ground_horizon_color = Color(0.5, 0.45, 0.4)
	sky.sky_material = ps
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_ball_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	_ball_view.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 2.6)
	cam.fov = 40
	_ball_view.add_child(cam)
	_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radial_segments = 48
	sm.rings = 24
	_ball.mesh = sm
	_ball_view.add_child(_ball)
	var tr := TextureRect.new()
	tr.texture = _ball_view.get_texture()
	tr.custom_minimum_size = Vector2(132, 132)
	tr.tooltip_text = "Your material on a ball, lit by a sun under a blue sky: gloss and reflections show here."
	row.add_child(tr)


func _finish_changed(key: String, v: float) -> void:
	if not canvas.recipe.get("finish") is Dictionary:
		canvas.recipe["finish"] = MaterialLibrary.FINISH_DEFAULTS.duplicate()
	canvas.recipe["finish"][key] = v
	_update_ball()


## The ball's material: the picture as it is now, the starting material's surface detail, and the finish.
func _update_ball() -> void:
	if _ball == null:
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = canvas.get_texture()
	var base := String(canvas.recipe.get("base", ""))
	var has_metal := false
	var has_glow := false
	if base != "" and MaterialLibrary.has(base):
		var n := MaterialLibrary.texture(base, "normal")
		if n:
			m.normal_enabled = true
			m.normal_texture = n
		var r := MaterialLibrary.texture(base, "roughness")
		if r:
			m.roughness_texture = r
		var mt := MaterialLibrary.texture(base, "metal")
		if mt:
			m.metallic = 1.0
			m.metallic_texture = mt
			has_metal = true
		var gl := MaterialLibrary.texture(base, "glow")
		if gl:
			m.emission_enabled = true
			m.emission_texture = gl
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			m.emission_energy_multiplier = MaterialLibrary.GLOW_ENERGY
			has_glow = true
	var fin := MaterialLibrary.FINISH_DEFAULTS.duplicate()
	if canvas.recipe.get("finish") is Dictionary:
		fin.merge(canvas.recipe["finish"], true)
	MaterialLibrary.apply_finish(m, fin, has_metal, has_glow)
	_ball.material_override = m


func _process(delta: float) -> void:
	if visible and _ball:
		_ball.rotate_y(delta * 0.6)


func _small_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


# ------------------------------------------------------------------------------------------------------ opening
## Start from a material: one of your made ones opens its recipe; anything else is the starting material of a new
## one; "" is a plain color.
func open_from(id: String) -> void:
	canvas.images.clear()
	canvas._textures.clear()
	_stroke_undo.clear()
	editing_id = ""
	if MaterialLibrary.is_made(id):
		editing_id = id
		canvas.recipe = (MaterialLibrary.entry(id)["recipe"] as Dictionary).duplicate(true)
		canvas.recipe["name"] = MaterialLibrary.display_name(id)
		canvas.load_images(String(MaterialLibrary.entry(id)["dir"]))
	else:
		canvas.recipe = MaterialMaker.new_recipe(id)
	selected = canvas.recipe["layers"].size() - 1
	_refresh_all()
	_status.text = ("Changing \"%s\". Save changes it everywhere it is used; Save as new keeps the old one." % MaterialLibrary.display_name(id)) \
		if editing_id != "" else "Add layers on top, then Save as new. It joins \"Made by you\" in the material picker."


func _pick_base() -> void:
	if editor == null:
		return
	editor._open_picker(func(id: String):
		if MaterialLibrary.is_made(id):
			open_from(id)
		else:
			canvas.recipe["base"] = id
			if id != "":
				canvas.recipe["size"] = MaterialLibrary.world_size(id)
			_refresh_all())


func _tint_changed(c: Color) -> void:
	if String(canvas.recipe.get("base", "")) != "":
		canvas.recipe["tint"] = c.to_html(false)
	else:
		canvas.recipe["color"] = c.to_html(false)
	canvas.rebuild()


func _refresh_all() -> void:
	var r := canvas.recipe
	var base := String(r.get("base", ""))
	_name.text = String(r.get("name", ""))
	_base_btn.text = MaterialLibrary.display_name(base) if base != "" else "(a plain color)"
	_base_btn.icon = MaterialLibrary.preview(base) if base != "" else null
	_base_btn.expand_icon = true
	_tint.color = Color.html(String(r.get("tint" if base != "" else "color", "ffffff")))
	_size.set_value_no_signal(float(r.get("size", 2.0)))
	_fit.set_pressed_no_signal(bool(r.get("ramp_fit", false)))
	_save_over.disabled = editing_id == ""
	var fin := MaterialLibrary.FINISH_DEFAULTS.duplicate()
	if r.get("finish") is Dictionary:
		fin.merge(r["finish"], true)
	for k in _finish_fields:
		(_finish_fields[k][0] as HSlider).set_value_no_signal(float(fin[k]))
		(_finish_fields[k][1] as SpinBox).set_value_no_signal(float(fin[k]))
	canvas.rebuild()
	_update_ball()
	_refresh_list()
	_refresh_props()


# ------------------------------------------------------------------------------------------------------- layers
func _layers() -> Array:
	return canvas.recipe["layers"]


## The list shows the top layer first.
func _list_to_layer(i: int) -> int:
	return _layers().size() - 1 - i


func _refresh_list() -> void:
	_list.clear()
	var ls := _layers()
	for i in range(ls.size() - 1, -1, -1):
		_list.add_item(MaterialMaker.layer_label(ls[i]))
	if selected >= 0 and selected < ls.size():
		_list.select(ls.size() - 1 - selected)
	_paint_row.visible = _selected_type() == "paint"
	_paint_help.visible = _paint_row.visible
	_overlay.queue_redraw()


func _selected_type() -> String:
	var ls := _layers()
	return String(ls[selected].get("type", "")) if selected >= 0 and selected < ls.size() else ""


func _select(i: int) -> void:
	selected = i
	_paint_row.visible = _selected_type() == "paint"
	_paint_help.visible = _paint_row.visible
	_refresh_props()
	_overlay.queue_redraw()


func add_layer(type: String) -> Dictionary:
	var l := MaterialMaker.new_layer(type)
	if type == "paint":
		l["file"] = canvas.new_file()
		var img := Image.create(MaterialMaker.SIZE, MaterialMaker.SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		canvas.images[l["file"]] = img
		l["color"] = "ffffff"
	_layers().insert(selected + 1, l)
	selected += 1
	canvas.rebuild()
	_refresh_list()
	_refresh_props()
	if type == "image":
		_choose_image()
	return l


## The user's example: a black line along the ridge of a ramp.
func add_ridge_line() -> void:
	var l := add_layer("stripe")
	l["width"] = 0.03
	canvas.recipe["ramp_fit"] = true
	_fit.set_pressed_no_signal(true)
	_guide.button_pressed = true
	canvas.rebuild()
	_refresh_props()


func _move(up: int) -> void:
	var ls := _layers()
	var to := selected + up
	if selected < 0 or to < 0 or to >= ls.size():
		return
	var l = ls[selected]
	ls.remove_at(selected)
	ls.insert(to, l)
	selected = to
	canvas.rebuild()
	_refresh_list()


func _toggle_on() -> void:
	if selected < 0 or selected >= _layers().size():
		return
	_layers()[selected]["on"] = not _layers()[selected].get("on", true)
	canvas.rebuild()
	_refresh_list()


func _duplicate() -> void:
	if selected < 0 or selected >= _layers().size():
		return
	var l: Dictionary = _layers()[selected].duplicate(true)
	var f := String(l.get("file", ""))
	if f != "" and canvas.images.has(f):
		l["file"] = canvas.new_file()
		canvas.images[l["file"]] = (canvas.images[f] as Image).duplicate()
	_layers().insert(selected + 1, l)
	selected += 1
	canvas.rebuild()
	_refresh_list()
	_refresh_props()


func _delete() -> void:
	if selected < 0 or selected >= _layers().size():
		return
	_layers().remove_at(selected)
	selected = mini(selected, _layers().size() - 1)
	canvas.rebuild()
	_refresh_list()
	_refresh_props()


# --------------------------------------------------------------------------------------------- layer settings
func _refresh_props() -> void:
	for c in _props.get_children():
		_props.remove_child(c)
		c.queue_free()
	if selected < 0 or selected >= _layers().size():
		var none := Label.new()
		none.text = "No layer chosen. Add one with + Add layer."
		_props.add_child(none)
		return
	var l: Dictionary = _layers()[selected]
	var type := String(l["type"])
	if type != "adjust":
		_color_row(l, "Color" if type != "image" else "Tint")
		_option_row(l, "blend", "Blend", MaterialMaker.BLENDS,
			"Mix: on top. Add: lightens. Multiply: darkens (white does nothing). Subtract: takes away.")
	_slider_row(l, "opacity", "Opacity", 0.0, 1.0, 0.01)
	match type:
		"adjust":
			_slider_row(l, "hue", "Hue shift", -0.5, 0.5, 0.01)
			_slider_row(l, "sat", "Saturation", 0.0, 2.0, 0.01)
			_slider_row(l, "bright", "Brightness", -1.0, 1.0, 0.01)
			_slider_row(l, "contrast", "Contrast", 0.0, 2.0, 0.01)
			_slider_row(l, "gamma", "Gamma (below 1 lighter, above darker)", 0.05, 4.0, 0.01, true)
		"stripe":
			_option_row(l, "dir", "Direction", ["vertical", "horizontal"],
				"Vertical runs up and down the picture: along a ramp. Horizontal runs across.")
			_slider_row(l, "pos", "Position", 0.0, 1.0, 0.005)
			_slider_row(l, "width", "Width", 0.002, 1.0, 0.002)
			_slider_row(l, "angle", "Angle", -90.0, 90.0, 1.0)
			_slider_row(l, "soft", "Soft edge", 0.0, 0.5, 0.005)
		"rect", "ellipse":
			_slider_row(l, "x", "Center left-right", 0.0, 1.0, 0.005)
			_slider_row(l, "y", "Center up-down", 0.0, 1.0, 0.005)
			_slider_row(l, "w", "Width", 0.005, 1.0, 0.005)
			_slider_row(l, "h", "Height", 0.005, 1.0, 0.005)
			_slider_row(l, "angle", "Angle", -180.0, 180.0, 1.0)
			_slider_row(l, "soft", "Soft edge", 0.0, 0.5, 0.005)
		"text":
			_text_row(l, "text", "Text")
			_slider_row(l, "x", "Center left-right", 0.0, 1.0, 0.005)
			_slider_row(l, "y", "Center up-down", 0.0, 1.0, 0.005)
			_slider_row(l, "size", "Size", 0.02, 0.6, 0.005)
			_slider_row(l, "angle", "Angle", -180.0, 180.0, 1.0)
		"image":
			var b := Button.new()
			b.text = "Choose an image…"
			b.pressed.connect(_choose_image)
			_props.add_child(_small_label("Picture"))
			_props.add_child(b)
			_slider_row(l, "x", "Center left-right", 0.0, 1.0, 0.005)
			_slider_row(l, "y", "Center up-down", 0.0, 1.0, 0.005)
			_slider_row(l, "w", "Width", 0.01, 1.0, 0.005)
			_slider_row(l, "h", "Height", 0.01, 1.0, 0.005)
			_slider_row(l, "angle", "Angle", -180.0, 180.0, 1.0)
		"paint":
			var hint := Label.new()
			hint.text = "Paint on the picture. Color here tints the whole layer (white = as painted)."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD
			hint.custom_minimum_size.x = 300
			_props.add_child(_small_label(""))
			_props.add_child(hint)


func _changed(l: Dictionary, key: String, v) -> void:
	l[key] = v
	canvas.rebuild()
	var i := _layers().find(l)
	if i >= 0:
		_list.set_item_text(_layers().size() - 1 - i, MaterialMaker.layer_label(l))
	_overlay.queue_redraw()


func _slider_row(l: Dictionary, key: String, label: String, lo: float, hi: float, step: float, unlimited := false) -> void:
	_props.add_child(_small_label(label))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(l.get(key, lo))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = s.value
	sp.custom_minimum_size.x = 90
	sp.allow_greater = unlimited
	s.value_changed.connect(func(v: float): sp.set_value_no_signal(v); _changed(l, key, v))
	sp.value_changed.connect(func(v: float): s.set_value_no_signal(v); _changed(l, key, v))
	row.add_child(s)
	row.add_child(sp)
	_props.add_child(row)


func _color_row(l: Dictionary, label: String) -> void:
	_props.add_child(_small_label(label))
	var c := ColorPickerButton.new()
	c.color = Color.html(String(l.get("color", "000000")))
	c.custom_minimum_size = Vector2(60, 28)
	c.color_changed.connect(func(v: Color): _changed(l, "color", v.to_html(v.a < 1.0)))
	_props.add_child(c)


func _option_row(l: Dictionary, key: String, label: String, options: Array, tip := "") -> void:
	_props.add_child(_small_label(label))
	var o := OptionButton.new()
	for opt in options:
		o.add_item(String(opt).capitalize())
	o.select(maxi(options.find(l.get(key, options[0])), 0))
	o.tooltip_text = tip
	o.item_selected.connect(func(i: int): _changed(l, key, options[i]))
	_props.add_child(o)


func _text_row(l: Dictionary, key: String, label: String) -> void:
	_props.add_child(_small_label(label))
	var e := LineEdit.new()
	e.text = String(l.get(key, ""))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(t: String): _changed(l, key, t))
	_props.add_child(e)


func _choose_image() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		_file_dialog.file_selected.connect(set_layer_image)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


## The chosen image layer shows this picture (PNG transparency is kept).
func set_layer_image(path: String) -> void:
	if _selected_type() != "image":
		return
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_status.text = "Couldn't read %s as an image." % path.get_file()
		return
	if maxi(img.get_width(), img.get_height()) > MaterialMaker.SIZE:
		var k := float(MaterialMaker.SIZE) / maxi(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	var l: Dictionary = _layers()[selected]
	l["file"] = canvas.new_file()
	canvas.images[l["file"]] = img
	var aspect := float(img.get_height()) / maxf(img.get_width(), 1)
	l["h"] = clampf(float(l.get("w", 0.5)) * aspect, 0.01, 1.0)
	canvas.rebuild()
	_refresh_props()


# ----------------------------------------------------------------------------------------------------- painting
func _paint_image() -> Image:
	if _selected_type() != "paint":
		return null
	return canvas.images.get(String(_layers()[selected].get("file", "")))


## Where on the texture (0..1) a point of the picture is (the tiled view shows it twice each way).
func _uv_at(p: Vector2) -> Vector2:
	var uv := p / VIEW
	if _tiles.visible:
		uv = Vector2(fposmod(uv.x * 2.0, 1.0), fposmod(uv.y * 2.0, 1.0))
	return uv


func _view_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_overlay.queue_redraw()
	var img := _paint_image()
	if img == null:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var file := String(_layers()[selected]["file"])
			_stroke_undo.append([file, img.duplicate()])
			if _stroke_undo.size() > 30:
				_stroke_undo.pop_front()
			var uv := _uv_at(e.position)
			if e.shift_pressed and _last_uv.x >= 0.0:
				paint_line(_last_uv, uv)
			else:
				paint_line(uv, uv)
			_painting = true
		else:
			_painting = false
	elif e is InputEventMouseMotion and _painting:
		var uv := _uv_at(e.position)
		var from := _uv_at(e.position - e.relative)
		if from.distance_to(uv) > 0.5:                       # (crossed a tile edge in the tiled view)
			from = uv
		paint_line(from, uv)


## A brush stroke from a to b (uv), dabs close enough to look continuous.
func paint_line(a: Vector2, b: Vector2) -> void:
	var img := _paint_image()
	if img == null:
		return
	var r := brush_size * img.get_width() / float(MaterialMaker.SIZE)
	var steps := maxi(int(ceil(a.distance_to(b) * img.get_width() / maxf(r * 0.35, 0.5))), 1)
	for i in range(0 if a == b else 1, steps + 1):
		MaterialMaker.dab(img, a.lerp(b, float(i) / steps), r, brush_color, brush_hardness, erasing)
	_last_uv = b
	canvas.image_changed(String(_layers()[selected]["file"]))


func _clear_paint() -> void:
	var img := _paint_image()
	if img:
		_stroke_undo.append([String(_layers()[selected]["file"]), img.duplicate()])
		img.fill(Color(0, 0, 0, 0))
		canvas.image_changed(String(_layers()[selected]["file"]))


func _input(e: InputEvent) -> void:
	if visible and e is InputEventKey and e.pressed and e.keycode == KEY_Z and e.ctrl_pressed and not _stroke_undo.is_empty():
		var u: Array = _stroke_undo.pop_back()
		if canvas.images.has(u[0]):
			(canvas.images[u[0]] as Image).copy_from(u[1])
			canvas.image_changed(u[0])
		set_input_as_handled()


func _draw_overlay() -> void:
	var cells := 2 if _tiles.visible else 1
	var cell := VIEW / cells
	if _guide.button_pressed:
		for k in cells:
			var x0 := k * cell
			_overlay.draw_dashed_line(Vector2(x0 + cell * 0.5, 0), Vector2(x0 + cell * 0.5, VIEW), Color(1, 0.85, 0.2, 0.9), 2.0, 8.0)
			_overlay.draw_line(Vector2(x0 + 1, 0), Vector2(x0 + 1, VIEW), Color(0.3, 0.8, 1.0, 0.8), 2.0)
			_overlay.draw_line(Vector2(x0 + cell - 1, 0), Vector2(x0 + cell - 1, VIEW), Color(0.3, 0.8, 1.0, 0.8), 2.0)
		_overlay.draw_string(get_theme_default_font(), Vector2(cell * 0.5 + 6, 18), "ridge", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.2))
		_overlay.draw_string(get_theme_default_font(), Vector2(6, 18), "edge", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.8, 1.0))
	if _selected_type() == "paint":
		var m := _overlay.get_local_mouse_position()
		if Rect2(Vector2.ZERO, Vector2(VIEW, VIEW)).has_point(m):
			_overlay.draw_arc(m, brush_size * cell / MaterialMaker.SIZE, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 1.0)


# ------------------------------------------------------------------------------------------------------- saving
## Save (over the material being changed, or as a new one). Emits `saved` with its id.
func save_material(as_new: bool) -> String:
	if String(canvas.recipe.get("name", "")).strip_edges() == "":
		canvas.recipe["name"] = "My material"
	var px := canvas.size
	canvas.size = Vector2i(MaterialMaker.SIZE, MaterialMaker.SIZE)
	canvas.rebuild()
	var img: Image = await canvas.capture()
	canvas.size = px
	canvas.rebuild()
	var id := MaterialMaker.save(canvas.recipe, img, canvas.images, "" if as_new else editing_id)
	editing_id = id
	_save_over.disabled = false
	_status.text = "Saved \"%s\" (in \"Made by you\")." % MaterialLibrary.display_name(id)
	saved.emit(id)
	return id
