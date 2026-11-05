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
var props_root := Node3D.new()
var blocks_root := Node3D.new()
var _block_props: VBoxContainer
var _blocks_dirty := false
var _draw_mode := false                 ## Draw block tool: drag a rectangle in a 2D view to make a block
var _draw_block: BlockNode = null
var _draw_start := Vector3.ZERO
var _draw_pane: ViewPane = null
var _last_block := {"size": [16.0, 8.0, 16.0]}   ## new blocks take the last size used
var _face := -1                          ## the block side being dragged (index into face_handles)
var _prop_props: VBoxContainer
var _prop_dialog: FileDialog
var _prop_replace := false
var selected: Node3D = null          ## a RampNode or an EntityNode
var selected_point := -1
var snap_enabled := true
var snap_step := 4.0
var current_path := ""
var play := PlayMode.new()
var panes: Array[ViewPane] = []
var active_pane: ViewPane
var quad_view := true
var environment := {}                ## the map's sky / sun / fog settings (see Look.ENV_PRESETS)
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var _map_props: VBoxContainer
var _image_dialog: FileDialog
var show_all_arcs := false
var best_ghost: Dictionary = {}         ## the map's best run in play mode (saved with the map, not in undo)
var show_ghost_path := true
var show_direction := true             ## editor guide: arrows along each ramp from its start to its end
var _arcs: Array = []                ## [{ramp, speed, ref, runs: [full, sloppy]}] from the jump checker
var _arcs_timer := 0.0
var _arcs_dirty := 2                 ## frames left to recompute arcs (2: physics needs a tick to see moved bodies)
const SLOPPY := 0.85                 ## the second arc: a rider who has lost 15% of their speed

var _undo: Array = []
var _redo: Array = []
var _coalesce_key := ""
var _coalesce_time := 0.0
# drag state
enum Drag { NONE, POINT, OBJECT, FACE }
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
var _stage_props: VBoxContainer
var _tex_box: VBoxContainer
var _freeform_box: VBoxContainer
var _unlock_confirm: ConfirmationDialog
var _pending_unlock := -1
const RAMP_WIDE := ["style", "solid", "base_depth", "detail", "slice", "freeform"]   ## frozen while locked
var _status: Label
var _info: Label
var _fields := {}
var _updating_ui := false
var _file_dialog: FileDialog
var _export_dialog: ConfirmationDialog
var _export_name: LineEdit
var _export_dir: LineEdit
var _dir_dialog: FileDialog
var _css_dialog: ConfirmationDialog
var _css_name: LineEdit
var _css_dir: LineEdit
var _css_sky: OptionButton
var _css_aa: SpinBox
var _css_compile: CheckBox
var _css_quality: OptionButton
var _css_thread: Thread
var _css_result := {}
var _css_status := ""
var welcome: WelcomeScreen
# ramp generator (while _gen_ramp is set, the side panel shows the generator and the ramp is a live preview)
var _gen_ramp: RampNode = null
var _gen_source: RampNode = null        ## the ramp the new one continues from (null = place at the view centre)
var _gen_shape := "spiral"
var _gen_values := {}                   ## shape -> {param: value}, remembered between uses
var _gen_follow := true
var _gen_gap := 40.0
var _gen_side := 1.0
var _gen_anchor := Vector3.ZERO
var _gen_anchor_yaw := 0.0
var _gen_props: VBoxContainer
var _gen_param_box: VBoxContainer
var _gen_place_box: VBoxContainer
var _gen_about: Label
var _gen_warning: Label
var _gen_shape_buttons := {}
const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	# The editor draws handles, outlines and arcs from objects' true positions, so the 3D view must not be
	# smoothed between physics ticks (that made outlines trail moving objects and the camera).
	# Only the play-mode player uses physics interpolation, as in SurfsUp.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	play.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_build_world()
	_build_ui()
	add_child(play)
	play.stopped.connect(_on_play_stopped)
	play.ghost_recorded.connect(func(g): best_ghost = g)
	_new_map()
	_set_title("")
	_show_welcome_if_main.call_deferred()


## The welcome screen greets you when SurfForge starts (not when a test builds the editor).
func _show_welcome_if_main() -> void:
	if get_tree().current_scene == self:
		welcome.popup("Skip, use the simple starter map")


# ================================================================================================= world
func _build_world() -> void:
	world_env = WorldEnvironment.new()
	add_child(world_env)
	sun = DirectionalLight3D.new()
	add_child(sun)
	environment = Look.default_environment()
	_apply_environment()

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
	add_child(props_root)
	add_child(blocks_root)


# ================================================================================================= ui
func _build_ui() -> void:
	add_child(_ui)
	_build_ui_main()
	welcome = WelcomeScreen.new()
	welcome.hide()
	_ui.add_child(welcome)
	welcome.template_chosen.connect(_on_template_chosen)
	welcome.open_requested.connect(func():
		welcome.hide()
		_open_clicked())


func _build_ui_main() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	_ui.add_child(root)

	var bar_panel := PanelContainer.new()
	_fields["toolbar"] = bar_panel
	root.add_child(bar_panel)
	var bar := HFlowContainer.new()                    # wraps onto a second row on narrower windows
	bar.add_theme_constant_override("h_separation", 5)
	bar.add_theme_constant_override("v_separation", 2)
	bar_panel.add_child(bar)
	var title := Label.new()
	title.text = "  SurfForge"
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	var ver := Label.new()
	ver.text = "%s  " % SurfForgeVersion.VERSION
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	ver.tooltip_text = SurfForgeVersion.full()
	bar.add_child(ver)
	for spec in [["New", _new_map_clicked], ["Open…", _open_clicked], ["Save", _save_clicked], ["|", null],
			["+ Ramp (N)", _add_ramp_clicked], ["✦ Generate (R)", _generate_clicked], ["+ Start (B)", func(): _add_entity("start")],
			["+ Finish (M)", func(): _add_entity("finish")], ["+ Kill zone (K)", func(): _add_entity("kill")],
			["+ Booster (J)", func(): _add_entity("booster")], ["+ Stage (T)", func(): _add_entity("stage")],
			["+ Teleport (Y)", func(): _add_entity("teleport")], ["+ Prop (I)", _add_prop_clicked], ["|", null],
			["+ Block (O)", _add_block_clicked], ["Draw block (D)", _toggle_draw_mode], ["|", null],
			["Extend", _extend_clicked], ["Add Bend", _bend_clicked], ["Duplicate", _duplicate_clicked],
			["Delete", _delete_clicked], ["|", null], ["Undo", undo], ["Redo", redo], ["|", null],
			["Frame (F)", _frame_clicked], ["|", null], ["▶ Play (P)", _play_clicked],
			["Export to SurfsUp", _export_clicked], ["Export to CS:S", _css_clicked]]:
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
	snap.text = "Snap to grid"
	snap.button_pressed = snap_enabled
	snap.focus_mode = Control.FOCUS_NONE
	snap.tooltip_text = "Dragged and nudged points land on a grid (G)."
	snap.toggled.connect(func(on): snap_enabled = on; _fields["snap_step"].disabled = not on; _set_status("Grid snap %s" % ("on" if on else "off")))
	bar.add_child(snap)
	_fields["snap_button"] = snap
	var step := OptionButton.new()
	for s in [1, 2, 4, 8, 16]:
		step.add_item("every %d m" % s, s)
	step.select(2)
	step.focus_mode = Control.FOCUS_NONE
	step.tooltip_text = "Grid size: how far apart the snap points are (also the arrow-key nudge step)."
	step.item_selected.connect(func(i): snap_step = float(step.get_item_id(i)); _set_status("Snap grid: every %d m" % int(snap_step)))
	bar.add_child(step)
	_fields["snap_step"] = step
	bar.add_child(VSeparator.new())
	var arcs := CheckButton.new()
	arcs.text = "Jump arcs: all ramps"
	arcs.focus_mode = Control.FOCUS_NONE
	arcs.tooltip_text = "Off: arcs only for the selected ramp. On: every ramp's jump at once."
	arcs.toggled.connect(func(on): show_all_arcs = on; _map_changed())
	bar.add_child(arcs)
	var arrows := CheckButton.new()
	arrows.text = "Direction arrows"
	arrows.button_pressed = show_direction
	arrows.focus_mode = Control.FOCUS_NONE
	arrows.tooltip_text = "Arrows along every ramp showing which way it is ridden (first point to last). Editor only: never exported."
	arrows.toggled.connect(func(on): show_direction = on; _redraw_overlays())
	bar.add_child(arrows)
	var gp := CheckButton.new()
	gp.text = "Best run"
	gp.button_pressed = show_ghost_path
	gp.focus_mode = Control.FOCUS_NONE
	gp.tooltip_text = "Draw the path of your best play-mode run, coloured by speed (blue slow, red fast). Editor only."
	gp.toggled.connect(func(on): show_ghost_path = on)
	bar.add_child(gp)

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

	# always shown at a fixed width (it used to pop in on selection and resize the views); scrolls when tall
	_props_panel = PanelContainer.new()
	_props_panel.custom_minimum_size = Vector2(310, 0)
	middle.add_child(_props_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_props_panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
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
	_build_css_dialog()


func _build_props(props: VBoxContainer) -> void:
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	props.add_child(head)
	_fields["head"] = head

	_ramp_props = VBoxContainer.new()
	_ramp_props.add_theme_constant_override("separation", 6)
	props.add_child(_ramp_props)
	var flip := Button.new()
	flip.text = "⇄  Flip direction"
	flip.focus_mode = Control.FOCUS_NONE
	flip.tooltip_text = "Reverse which end the ramp is ridden from. The ramp itself stays exactly where it is."
	flip.pressed.connect(_flip_clicked)
	_ramp_props.add_child(flip)
	_fields["flip"] = flip
	_build_lock_props()
	var shape := OptionButton.new()
	shape.add_item("V ramp (surf either side)")
	shape.add_item("Half ramp (surf the left side)")
	shape.add_item("Half ramp (surf the right side)")
	shape.focus_mode = Control.FOCUS_NONE
	shape.item_selected.connect(func(i): _edit_prop("style", RampShape.STYLES[i]))
	_add_row(_ramp_props, "Shape", shape)
	_fields["style"] = shape
	var body := OptionButton.new()
	body.add_item("Hollow (open underneath)", 0)
	body.add_item("Solid (flat bottom)", 1)
	body.focus_mode = Control.FOCUS_NONE
	body.item_selected.connect(func(i): _edit_prop("solid", i == 1))
	_add_row(_ramp_props, "Body", body)
	_fields["solid"] = body
	_add_slider(_ramp_props, "angle", "Slope angle (°)", 30.0, 80.0, 0.5)
	_add_slider(_ramp_props, "face_length", "Face length (m)", 2.0, 60.0, 0.25)
	_fields["angle_label"] = _ramp_props.get_child(_fields["angle"][0].get_parent().get_index() - 1)
	_fields["face_length_label"] = _ramp_props.get_child(_fields["face_length"][0].get_parent().get_index() - 1)
	_add_slider(_ramp_props, "base_depth", "Base depth (m, solid only)", 0.0, 60.0, 0.5)
	_add_slider(_ramp_props, "detail", "Smoothness (cross-sections / m)", 0.1, 4.0, 0.05)
	var slice := OptionButton.new()
	slice.add_item("Vertical slice (recommended)")
	slice.add_item("Perpendicular to travel")
	slice.focus_mode = Control.FOCUS_NONE
	slice.tooltip_text = ("Vertical slice: the cross-section stays upright even where the ramp climbs or drops steeply, so it never\n"
		+ "leans. Perpendicular: the cross-section tips with the slope. On steep stretches the two differ slightly: in a\n"
		+ "vertical slice the face measured across the direction of travel is a little steeper than the slider says.")
	slice.item_selected.connect(func(i): _edit_prop("slice", "vertical" if i == 0 else "perpendicular"))
	_add_row(_ramp_props, "Angle measured in", slice)
	_fields["slice"] = slice
	var ff := CheckButton.new()
	ff.text = "Freeform (advanced)"
	ff.focus_mode = Control.FOCUS_NONE
	ff.tooltip_text = "Off: both faces match. On: the right face can have its own angle and length."
	ff.toggled.connect(func(on): _edit_prop("freeform", on))
	_ramp_props.add_child(ff)
	_fields["freeform"] = ff
	_freeform_box = VBoxContainer.new()
	_freeform_box.add_theme_constant_override("separation", 6)
	_ramp_props.add_child(_freeform_box)
	var ff_note := Label.new()
	ff_note.text = "FREEFORM: the faces can differ. Turning it off again makes the right face match the left one."
	ff_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ff_note.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
	_freeform_box.add_child(ff_note)
	_add_slider(_freeform_box, "angle_right", "Right face angle (°)", 10.0, 89.0, 0.5)
	_add_slider(_freeform_box, "face_length_right", "Right face length (m)", 2.0, 60.0, 0.25)
	var look := OptionButton.new()
	for k in Look.LOOK_ORDER:
		look.add_item(Look.RAMP_LOOKS[k][0])
	look.focus_mode = Control.FOCUS_NONE
	look.item_selected.connect(func(i): _edit_prop("look", Look.LOOK_ORDER[i]))
	_add_row(_ramp_props, "Look", look)
	_fields["look"] = look
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("color", c))
	_add_row(_ramp_props, "Colour", cp)
	_fields["color"] = cp
	_fields["color_label"] = _ramp_props.get_child(cp.get_index() - 1)
	_tex_box = VBoxContainer.new()
	_ramp_props.add_child(_tex_box)
	var pick := Button.new()
	pick.text = "Choose image…"
	pick.focus_mode = Control.FOCUS_NONE
	pick.pressed.connect(func(): _image_dialog.popup_centered_ratio(0.6))
	_tex_box.add_child(pick)
	var tex_name := Label.new()
	tex_name.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tex_name.add_theme_font_size_override("font_size", 12)
	_tex_box.add_child(tex_name)
	_fields["tex_name"] = tex_name
	_add_slider(_tex_box, "tex_scale", "Image size along the ramp (m)", 1.0, 200.0, 1.0)

	_build_gen_props(props)
	_build_prop_props(props)
	_build_block_props(props)

	_entity_props = VBoxContainer.new()
	_entity_props.add_theme_constant_override("separation", 6)
	props.add_child(_entity_props)
	_add_slider(_entity_props, "size_x", "Width (m)", 4.0, 200.0, 1.0)
	_add_slider(_entity_props, "size_z", "Depth (m)", 4.0, 200.0, 1.0)
	_add_slider(_entity_props, "size_y", "Height (m)", 2.0, 200.0, 1.0)
	_add_slider(_entity_props, "yaw", "Facing (°)", -180.0, 180.0, 5.0)
	_stage_props = VBoxContainer.new()
	_stage_props.add_theme_constant_override("separation", 6)
	_entity_props.add_child(_stage_props)
	_add_slider(_stage_props, "number", "Stage number", 2.0, 50.0, 1.0)
	var keep := CheckButton.new()
	keep.text = "Keep the player's speed"
	keep.focus_mode = Control.FOCUS_NONE
	keep.toggled.connect(func(on): _edit_prop("keep_speed", on))
	_stage_props.add_child(keep)
	_fields["keep_speed"] = keep
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

	_build_map_props(props)
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
		+ "N ramp · B start · M finish · K kill zone · J booster · T stage · Y teleport · I prop · P play\nR generate a ramp shape · L lock / unlock a point\nSpace maximise the view under the mouse (again: back to four)\nF frame · G snap to grid · F11 fullscreen\n"
		+ "Del delete · Ctrl+D duplicate · Ctrl+Z undo · Ctrl+S save")
	props.add_child(help)


## Map panel (shown when nothing is selected): the map's sky, sun and fog.
func _build_map_props(props: VBoxContainer) -> void:
	_map_props = VBoxContainer.new()
	_map_props.add_theme_constant_override("separation", 6)
	props.add_child(_map_props)
	var preset := OptionButton.new()
	for k in Look.ENV_PRESETS:
		preset.add_item(Look.ENV_PRESETS[k]["label"])
	preset.add_item("Custom")
	preset.focus_mode = Control.FOCUS_NONE
	preset.item_selected.connect(func(i):
		var keys := Look.ENV_PRESETS.keys()
		if i < keys.size():
			_checkpoint()
			environment = Look.preset_environment(keys[i])
			_apply_environment()
			_refresh_props())
	_add_row(_map_props, "Sky preset", preset)
	_fields["env_preset"] = preset
	for spec in [["sky_top", "Sky colour (top)"], ["sky_horizon", "Sky colour (horizon)"], ["ground", "Below the horizon"],
			["sun_color", "Sun colour"], ["ambient_color", "Shadow fill colour"], ["fog_color", "Fog colour"]]:
		var key: String = spec[0]
		var c := ColorPickerButton.new()
		c.custom_minimum_size = Vector2(0, 24)
		c.color_changed.connect(func(col): _edit_env(key, col.to_html(false)))
		_add_row(_map_props, spec[1], c)
		_fields["env_" + key] = c
	_add_slider(_map_props, "env_sun_yaw", "Sun direction (°)", -180.0, 180.0, 1.0)
	_add_slider(_map_props, "env_sun_pitch", "Sun height (°)", 0.0, 90.0, 1.0)
	_add_slider(_map_props, "env_sun_energy", "Sun brightness", 0.0, 3.0, 0.05)
	_add_slider(_map_props, "env_ambient_energy", "Shadow fill brightness", 0.0, 3.0, 0.05)
	_add_slider(_map_props, "env_stars", "Stars", 0.0, 1.0, 0.05)
	_add_slider(_map_props, "env_aurora", "Aurora", 0.0, 1.0, 0.05)
	_add_slider(_map_props, "env_nebula", "Nebula clouds", 0.0, 1.0, 0.05)
	var fog := CheckButton.new()
	fog.text = "Fog"
	fog.focus_mode = Control.FOCUS_NONE
	fog.toggled.connect(func(on): _edit_env("fog", on))
	_map_props.add_child(fog)
	_fields["env_fog"] = fog
	_add_slider(_map_props, "env_fog_density", "Fog thickness", 0.0, 0.01, 0.0001)

	_image_dialog = FileDialog.new()
	_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_dialog.use_native_dialog = true
	_image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_image_dialog.file_selected.connect(func(path): _edit_prop("texture", path); _refresh_props())
	_ui.add_child(_image_dialog)


func _apply_environment() -> void:
	world_env.environment = Look.build_environment(environment)
	Look.apply_sun(sun, environment)
	sun.directional_shadow_max_distance = 1500.0


func _edit_env(key: String, value) -> void:
	if _updating_ui:
		return
	_checkpoint("env:" + key)
	environment[key] = value
	environment["preset"] = "custom"
	_apply_environment()
	_fields["env_preset"].select(Look.ENV_PRESETS.size())


func _refresh_map_props() -> void:
	_updating_ui = true
	var keys := Look.ENV_PRESETS.keys()
	var p: int = keys.find(environment.get("preset", "custom"))
	_fields["env_preset"].select(p if p >= 0 else keys.size())
	for key in ["sky_top", "sky_horizon", "ground", "sun_color", "ambient_color", "fog_color"]:
		_fields["env_" + key].color = Color.html(environment[key])
	for key in ["sun_yaw", "sun_pitch", "sun_energy", "ambient_energy", "stars", "aurora", "nebula", "fog_density"]:
		_set_field("env_" + key, float(environment[key]))
	_fields["env_fog"].button_pressed = bool(environment["fog"])
	_updating_ui = false


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
	_gen_props.visible = _gen_ramp != null
	if _gen_ramp:
		_map_props.visible = false
		_ramp_props.visible = false
		_entity_props.visible = false
		_prop_props.visible = false
		_block_props.visible = false
		_fields["head"].text = "Generate a ramp"
		_refresh_info()
		return
	_map_props.visible = selected == null
	_prop_props.visible = false
	_block_props.visible = false
	if selected == null:
		_ramp_props.visible = false
		_entity_props.visible = false
		_fields["head"].text = "Map"
		_refresh_map_props()
		_refresh_info()
		return
	_updating_ui = true
	var is_ramp := selected is RampNode
	_ramp_props.visible = is_ramp
	_entity_props.visible = selected is EntityNode
	_prop_props.visible = selected is PropNode
	_block_props.visible = selected is BlockNode
	if selected is BlockNode:
		var b := selected as BlockNode
		_fields["head"].text = b.label()
		_fields["block_shape"].select(BlockShape.SHAPES.find(b.data["shape"]))
		var sz: Vector3 = b.size()
		_set_field("block_x", sz.x)
		_set_field("block_y", sz.y)
		_set_field("block_z", sz.z)
		_set_field("block_yaw", float(b.data["yaw"]))
		_set_field("block_sides", float(b.data["sides"]))
		_set_field("block_steps", float(b.data["steps"]))
		_set_field("block_wall", float(b.data["wall"]))
		_fields["block_hollow"].set_pressed_no_signal(bool(b.data["hollow"]))
		_fields["block_cutter"].set_pressed_no_signal(b.is_cutter())
		_fields["block_look"].select(Look.LOOK_ORDER.find(b.data["look"]))
		_fields["block_color"].color = Color.html(b.data["color"])
		_fields["block_sides_box"].visible = b.data["shape"] == "cylinder"
		_fields["block_steps_box"].visible = b.data["shape"] == "stairs"
		_fields["block_hollow"].visible = b.data["shape"] in ["box", "cylinder"] and not b.is_cutter()
		_fields["block_wall_box"].visible = bool(b.data["hollow"]) and b.data["shape"] in ["box", "cylinder"] and not b.is_cutter()
		_fields["block_look_box"].visible = not b.is_cutter()
		_updating_ui = false
		_refresh_info()
		return
	if selected is PropNode:
		var pr := selected as PropNode
		_fields["head"].text = "Prop"
		_fields["prop_file"].text = pr.source.get_file() if pr.source != "" else "(no model)"
		_set_field("prop_size", pr.size)
		_set_field("prop_yaw", pr.yaw)
		_fields["prop_solid"].set_pressed_no_signal(pr.solid)
		_updating_ui = false
		_refresh_info()
		return
	if is_ramp:
		var r := selected as RampNode
		_fields["head"].text = "Ramp  ·  FREEFORM" if r.freeform else "Ramp"
		_fields["style"].select(RampShape.STYLES.find(r.style))
		_refresh_lock_props(r)
		_fields["flip"].disabled = not r.frozen.is_empty()
		_fields["flip"].tooltip_text = ("Unlock the ramp first: flipping would change what each lock freezes." if not r.frozen.is_empty()
			else "Reverse which end the ramp is ridden from. The ramp itself stays exactly where it is.")
		_fields["solid"].select(1 if r.solid else 0)
		_fields["slice"].select(0 if r.slice == "vertical" else 1)
		_fields["freeform"].set_pressed_no_signal(r.freeform)
		_freeform_box.visible = r.freeform
		_fields["angle_label"].text = "Left face angle (°)" if r.freeform else "Slope angle (°)"
		_fields["face_length_label"].text = "Left face length (m)" if r.freeform else "Face length (m)"
		for key in ["angle", "face_length", "base_depth", "detail", "angle_right", "face_length_right"]:
			_set_field(key, r.get(key))
		_fields["color"].color = r.color
		_fields["look"].select(Look.LOOK_ORDER.find(r.look))
		_fields["color_label"].text = "Colour (%s)" % Look.RAMP_LOOKS[r.look][2]
		_tex_box.visible = r.look == "texture"
		_fields["tex_name"].text = r.texture.get_file() if r.texture != "" else "No image chosen (PNG / JPG / WebP)"
		_set_field("tex_scale", r.tex_scale)
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
		_stage_props.visible = e.kind in ["stage", "teleport"]
		_fields["keep_speed"].visible = e.kind == "teleport"
		var num_label: Label = _fields["number"][0].get_parent().get_parent().get_child(_fields["number"][0].get_parent().get_index() - 1)
		num_label.text = "Stage number" if e.kind == "stage" else "Sends the player to stage"
		if e.kind in ["stage", "teleport"]:
			_set_field("number", e.number)
			_fields["keep_speed"].button_pressed = e.keep_speed
		if e.kind == "booster":
			_set_field("pitch", e.pitch)
			_set_field("strength", e.strength)
			_fields["mode"].select(e.mode)
	_updating_ui = false
	_refresh_info()


func _refresh_info() -> void:
	if selected == null:
		var counts := {}
		for e in entities_root.get_children():
			counts[e.kind] = counts.get(e.kind, 0) + 1
		var best_txt := ("\n\nBest run: %s (saved with the map). Its path is drawn in the views; in play mode you race it (G hides it)."
			% PlayMode.format_time(float(best_ghost["time"]))) if not best_ghost.is_empty() else "\n\nNo best run yet: press P and finish a run."
		_info.text = ("Nothing selected - click a ramp or platform in any view to edit it.\n\n"
			+ "Ramps: %d\nStart: %s   Finish: %s\nStages: %d   Teleports: %d\nBoosters: %d   Kill zones: %d"
			% [ramps_root.get_child_count(), "yes" if counts.has("start") else "missing", "yes" if counts.has("finish") else "missing",
				counts.get("stage", 0), counts.get("teleport", 0), counts.get("booster", 0), counts.get("kill", 0)]) + best_txt
		return
	if selected is RampNode:
		var r := selected as RampNode
		var faces := []
		if r.style != "half_right":
			faces.append(["left" if r.freeform or r.style != "v" else "", r.angle])
		if r.style == "half_right" or (r.style == "v" and r.freeform):
			faces.append(["right", r.angle_right])
		var face_text := ""
		for f in faces:
			var ok: bool = f[1] > 45.6 and f[1] < 89.5
			face_text += "\nFace angle%s: %.1f° (%s)" % [(" (" + f[0] + ")") if f[0] != "" else "", f[1],
				"surfable" if ok else ("too flat: players will stand on it" if f[1] <= 45.6 else "too steep")]
		var drop := r.points[0].y - r.points[r.points.size() - 1].y
		_info.text = ("%sLength: %.0f m\n%s\nWidth: %.1f m edge to edge%s\nControl points: %d\nTriangles: %d"
			% ["FREEFORM is on: the upright rules are off for this ramp.\n\n" if r.freeform else "", r.length,
				("Drop: %.0f m" % drop) if drop >= 0.0 else ("Climbs %.0f m (riders lose speed going up it)" % -drop),
				r.geometry_width(), face_text, r.points.size(), r.triangle_count])
		if not r.folds.is_empty():
			_info.text = ("⚠ The bend is too tight for this face width in %d place(s): the inner edge folds over"
				+ " (marked red). Widen the bend, or shorten the face.\n\n") % r.folds.size() + _info.text
		for a in _arcs:
			if a["ramp"] == r:
				_info.text += ("\n\nJump off the end (from %s): ≈ %d u/s\n  full speed: %s\n  at %d%% speed: %s\n(no air strafing: good players can stretch this)"
					% [a["ref"], roundi(a["speed"] * JumpCheck.U), a["runs"][0]["label"], roundi(SLOPPY * 100), a["runs"][1]["label"]])
	elif selected is BlockNode:
		var b := selected as BlockNode
		var sz: Vector3 = b.size()
		_info.text = ("%s\nSize: %.2f x %.2f x %.2f m\nPosition: (%.1f, %.1f, %.1f)\nPieces: %d (each is one brush in a CS:S export)\n\n%s" % [
			BlockShape.LABELS[b.data["shape"]] + (" (hollow)" if b.data["hollow"] else ""), sz.x, sz.y, sz.z,
			b.global_position.x, b.global_position.y, b.global_position.z, b.pieces.size(),
			"CUTTER: cuts a hole wherever it overlaps a block. Move it and the hole moves. It isn't exported itself."
				if b.is_cutter() else "Drag the small squares on its sides to resize it; drag the block itself to move it."])
	elif selected is PropNode:
		var pr := selected as PropNode
		var sz := pr.world_size()
		_info.text = ("%sModel: %s\nSize: %.1f x %.1f x %.1f m\nTriangles: %d\nPosition: (%.0f, %.0f, %.0f)\n\n%s"
			% [("⚠ " + pr.error + "\n\n") if pr.error != "" else "", pr.source.get_file(), sz.x, sz.y, sz.z, pr.triangles,
				pr.position.x, pr.position.y, pr.position.z,
				"Solid: players (and jump arcs) hit it." if pr.solid else "Decoration: players fly straight through it."])
		if pr.triangles > 200000:
			_info.text += "\n\nThat's a heavy model: it may slow the game down. Consider a simpler version."
	else:
		var e := selected as EntityNode
		var about := {
			"start": "Players spawn here facing the arrow. The timer starts when they leave the green zone.",
			"finish": "Landing in the blue zone finishes the run.",
			"kill": "Touching this sends the player back to their spawn. Players fly through it; it is invisible in game.",
			"booster": "Players passing through are pushed along the arrow. Add = extra speed on top of theirs; Set = this exact speed.",
			"stage": "Stage checkpoint: reaching this plate (landing on it or being teleported here) makes it the player's respawn point and records a split. Players spawn here facing the arrow.",
			"teleport": "Sends the player to the stage plate with this number. Keep speed: they arrive still moving (same direction of travel); off: they arrive standing still.",
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
	maximise_pane(hovered)


## Fill the editor with `pane`, or (if one view already fills it) go back to four views.
func maximise_pane(pane: ViewPane) -> void:
	var maximised: bool = panes.filter(func(p): return p.visible).size() == 1
	for p in panes:
		p.visible = maximised or p == pane
	_view_grid.columns = 2 if maximised else 1
	quad_view = maximised
	active_pane = pane
	_set_status("Four views" if maximised else "%s view - Space to go back to four views" % ViewPane.NAMES[pane.kind].get_slice(" ", 0))


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
	var ps := []
	for pr in props_root.get_children():
		ps.append(pr.to_dict())
	var bs := []
	for b in blocks_root.get_children():
		bs.append(b.to_dict())
	return {"format": MAP_FORMAT, "version": MAP_VERSION, "environment": environment.duplicate(), "ramps": rs, "entities": es,
		"props": ps, "blocks": bs}


func _load_dict(data: Dictionary) -> void:
	_gen_ramp = null
	_gen_source = null
	environment = Look.default_environment()
	environment.merge(data.get("environment", {}), true)
	_apply_environment()
	_select(null)
	for root in [ramps_root, entities_root, props_root, blocks_root]:
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
	for pd in data.get("props", []):
		var pr := PropNode.new()
		props_root.add_child(pr)
		pr.from_dict(pd)
	for bd in data.get("blocks", []):
		var b := BlockNode.new()
		blocks_root.add_child(b)
		b.from_dict(bd)
	_rebuild_blocks()


func _new_map() -> void:
	_load_dict({})
	best_ghost = {}
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
	return ramps_root.get_children() + entities_root.get_children() + props_root.get_children() + blocks_root.get_children()


# ================================================================================================= undo / redo
## Call before any change. `key` lets rapid repeats of the same edit (slider drags) share one undo step.
func _checkpoint(key := "") -> void:
	_map_changed()
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
	_map_changed()
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
	_map_changed()
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


## Arrows along a ramp's spine pointing from its first point to its last, spaced evenly on screen; the selected
## ramp also gets "ramp start" / "ramp end" markers. Drawn in the views only: nothing here reaches the map.
func _draw_direction(cam: Camera3D, ov: Control, r: RampNode, is_selected: bool) -> void:
	var ridge := r.ridge
	var n := ridge.size()
	if n < 2:
		return
	var tans: PackedVector3Array = r.geometry.get("tan", PackedVector3Array())
	var col := Color(1, 1, 1, 0.95) if is_selected else Color(1, 1, 1, 0.4)
	var size := 12.0 if is_selected else 8.0
	var gap := 90.0 if is_selected else 120.0
	var travelled := gap * 0.5                         # first arrow half a gap in from the start
	var prev_s := Vector2.INF
	for i in n:
		if cam.is_position_behind(ridge[i]):
			prev_s = Vector2.INF
			continue
		var sp := cam.unproject_position(ridge[i])
		if prev_s != Vector2.INF:
			travelled += sp.distance_to(prev_s)
		prev_s = sp
		if travelled < gap or i == 0 or i == n - 1:
			continue
		var t: Vector3 = tans[i] if i < tans.size() else (ridge[i] - ridge[i - 1]).normalized()
		var ahead := ridge[i] + t * 2.0
		if cam.is_position_behind(ahead):
			continue
		var d := cam.unproject_position(ahead) - sp
		if d.length() < 0.5:                            # travelling straight at or away from this view
			continue
		travelled = 0.0
		d = d.normalized()
		var perp := Vector2(-d.y, d.x)
		var tip := sp + d * size * 0.6
		for w in [Color(0, 0, 0, col.a * 0.8), col]:
			var thick := 4.0 if w.r == 0.0 else 2.0
			ov.draw_line(tip, tip - d * size + perp * size * 0.7, w, thick)
			ov.draw_line(tip, tip - d * size - perp * size * 0.7, w, thick)
	if not is_selected:
		return
	var font := ov.get_theme_default_font()
	for end in [[r.points[0], "ramp start", Color(0.45, 1.0, 0.55)], [r.points[r.points.size() - 1], "ramp end", Color(1.0, 0.5, 0.45)]]:
		var p: Vector3 = end[0]
		if cam.is_position_behind(p):
			continue
		var at := cam.unproject_position(p)
		ov.draw_arc(at, 12.0, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 4.0)
		ov.draw_arc(at, 12.0, 0.0, TAU, 24, end[2], 2.0)
		ov.draw_string_outline(font, at + Vector2(16, 18), end[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, at + Vector2(16, 18), end[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, end[2])


func _draw_lines(cam: Camera3D, ov: Control, lines: Array, col: Color, width: float) -> void:
	for line in lines:
		for i in range(1, line.size()):
			if cam.is_position_behind(line[i]) or cam.is_position_behind(line[i - 1]):
				continue
			ov.draw_line(cam.unproject_position(line[i - 1]), cam.unproject_position(line[i]), col, width)


## A small padlock icon centred on `at`.
func _draw_padlock(ov: Control, at: Vector2, col: Color) -> void:
	for pass_col in [Color(0, 0, 0, 0.8), col]:
		var grow := 1.5 if pass_col.a > 0.75 and pass_col.r == 0.0 else 0.0
		ov.draw_arc(at + Vector2(0, -2), 4.0, PI, TAU, 10, pass_col, 2.0 + grow * 2.0)
		ov.draw_rect(Rect2(at + Vector2(-6 - grow, -2 - grow), Vector2(12 + grow * 2, 9 + grow * 2)), pass_col, true)


## The best run's path, coloured by speed: blue slow -> green -> yellow -> red at its top speed.
func _draw_ghost_path(cam: Camera3D, ov: Control) -> void:
	var s: Array = best_ghost.get("samples", [])
	var n := s.size() / 4
	var top := 1.0
	for i in n:
		top = maxf(top, s[i * 4 + 3])
	var prev := Vector2.INF
	for i in n:
		var p := Vector3(s[i * 4], s[i * 4 + 1], s[i * 4 + 2]) + Vector3(0, 0.9, 0)
		if cam.is_position_behind(p):
			prev = Vector2.INF
			continue
		var sp := cam.unproject_position(p)
		if prev != Vector2.INF:
			var f: float = s[i * 4 + 3] / top
			var col := Color.from_hsv(lerpf(0.62, 0.0, f), 0.85, 1.0, 0.9)
			ov.draw_line(prev, sp, col, 3.0)
		prev = sp
	var end := Vector3(s[(n - 1) * 4], s[(n - 1) * 4 + 1], s[(n - 1) * 4 + 2]) + Vector3(0, 3, 0)
	if n > 0 and not cam.is_position_behind(end):
		var font := ov.get_theme_default_font()
		var at := cam.unproject_position(end)
		var t := "best run  " + PlayMode.format_time(float(best_ghost.get("time", 0.0)))
		ov.draw_string_outline(font, at + Vector2(-40, -8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, at + Vector2(-40, -8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.9, 1.0))


func _redraw_overlays() -> void:
	for p in panes:
		p.overlay.queue_redraw()


func _build_lock_props() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_ramp_props.add_child(box)
	var head := Label.new()
	head.text = "Sections (locking)"
	head.add_theme_font_size_override("font_size", 15)
	box.add_child(head)
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	info.add_theme_font_size_override("font_size", 13)
	box.add_child(info)
	_fields["lock_info"] = info
	var row := HBoxContainer.new()
	box.add_child(row)
	var lock := Button.new()
	lock.focus_mode = Control.FOCUS_NONE
	lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lock.pressed.connect(_lock_clicked)
	row.add_child(lock)
	_fields["lock_btn"] = lock
	var unlock := Button.new()
	unlock.focus_mode = Control.FOCUS_NONE
	unlock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlock.pressed.connect(_unlock_clicked)
	row.add_child(unlock)
	_fields["unlock_btn"] = unlock
	var seam := CheckButton.new()
	seam.text = "Tangent lock at seam"
	seam.focus_mode = Control.FOCUS_NONE
	seam.tooltip_text = "On: the editable section leaves the seam in exactly the locked section's direction (no kink). Off: it follows its own points, which can leave a crease."
	seam.toggled.connect(func(on): _edit_prop("seam_tangent_lock", on))
	box.add_child(seam)
	_fields["seam_lock"] = seam
	var warn := Label.new()
	warn.text = "⚠ Tangent lock is off: the ramp can kink at the seam, which riders feel as a bump."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	box.add_child(warn)
	_fields["seam_warn"] = warn
	box.add_child(HSeparator.new())
	_unlock_confirm = ConfirmationDialog.new()
	_unlock_confirm.title = "Unlock"
	_unlock_confirm.ok_button_text = "Unlock them"
	_unlock_confirm.confirmed.connect(func(): _do_unlock(_pending_unlock))
	_ui.add_child(_unlock_confirm)


func _refresh_lock_props(r: RampNode) -> void:
	var n := r.frozen.size()
	var sp := selected_point
	var text := ""
	if n == 0:
		text = "Select a point and lock it (L) to freeze the ramp up to there. Everything after it becomes a new section you can reshape freely - the locked part never changes."
	else:
		text = "%d locked section%s (grey) + the editable section (blue). Points up to %d are frozen; the orange line is the seam. Slope angle and face length now only change the editable section; they blend in from the seam." % [
			n, "" if n == 1 else "s", r.lock_index()]
	_fields["lock_info"].text = text
	var lock_btn: Button = _fields["lock_btn"]
	var problem := r.lock_problem(sp) if sp >= 0 else "Select a point first (click its yellow handle)."
	lock_btn.text = "🔒 Lock at point %d" % sp if sp >= 0 else "🔒 Lock at a point"
	lock_btn.disabled = problem != ""
	lock_btn.tooltip_text = problem if problem != "" else "Freeze the ramp from its start up to this point (L)."
	var unlock_btn: Button = _fields["unlock_btn"]
	var k := r.lock_number(sp) if sp >= 0 else -1
	unlock_btn.visible = n > 0
	unlock_btn.text = "Unlock point %d" % sp if k >= 0 else "Unlock the last lock"
	unlock_btn.tooltip_text = ("Also unlocks the %d lock(s) after it." % (n - 1 - k)) if k >= 0 and k < n - 1 else "Merge the last locked section back into the editable one."
	_fields["seam_lock"].visible = n > 0
	_fields["seam_lock"].set_pressed_no_signal(r.seam_tangent_lock)
	_fields["seam_warn"].visible = n > 0 and not r.seam_tangent_lock
	# settings that shape the whole ramp would change the locked part too
	for key in RAMP_WIDE:
		var f = _fields[key]
		if f is Array:
			f[0].editable = n == 0
			f[1].editable = n == 0
		elif f is BaseButton:
			f.disabled = n > 0
		elif f is OptionButton:
			f.disabled = n > 0
	_fields["freeform"].tooltip_text = "Unlock the ramp to change this: it shapes every section." if n > 0 else \
		"Off: both faces match. On: the right face can have its own angle and length."


func _lock_clicked() -> void:
	if not selected is RampNode:
		return
	var r := selected as RampNode
	var problem := r.lock_problem(selected_point) if selected_point >= 0 else "Select a point first (click its yellow handle)."
	if problem != "":
		_set_status(problem)
		return
	_checkpoint()
	r.lock_at(selected_point)
	_refresh_props()
	_map_changed()
	_set_status("Locked at point %d: everything before it is frozen. The ramp after it is a new section - reshape it freely." % selected_point)


func _unlock_clicked() -> void:
	if not selected is RampNode or selected.frozen.is_empty():
		return
	var r := selected as RampNode
	var k := r.lock_number(selected_point) if selected_point >= 0 else -1
	if k < 0:
		k = r.frozen.size() - 1
	if k < r.frozen.size() - 1:
		_pending_unlock = k
		_unlock_confirm.dialog_text = "Unlocking point %d also unlocks the %d lock(s) after it, merging those sections back into the editable one.\n\n(Undo brings them back.)" % [
			int(r.frozen[k]["end"]), r.frozen.size() - 1 - k]
		_unlock_confirm.popup_centered()
		return
	_do_unlock(k)


func _do_unlock(k: int) -> void:
	if not selected is RampNode or k < 0:
		return
	var r := selected as RampNode
	var at := int(r.frozen[k]["end"])
	_checkpoint()
	r.unlock_from(k)
	_refresh_props()
	_map_changed()
	_set_status("Unlocked from point %d: that part is editable again (it takes the editable section's slope and face)." % at)


## Presentation mode (for videos and screenshots): only the 3D view, no toolbar, panel or status line.
func set_presentation(on: bool) -> void:
	_fields["toolbar"].visible = not on
	_props_panel.visible = not on
	_status.get_parent().visible = not on if _status.get_parent() is PanelContainer else true
	_status.visible = not on
	for i in panes.size():
		panes[i].visible = (i == 0) if on else (quad_view or i == 0)
	_view_grid.columns = 1 if on else (2 if quad_view else 1)


func _set_title(map_name: String) -> void:
	get_window().title = SurfForgeVersion.full() + ("  -  " + map_name if map_name != "" else "")


## F11: fullscreen (no title bar - handy for recording) and back.
func _toggle_fullscreen() -> void:
	var w := get_window()
	w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	_set_status("Fullscreen - F11 to go back" if w.mode == Window.MODE_FULLSCREEN else "Windowed")


## L: lock the selected point, or unlock it if it already is a lock.
func _lock_toggle() -> void:
	if not selected is RampNode:
		return
	if selected_point >= 0 and selected.is_locked_point(selected_point):
		_unlock_clicked()
	else:
		_lock_clicked()


func _build_prop_props(props: VBoxContainer) -> void:
	_prop_props = VBoxContainer.new()
	_prop_props.add_theme_constant_override("separation", 6)
	_prop_props.visible = false
	props.add_child(_prop_props)
	var file := Label.new()
	file.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_prop_props.add_child(file)
	_fields["prop_file"] = file
	var replace := Button.new()
	replace.text = "Replace model…"
	replace.focus_mode = Control.FOCUS_NONE
	replace.pressed.connect(func(): _prop_replace = true; _prop_dialog.popup_centered_ratio(0.6))
	_prop_props.add_child(replace)
	_add_slider(_prop_props, "prop_size", "Size (x)", 0.05, 50.0, 0.05)
	_add_slider(_prop_props, "prop_yaw", "Facing (°)", -180.0, 180.0, 5.0)
	var solid := CheckButton.new()
	solid.text = "Solid (players collide with it)"
	solid.focus_mode = Control.FOCUS_NONE
	solid.toggled.connect(func(on): _edit_prop("prop_solid", on))
	_prop_props.add_child(solid)
	_fields["prop_solid"] = solid
	var tip := Label.new()
	tip.text = "glTF models (.glb / .gltf) from Blender, Sketchfab, Kenney, etc. Only the meshes, materials and textures are used. Drag to move, [ ] to turn."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	_prop_props.add_child(tip)
	_prop_dialog = FileDialog.new()
	_prop_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_prop_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_prop_dialog.use_native_dialog = true
	_prop_dialog.filters = PackedStringArray(["*.glb, *.gltf ; glTF model"])
	_prop_dialog.file_selected.connect(_on_prop_file)
	_ui.add_child(_prop_dialog)


func _add_prop_clicked() -> void:
	_prop_replace = false
	_prop_dialog.popup_centered_ratio(0.6)


func _on_prop_file(path: String) -> void:
	if _prop_replace and selected is PropNode:
		_checkpoint()
		PropLoader.forget(path)
		selected.source = path
		selected.rebuild()
		_refresh_props()
		_set_status("Model replaced with %s." % path.get_file())
		return
	add_prop(path, _view_center())


## Place a model at `at` (standing on that point).
func add_prop(path: String, at: Vector3) -> PropNode:
	_checkpoint()
	PropLoader.forget(path)                             # pick up changes if the file was re-exported
	var pr := PropNode.new()
	props_root.add_child(pr)
	pr.from_dict({"source": path, "position": [at.x, at.y, at.z]})
	_select(pr)
	_set_status(("Couldn't load the model: " + pr.error) if pr.error != "" else
		"Added %s (%.0f m tall). Drag to place it, [ ] to turn, Size in the panel." % [path.get_file(), pr.world_size().y])
	return pr


# ------------------------------------------------------------------------------------------------ blocks
func _build_block_props(props: VBoxContainer) -> void:
	_block_props = VBoxContainer.new()
	_block_props.add_theme_constant_override("separation", 6)
	_block_props.visible = false
	props.add_child(_block_props)
	var shape := OptionButton.new()
	for k in BlockShape.SHAPES:
		shape.add_item(BlockShape.LABELS[k])
	shape.focus_mode = Control.FOCUS_NONE
	shape.item_selected.connect(func(i): _edit_prop("block_shape", BlockShape.SHAPES[i]))
	_add_row(_block_props, "Shape", shape)
	_fields["block_shape"] = shape
	_add_slider(_block_props, "block_x", "Width (m)", 0.25, 500.0, 0.25)
	_add_slider(_block_props, "block_y", "Height (m)", 0.25, 500.0, 0.25)
	_add_slider(_block_props, "block_z", "Depth (m)", 0.25, 500.0, 0.25)
	_add_slider(_block_props, "block_yaw", "Facing (\u00b0)", -180.0, 180.0, 5.0)
	var sides_box := VBoxContainer.new()
	_block_props.add_child(sides_box)
	_add_slider(sides_box, "block_sides", "Sides (smoothness)", 3.0, 64.0, 1.0)
	_fields["block_sides_box"] = sides_box
	var steps_box := VBoxContainer.new()
	_block_props.add_child(steps_box)
	_add_slider(steps_box, "block_steps", "Steps", 2.0, 64.0, 1.0)
	_fields["block_steps_box"] = steps_box
	var hollow := CheckButton.new()
	hollow.text = "Hollow (a room with walls)"
	hollow.focus_mode = Control.FOCUS_NONE
	hollow.toggled.connect(func(on): _edit_prop("block_hollow", on))
	_block_props.add_child(hollow)
	_fields["block_hollow"] = hollow
	var wall_box := VBoxContainer.new()
	_block_props.add_child(wall_box)
	_add_slider(wall_box, "block_wall", "Wall thickness (m)", 0.1, 10.0, 0.1)
	_fields["block_wall_box"] = wall_box
	var cutter := CheckButton.new()
	cutter.text = "Cutter (cuts holes in blocks)"
	cutter.focus_mode = Control.FOCUS_NONE
	cutter.tooltip_text = "A cutter isn't built itself: it cuts its shape out of every block it overlaps - doorways, windows, tunnels. Move it and the hole moves."
	cutter.toggled.connect(func(on): _edit_prop("block_cutter", on))
	_block_props.add_child(cutter)
	_fields["block_cutter"] = cutter
	var look_box := VBoxContainer.new()
	_block_props.add_child(look_box)
	_fields["block_look_box"] = look_box
	var look := OptionButton.new()
	for k in Look.LOOK_ORDER:
		if k != "texture":
			look.add_item(Look.RAMP_LOOKS[k][0])
	look.focus_mode = Control.FOCUS_NONE
	look.item_selected.connect(func(i): _edit_prop("block_look", Look.LOOK_ORDER[i]))
	_add_row(look_box, "Look", look)
	_fields["block_look"] = look
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("block_color", c))
	_add_row(look_box, "Colour", cp)
	_fields["block_color"] = cp


## Blocks are cut by every cutter they overlap, so a change to any block can change others: rebuild them all.
func _mark_blocks() -> void:
	_blocks_dirty = true
	_map_changed()


func _rebuild_blocks() -> void:
	_blocks_dirty = false
	var cutters := []
	for b in blocks_root.get_children():
		if b.is_queued_for_deletion():
			continue
		if b.is_cutter():
			cutters.append(b.data)
	for b in blocks_root.get_children():
		if not b.is_queued_for_deletion():
			b.rebuild(cutters)


func _add_block_clicked() -> void:
	_checkpoint()
	var c := _view_center()
	var d := {"position": [c.x, maxf(c.y - _last_block["size"][1] * 0.5, 0.0), c.z], "size": _last_block["size"].duplicate()}
	if snap_enabled:
		d["position"] = [snappedf(c.x, snap_step), snappedf(d["position"][1], snap_step), snappedf(c.z, snap_step)]
	var b := BlockNode.new()
	blocks_root.add_child(b)
	b.from_dict(d)
	_rebuild_blocks()
	_select(b)
	_set_status("New block. Drag the squares on its sides to resize it, or use Draw block (D) to draw blocks in the 2D views.")


func _toggle_draw_mode() -> void:
	_draw_mode = not _draw_mode
	_set_status("Draw block: drag a rectangle in the Top, Front or Side view. Esc or D to stop." if _draw_mode else "Draw block off.")


func _draw_begin(pane: ViewPane, mouse: Vector2) -> void:
	_checkpoint()
	_draw_pane = pane
	var hit = pane.drag_plane(_view_center(), false).intersects_ray(pane.ray(mouse)[0], pane.ray(mouse)[1])
	if hit == null:
		return
	_draw_start = _snap_axes(hit, pane.drag_axes(false))
	_draw_block = BlockNode.new()
	blocks_root.add_child(_draw_block)
	_draw_update(mouse)


func _draw_update(mouse: Vector2) -> void:
	var pane := _draw_pane
	var hit = pane.drag_plane(_view_center(), false).intersects_ray(pane.ray(mouse)[0], pane.ray(mouse)[1])
	if hit == null or _draw_block == null:
		return
	var a := _draw_start
	var b: Vector3 = _snap_axes(hit, pane.drag_axes(false))
	var axes := pane.drag_axes(false)
	var last: Array = _last_block["size"]
	var lo := a.min(b)
	var hi := a.max(b)
	var size := Vector3(maxf(hi.x - lo.x, 0.25), maxf(hi.y - lo.y, 0.25), maxf(hi.z - lo.z, 0.25))
	var base := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	# the axis the view looks along keeps the last size used (Hammer does the same)
	for i in 3:
		if axes[i] < 0.5:
			size[i] = float(last[i])
			if i == 1:
				base.y = snappedf(_view_center().y - size.y * 0.5, snap_step if snap_enabled else 0.25)
			else:
				base[i] = a[i]
	_draw_block.from_dict({"position": [base.x, base.y, base.z], "size": [size.x, size.y, size.z]})
	_draw_block.rebuild([])
	_set_status("Block %.2f x %.2f x %.2f m" % [size.x, size.y, size.z])


func _draw_end() -> void:
	if _draw_block == null:
		return
	var b := _draw_block
	_draw_block = null
	var sz: Vector3 = b.size()
	if sz.x * sz.z < 1.0 and sz.y * sz.x < 1.0:
		blocks_root.remove_child(b)
		b.queue_free()
		_undo.pop_back()
		return
	_last_block["size"] = b.data["size"].duplicate()
	_rebuild_blocks()
	_select(b)
	_set_status("Block drawn. Keep drawing, or Esc / D to stop.")


func _pick_face(pane: ViewPane, mouse: Vector2) -> int:
	var best := -1
	var best_d := PICK_PIXELS
	var hs: Array = (selected as BlockNode).face_handles()
	for i in hs.size():
		var fh: Array = hs[i]
		if pane.camera.is_position_behind(fh[0]):
			continue
		if pane.is_ortho() and absf((fh[1] as Vector3).dot(-pane.camera.global_basis.z)) > 0.5:
			continue
		var d := pane.camera.unproject_position(fh[0]).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = i
	return best


## Reverse a ramp's direction of travel without moving any of it: the points run the other way, and what was
## the left face is now the right face (half ramps and Freeform faces swap sides to stay where they are).
func _flip_clicked() -> void:
	if not selected is RampNode:
		return
	var r := selected as RampNode
	if not r.frozen.is_empty():
		_set_status("Unlock the ramp first: flipping would change what each lock freezes.")
		return
	_checkpoint()
	var pts := r.points.duplicate()                     # a real copy: reverse() works in place
	pts.reverse()
	r.points = pts
	match r.style:
		"half_left": r.style = "half_right"
		"half_right": r.style = "half_left"
	var a := r.angle
	var l := r.face_length
	r.angle = r.angle_right
	r.face_length = r.face_length_right
	r.angle_right = a
	r.face_length_right = l
	if selected_point >= 0:
		selected_point = pts.size() - 1 - selected_point
	r.rebuild()
	_refresh_props()
	_map_changed()
	_set_status("Direction flipped: the ramp is now ridden the other way (the jump leaves from the other end).")


func _stage_numbers() -> Array:
	return entities_root.get_children().filter(func(x): return x.kind == "stage").map(func(x): return x.number)


func _stage_plate(n: int) -> EntityNode:
	for e in entities_root.get_children():
		if e.kind == "stage" and e.number == n:
			return e
	return null


## Handles and helper lines, drawn in 2D on top of each view so they stay a constant size.
func draw_pane_overlay(pane: ViewPane, ov: Control) -> void:
	if play.active:
		return
	_draw_arcs(pane, ov)
	var cam := pane.camera
	var font := ov.get_theme_default_font()
	for e in entities_root.get_children():       # name tags: Start, Finish, Stage 2, -> Stage 3 ...
		var t: String = e.tag()
		if t == "" or cam.is_position_behind(e.global_position):
			continue
		var s := cam.unproject_position(e.global_position + Vector3(0, 4, 0))
		ov.draw_string_outline(font, s + Vector2(-30, -6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, s + Vector2(-30, -6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, EntityNode.KINDS[e.kind]["color"].lightened(0.35))
	for r in ramps_root.get_children():                  # too-tight bends, on every ramp
		for line in r.fold_lines:
			for i in range(1, line.size()):
				if cam.is_position_behind(line[i]) or cam.is_position_behind(line[i - 1]):
					continue
				ov.draw_line(cam.unproject_position(line[i - 1]), cam.unproject_position(line[i]), Color(1.0, 0.15, 0.1, 0.95), 3.0)
	if show_ghost_path and not best_ghost.is_empty():
		_draw_ghost_path(cam, ov)
	if show_direction:
		for r in ramps_root.get_children():
			_draw_direction(cam, ov, r, r == selected)
	for r in ramps_root.get_children():                  # seams between sections
		_draw_lines(cam, ov, r.seam_lines, Color(1.0, 0.62, 0.15, 0.95 if r == selected else 0.5), 3.0 if r == selected else 2.0)
	if selected == null:
		return
	if selected is EntityNode and selected.kind == "teleport":      # where does this teleport go?
		var target := _stage_plate(selected.number)
		if target and not cam.is_position_behind(target.global_position) and not cam.is_position_behind(selected.global_position):
			var a := cam.unproject_position(selected.global_position)
			var b := cam.unproject_position(target.global_position)
			var segs := 24
			for k in segs:
				if k % 2 == 0:
					ov.draw_line(a.lerp(b, float(k) / segs), a.lerp(b, float(k + 1) / segs), Color(0.85, 0.5, 1.0), 2.0)
	var lines: Array[PackedVector3Array] = selected.outline if selected is RampNode else selected.outline_lines()
	_draw_lines(cam, ov, lines, Color(0.3, 0.75, 1.0, 0.95), 2.0)   # selection outline (keeps the real colour visible)
	if selected is RampNode:                       # the locked part: muted
		_draw_lines(cam, ov, selected.outline_frozen, Color(0.62, 0.64, 0.7, 0.9), 2.0)
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
			var frozen_pt: bool = i <= selected.lock_index()
			var col := Color(1.0, 0.35, 0.1) if i == selected_point else (Color(0.6, 0.62, 0.68) if frozen_pt else Color(1.0, 0.85, 0.15))
			ov.draw_circle(s, HANDLE_RADIUS + 1.5, Color(0, 0, 0, 0.7))
			ov.draw_circle(s, HANDLE_RADIUS, col)
			if selected.is_locked_point(i):
				_draw_padlock(ov, s + Vector2(0, -HANDLE_RADIUS - 12), Color(1.0, 0.62, 0.15))
	elif selected is BlockNode:
		for fh in (selected as BlockNode).face_handles():
			if cam.is_position_behind(fh[0]):
				continue
			# in a 2D view only the sides seen edge-on can be dragged
			if pane.is_ortho() and absf((fh[1] as Vector3).dot(-cam.global_basis.z)) > 0.5:
				continue
			var s := cam.unproject_position(fh[0])
			ov.draw_rect(Rect2(s - Vector2(6, 6), Vector2(12, 12)), Color(0, 0, 0, 0.75), true)
			ov.draw_rect(Rect2(s - Vector2(4.5, 4.5), Vector2(9, 9)), Color(1.0, 0.85, 0.15), true)
	else:
		var e: Node3D = selected
		if not cam.is_position_behind(e.global_position):
			var s := cam.unproject_position(e.global_position)
			ov.draw_rect(Rect2(s - Vector2(6, 6), Vector2(12, 12)), Color(1, 0.85, 0.15), true)
			ov.draw_rect(Rect2(s - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7), false, 1.5)


func _process(delta: float) -> void:
	_poll_css()
	if _blocks_dirty:
		_rebuild_blocks()
	if play.active:
		return
	_arcs_timer -= delta
	if _arcs_dirty > 0 or _arcs_timer <= 0.0:
		_arcs_dirty = max(_arcs_dirty - 1, 0)
		_arcs_timer = 0.5                         # safety refresh; changes trigger an immediate update
		_update_arcs()


## Anything that changes the map calls this so the jump arcs follow instantly.
func _map_changed() -> void:
	_arcs_dirty = 2


## Where the speed for a ramp comes from: the start or stage plate the rider most likely set off from - the
## nearest plate that is above this ramp's start. Returns [height, speed m/s, name].
func _speed_reference(r: RampNode) -> Array:
	var best: Array = []
	var best_cost := INF
	for e in entities_root.get_children():
		if not e.kind in ["start", "stage"]:
			continue
		var above: float = e.position.y - r.points[0].y
		if above < -2.0:
			continue
		var cost: float = above + Vector2(e.position.x - r.points[0].x, e.position.z - r.points[0].z).length() * 0.25
		if cost < best_cost:
			best_cost = cost
			best = [e.position.y, JumpCheck.START_SPEED, e.label().to_lower()]
	if best.is_empty():
		best = [r.points[0].y, JumpCheck.START_SPEED, "the ramp's own start"]
	return best


func _update_arcs() -> void:
	_arcs.clear()
	var targets: Array = ramps_root.get_children() if show_all_arcs else ([selected] if selected is RampNode else [])
	if _gen_source and is_instance_valid(_gen_source) and not _gen_source in targets:
		targets.append(_gen_source)
	if targets.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var volumes := entities_root.get_children().filter(func(x): return x.is_volume())
	var kill_y := SurfsUpExporter.kill_floor_y(_map_dict())
	var zones := []                                  # entering the finish / a stage zone counts, like in game
	for e in entities_root.get_children():
		if e.kind in ["finish", "stage"]:
			zones.append([e.zone_aabb(), "reaches the " + e.label().to_lower() + (" zone" if e.kind == "finish" else ""), e])
	for r in targets:
		if r.ridge.size() < 2:
			continue
		var ref := _speed_reference(r)
		var ex := JumpCheck.exit_of(r.ridge)
		var speed := JumpCheck.speed_at(ref[0], ref[1], ex[0].y)
		var runs := []
		for f in [1.0, SLOPPY]:
			runs.append(JumpCheck.fly(space, ex[0], ex[1] * speed * f, volumes, kill_y, [r._body.get_rid()], zones))
		_arcs.append({"ramp": r, "speed": speed, "ref": ref[2], "runs": runs})
	if selected is RampNode:
		_refresh_info()


func _draw_arcs(pane: ViewPane, ov: Control) -> void:
	var cam := pane.camera
	for a in _arcs:
		for k in a["runs"].size():
			var run: Dictionary = a["runs"][k]
			var ok := JumpCheck.good(run["outcome"])
			var col := Color(0.35, 1.0, 0.45) if ok else Color(1.0, 0.3, 0.25)
			if k == 1:
				col = col.darkened(0.25)
				col.a = 0.75
			var pts: PackedVector3Array = run["points"]
			for i in range(1, pts.size()):
				if cam.is_position_behind(pts[i]) or cam.is_position_behind(pts[i - 1]):
					continue
				if k == 1 and i % 2 == 0:
					continue                                 # the sloppy arc is dashed
				ov.draw_line(cam.unproject_position(pts[i - 1]), cam.unproject_position(pts[i]), col, 2.0 if k == 0 else 1.5)
			var end: Vector3 = run["hit_point"]
			if not cam.is_position_behind(end):
				ov.draw_circle(cam.unproject_position(end), 4.0 if k == 0 else 3.0, col)


# ================================================================================================= view input
## Mouse input from a view (after its own camera navigation). Returns true if used.
func pane_input(pane: ViewPane, event: InputEvent) -> bool:
	if play.active:
		return false
	if _gen_ramp and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_set_status("Generating a ramp: press Create (Enter) to keep it or Cancel (Esc) first.")
		return true
	if _draw_mode and pane.is_ortho() and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_draw_begin(pane, event.position)
		else:
			_draw_end()
		return true
	if _draw_mode and _draw_block and event is InputEventMouseMotion and pane == _draw_pane:
		_draw_update(event.position)
		return true
	if selected is BlockNode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var f := _pick_face(pane, event.position)
		if f >= 0:
			_face = f
			_begin_drag(pane, Drag.FACE, event.position, false)
			return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.double_click and selected is RampNode:
				_insert_point_at_mouse(pane, event.position)
				return true
			var hp := _pick_handle(pane, event.position)
			if hp >= 0 and hp <= (selected as RampNode).lock_index():
				selected_point = hp                       # select it (to unlock), but it can't move
				_refresh_props()
				_set_status("Point %d is locked%s." % [hp, " (a lock point: press L or Unlock to free it)" if selected.is_locked_point(hp)
					else ": it's part of a locked section"])
				return true
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
	if welcome.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			welcome.hide()
			get_viewport().set_input_as_handled()
		return
	if play.handle_input(event):
		return
	if _gen_ramp and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: _gen_create()
			KEY_ESCAPE: _gen_cancel()
			KEY_F: _frame_clicked()
			KEY_SPACE: _toggle_maximise_hovered()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _draw_mode:
		_toggle_draw_mode()
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
		KEY_O: _add_block_clicked()
		KEY_D when not ctrl: _toggle_draw_mode()
		KEY_F11: _toggle_fullscreen()
		KEY_I: _add_prop_clicked()
		KEY_L: _lock_toggle()
		KEY_R: _generate_clicked()
		KEY_B: _add_entity("start")
		KEY_M: _add_entity("finish")
		KEY_K: _add_entity("kill")
		KEY_J: _add_entity("booster")
		KEY_T: _add_entity("stage")
		KEY_Y: _add_entity("teleport")
		KEY_P: _play_clicked()
		KEY_SPACE: _toggle_maximise_hovered()
		KEY_DELETE, KEY_BACKSPACE: _delete_clicked()
		KEY_F: _frame_clicked()
		KEY_G:
			_fields["snap_button"].button_pressed = not snap_enabled
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
		if hit.collider.has_meta("prop"):
			return hit.collider.get_meta("prop")
		if hit.collider.has_meta("block"):
			return hit.collider.get_meta("block")
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
	if _drag == Drag.FACE:
		return selected.face_handles()[_face][0]
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
	_map_changed()
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
	if _drag == Drag.FACE:
		var fh: Array = (selected as BlockNode).face_handles()[_face]
		var amount: float = (hit - _drag_start_hit).dot(fh[1])
		if snap_enabled:
			amount = snappedf(amount, snap_step)
		selected.from_dict(BlockNode.resized(_drag_origin, fh[2], fh[3], amount))
		_last_block["size"] = selected.data["size"].duplicate()
		_mark_blocks()
		var sz: Vector3 = selected.size()
		_set_status("Size %.2f x %.2f x %.2f m" % [sz.x, sz.y, sz.z])
		_refresh_props()
		return
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
		if selected is BlockNode:
			_mark_blocks()
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
	if best["span"] < ramp.lock_index():
		_set_status("That part of the ramp is locked: unlock it to add points there.")
		return
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
	if selected is RampNode and selected_point >= 0 and selected_point <= selected.lock_index():
		_set_status("Point %d is locked." % selected_point)
		return
	_checkpoint("nudge")
	if selected is RampNode and selected_point >= 0:
		var pts: PackedVector3Array = selected.points
		pts[selected_point] += d
		selected.points = pts
		selected.rebuild()
	else:
		selected.translate_by(d)
	if selected is BlockNode:
		_mark_blocks()
	_refresh_info()
	_set_status("Nudged %s" % ["point" if selected is RampNode and selected_point >= 0 else "object"])


func _rotate_selected(deg: float) -> void:
	if selected == null:
		return
	_checkpoint("rotate")
	selected.rotate_by(deg)
	if selected is BlockNode:
		_mark_blocks()
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


# ================================================================================================= ramp generator
func _build_gen_props(props: VBoxContainer) -> void:
	_gen_props = VBoxContainer.new()
	_gen_props.add_theme_constant_override("separation", 6)
	_gen_props.visible = false
	props.add_child(_gen_props)
	var grid := GridContainer.new()
	grid.columns = 3
	_gen_props.add_child(grid)
	var group := ButtonGroup.new()
	for shape in RampGenerator.SHAPE_ORDER:
		var b := Button.new()
		b.text = RampGenerator.SHAPES[shape]["label"]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _gen_set_shape(shape))
		grid.add_child(b)
		_gen_shape_buttons[shape] = b
	_gen_about = Label.new()
	_gen_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gen_about.add_theme_color_override("font_color", Color(0.72, 0.76, 0.82))
	_gen_props.add_child(_gen_about)
	_gen_param_box = VBoxContainer.new()
	_gen_param_box.add_theme_constant_override("separation", 6)
	_gen_props.add_child(_gen_param_box)
	_gen_props.add_child(HSeparator.new())
	_gen_place_box = VBoxContainer.new()
	_gen_place_box.add_theme_constant_override("separation", 6)
	_gen_props.add_child(_gen_place_box)
	var follow := CheckButton.new()
	follow.text = "Continue from the selected ramp"
	follow.focus_mode = Control.FOCUS_NONE
	follow.toggled.connect(func(on): _gen_follow = on; _gen_refresh_place(); _gen_rebuild())
	_gen_place_box.add_child(follow)
	_fields["gen_follow"] = follow
	var follow_opts := VBoxContainer.new()
	follow_opts.add_theme_constant_override("separation", 6)
	_gen_place_box.add_child(follow_opts)
	_fields["gen_follow_opts"] = follow_opts
	_gen_slider(follow_opts, "Jump gap (m)", 5.0, 150.0, 1.0, _gen_gap, func(v): _gen_gap = v; _gen_rebuild())
	var face := OptionButton.new()
	face.add_item("Land on the right-hand face")
	face.add_item("Land on the left-hand face")
	face.focus_mode = Control.FOCUS_NONE
	face.item_selected.connect(func(i): _gen_side = 1.0 if i == 0 else -1.0; _gen_rebuild())
	_add_row(follow_opts, "Landing", face)
	_gen_warning = Label.new()
	_gen_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gen_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_gen_props.add_child(_gen_warning)
	var row := HBoxContainer.new()
	_gen_props.add_child(row)
	var ok := Button.new()
	ok.text = "Create (Enter)"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_gen_create)
	row.add_child(ok)
	var cancel := Button.new()
	cancel.text = "Cancel (Esc)"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_gen_cancel)
	row.add_child(cancel)
	var tip := Label.new()
	tip.text = "The result is an ordinary ramp: drag its points, change its width, look or smoothness afterwards."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 12)
	tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	_gen_props.add_child(tip)


func _gen_slider(parent: Container, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.value = value
	box.custom_minimum_size = Vector2(86, 0)
	s.value_changed.connect(func(v): box.set_value_no_signal(v); on_change.call(v))
	box.value_changed.connect(func(v): s.set_value_no_signal(v); on_change.call(v))
	row.add_child(s)
	row.add_child(box)
	_add_row(parent, label, row)


func _generate_clicked() -> void:
	if play.active or _gen_ramp:
		return
	_gen_source = selected if selected is RampNode else null
	_checkpoint()                                       # Cancel pops this again
	var r := RampNode.new()
	if _gen_source:                                     # carry the course's style on
		for key in ["style", "angle", "face_length", "angle_right", "face_length_right", "slice", "freeform", "detail",
				"solid", "base_depth", "color", "look", "texture", "tex_scale"]:
			r.set(key, _gen_source.get(key))
	# fallback placement: the middle of the 3D view, heading the way the camera looks
	var cam := panes[0].camera as OrbitCamera
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 1e-3 else Vector3.FORWARD
	_gen_anchor = _view_center()
	_gen_anchor.y = maxf(_gen_anchor.y, 120.0)
	_gen_anchor_yaw = rad_to_deg(atan2(-fwd.x, -fwd.z))
	_gen_follow = _gen_source != null
	_fields["gen_follow"].set_pressed_no_signal(_gen_follow)
	_fields["gen_follow"].disabled = _gen_source == null
	_gen_ramp = r
	ramps_root.add_child(r)
	_gen_set_shape(_gen_shape)
	_select(r)
	_set_status("Pick a shape and drag the sliders - the ramp updates as you go. Enter keeps it, Esc throws it away.")


func _gen_set_shape(shape: String) -> void:
	_gen_shape = shape
	_gen_shape_buttons[shape].set_pressed_no_signal(true)
	_gen_about.text = RampGenerator.SHAPES[shape]["about"]
	var vals: Dictionary = _gen_values.get(shape, {})
	var defaults := RampGenerator.defaults(shape)
	for k in defaults:
		if not vals.has(k):
			vals[k] = defaults[k]
	_gen_values[shape] = vals
	for c in _gen_param_box.get_children():
		_gen_param_box.remove_child(c)
		c.queue_free()
	for p in RampGenerator.params(shape):
		var key: String = p[0]
		if p[2] == 0.0 and p[3] == 1.0 and p[4] == 1.0:  # an on/off choice
			var cb := CheckButton.new()
			cb.text = p[1]
			cb.focus_mode = Control.FOCUS_NONE
			cb.button_pressed = vals[key] >= 0.5
			cb.toggled.connect(func(on): vals[key] = 1.0 if on else 0.0; _gen_rebuild())
			_gen_param_box.add_child(cb)
		else:
			_gen_slider(_gen_param_box, p[1], p[2], p[3], p[4], vals[key], func(v): vals[key] = v; _gen_rebuild())
	_gen_refresh_place()
	_gen_rebuild()


func _gen_refresh_place() -> void:
	_fields["gen_follow_opts"].visible = _gen_follow and _gen_source != null


## Where the generated ramp starts and which way it heads.
func _gen_placement() -> Array:
	var r := _gen_ramp
	if _gen_follow and _gen_source and is_instance_valid(_gen_source) and _gen_source.ridge.size() >= 2:
		var ex := JumpCheck.exit_of(_gen_source.ridge)
		var ref := _speed_reference(_gen_source)
		var speed := JumpCheck.speed_at(ref[0], ref[1], ex[0].y) * SLOPPY   # aim so even a sloppy run makes it
		var sp := r.shape_spec()
		var side := RampShape.landing_side(sp, _gen_side)
		var start := JumpCheck.next_ramp_start(ex[0], ex[1], speed, _gen_gap, side, RampShape.face_slope(sp, side))
		return [start, rad_to_deg(atan2(-ex[1].x, -ex[1].z))]
	return [_gen_anchor, _gen_anchor_yaw]


func _gen_rebuild() -> void:
	if _gen_ramp == null:
		return
	var place := _gen_placement()
	var res := RampGenerator.generate(_gen_shape, _gen_values[_gen_shape], place[0], place[1])
	_gen_ramp.points = res["points"]
	_gen_ramp.rebuild()
	var warn := ""
	var crest := RampGenerator.crest_above_start(_gen_ramp.points)
	if crest > 0.0:
		warn = "A crest is %.0f m above the start of the ramp: slow riders may not make it over. Add more drop or lower the waves." % crest
	if not _gen_ramp.folds.is_empty():
		warn += ("\n" if warn != "" else "") + "Too tight for this face width: the inner edge folds (red). Use a bigger radius or fewer bends."
	_gen_warning.text = warn
	_gen_warning.visible = warn != ""
	_map_changed()


func _gen_create() -> void:
	if _gen_ramp == null:
		return
	var r := _gen_ramp
	var label: String = RampGenerator.SHAPES[_gen_shape]["label"]
	_gen_ramp = null
	_gen_source = null
	_select(r)
	_set_status("%s ramp created. Drag its points to fine-tune it; Ctrl+Z takes it away again." % label)


func _gen_cancel() -> void:
	if _gen_ramp == null:
		return
	var r := _gen_ramp
	var src := _gen_source
	_gen_ramp = null
	_gen_source = null
	ramps_root.remove_child(r)
	r.queue_free()
	if not _undo.is_empty():
		_undo.pop_back()                                # the checkpoint taken when the generator opened
	_select(src if src and is_instance_valid(src) else null)
	_set_status("Generator closed, nothing added.")


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
	if kind in ["stage", "teleport"]:
		# new stage plates take the next free number; new teleports point at the highest stage without one
		var stages := _stage_numbers()
		if kind == "stage":
			n.number = (stages.max() + 1) if not stages.is_empty() else 2
		else:
			var targeted := entities_root.get_children().filter(func(x): return x.kind == "teleport").map(func(x): return x.number)
			var free := stages.filter(func(s): return not s in targeted)
			n.number = free.min() if not free.is_empty() else (stages.max() if not stages.is_empty() else 2)
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
	var i: int = clamp(selected_point if selected_point >= 0 else 0, maxi(r.lock_index(), 0), pts.size() - 2)
	pts.insert(i + 1, pts[i].lerp(pts[i + 1], 0.5))
	r.points = pts
	r.rebuild()
	selected_point = i + 1
	_set_status("Bend point added between points %d and %d." % [i, i + 2])


func _duplicate_clicked() -> void:
	if selected is BlockNode:
		_checkpoint()
		var cb := BlockNode.new()
		blocks_root.add_child(cb)
		cb.from_dict(selected.to_dict())
		cb.translate_by((selected as BlockNode).global_basis * Vector3(selected.size().x, 0, 0))
		_rebuild_blocks()
		_select(cb)
		_set_status("Duplicated %s (placed alongside)." % cb.label().to_lower())
		return
	if selected is PropNode:
		_checkpoint()
		var cp := PropNode.new()
		props_root.add_child(cp)
		cp.from_dict(selected.to_dict())
		cp.translate_by(Vector3(maxf(selected.world_size().x, 4.0) + 4.0, 0, 0))
		_select(cp)
		_set_status("Duplicated prop.")
		return
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
	if selected is RampNode and selected_point >= 0 and selected_point <= selected.lock_index():
		_set_status("Point %d is locked: unlock it before deleting it." % selected_point)
		return
	if selected is RampNode and selected_point >= 0 and selected.points.size() - 1 - selected.lock_index() < 2:
		_set_status("The editable section needs at least one point after the lock.")
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
	if obj is BlockNode:
		_mark_blocks()
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


## Point a perspective camera down the whole course: from behind the start, a little off to the side, raised,
## and backed off until every ramp and platform fits a frame of the given aspect.
func frame_course(cam: OrbitCamera, aspect: float) -> void:
	var pts: Array[Vector3] = []
	for o in _all_objects():
		if o is RampNode:
			pts.append_array(Array(o.ridge))
		else:
			var hs: Vector3 = o.size / 2.0
			for c in 8:
				pts.append(o.position + Vector3(hs.x * (1 if c & 1 else -1), hs.y * (1 if c & 2 else -1), hs.z * (1 if c & 4 else -1)))
	if pts.is_empty():
		return
	var course := Vector3(1, 0, 0)
	var st: Array = entities_root.get_children().filter(func(x): return x.kind == "start")
	var fin: Array = entities_root.get_children().filter(func(x): return x.kind == "finish")
	if not st.is_empty() and not fin.is_empty() and (fin[0].position - st[0].position) * Vector3(1, 0, 1) != Vector3.ZERO:
		course = (fin[0].position - st[0].position) * Vector3(1, 0, 1)
	course = course.normalized()
	cam.yaw = atan2(-course.x, -course.z) + deg_to_rad(42.0)
	cam.pitch = deg_to_rad(-32)
	cam._apply()
	# measure the points along the camera's right/up/forward axes, centre on them and back off until they fit
	var bx := cam.global_basis.x
	var by := cam.global_basis.y
	var bz := cam.global_basis.z
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q in pts:
		var c := Vector3(q.dot(bx), q.dot(by), q.dot(bz))
		lo = lo.min(c)
		hi = hi.max(c)
	var mid := (lo + hi) / 2.0
	cam.focus = bx * mid.x + by * mid.y + bz * mid.z
	var half_v := tan(deg_to_rad(cam.fov) / 2.0)          # Godot's fov is vertical
	var half_h := half_v * aspect
	cam.distance = maxf(maxf((hi.x - lo.x) / 2.0 / (half_h * 0.88), (hi.y - lo.y) / 2.0 / (half_v * 0.80)) + (hi.z - lo.z) / 2.0, 30.0)
	cam._apply()


func _edit_prop(key: String, value) -> void:
	_map_changed()
	if key.begins_with("env_"):
		_edit_env(key.substr(4), value)
		return
	if selected == null or _updating_ui:
		return
	_checkpoint("prop:%s:%d" % [key, _all_objects().find(selected)])
	if selected is BlockNode:
		var b := selected as BlockNode
		var d: Dictionary = b.data.duplicate(true)
		match key:
			"block_shape": d["shape"] = value
			"block_x": d = BlockNode.resized_centered(d, 0, value)
			"block_y": d["size"][1] = value
			"block_z": d = BlockNode.resized_centered(d, 2, value)
			"block_yaw": d["yaw"] = value
			"block_sides": d["sides"] = int(value)
			"block_steps": d["steps"] = int(value)
			"block_hollow": d["hollow"] = value
			"block_wall": d["wall"] = value
			"block_cutter": d["cutter"] = value
			"block_look": d["look"] = value
			"block_color": d["color"] = (value as Color).to_html(false)
		b.from_dict(d)
		if key in ["block_x", "block_y", "block_z"]:
			_last_block["size"] = b.data["size"].duplicate()
		_rebuild_blocks()
		if key in ["block_shape", "block_hollow", "block_cutter"]:
			_refresh_props()
		_refresh_info()
		return
	if selected is PropNode:
		var pr := selected as PropNode
		match key:
			"prop_size": pr.size = value
			"prop_yaw": pr.yaw = value
			"prop_solid": pr.solid = value
		pr.rebuild()
		_refresh_info()
		return
	if selected is RampNode:
		var r := selected as RampNode
		r.set(key, value)
		if not r.freeform:                              # outside Freeform both faces always match
			r.angle_right = r.angle
			r.face_length_right = r.face_length
		r.rebuild()
		if key in ["look", "freeform", "style"]:
			_refresh_props()
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
			"number": e.number = int(value)
			"keep_speed": e.keep_speed = value
		e.rebuild()
	_refresh_info()


func _new_map_clicked() -> void:
	welcome.popup("Keep the current map")


func _on_template_chosen(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("format", "") != MAP_FORMAT:
		_set_status("Template %s could not be read" % path.get_file())
		return
	welcome.hide()
	var info: Dictionary = data.get("template", {})
	data.erase("template")
	_checkpoint()                                       # Ctrl+Z brings back the map you had before
	_load_dict(data)
	best_ghost = {}
	current_path = ""
	_set_title("new map")
	_frame_clicked()
	var pv: Vector2 = Vector2(panes[0].viewport.size)
	frame_course(panes[0].camera, pv.x / maxf(pv.y, 1.0))
	_map_changed()
	_set_status("%s: %s  Press P to play it, then make it your own." % [info.get("title", "New map"), info.get("description", "")])


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
	var d := _map_dict()
	d["made_with"] = SurfForgeVersion.full()
	if not best_ghost.is_empty():
		d["ghost"] = best_ghost                          # the best run travels with the map (editor only)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	current_path = path
	_set_title(path.get_file())
	_set_status("Saved %s" % path)


func load_map(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("format", "") != MAP_FORMAT:
		_set_status("%s is not a SurfForge map" % path.get_file())
		return
	_checkpoint()
	_load_dict(data)
	best_ghost = data.get("ghost", {})
	current_path = path
	_set_title(path.get_file())
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
			var pos := p0 + t * 3.0 + side * out + Vector3(0, -out * RampShape.face_slope(r.shape_spec(), -1.0) + 0.3, 0)
			at = Transform3D(Basis(Vector3.UP, atan2(-t.x, -t.z)), pos)
	_end_drag()
	if selected:
		selected.set_selected(false)
	_ui.visible = false
	var volumes := entities_root.get_children().filter(func(x): return x.is_volume())
	var stages := {}
	for e in entities_root.get_children():
		if e.kind == "stage":
			stages[e.number] = e
	play.start(at, start.zone_aabb() if start else AABB(), finish.zone_aabb() if finish else AABB(),
		SurfsUpExporter.kill_floor_y(_map_dict()), volumes, stages, best_ghost)


func _on_play_stopped() -> void:
	_ui.visible = true
	if selected:
		selected.set_selected(true)
	var t := " Best time: %s (its path is drawn in the views; G in play mode races it)." % PlayMode.format_time(play.best_time) if play.best_time > 0.0 else ""
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


# ------------------------------------------------------------------------------------------------ CS:S
func _build_css_dialog() -> void:
	_css_dialog = ConfirmationDialog.new()
	_css_dialog.title = "Export to Counter-Strike: Source"
	_css_dialog.ok_button_text = "Export"
	_css_dialog.min_size = Vector2i(600, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_css_dialog.add_child(box)
	var l1 := Label.new()
	l1.text = "Map name (surf maps usually start with surf_). In CS:S, open the console (~) and type:  map <name>"
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(l1)
	_css_name = LineEdit.new()
	box.add_child(_css_name)
	var l2 := Label.new()
	l2.text = "Folder for the Hammer file (.vmf) - you can open it in Hammer to keep working on it"
	box.add_child(l2)
	_css_dir = LineEdit.new()
	box.add_child(_css_dir)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var ls := Label.new()
	ls.text = "Sky"
	grid.add_child(ls)
	_css_sky = OptionButton.new()
	for sky in VmfExporter.SKY_CHOICES:
		_css_sky.add_item(sky)
	grid.add_child(_css_sky)
	var la := Label.new()
	la.text = "sv_airaccelerate (set when the map loads)"
	grid.add_child(la)
	_css_aa = SpinBox.new()
	_css_aa.min_value = 10
	_css_aa.max_value = 1000
	_css_aa.value = 150
	grid.add_child(_css_aa)
	_css_compile = CheckBox.new()
	_css_compile.text = "Compile it now with CS:S's own tools (vbsp, vvis, vrad) and put the .bsp in cstrike/maps"
	box.add_child(_css_compile)
	_css_quality = OptionButton.new()
	_css_quality.add_item("Quick compile (fast lighting, for testing)")
	_css_quality.add_item("Final compile (full lighting, slower)")
	box.add_child(_css_quality)
	var note := Label.new()
	note.text = ("Zones use the surf timer names (map_start, map_end, s2_start...) so timer plugins pick them up. "
		+ "Props aren't exported to CS:S yet. Source maps must fit in about 800 m on every side.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	box.add_child(note)
	_css_dialog.confirmed.connect(_do_css_export)
	_ui.add_child(_css_dialog)


func _css_clicked() -> void:
	if _css_thread and _css_thread.is_alive():
		_set_status("A CS:S compile is still running...")
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var base := current_path.get_file().get_basename() if current_path != "" else "mymap"
	var default_name := base if base.begins_with("surf_") else "surf_" + base
	_css_name.text = cfg.get_value("css", "name_" + current_path.md5_text(), default_name)
	_css_dir.text = cfg.get_value("css", "dir", "D:/SurfForge_exports/css")
	var sky: String = VmfExporter.SKIES.get(environment.get("preset", "day"), "sky_day01_01")
	_css_sky.select(maxi(VmfExporter.SKY_CHOICES.find(sky), 0))
	var css := VmfExporter.find_css()
	_css_compile.disabled = css == ""
	_css_compile.button_pressed = css != "" and cfg.get_value("css", "compile", true)
	_css_compile.tooltip_text = "Found CS:S at " + css if css != "" else "Counter-Strike: Source wasn't found, so only the .vmf is written."
	_css_dialog.popup_centered()


func _do_css_export() -> void:
	var map_name := _css_name.text.strip_edges()
	if not SurfsUpExporter.valid_name(map_name):
		_show_message("Can't export yet", "Map names can only use letters, numbers, _ and - (no spaces).")
		return
	var vmf := _css_dir.text.strip_edges().path_join(map_name + ".vmf")
	var res := VmfExporter.export_vmf(_map_dict(), vmf, {"skyname": _css_sky.get_item_text(_css_sky.selected), "airaccelerate": int(_css_aa.value)})
	if res["error"] != "":
		_show_message("Can't export to CS:S yet", res["error"])
		_set_status("CS:S export failed: " + res["error"])
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("css", "dir", _css_dir.text.strip_edges())
	cfg.set_value("css", "name_" + current_path.md5_text(), map_name)
	cfg.set_value("css", "compile", _css_compile.button_pressed)
	cfg.save(SETTINGS_PATH)
	var notes := "\n".join(res["warnings"])
	if not _css_compile.button_pressed or _css_compile.disabled:
		_show_message("Exported for CS:S", "Wrote %s (%d brushes).\n\n%s" % [vmf, res["brushes"], notes])
		_set_status("Wrote %s - open it in Hammer or compile it with vbsp / vvis / vrad." % vmf.get_file())
		return
	var quality := "fast" if _css_quality.selected == 0 else "final"
	_css_status = notes
	_set_status("Compiling %s for CS:S (%d brushes)... this can take a minute; keep working meanwhile." % [map_name, res["brushes"]])
	_css_thread = Thread.new()
	_css_thread.start(func(): return VmfExporter.compile(vmf, VmfExporter.find_css(), quality))


## Called every frame: picks up a finished CS:S compile.
func _poll_css() -> void:
	if _css_thread == null or _css_thread.is_alive():
		return
	var c: Dictionary = _css_thread.wait_to_finish()
	_css_thread = null
	var log_path: String = String(_css_dir.text).path_join(_css_name.text.strip_edges() + "_compile.log")
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f:
		f.store_string(c.get("log", ""))
		f.close()
	if c["error"] != "":
		_show_message("CS:S compile failed", "%s\n\nThe full compile log is in %s" % [c["error"], log_path])
		_set_status("CS:S compile failed: " + c["error"])
		return
	var name: String = c["bsp"].get_file().get_basename()
	_show_message("Ready in CS:S", "Built %s.\n\nStart CS:S, open the console (~) and type:\n    map %s\n\n%s" % [c["bsp"], name, _css_status])
	_set_status("CS:S map ready: in CS:S press ~ and type  map %s" % name)


func _show_message(title: String, text: String) -> void:
	var a := AcceptDialog.new()
	a.title = title
	a.dialog_text = text
	_ui.add_child(a)
	a.popup_centered()
	a.confirmed.connect(a.queue_free)
	a.canceled.connect(a.queue_free)


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
