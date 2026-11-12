extends Node3D
## MALLET main editor: four views (perspective / top / front / side), ramp + platform tools,
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

const MAP_FORMAT := "mallet-map"
const OLD_MAP_FORMATS := ["surfforge-map"]     ## maps saved before the rename (SurfForge) still open
const MAP_EXT := "mallet"
const OLD_MAP_EXTS := ["sfmap"]
const MAP_VERSION := 2
const HANDLE_RADIUS := 6.0          ## px
const PICK_PIXELS := 12.0

var ramps_root := Node3D.new()
var entities_root := Node3D.new()
var props_root := Node3D.new()
var blocks_root := Node3D.new()
var texts_root := Node3D.new()
var lights_root := Node3D.new()
var particles_root := Node3D.new()           ## particle effects (fire, smoke, snow...)
var cube_models_root := Node3D.new()     ## cube objects built in build mode (E)
var co_avatars_root := Node3D.new()      ## co-editors' bodies (U17), in the shared world so every view sees them
var outliner := Outliner.new()           ## every object by name, in folders
var _outliner_panel: PanelContainer
var _cube_panel: VBoxContainer
var build := BuildMode.new()
var _light_props: VBoxContainer
var _particle_props: VBoxContainer
var _prefab_popup: PopupPanel
var _prefab_name_dialog: ConfirmationDialog
var _text_props: VBoxContainer
var _place_on_surface := false          ## the next click in a view puts the selected text on that face
var _font_dialog: FileDialog
var _block_props: VBoxContainer
var _blocks_dirty := false
var _draw_mode := false                 ## Draw block tool: drag a rectangle in a 2D view to make a block
var _draw_block: BlockNode = null
var _draw_start := Vector3.ZERO
var _draw_pane: ViewPane = null
var _last_block := {"size": [16.0, 8.0, 16.0]}   ## new blocks take the last size used
var _face := -1                          ## the block side being dragged (index into face_handles)
var _block_side := "all"                 ## which side of the selected block the material controls edit
var _paint := ""                         ## the material Alt+click paints onto a face (the last one picked)
var _picker: PopupPanel
var _picker_cb: Callable
var _prop_props: VBoxContainer
var _prop_dialog: FileDialog
var _prop_replace := false
var selected: Node3D = null          ## a RampNode or an EntityNode
var selected_point := -1
var _extra: Array = []                  ## other selected objects (Ctrl+click, box select, groups); `selected` leads
var _text_surface := {}                ## while dragging text that sits on a block face: that face (see _text_face)
var _drag_origins := {}                 ## every dragged object's state before the drag
var _marquee_pane: ViewPane = null      ## box selection in a 2D view
var _marquee_a := Vector2.ZERO
var _marquee_b := Vector2.ZERO
var _marquee_add := false
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
var _ground_grid: MeshInstance3D         ## the 3D view's ground grid plane (View > Ground grid)
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
var _drag_applied := Vector3.ZERO        ## how far the selection has been moved so far in this drag

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
var _gen_source: RampNode = null        ## the ramp the new one continues from (null = place at the view center)
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
var tester := {}                       ## a test build: {"dir", "cfg", "name", "file", "attempts"} ({} = normal MALLET)
var test_version := 0                  ## how many test builds of this map were made (stamped into each)
var tester_runs: Array = []            ## imported tester sessions (Tester.read_runs), saved with the map
var relay: Relay = null                ## the relay connection (a playtest session, or a test build's)
var live_peers := {}                   ## tester id -> their last live message (where they are right now)
var live_trails := {}                  ## tester id -> their last few live positions (the trail drawn in the views)
var show_tester_paths := true          ## draw testers' finished routes and where they fell (View menu)
var co_cursors := {}                   ## co-editor id -> their last cursor message (camera, aim, selection, mouse)
var _co_build_steps := -1              ## build mode's undo steps when last watched (its cube edits go out)
var _co_build_model: CubeModelNode = null
var _co_env := ""                      ## the environment (sky and the rest of the Map panel) as last sent
var _co_names: Array = []              ## names for the objects, from the maker, applied with the map it sent
var _co_named := false                 ## those names are in use here (a relay older than 0.17.3 doesn't forward them)
var show_co_editors := true            ## draw co-editors' cameras and selections in the views (View menu)
var session_role := ""                 ## what we joined the relay as: maker, editor or tester
var _cursor_clock := 0.0
var _co_queue := {}                    ## objects changed here that the other editors haven't been sent yet
var _co_last := {}                     ## session id -> where that object was when we last sent or applied it
var _co_uids := {}                     ## session id -> {"o", "kind"}: every object both sides believe exists
var _co_new_now := {}                  ## objects that appeared and haven't gone out yet (they go out as adds)
var _co_dels := []                     ## [kind, uid] waiting to be sent as deletions
var _co_parts := {}                    ## an edit too big for one message, arriving: id -> {part: text}
var _co_seq := 0
var _co_mute := false                  ## a remote edit or an undo is being applied: nothing goes back out
var _co_waiting_state := false         ## waiting for the session's map: nothing goes out until it lands
var _co_state_since := 0
var _co_state_of := 0
var _co_state_next := -1               ## -1 while no map is arriving
var _co_state_text := ""
var _co_state_dialog: ConfirmationDialog = null
var _relay_url := ""                   ## where we joined from, and how: kept so a dropped connection gets back in
var _relay_code := ""
var _relay_secret := ""
var _relay_name := ""
var _reconnect_at := 0                 ## msec of the next try (0 = not trying)
var _reconnect_wait := 1000
var _rejoining := false                ## this connection is a reconnect, not a first join
var _playtest_panel: PlaytestPanel
var _playtest_dialog: ConfirmationDialog
var _playtest_inputs := {}
var ramp_creator: RampCreator
const BAKED_SKY_LABEL := "This map's sky (made into a skybox)"
const BLOCK_LOOKS := ["color", "ceramic", "steel", "grid", "aurora", "nebula", "neon", "material", "shader"]   ## (no "texture")


func _ready() -> void:
	if get_tree().current_scene == self:
		Migrate.from_surfforge()                         # first start after the rename: bring SurfForge's settings along
	# The editor draws handles, outlines and arcs from objects' true positions, so the 3D view must not be
	# smoothed between physics ticks (that made outlines trail moving objects and the camera).
	# Only the play-mode player uses physics interpolation, as in SurfsUp.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	play.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	get_window().theme = UiTheme.shared()             # (dialogs and popups: one look for every menu and button)
	_build_world()
	_build_ui()
	add_child(play)
	play.stopped.connect(_on_play_stopped)
	play.ghost_recorded.connect(func(g): best_ghost = g)
	play.live.connect(_playtest_live)
	_new_map()
	_set_title("")
	_mark_saved()
	if get_tree().current_scene == self:
		get_tree().set_auto_accept_quit(false)           # closing the window asks first when there are unsaved changes
	_show_welcome_if_main.call_deferred()


# ================================================================================================= unsaved changes
var _saved_state := ""                   ## the map as last saved / opened, to tell whether it has changed since
var _quit_after_save := false


func _state_text() -> String:
	return JSON.stringify(_map_dict()) + str(best_ghost.get("time", ""))


func _mark_saved() -> void:
	_saved_state = _state_text()


## Would closing lose work? (Changes since the last save, or a map with something in it that was never saved.)
func has_unsaved_changes() -> bool:
	if current_path == "" and _all_objects().is_empty():
		return false
	return current_path == "" or _state_text() != _saved_state


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_inside_tree() and world_env != null:
		_rescan_shaders()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not tester.is_empty():
		get_tree().quit()                               # (a test build: runs are already saved, nothing else to keep)
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST and get_tree().current_scene == self:
		if has_unsaved_changes():
			_ask_save_before_quit()
		else:
			get_tree().quit()


func _ask_save_before_quit() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Unsaved changes"
	d.dialog_text = ("Save the changes to %s before closing?" % current_path.get_file()) if current_path != "" 		else "This map has never been saved. Save it before closing?"
	d.ok_button_text = "Save"
	d.cancel_button_text = "Cancel"
	d.add_button("Don't save", true, "discard")
	_ui_root.add_child(d)
	d.confirmed.connect(func():
		d.queue_free()
		_quit_after_save = true
		_save_clicked())                                 # (no file yet: the Save dialog opens, closing follows the save)
	d.canceled.connect(func():
		_quit_after_save = false
		d.queue_free())
	d.custom_action.connect(func(action: StringName):
		if action == "discard":
			get_tree().quit())
	d.popup_centered()


## The welcome screen greets you when MALLET starts (not when a test builds the editor).
func _show_welcome_if_main() -> void:
	var td := Tester.folder()
	if td != "" and (get_tree().current_scene == self or OS.get_cmdline_user_args().has("--tester")):
		_start_tester(td)
		return
	if get_tree().current_scene == self:
		welcome.popup("Skip, use the simple starter map")


# ================================================================================================= world
func _build_world() -> void:
	world_env = WorldEnvironment.new()
	add_child(world_env)
	sun = DirectionalLight3D.new()
	add_child(sun)
	environment = Look.default_environment()
	UserShaders.scan()                                   # (your own shaders: before anything asks for one)
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
	grid.visible = bool(Settings.value("ground_grid"))
	_ground_grid = grid
	add_child(grid)
	add_child(ramps_root)
	add_child(entities_root)
	add_child(props_root)
	add_child(blocks_root)
	add_child(texts_root)
	add_child(lights_root)
	add_child(particles_root)
	add_child(cube_models_root)
	add_child(co_avatars_root)
	build.setup(self, cube_models_root)
	add_child(build)
	build.stopped.connect(_on_build_stopped)


# ================================================================================================= ui
var _ui_root: Control                    ## the Control root of the UI: its theme reaches every popup and dialog


func _build_ui() -> void:
	add_child(_ui)
	_ui_root = Control.new()                        # (a Control: its theme reaches every control and popup under it)
	_ui_root.name = "UIRoot"
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = UiTheme.shared()
	_ui.add_child(_ui_root)
	_build_ui_main()
	welcome = WelcomeScreen.new()
	welcome.hide()
	_ui_root.add_child(welcome)
	welcome.template_chosen.connect(_on_template_chosen)
	welcome.open_requested.connect(func():
		welcome.hide()
		_open_clicked())
	ramp_creator = RampCreator.new()
	ramp_creator.hide()
	_ui_root.add_child(ramp_creator)
	ramp_creator.apply_requested.connect(apply_design)
	ramp_creator.new_ramp_requested.connect(new_ramp_from_design)
	_playtest_panel = PlaytestPanel.new()
	_playtest_panel.hide()
	_ui_root.add_child(_playtest_panel)
	_playtest_panel.leave_requested.connect(_leave_playtest)
	_playtest_panel.copy_requested.connect(_copy_playtest_code)
	_playtest_panel.remove_requested.connect(_remove_from_session)
	_playtest_panel.refresh("", "No playtest session", {}, {}, [])


func _build_ui_main() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	_ui_root.add_child(root)

	var bar_panel := PanelContainer.new()
	_fields["toolbar"] = bar_panel
	root.add_child(bar_panel)
	var bar := HFlowContainer.new()                    # wraps onto a second row on narrower windows
	bar.add_theme_constant_override("h_separation", 5)
	bar.add_theme_constant_override("v_separation", 2)
	bar_panel.add_child(bar)
	var title := Label.new()
	title.text = "  MALLET"
	title.add_theme_font_size_override("font_size", 18)
	bar.add_child(title)
	var ver := Label.new()
	ver.text = "%s  " % MalletVersion.VERSION
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	ver.tooltip_text = MalletVersion.full()
	bar.add_child(ver)
	for spec in [["New", _new_map_clicked], ["Open…", _open_clicked], ["Save", _save_clicked], ["|", null],
			["Undo", undo], ["Redo", redo], ["|", null]]:
		_bar_item(bar, spec)
	# Add: everything you can put in a map, each with its key
	_menu(bar, "Add ▾", [
		["Ramp", KEY_N, _add_ramp_clicked], ["Generate a ramp shape…", KEY_R, _generate_clicked],
		["Ramp creator (cross-sections, ends, ramp prefabs)…", KEY_NONE, _open_ramp_creator], [],
		["Block", KEY_O, _add_block_clicked], ["Draw blocks (drag in a 2D view)", KEY_D, _toggle_draw_mode, "draw"], [],
		["Start platform", KEY_B, func(): _add_entity("start")], ["Finish platform", KEY_M, func(): _add_entity("finish")],
		["Stage plate", KEY_T, func(): _add_entity("stage")], ["Teleport", KEY_Y, func(): _add_entity("teleport")],
		["Start zone (on your own platform)", KEY_NONE, func(): _add_entity("start", true)],
		["Finish zone (on your own platform)", KEY_NONE, func(): _add_entity("finish", true)],
		["Stage zone (on your own platform)", KEY_NONE, func(): _add_entity("stage", true)],
		["Kill zone", KEY_K, func(): _add_entity("kill")], ["Booster", KEY_J, func(): _add_entity("booster")], [],
		["Prop (glTF model)…", KEY_I, _add_prop_clicked], ["Text", KEY_X, _add_text_clicked], [],
		["Light", KEY_U, func(): _add_light("point")], ["Spot light", KEY_NONE, func(): _add_light("spot")],
		["Light strip (neon, tubes)", KEY_NONE, func(): _add_light("strip")],
		["Particles (fire, smoke, snow, rain\u2026)", KEY_NONE, func(): _add_particles("fire")],
		["Water", KEY_H, _add_water_clicked], [], ["Prefab\u2026", KEY_NONE, _open_prefabs]])
	_menu(bar, "Edit ▾", [
		["Copy", KEY_MASK_CTRL | KEY_C, _copy], ["Paste", KEY_MASK_CTRL | KEY_V, _paste_clicked],
		["Duplicate", KEY_MASK_CTRL | KEY_D, _duplicate_clicked], ["Delete", KEY_DELETE, _delete_clicked], [],
		["Select all", KEY_MASK_CTRL | KEY_A, func(): _set_selection(_all_objects())],
		["Group", KEY_MASK_CTRL | KEY_G, _group], ["Ungroup", KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_G, _ungroup],
		["Save selection as prefab\u2026", KEY_NONE, _save_prefab_clicked], [],
		["Extend ramp", KEY_NONE, _extend_clicked], ["Add bend to ramp", KEY_NONE, _bend_clicked],
		["Turn left 15°", KEY_BRACKETLEFT, func(): _rotate_selected(-15.0)],
		["Turn right 15°", KEY_BRACKETRIGHT, func(): _rotate_selected(15.0)]])
	_menu(bar, "View ▾", [
		["Frame selection", KEY_F, _frame_clicked], ["Fullscreen", KEY_F11, _toggle_fullscreen],
		["Mouse sensitivity…", KEY_NONE, _open_mouse_settings], ["Your shaders folder…", KEY_NONE, _open_shaders_folder], [],
		["Jump arcs: all ramps", KEY_NONE, func(): show_all_arcs = not show_all_arcs; _sync_view_menu(); _map_changed(), "arcs"],
		["Direction arrows", KEY_NONE, func(): show_direction = not show_direction; _sync_view_menu(), "arrows"],
		["Best run path", KEY_NONE, func(): show_ghost_path = not show_ghost_path; _sync_view_menu(), "ghost"],
		["Testers' paths", KEY_NONE, func(): show_tester_paths = not show_tester_paths; _sync_view_menu(), "paths"],
		["Co-editors", KEY_NONE, func(): show_co_editors = not show_co_editors; _sync_view_menu(), "cores"],
		["Ground grid (3D view)", KEY_NONE, _toggle_ground_grid, "groundgrid"],
		["Outliner (names, folders)", KEY_NONE, func(): _outliner_panel.visible = not _outliner_panel.visible; _sync_view_menu(), "outliner"]])
	bar.add_child(VSeparator.new())
	_bar_item(bar, ["▶ Play (P)", _play_clicked])
	_bar_item(bar, ["Build (E)", _build_clicked])
	var pt := CheckButton.new()                        # (the playtest panel's own button: it is not an export)
	pt.text = "Playtest panel"
	pt.focus_mode = Control.FOCUS_NONE
	pt.tooltip_text = "Who is on the session, their runs, and the invite. Start one in Export > Playtest session."
	pt.toggled.connect(_set_playtest_panel)
	bar.add_child(pt)
	_fields["playtest_button"] = pt
	_menu(bar, "Export ▾", [["To SurfsUp…", KEY_NONE, _export_clicked], ["To Counter-Strike: Source…", KEY_NONE, _css_clicked], [],
		["Playtest session…", KEY_NONE, _playtest_clicked], [],
		["Test build for testers…", KEY_NONE, _test_build_clicked], ["Import tester runs…", KEY_NONE, _import_runs_clicked]])
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
	for sz in [1, 2, 4, 8, 16]:
		step.add_item("every %d m" % sz, sz)
	step.select(2)
	step.focus_mode = Control.FOCUS_NONE
	step.tooltip_text = "Grid size: how far apart the snap points are (also the arrow-key nudge step)."
	step.item_selected.connect(func(i): snap_step = float(step.get_item_id(i)); _set_status("Snap grid: every %d m" % int(snap_step)))
	bar.add_child(step)
	_fields["snap_step"] = step
	_sync_view_menu()

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

	# the Outliner, on the left: every object by name, in folders
	_outliner_panel = PanelContainer.new()
	_outliner_panel.custom_minimum_size = Vector2(250, 0)
	var om := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		om.add_theme_constant_override("margin_" + side, 8)
	_outliner_panel.add_child(om)
	outliner.setup(self)
	om.add_child(outliner)
	middle.add_child(_outliner_panel)
	middle.move_child(_outliner_panel, 0)

	var status_panel := PanelContainer.new()
	root.add_child(status_panel)
	_status = Label.new()
	status_panel.add_child(_status)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.mallet, *.sfmap ; MALLET map"])   # (.sfmap: from before the rename)
	_file_dialog.current_dir = ProjectSettings.globalize_path("res://maps") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()
	_file_dialog.file_selected.connect(_on_file_chosen)
	_file_dialog.canceled.connect(func(): _quit_after_save = false)   # (backed out of Save-then-close)
	_ui_root.add_child(_file_dialog)
	_build_export_dialog()
	_build_css_dialog()


func _build_props(props: VBoxContainer) -> void:
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	props.add_child(head)
	_fields["head"] = head
	_build_position_box(props)

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
	# its design (ramp creator): custom cross-section and shaped ends
	var drow := HBoxContainer.new()
	var creator_btn := Button.new()
	creator_btn.text = "Ramp creator\u2026"
	creator_btn.focus_mode = Control.FOCUS_NONE
	creator_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	creator_btn.tooltip_text = "Design this ramp's cross-section and ends, or give it one of your ramp prefabs."
	creator_btn.pressed.connect(_open_ramp_creator)
	drow.add_child(creator_btn)
	var plain_btn := Button.new()
	plain_btn.text = "Plain again"
	plain_btn.focus_mode = Control.FOCUS_NONE
	plain_btn.tooltip_text = "Back to straight faces and square ends (keeps the angle, face length and points)."
	plain_btn.pressed.connect(_plain_ramp_clicked)
	drow.add_child(plain_btn)
	_add_row(_ramp_props, "Design", drow)
	_fields["ramp_plain"] = plain_btn
	var dlabel := Label.new()
	dlabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlabel.add_theme_font_size_override("font_size", 12)
	dlabel.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_ramp_props.add_child(dlabel)
	_fields["ramp_design"] = dlabel
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
	_add_row(_ramp_props, "Color", cp)
	_fields["color"] = cp
	_fields["color_label"] = _ramp_props.get_child(cp.get_index() - 1)
	var rmat := Button.new()
	rmat.focus_mode = Control.FOCUS_NONE
	rmat.expand_icon = false
	rmat.alignment = HORIZONTAL_ALIGNMENT_LEFT
	rmat.pressed.connect(func(): _open_picker(func(id): _edit_prop("material", id); _refresh_props()))
	_ramp_props.add_child(rmat)
	_fields["ramp_material"] = rmat
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
	_surface_shader_box(_ramp_props, "")

	_build_gen_props(props)
	_build_prop_props(props)
	_build_block_props(props)
	_build_text_props(props)
	_build_light_props(props)
	_build_particle_props(props)
	_cube_panel = VBoxContainer.new()
	_cube_panel.visible = false
	props.add_child(_cube_panel)
	var eb := Button.new()
	eb.text = "Edit its cubes in build mode (E)"
	eb.focus_mode = Control.FOCUS_NONE
	eb.pressed.connect(_build_clicked)
	_cube_panel.add_child(eb)
	var tb := HBoxContainer.new()
	_cube_panel.add_child(tb)
	for t in [["Turn -90\u00b0", -90.0], ["Turn +90\u00b0", 90.0]]:
		var b := Button.new()
		b.text = t[0]
		b.focus_mode = Control.FOCUS_NONE
		var deg: float = t[1]
		b.pressed.connect(func(): _rotate_selected(deg))
		tb.add_child(b)

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
	var zo := CheckButton.new()
	zo.text = "Zone only (stand on your own platform)"
	zo.tooltip_text = "No platform: just the zone, for a platform you built yourself. Several zone boxes of one kind make one zone of any shape."
	zo.focus_mode = Control.FOCUS_NONE
	zo.toggled.connect(func(on): if not _updating_ui: _edit_prop("zone_only", on); _refresh_props())
	_entity_props.add_child(zo)
	_fields["zone_only"] = zo
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
	var clear_best := Button.new()
	clear_best.text = "Clear best run…"
	clear_best.focus_mode = Control.FOCUS_NONE
	clear_best.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	clear_best.visible = false
	clear_best.pressed.connect(_clear_best_clicked)
	props.add_child(clear_best)
	_fields["clear_best"] = clear_best
	props.add_child(HSeparator.new())
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	help.text = ("Drag yellow handles to reshape · drag the object to move it (Shift = up/down in 3D view)\n"
		+ "Double-click a ramp to add a bend\nArrows / PgUp PgDn nudge · [ ] rotate\n"
		+ "N ramp · B start · M finish · K kill zone · J booster · T stage · Y teleport · I prop · P play\nR generate a ramp shape · L lock / unlock a point\nSpace maximize the view under the mouse (again: back to four)\nF frame · G snap to grid · F11 fullscreen\n"
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
			var keep := {}                                 # (a sky preset doesn't change the water / lava / glass looks)
			for k in ["water_look", "lava_look", "glass_look", "sky_shader", "sky_params"]:
				if environment.has(k):
					keep[k] = environment[k]
			environment = Look.preset_environment(keys[i])
			environment.merge(keep, true)
			_apply_environment()
			_refresh_props())
	_add_row(_map_props, "Sky preset", preset)
	_fields["env_preset"] = preset
	# the sky itself: MALLET's built-in sky (colors, stars, aurora, nebula below) or one of your own sky shaders
	var sky_row := HBoxContainer.new()
	var sky_pick := OptionButton.new()
	sky_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sky_pick.focus_mode = Control.FOCUS_NONE
	sky_pick.clip_text = true
	sky_pick.tooltip_text = "MALLET's own sky, or a sky shader from your shaders folder (Folder\u2026 opens it)."
	sky_pick.item_selected.connect(func(i): _pick_sky_shader(String(sky_pick.get_item_metadata(i))))
	sky_row.add_child(sky_pick)
	sky_row.add_child(_shaders_folder_button())
	_add_row(_map_props, "Sky", sky_row)
	_fields["env_sky_shader"] = sky_pick
	var sky_params := VBoxContainer.new()
	sky_params.add_theme_constant_override("separation", 6)
	_map_props.add_child(sky_params)
	_fields["env_sky_params"] = sky_params
	var builtin := VBoxContainer.new()
	builtin.add_theme_constant_override("separation", 6)
	_map_props.add_child(builtin)
	_fields["env_sky_builtin"] = builtin
	for spec in [["sky_top", "Sky color (top)"], ["sky_horizon", "Sky color (horizon)"], ["ground", "Below the horizon"]]:
		_env_color(builtin, spec[0], spec[1])
	_add_slider(builtin, "env_stars", "Stars", 0.0, 1.0, 0.05)
	_add_slider(builtin, "env_aurora", "Aurora", 0.0, 1.0, 0.05)
	_add_slider(builtin, "env_nebula", "Nebula clouds", 0.0, 1.0, 0.05)
	for spec in [["water_look", "Build mode water", Look.LIQUID_ORDER.filter(func(k): return Look.LIQUIDS[k]["style"] == "water"), Look.LIQUIDS],
			["lava_look", "Build mode lava", Look.LIQUID_ORDER.filter(func(k): return Look.LIQUIDS[k]["style"] == "lava"), Look.LIQUIDS],
			["glass_look", "Build mode glass", Look.GLASS_ORDER, Look.GLASS]]:
		var ob := OptionButton.new()
		var ids: Array = spec[2]
		for k in ids:
			ob.add_item(spec[3][k]["label"])
		ob.focus_mode = Control.FOCUS_NONE
		var key: String = spec[0]
		ob.item_selected.connect(func(i): _edit_mat_look(key, ids[i]))
		ob.set_meta("ids", ids)
		_add_row(_map_props, spec[1], ob)
		_fields["env_" + key] = ob
	for spec in [["sun_color", "Sun color"], ["ambient_color", "Shadow fill color"], ["fog_color", "Fog color"]]:
		_env_color(_map_props, spec[0], spec[1])
	_add_slider(_map_props, "env_sun_yaw", "Sun direction (°)", -180.0, 180.0, 1.0)
	_add_slider(_map_props, "env_sun_pitch", "Sun height (°)", 0.0, 90.0, 1.0)
	_add_slider(_map_props, "env_sun_energy", "Sun brightness", 0.0, 3.0, 0.05)
	_add_slider(_map_props, "env_ambient_energy", "Shadow fill brightness", 0.0, 3.0, 0.05)
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
	_ui_root.add_child(_image_dialog)


func _env_color(parent: Container, key: String, label: String) -> void:
	var c := ColorPickerButton.new()
	c.custom_minimum_size = Vector2(0, 24)
	c.color_changed.connect(func(col): _edit_env(key, col.to_html(false)))
	_add_row(parent, label, c)
	_fields["env_" + key] = c


# ------------------------------------------------------------------------------------------------ your own shaders
## A "Folder…" button: opens your shaders folder.
func _shaders_folder_button() -> Button:
	var b := Button.new()
	b.text = "Folder\u2026"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ("Open your shaders folder. Put Godot .gdshader files in it (shader_type sky; or shader_type spatial;)\n"
		+ "and switch back to MALLET: they show up here, with a control for every setting. Guide: docs/SHADERS.md")
	b.pressed.connect(_open_shaders_folder)
	return b


func _open_shaders_folder() -> void:
	var dir := UserShaders.folder()
	OS.shell_open(dir)
	_set_status("Your shaders folder: %s  -  save a .gdshader there, then switch back to MALLET (the examples show how)." % dir)


## Pick up new, changed and removed files in your shaders folder (at start and whenever MALLET gets the focus back),
## and redraw whatever uses them.
func _rescan_shaders() -> void:
	var in_use := _used_shaders(environment, ramps_root.get_children().map(func(r): return r.to_dict()),
		blocks_root.get_children().map(func(b): return b.data))
	var changed := UserShaders.scan()
	if changed.is_empty():
		return
	UserShaders.add_embedded(in_use)                     # (a file deleted while this map uses it: keep the map's copy)
	_apply_environment()
	for r in ramps_root.get_children():
		if (r as RampNode).look == "shader":
			r._update_material()
	for b in blocks_root.get_children():
		if (b as BlockNode).data.get("look", "") == "shader":
			_rebuild_blocks()
			break
	_refresh_props()
	var bad := []
	for id in changed:
		if UserShaders.has(id) and not UserShaders.ok(id):
			bad.append("%s: %s" % [id, UserShaders.problem(id)])
	if not bad.is_empty():
		_set_status("Shader error - " + " | ".join(bad))
	else:
		_set_status("Shaders reloaded: " + ", ".join(changed))


## Fill a shader list: (for skies) MALLET's own first, then your shaders of that kind; broken and missing ones marked.
func _fill_shader_choice(ob: OptionButton, kind: String, current: String) -> void:
	ob.clear()
	if kind == "sky":
		ob.add_item("MALLET's sky (colors below)")
		ob.set_item_metadata(0, "")
	for id in UserShaders.ids(kind, true):
		var e := UserShaders.entry(id)
		ob.add_item(String(id) + ("  (has an error)" if e["shader"] == null else "") + ("  (only in this map)" if e["path"] == "" else ""))
		ob.set_item_metadata(ob.item_count - 1, id)
	if current != "" and not UserShaders.has(current):
		ob.add_item(current + "  (missing)")
		ob.set_item_metadata(ob.item_count - 1, current)
	if ob.item_count == 0:
		ob.add_item("No surface shaders yet: click Folder\u2026")
		ob.set_item_metadata(0, "")
		ob.set_item_disabled(0, true)
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == current:
			ob.select(i)


## A ramp's / block's "Your own shader" settings: which shader, and its controls. `prefix` "" (ramps) or "block_".
func _surface_shader_box(parent: Container, prefix: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var row := HBoxContainer.new()
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.focus_mode = Control.FOCUS_NONE
	ob.clip_text = true
	ob.item_selected.connect(func(i):
		if not _updating_ui:
			_edit_prop(prefix + "shader", String(ob.get_item_metadata(i)))
			_refresh_props())
	row.add_child(ob)
	row.add_child(_shaders_folder_button())
	_add_row(box, "Shader", row)
	var params := VBoxContainer.new()
	params.add_theme_constant_override("separation", 6)
	box.add_child(params)
	_fields[prefix + "shader_box"] = box
	_fields[prefix + "shader"] = ob
	_fields[prefix + "shader_params"] = params


## A control for every setting (uniform) of your shader, in `box`. `params` = the current settings; `on_change` gets
## (uniform name, stored value), or ("", null) to go back to the shader's own values. The controls are only made
## again when the shader or the object changes (never while dragging one), otherwise just updated.
func _fill_shader_controls(box: VBoxContainer, id: String, params: Dictionary, owner_key: String, on_change: Callable,
		fallback: String) -> void:
	var sig := "%s|%d|%s|%s" % [id, UserShaders.version(id), owner_key, UserShaders.problem(id) if id != "" else ""]
	if box.get_meta("sig", "") == sig:
		for f in box.get_meta("setters", []):
			f.call(params)
		return
	box.set_meta("sig", sig)
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var setters := []
	box.set_meta("setters", setters)
	if id == "":
		return
	if not UserShaders.ok(id):
		var l := Label.new()
		l.text = "This shader can't be used yet:\n%s\n\nFix the file and switch back to MALLET. Until then you see %s." % [UserShaders.problem(id), fallback]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		box.add_child(l)
		return
	var e := UserShaders.entry(id)
	if e["path"] == "":
		var n := Label.new()
		n.text = "This shader came with the map (it isn't in your shaders folder)."
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.add_theme_font_size_override("font_size", 12)
		n.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		box.add_child(n)
	if e["uniforms"].is_empty():
		var n := Label.new()
		n.text = "This shader has no settings (add uniforms to get controls here)."
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.add_theme_font_size_override("font_size", 12)
		box.add_child(n)
	for u in e["uniforms"]:
		var name: String = u["name"]
		var ctl: Control
		match u["type"]:
			"float", "int":
				var row := HBoxContainer.new()
				var sl := HSlider.new()
				var sb := SpinBox.new()
				for r in [sl, sb]:
					r.min_value = u["min"]
					r.max_value = u["max"]
					r.step = u["step"]
				sb.allow_greater = u.get("free", false)
				sb.allow_lesser = u.get("free", false)
				sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				sl.focus_mode = Control.FOCUS_NONE
				sb.custom_minimum_size = Vector2(86, 0)
				sl.value_changed.connect(func(v): sb.set_value_no_signal(v); on_change.call(name, UserShaders.encode(u, v)))
				sb.value_changed.connect(func(v): sl.set_value_no_signal(v); on_change.call(name, UserShaders.encode(u, v)))
				row.add_child(sl)
				row.add_child(sb)
				setters.append(func(p): var v = UserShaders.value_of(u, p); sl.set_value_no_signal(v); sb.set_value_no_signal(v))
				ctl = row
			"bool":
				var cb := CheckButton.new()
				cb.focus_mode = Control.FOCUS_NONE
				cb.text = "On"
				cb.toggled.connect(func(on): on_change.call(name, on))
				setters.append(func(p): cb.set_pressed_no_signal(bool(UserShaders.value_of(u, p))))
				ctl = cb
			"color":
				var cp := ColorPickerButton.new()
				cp.custom_minimum_size = Vector2(0, 24)
				cp.edit_alpha = u["alpha"]
				cp.color_changed.connect(func(c): on_change.call(name, UserShaders.encode(u, c)))
				setters.append(func(p): cp.color = UserShaders.value_of(u, p))
				ctl = cp
			"vec2", "vec3", "vec4":
				var row := HBoxContainer.new()
				var n: int = {"vec2": 2, "vec3": 3, "vec4": 4}[u["type"]]
				var boxes := []
				for i in n:
					var sb := SpinBox.new()
					sb.min_value = -100000.0
					sb.max_value = 100000.0
					sb.step = 0.01
					sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					boxes.append(sb)
					row.add_child(sb)
				for sb in boxes:
					sb.value_changed.connect(func(_v):
						var vals: Array = boxes.map(func(bx): return bx.value)
						on_change.call(name, vals))
				setters.append(func(p):
					var v = UserShaders.value_of(u, p)
					for i in n:
						boxes[i].set_value_no_signal(v[i]))
				ctl = row
			"image":
				var row := HBoxContainer.new()
				var pick := Button.new()
				pick.focus_mode = Control.FOCUS_NONE
				pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				pick.clip_text = true
				pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
				pick.pressed.connect(func(): _choose_shader_image(func(path): on_change.call(name, path)))
				var clear := Button.new()
				clear.text = "\u2715"
				clear.focus_mode = Control.FOCUS_NONE
				clear.tooltip_text = "No image"
				clear.pressed.connect(func(): on_change.call(name, ""); _refresh_props())
				row.add_child(pick)
				row.add_child(clear)
				setters.append(func(p):
					var path := String(p.get(name, ""))
					pick.text = path.get_file() if path != "" else "Choose image\u2026"
					pick.tooltip_text = path)
				ctl = row
		_add_row(box, u["label"], ctl)
		if u["tip"] != "":
			ctl.tooltip_text = u["tip"]
			var lab: Label = box.get_child(ctl.get_index() - 1)
			lab.tooltip_text = u["tip"]
			lab.mouse_filter = Control.MOUSE_FILTER_STOP
	if not e["uniforms"].is_empty():
		var reset := Button.new()
		reset.text = "Back to the shader's own values"
		reset.focus_mode = Control.FOCUS_NONE
		reset.pressed.connect(func(): on_change.call("", null); _refresh_props())
		box.add_child(reset)
	for f in setters:
		f.call(params)


var _shader_image_dialog: FileDialog
var _shader_image_done: Callable


func _choose_shader_image(done: Callable) -> void:
	if _shader_image_dialog == null:
		_shader_image_dialog = FileDialog.new()
		_shader_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_shader_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_shader_image_dialog.use_native_dialog = true
		_shader_image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		_shader_image_dialog.file_selected.connect(func(path): _shader_image_done.call(path); _refresh_props())
		_ui_root.add_child(_shader_image_dialog)
	_shader_image_done = done
	_shader_image_dialog.popup_centered_ratio(0.6)


func _pick_sky_shader(id: String) -> void:
	if _updating_ui:
		return
	_checkpoint()
	environment["sky_shader"] = id
	environment["sky_params"] = {}
	_apply_environment()
	_map_changed()                               # (a sky is a map change like any other: the others follow it)
	_refresh_props()
	if id != "" and not UserShaders.ok(id):
		_set_status("That sky shader has an error, so the built-in sky stays for now: " + UserShaders.problem(id))


func _set_sky_param(name: String, value) -> void:
	if _updating_ui:
		return
	_checkpoint("sky:" + name)
	var p: Dictionary = (environment.get("sky_params", {}) as Dictionary).duplicate(true)
	if name == "":
		p.clear()
	else:
		p[name] = value
	environment["sky_params"] = p
	_map_changed()
	# a slider drag only changes one setting of the sky that's already showing: no need to build it all again
	var id := String(environment.get("sky_shader", ""))
	var m = world_env.environment.sky.sky_material if world_env.environment and world_env.environment.sky else null
	if name != "" and m is ShaderMaterial and UserShaders.ok(id) and m.shader == UserShaders.entry(id)["shader"]:
		for u in UserShaders.entry(id)["uniforms"]:
			if u["name"] == name:
				m.set_shader_parameter(name, UserShaders.decode(u, value))
		return
	_apply_environment()


## The shaders a map uses (sky, ramps, blocks) with their code, saved into the map so it looks the same elsewhere.
static func _used_shaders(env: Dictionary, ramp_list: Array, block_list: Array) -> Dictionary:
	var out := {}
	var ids := [String(env.get("sky_shader", ""))]
	for d in ramp_list + block_list:
		if d.get("look", "") == "shader":
			ids.append(String(d.get("shader", "")))
	for id in ids:
		if id != "" and UserShaders.code(id) != "":
			out[id] = UserShaders.code(id)
	return out


func _apply_environment() -> void:
	_apply_mat_looks()
	world_env.environment = Look.build_environment(environment)
	Look.apply_sun(sun, environment)
	sun.directional_shadow_max_distance = 1500.0


## The Map panel's looks for build mode's water / lava / glass cubes (saved with the map's environment).
func _edit_mat_look(key: String, value: String) -> void:
	if _updating_ui:
		return
	_checkpoint("env:" + key)
	environment[key] = value
	_apply_mat_looks()
	_map_changed()


func _apply_mat_looks() -> void:
	if CubeWorld.set_mat_looks(environment):
		for cm in cube_models_root.get_children():
			cm.rebuild_all()


func _edit_env(key: String, value) -> void:
	if _updating_ui:
		return
	_checkpoint("env:" + key)
	environment[key] = value
	environment["preset"] = "custom"
	_apply_environment()
	_map_changed()
	_fields["env_preset"].select(Look.ENV_PRESETS.size())


func _refresh_map_props() -> void:
	_updating_ui = true
	var keys := Look.ENV_PRESETS.keys()
	var p: int = keys.find(environment.get("preset", "custom"))
	_fields["env_preset"].select(p if p >= 0 else keys.size())
	for key in ["sky_top", "sky_horizon", "ground", "sun_color", "ambient_color", "fog_color"]:
		_fields["env_" + key].color = Color.html(environment[key])
	var sky_id := String(environment.get("sky_shader", ""))
	_fill_shader_choice(_fields["env_sky_shader"], "sky", sky_id)
	_fill_shader_controls(_fields["env_sky_params"], sky_id, environment.get("sky_params", {}), "map", _set_sky_param, "MALLET's built-in sky")
	_fields["env_sky_builtin"].visible = not UserShaders.ok(sky_id)
	for key in ["sun_yaw", "sun_pitch", "sun_energy", "ambient_energy", "stars", "aurora", "nebula", "fog_density"]:
		_set_field("env_" + key, float(environment[key]))
	_fields["env_fog"].button_pressed = bool(environment["fog"])
	for key in ["water_look", "lava_look", "glass_look"]:
		var ob: OptionButton = _fields["env_" + key]
		ob.select(maxi((ob.get_meta("ids") as Array).find(environment.get(key, {"water_look": "water", "lava_look": "lava", "glass_look": "clear"}[key])), 0))
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
	if outliner.is_inside_tree():
		outliner.sync_selection.call_deferred()
	_gen_props.visible = _gen_ramp != null
	if _gen_ramp:
		_map_props.visible = false
		_ramp_props.visible = false
		_entity_props.visible = false
		_prop_props.visible = false
		_block_props.visible = false
		_text_props.visible = false
		_light_props.visible = false
		_particle_props.visible = false
		_cube_panel.visible = false
		_fields["head"].text = "Generate a ramp"
		_refresh_info()
		return
	_map_props.visible = selected == null
	_prop_props.visible = false
	_block_props.visible = false
	_text_props.visible = false
	_light_props.visible = false
	_particle_props.visible = false
	_cube_panel.visible = false
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
	_text_props.visible = selected is TextNode
	_light_props.visible = selected is LightNode
	_particle_props.visible = selected is ParticleNode
	_cube_panel.visible = selected is CubeModelNode
	if selected is CubeModelNode:
		_fields["head"].text = String(selected.get_meta("name", "Cube object"))
		_updating_ui = false
		_refresh_info()
		return
	if selected is ParticleNode:
		var ps := ParticleNode.spec((selected as ParticleNode).data)
		_fields["head"].text = (selected as ParticleNode).label()
		_fields["fx_preset"].select(ParticleNode.PRESET_ORDER.find(ps["preset"]))
		_fields["fx_own_color"].set_pressed_no_signal(ps["color"] != "")
		_fields["fx_color"].visible = ps["color"] != ""
		if ps["color"] != "":
			_fields["fx_color"].color = Color.html(ps["color"])
		_set_field("fx_amount", float(ps["amount"]))
		_set_field("fx_size", float(ps["size"]))
		_set_field("fx_speed", float(ps["speed"]))
		_set_field("fx_area_x", float(ps["area"][0]))
		_set_field("fx_area_y", float(ps["area"][1]))
		_set_field("fx_area_z", float(ps["area"][2]))
		_updating_ui = false
		_refresh_info()
		return
	if selected is LightNode:
		var ln := selected as LightNode
		_fields["head"].text = ln.label()
		_fields["light_kind"].select(LightNode.KINDS.find(ln.data["kind"]))
		_fields["light_color"].color = Color.html(ln.data["color"])
		_set_field("light_energy", float(ln.data["energy"]))
		_set_field("light_range", float(ln.data["range"]))
		_set_field("light_angle", float(ln.data["angle"]))
		_set_field("light_yaw", float(ln.data["yaw"]))
		_set_field("light_pitch", float(ln.data["pitch"]))
		_fields["light_shadows"].set_pressed_no_signal(bool(ln.data["shadows"]))
		_fields["light_spot_box"].visible = ln.data["kind"] == "spot"
		_fields["light_strip_box"].visible = ln.data["kind"] == "strip"
		_fields["light_effect"].select(maxi(LightNode.EFFECTS.find(ln.data.get("effect", "none")), 0))
		_set_field("light_length", float(ln.data.get("length", 4.0)))
		_set_field("light_strip_yaw", float(ln.data["yaw"]))
		_fields["light_preset"].select(0)
		_updating_ui = false
		_refresh_info()
		return
	if selected is TextNode:
		var tn := selected as TextNode
		_fields["head"].text = tn.label()
		var te: TextEdit = _fields["text_text"]
		if te.text != tn.data["text"]:
			te.text = tn.data["text"]
		var fo: OptionButton = _fields["text_font"]
		var fi := TextShape.FONTS.find(tn.data["font"])
		if fi < 0:
			fo.set_item_text(fo.item_count - 1, "Font file: " + String(tn.data["font"]).get_file())
			fo.select(fo.item_count - 1)
		else:
			fo.set_item_text(fo.item_count - 1, "Load a font file\u2026")
			fo.select(fi)
		_fields["text_mode"].select(TextShape.MODES.find(tn.data["mode"]))
		_fields["text_align"].select(["left", "center", "right"].find(tn.data["align"]))
		_set_field("text_height", float(tn.data["height"]))
		_set_field("text_depth", float(tn.data["depth"]))
		_set_field("text_yaw", float(tn.data["yaw"]))
		_set_field("text_pitch", float(tn.data["pitch"]))
		_set_field("text_roll", float(tn.data["roll"]))
		_set_field("text_glow", float(tn.data["glow"]))
		_fields["text_solid"].set_pressed_no_signal(bool(tn.data["solid"]))
		_fields["text_solid"].visible = tn.data["mode"] == "3d"
		_fields["text_depth"][0].get_parent().visible = tn.data["mode"] != "flat"
		_fields["text_depth"][0].get_parent().get_parent().get_child(_fields["text_depth"][0].get_parent().get_index() - 1).visible = tn.data["mode"] != "flat"
		var tb: Button = _fields["text_mat"]
		tb.text = "  " + (MaterialLibrary.display_name(tn.data["material"]) if tn.data["material"] != "" else "Plain color (pick a material\u2026)")
		tb.icon = MaterialLibrary.preview(tn.data["material"]) if tn.data["material"] != "" else null
		_fields["text_color"].color = Color.html(tn.data["color"])
		_updating_ui = false
		_refresh_info()
		return
	if selected is BlockNode:
		var b := selected as BlockNode
		_fields["head"].text = b.label()
		_fields["block_shape"].select(BlockShape.SHAPES.find(b.data["shape"]))
		var sz: Vector3 = b.size()
		_set_field("block_x", sz.x)
		_set_field("block_y", sz.y)
		_set_field("block_z", sz.z)
		_set_field("block_yaw", float(b.data["yaw"]))
		_set_field("block_pitch", float(b.data.get("pitch", 0.0)))
		_set_field("block_roll", float(b.data.get("roll", 0.0)))
		_set_field("block_sides", float(b.data["sides"]))
		_set_field("block_steps", float(b.data["steps"]))
		_set_field("block_wall", float(b.data["wall"]))
		_fields["block_hollow"].set_pressed_no_signal(bool(b.data["hollow"]))
		_fields["block_cutter"].set_pressed_no_signal(b.is_cutter())
		_fields["block_look"].select(maxi(BLOCK_LOOKS.find(b.data["look"]), 0))
		_fields["block_shader_box"].visible = b.data["look"] == "shader"
		if b.data["look"] == "shader":
			_fill_shader_choice(_fields["block_shader"], "surface", String(b.data.get("shader", "")))
			_fill_shader_controls(_fields["block_shader_params"], String(b.data.get("shader", "")), b.data.get("shader_params", {}),
				"block%d" % b.get_instance_id(), func(n, v): _edit_prop("block_shader_param", [n, v]), "a plain color (the Color above)")
		_fields["block_color"].color = Color.html(b.data["color"])
		_fields["block_sides_box"].visible = b.data["shape"] in ["cylinder", "arch", "cone", "sphere"]
		_fields["block_steps_box"].visible = b.data["shape"] == "stairs"
		_fields["block_hollow"].visible = b.data["shape"] in ["box", "cylinder"] and not b.is_cutter()
		_fields["block_wall_box"].visible = (bool(b.data["hollow"]) and b.data["shape"] in ["box", "cylinder"] or b.data["shape"] == "arch") and not b.is_cutter()
		var fs := BlockShape.face_settings(b.data, _block_side) if _block_side != "all" else BlockShape.face_settings(b.data, "")
		if _block_side == "all":
			fs = {"material": b.data.get("material", ""), "uv_scale": float(b.data.get("uv_scale", 1.0)),
				"uv_offset": b.data.get("uv_offset", [0.0, 0.0]), "uv_rot": float(b.data.get("uv_rot", 0.0))}
		_fields["block_side"].select(0 if _block_side == "all" else BlockShape.SLOTS.find(_block_side) + 1)
		var mbtn: Button = _fields["block_mat"]
		mbtn.text = "  " + (MaterialLibrary.display_name(fs["material"]) if fs["material"] != "" else "No material (Look & color below) \u2026")
		mbtn.icon = MaterialLibrary.preview(fs["material"]) if fs["material"] != "" else null
		_set_field("block_uv_scale", float(fs["uv_scale"]))
		_set_field("block_uv_u", float(fs["uv_offset"][0]))
		_set_field("block_uv_v", float(fs["uv_offset"][1]))
		_set_field("block_uv_rot", float(fs["uv_rot"]))
		for k in ["block_mat_head", "block_side", "block_mat", "block_uv_box"]:
			var c: Control = _fields[k]
			c.visible = not b.is_cutter()
		_fields["block_side"].get_parent().get_child(_fields["block_side"].get_index() - 1).visible = not b.is_cutter()
		_fields["block_uv_box"].visible = not b.is_cutter() and fs["material"] != ""
		_fields["block_look_box"].visible = not b.is_cutter()
		var is_water: bool = b.data.get("water", false)
		_fields["block_water_box"].visible = is_water
		_fields["block_water_color"].color = Color.html(b.data.get("water_color", "1f6b8c"))
		_set_field("block_clarity", float(b.data.get("clarity", 0.55)))
		_set_field("block_glow", float(b.data.get("glow", 0.0)))
		_fields["block_deadly"].set_pressed_no_signal(bool(b.data.get("deadly", false)))
		_fields["block_liquid"].select(maxi(Look.LIQUID_ORDER.find(b.data.get("liquid", "water")), 0))
		if is_water:
			for k in ["block_mat_head", "block_side", "block_mat", "block_uv_box", "block_cutter", "block_hollow", "block_wall_box"]:
				(_fields[k] as Control).visible = false
			_fields["block_side"].get_parent().get_child(_fields["block_side"].get_index() - 1).visible = false
			for c in (_fields["block_look_box"] as Container).get_children():
				c.visible = c == _fields["block_glow"][0].get_parent() or c.get_index() == _fields["block_glow"][0].get_parent().get_index() - 1
		else:
			_fields["block_cutter"].visible = true
			for c in (_fields["block_look_box"] as Container).get_children():
				c.visible = true
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
		var custom := RampShape.custom_profile(r.shape_spec()) or RampShape.custom_ends(r.shape_spec())
		_fields["ramp_design"].text = (r.design + ": " if r.design != "" else "") + RampPrefabs.describe(r.to_dict())
		_fields["ramp_plain"].disabled = not custom or not r.frozen.is_empty()
		_fields["slice"].select(0 if r.slice == "vertical" else 1)
		_fields["freeform"].set_pressed_no_signal(r.freeform)
		_freeform_box.visible = r.freeform
		_fields["angle_label"].text = "Left face angle (°)" if r.freeform else "Slope angle (°)"
		_fields["face_length_label"].text = "Left face length (m)" if r.freeform else "Face length (m)"
		for key in ["angle", "face_length", "base_depth", "detail", "angle_right", "face_length_right"]:
			_set_field(key, r.get(key))
		_fields["color"].color = r.color
		_fields["look"].select(Look.LOOK_ORDER.find(r.look))
		_fields["color_label"].text = "Color (%s)" % Look.RAMP_LOOKS[r.look][2]
		_tex_box.visible = r.look in ["texture", "material"]
		_fields["tex_name"].visible = r.look == "texture"
		var rmb: Button = _fields["ramp_material"]
		rmb.visible = r.look == "material"
		rmb.text = "  " + (MaterialLibrary.display_name(r.material) if r.material != "" else "Choose a material\u2026")
		rmb.icon = MaterialLibrary.preview(r.material) if r.material != "" else null
		_fields["tex_name"].text = r.texture.get_file() if r.texture != "" else "No image chosen (PNG / JPG / WebP)"
		_fields["shader_box"].visible = r.look == "shader"
		if r.look == "shader":
			_fill_shader_choice(_fields["shader"], "surface", r.shader)
			_fill_shader_controls(_fields["shader_params"], r.shader, r.shader_params, "ramp%d" % r.get_instance_id(),
				func(n, v): _edit_prop("shader_param", [n, v]), "a plain color (the Color above)")
		_set_field("tex_scale", r.tex_scale)
	else:
		var e := selected as EntityNode
		_fields["head"].text = e.label()
		_set_field("size_x", e.size.x)
		_set_field("size_z", e.size.z)
		_set_field("size_y", e.size.y)
		_set_field("yaw", e.yaw)
		_fields["size_y"][0].get_parent().get_parent().get_child(_fields["size_y"][0].get_parent().get_index() - 1).visible = e.is_volume() or e.is_zone_box()
		_fields["size_y"][0].get_parent().visible = e.is_volume() or e.is_zone_box()
		_fields["zone_only"].visible = e.kind in ["start", "finish", "stage"]
		_fields["zone_only"].button_pressed = e.zone_only
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


## How heavy the map's lights and particles are for players' computers, with a warning when it's a lot.
static func map_weight(map: Dictionary) -> Dictionary:
	var lights := 0
	var shadowed := 0
	for ld in map.get("lights", []):
		var ls := LightNode.spec(ld)
		var n := LightNode.strip_count(ls) if ls["kind"] == "strip" else 1
		lights += n
		if ls["shadows"]:
			shadowed += n
	var particles := 0
	for pd in map.get("particles", []):
		particles += ParticleNode.particle_count(ParticleNode.spec(pd))
	var warn := []
	if shadowed > 8:
		warn.append("%d lights cast shadows: shadows are the costly part. Turn shadows off on the small ones." % shadowed)
	if lights > 40:
		warn.append("%d lights is a lot: slower computers will struggle." % lights)
	if particles > 6000:
		warn.append("%d particles at a time is a lot: lower the Amount of the big rain / snow areas." % particles)
	return {"lights": lights, "shadowed": shadowed, "particles": particles, "warnings": warn}


static func map_weight_text(map: Dictionary) -> String:
	var w := map_weight(map)
	if w["lights"] == 0 and w["particles"] == 0:
		return ""
	var t := "\n\nMap weight: %d light(s), %d with shadows; %d particle(s) at a time." % [w["lights"], w["shadowed"], w["particles"]]
	for m in w["warnings"]:
		t += "\n\u26a0 " + m
	if (w["warnings"] as Array).is_empty():
		t += " Light enough for most computers."
	return t


func _refresh_info() -> void:
	if _fields.has("clear_best"):
		_fields["clear_best"].visible = selected == null and not best_ghost.is_empty()
	if selected != null and selected.has_meta("name") and String(selected.get_meta("name")) != "":
		_fields["head"].text = String(selected.get_meta("name"))         # the name given in the Outliner
	if selected == null:
		var counts := {}
		for e in entities_root.get_children():
			counts[e.kind] = counts.get(e.kind, 0) + 1
		var best_txt := ("\n\nBest run: %s (saved with the map). Its path is drawn in the views; in play mode you race it (G hides it)."
			% PlayMode.format_time(float(best_ghost["time"]))) if not best_ghost.is_empty() else "\n\nNo best run yet: press P and finish a run."
		_info.text = ("Nothing selected - click a ramp or platform in any view to edit it.\n\n"
			+ "Ramps: %d\nStart: %s   Finish: %s\nStages: %d   Teleports: %d\nBoosters: %d   Kill zones: %d"
			% [ramps_root.get_child_count(), "yes" if counts.has("start") else "missing", "yes" if counts.has("finish") else "missing",
				counts.get("stage", 0), counts.get("teleport", 0), counts.get("booster", 0), counts.get("kill", 0)]) \
			+ map_weight_text(_map_dict()) + best_txt
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
	elif selected is CubeModelNode:
		var cm := selected as CubeModelNode
		var bb: AABB = cm.world.bounds()
		_info.text = "Cube object: %d cubes, %.0f x %.0f x %.0f m.\nBuilt in build mode; here it moves, turns, copies and groups as one object (and can be a prefab).\n\nSurfsUp: exact collision per cube. CS:S: a brush per cube." % [
			cm.world.count(), bb.size.x, bb.size.y, bb.size.z]
	elif selected is ParticleNode:
		var pn := selected as ParticleNode
		var ps := ParticleNode.spec(pn.data)
		var css: String = ParticleNode.PRESETS[ps["preset"]]["css"]
		_info.text = "%s: %d particles at a time.\nPlays live here and in play mode.\n\nSurfsUp: the same particles. CS:S: %s." % [
			pn.label(), ParticleNode.particle_count(ps), ("a stock " + css + " (Source's nearest effect)") if css != "" else "nothing (Source has no such effect)"]
	elif selected is LightNode:
		var ln := selected as LightNode
		var fx: String = ln.data.get("effect", "none")
		_info.text = "%s\nReaches %.0f m. Lights the editor view straight away.%s\n\nSurfsUp: %s. CS:S: %s (lighting is baked when the map compiles%s)." % [
			ln.label(), float(ln.data["range"]),
			("\nEffect: " + LightNode.EFFECT_LABELS[LightNode.EFFECTS.find(fx)].to_lower() + ".") if fx != "none" else "",
			"%d real lights along the tube" % LightNode.strip_count(LightNode.spec(ln.data)) if ln.data["kind"] == "strip" else "a real light",
			"%d light entities" % LightNode.strip_count(LightNode.spec(ln.data)) if ln.data["kind"] == "strip"
				else ("a light_spot entity" if ln.data["kind"] == "spot" else "a light entity"),
			"; the effect is a Source light style" if fx != "none" else ""]
	elif selected is TextNode:
		var tn := selected as TextNode
		var pieces_txt := "working it out…"
		if tn.pieces_pending():
			if not tn.pieces_ready.is_connected(_refresh_info):
				tn.pieces_ready.connect(_refresh_info, CONNECT_ONE_SHOT)
		else:
			pieces_txt = str(TextShape.convex_polygons(TextShape.spec(tn.data)).size())
		_info.text = "%s\n\"%s\"  -  %s, letters %.1f m tall\nConvex pieces: %s (each one is a brush in a CS:S export)\n\n%s" % [
			TextShape.MODE_LABELS[tn.data["mode"]], String(tn.data["text"]).replace("\n", " / "), tn.data["font"].get_file(), float(tn.data["height"]), pieces_txt,
			{"flat": "A sign: players pass through it. Place it on a wall with 'Place on a surface'.",
			 "3d": "Solid letters - stand on them, surf around them. On a surface they look embossed."}[tn.data["mode"]]]
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
## The view under the mouse, or null.
func _hovered_pane() -> ViewPane:
	var mouse := get_viewport().get_mouse_position()
	for p in panes:
		if p.visible and p.get_global_rect().has_point(mouse):
			return p
	return null


## Is the right mouse button held in any view (flying)?
func _flying() -> bool:
	for p in panes:
		if p.camera is OrbitCamera and (p.camera as OrbitCamera).flying():
			return true
	return false


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
		rs.append(_with_group(r))
	var es := []
	for e in entities_root.get_children():
		es.append(_with_group(e))
	var ps := []
	for pr in props_root.get_children():
		ps.append(_with_group(pr))
	var bs := []
	for b in blocks_root.get_children():
		bs.append(_with_group(b))
	var ts := []
	for t in texts_root.get_children():
		ts.append(_with_group(t))
	var ls := []
	for l in lights_root.get_children():
		ls.append(_with_group(l))
	var pfx := []
	for p in particles_root.get_children():
		pfx.append(_with_group(p))
	var cms := []
	for cm in cube_models_root.get_children():
		if (cm as CubeModelNode).world.count() > 0 or not (cm as CubeModelNode).world.mats.is_empty():
			cms.append(_with_group(cm))
	var d := {"format": MAP_FORMAT, "version": MAP_VERSION, "environment": environment.duplicate(true), "ramps": rs, "entities": es,
		"props": ps, "blocks": bs, "texts": ts, "lights": ls, "particles": pfx, "cube_models": cms, "folders": outliner.folders.duplicate(true)}
	if test_version > 0:
		d["test_version"] = test_version
	if not tester_runs.is_empty():
		d["tester_runs"] = tester_runs.duplicate(true)
	var used := _used_shaders(environment, rs, bs)
	if not used.is_empty():
		d["shaders"] = used                              # (your own shaders' code: the map looks the same anywhere)
	return d


func _load_dict(data: Dictionary) -> void:
	outliner.folders = (data.get("folders", []) as Array).duplicate(true)   # first: objects file into them as they load
	_gen_ramp = null
	_gen_source = null
	play.finish_speed = 0.0                  # another map's finish speed would mislead
	UserShaders.add_embedded(data.get("shaders", {}))
	test_version = int(data.get("test_version", 0))
	tester_runs = (data.get("tester_runs", []) as Array).duplicate(true) if data.get("tester_runs") is Array else []
	environment = Look.default_environment()
	environment.merge(data.get("environment", {}), true)
	_apply_environment()
	_select(null)
	for root in [ramps_root, entities_root, props_root, blocks_root, texts_root, lights_root, particles_root, cube_models_root]:
		for c in root.get_children():
			root.remove_child(c)
			c.queue_free()
	for rd in data.get("ramps", []):
		var r := RampNode.new()
		ramps_root.add_child(r)
		r.from_dict(rd)
		_take_group(r, rd)
	for ed in data.get("entities", []):
		var e := EntityNode.new()
		entities_root.add_child(e)
		e.from_dict(ed)
		_take_group(e, ed)
	for pd in data.get("props", []):
		var pr := PropNode.new()
		props_root.add_child(pr)
		pr.from_dict(pd)
		_take_group(pr, pd)
	for bd in data.get("blocks", []):
		var b := BlockNode.new()
		blocks_root.add_child(b)
		b.from_dict(bd)
		_take_group(b, bd)
	for td in data.get("texts", []):
		var t := TextNode.new()
		texts_root.add_child(t)
		t.from_dict(td)
		_take_group(t, td)
	var cm_list: Array = data.get("cube_models", [])
	if cm_list.is_empty() and not (data.get("cubes", {}) as Dictionary).is_empty():
		cm_list = [{"cubes": data["cubes"]}]          # 0.6.0 maps: one set of cubes -> one cube object
	for cmd in cm_list:
		var cm := CubeModelNode.new()
		cube_models_root.add_child(cm)
		cm.from_dict(cmd)
		_take_group(cm, cmd)
	for ld in data.get("lights", []):
		var l := LightNode.new()
		lights_root.add_child(l)
		l.from_dict(ld)
		_take_group(l, ld)
	for pd in data.get("particles", []):
		var pn := ParticleNode.new()
		particles_root.add_child(pn)
		pn.from_dict(pd)
		_take_group(pn, pd)
	_rebuild_blocks()


## Undo and redo: put the map in the state `data` describes, keeping every object that is already exactly that way
## (only what the step changed is rebuilt). Loading the whole map instead took 18 s on a 76,000-cube map.
func _restore_dict(data: Dictionary) -> void:
	outliner.folders = (data.get("folders", []) as Array).duplicate(true)
	_gen_ramp = null
	_gen_source = null
	UserShaders.add_embedded(data.get("shaders", {}))
	test_version = int(data.get("test_version", 0))
	tester_runs = (data.get("tester_runs", []) as Array).duplicate(true) if data.get("tester_runs") is Array else []
	var env := Look.default_environment()
	env.merge(data.get("environment", {}), true)
	if env != environment:
		environment = env
		_apply_environment()
	_select(null)
	var kinds := [["ramps", ramps_root, RampNode], ["entities", entities_root, EntityNode], ["props", props_root, PropNode],
		["blocks", blocks_root, BlockNode], ["texts", texts_root, TextNode], ["cube_models", cube_models_root, CubeModelNode],
		["lights", lights_root, LightNode], ["particles", particles_root, ParticleNode]]
	var blocks_changed := false
	for k in kinds:
		var want: Array = data.get(k[0], [])
		var root: Node3D = k[1]
		var have: Array = []
		for c in root.get_children():
			if not c.is_queued_for_deletion():
				have.append(c)
		var by_state := {}                                # state hash -> indexes of objects that are exactly that now
		for j in have.size():
			var h: int = _with_group(have[j]).hash()
			if not by_state.has(h):
				by_state[h] = []
			by_state[h].append(j)
		var taken := []
		taken.resize(have.size())
		taken.fill(false)
		var result: Array = []
		result.resize(want.size())
		var todo := []                                    # wanted states no object here has
		for i in want.size():
			var cands: Array = by_state.get((want[i] as Dictionary).hash(), [])
			var hit := -1
			for j in cands:
				if not taken[j] and _with_group(have[j]) == want[i]:
					hit = j
					break
			if hit >= 0:
				taken[hit] = true
				result[i] = have[hit]
			else:
				todo.append(i)
		var spare := []                                   # objects here that match nothing: reused for the changed ones
		for j in have.size():
			if not taken[j]:
				spare.append(have[j])
		for i in todo:
			var d: Dictionary = want[i]
			var o: Node3D
			if not spare.is_empty():
				o = spare.pop_front()
				for key in ["group", "name", "folder", "hidden"]:
					if o.has_meta(key) and not d.has(key):
						o.remove_meta(key)
				if not d.get("hidden", false):
					o.visible = true
			else:
				o = k[2].new()
				root.add_child(o)
			o.from_dict(d)
			_take_group(o, d)
			if o.has_method("rebuild") and not o is CubeModelNode:
				o.rebuild()
			result[i] = o
			blocks_changed = blocks_changed or root == blocks_root
		for o in spare:                                   # (left over: the step removed them)
			root.remove_child(o)
			o.queue_free()
			blocks_changed = blocks_changed or root == blocks_root
		for i in result.size():
			root.move_child(result[i], i)
	if blocks_changed:
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
	_co_map_replaced()
	_set_status("New map: a start platform, one ramp and a finish. Shape the ramp, then press P to play.")


func _make_ramp(a: Vector3, b: Vector3) -> RampNode:
	var r := RampNode.new()
	r.points = PackedVector3Array([a, a.lerp(b, 0.5), b])
	ramps_root.add_child(r)
	return r


## A whole different map is in this MALLET now (File > New, a template, an opened file): the session takes it too, so
## nobody keeps building on the map that just went away.
func _co_map_replaced() -> void:
	if relay == null or not relay.is_open() or session_role != "maker":
		return
	_co_seed()
	_co_seq += 1
	relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "reset"}})


func _all_objects() -> Array:
	return ramps_root.get_children() + entities_root.get_children() + props_root.get_children() + blocks_root.get_children() + texts_root.get_children() + lights_root.get_children() + particles_root.get_children() + cube_models_root.get_children()


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
	return {"map": _map_dict(), "sel": sel, "pt": selected_point, "t": Time.get_ticks_msec()}


func _restore(s: Dictionary) -> void:
	_map_changed()
	var before := _co_step_before()                 # (what every object was, so the others can follow the step)
	var keep := _co_foreign_since(int(s.get("t", 0)))   # (what they changed since: not ours to undo)
	_co_mute = true
	_restore_dict(s["map"])
	var objs := _all_objects()
	var sel: int = s["sel"]
	if sel >= 0 and sel < objs.size():
		_select(objs[sel], s["pt"])
	_co_mute = false
	_co_queue.clear()
	if before.is_empty():
		_co_seed()
		return
	_co_step_after(before)
	_co_put_back(keep)


## The objects another editor changed after an undo step's checkpoint: their changes came after ours, so a step back
## here must not take them back too. Each is [kind, state, where it was].
func _co_foreign_since(since: int) -> Array:
	var out := []
	if relay == null or not relay.is_open() or since <= 0:
		return out
	for o in _all_objects():
		if not is_instance_valid(o) or not o.has_meta("co_remote_at"):
			continue
		if int(o.get_meta("co_remote_at")) <= since:
			continue
		out.append([_co_kind(o), _with_group(o), (o as Node3D).center()])
	return out


## Put their changes back on top of the step we just took, without telling them (they made them).
func _co_put_back(list: Array) -> void:
	if list.is_empty():
		return
	_co_mute = true
	for entry in list:
		var kind := String(entry[0])
		var at: Vector3 = entry[2]
		var best: Node3D = null
		var best_d := 60.0
		for o in _all_objects():
			if _co_kind(o) != kind or not is_instance_valid(o):
				continue
			var d: float = (o as Node3D).center().distance_to(at)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			continue
		best.from_dict(entry[1])
		_take_group(best, entry[1])
		if best.has_method("rebuild"):
			best.rebuild()
		best.set_meta("co_remote_at", Time.get_ticks_msec())
		_co_queue.erase(best)                       # (they already have this version: nothing to send)
		_co_new_now.erase(best)
	_co_mute = false
	_co_seed()


## Every object as it is right now, for an undo or redo to compare its result against. Empty when nobody else is
## in the session.
func _co_step_before() -> Array:
	if relay == null or not relay.is_open() or not (session_role in ["maker", "editor"]):
		return []
	var out := []
	for o in _all_objects():
		if is_instance_valid(o):
			out.append({"uid": _co_uid(o), "kind": _co_kind(o), "at": o.center(),
				"state": JSON.stringify(_with_group(o))})
	return out


## Undo and redo rebuild the whole map, which leaves the others behind. This finds each object it re-made, gives
## it back the name the others know it by, and queues what the step changed: the edits, additions and deletions
## go out the usual way, so a step back here is a step back there.
func _co_step_after(before: Array) -> void:
	var used := []
	used.resize(before.size())
	used.fill(false)
	var here := []
	for o in _all_objects():
		if is_instance_valid(o):
			here.append(o)
	var matched := []
	matched.resize(here.size())
	matched.fill(-1)
	for i in here.size():                                   # (exactly as it was: nothing to say about it)
		var kind := _co_kind(here[i])
		var state := JSON.stringify(_with_group(here[i]))
		for j in before.size():
			if not used[j] and String(before[j]["kind"]) == kind and String(before[j]["state"]) == state:
				used[j] = true
				matched[i] = j
				break
	for kind in ["ramp", "entity", "prop", "block", "text", "light", "particle", "cube"]:
		var mine := []                                       # (the step changed these rather than adding them)
		for i in here.size():
			if matched[i] < 0 and _co_kind(here[i]) == kind:
				mine.append(i)
		var theirs := []
		for j in before.size():
			if not used[j] and String(before[j]["kind"]) == kind:
				theirs.append(j)
		if mine.size() != theirs.size():                     # (a different count: some really were added or removed)
			continue
		for i in mine:
			var pick := -1
			var best := INF
			for j in theirs:
				var d: float = (before[j]["at"] as Vector3).distance_to(here[i].center())
				if d < best:
					best = d
					pick = j
			if pick < 0:
				continue
			theirs.erase(pick)
			used[pick] = true
			matched[i] = pick
	var changed := []
	var made := []
	for i in here.size():
		if matched[i] >= 0:
			here[i].set_meta("co_uid", String(before[matched[i]]["uid"]))
			if String(before[matched[i]]["state"]) != JSON.stringify(_with_group(here[i])):
				changed.append(here[i])
		else:
			made.append(here[i])
	_co_seed()                                               # (everything is known again, under those names)
	for o in changed:
		_co_queue[o] = true
		if o is CubeModelNode:
			o.world.changed_all = true                   # (just marked as in step: it has to go whole, not as no changes)
	for o in made:
		_co_new_now[o] = true
	for j in before.size():
		if not used[j]:
			_co_dels.append([String(before[j]["kind"]), String(before[j]["uid"])])


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
## Everything selected, the lead object first.
func selection() -> Array:
	var out := []
	if selected and is_instance_valid(selected):
		out.append(selected)
	for o in _extra:
		if is_instance_valid(o) and not o.is_queued_for_deletion() and o != selected:
			out.append(o)
	return out


## Select `obj` and the rest of its group; with `add`, add them to (or, if already there, take them out of) the
## current selection.
func _select_with_group(obj: Node3D, add := false) -> void:
	var members := _group_of(obj)
	if add:
		var cur := selection()
		if obj in cur:
			for m in members:
				cur.erase(m)
		else:
			for m in members:
				if not m in cur:
					cur.append(m)
		_set_selection(cur)
		return
	_select(obj)
	_extra = members.filter(func(m): return m != obj)
	_refresh_props()


func _set_selection(objs: Array) -> void:
	_select(objs[0] if not objs.is_empty() else null)
	_extra = objs.slice(1)
	_refresh_props()
	outliner.sync_selection()


func _group_of(obj: Node3D) -> Array:
	if obj == null or not obj.has_meta("group"):
		return [obj] if obj else []
	var g = obj.get_meta("group")
	return _all_objects().filter(func(o): return o.has_meta("group") and o.get_meta("group") == g)


func _select(obj: Node3D, point := -1) -> void:
	if obj != selected:
		_block_side = "all"
	_extra = []
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
		if d.length() < 0.5:                            # traveling straight at or away from this view
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


## A small padlock icon centered on `at`.
func _draw_padlock(ov: Control, at: Vector2, col: Color) -> void:
	for pass_col in [Color(0, 0, 0, 0.8), col]:
		var grow := 1.5 if pass_col.a > 0.75 and pass_col.r == 0.0 else 0.0
		ov.draw_arc(at + Vector2(0, -2), 4.0, PI, TAU, 10, pass_col, 2.0 + grow * 2.0)
		ov.draw_rect(Rect2(at + Vector2(-6 - grow, -2 - grow), Vector2(12 + grow * 2, 9 + grow * 2)), pass_col, true)


## The best run's path, colored by speed: blue slow -> green -> yellow -> red at its top speed.
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


## A color per tester, the same in every view (and the same for their live dot and their finished routes).
static func _tester_color(who: String) -> Color:
	return Color.from_hsv(float(absi(who.hash()) % 997) / 997.0, 0.62, 1.0)


static func _peer_pos(m: Dictionary) -> Vector3:
	var p: Array = m.get("p", [])
	return Vector3(p[0], p[1], p[2]) if p.size() >= 3 else Vector3.ZERO


## Where every tester is right now: a fading trail of their last few positions, then a dot with their name, speed
## and stage.
func _draw_live_peers(cam: Camera3D, ov: Control) -> void:
	var font := ov.get_theme_default_font()
	for id in live_peers:
		var m: Dictionary = live_peers[id]
		var col := _tester_color(String(m.get("name", id)))
		var trail: Array = live_trails.get(id, [])
		var prev := Vector2.INF
		for k in trail.size():
			var p: Vector3 = trail[k] + Vector3(0, 0.9, 0)
			if cam.is_position_behind(p):
				prev = Vector2.INF
				continue
			var s := cam.unproject_position(p)
			if prev != Vector2.INF:
				ov.draw_line(prev, s, Color(col, lerpf(0.12, 0.8, float(k + 1) / maxf(trail.size(), 1.0))), 3.0)
			prev = s
		var head := _peer_pos(m) + Vector3(0, 0.9, 0)
		if cam.is_position_behind(head):
			continue
		var at := cam.unproject_position(head)
		ov.draw_circle(at, 7.0, Color(0, 0, 0, 0.6))
		ov.draw_circle(at, 5.0, col)
		ov.draw_arc(at, 9.0, 0.0, TAU, 24, col, 2.0)
		var t := String(m.get("name", "?"))
		if String(m.get("state", "run")) == "wait":
			t += "  waiting"
		else:
			t += "  %d u/s" % int(m.get("speed", 0))
		if int(m.get("stage", 0)) > 0:
			t += "  ·  stage %d" % int(m.get("stage", 0))
		ov.draw_string_outline(font, at + Vector2(13, -9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, at + Vector2(13, -9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


## Every tester run's path in that tester's color, with an × where they fell. Decimated: a long run is thousands of
## samples and every view redraws this each frame.
func _draw_tester_paths(cam: Camera3D, ov: Control) -> void:
	for run in tester_runs:
		if not run is Dictionary:
			continue
		var col := _tester_color(String(run.get("tester", "?")))
		for a in (run.get("attempts", []) as Array):
			if not a is Dictionary:
				continue
			var route: Array = a.get("route", [])
			var step := maxi(1, route.size() / 400)
			var prev := Vector2.INF
			var i := 0
			while i < route.size():
				var r = route[i]
				i += step
				if not r is Array or (r as Array).size() < 3:
					prev = Vector2.INF
					continue
				var p := Vector3(r[0], r[1], r[2]) + Vector3(0, 0.5, 0)
				if cam.is_position_behind(p):
					prev = Vector2.INF
					continue
				var s := cam.unproject_position(p)
				if prev != Vector2.INF:
					ov.draw_line(prev, s, Color(col, 0.75), 2.0)
				prev = s
			for d in (a.get("deaths", []) as Array):
				if not d is Array or (d as Array).size() < 3:
					continue
				var p := Vector3(d[0], d[1], d[2])
				if cam.is_position_behind(p):
					continue
				var s := cam.unproject_position(p)
				for w in [Color(0, 0, 0, 0.8), Color(1.0, 0.35, 0.3)]:
					ov.draw_line(s + Vector2(-5, -5), s + Vector2(5, 5), w, 2.0)
					ov.draw_line(s + Vector2(-5, 5), s + Vector2(5, -5), w, 2.0)


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
	_ui_root.add_child(_unlock_confirm)


func _refresh_lock_props(r: RampNode) -> void:
	var n := r.frozen.size()
	var sp := selected_point
	var text := ""
	if n == 0:
		text = "Select a point and lock it (L) to freeze the ramp up to there. Everything after it becomes a new section you can reshape freely - the locked part never changes."
	else:
		text = "%d locked section%s (gray) + the editable section (blue). Points up to %d are frozen; the orange line is the seam. Slope angle and face length now only change the editable section; they blend in from the seam." % [
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


## A toolbar button (or a separator for "|").
func _bar_item(bar: Container, spec: Array) -> void:
	if spec[0] == "|":
		bar.add_child(VSeparator.new())
		return
	var b := Button.new()
	b.text = spec[0]
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(spec[1])
	bar.add_child(b)


## A toolbar menu. Items are [label, shortcut shown, action, optional check id] or [] for a separator; the
## shortcuts are only shown here, the keys themselves are handled with the rest of the keyboard.
func _menu(bar: Container, title: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = title
	mb.flat = false
	mb.focus_mode = Control.FOCUS_NONE
	mb.set_disable_shortcuts(true)                       # (else the menus run their keys first, even while flying)
	var pm := mb.get_popup()
	var actions := {}
	for it in items:
		if it.is_empty():
			pm.add_separator()
			continue
		var id := actions.size()
		if it.size() > 3:
			pm.add_check_item(it[0], id)
			_fields["menu_" + it[3]] = [pm, pm.get_item_index(id)]
		else:
			pm.add_item(it[0], id)
		if it[1] != KEY_NONE:
			pm.set_item_accelerator(pm.get_item_index(id), it[1])
		actions[id] = it[2]
	pm.id_pressed.connect(func(id): actions[id].call())
	bar.add_child(mb)
	_fields["menu_" + title.get_slice(" ", 0)] = mb
	return mb


## Tick the View and Add menus' check items to match the current settings.
func _sync_view_menu() -> void:
	for pair in [["arcs", show_all_arcs], ["arrows", show_direction], ["ghost", show_ghost_path], ["paths", show_tester_paths], ["cores", show_co_editors], ["draw", _draw_mode],
			["groundgrid", _ground_grid != null and _ground_grid.visible],
			["playtest", _playtest_panel != null and _playtest_panel.visible],
			["outliner", _outliner_panel != null and _outliner_panel.visible]]:
		if _fields.has("menu_" + pair[0]):
			var m: Array = _fields["menu_" + pair[0]]
			(m[0] as PopupMenu).set_item_checked(m[1], pair[1])
	if _fields.has("playtest_button"):
		(_fields["playtest_button"] as CheckButton).set_pressed_no_signal(_playtest_panel != null and _playtest_panel.visible)
	_redraw_overlays()


func _toggle_ground_grid() -> void:
	_ground_grid.visible = not _ground_grid.visible
	Settings.set_value("ground_grid", _ground_grid.visible)
	_sync_view_menu()


## Forget the map's best run (time and path) - asks first, as it isn't part of undo.
func _clear_best_clicked() -> void:
	if best_ghost.is_empty():
		return
	var d := ConfirmationDialog.new()
	d.title = "Clear best run"
	d.dialog_text = "Forget the best run (%s) and its path? This can't be undone." % PlayMode.format_time(float(best_ghost["time"]))
	d.ok_button_text = "Clear it"
	_ui_root.add_child(d)
	d.confirmed.connect(func():
		clear_best_run()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()


func clear_best_run() -> void:
	best_ghost = {}
	_refresh_info()
	_redraw_overlays()
	_set_status("Best run cleared: the next finished run sets a new one.")


## Presentation mode (for videos and screenshots): only the 3D view, no toolbar, panel or status line.
func set_presentation(on: bool) -> void:
	_fields["toolbar"].visible = not on
	_props_panel.visible = not on
	if _outliner_panel:
		_outliner_panel.visible = not on
	_status.get_parent().visible = not on if _status.get_parent() is PanelContainer else true
	_status.visible = not on
	for i in panes.size():
		panes[i].visible = (i == 0) if on else (quad_view or i == 0)
	_view_grid.columns = 1 if on else (2 if quad_view else 1)


func _set_title(map_name: String) -> void:
	get_window().title = MalletVersion.full() + ("  -  " + map_name if map_name != "" else "")


## F11: fullscreen (no title bar - handy for recording) and back.
var _mouse_dialog: AcceptDialog


## View > Mouse sensitivity: how fast the mouse turns the view in the editor's 3D view, in build mode and in play
## mode (that one uses the same numbers as SurfsUp and CS:S), and inverted up / down. Saved for next time.
func _open_mouse_settings() -> void:
	if _mouse_dialog == null:
		_mouse_dialog = AcceptDialog.new()
		_mouse_dialog.title = "Mouse sensitivity"
		_mouse_dialog.ok_button_text = "Done"
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(460, 0)
		box.add_theme_constant_override("separation", 6)
		_mouse_dialog.add_child(box)
		for spec in [["editor_mouse", "Editor 3D view (orbit / fly with the right mouse button)", 0.1, 5.0, 0.05, "x"],
				["play_mouse", "Mouse sensitivity, in Source's numbers (1.2 = CS:S 1.2). Build mode and play mode\nboth use it.", 0.1, 20.0, 0.05, ""]]:
			var l := Label.new()
			l.text = spec[1]
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(l)
			var row := HBoxContainer.new()
			box.add_child(row)
			var sl := HSlider.new()
			sl.min_value = spec[2]
			sl.max_value = spec[3]
			sl.step = spec[4]
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sl.value = float(Settings.value(spec[0]))
			var sb := SpinBox.new()
			sb.min_value = spec[2]
			sb.max_value = spec[3]
			sb.step = spec[4]
			sb.suffix = spec[5]
			sb.value = sl.value
			sb.custom_minimum_size = Vector2(96, 0)
			var key: String = spec[0]
			sl.value_changed.connect(func(v): sb.set_value_no_signal(v); _set_mouse(key, v))
			sb.value_changed.connect(func(v): sl.set_value_no_signal(v); _set_mouse(key, v))
			row.add_child(sl)
			row.add_child(sb)
			_fields["mouse_" + key] = [sl, sb]
		var inv := CheckButton.new()
		inv.text = "Invert mouse up / down (everywhere)"
		inv.button_pressed = Settings.invert_y()
		inv.toggled.connect(func(on): _set_mouse("invert_y", on))
		box.add_child(inv)
		_fields["mouse_invert_y"] = inv
		var reset := Button.new()
		reset.text = "Back to the defaults"
		reset.pressed.connect(func():
			for k in ["editor_mouse", "play_mouse"]:
				var pair: Array = _fields["mouse_" + k]
				(pair[0] as HSlider).value = Settings.DEFAULTS[k]
			(_fields["mouse_invert_y"] as CheckButton).button_pressed = false)
		box.add_child(reset)
		_ui_root.add_child(_mouse_dialog)
	_mouse_dialog.popup_centered()


func _set_mouse(key: String, v) -> void:
	Settings.set_value(key, v)
	if play.active:
		play.apply_mouse_settings()


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
	_ui_root.add_child(_prop_dialog)


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
	_add_slider(_block_props, "block_pitch", "Tilt forward / back (\u00b0)", -90.0, 90.0, 1.0)
	_add_slider(_block_props, "block_roll", "Tilt sideways (\u00b0)", -90.0, 90.0, 1.0)
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
	var mat_head := Label.new()
	mat_head.text = "Material"
	mat_head.add_theme_font_size_override("font_size", 15)
	_block_props.add_child(mat_head)
	_fields["block_mat_head"] = mat_head
	var side := OptionButton.new()
	side.add_item("All sides")
	for sl in BlockShape.SLOTS:
		side.add_item(BlockShape.SLOT_LABELS[sl] + " side")
	side.focus_mode = Control.FOCUS_NONE
	side.tooltip_text = "Pick a side to give it its own material and texture placement. Tip: Alt+click any face in a view to paint the last material you picked onto it."
	side.item_selected.connect(func(i): _block_side = "all" if i == 0 else BlockShape.SLOTS[i - 1]; _refresh_props())
	_add_row(_block_props, "Side", side)
	_fields["block_side"] = side
	var mb := Button.new()
	mb.focus_mode = Control.FOCUS_NONE
	mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mb.custom_minimum_size = Vector2(0, 40)
	mb.pressed.connect(func(): _open_picker(func(id): _edit_prop("block_mat", id)))
	_block_props.add_child(mb)
	_fields["block_mat"] = mb
	var uv_box := VBoxContainer.new()
	_block_props.add_child(uv_box)
	_fields["block_uv_box"] = uv_box
	_add_slider(uv_box, "block_uv_scale", "Texture size (x)", 0.1, 10.0, 0.05)
	_add_slider(uv_box, "block_uv_u", "Texture shift across", 0.0, 1.0, 0.01)
	_add_slider(uv_box, "block_uv_v", "Texture shift up", 0.0, 1.0, 0.01)
	_add_slider(uv_box, "block_uv_rot", "Texture turn (\u00b0)", -180.0, 180.0, 5.0)
	var look_box := VBoxContainer.new()
	_block_props.add_child(look_box)
	_fields["block_look_box"] = look_box
	var look := OptionButton.new()
	for k in BLOCK_LOOKS:
		look.add_item(Look.RAMP_LOOKS[k][0])
	look.focus_mode = Control.FOCUS_NONE
	look.item_selected.connect(func(i): _edit_prop("block_look", BLOCK_LOOKS[i]))
	_add_row(look_box, "Look", look)
	_fields["block_look"] = look
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("block_color", c))
	_add_row(look_box, "Color", cp)
	_fields["block_color"] = cp
	_add_slider(look_box, "block_glow", "Glow", 0.0, 8.0, 0.1)
	_surface_shader_box(look_box, "block_")
	var water_box := VBoxContainer.new()
	_block_props.add_child(water_box)
	_fields["block_water_box"] = water_box
	var lq := OptionButton.new()                          # a liquid preset: water, pool, sea, lake, swamp, river, acid, lava...
	for k in Look.LIQUID_ORDER:
		lq.add_item(Look.LIQUIDS[k]["label"])
	lq.focus_mode = Control.FOCUS_NONE
	lq.item_selected.connect(func(i): if not _updating_ui: _edit_prop("block_liquid", Look.LIQUID_ORDER[i]); _refresh_props())
	_add_row(water_box, "Liquid", lq)
	_fields["block_liquid"] = lq
	var wc := ColorPickerButton.new()
	wc.custom_minimum_size = Vector2(0, 26)
	wc.color_changed.connect(func(c): _edit_prop("block_water_color", c))
	_add_row(water_box, "Water color", wc)
	_fields["block_water_color"] = wc
	_add_slider(water_box, "block_clarity", "Clarity", 0.0, 1.0, 0.05)
	var deadly := CheckButton.new()
	deadly.text = "Deadly (sends players back - lava, acid)"
	deadly.focus_mode = Control.FOCUS_NONE
	deadly.toggled.connect(func(on): _edit_prop("block_deadly", on))
	water_box.add_child(deadly)
	_fields["block_deadly"] = deadly
	var wnote := Label.new()
	wnote.text = "SurfsUp has no swimming: water is something to look at (or, if deadly, to avoid). In CS:S it's real water."
	wnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wnote.add_theme_font_size_override("font_size", 12)
	wnote.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	water_box.add_child(wnote)


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


## U12: a block that build mode edits becomes a cube object - one cell for a plain, cube-shaped box (1, 2, 4 or 8 m
## on every side). It keeps its material, its name, its folder and its group, and the swap is one undo step. Returns
## {"model", "sel"} or {"error": why not}, because a cutter, water or a shaped block has no one-cell equivalent.
func block_to_cube(b: BlockNode) -> Dictionary:
	if b == null or not is_instance_valid(b):
		return {"error": "That block is gone."}
	if b.is_cutter():
		return {"error": "A cutter block stays a block: cubes have no cutters."}
	if bool(b.data.get("water", false)):
		return {"error": "Water stays a block: use build mode's water material for a water volume."}
	if String(b.data.get("shape", "box")) != "box":
		return {"error": "Only a plain box can become a cube; this block is a %s." % String(b.data.get("shape", "box"))}
	if bool(b.data.get("hollow", false)):
		return {"error": "Only a solid box can become a cube; untick Hollow first."}
	var sz := b.size()
	var p := -1
	for i in 4:
		if absf(sz.x - float(1 << i)) < 0.001 and absf(sz.y - float(1 << i)) < 0.001 and absf(sz.z - float(1 << i)) < 0.001:
			p = i
	if p < 0:
		return {"error": "A cube cell is 1, 2, 4 or 8 m on every side; this block is %s." % str(sz).replace(", 0", ".0")}
	var yaw_deg := fposmod(float(b.data.get("yaw", 0.0)), 360.0)
	var quarter := roundf(yaw_deg / 90.0) * 90.0
	if absf(angle_difference(deg_to_rad(yaw_deg), deg_to_rad(quarter))) > deg_to_rad(0.5):
		return {"error": "A cube can turn in 90 degree steps only; this block is turned %.1f degrees." % yaw_deg}
	_checkpoint()
	var pos: Array = b.data["position"]                   # (base center: x/z middle, y bottom)
	var meters := Vector3(float(pos[0]) - sz.x * 0.5, float(pos[1]), float(pos[2]) - sz.z * 0.5)
	var m := CubeModelNode.new()
	cube_models_root.add_child(m)
	m.position = meters
	m.yaw = quarter
	m.basis = Basis(Vector3.UP, deg_to_rad(quarter))
	var sel := CubeWorld.make_sel(Vector3i.ZERO, p, 3)
	var tex := CubeWorld.blank_tex(String(b.data.get("material", "")))
	m.world.begin()
	m.world.set_cell(Vector3i.ZERO, p, CubeWorld.FULL.duplicate(), tex)
	m.world.commit()
	for key in ["group", "name", "folder", "hidden"]:   # (keeps its place in the Outliner)
		if b.has_meta(key):
			m.set_meta(key, b.get_meta(key))
	if bool(b.get_meta("hidden", false)):
		m.visible = false
	blocks_root.remove_child(b)
	b.queue_free()
	_rebuild_blocks()
	m.rebuild_all()
	_select(m)
	_set_status("That block is a cube object now (one %s m cell): push its faces here, and it still edits as one object in the views." % str(1 << p))
	sel["model"] = m
	return {"model": m, "sel": sel}


func _toggle_draw_mode() -> void:
	_draw_mode = not _draw_mode
	_sync_view_menu()
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
	var box := _draw_box(a, b, pane.drag_axes(false), _last_block["size"], _view_center().y)
	var size: Vector3 = box["size"]
	var base: Vector3 = box["base"]
	_draw_block.from_dict({"position": [base.x, base.y, base.z], "size": [size.x, size.y, size.z]})
	_set_status("Block %.2f x %.2f x %.2f m" % [size.x, size.y, size.z])


## The block a drag from corner `a` to corner `b` makes: its center and size, in meters. A block's position is its
## center while a drag works in corners, so the corners turn into a center here and nowhere else (U11) - the axis
## the view looks along keeps the last size used (Hammer does the same) and is centered on the view plane.
func _draw_box(a: Vector3, b: Vector3, axes: Vector3, last: Array, mid_y: float) -> Dictionary:
	var lo := a.min(b)
	var hi := a.max(b)
	var size := Vector3(maxf(hi.x - lo.x, 0.25), maxf(hi.y - lo.y, 0.25), maxf(hi.z - lo.z, 0.25))
	var base := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
	for i in 3:
		if axes[i] >= 0.5:
			continue
		size[i] = float(last[i])
		if i == 1:
			base.y = snappedf(mid_y, snap_step if snap_enabled else 0.25)
		else:
			base[i] = a[i] + (size[i] * 0.5 if b[i] >= a[i] else -size[i] * 0.5)
	return {"size": size, "base": base, "lo": lo}
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


# ------------------------------------------------------------------------------------------------ position fields
## Position of the selection as three numbers you can drag without limit (or click to type). For text lying on a
## block face: Across and Up on that face, measured from its center (type 0 to center it).
var _pos_box: GridContainer
var _pos_fields: Array = []
var _pos_labels: Array = []
var _pos_state := {}                                ## what the fields show: {obj, center, face}


func _build_position_box(props: VBoxContainer) -> void:
	_pos_box = GridContainer.new()
	_pos_box.columns = 2
	_pos_box.add_theme_constant_override("h_separation", 8)
	props.add_child(_pos_box)
	for i in 3:
		var l := Label.new()
		l.custom_minimum_size = Vector2(56, 0)
		_pos_box.add_child(l)
		_pos_labels.append(l)
		var dn := DragNumber.new()
		dn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dn.drag_started.connect(func(): _checkpoint())
		dn.changed_by.connect(func(a): _move_selection_along(i, a))
		dn.typed.connect(func(v): _checkpoint(); _move_selection_along(i, v - _pos_value(i)))
		_pos_box.add_child(dn)
		_pos_fields.append(dn)
	_pos_box.visible = false


## The direction field i moves along: world X / Y / Z, or the face's across / up / out for text on a face.
func _pos_axis(i: int) -> Vector3:
	var face: Dictionary = _pos_state.get("face", {})
	if not face.is_empty():
		return [face["ax"], face["ay"], face["normal"]][i]
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][i]


func _pos_value(i: int) -> float:
	var c: Vector3 = _pos_state.get("center", Vector3.ZERO)
	var face: Dictionary = _pos_state.get("face", {})
	if not face.is_empty():
		return (c - (face["center"] as Vector3)).dot(_pos_axis(i))
	return c[i]


func _move_selection_along(i: int, amount: float) -> void:
	if selected == null or amount == 0.0:
		return
	var d := _pos_axis(i) * amount
	var any_block := false
	for o in selection():
		o.translate_by(d)
		any_block = any_block or o is BlockNode
	if any_block:
		_mark_blocks()
	_map_changed()
	_pos_state["center"] = selected.center()
	_refresh_info()


func _refresh_position() -> void:
	var obj = selected if selected != null and selected.has_method("center") and selected.has_method("translate_by") else null
	_pos_box.visible = obj != null and _gen_ramp == null
	if obj == null:
		_pos_state = {}
		return
	var c: Vector3 = obj.center()
	if _pos_state.get("obj") != obj or not (_pos_state.get("center", Vector3.INF) as Vector3).is_equal_approx(c):
		var face := {}
		if obj is TextNode and selection().size() == 1:
			face = _text_face(obj)
		_pos_state = {"obj": obj, "center": c, "face": face}
		var names := ["Across", "Up", "Out"] if not face.is_empty() else ["X", "Y", "Z"]
		for i in 3:
			_pos_labels[i].text = names[i]
			_pos_labels[i].visible = i < 2 or face.is_empty()
			_pos_fields[i].visible = i < 2 or face.is_empty()
			_pos_fields[i].show_value(_pos_value(i))


# ------------------------------------------------------------------------------------------------ lights, water, prefabs
func _build_light_props(props: VBoxContainer) -> void:
	_light_props = VBoxContainer.new()
	_light_props.add_theme_constant_override("separation", 6)
	_light_props.visible = false
	props.add_child(_light_props)
	var preset := OptionButton.new()                     # a starting point: torch, neon strip, alarm...
	preset.add_item("Pick a preset…")
	for k in LightNode.PRESET_ORDER:
		preset.add_item(LightNode.PRESETS[k]["label"])
	preset.focus_mode = Control.FOCUS_NONE
	preset.item_selected.connect(func(i):
		if i > 0 and not _updating_ui:
			_edit_prop("light_preset", LightNode.PRESET_ORDER[i - 1])
			_refresh_props())
	_add_row(_light_props, "Preset", preset)
	_fields["light_preset"] = preset
	var kind := OptionButton.new()
	kind.add_item("Point light (shines all around)")
	kind.add_item("Spot light (a cone)")
	kind.add_item("Light strip (a glowing tube: neon, fluorescent)")
	kind.focus_mode = Control.FOCUS_NONE
	kind.item_selected.connect(func(i): _edit_prop("light_kind", LightNode.KINDS[i]))
	_add_row(_light_props, "Kind", kind)
	_fields["light_kind"] = kind
	var fx := OptionButton.new()
	for l in LightNode.EFFECT_LABELS:
		fx.add_item(l)
	fx.focus_mode = Control.FOCUS_NONE
	fx.item_selected.connect(func(i): _edit_prop("light_effect", LightNode.EFFECTS[i]))
	_add_row(_light_props, "Effect", fx)
	_fields["light_effect"] = fx
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("light_color", c))
	_add_row(_light_props, "Color", cp)
	_fields["light_color"] = cp
	_add_slider(_light_props, "light_energy", "Brightness", 0.0, 16.0, 0.1)
	_add_slider(_light_props, "light_range", "Reach (m)", 1.0, 2000.0, 1.0)
	var strip := VBoxContainer.new()
	_light_props.add_child(strip)
	_fields["light_strip_box"] = strip
	_add_slider(strip, "light_length", "Length (m)", 0.5, 20.0, 0.5)
	_add_slider(strip, "light_strip_yaw", "Facing (\u00b0)", -180.0, 180.0, 5.0)
	var spot := VBoxContainer.new()
	_light_props.add_child(spot)
	_fields["light_spot_box"] = spot
	_add_slider(spot, "light_angle", "Cone width (\u00b0)", 5.0, 170.0, 1.0)
	_add_slider(spot, "light_yaw", "Facing (\u00b0)", -180.0, 180.0, 5.0)
	_add_slider(spot, "light_pitch", "Tilt (\u00b0, down is negative)", -90.0, 90.0, 1.0)
	var sh := CheckButton.new()
	sh.text = "Casts shadows"
	sh.focus_mode = Control.FOCUS_NONE
	sh.toggled.connect(func(on): _edit_prop("light_shadows", on))
	_light_props.add_child(sh)
	_fields["light_shadows"] = sh


## Particle effects: the preset, its color, how many, how big, how fast, and the area they start in.
func _build_particle_props(props: VBoxContainer) -> void:
	_particle_props = VBoxContainer.new()
	_particle_props.add_theme_constant_override("separation", 6)
	_particle_props.visible = false
	props.add_child(_particle_props)
	var preset := OptionButton.new()
	for k in ParticleNode.PRESET_ORDER:
		preset.add_item(ParticleNode.PRESETS[k]["label"])
	preset.focus_mode = Control.FOCUS_NONE
	preset.item_selected.connect(func(i): _edit_prop("fx_preset", ParticleNode.PRESET_ORDER[i]); _refresh_props())
	_add_row(_particle_props, "Effect", preset)
	_fields["fx_preset"] = preset
	var own := CheckButton.new()
	own.text = "Own color"
	own.focus_mode = Control.FOCUS_NONE
	own.toggled.connect(func(on): _edit_prop("fx_own_color", on); _refresh_props())
	_particle_props.add_child(own)
	_fields["fx_own_color"] = own
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("fx_color", c))
	_particle_props.add_child(cp)
	_fields["fx_color"] = cp
	_add_slider(_particle_props, "fx_amount", "Amount (x the preset)", 0.1, 5.0, 0.1)
	_add_slider(_particle_props, "fx_size", "Size (x)", 0.2, 5.0, 0.1)
	_add_slider(_particle_props, "fx_speed", "Speed (x)", 0.1, 4.0, 0.1)
	_add_slider(_particle_props, "fx_area_x", "Area width (m)", 0.1, 200.0, 0.1)
	_add_slider(_particle_props, "fx_area_y", "Area height (m)", 0.1, 100.0, 0.1)
	_add_slider(_particle_props, "fx_area_z", "Area depth (m)", 0.1, 200.0, 0.1)


func _add_particles(preset: String) -> void:
	_checkpoint()
	var c := _view_center()
	var pn := ParticleNode.new()
	particles_root.add_child(pn)
	pn.from_dict({"preset": preset, "position": [c.x, c.y + 2.0, c.z], "area": ParticleNode.PRESETS[preset]["area"]})
	_select(pn)
	_set_status("New particle effect. Pick fire, smoke, snow, rain and more in the panel; the box is where they start.")


func _add_light(kind: String) -> void:
	_checkpoint()
	var c := _view_center()
	var l := LightNode.new()
	lights_root.add_child(l)
	l.from_dict({"kind": kind, "position": [c.x, c.y + 6.0, c.z]})
	_select(l)
	_set_status("New %s. Color, brightness and reach are in the panel." % l.label().to_lower())


func _add_water_clicked() -> void:
	_checkpoint()
	var c := _view_center()
	var b := BlockNode.new()
	blocks_root.add_child(b)
	b.from_dict({"position": [c.x, c.y - 3.0, c.z], "size": [40.0, 6.0, 40.0], "water": true})
	_rebuild_blocks()
	_select(b)
	_set_status("New water. Resize it like a block; tick Deadly for lava or acid.")


## Add > Prefab: the starter prefabs and yours, each dropped in the middle of the 3D view.
func _open_prefabs() -> void:
	if _prefab_popup:
		_prefab_popup.queue_free()
	_prefab_popup = PopupPanel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.15)
	sb.set_content_margin_all(10)
	_prefab_popup.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	_prefab_popup.add_child(box)
	var head := Label.new()
	head.text = "Prefabs - click one to drop it into the map"
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	var mine_header := false
	for pf in Prefabs.list():
		if not pf["builtin"] and not mine_header:
			mine_header = true
			var h := Label.new()
			h.text = "Yours"
			box.add_child(h)
		var b := Button.new()
		b.text = pf["name"] + ("  -  " + pf["description"] if pf["description"] != "" else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var path: String = pf["path"]
		b.pressed.connect(func(): _prefab_popup.hide(); place_prefab(path))
		box.add_child(b)
		_fields["prefab_" + String(pf["name"])] = b
	if not mine_header:
		var tip := Label.new()
		tip.text = "Make your own: select some objects, then Edit > Save selection as prefab."
		tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
		box.add_child(tip)
	_ui_root.add_child(_prefab_popup)
	_prefab_popup.popup_centered()


func place_prefab(path: String) -> Array:
	var data := Prefabs.read(path)
	if data.is_empty():
		return []
	var objs := _paste(data, Vector3.ZERO, true)
	if objs.is_empty():
		return []
	var fid := outliner.new_folder(String(data.get("name", "Prefab")))
	for o in objs:
		o.set_meta("folder", fid)
	var mid := Vector3.ZERO
	for o in objs:
		mid += o.center()
	mid /= objs.size()
	var to := _view_center()
	if snap_enabled:
		to = to.snapped(Vector3.ONE * snap_step)
	for o in objs:
		o.translate_by(to - mid)
	_rebuild_blocks()
	_map_changed()
	_set_status("Placed the prefab '%s' (%d objects, selected - drag to move them)." % [data.get("name", "?"), objs.size()])
	return objs


func _save_prefab_clicked() -> void:
	if selection().is_empty():
		_set_status("Select what you want to keep as a prefab first.")
		return
	if _prefab_name_dialog == null:
		_prefab_name_dialog = ConfirmationDialog.new()
		_prefab_name_dialog.title = "Save as prefab"
		var box := VBoxContainer.new()
		_prefab_name_dialog.add_child(box)
		var l := Label.new()
		l.text = "Name"
		box.add_child(l)
		var name_edit := LineEdit.new()
		box.add_child(name_edit)
		_fields["prefab_name"] = name_edit
		var l2 := Label.new()
		l2.text = "Description (optional)"
		box.add_child(l2)
		var desc := LineEdit.new()
		box.add_child(desc)
		_fields["prefab_desc"] = desc
		_prefab_name_dialog.confirmed.connect(func(): save_prefab(_fields["prefab_name"].text, _fields["prefab_desc"].text))
		_ui_root.add_child(_prefab_name_dialog)
	_fields["prefab_name"].text = ""
	_fields["prefab_desc"].text = ""
	_prefab_name_dialog.popup_centered(Vector2i(420, 0))


func save_prefab(name: String, description := "") -> String:
	if name.strip_edges() == "":
		_set_status("A prefab needs a name.")
		return ""
	var path := Prefabs.save(name, _clip_of(selection()), description)
	_set_status("Saved the prefab '%s' (%d objects). Add > Prefab drops it into any map." % [name, selection().size()])
	return path


# ------------------------------------------------------------------------------------------------ text
func _build_text_props(props: VBoxContainer) -> void:
	_text_props = VBoxContainer.new()
	_text_props.add_theme_constant_override("separation", 6)
	_text_props.visible = false
	props.add_child(_text_props)
	var te := TextEdit.new()                             # multi-line: Enter starts a new line
	te.placeholder_text = "Type your text (Enter for a new line)"
	te.custom_minimum_size = Vector2(0, 74)
	te.scroll_fit_content_height = true
	te.text_changed.connect(func(): _edit_prop("text_text", te.text))
	_add_row(_text_props, "Text", te)
	_fields["text_text"] = te
	var mode := OptionButton.new()
	for m in TextShape.MODES:
		mode.add_item(TextShape.MODE_LABELS[m])
	mode.focus_mode = Control.FOCUS_NONE
	mode.item_selected.connect(func(i): _edit_prop("text_mode", TextShape.MODES[i]))
	_add_row(_text_props, "Kind", mode)
	_fields["text_mode"] = mode
	var place := Button.new()
	place.text = "Place on a surface (then click a face)"
	place.focus_mode = Control.FOCUS_NONE
	place.pressed.connect(func(): _place_on_surface = true; _set_status("Click the face to put the text on (Esc cancels)."))
	_text_props.add_child(place)
	var font := OptionButton.new()
	for f in TextShape.FONTS:
		font.add_item(f)
	font.add_item("Load a font file\u2026")
	font.focus_mode = Control.FOCUS_NONE
	font.item_selected.connect(func(i):
		if i < TextShape.FONTS.size():
			_edit_prop("text_font", TextShape.FONTS[i])
		else:
			_font_file_dialog().popup_centered_ratio(0.6))
	_add_row(_text_props, "Font", font)
	_fields["text_font"] = font
	var align := OptionButton.new()
	for a in ["Left", "Center", "Right"]:
		align.add_item(a)
	align.focus_mode = Control.FOCUS_NONE
	align.item_selected.connect(func(i): _edit_prop("text_align", ["left", "center", "right"][i]))
	_add_row(_text_props, "Align", align)
	_fields["text_align"] = align
	_add_slider(_text_props, "text_height", "Text size (letter height, m)", 0.25, 100.0, 0.25)
	_add_slider(_text_props, "text_depth", "Depth (m)", 0.05, 20.0, 0.05)
	_add_slider(_text_props, "text_yaw", "Facing (\u00b0)", -180.0, 180.0, 5.0)
	_add_slider(_text_props, "text_pitch", "Tilt forward / back (\u00b0)", -90.0, 90.0, 1.0)
	_add_slider(_text_props, "text_roll", "Tilt sideways (\u00b0)", -180.0, 180.0, 1.0)
	var solid := CheckButton.new()
	solid.text = "Solid (players collide with it)"
	solid.focus_mode = Control.FOCUS_NONE
	solid.toggled.connect(func(on): _edit_prop("text_solid", on))
	_text_props.add_child(solid)
	_fields["text_solid"] = solid
	var look := VBoxContainer.new()
	_text_props.add_child(look)
	_fields["text_look_box"] = look
	var mb := Button.new()
	mb.focus_mode = Control.FOCUS_NONE
	mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mb.custom_minimum_size = Vector2(0, 40)
	mb.pressed.connect(func(): _open_picker(func(id): _edit_prop("text_mat", id)))
	look.add_child(mb)
	_fields["text_mat"] = mb
	var cp := ColorPickerButton.new()
	cp.custom_minimum_size = Vector2(0, 26)
	cp.color_changed.connect(func(c): _edit_prop("text_color", c))
	_add_row(look, "Color", cp)
	_fields["text_color"] = cp
	_add_slider(look, "text_glow", "Glow", 0.0, 8.0, 0.1)


func _font_file_dialog() -> FileDialog:
	if _font_dialog == null:
		_font_dialog = FileDialog.new()
		_font_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_font_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_font_dialog.use_native_dialog = true
		_font_dialog.filters = PackedStringArray(["*.ttf, *.otf, *.woff, *.woff2 ; Fonts"])
		_font_dialog.file_selected.connect(func(path): _edit_prop("text_font", path))
		_ui_root.add_child(_font_dialog)
	return _font_dialog


func _add_text_clicked() -> void:
	_checkpoint()
	var c := _view_center()
	var cam := panes[0].camera as OrbitCamera
	var t := TextNode.new()
	texts_root.add_child(t)
	# face the 3D view so it reads straight away
	t.from_dict({"position": [c.x, c.y, c.z], "yaw": rad_to_deg(cam.yaw)})
	_select(t)
	_set_status("New text. Type in the panel; 'Place on a surface' sticks it onto a wall or floor.")


## Put the selected text flat on the face that was clicked: facing out of it, upright where possible.
func _place_text_on_surface(pane: ViewPane, mouse: Vector2) -> void:
	_place_on_surface = false
	if not selected is TextNode:
		return
	var r := pane.ray(mouse)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 20000.0)
	q.collision_mask = 1
	q.exclude = [(selected as TextNode)._body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_set_status("No surface there - try again with 'Place on a surface'.")
		return
	var z: Vector3 = (hit["normal"] as Vector3).normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.1:                                  # floor or ceiling: read along the camera's view
		var f := -pane.camera.global_basis.z
		x = Vector3(f.x, 0, f.z).cross(Vector3.UP) if Vector3(f.x, 0, f.z).length() > 0.1 else Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x).normalized()
	var e := Basis(x, y, z).get_euler(EULER_ORDER_YXZ)
	_checkpoint()
	var d: Dictionary = selected.data.duplicate(true)
	var p: Vector3 = hit["position"] + z * 0.005
	d["position"] = [p.x, p.y, p.z]
	d["pitch"] = rad_to_deg(e.x)
	d["yaw"] = rad_to_deg(e.y)
	d["roll"] = rad_to_deg(e.z)
	selected.from_dict(d)
	var centred := _centre_text_on_face(selected)
	_mark_blocks()
	_refresh_props()
	_set_status("Text placed on the surface%s. Drag it along the face; it snaps to the face's center lines." % (
		(" (snapped to the %s)" % centred) if centred != "" else ""))


## The block face a text lies flat on: {block, poly, normal, center, ax, ay, size_x, size_y} (ax / ay: the text's
## own across / up directions; sizes: the face's extent along them), or {} if it isn't on one.
func _text_face(t: TextNode) -> Dictionary:
	var xf := t.global_transform
	var out_dir := xf.basis.z.normalized()                # text faces out along its +Z
	var box := t.local_box
	var mid := xf * Vector3(box.get_center().x, box.get_center().y, 0.0)
	var q := PhysicsRayQueryParameters3D.create(mid + out_dir * 0.3, mid - out_dir * 0.3)
	q.collision_mask = 1 | BlockNode.PICK_ONLY_LAYER
	q.exclude = [t._body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or not hit["collider"].has_meta("block"):
		return {}
	var b: BlockNode = hit["collider"].get_meta("block")
	var poly: Array = []
	for piece in b.pieces:
		for f in Convex.faces(piece):
			var pl: Plane = f[0]
			if pl.normal.dot(out_dir) > 0.999 and absf(pl.distance_to(hit["position"])) < 0.05 					and _poly_has(f[1], hit["position"], pl.normal):
				poly = f[1]
		if not poly.is_empty():
			break
	if poly.is_empty():
		return {}
	var fc := Vector3.ZERO
	for v in poly:
		fc += v
	fc /= poly.size()
	var ax := xf.basis.x.normalized()
	var ay := xf.basis.y.normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in poly:
		var p2 := Vector2((v - fc).dot(ax), (v - fc).dot(ay))
		lo = lo.min(p2)
		hi = hi.max(p2)
	fc += ax * (lo.x + hi.x) * 0.5 + ay * (lo.y + hi.y) * 0.5     # the middle of the face's extent
	return {"block": b, "poly": poly, "normal": out_dir, "center": fc, "ax": ax, "ay": ay,
		"size_x": hi.x - lo.x, "size_y": hi.y - lo.y}


## While dragging text on a face: no drifting off it (out of its plane, or past its edges).
func _keep_on_face(t: TextNode, face: Dictionary, origin: Dictionary) -> void:
	var n: Vector3 = face["normal"]
	var p0 := Vector3(origin["position"][0], origin["position"][1], origin["position"][2])
	var p := Vector3(t.data["position"][0], t.data["position"][1], t.data["position"][2])
	var fix := -n * (p - p0).dot(n)                       # back onto the face's plane
	var box := t.local_box
	var mid := t.global_transform * Vector3(box.get_center().x, box.get_center().y, 0.0) + fix
	var off := mid - (face["center"] as Vector3)
	for k in [["ax", "size_x", box.size.x], ["ay", "size_y", box.size.y]]:
		var a: Vector3 = face[k[0]]
		var lim: float = maxf(face[k[1]] * 0.5 - float(k[2]) * 0.5, 0.0)   # the whole text stays on the face
		var d := off.dot(a)
		if absf(d) > lim:
			fix -= a * (d - signf(d) * lim)
	if fix.length() > 1e-6:
		t.translate_by(fix)


## If the text lies flat on a block's face, snap it onto that face's center lines when it's close to them (each
## direction on its own, like design apps). Returns what it snapped to ("center", "middle line", ...) or "".
func _centre_text_on_face(t: TextNode) -> String:
	var face := _text_face(t)
	if face.is_empty():
		return ""
	var box := t.local_box
	var mid := t.global_transform * Vector3(box.get_center().x, box.get_center().y, 0.0)
	var fc: Vector3 = face["center"]
	var ax: Vector3 = face["ax"]
	var ay: Vector3 = face["ay"]
	var dx := (fc - mid).dot(ax)
	var dy := (fc - mid).dot(ay)
	var fix := Vector3.ZERO
	var got := []
	if absf(dx) < maxf(0.75, float(face["size_x"]) * 0.06):
		fix += ax * dx
		got.append("x")
	if absf(dy) < maxf(0.75, float(face["size_y"]) * 0.06):
		fix += ay * dy
		got.append("y")
	if fix.length() > 1e-6:
		t.translate_by(fix)
	if got.size() == 2:
		return "center"
	if got.has("x"):
		return "center line (left to right)"
	if got.has("y"):
		return "middle line (top to bottom)"
	return ""


static func _poly_has(poly: Array, p: Vector3, n: Vector3) -> bool:
	for i in poly.size():
		var a: Vector3 = poly[i]
		var c: Vector3 = poly[(i + 1) % poly.size()]
		if (c - a).cross(p - a).dot(n) < -1e-4:
			return false
	return true


## The material library: thumbnails by category. `cb` gets the chosen material id ("" = none).
func _open_picker(cb: Callable) -> void:
	_picker_cb = cb
	if _picker == null:
		_picker = PopupPanel.new()
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(780, 620)      # (5 thumbnails a row + the bar: no sideways scrolling)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_picker.add_child(scroll)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.12, 0.15)
		sb.set_content_margin_all(10)
		sb.set_corner_radius_all(8)
		_picker.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		box.add_child(row)
		var none := Button.new()
		none.text = "No material (use the Look & color)"
		none.focus_mode = Control.FOCUS_NONE
		none.pressed.connect(func(): _picker.hide(); _picker_cb.call(""))
		row.add_child(none)
		var own := Button.new()
		own.text = "+ Your own image\u2026"
		own.focus_mode = Control.FOCUS_NONE
		own.tooltip_text = "Use any PNG / JPG / WebP as a material. It joins 'Your images' in this library."
		own.pressed.connect(func(): _picker.hide(); _own_image_dialog().popup_centered_ratio(0.6))
		row.add_child(own)
		var search := LineEdit.new()                     # type to narrow a big library down
		search.placeholder_text = "Search materials (brick, metal, glow...)"
		search.clear_button_enabled = true
		box.add_child(search)
		_fields["picker_search"] = search
		var sections := []                               # [header, credit label, grid, [[button, words]]]
		for cat in MaterialLibrary.categories():
			var head := Label.new()
			head.text = cat
			head.add_theme_font_size_override("font_size", 15)
			box.add_child(head)
			var credit := Label.new()
			credit.add_theme_font_size_override("font_size", 12)
			credit.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
			credit.visible = false
			box.add_child(credit)
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_theme_constant_override("h_separation", 6)
			grid.add_theme_constant_override("v_separation", 6)
			box.add_child(grid)
			var items := []
			sections.append([head, credit, grid, items])
			for e in MaterialLibrary.entries():
				if e["category"] != cat:
					continue
				if e.has("credit") and not credit.visible:
					credit.text = ("Textures by %s - thank you! License: %s." % [e["credit"], e["license"]]) if e.has("license") 						else "Textures by %s - thank you! Used with permission." % e["credit"]
					credit.visible = true
				var b := Button.new()
				b.icon = MaterialLibrary.preview(e["id"])
				b.text = e["name"]
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				b.expand_icon = true
				b.custom_minimum_size = Vector2(128, 132)
				b.focus_mode = Control.FOCUS_NONE
				b.tooltip_text = "%s - one repeat covers %.1f m%s%s" % [e["name"], float(e["size"]),
					" - glows" if (e.get("maps", {}) as Dictionary).has("glow") else "", ((" - by " + e["credit"]) + ((" from a photo by " + e["photo"]) if e.has("photo") else "")) if e.has("credit") else ""]
				var id: String = e["id"]
				b.pressed.connect(func(): _picker.hide(); _picker_cb.call(id))
				grid.add_child(b)
				_fields["pick_" + id] = b
				items.append([b, ("%s %s %s %s %s" % [e["name"], e["id"], cat, e.get("surface", ""),
					"glow" if (e.get("maps", {}) as Dictionary).has("glow") else ""]).to_lower()])
		var css_folders := _picker_css_section(box)
		search.text_changed.connect(func(t: String):
			var q := t.strip_edges().to_lower()
			for sec in sections:
				var shown := 0
				for it in sec[3]:
					it[0].visible = q == "" or (it[1] as String).contains(q)
					shown += 1 if it[0].visible else 0
				sec[0].visible = shown > 0
				sec[2].visible = shown > 0
				sec[1].visible = shown > 0 and (sec[1] as Label).text != ""
			for fo in css_folders:                       # CS:S folders: open (and fill) only the ones with matches
				fo.search(q))
		_ui_root.add_child(_picker)
	_picker.popup_centered()
	var search: LineEdit = _fields["picker_search"]   # type straight away to search (F2 in build mode too)
	search.grab_focus()
	search.select_all()


## CS:S's own materials in the picker (when CS:S is installed): one collapsed row per folder; a folder's
## thumbnails are only made when it's opened (there are thousands). Returns the folders (for the search box).
func _picker_css_section(box: VBoxContainer) -> Array:
	var out := []
	if not CssLibrary.available():
		return out
	var by_folder := {}
	for e in CssLibrary.entries():
		var c: String = e["category"]
		if not by_folder.has(c):
			by_folder[c] = []
		by_folder[c].append(e)
	if by_folder.is_empty():
		return out
	var head := Label.new()
	head.text = "Counter-Strike: Source (from your CS:S install)"
	head.add_theme_font_size_override("font_size", 15)
	box.add_child(head)
	var note := Label.new()
	note.text = "Valve's own textures: CS:S exports use them as they are; SurfsUp exports copy them in only if you turn that on when exporting."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	box.add_child(note)
	var cats := by_folder.keys()
	cats.sort()
	for c in cats:
		var fo := PickerCssFolder.new()
		fo.setup(self, box, c, by_folder[c])
		out.append(fo)
	return out


func _picker_pick(id: String) -> void:
	_picker.hide()
	_picker_cb.call(id)


func _own_image_dialog() -> FileDialog:
	if not _fields.has("own_image_dialog"):
		var d := FileDialog.new()
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		d.use_native_dialog = true
		d.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
		d.file_selected.connect(func(path): add_own_material(path))
		_ui_root.add_child(d)
		_fields["own_image_dialog"] = d
	return _fields["own_image_dialog"]


## Add an image file to the library as a material and use it where the picker was opened from.
func add_own_material(path: String) -> String:
	var id := MaterialLibrary.add_user_image(path)
	if id == "":
		_set_status("Couldn't read %s as an image." % path.get_file())
		return ""
	if _picker:
		_picker.queue_free()                            # rebuilt next time with the new one in it
		_picker = null
	_set_status("Added %s to your materials." % path.get_file())
	if _picker_cb.is_valid():
		_picker_cb.call(id)
	return id


## Alt+click: paint the last picked material onto the face under the mouse (that side of that block).
func _paint_face(pane: ViewPane, mouse: Vector2) -> void:
	var r := pane.ray(mouse)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 20000.0))
	if hit.is_empty() or not hit.collider.has_meta("block"):
		_set_status("Alt+click a block's face to paint it with the last material you picked.")
		return
	if _paint == "":
		_set_status("Pick a material first (select a block, then Material), then Alt+click faces to paint them.")
		return
	var b: BlockNode = hit.collider.get_meta("block")
	var slot := BlockShape.slot_of((b.global_basis.inverse() * (hit["normal"] as Vector3)).normalized())
	_checkpoint()
	var d: Dictionary = b.data.duplicate(true)
	var f: Dictionary = d["faces"].get(slot, {})
	f["material"] = _paint
	d["faces"][slot] = f
	if d["color"] == BlockShape.DEFAULTS["color"]:
		d["color"] = "ffffff"
	b.from_dict(d)
	_rebuild_blocks()
	if b != selected:
		_select(b)
	_block_side = slot
	_refresh_props()
	_set_status("Painted the %s side with %s." % [BlockShape.SLOT_LABELS[slot].to_lower(), MaterialLibrary.display_name(_paint)])


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


# ------------------------------------------------------------------------------------------------ selection tools
func _finish_marquee() -> void:
	var pane := _marquee_pane
	_marquee_pane = null
	var r := Rect2(_marquee_a, Vector2.ZERO).expand(_marquee_b)
	if r.size.length() < 4.0:                            # just a click on empty space
		if not _marquee_add:
			_select(null)
		return
	var hits := []
	for o in _all_objects():
		var c: Vector3 = o.center()
		if not pane.camera.is_position_behind(c) and r.has_point(pane.camera.unproject_position(c)):
			for m in _group_of(o):
				if not m in hits:
					hits.append(m)
	var cur := selection() if _marquee_add else []
	for h in hits:
		if not h in cur:
			cur.append(h)
	_set_selection(cur)
	_set_status("%d selected" % cur.size())


func _with_group(o: Node3D) -> Dictionary:
	var d: Dictionary = o.to_dict()
	for key in ["group", "name", "folder", "hidden"]:
		if o.has_meta(key):
			d[key] = o.get_meta(key)
	return d


func _take_group(o: Node3D, d: Dictionary) -> void:
	if d.has("group"):
		o.set_meta("group", d["group"])
	if d.has("name"):
		o.set_meta("name", d["name"])
	if d.has("folder") and not outliner.folder(d["folder"]).is_empty():
		o.set_meta("folder", d["folder"])
	if d.get("hidden", false):
		o.set_meta("hidden", true)
		o.visible = false


## Ctrl+G: the selected objects become one group (clicking any of them selects them all).
func _group() -> void:
	var objs := selection()
	if objs.size() < 2:
		_set_status("Select two or more objects to group them (Ctrl+click or drag a box in a 2D view).")
		return
	_checkpoint()
	var id := "g%d" % Time.get_ticks_usec()
	for o in objs:
		o.set_meta("group", id)
	_set_status("Grouped %d objects. Clicking any of them now selects them all; Ctrl+Shift+G to ungroup." % objs.size())


func _ungroup() -> void:
	_checkpoint()
	for o in selection():
		if o.has_meta("group"):
			o.remove_meta("group")
	_set_status("Ungrouped.")


func _kind_of(o: Node3D) -> String:
	if o is RampNode: return "ramps"
	if o is EntityNode: return "entities"
	if o is PropNode: return "props"
	if o is TextNode: return "texts"
	if o is LightNode: return "lights"
	if o is ParticleNode: return "particles"
	if o is CubeModelNode: return "cube_models"
	return "blocks"


func _clip_of(objs: Array) -> Dictionary:
	var clip := {"mallet_clipboard": 1, "ramps": [], "entities": [], "props": [], "blocks": [], "texts": [], "lights": [], "particles": [], "cube_models": []}
	for o in objs:
		clip[_kind_of(o)].append(_with_group(o))
	return clip


## Ctrl+C: the selection goes on the system clipboard (so it pastes into another map, or another MALLET).
func _copy() -> void:
	if selection().is_empty():
		return
	DisplayServer.clipboard_set(JSON.stringify(_clip_of(selection())))
	_set_status("Copied %d object(s). Ctrl+V pastes them (also into another map)." % selection().size())


## Ctrl+V: paste in the middle of the 3D view.
func _paste_clicked() -> void:
	var data = JSON.parse_string(DisplayServer.clipboard_get())
	if typeof(data) != TYPE_DICTIONARY or not (data.has("mallet_clipboard") or data.has("surfforge_clipboard")):
		_set_status("Nothing to paste: copy something in MALLET first (Ctrl+C).")
		return
	# center of what was copied
	var objs := _paste(data, Vector3.ZERO, true)
	if objs.is_empty():
		return
	var mid := Vector3.ZERO
	for o in objs:
		mid += o.center()
	mid /= objs.size()
	var to := _view_center()
	if snap_enabled:
		to = to.snapped(Vector3.ONE * snap_step)
	for o in objs:
		o.translate_by(to - mid)
	_rebuild_blocks()
	_map_changed()


## Add copies of clipboard objects, moved by `offset`. Start and finish platforms are skipped if the map has
## them already (a map has one of each). Returns the new objects, selected.
func _paste(data: Dictionary, offset: Vector3, quiet := false) -> Array:
	_checkpoint()
	var made := []
	var skipped := 0
	var groups := {}                                     # pasted groups get fresh ids
	for kind in ["ramps", "entities", "props", "blocks", "texts", "lights", "particles", "cube_models"]:
		for d in data.get(kind, []):
			if kind == "entities" and d.get("kind", "") in ["start", "finish"] and not d.get("zone_only", false) and _find_plate(d["kind"]):
				skipped += 1
				continue
			var o: Node3D
			match kind:
				"ramps":
					o = RampNode.new()
					ramps_root.add_child(o)
				"entities":
					o = EntityNode.new()
					entities_root.add_child(o)
				"props":
					o = PropNode.new()
					props_root.add_child(o)
				"texts":
					o = TextNode.new()
					texts_root.add_child(o)
				"lights":
					o = LightNode.new()
					lights_root.add_child(o)
				"particles":
					o = ParticleNode.new()
					particles_root.add_child(o)
				"cube_models":
					o = CubeModelNode.new()
					cube_models_root.add_child(o)
				_:
					o = BlockNode.new()
					blocks_root.add_child(o)
			o.from_dict(d)
			if d.has("group"):
				if not groups.has(d["group"]):
					groups[d["group"]] = "g%d_%d" % [Time.get_ticks_usec(), groups.size()]
				o.set_meta("group", groups[d["group"]])
			if offset != Vector3.ZERO:
				o.translate_by(offset)
			made.append(o)
	_rebuild_blocks()
	_set_selection(made)
	if not quiet or skipped > 0:
		_set_status("Pasted %d object(s)%s." % [made.size(), (" (left out %d start/finish: a map has one of each)" % skipped) if skipped else ""])
	return made


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
	if _marquee_pane == pane:
		var r := Rect2(_marquee_a, Vector2.ZERO).expand(_marquee_b)
		ov.draw_rect(r, Color(0.3, 0.75, 1.0, 0.12), true)
		ov.draw_rect(r, Color(0.3, 0.75, 1.0, 0.9), false, 1.5)
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
	if show_tester_paths and not tester_runs.is_empty():
		_draw_tester_paths(cam, ov)
	if not live_peers.is_empty():
		_draw_live_peers(cam, ov)
	if show_co_editors and not co_cursors.is_empty():
		_draw_co_editors(cam, ov)
		_draw_co_mice(cam, ov, pane.size)
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
	for o in selection():
		if o != selected:
			_draw_lines(cam, ov, o.outline if o is RampNode else o.outline_lines(), Color(0.55, 0.85, 1.0, 0.7), 1.5)
	var lines: Array[PackedVector3Array] = selected.outline if selected is RampNode else selected.outline_lines()
	_draw_lines(cam, ov, lines, Color(0.3, 0.75, 1.0, 0.95), 2.0)   # selection outline (keeps the real color visible)
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
		var hp := _move_handle_point(selected)
		if not cam.is_position_behind(hp):
			var s := cam.unproject_position(hp)
			ov.draw_rect(Rect2(s - Vector2(6, 6), Vector2(12, 12)), Color(1, 0.85, 0.15), true)
			ov.draw_rect(Rect2(s - Vector2(7, 7), Vector2(14, 14)), Color(0, 0, 0, 0.7), false, 1.5)


## Where an object's yellow move handle is drawn. A cube object's own origin can be far from its cubes (they're
## built anywhere in build mode), so its handle sits in their middle - where the X / Y / Z boxes and dragging work from.
func _move_handle_point(e: Node3D) -> Vector3:
	return (e as CubeModelNode).center() if e is CubeModelNode else e.global_position


func _process(delta: float) -> void:
	_poll_css()
	_tick_relay()
	if _blocks_dirty:
		_rebuild_blocks()
	_refresh_position()
	if play.active:
		return
	_tick_co_cursors(delta)
	_update_co_avatars()
	_arcs_timer -= delta
	if _arcs_dirty > 0 or _arcs_timer <= 0.0:
		_arcs_dirty = max(_arcs_dirty - 1, 0)
		_arcs_timer = 0.5                         # safety refresh; changes trigger an immediate update
		_update_arcs()


## The kill floor's height, from the live objects (no re-reading of every cube).
func kill_floor_y() -> float:
	var models := []
	for cm in cube_models_root.get_children():
		models.append([cm.world, cm.global_transform])
	var d := _map_dict()
	d.erase("cube_models")
	return SurfsUpExporter.kill_floor_y(d, models)


## Anything that changes the map calls this so the jump arcs follow instantly (and so co-editors hear about it).
func _map_changed() -> void:
	_arcs_dirty = 2
	if _co_mute or relay == null or not relay.is_open() or not (session_role in ["maker", "editor"]):
		return
	for o in selection():
		if is_instance_valid(o):
			_co_queue[o] = true
	if _gen_source != null and is_instance_valid(_gen_source):
		_co_queue[_gen_source] = true              # (the ramp creator's own ramp)
	var env := JSON.stringify(environment)          # the Map panel: the sky, water and the rest of the map's look
	if env != _co_env:
		_co_env = env
		_co_seq += 1
		relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "env", "environment": environment.duplicate(true)}})


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
	var volumes: Array = []                             # (untyped: lava / death in cube objects are KillBoxes, not nodes)
	volumes.append_array(entities_root.get_children().filter(func(x): return x.is_volume()))
	var kill_y := kill_floor_y()
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
	if _place_on_surface and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_place_text_on_surface(pane, event.position)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.alt_pressed:
		_paint_face(pane, event.position)
		return true
	if selected is BlockNode and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var f := _pick_face(pane, event.position)
		if f >= 0:
			_face = f
			# top and bottom handles move up and down: drag them on an upright plane (a level one can't go up)
			var up_down := absf(((selected as BlockNode).face_handles()[f][1] as Vector3).y) > 0.7
			_begin_drag(pane, Drag.FACE, event.position, up_down)
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
			var ctrl: bool = event.ctrl_pressed or event.meta_pressed
			if obj and ctrl:
				_select_with_group(obj, true)            # Ctrl+click: add to / take out of the selection
				_set_status("%d selected" % selection().size())
				return true
			if obj == null:
				if pane.is_ortho():                      # drag on empty space in a 2D view: box select
					_marquee_pane = pane
					_marquee_a = event.position
					_marquee_b = event.position
					_marquee_add = ctrl
					return true
				_select(null)
				_set_status("")
				return true
			if obj in selection() and selection().size() > 1:
				var rest := selection()                  # keep the whole selection, lead with this one
				rest.erase(obj)
				selected = obj
				_extra = rest
			elif obj != selected:
				_select_with_group(obj)
			elif obj is RampNode:
				selected_point = -1
			_begin_drag(pane, Drag.OBJECT, event.position, event.shift_pressed)
			var n := selection().size()
			_set_status(("%d selected - drag to move them together" % n) if n > 1 else
				"Selected %s - drag to move it" % ("ramp" if obj is RampNode else obj.label().to_lower()))
			return true
		elif _marquee_pane:
			_finish_marquee()
			return true
		elif _drag != Drag.NONE:
			_end_drag()
			return true
	elif event is InputEventMouseMotion and _marquee_pane and pane == _marquee_pane:
		_marquee_b = event.position
		return true
	elif event is InputEventMouseMotion and _drag != Drag.NONE and pane == _drag_pane:
		_drag_to(event.position, _drag_vertical if _drag == Drag.FACE else event.shift_pressed)
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not tester.is_empty() and not play.active:
		return                                           # (a test build's menu is up: no editor keys)
	if ramp_creator.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			ramp_creator.hide()
			get_viewport().set_input_as_handled()
		return
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
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _place_on_surface:
		_place_on_surface = false
		_set_status("")
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
	if _flying() and not ctrl:
		return                                           # (right mouse held: letters are W A S D Q E flying, not shortcuts)
	match e.keycode:
		KEY_Z when ctrl:
			if e.shift_pressed: redo()
			else: undo()
		KEY_Y when ctrl: redo()
		KEY_S when ctrl: _save_clicked()
		KEY_O when ctrl: _open_clicked()
		KEY_D when ctrl: _duplicate_clicked()
		KEY_C when ctrl: _copy()
		KEY_V when ctrl: _paste_clicked()
		KEY_G when ctrl:
			if e.shift_pressed: _ungroup()
			else: _group()
		KEY_A when ctrl: _set_selection(_all_objects())
		KEY_N: _add_ramp_clicked()
		KEY_O: _add_block_clicked()
		KEY_U: _add_light("point")
		KEY_H: _add_water_clicked()
		KEY_X when not ctrl: _add_text_clicked()
		KEY_D when not ctrl:
			if _draw_mode or _hovered_pane() == null or _hovered_pane().is_ortho():
				_toggle_draw_mode()
			else:
				_set_status("Draw blocks works in the Top, Front and Side views: press D with the mouse over one.")
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
		KEY_E: _build_clicked()
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
	var exclude := []
	for attempt in 8:                                    # look past things hidden in the Outliner
		q.exclude = exclude
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			break
		var obj: Node3D = null
		for key in ["ramp", "entity", "prop", "block", "text", "light", "particle", "cube_model"]:
			if hit.collider.has_meta(key):
				obj = hit.collider.get_meta(key)
				break
		if obj == null:
			break                                        # not an object: try the ramp ridges below
		if obj.is_visible_in_tree():
			return obj
		exclude.append(hit.collider.get_rid())
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
	# text on a block face stays on it: in the 3D view the mouse is followed across the face itself
	_text_surface = _text_face(selected) if _drag == Drag.OBJECT and selected is TextNode and selection().size() == 1 else {}
	if not _text_surface.is_empty() and not _drag_pane.is_ortho():
		var n: Vector3 = _text_surface["normal"]
		var look := -_drag_pane.camera.global_basis.z
		if absf(look.dot(n)) > 0.15:                     # (seen edge-on, the view's own plane works better)
			_drag_plane = Plane(n, anchor)
	var r := _drag_pane.ray(mouse)
	var hit = _drag_plane.intersects_ray(r[0], r[1])
	_drag_start_hit = hit if hit != null else anchor
	_drag_applied = Vector3.ZERO
	_settle_ramps()
	_drag_origin = selected.to_dict()                    # re-based so switching Shift mid-drag doesn't jump
	_drag_origins = {}
	for o in selection():
		_drag_origins[o] = o.to_dict()


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
	if not _text_surface.is_empty():
		delta = hit - _drag_start_hit
		if _drag_pane.is_ortho():
			delta *= _drag_pane.drag_axes(false)
	if not _drag_moved:
		if delta.length() < 0.01:
			return
		_checkpoint()                                    # first real movement: the object is still in its pre-drag state
		_drag_moved = true
	if _drag != Drag.OBJECT or not _text_surface.is_empty():
		selected.from_dict(_drag_origin)                 # (shapes and text on faces start over from the drag's start)
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
		delta = _snap_axes(delta, Vector3.ONE if not _text_surface.is_empty() else _drag_pane.drag_axes(_drag_vertical))
		var any_block := false
		var step := delta - _drag_applied                # (moved by what's new since the last mouse move: no rebuilds)
		if not _text_surface.is_empty():
			step = delta
		for o in selection():
			if not _text_surface.is_empty() and o != selected:
				o.from_dict(_drag_origins[o])
			if o is RampNode and _text_surface.is_empty():
				(o as RampNode).shift(step)
			else:
				o.translate_by(step)
			any_block = any_block or o is BlockNode
		_drag_applied = delta
		if any_block:
			_mark_blocks()
		var c: Vector3 = selected.center()
		if not _text_surface.is_empty():
			_keep_on_face(selected, _text_surface, _drag_origin)
		var centred := _centre_text_on_face(selected) if selected is TextNode and selection().size() == 1 else ""
		if centred != "":
			_set_status("Snapped to the %s of the face (drag further to let go)" % centred)
		else:
			_set_status("Moved by (%.0f, %.0f, %.0f) - center now (%.0f, %.0f, %.0f)" % [delta.x, delta.y, delta.z, c.x, c.y, c.z])
	_refresh_info()


## Ramps moved with shift() while dragging get their final mesh.
func _settle_ramps() -> void:
	for o in selection():
		if o is RampNode:
			(o as RampNode).settle()


func _snap_axes(v: Vector3, axes: Vector3) -> Vector3:
	if not snap_enabled:
		return v
	for i in 3:
		if axes[i] > 0.5:
			v[i] = snappedf(v[i], snap_step)
	return v


func _end_drag() -> void:
	_settle_ramps()
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
		for o in selection():
			o.translate_by(d)
	if selection().any(func(o): return o is BlockNode or o is TextNode):
		_mark_blocks()
	_refresh_info()
	_set_status("Nudged %s" % ["point" if selected is RampNode and selected_point >= 0 else "object"])


func _rotate_selected(deg: float) -> void:
	if selected == null:
		return
	_checkpoint("rotate")
	var objs := selection()
	if objs.size() == 1:
		selected.rotate_by(deg)
	else:
		var pivot := Vector3.ZERO
		for o in objs:
			pivot += o.center()
		pivot /= objs.size()
		var b := Basis(Vector3.UP, deg_to_rad(deg))
		for o in objs:
			var c: Vector3 = o.center()
			o.translate_by(pivot + b * (c - pivot) - c)
			o.rotate_by(deg)
	if objs.any(func(o): return o is BlockNode or o is TextNode):
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
	_set_status("New ramp added at the view center.")


# ================================================================================================= ramp creator
## Open the ramp creator, loaded with the selected ramp's design (or the last one worked on).
func _open_ramp_creator() -> void:
	ramp_creator.env = environment.duplicate(true)
	ramp_creator.has_target = selected is RampNode
	ramp_creator.target_locked = selected is RampNode and not (selected as RampNode).frozen.is_empty()
	if selected is RampNode:
		ramp_creator.set_design((selected as RampNode).to_dict(), (selected as RampNode).design)
	ramp_creator.open()


## Give the selected ramp a design: it keeps its points (and look), takes the shape.
func apply_design(design: Dictionary, name := "") -> void:
	if not selected is RampNode:
		_set_status("Select a ramp first, or use Add as a new ramp.")
		return
	var r := selected as RampNode
	if not r.frozen.is_empty():
		_set_status("Unlock the ramp first: a design changes the whole ramp, its locked part too.")
		return
	_checkpoint()
	_set_design(r, design, name)
	ramp_creator.hide()
	_refresh_props()
	_set_status("The ramp now has the design %s - drag, stretch and bend it as usual." % ("'%s'" % name if name != "" else "from the ramp creator"))


## A new ramp at the view center with a design.
func new_ramp_from_design(design: Dictionary, name := "") -> void:
	_add_ramp_clicked()
	if selected is RampNode:
		_set_design(selected as RampNode, design, name)
		ramp_creator.hide()
		_refresh_props()
		_set_status("New ramp%s added at the view center." % (" '%s'" % name if name != "" else ""))


func _set_design(r: RampNode, design: Dictionary, name: String) -> void:
	var d := RampPrefabs.design_of(design)
	var rd := r.to_dict()
	for k in RampPrefabs.DESIGN_KEYS:
		rd[k] = d[k]
	rd["design"] = name
	r.from_dict(rd)
	_map_changed()


func _plain_ramp_clicked() -> void:
	if not selected is RampNode or not (selected as RampNode).frozen.is_empty():
		return
	_checkpoint()
	var r := selected as RampNode
	var rd := r.to_dict()
	rd["profile"] = {}
	rd["ends"] = {}
	rd["design"] = ""
	r.from_dict(rd)
	_map_changed()
	_refresh_props()
	_set_status("Plain ramp again: straight faces, square ends.")


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


func _add_entity(kind: String, zone_only := false) -> void:
	_checkpoint()
	var c := _view_center()
	if snap_enabled:
		c = c.snapped(Vector3.ONE * snap_step)
	for e in entities_root.get_children():         # a map has one start and one finish plate: move the existing one
		if e.kind == kind and kind in ["start", "finish"] and not zone_only and not e.zone_only:
			e.position = c
			_select(e)
			_set_status("Moved the %s to the view center (a map has one)." % e.label().to_lower())
			return
	var n := EntityNode.create(kind)
	n.position = c
	if zone_only:                                       # just the zone: set it on the platform you built
		n.zone_only = true
		n.size.y = 10.0
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
	_set_status(("Added a %s: put it on your own platform (its floor is where the player stands). More boxes of the same kind " 		+ "(and stage number) make one zone of any shape.") % n.label().to_lower() if zone_only else "Added %s at the view center." % n.label().to_lower())


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
	if (selected is LightNode or selected is ParticleNode) and selection().size() == 1:
		_paste(_clip_of([selected]), Vector3(10, 0, 0))
		return
	if selected is CubeModelNode and selection().size() == 1:
		var bb: AABB = (selected as CubeModelNode).world.bounds()
		_paste(_clip_of([selected]), Vector3(maxf(bb.size.x, 4.0) + 4.0, 0, 0))
		return
	if selected is TextNode and selection().size() == 1:
		_paste(_clip_of([selected]), (selected as TextNode).global_basis * Vector3(0, -float(selected.data["height"]) * 1.4, 0))
		return
	if selection().size() > 1:
		_paste(_clip_of(selection()), Vector3(20, 0, 20))
		return
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
	var objs := selection()
	_select(null)
	for obj in objs:
		obj.get_parent().remove_child(obj)
		obj.queue_free()
	if objs.any(func(o): return o is BlockNode or o is TextNode):
		_mark_blocks()
	if objs.size() > 1:
		_set_status("Deleted %d objects." % objs.size())
		return
	_set_status("Deleted.")


func _frame_clicked() -> void:
	var aabb := AABB()
	var first := true
	var targets: Array = selection() if not selection().is_empty() else _all_objects()
	for o in targets:
		var pts: Array = Array(o.points) if o is RampNode else [_move_handle_point(o)]
		if not o is RampNode and o.has_method("outline_lines"):
			for line in o.outline_lines():                   # (its whole shape, so big things fit the view)
				pts.append_array(Array(line))
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
		elif o is EntityNode:                           # (the course: ramps and platforms; scenery is left out)
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
	# measure the points along the camera's right/up/forward axes, center on them and back off until they fit
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
	if selected is ParticleNode:
		var pn := selected as ParticleNode
		var pd: Dictionary = pn.data.duplicate(true)
		var area: Array = (pd["area"] as Array).duplicate()
		match key:
			"fx_preset":
				pd["preset"] = value
				pd["area"] = (ParticleNode.PRESETS[value]["area"] as Array).duplicate()
				pd["color"] = ""
			"fx_own_color": pd["color"] = ParticleNode.PRESETS[pd["preset"]]["colors"][1].substr(0, 6) if value else ""
			"fx_color": pd["color"] = (value as Color).to_html(false)
			"fx_amount": pd["amount"] = value
			"fx_size": pd["size"] = value
			"fx_speed": pd["speed"] = value
			"fx_area_x": area[0] = value
			"fx_area_y": area[1] = value
			"fx_area_z": area[2] = value
		if key.begins_with("fx_area"):
			pd["area"] = area
		pn.from_dict(pd)
		_refresh_info()
		return
	if selected is LightNode:
		var ln := selected as LightNode
		var ld: Dictionary = ln.data.duplicate(true)
		match key:
			"light_kind": ld["kind"] = value
			"light_color": ld["color"] = (value as Color).to_html(false)
			"light_energy": ld["energy"] = value
			"light_range": ld["range"] = value
			"light_angle": ld["angle"] = value
			"light_yaw": ld["yaw"] = value
			"light_pitch": ld["pitch"] = value
			"light_shadows": ld["shadows"] = value
			"light_effect": ld["effect"] = value
			"light_length": ld["length"] = value
			"light_strip_yaw": ld["yaw"] = value
			"light_preset":
				for k in LightNode.PRESETS[value]:
					if k != "label":
						ld[k] = LightNode.PRESETS[value][k]
				if ld["kind"] == "strip":
					ld["pitch"] = 0.0                    # (strips lie level)
		ln.from_dict(ld)
		if key == "light_kind":
			_refresh_props()
		_refresh_info()
		return
	if selected is TextNode:
		var tn := selected as TextNode
		var td: Dictionary = tn.data.duplicate(true)
		match key:
			"text_text": td["text"] = value
			"text_font": td["font"] = value
			"text_mode": td["mode"] = value
			"text_align": td["align"] = value
			"text_height": td["height"] = value
			"text_depth": td["depth"] = value
			"text_yaw": td["yaw"] = value
			"text_pitch": td["pitch"] = value
			"text_roll": td["roll"] = value
			"text_glow": td["glow"] = value
			"text_solid": td["solid"] = value
			"text_mat":
				td["material"] = value
				if value != "" and td["color"] == TextShape.DEFAULTS["color"]:
					td["color"] = "ffffff"
			"text_color": td["color"] = (value as Color).to_html(false)
		tn.from_dict(td)
		if key in ["text_mode", "text_font", "text_mat"]:
			_refresh_props()
		_refresh_info()
		return
	if selected is BlockNode:
		var b := selected as BlockNode
		var d: Dictionary = b.data.duplicate(true)
		match key:
			"block_shape": d["shape"] = value
			"block_x": d = BlockNode.resized_centered(d, 0, value)
			"block_y": d["size"][1] = value
			"block_z": d = BlockNode.resized_centered(d, 2, value)
			"block_yaw": d["yaw"] = value
			"block_pitch": d["pitch"] = value
			"block_roll": d["roll"] = value
			"block_sides": d["sides"] = int(value)
			"block_steps": d["steps"] = int(value)
			"block_hollow": d["hollow"] = value
			"block_wall": d["wall"] = value
			"block_cutter": d["cutter"] = value
			"block_look":
				d["look"] = value
				if value == "shader" and String(d.get("shader", "")) == "" and not UserShaders.ids("surface").is_empty():
					d["shader"] = UserShaders.ids("surface")[0]
			"block_shader":
				d["shader"] = value
				d["shader_params"] = {}
			"block_shader_param":
				var sp: Dictionary = (d.get("shader_params", {}) as Dictionary).duplicate(true)
				if value[0] == "":
					sp.clear()
				else:
					sp[value[0]] = value[1]
				d["shader_params"] = sp
			"block_color": d["color"] = (value as Color).to_html(false)
			"block_glow": d["glow"] = value
			"block_water_color": d["water_color"] = (value as Color).to_html(false)
			"block_clarity": d["clarity"] = value
			"block_deadly": d["deadly"] = value
			"block_liquid":                              # a preset sets its look and whether it's deadly
				var lp: Dictionary = Look.LIQUIDS[value]
				d["liquid"] = value
				d["water_color"] = lp["color"]
				d["clarity"] = float(lp.get("clarity", 0.0))
				d["deadly"] = bool(lp.get("deadly", false))
				d["glow"] = 0.0
			"block_mat":
				_paint = value
				if _block_side == "all":
					d["material"] = value
					for sl in d["faces"]:                       # the whole block: drop the sides' own materials
						d["faces"][sl].erase("material")
					if value != "" and d["color"] == BlockShape.DEFAULTS["color"]:
						d["color"] = "ffffff"                   # library materials look as photographed
				else:
					var f: Dictionary = d["faces"].get(_block_side, {})
					f["material"] = value
					d["faces"][_block_side] = f
			"block_uv_scale", "block_uv_u", "block_uv_v", "block_uv_rot":
				var target: Dictionary = d if _block_side == "all" else d["faces"].get(_block_side, {})
				var off: Array = target.get("uv_offset", d.get("uv_offset", [0.0, 0.0])).duplicate()
				match key:
					"block_uv_scale": target["uv_scale"] = value
					"block_uv_u": off[0] = value
					"block_uv_v": off[1] = value
					"block_uv_rot": target["uv_rot"] = value
				if key in ["block_uv_u", "block_uv_v"]:
					target["uv_offset"] = off
				if _block_side != "all":
					d["faces"][_block_side] = target
		b.from_dict(d)
		if key in ["block_x", "block_y", "block_z"]:
			_last_block["size"] = b.data["size"].duplicate()
		_rebuild_blocks()
		if key in ["block_shape", "block_hollow", "block_cutter", "block_mat", "block_deadly", "block_look"]:
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
		if key == "shader_param":                       # (one setting of your shader: just the material)
			var sp: Dictionary = r.shader_params.duplicate(true)
			if value[0] == "":
				sp.clear()
			else:
				sp[value[0]] = value[1]
			r.shader_params = sp
			r._update_material()
			return
		if key == "shader":
			r.shader = value
			r.shader_params = {}
			r._update_material()
			return
		if key == "look" and value == "shader" and r.shader == "" and not UserShaders.ids("surface").is_empty():
			r.shader = UserShaders.ids("surface")[0]
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
			"zone_only":
				e.zone_only = value
				e.size.y = 10.0 if value else EntityNode.KINDS[e.kind]["size"].y
		e.rebuild()
	_refresh_info()


func _new_map_clicked() -> void:
	welcome.popup("Keep the current map")


func _on_template_chosen(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not (data.get("format", "") == MAP_FORMAT or data.get("format", "") in OLD_MAP_FORMATS):
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
	_co_map_replaced()
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
		if path.get_extension() in OLD_MAP_EXTS:
			path = path.get_basename()                   # (saving an old SurfForge map: it becomes a .mallet)
		if not path.ends_with("." + MAP_EXT):
			path += "." + MAP_EXT
		save_map(path)
	else:
		load_map(path)


func save_map(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_set_status("Could not save %s" % path)
		return
	var d := _map_dict()
	d["made_with"] = MalletVersion.full()
	if not best_ghost.is_empty():
		d["ghost"] = best_ghost                          # the best run travels with the map (editor only)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	current_path = path
	_set_title(path.get_file())
	_set_status("Saved %s" % path)
	_mark_saved()
	if _quit_after_save:
		get_tree().quit()


func load_map(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not (data.get("format", "") == MAP_FORMAT or data.get("format", "") in OLD_MAP_FORMATS):
		_set_status("%s is not a MALLET map" % path.get_file())
		return
	_checkpoint()
	_load_dict(data)
	_co_map_replaced()                                  # (the session builds on this map now, not the last one)
	best_ghost = data.get("ghost", {})
	current_path = path
	_set_title(path.get_file())
	_mark_saved()
	_frame_clicked()
	_set_status("Opened %s (%d ramps)" % [path.get_file(), ramps_root.get_child_count()])


# ================================================================================================= play mode
## The start / finish plate (not a zone box), or null.
func _find_plate(kind: String) -> EntityNode:
	for e in entities_root.get_children():
		if e.kind == kind and not e.zone_only:
			return e
	return null


## The plate of that kind, or else its first zone box, or null.
func _find_entity(kind: String) -> EntityNode:
	var plate := _find_plate(kind)
	if plate:
		return plate
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
	_play_from(at, start, finish)


## Play from `at` (the start plate, or wherever build mode's P was pressed).
func _play_from(at: Transform3D, start: EntityNode = null, finish: EntityNode = null) -> void:
	_release_views()
	if selected:
		selected.set_selected(false)
	_ui.visible = false
	var volumes: Array = []                             # (untyped: lava / death in cube objects are KillBoxes, not nodes)
	volumes.append_array(entities_root.get_children().filter(func(x): return x.is_volume()))
	for cm in cube_models_root.get_children():
		cm.finish_background()                          # (a map still drawing in after opening: solid before you land)
		volumes.append_array(cm.kill_volumes())
		cm.set_show_mats(false)
	var stages := {}
	var starts := []
	var finishes := []
	var stage_boxes := []                               # every stage zone box, [number, AABB] (several can share a number)
	for e in entities_root.get_children():
		if e.kind == "stage":
			if not stages.has(e.number) or (stages[e.number] as EntityNode).zone_only and not e.zone_only:
				stages[e.number] = e                     # (its plate - or first box - is where you respawn)
			stage_boxes.append([e.number, e.zone_aabb()])
		elif e.kind == "start":
			starts.append(e.zone_aabb())
		elif e.kind == "finish":
			finishes.append(e.zone_aabb())
	play.start(at, starts, finishes, kill_floor_y(), volumes, stages, best_ghost, stage_boxes)


## Build mode: first-person building with cubes, Sauerbraten style. Starts from where the 3D view looks from.
func _build_clicked() -> void:
	if play.active or build.active:
		return
	_checkpoint()                                        # one editor undo step takes back a whole build session
	_release_views()
	_ui.visible = false
	var target: CubeModelNode = selected if selected is CubeModelNode else null
	build.start((panes[0].camera as Camera3D).global_transform, target)


func _on_build_stopped() -> void:
	_ui.visible = true
	_mouse_buttons_up.call_deferred()
	_map_changed()
	var n := 0
	for cm in cube_models_root.get_children():
		n += cm.world.count()
	_set_status("Back from build mode: %d cube objects, %d cubes. Ctrl+Z here undoes the whole session; E goes back in." % [
		cube_models_root.get_child_count(), n])
	_refresh_props()


## No view keeps holding the mouse (a mode is starting).
func _release_views() -> void:
	for p in panes:
		(p as ViewPane).release_grab()
	if _drag != Drag.NONE:
		_end_drag()


## Back from build / play mode, which took every click: tell the window no mouse button is held, so clicks go where
## they're aimed again (otherwise one press it never saw let go of could keep sending them all to one place).
func _mouse_buttons_up() -> void:
	var at := get_viewport().get_mouse_position()
	for b in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		if Input.is_mouse_button_pressed(b):
			continue
		var up := InputEventMouseButton.new()
		up.button_index = b
		up.pressed = false
		up.position = at
		up.global_position = at
		get_viewport().push_input(up)


## Build mode's P: play from where you are, and come back to build mode afterwards.
func _play_from_build(at: Transform3D) -> void:
	_play_from(at, _find_entity("start"), _find_entity("finish"))


func _on_play_stopped() -> void:
	for cm in cube_models_root.get_children():
		cm.set_show_mats(true)
	if not tester.is_empty():
		_tester_menu()
		return
	if build.resume_after_play:
		build.resume()
		return
	_ui.visible = true
	_mouse_buttons_up.call_deferred()
	if selected:
		selected.set_selected(true)
	var t := " Best time: %s (its path is drawn in the views; G in play mode races it)." % PlayMode.format_time(play.best_time) if play.best_time > 0.0 else ""
	var f := " Finish speed on your last run: %d u/s." % roundi(play.finish_speed) if play.finish_speed > 0.0 else ""
	_set_status("Back in the editor. Top speed %d u/s.%s%s" % [roundi(play.top_speed), f, t])


# ================================================================================================= test builds
## A test build starts here: the map, the tester's name and consent (asked once), then straight into play mode.
func _start_tester(dir: String) -> void:
	welcome.hide()
	var cfg := Tester.config(dir)
	var data = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(Tester.MAP_FILE)))
	_load_dict(data if data is Dictionary else {})
	tester = {"dir": dir, "cfg": cfg, "name": Tester.tester_name(dir), "file": "", "attempts": []}
	_join_relay_as_tester(cfg)
	_ui.visible = false
	get_window().title = "%s - test build v%d" % [cfg.get("map_name", "map"), int(cfg.get("version", 1))]
	play.attempt_ended.connect(_tester_attempt)
	if tester["name"] != "":
		_tester_go()
		return
	var d := ConfirmationDialog.new()
	d.title = "Before you play"
	d.ok_button_text = "OK, let's play"
	d.cancel_button_text = "No thanks (quit)"
	var box := VBoxContainer.new()
	d.add_child(box)
	var l := Label.new()
	l.text = ("This is a test build of %s. While you play, every attempt is saved in the \"%s\" folder next to it:\n"
		+ "your name below, your times and speeds, where you fell and the path you took. Nothing is sent anywhere;\n"
		+ "you send that folder to the map maker yourself when you're done.\n\nName to show on your runs:") % [cfg.get("map_name", "this map"), Tester.RUNS_DIR]
	box.add_child(l)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Your name or nickname"
	box.add_child(name_edit)
	_fields["tester_name"] = name_edit
	add_child(d)
	d.confirmed.connect(func():
		var n := name_edit.text.strip_edges().left(40)
		Tester.save_tester(dir, n if n != "" else "Tester")
		tester["name"] = Tester.tester_name(dir)
		d.queue_free()
		_tester_go())
	d.canceled.connect(func(): get_tree().quit())
	d.popup_centered()


func _tester_go() -> void:
	tester["file"] = Tester.session_file(tester["dir"], tester["cfg"], tester["name"])
	_play_clicked()


func _tester_attempt(a: Dictionary) -> void:
	if tester.is_empty():
		return
	tester["attempts"].append(a)
	Tester.write_session(tester["file"], tester["cfg"], tester["name"], tester["attempts"])
	if relay != null and relay.is_open():
		relay.send({"t": "attempt", "attempt": a})            # (the file stays the fallback if the relay is away)


## Esc in a test build: keep playing or quit (there's no editor to go back to).
func _tester_menu() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Paused"
	d.dialog_text = "%d attempt(s) saved so far." % (tester["attempts"] as Array).size()
	d.ok_button_text = "Keep playing"
	d.cancel_button_text = "Quit"
	add_child(d)
	d.confirmed.connect(func(): d.queue_free(); _play_clicked())
	d.canceled.connect(func(): get_tree().quit())
	d.popup_centered()


## Export > Test build: MALLET itself + this map, zipped for testers (Tester.make_build).
func _test_build_clicked() -> void:
	var name := current_path.get_file().get_basename() if current_path != "" else "mymap"
	var out_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MALLET exports/test builds")
	test_version += 1
	_set_status("Making the test build... (a few seconds)")
	await get_tree().process_frame
	var live := {}
	if relay != null and relay.is_open():
		live = {"url": relay.url, "session": relay.session, "secret": relay.secret}
	var res := Tester.make_build(_map_dict(), name, test_version, OS.get_executable_path(), out_dir, live)
	if res["error"] != "":
		test_version -= 1
		_show_message("Can't make a test build", res["error"])
		return
	_map_changed()
	_show_message("Test build ready", ("Made %s (version %d of this map).\n\nSend the zip to your testers. They unzip it and start \"Play %s.exe\"; "
		+ "their runs are saved in a \"%s\" folder next to it. Ask them to send that folder back, then use Export > Import tester runs."
		+ ("\n\nWhile the playtest session %s is open, this build also sends their runs here as they play." % live.get("session", "") if not live.is_empty() else "")) % [
		res["zip"], test_version, name, Tester.RUNS_DIR])
	OS.shell_open(out_dir)


var _runs_dialog: FileDialog


func _import_runs_clicked() -> void:
	if _runs_dialog == null:
		_runs_dialog = FileDialog.new()
		_runs_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_runs_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_runs_dialog.use_native_dialog = true
		_runs_dialog.filters = PackedStringArray(["*.json ; Tester runs"])
		_runs_dialog.files_selected.connect(import_runs)
		_ui_root.add_child(_runs_dialog)
	_runs_dialog.popup_centered_ratio(0.6)


## Bring testers' runs files into the map (kept with it). Returns how many sessions were added.
func import_runs(paths: PackedStringArray) -> int:
	var added := 0
	var skipped := []
	for p in paths:
		var r := Tester.read_runs(p)
		if r.is_empty():
			skipped.append(p.get_file())
			continue
		if tester_runs.any(func(x): return x["tester"] == r["tester"] and x["attempts"] == r["attempts"]):
			continue                                     # (already imported)
		tester_runs.append(r)
		added += 1
	if added > 0:
		_checkpoint()
	var text := "Imported %d runs file(s).%s\n\nAll runs with this map so far: %s" % [added,
		("\nNot tester runs (skipped): " + ", ".join(skipped)) if not skipped.is_empty() else "", Tester.summary(tester_runs)]
	_show_message("Tester runs", text)
	_set_status(Tester.summary(tester_runs).get_slice("\n", 0))
	return added


# ================================================================================================= playtest session
## Export > Playtest session: start one (no code) or join one you made. Testers' live positions and runs arrive
## here while they play; test builds made from now on carry the session.
func _playtest_clicked() -> void:
	if _playtest_dialog == null:
		_build_playtest_dialog()
	_playtest_inputs["address"].text = String(Settings.value("relay_url"))
	_playtest_inputs["name"].text = String(Settings.value("player_name"))
	_playtest_dialog.popup_centered()


func _build_playtest_dialog() -> void:
	_playtest_dialog = ConfirmationDialog.new()
	_playtest_dialog.title = "Playtest session"
	_playtest_dialog.ok_button_text = "Start / join"
	var box := VBoxContainer.new()
	_playtest_dialog.add_child(box)
	var l := Label.new()
	l.text = ("Test builds made while a session is open send their runs to you as they play, and the panel shows\n"
		+ "who is on and how they are doing. Leave the code empty to start a new session; to join one you made\n"
		+ "before, type its code and secret.\n\nThe address is your relay server (your own computer while trying it out).")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	box.add_child(l)
	var prow := HBoxContainer.new()
	box.add_child(prow)
	var paste := Button.new()                               # nobody should have to retype a 32-character secret
	paste.text = "Paste invite"
	paste.focus_mode = Control.FOCUS_NONE
	paste.tooltip_text = "Fill in the address, code and secret from the line the maker copied (their playtest panel > Copy invite)."
	paste.pressed.connect(func(): _paste_invite())
	prow.add_child(paste)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for spec in [["address", "Relay address", "relay_url"], ["name", "Your name", "player_name"],
			["code", "Session code (empty = new)", ""], ["secret", "Secret (to join a session)", ""]]:
		var lab := Label.new()
		lab.text = spec[1]
		grid.add_child(lab)
		var le := LineEdit.new()
		le.text = String(Settings.value(spec[2])) if spec[2] != "" else ""
		le.custom_minimum_size = Vector2(360, 0)
		if spec[0] == "secret":
			le.secret = true
		grid.add_child(le)
		_playtest_inputs[spec[0]] = le
	var co := CheckBox.new()
	co.text = "Join as a co-editor: see their camera and selection (needs the code and secret)"
	co.tooltip_text = "Another MALLET sends you the session code and secret; tick this to join theirs as an editor instead of as the map's owner."
	box.add_child(co)
	_playtest_inputs["co"] = co
	_playtest_dialog.confirmed.connect(func():
		start_playtest(_playtest_inputs["address"].text.strip_edges(), _playtest_inputs["code"].text.strip_edges().to_upper(),
			_playtest_inputs["secret"].text.strip_edges(), _playtest_inputs["name"].text.strip_edges(),
			_playtest_inputs["co"].button_pressed))
	_ui_root.add_child(_playtest_dialog)


## Connect to the relay as the map maker. `code` empty starts a new session. `as_editor` joins someone else's
## session as a co-editor (code and secret are the invite). False if the address isn't a relay, or the invite is
## incomplete.
func start_playtest(url: String, code: String, secret: String, who: String, as_editor := false) -> bool:
	if code.contains("session") and code.contains("secret"):     # (the whole invite pasted into the code field)
		var inv := parse_invite(code)
		if String(inv["code"]) != "":
			code = String(inv["code"])
			if String(inv["secret"]) != "":
				secret = String(inv["secret"])
			if String(inv["url"]) != "":
				url = String(inv["url"])
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		_show_message("Playtest session", "The relay address must start with ws:// or wss:// (for example ws://127.0.0.1:8787/ws).")
		return false
	if as_editor and (code == "" or secret == ""):
		_show_message("Co-editing session", "To join as a co-editor, paste the maker's invite (Paste invite) or type the session's code and secret.")
		return false
	var role := "editor" if as_editor else "maker"
	Settings.set_value("relay_url", url)
	Settings.set_value("player_name", who)
	_leave_playtest()
	session_role = role
	_relay_url = url                                  # (kept, so a dropped connection can get back in)
	_relay_name = who
	_relay_code = code
	_relay_secret = secret
	relay = Relay.new()
	add_child(relay)
	relay.opened.connect(_playtest_opened)
	relay.failed.connect(_playtest_failed)
	relay.closed.connect(_playtest_lost)
	relay.message.connect(_playtest_message)
	relay.connect_to(url, {"t": "hello", "v": 1, "role": role, "session": code,
		"secret": secret if code != "" else "", "name": who if who != "" else ("Co-editor" if as_editor else "Maker"),
		"map": _map_name(), "map_version": test_version, "client": MalletVersion.full()})
	_set_status("Connecting to the relay at %s..." % url)
	return true


func _map_name() -> String:
	return current_path.get_file().get_basename() if current_path != "" else "untitled"


func _playtest_opened(_welcome: Dictionary) -> void:
	_playtest_panel.visible = true
	_refresh_playtest()
	_sync_view_menu()
	_co_seed()                                      # (everything already in the map is on both sides)
	_relay_code = relay.session                      # (a maker only learns its own code here)
	_relay_url = relay.url
	if relay.secret != "":
		_relay_secret = relay.secret
	_reconnect_at = 0
	_reconnect_wait = 1000
	var rejoining := _rejoining
	_rejoining = false
	if rejoining:
		if session_role == "editor":
			_co_request_state(true)                 # (their copy may have moved on while we were away)
		else:
			relay.send({"t": "collect"})            # (runs filed while the editor was away)
			_set_status("Back in session %s." % relay.session)
		return
	if session_role == "editor":
		if has_unsaved_changes():
			_co_ask_for_their_map()                 # (their map replaces ours: ask before unsaved work is lost)
			return
		_co_request_state()
		return
	relay.send({"t": "collect"})                       # (runs made while the editor was closed)
	_set_status("Playtest session %s is open: testers' runs arrive here." % relay.session)
	_show_message("Playtest session", ("Session code: %s\n\nTest builds made now (Export > Test build for testers…) send their runs here while they play.\n"
		+ "The panel (Export > Playtest panel) shows who is on and how they are doing.\n"
		+ "To co-edit, another MALLET joins with this code and secret and \"Join as a co-editor\" ticked.") % relay.session)


## The relay turned us away. While reconnecting that is usually the relay restarting, so try again; a wrong secret
## or a session that is gone means trying again is pointless.
func _playtest_failed(code: String, msg: String) -> void:
	if _rejoining and not (code in ["bad_secret", "unknown_session"]):
		_co_waiting_state = false
		_reconnect_at = Time.get_ticks_msec() + _reconnect_wait
		_set_status("Still trying to get back into session %s..." % _relay_code)
		return
	_rejoining = false
	_reconnect_at = 0
	_playtest_problem(code, msg)


## The connection ended. Keep trying to get back in, waiting a little longer after every try, so a blip in the
## network or a relay restart doesn't end the session.
func _playtest_lost(_code: int, _reason: String) -> void:
	if relay != null and relay.is_open():
		relay.close()                                # (nothing more is heard on a connection that ended)
	if _relay_code == "" or not (session_role in ["maker", "editor"]):
		_playtest_problem("closed", "The relay connection ended. Testers' runs are still saved on their side.")
		return
	_co_waiting_state = false
	_reconnect_at = Time.get_ticks_msec() + _reconnect_wait
	_reconnect_wait = mini(_reconnect_wait * 2, 30000)
	_set_status("The relay connection ended: getting back into session %s..." % _relay_code)
	_refresh_playtest()


func _tick_relay() -> void:
	if _reconnect_at > 0 and Time.get_ticks_msec() >= _reconnect_at:
		_reconnect_at = 0
		_reconnect()


## Join the session we were in again, with the same code and secret: the relay hands us back to the same session.
func _reconnect() -> void:
	if _relay_code == "" or _relay_url == "" or not (session_role in ["maker", "editor"]):
		return
	_rejoining = true
	if relay != null:
		relay.close()
		relay.queue_free()
		relay = null
	relay = Relay.new()
	add_child(relay)
	relay.opened.connect(_playtest_opened)
	relay.failed.connect(_playtest_failed)
	relay.closed.connect(_playtest_lost)
	relay.message.connect(_playtest_message)
	relay.connect_to(_relay_url, {"t": "hello", "v": 1, "role": session_role, "session": _relay_code,
		"secret": _relay_secret, "name": _relay_name if _relay_name != "" else "MALLET",
		"map": _map_name(), "map_version": test_version, "client": MalletVersion.full()})
	_set_status("Reconnecting to session %s..." % _relay_code)


func _playtest_problem(code: String, msg: String) -> void:
	var t := msg
	if code == "bad_secret":
		t = "That session's secret doesn't match. Press Paste invite to take the whole line from the maker's playtest panel (Copy invite); the secret is 32 characters and must not be retyped."
	elif code == "unknown_session":
		t = "No playtest session with that code. Start a new one (leave the code empty)."
	elif code == "session_full":
		t = "That session already has as many people as the relay allows."
	_playtest_panel.visible = true
	_refresh_playtest()
	_set_status("Playtest session: " + t)


func _playtest_message(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"live":
			var id := String(m.get("id", ""))
			live_peers[id] = m
			var trail: Array = live_trails.get(id, [])
			trail.append(_peer_pos(m))
			if trail.size() > 40:                           # 3-4 seconds at the 10 Hz test builds send
				trail = trail.slice(trail.size() - 40)
			live_trails[id] = trail
			_refresh_playtest()
		"peer_join":
			_refresh_playtest()
			var who_joined = m.get("peer", {})
			if session_role == "editor" and who_joined is Dictionary and String((who_joined as Dictionary).get("role", "")) == "maker":
				_co_request_state(true)                 # (the map's owner is back: catch up on what changed)
		"peer_leave":
			var gone := String(m.get("id", ""))
			live_peers.erase(gone)
			live_trails.erase(gone)
			co_cursors.erase(gone)
			_co_avatar_free(gone)
			_refresh_playtest()
		"names":
			_co_take_names(m)
		"kicked":
			_playtest_kicked(String(m.get("by", "the map's owner")))
		"cursor":
			var who := String(m.get("id", ""))
			if m.get("pos") is Array and (m.get("pos", []) as Array).size() >= 3:
				co_cursors[who] = m
		"edit":
			_co_apply(m)
		"state":
			_co_state_chunk(m)
		"state_please":
			if session_role == "maker":
				_co_send_state(String(m.get("id", "")))
		"attempt":
			if session_role != "editor":
				_add_live_attempt(String(m.get("name", "?")), m.get("attempt", {}), int(m.get("map_version", 0)))
		"runs":
			if session_role != "editor":
				for r in (m.get("runs", []) as Array):
					if r is Dictionary:
						_add_live_attempt(String(r.get("tester", "?")), r.get("attempt", {}), int(r.get("map_version", 0)))
				_refresh_playtest()


## One attempt from the relay, filed with the map like an imported one. The same attempt arriving twice (live and
## again from collect) is kept once.
func _add_live_attempt(who: String, attempt, version: int) -> void:
	if not attempt is Dictionary:
		return
	for x in tester_runs:                           # (the same run arrives live and again from collect, and an older
		if x is Dictionary and String(x.get("tester", "")) == who:   # relay may not say which build it is)
			for seen in (x.get("attempts", []) as Array):
				if seen is Dictionary and _attempt_key(seen) == _attempt_key(attempt):
					return
	var s: Dictionary = {}
	for x in tester_runs:
		if x is Dictionary and String(x.get("tester", "")) == who and int(x.get("map_version", 0)) == version:
			s = x
			break
	if s.is_empty():
		s = {"tester": who, "map": _map_name(), "map_version": version, "attempts": []}
		tester_runs.append(s)
	for seen in (s["attempts"] as Array):
		if seen is Dictionary and _attempt_key(seen) == _attempt_key(attempt):
			return
	s["attempts"].append(attempt.duplicate(true))
	_map_changed()
	var t := float(attempt.get("time", 0.0))
	_set_status("%s: %s%s" % [who, String(attempt.get("outcome", "run")), ("  " + PlayMode.format_time(t)) if t > 0.0 else ""])
	_refresh_playtest()


static func _attempt_key(a: Dictionary) -> String:
	return "%s|%.3f|%.1f" % [String(a.get("outcome", "")), float(a.get("time", 0.0)), float(a.get("started", 0.0))]


func _refresh_playtest() -> void:
	if _playtest_panel == null:
		return
	_playtest_panel.refresh(relay.session if relay != null else "", relay.status_text() if relay != null else "No playtest session",
		relay.peers if relay != null else {}, live_peers, tester_runs, session_role == "maker", _playtest_invite())


func _toggle_playtest_panel() -> void:
	_set_playtest_panel(_playtest_panel != null and not _playtest_panel.visible)


## Show or hide the playtest panel. Its toolbar button follows, so the two never disagree.
func _set_playtest_panel(on: bool) -> void:
	if _playtest_panel == null:
		return
	_playtest_panel.visible = on
	if on:
		_refresh_playtest()
	_sync_view_menu()


## Leave the session. The panel stays up with what came in, and the map keeps the runs.
func _leave_playtest() -> void:
	if relay != null:
		relay.close()
		relay.queue_free()
		relay = null
	live_peers.clear()
	live_trails.clear()
	co_cursors.clear()
	_co_avatar_free_all()
	_co_queue.clear()
	_co_last.clear()
	_co_uids.clear()
	_co_new_now.clear()
	_co_dels.clear()
	_co_waiting_state = false
	_relay_code = ""
	_relay_secret = ""
	_reconnect_at = 0
	_reconnect_wait = 1000
	_rejoining = false
	_co_state_next = -1
	_co_state_text = ""
	_co_names.clear()
	_co_named = false
	_co_env = ""
	session_role = ""
	_refresh_playtest()


## An invite line, as _playtest_invite() writes it:
## "MALLET co-editing - relay wss://relay.sebz.xyz/ws - session ABC123 - secret 9f3c...".
## Returns {"url", "code", "secret"}; empty strings for whatever isn't in the text.
func parse_invite(text: String) -> Dictionary:
	var t := text.strip_edges().replace("\r", " ").replace("\n", " ").replace("\t", " ")
	var out := {"url": "", "code": "", "secret": ""}
	var mu := RegEx.create_from_string("(wss?://[^\\s]+)").search(t)
	if mu != null:
		out["url"] = mu.get_string(1).trim_suffix(",").trim_suffix(".")
	var mc := RegEx.create_from_string("session\\s*[:=]?\\s*([A-Za-z0-9]{4,12})").search(t)
	if mc != null:
		out["code"] = mc.get_string(1).to_upper()
	var ms := RegEx.create_from_string("secret\\s*[:=]?\\s*([A-Za-z0-9]{6,128})").search(t)
	if ms != null:
		out["secret"] = ms.get_string(1)
	return out


## Fill the dialog from the invite on the clipboard, so nothing has to be retyped.
func _paste_invite() -> void:
	var got := parse_invite(DisplayServer.clipboard_get())
	if String(got["code"]) == "":
		_set_status("No invite on the clipboard: on the maker's MALLET, Export > Playtest panel > Copy invite.")
		return
	if String(got["url"]) != "":
		_playtest_inputs["address"].text = String(got["url"])
	_playtest_inputs["code"].text = String(got["code"])
	if String(got["secret"]) != "":
		_playtest_inputs["secret"].text = String(got["secret"])
		_playtest_inputs["co"].button_pressed = true
		_playtest_inputs["secret"].tooltip_text = "Filled from the invite: %d characters." % String(got["secret"]).length()
	_set_status("Invite filled in: session %s%s. Press Start / join." % [String(got["code"]), ", as a co-editor" if String(got["secret"]) != "" else ""])


## What to send someone so they can join: the relay, the code and the secret (only the owner has the secret).
func _playtest_invite() -> String:
	if relay == null or relay.session == "":
		return ""
	if session_role == "maker" and relay.secret != "":
		return "MALLET co-editing - relay %s - session %s - secret %s" % [relay.url, relay.session, relay.secret]
	return "MALLET co-editing - relay %s - session %s" % [relay.url, relay.session]


func _copy_playtest_code() -> void:
	var invite := _playtest_invite()
	if invite == "":
		_set_status("No session to copy.")
		return
	DisplayServer.clipboard_set(invite)
	_set_status("Invite copied. The other person ticks \"Join as a co-editor\" and types the code and secret.")


## Put someone out of the session (the map's owner only). The relay closes their connection; the code they have
## still works, so they can come back if you let them.
func _remove_from_session(id: String) -> void:
	if relay == null or not relay.is_open() or session_role != "maker" or id == "":
		return
	relay.send({"t": "kick", "id": id})
	_set_status("Removing them from the session...")


## The map's owner put us out: stop here, and don't retry (a reconnect would just walk back in).
func _playtest_kicked(by: String) -> void:
	_leave_playtest()
	_playtest_panel.visible = true
	_refresh_playtest()
	_set_status("%s removed you from the session. Your map is still yours to save." % by)


## A live position from our own play mode (a test build sends these to the map maker).
func _playtest_live(at: Vector3, speed: float, stage: int, state: String, attempt: int) -> void:
	if relay == null or not relay.is_open():
		return
	relay.send({"t": "live", "attempt": attempt, "p": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"speed": roundi(speed), "stage": stage, "state": state})


## A test build: report to the map maker's session when tester.cfg has one (the runs file is still written).
func _join_relay_as_tester(cfg: Dictionary) -> void:
	var url := String(cfg.get("relay", ""))
	if url == "":
		return
	session_role = "tester"
	relay = Relay.new()
	add_child(relay)
	relay.connect_to(url, {"t": "hello", "v": 1, "role": "tester", "session": String(cfg.get("session", "")),
		"secret": String(cfg.get("secret", "")), "name": tester["name"], "map": String(cfg.get("map_name", "map")),
		"map_version": int(cfg.get("version", 1)), "client": MalletVersion.full()})


# ================================================================================================= co-editing
## Send where we are looking and what we have selected, ten times a second, while we're in a session as the maker
## or a co-editor. The relay passes it to the others, never back to us.
func _tick_co_cursors(delta: float) -> void:
	if relay == null or not relay.is_open() or not (session_role in ["maker", "editor"]):
		return
	_cursor_clock -= delta
	if _cursor_clock > 0.0:
		return
	_cursor_clock = 0.1
	var at: Vector3
	var aim: Vector3
	var mouse: Array = []
	var view := "editor"
	if build != null and build.active:
		at = build.cam.global_position                # (build mode looks through its own camera; the panes are hidden)
		aim = -build.cam.global_basis.z
		var t: Dictionary = build.target if build.target is Dictionary else {}
		var w0 = t.get("point")
		if w0 is Vector3:
			mouse = [snappedf(w0.x, 0.01), snappedf(w0.y, 0.01), snappedf(w0.z, 0.01)]
		view = "build"
	else:
		var p: ViewPane = active_pane if active_pane != null else (panes[0] if not panes.is_empty() else null)
		if p == null or p.camera == null:
			return
		at = p.camera.global_position
		aim = -p.camera.global_basis.z
		var w = _co_mouse_point(p)
		if w != null:
			mouse = [snappedf(w.x, 0.01), snappedf(w.y, 0.01), snappedf(w.z, 0.01)]
		view = ViewPane.NAMES[p.kind].get_slice(" ", 0).to_lower()
	relay.send({"t": "cursor", "pos": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)],
		"aim": [snappedf(aim.x, 0.001), snappedf(aim.y, 0.001), snappedf(aim.z, 0.001)], "sel": _co_sel(),
		"view": view, "mouse": mouse, "doing": _co_doing()})
	_co_watch_build()
	_co_send_edits()


## Where the other editors should draw our mouse: the surface under it (what a click there would hit), or, when
## there's nothing under it, the plane this view drags on. Null when the pointer isn't over the view.
func _co_mouse_point(p: ViewPane) -> Variant:
	if p == null or p.camera == null or not p.mouse_here:
		return null
	var r := p.ray(p.mouse_pos)
	var q := PhysicsRayQueryParameters3D.create(r[0], r[0] + r[1] * 20000.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		return hit.position
	return p.drag_plane(_view_center(), false).intersects_ray(r[0], r[1])


## What we are doing right now, shown next to our mouse in the other editors' views.
func _co_doing() -> String:
	if build != null and build.active:
		return build.doing()
	if _drag != Drag.NONE:
		var n := selection().size()
		return "dragging" if n <= 1 else "dragging %d objects" % n
	return ""


## Build mode edits one cube object in place and never calls _map_changed, so its own undo history is the sign that
## something changed: a step more, or a different cube object, and that object goes out.
func _co_watch_build() -> void:
	if build == null or not build.active:
		_co_build_steps = -1
		_co_build_model = null
		return
	var steps: int = build.step_count()
	if build.model != _co_build_model or steps != _co_build_steps:
		_co_build_model = build.model
		_co_build_steps = steps
		if build.model != null and is_instance_valid(build.model):
			_co_queue[build.model] = true


## Our selection as [kind, x, y, z]: the other MALLET finds the object at that place in its own copy of the map.
## Objects have no ids of their own and both editors hold the same map, so the middle of the object is the key.
func _co_sel() -> Array:
	if selected == null or not is_instance_valid(selected):
		return []
	var c: Vector3 = selected.center()
	return [[_co_kind(selected), snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)]]


static func _co_kind(o: Node3D) -> String:
	if o is RampNode: return "ramp"
	if o is EntityNode: return "entity"
	if o is PropNode: return "prop"
	if o is TextNode: return "text"
	if o is LightNode: return "light"
	if o is ParticleNode: return "particle"
	if o is CubeModelNode: return "cube"
	if o is BlockNode: return "block"
	return ""


func _co_root(kind: String) -> Node3D:
	return {"ramp": ramps_root, "entity": entities_root, "prop": props_root, "block": blocks_root,
		"text": texts_root, "light": lights_root, "particle": particles_root, "cube": cube_models_root}.get(kind, null)


## The object of that kind whose middle is closest to `at` (under a meter), or null: the other editor's selection.
func _co_object_at(kind: String, at: Vector3) -> Node3D:
	var root := _co_root(kind)
	if root == null:
		return null
	var best: Node3D = null
	var best_d := 1.0
	for o in root.get_children():
		var d: float = (o as Node3D).center().distance_to(at)
		if d < best_d:
			best_d = d
			best = o
	return best


## A name for this object that both MALLETs agree on for the length of the session. Objects have no ids of their
## own and the map file is not ours to change here, so the id lives in the node's metadata: when the other editor
## mentions one we haven't named yet, we adopt their id for the object we matched.
func _co_uid(o: Node3D) -> String:
	if o.has_meta("co_uid"):
		return String(o.get_meta("co_uid"))
	var uid := "%x%04x" % [Time.get_ticks_usec(), randi() % 65536]
	o.set_meta("co_uid", uid)
	return uid


## The object the other editor means: by its session id when we've seen it before, else the object of that kind
## nearest to where it was when they changed it (both copies of the map start out the same).
func _co_find(kind: String, uid: String, at: Vector3) -> Node3D:
	var root := _co_root(kind)
	if root == null:
		return null
	if uid != "":
		for o in root.get_children():
			if o.has_meta("co_uid") and String(o.get_meta("co_uid")) == uid:
				return o
	var best: Node3D = null
	var best_d := 1.0
	for o in root.get_children():
		if (o.has_meta("co_uid") and _co_named) or o.is_queued_for_deletion():
			continue                                 # (with shared names, a named object is another object: never take it over)
		var d: float = (o as Node3D).center().distance_to(at)
		if d < best_d:
			best_d = d
			best = o
	if best != null and uid != "":
		best.set_meta("co_uid", uid)
		for other in _co_uids.keys():                # (it may have been filed under a name of its own)
			var rec = _co_uids[other]
			if rec is Dictionary and rec.get("o") == best:
				_co_uids.erase(other)
		_co_uids[uid] = {"o": best, "kind": kind}
		_co_last[uid] = best.center()
	return best


## Everything already in the map is on both sides when a session opens, so remember it without sending it.
func _co_seed() -> void:
	_co_uids.clear()
	_co_new_now.clear()
	_co_dels.clear()
	_co_queue.clear()
	for o in _all_objects():
		if is_instance_valid(o):
			var uid := _co_uid(o)
			_co_uids[uid] = {"o": o, "kind": _co_kind(o)}
			_co_last[uid] = (o as Node3D).center()   # (so the first edit says where this copy still has it)
			_co_track(o)
	_co_env = JSON.stringify(environment)          # (both copies start from the same map's look)


## Objects that appeared or vanished since the last tick (new ones wait in _co_new_now until they have gone out: a
## paste of more than a tick's worth used to lose the rest). Watching the map's contents is one place instead of every
## way an object can be made or removed (paste, every Add menu item, build mode, delete...).
func _co_scan_objects() -> void:
	var here := {}
	for o in _all_objects():
		if not is_instance_valid(o) or o.is_queued_for_deletion():
			continue
		var uid := _co_uid(o)
		here[uid] = o
		if not _co_uids.has(uid):
			_co_uids[uid] = {"o": o, "kind": _co_kind(o)}
			_co_new_now[o] = true
	for uid in _co_uids.keys():
		if here.has(uid):
			continue
		var gone: Dictionary = _co_uids[uid]
		_co_uids.erase(uid)
		_co_last.erase(uid)
		_co_dels.append([String(gone.get("kind", "")), uid])


## Hand the other editors what changed here since the last tick: new objects, removed objects, and changed objects.
## Each object goes as its whole plain-data state, so one path covers a dragged ramp point, a moved block and a
## changed property. A handful a tick, so a big paste or a long drag can't flood the relay.
func _co_send_edits() -> void:
	if _co_waiting_state:
		if Time.get_ticks_msec() - _co_state_since < 10000:
			return                                 # (our own map isn't theirs: nothing of it goes out yet)
		_co_waiting_state = false
		_set_status("The session's map hasn't arrived: make sure its owner is in the session.")
	_co_scan_objects()
	var sent := 0
	while not _co_dels.is_empty() and sent < 8:          # (popping inside a for over the same list skipped every other)
		var pair: Array = _co_dels.pop_front()
		_co_seq += 1
		relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "del", "kind": pair[0], "uid": pair[1]}})
		sent += 1
	for o in _co_new_now.keys():
		if sent >= 8:
			break
		_co_new_now.erase(o)
		if is_instance_valid(o) and not o.is_queued_for_deletion() and o.is_inside_tree() and _co_send_one(o, "add"):
			sent += 1
	for o in _co_queue.keys():
		if sent >= 8:
			break
		_co_queue.erase(o)
		if not is_instance_valid(o) or _co_new_now.has(o):
			continue                                     # (a new object goes out whole, as an add)
		if _co_send_one(o, "edit"):
			sent += 1


## One object's state, as `act` (add or edit). A cube object both sides already have sends only the cubes that
## changed (whole, it can be megabytes); `full` sends it whole anyway. False if there was nothing to send.
func _co_send_one(o: Node3D, act: String, full := false) -> bool:
	if act == "edit" and not full and o is CubeModelNode:
		var r := _co_send_cubes(o)
		if r >= 0:
			return r == 1
	var d := _with_group(o)
	var uid := _co_uid(o)
	var at: Vector3 = _co_last.get(uid, o.center())
	_co_seq += 1
	_co_send_msg({"t": "edit", "seq": _co_seq, "op": {"act": act, "kind": _co_kind(o), "uid": uid,
		"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)], "obj": d}})
	_co_last[uid] = o.center()
	_co_track(o)
	return true


const CO_EDIT_PART := 400000          ## bytes of an edit per message; bigger ones go in parts (the relay's limit is 2 MB)


## Send an edit message, in parts when it is too big for one (a whole big cube object; it used to be refused, so a
## paste of a big object never reached the others).
func _co_send_msg(msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	if text.to_utf8_buffer().size() <= CO_EDIT_PART:
		relay.send(msg)
		return
	var parts := []
	var i := 0
	while i < text.length():
		var n: int = mini(CO_EDIT_PART, text.length() - i)
		while n > 1 and text.substr(i, n).to_utf8_buffer().size() > CO_EDIT_PART:
			n = int(n * 0.9)
		parts.append(text.substr(i, n))
		i += n
	var pid := "%s.%d" % [relay.you, int(msg.get("seq", 0))]
	for k in parts.size():
		_co_seq += 1
		relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "part", "pid": pid, "part": k, "of": parts.size(), "text": parts[k]}})


## From now on, note which cubes of this cube object change, so its edits can go as just those.
func _co_track(o) -> void:
	if not o is CubeModelNode or not is_instance_valid(o):
		return
	var w: CubeWorld = o.world
	w.change_log = {}
	w.changed_all = false
	o.set_meta("co_world", w)
	o.set_meta("co_props", JSON.stringify(_co_cube_props(o)))


func _co_cube_props(o: CubeModelNode) -> Dictionary:
	var d := {"position": [snappedf(o.position.x, 0.001), snappedf(o.position.y, 0.001), snappedf(o.position.z, 0.001)],
		"yaw": snappedf(o.yaw, 0.001)}
	for key in ["group", "name", "folder", "hidden"]:
		if o.has_meta(key):
			d[key] = o.get_meta(key)
	return d


## A cube object's edit as only the cells that changed (and where it is, its name and folder). 1 sent, 0 nothing to
## send, -1 it has to go whole (not tracked, or replaced as a whole since).
func _co_send_cubes(o: CubeModelNode) -> int:
	var w: CubeWorld = o.world
	if w.change_log == null or w.changed_all or o.get_meta("co_world", null) != w:
		return -1
	var props := _co_cube_props(o)
	var sig := JSON.stringify(props)
	if (w.change_log as Dictionary).is_empty() and sig == String(o.get_meta("co_props", "")):
		return 0
	o.set_meta("co_props", sig)
	var uid := _co_uid(o)
	var at: Vector3 = _co_last.get(uid, o.center())
	_co_seq += 1
	_co_send_msg({"t": "edit", "seq": _co_seq, "op": {"act": "cubes", "kind": "cube", "uid": uid,
		"at": [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)], "props": props,
		"changes": w.take_changes(), "n": w.count(), "m": w.mats.size()}})
	_co_last[uid] = o.center()
	return 1


const CO_STATE_CHUNK := 400000        ## bytes of map text per message (the relay refuses one message over 2 MB)


## The whole map as text, for an editor who joined after the session started: it asks, and gets the map its owner
## has now, so both copies match from the first tick. In pieces, because a map with cube builds is far past the
## relay's limit for one message.
func _co_send_state(to: String) -> void:
	if relay == null or not relay.is_open() or to == "":
		return
	relay.send({"t": "names", "to": to, "names": _co_all_names()})   # (before the map: the newcomer takes our names)
	var text := JSON.stringify(_map_dict())
	var parts := []
	var i := 0
	while i < text.length():
		var n: int = mini(CO_STATE_CHUNK, text.length() - i)     # (characters: one can be up to three bytes)
		while n > 1 and text.substr(i, n).to_utf8_buffer().size() > CO_STATE_CHUNK:
			n = int(n * 0.9)
		parts.append(text.substr(i, n))
		i += n
	for k in parts.size():
		relay.send({"t": "state", "to": to, "part": k, "of": parts.size(), "map": parts[k]})
	_set_status("Sent the map to a co-editor (%d part(s))." % parts.size())


## Ask the session's owner for the map it has now, and say what that does to the map we have open.
func _co_request_state(quiet := false) -> void:
	if relay == null or not relay.is_open():
		return
	_co_waiting_state = true
	_co_state_since = Time.get_ticks_msec()
	_co_state_of = 0
	_co_state_next = -1
	_co_state_text = ""
	_set_status("Co-editing session %s: waiting for its map." % relay.session)
	relay.send({"t": "state_please"})
	if quiet:
		return
	_show_message("Co-editing session", ("You're in session %s as a co-editor. Its map is loading here so both copies match: the map you had open is replaced, and the file on disk is left alone.\n\n"
		+ "You see where the others are looking and what they have selected, in their own color. View > Co-editors hides it.\n"
		+ "Your camera and selection go out to them the same way.") % relay.session)


## Unsaved work here would be lost when their map lands: ask first.
func _co_ask_for_their_map() -> void:
	if _co_state_dialog == null:
		_co_state_dialog = ConfirmationDialog.new()
		_co_state_dialog.title = "Co-editing session"
		_co_state_dialog.ok_button_text = "Load their map"
		_co_state_dialog.cancel_button_text = "Stay with mine"
		_co_state_dialog.min_size = Vector2i(520, 0)
		_co_state_dialog.confirmed.connect(_co_request_state)
		_co_state_dialog.canceled.connect(_co_stay_local)
		_ui_root.add_child(_co_state_dialog)
	_co_state_dialog.dialog_text = ("Session %s is live. Joining it loads the map its owner has now over the one you have open, so both copies match.\n\n"
		+ "You have changes here that aren't saved: save them first (File > Save) if you want to keep them.\n\n"
		+ "\"Stay with mine\" leaves the session and changes nothing.") % relay.session
	_co_state_dialog.popup_centered()


## They chose to keep their own map, so the session is not for them.
func _co_stay_local() -> void:
	_leave_playtest()
	_set_status("Left the session: your map is as it was.")


## One piece of the session's map. The pieces arrive in order; the last one loads the whole thing.
func _co_state_chunk(m: Dictionary) -> void:
	if session_role != "editor":
		return                                     # (the map's owner keeps its own copy)
	var part := int(m.get("part", 0))
	var of := int(m.get("of", 1))
	if part == 0:
		_co_state_of = of
		_co_state_next = 0
		_co_state_text = ""
	elif part != _co_state_next or of != _co_state_of:
		_co_state_next = -1                        # (a piece is missing: wait for a fresh map)
		_co_state_text = ""
		return
	_co_state_text += String(m.get("map", ""))
	_co_state_next += 1
	if _co_state_next < _co_state_of:
		return
	var text := _co_state_text
	_co_state_next = -1
	_co_state_text = ""
	if text == JSON.stringify(_map_dict()):              # (nothing moved: no need to rebuild anything)
		_co_waiting_state = false
		_co_apply_names()                            # (but the names still have to come from the maker)
		_co_names.clear()
		_co_seed()
		_set_status("Session %s: this copy already matches." % relay.session)
		return
	_co_apply_state(text, String(m.get("name", "")))


## Every object's session name and where it is, so a newcomer uses the same names instead of inventing its own
## (two copies inventing names independently is what made edits land on the wrong object).
func _co_all_names() -> Array:
	var out := []
	for o in _all_objects():
		if not is_instance_valid(o) or o.is_queued_for_deletion():
			continue
		var c: Vector3 = (o as Node3D).center()
		out.append([_co_kind(o), _co_uid(o), snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(c.z, 0.01)])
	return out


## Give this copy the names that came with a map: each name goes to the nearest object of its kind that has no
## name yet, so the two copies agree exactly instead of matching by distance later.
func _co_apply_names() -> void:
	var used := {}
	for entry in _co_names:
		if not entry is Array or (entry as Array).size() < 5:
			continue
		var kind := String(entry[0])
		var uid := String(entry[1])
		var at := Vector3(entry[2], entry[3], entry[4])
		var root := _co_root(kind)
		if root == null or uid == "":
			continue
		var best: Node3D = null
		var best_d := 1.0
		for o in root.get_children():
			if used.has(o) or o.has_meta("co_uid") or o.is_queued_for_deletion():
				continue
			var d: float = (o as Node3D).center().distance_to(at)
			if d < best_d:
				best_d = d
				best = o
		if best != null:
			best.set_meta("co_uid", uid)
			used[best] = true


func _co_take_names(m: Dictionary) -> void:
	var list = m.get("names")
	if not list is Array:
		return
	_co_names = (list as Array).duplicate(true)
	_co_named = _co_names.size() > 0              # (from here on, an object's name is its identity)
	if _co_state_next < 0:                        # (no map on its way: our copy already matches, name it now)
		_co_apply_names()
		_co_seed()
		_set_status("This session's names: %d objects." % _co_names.size())


## Their map, loaded here: both copies match from here on, and it takes their name for every object. Not an undo
## step (there is nothing sane to step back to mid-session) and muted, so it doesn't go out again as thousands of
## adds.
func _co_apply_state(text: String, who: String) -> void:
	var d = JSON.parse_string(text)
	if not d is Dictionary:
		_co_waiting_state = false
		_set_status("Their map didn't arrive in one piece: both copies may differ.")
		return
	_co_mute = true
	_load_dict(d)
	_map_changed()
	_co_mute = false
	current_path = ""
	best_ghost = {}
	_undo.clear()
	_redo.clear()
	_co_queue.clear()
	_co_last.clear()
	_select(null)
	_co_apply_names()                              # (their names for the objects that just loaded)
	_co_names.clear()
	_co_seed()                                     # (it all came from them: none of it is new)
	outliner.sync_selection()
	_set_title("untitled")
	_mark_saved()
	_frame_clicked()
	_co_waiting_state = false
	_set_status("Loaded %s's map: both copies match from here on (File > Save keeps a copy of your own)." % (who if who != "" else "the session's"))


## Someone else's change. No checkpoint anywhere below, so it never lands in our undo history, and everything runs
## under _co_mute, so nothing is sent back out (they already have it).
func _co_apply(m: Dictionary) -> void:
	if not (session_role in ["maker", "editor"]):
		return
	var op = m.get("op")
	if not op is Dictionary:
		return
	if _co_mine(op):
		return                                   # (the object we're dragging is ours until we let go)
	var who := String(m.get("name", "A co-editor"))
	match String(op.get("act", "edit")):
		"add": _co_add(op, who)
		"del": _co_del(op, who)
		"folders": _co_folders(op)
		"env": _co_env_props(op)
		"reset": _co_reset(who)
		"part": _co_part(op, m)
		"cubes": _co_cubes(op, who, m)
		"need": _co_need(op)
		_: _co_edit(op, who)


## A piece of an edit too big for one message: put the pieces back together and apply it.
func _co_part(op: Dictionary, m: Dictionary) -> void:
	var pid := String(op.get("pid", ""))
	var of := int(op.get("of", 0))
	var k := int(op.get("part", -1))
	if pid == "" or of < 1 or of > 64 or k < 0 or k >= of:
		return
	if not _co_parts.has(pid):
		if _co_parts.size() > 16:                        # (pieces of an edit that never finished: let them go)
			_co_parts.erase(_co_parts.keys()[0])
		_co_parts[pid] = {}
	var got: Dictionary = _co_parts[pid]
	got[k] = String(op.get("text", ""))
	if got.size() < of:
		return
	_co_parts.erase(pid)
	var text := ""
	for i in of:
		text += String(got.get(i, ""))
	var whole = JSON.parse_string(text)
	if not whole is Dictionary or not (whole as Dictionary).get("op") is Dictionary or String(whole["op"].get("act", "")) == "part":
		return
	whole["id"] = m.get("id", "")
	whole["name"] = m.get("name", "A co-editor")
	_co_apply(whole)


## They changed some cubes of a cube object: make the same changes here. If the two copies turn out to differ, ask
## for the whole object.
func _co_cubes(op: Dictionary, who: String, m: Dictionary) -> void:
	var uid := String(op.get("uid", ""))
	var o := _co_find("cube", uid, _co_vec3(op.get("at", [])))
	var ch = op.get("changes")
	if o == null or not o is CubeModelNode or not ch is Dictionary:
		_co_ask_whole(uid, m)
		return
	var cm := o as CubeModelNode
	var props: Dictionary = op.get("props", {}) if op.get("props") is Dictionary else {}
	_co_mute = true
	if uid != "" and not cm.has_meta("co_uid"):
		cm.set_meta("co_uid", uid)
	var p = props.get("position")
	if p is Array and (p as Array).size() >= 3:
		cm.position = Vector3(p[0], p[1], p[2])
	cm.yaw = float(props.get("yaw", cm.yaw))
	cm.basis = Basis(Vector3.UP, deg_to_rad(cm.yaw))
	_take_group(cm, props)
	if String(props.get("group", "")) == "" and cm.has_meta("group"):
		cm.remove_meta("group")
	cm.world.apply_changes(ch)
	cm.set_meta("co_remote_at", Time.get_ticks_msec())
	if cm == selected:
		_refresh_props()
	_map_changed()
	_co_mute = false
	_co_queue.erase(cm)
	_co_track(cm)
	_co_last[_co_uid(cm)] = cm.center()
	if cm.world.count() != int(op.get("n", -1)) or cm.world.mats.size() != int(op.get("m", -1)):
		_co_ask_whole(uid, m)                            # (the copies had drifted apart: get theirs whole)
		return
	_set_status("%s: %s" % [who, cm.label()])


## Ask the editor who sent `m` for the whole of object `uid`.
func _co_ask_whole(uid: String, m: Dictionary) -> void:
	if uid == "" or relay == null or not relay.is_open():
		return
	_co_seq += 1
	relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "need", "uid": uid, "from": String(m.get("id", ""))}})


## Someone's copy of one of our objects differs: send it whole (only the one who changed it answers).
func _co_need(op: Dictionary) -> void:
	if relay == null or String(op.get("from", "")) != relay.you:
		return
	var rec = _co_uids.get(String(op.get("uid", "")), {})
	if rec is Dictionary and rec.get("o") is Node3D and is_instance_valid(rec["o"]):
		_co_send_one(rec["o"], "edit", true)


## True while we have the object in hand: an edit to something being dragged here waits, so a drag can't be pulled
## back and forth between two people. Ours goes out when we let go.
func _co_mine(op: Dictionary) -> bool:
	if _drag == Drag.NONE:
		return false
	var rec = _co_uids.get(String(op.get("uid", "")), {})
	if not rec is Dictionary or not rec.has("o"):
		return false
	var o = rec["o"]
	return o is Node3D and is_instance_valid(o) and o in selection()


## One object changed without the selection being involved: a rename in the outliner, hidden, filed in a folder.
func _co_touch(o: Node3D) -> void:
	if _co_mute or relay == null or not relay.is_open() or not (session_role in ["maker", "editor"]):
		return
	if is_instance_valid(o):
		_co_queue[o] = true


## The outliner's folders changed (one renamed or made): small enough to send as they are.
func _co_send_folders() -> void:
	if _co_mute or relay == null or not relay.is_open() or not (session_role in ["maker", "editor"]):
		return
	_co_seq += 1
	relay.send({"t": "edit", "seq": _co_seq, "op": {"act": "folders", "folders": outliner.folders}})


## The other editor changed the map's look (Map panel: sky, water, lava, glass): take theirs.
func _co_env_props(op: Dictionary) -> void:
	var d = op.get("environment")
	if not d is Dictionary:
		return
	_co_mute = true
	environment = Look.default_environment()
	environment.merge(d, true)
	_apply_environment()
	_refresh_props()
	_co_env = JSON.stringify(environment)
	_map_changed()
	_co_mute = false


func _co_folders(op: Dictionary) -> void:
	var f = op.get("folders")
	if not f is Array:
		return
	_co_mute = true
	outliner.folders = (f as Array).duplicate(true)
	outliner.refresh.call_deferred(true)
	_map_changed()
	_co_mute = false


## The session's owner started a new map (or opened another one): take theirs, so everyone builds the same map.
func _co_reset(who: String) -> void:
	if session_role != "editor":
		return
	_co_request_state(true)
	_set_status("%s started another map: loading it here." % who)


## They made an object: build our own copy of it here.
func _co_add(op: Dictionary, who: String) -> void:
	var d = op.get("obj")
	var kind := String(op.get("kind", ""))
	var uid := String(op.get("uid", ""))
	if not d is Dictionary or uid == "" or _co_root(kind) == null:
		return
	if _co_find_uid(kind, uid) != null:
		return                                       # (the same add arriving twice)
	var o := _co_new_node(kind)
	if o == null:
		return
	_co_root(kind).add_child(o)
	_co_mute = true
	o.set_meta("co_uid", uid)
	o.from_dict(d)
	_take_group(o, d)
	if o.has_method("rebuild"):
		o.rebuild()
	o.set_meta("co_remote_at", Time.get_ticks_msec())
	_map_changed()
	_co_mute = false
	_co_track(o)
	_co_uids[uid] = {"o": o, "kind": kind}
	_co_last[uid] = o.center()
	_set_status("%s added a %s." % [who, String(o.call("label")) if o.has_method("label") else kind])


## They removed an object: take ours out, without a checkpoint and without leaving it selectable.
func _co_del(op: Dictionary, who: String) -> void:
	var kind := String(op.get("kind", ""))
	var o := _co_find_uid(kind, String(op.get("uid", "")))
	if o == null:
		return
	_co_mute = true
	if o == selected:
		_select(null)
	_extra.erase(o)
	var parent := o.get_parent()
	if parent != null:
		parent.remove_child(o)
	o.queue_free()
	_map_changed()
	_co_mute = false
	outliner.sync_selection()
	_co_queue.erase(o)
	var uid := String(op.get("uid", ""))
	_co_uids.erase(uid)
	_co_last.erase(uid)
	_set_status("%s deleted a %s." % [who, kind])


func _co_new_node(kind: String) -> Node3D:
	match kind:
		"ramp": return RampNode.new()
		"entity": return EntityNode.new()
		"prop": return PropNode.new()
		"text": return TextNode.new()
		"light": return LightNode.new()
		"particle": return ParticleNode.new()
		"cube": return CubeModelNode.new()
		"block": return BlockNode.new()
	return null


## The object with exactly that session id, or null.
func _co_find_uid(kind: String, uid: String) -> Node3D:
	var root := _co_root(kind)
	if root == null or uid == "":
		return null
	for o in root.get_children():
		if o.has_meta("co_uid") and String(o.get_meta("co_uid")) == uid:
			return o
	return null


## They changed an object: put our copy in the same state.
func _co_edit(op: Dictionary, who: String) -> void:
	var d = op.get("obj")
	if not d is Dictionary:
		return
	var kind := String(op.get("kind", ""))
	var uid := String(op.get("uid", ""))
	var o := _co_find(kind, uid, _co_vec3(op.get("at", [])))
	if o == null:
		_set_status("%s changed an object this copy doesn't have." % who)
		return
	_co_mute = true
	if uid != "" and not o.has_meta("co_uid"):
		o.set_meta("co_uid", uid)
	o.from_dict(d)
	_take_group(o, d)
	if String(d.get("group", "")) == "" and o.has_meta("group"):
		o.remove_meta("group")
	if o.has_method("rebuild"):
		o.rebuild()
	o.set_meta("co_remote_at", Time.get_ticks_msec())     # (undo leaves this one alone: it's theirs)
	if o == selected:
		_refresh_props()
	_map_changed()
	_co_mute = false
	_co_queue.erase(o)
	_co_track(o)
	var oid := _co_uid(o)
	_co_last[oid] = o.center()
	_set_status("%s: %s" % [who, String(o.call("label")) if o.has_method("label") else kind])


static func _co_vec3(a) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


## Co-editors in a view: their camera, where they look, where their mouse is, and what they have selected. Drawn
## with `cam`, the camera that view really uses - build mode (E) has its own, so it calls this for its own view.
## Co-editors' bodies (U17): one per peer, placed where their cursor is and turned where they look. Only while they
## are in build mode (in the 2D views their body would be in the way of the drawing) and while View > Co-editors is
## on. They live under `co_avatars_root` in the shared world, so every pane, the 2D views and build mode see the same
## body - build mode's camera is its own but its world is this one.
var _co_avatars := {}                    ## co-editor id -> CoAvatar


func _update_co_avatars() -> void:
	var live: bool = show_co_editors and not play.active and relay != null and not co_cursors.is_empty()
	for id in co_cursors:
		var m: Dictionary = co_cursors[id]
		var a: CoAvatar = _co_avatars.get(id)
		if not live or String(m.get("view", "")) != "build":
			if a != null:
				a.visible = false
			continue
		if a == null:
			a = CoAvatar.new()
			co_avatars_root.add_child(a)
			_co_avatars[id] = a
		var who := String(m.get("name", "Co-editor"))
		if a.who != who:
			a.setup(_tester_color(who), who)
		a.visible = true
		# (their cursor says where their camera is, at eye height: stand the body so the visor is there, not its feet)
		a.place(_co_vec3(m.get("pos", [])) - Vector3(0.0, CoAvatar.EYE_AT, 0.0), _co_vec3(m.get("aim", [])))
	for id in _co_avatars.keys():
		if not co_cursors.has(id):
			_co_avatar_free(id)


func _co_avatar_free(id: String) -> void:
	if _co_avatars.has(id):
		var a = _co_avatars[id]
		if is_instance_valid(a):
			a.queue_free()
		_co_avatars.erase(id)


func _co_avatar_free_all() -> void:
	for id in _co_avatars.keys():
		_co_avatar_free(id)


func draw_co_overlay(cam: Camera3D, ov: Control) -> void:
	if cam == null or co_cursors.is_empty():
		return
	_draw_co_editors(cam, ov)
	_draw_co_mice(cam, ov, ov.size)


## Co-editors in the views: their camera (a dot with a line along where they look, named) and, outlined in their
## color, the object they have selected.
## Where each co-editor's mouse is, with their name and what they're doing, drawn in the view we're drawing.
func _draw_co_mice(cam: Camera3D, ov: Control, size: Vector2) -> void:
	var font := ov.get_theme_default_font()
	for id in co_cursors:
		var m: Dictionary = co_cursors[id]
		var mp = m.get("mouse", [])
		if not mp is Array or (mp as Array).size() < 3:
			continue
		var at := _co_vec3(mp)
		if cam.is_position_behind(at):
			continue
		var s := cam.unproject_position(at)
		if not Rect2(Vector2.ZERO, size).has_point(s):
			continue
		var col := _tester_color(String(m.get("name", "?")))
		var arrow := PackedVector2Array([s, s + Vector2(0, 15), s + Vector2(4.2, 10.5), s + Vector2(10.5, 10.5)])
		ov.draw_colored_polygon(arrow, Color(0, 0, 0, 0.8))
		ov.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), col, 1.4)
		var label := String(m.get("name", "?"))
		var doing := String(m.get("doing", ""))
		if doing != "":
			label += "  ·  " + doing
		ov.draw_string_outline(font, s + Vector2(13, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, s + Vector2(13, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


func _draw_co_editors(cam: Camera3D, ov: Control) -> void:
	var font := ov.get_theme_default_font()
	for id in co_cursors:
		var m: Dictionary = co_cursors[id]
		var col := _tester_color(String(m.get("name", "?")))
		var sel := m.get("sel", []) as Array
		for s in sel:                                   # their selection, outlined in our copy of the same object
			if not s is Array or (s as Array).size() < 4:
				continue
			var o := _co_object_at(String(s[0]), Vector3(s[1], s[2], s[3]))
			if o != null:
				_draw_lines(cam, ov, o.outline if o is RampNode else o.outline_lines(), Color(col, 0.85), 2.0)
		var at := _co_vec3(m.get("pos", []))
		if cam.is_position_behind(at):
			continue
		var s_at := cam.unproject_position(at)
		var aim := _co_vec3(m.get("aim", []))
		var dir := Vector2(0, -1)
		if aim.length() > 0.001 and not cam.is_position_behind(at + aim * 3.0):
			var d := cam.unproject_position(at + aim * 3.0) - s_at
			if d.length() > 1.0:
				dir = d.normalized()
		var perp := Vector2(-dir.y, dir.x)
		ov.draw_circle(s_at, 6.5, Color(0, 0, 0, 0.55))
		ov.draw_circle(s_at, 4.0, col)
		var tip := s_at + dir * 17.0
		ov.draw_line(s_at, tip, Color(col, 0.9), 2.0)
		ov.draw_line(tip, tip - dir * 6.0 + perp * 5.0, Color(col, 0.9), 2.0)
		ov.draw_line(tip, tip - dir * 6.0 - perp * 5.0, Color(col, 0.9), 2.0)
		if aim.length() > 0.001:                        # the field of view they're looking down
			var side := aim.normalized().cross(Vector3.UP)
			if side.length() > 0.001:
				side = side.normalized() * 0.577 * 4.0   # (60 degrees across)
				for sgn in [1.0, -1.0]:
					var e: Vector3 = at + aim * 4.0 + side * sgn
					if not cam.is_position_behind(e):
						ov.draw_line(s_at, cam.unproject_position(e), Color(col, 0.45), 1.5)
		var label := String(m.get("name", "?"))
		if not sel.is_empty() and sel[0] is Array and (sel[0] as Array).size() >= 1:
			label += "  ·  " + String((sel[0] as Array)[0])
		ov.draw_string_outline(font, s_at + Vector2(13, -11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
		ov.draw_string(font, s_at + Vector2(13, -11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


# ================================================================================================= export
## Wrapped text in a dialog needs its width up front: measured at no width, a label is one word a line, and the
## dialog grew past the screen with its Export button off the bottom (a window never shrinks back on its own).
static func _wrap_width(box: Control, width: int) -> void:
	for c in box.find_children("*", "Label", true, false):
		if (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF and c.custom_minimum_size.x <= 0.0:
			c.custom_minimum_size.x = width


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
	var css := CheckButton.new()                         # CS:S's own textures: Valve's, so copying them in is a choice
	css.text = "Copy CS:S textures into the map"
	css.tooltip_text = "Surfaces using Counter-Strike: Source materials get the real textures, copied from your own CS:S install.
They're Valve's textures: leave this off and those surfaces get a similar MALLET material instead."
	css.focus_mode = Control.FOCUS_NONE
	box.add_child(css)
	_fields["export_css"] = css
	var css_note := Label.new()
	css_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	css_note.add_theme_font_size_override("font_size", 12)
	css_note.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84))
	box.add_child(css_note)
	_fields["export_css_note"] = css_note
	var note := Label.new()
	note.text = "If SurfsUp is running and you are replacing a map you already loaded, restart SurfsUp before loading it again."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
	box.add_child(note)
	_wrap_width(box, 528)
	_export_dialog.confirmed.connect(_do_export)
	_ui_root.add_child(_export_dialog)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(d): _export_dir.text = d)
	_ui_root.add_child(_dir_dialog)


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
	_css_sky.add_item(BAKED_SKY_LABEL)                  # (rendered from this map's own sky into a skybox)
	for sky in VmfExporter.SKY_CHOICES:
		_css_sky.add_item(sky)
	_css_sky.tooltip_text = ("This map's sky: MALLET renders the map's sky (your own sky shader too) into a 6-sided\n"
		+ "skybox that goes inside the map. The others are CS:S's own skies.")
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
	_wrap_width(box, 568)
	_css_dialog.confirmed.connect(_do_css_export)
	_ui_root.add_child(_css_dialog)


func _css_clicked() -> void:
	if _css_thread and _css_thread.is_alive():
		_set_status("A CS:S compile is still running...")
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var base := current_path.get_file().get_basename() if current_path != "" else "mymap"
	var default_name := base if base.begins_with("surf_") else "surf_" + base
	_css_name.text = cfg.get_value("css", "name_" + current_path.md5_text(), default_name)
	_css_dir.text = cfg.get_value("css", "dir", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MALLET exports/css"))
	var sky: String = VmfExporter.SKIES.get(environment.get("preset", "day"), "sky_day01_01")
	_css_sky.select(0 if String(environment.get("sky_shader", "")) != "" else maxi(VmfExporter.SKY_CHOICES.find(sky), 0) + 1)
	var css := VmfExporter.find_css()
	_css_compile.disabled = css == ""
	_css_compile.button_pressed = css != "" and cfg.get_value("css", "compile", true)
	_css_compile.tooltip_text = "Found CS:S at " + css if css != "" else "Counter-Strike: Source wasn't found, so only the .vmf is written."
	_css_dialog.size = Vector2i(600, 0)                   # (fit it to what shows now)
	_css_dialog.popup_centered()


func _do_css_export() -> void:
	var map_name := _css_name.text.strip_edges()
	if not SurfsUpExporter.valid_name(map_name):
		_show_message("Can't export yet", "Map names can only use letters, numbers, _ and - (no spaces).")
		return
	var vmf := _css_dir.text.strip_edges().path_join(map_name + ".vmf")
	var opts := {"skyname": _css_sky.get_item_text(_css_sky.selected), "airaccelerate": int(_css_aa.value)}
	if _css_sky.selected == 0:                          # this map's own sky, rendered into the six skybox images
		_set_status("Making the sky into a CS:S skybox...")
		opts["skyname"] = "mallet_" + map_name.to_lower()
		opts["sky_faces"] = await Look.bake_skybox(environment, self)
	var res := VmfExporter.export_vmf(_map_dict(), vmf, opts)
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
		var files := VmfExporter.write_materials(res.get("materials", []), vmf.get_base_dir())
		if not files.is_empty():
			notes += "\n\nThe map's textures and sky are in %s/materials - copy that materials folder into cstrike (or compile here, which packs them into the map)." % vmf.get_base_dir()
		_show_message("Exported for CS:S", "Wrote %s (%d brushes).\n\n%s" % [vmf, res["brushes"], notes])
		_set_status("Wrote %s - open it in Hammer or compile it with vbsp / vvis / vrad." % vmf.get_file())
		return
	var quality := "fast" if _css_quality.selected == 0 else "final"
	_css_status = notes
	_set_status("Compiling %s for CS:S (%d brushes)... this can take a minute; keep working meanwhile." % [map_name, res["brushes"]])
	_css_thread = Thread.new()
	var mats: Array = res.get("materials", [])
	_css_thread.start(func(): return VmfExporter.compile(vmf, VmfExporter.find_css(), quality, mats))


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


## One message box at a time: a second message replaces the first (two exclusive dialogs at once is an error, and
## the user only reads the newest one anyway).
func _show_message(title: String, text: String) -> void:
	var a: AcceptDialog = _ui.get_node_or_null("MessageBox")
	if a == null:
		a = AcceptDialog.new()
		a.name = "MessageBox"
		a.confirmed.connect(a.queue_free)
		a.canceled.connect(a.queue_free)
		_ui_root.add_child(a)
	a.title = title
	a.dialog_text = text
	a.popup_centered()


func _export_clicked() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var default_name := current_path.get_file().get_basename() if current_path != "" else "surf_mymap"
	_export_name.text = cfg.get_value("export", "name_" + current_path.md5_text(), default_name)
	_export_dir.text = cfg.get_value("export", "maps_dir", SurfsUpExporter.guess_maps_dir())
	var n_css := SurfsUpExporter.css_count(_map_dict())
	_fields["export_css"].button_pressed = cfg.get_value("export", "css_textures", false)
	_fields["export_css"].visible = n_css > 0
	_fields["export_css_note"].visible = n_css > 0
	_fields["export_css_note"].text = ("This map uses %d CS:S material%s. They're Valve's textures, copied from your CS:S " 		+ "install when this is on; off, those surfaces get a similar MALLET material.") % [n_css, "" if n_css == 1 else "s"]
	_export_dialog.size = Vector2i(560, 0)                # (a window never shrinks on its own: fit it to what shows now)
	_export_dialog.popup_centered()
	_export_name.grab_focus()


func _do_export() -> void:
	var map_name := _export_name.text.strip_edges()
	var dir := _export_dir.text.strip_edges()
	var css_on: bool = _fields["export_css"].visible and _fields["export_css"].button_pressed
	var err := SurfsUpExporter.export_pack(_map_dict(), map_name, dir, css_on)
	if err != "":
		var a := AcceptDialog.new()
		a.title = "Can't export yet"
		a.dialog_text = err
		_ui_root.add_child(a)
		a.popup_centered()
		_set_status("Export failed: " + err.get_slice("
", 0))
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("export", "maps_dir", dir)
	if _fields["export_css"].visible:
		cfg.set_value("export", "css_textures", _fields["export_css"].button_pressed)
	cfg.set_value("export", "name_" + current_path.md5_text(), map_name)
	cfg.save(SETTINGS_PATH)
	_set_status("Exported %s.pck to %s - in SurfsUp press ~ and type:  map %s" % [map_name, dir, map_name])
