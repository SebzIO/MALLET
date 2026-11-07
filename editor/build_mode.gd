class_name BuildMode
extends Node
## Build mode: fly around the map in first person and build with cubes in real time, the way Cube 2: Sauerbraten's
## editor works - the same keys wherever it can. Point at a face and roll the mouse wheel to pull cubes out of it or
## push them in; hold a key while rolling to push faces or corners 1/8 at a time, change the grid, texture, rotate;
## sculpt terrain in heightmap mode; paint blend layers; fill space with water, lava, glass, clip...; place, move and
## tweak entities (lights, platforms, zones, text) where you aim. Each build is a cube object: in the editor views it
## moves, turns and copies as one object. E (or Esc) goes back to the editor; P plays from where you are,
## Ctrl+P from the map's start (like the editor's Play); Esc in play mode comes back to build mode.

signal stopped

const PICK_LAYER := 1 << 19
const HELP := [
	["Look / fly", "mouse  /  W A S D  (Shift: fast)"], ["P", "play from here (Esc comes back)"], ["Ctrl+P", "play from the start (Esc comes back)"], ["", ""],
	["Mouse wheel", "pull cubes out / push them in"],
	["F + wheel", "push / pull the face 1/8 at a time"],
	["Q + wheel", "push / pull the corner you aim at"],
	["Middle drag + wheel", "select corners of cubes, then shape them"],
	["G + wheel", "grid size"], ["Ctrl (hold)", "aim at the cube itself (passthrough)"],
	["Y + wheel  /  Y", "change texture  /  pick up the one you aim at"],
	["O / P + wheel", "shift the texture across / up"],
	["F2  /  F3", "texture menu  /  texture settings"], ["0", "texture all faces on / off"],
	["R + wheel  /  X", "rotate  /  flip the selection"], ["", ""],
	["Left click (drag)", "select faces (or an entity)"], ["Shift + drag", "move the selected cubes"],
	["Right click", "extend the selection / turn it to this face"],
	["Space  /  J", "drop the selection  /  go to it"],
	["C / V  /  Delete", "copy / paste  /  delete"], ["Z or U  /  I", "undo / redo"], ["", ""],
	["H (or hold Alt)", "heightmap mode;  B + wheel: brush"],
	["Keypad 1-5  /  0", "blend painting modes  /  off;  8 / 9 brush size"],
	["T", "commands: materials (water, lava, glass...), replace"],
	["Tab", "place an entity;  1-4 + wheel: its settings"],
	["N", "start a new cube object"],
	["M  5  6  7  8  L", "materials  HUD  snap  outlines  wireframe  fullbright"],
	["F5  /  E or Esc", "save  /  back to the editor"], ["F1", "hide this"],
]

var active := false
var resume_after_play := false
var editor: Node
var models: Node3D
var cam := Camera3D.new()
var yaw := 0.0
var pitch := 0.0
var speed := 10.0
var grid_p := 0
var model: CubeModelNode = null          ## the cube object you're building on (null: the next cubes start a new one)
var sel := {}                            ## {o, s, p, orient, model} (empty = none: edits use the face you aim at)
var corners: Array = []                  ## corner selection: [a0, a1, b0, b1] half-cell squares on the face (with sel), or empty
var target := {}                         ## what the crosshair is on
var texture := ""
var mru: Array = []                      ## textures, most recently used first (Sauerbraten's texmru)
var all_faces := false
var clip := {}
var hmap := false
var brush := 2
var blend_mode := 0
var blend_radius := 2.0
var ent_sel: Array = []                  ## selected entities (lights, platforms, zones, props, text)
var entsnap := true
var _hud_on := true
var _history: Array = []
var _redo: Array = []
var _drag := ""                          ## "", "select", "corners", "cut", "entity", "paint"
var _drag_from := {}
var _cut := {}
var _ent_drag := {}
var _paint_time := 0.0
var _y_used := false
var _ui_open := false
var _hud := CanvasLayer.new()
var _info := Label.new()
var _help := PanelContainer.new()
var _msg := Label.new()
var _msg_time := 0.0
var _cross: Label
var _banner := Label.new()               ## big notice while heightmap / blend painting is on (easy to leave on by mistake)
var _lines := MeshInstance3D.new()
var _im := ImmediateMesh.new()
var _menu: PopupMenu
var _tex_panel: PanelContainer
var _tex_fields := {}
var _tex_updating := false


func setup(ed: Node, root: Node3D) -> void:
	editor = ed
	models = root


func _ready() -> void:
	cam.fov = 80.0
	cam.near = 0.05
	cam.far = 8000.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	_lines.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 10
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA      # (the corner squares are see-through)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_lines.material_override = m
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.visible = false
	add_child(_lines)
	_hud.layer = 6
	_hud.visible = false
	add_child(_hud)
	_cross = Label.new()
	_cross.text = "+"
	_cross.add_theme_font_size_override("font_size", 26)
	_cross.add_theme_color_override("font_outline_color", Color.BLACK)
	_cross.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_cross)
	for l in [_info, _msg]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		_hud.add_child(l)
	_info.add_theme_font_size_override("font_size", 16)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.custom_minimum_size = Vector2(900, 0)
	_msg.add_theme_font_size_override("font_size", 20)
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_banner)
	_build_help()
	_build_tex_panel()
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_menu_pressed)
	_menu.popup_hide.connect(_ui_closed)
	_hud.add_child(_menu)


func _build_help() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_content_margin_all(12)
	bg.set_corner_radius_all(6)
	_help.add_theme_stylebox_override("panel", bg)
	_hud.add_child(_help)
	var hb := VBoxContainer.new()
	_help.add_child(hb)
	var title := Label.new()
	title.text = "BUILD MODE  -  Sauerbraten-style"
	title.add_theme_font_size_override("font_size", 16)
	hb.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 0)
	hb.add_child(grid)
	for row in HELP:
		for i in 2:
			var l := Label.new()
			l.text = row[i]
			l.add_theme_font_size_override("font_size", 13)
			if i == 0:
				l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			grid.add_child(l)


# ------------------------------------------------------------------------------------------------ start / stop
func start(from: Transform3D, edit_model: CubeModelNode = null) -> void:
	if active:
		return
	active = true
	cam.global_position = from.origin
	var f := -from.basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))
	_apply_cam()
	model = edit_model
	sel = {}
	corners = []
	ent_sel = []
	_history.clear()
	_redo.clear()
	_enter()
	say("Build mode%s. Aim and roll the mouse wheel. F1 shows the keys." % (" - editing the selected cube object" if edit_model else ""))


func _enter() -> void:
	active = true
	cam.current = true
	_hud.visible = true
	_lines.visible = true
	_ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Back from play mode (P).
func resume() -> void:
	resume_after_play = false
	_enter()
	say("Back in build mode.")


func stop() -> void:
	if not active:
		return
	_leave()
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED
	for e in _history:                                  # objects undone out of existence, and empty ones
		if e["t"] == "new" and is_instance_valid(e["m"]) and not (e["m"] as Node).is_inside_tree():
			e["m"].queue_free()
	for m in models.get_children():
		if m.world.count() == 0 and m.world.mats.is_empty():
			m.queue_free()
	_history.clear()
	_redo.clear()
	stopped.emit()


func _leave() -> void:
	active = false
	_drag = ""
	cam.clear_current(false)
	_hud.visible = false
	_lines.visible = false
	_tex_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func say(t: String) -> void:
	_msg.text = t
	_msg_time = 3.5


func _apply_cam() -> void:
	cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


static func _frame(m) -> Transform3D:
	return (m as CubeModelNode).global_transform if m != null and is_instance_valid(m) else Transform3D.IDENTITY


# ------------------------------------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not active or _ui_open:
		if _ui_open and event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_F3] and _tex_panel.visible:
			_close_tex_panel()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.keycode == KEY_F11:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var k := 0.0025 * Settings.build_mouse()            # (View > Mouse sensitivity)
		yaw -= event.relative.x * k
		pitch = clampf(pitch - event.relative.y * k * Settings.y_sign(), deg_to_rad(-89), deg_to_rad(89))
		_apply_cam()
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			_key(event)
		elif not event.pressed and event.keycode == KEY_Y and not _y_used:
			_get_texture()


func _mouse_button(e: InputEventMouseButton) -> void:
	if e.button_index != MOUSE_BUTTON_WHEEL_UP and e.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		_flush_wheel()                                   # (a click acts on the selection after the notches)
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed:
				_left_down(e.shift_pressed, e.ctrl_pressed)
			else:
				_left_up()
		MOUSE_BUTTON_MIDDLE:
			if e.pressed and _on_cube(target):
				_drag = "corners"
				_drag_from = target.duplicate()
				_update_corner_drag()
			elif e.pressed:
				say("Corner selection starts on a cube (it shapes cubes that are there)")
			elif not e.pressed and _drag == "corners":
				_drag = ""
		MOUSE_BUTTON_RIGHT:
			if e.pressed and not target.is_empty():
				_right_click()
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				wheel(1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				wheel(-1)


func _left_down(shift: bool, ctrl: bool) -> void:
	if target.is_empty():
		return
	if blend_mode > 0:
		var m = target["model"]
		if m != null and target["hit"]:
			_drag = "paint"
			(m as CubeModelNode).world.begin()
			_drag_from = {"model": m}
			_paint()
		return
	if target.get("entity") != null:
		var ent: Node3D = target["entity"]
		if ctrl:
			if ent in ent_sel:
				ent_sel.erase(ent)
			else:
				ent_sel.append(ent)
		elif not ent in ent_sel:
			ent_sel = [ent]
		_drag = "entity"
		_ent_drag = {"start": target["point"], "before": {}, "plane_y": ent.center().y}
		for o in ent_sel:
			_ent_drag["before"][o] = o.to_dict()
		say("%s selected - drag to move it, 1-4 + wheel to change it, Delete to remove it" % ent.label())
		return
	ent_sel = []
	if shift and not sel.is_empty() and _in_sel(target["sel"]) and sel.get("model") != null:
		_start_cut()
		return
	_drag = "select"
	_drag_from = target["sel"].duplicate()
	sel = _drag_from.duplicate()
	corners = []


func _left_up() -> void:
	match _drag:
		"paint":
			var m: CubeModelNode = _drag_from["model"]
			if m.world.commit():
				_push_history({"t": "cubes", "m": m})
		"cut":
			var m: CubeModelNode = _cut["model"]
			if m.world.commit():
				_push_history({"t": "cubes", "m": m})
			say("Moved")
		"entity":
			for o in ent_sel:
				var before: Dictionary = _ent_drag["before"].get(o, {})
				if not before.is_empty() and before != o.to_dict():
					_push_history({"t": "ent", "obj": o, "before": before, "after": o.to_dict()})
	_drag = ""


func _right_click() -> void:
	var ts: Dictionary = target["sel"]
	if sel.is_empty():
		sel = ts.duplicate()
	elif _in_sel(ts):
		sel["orient"] = ts["orient"]                    # Sauerbraten's reorient
		say("Selection turned to face %s" % CubeWorld.ORIENT_SLOTS[ts["orient"]])
	else:
		sel = _bounds(sel, ts)


func _key(e: InputEventKey) -> void:
	_flush_wheel()                                       # (keys act after the notches gathered this frame)
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_E, KEY_ESCAPE: stop()
		KEY_P:
			if ctrl:
				_play_from_start()
			elif not Input.is_key_pressed(KEY_O):
				_play_here()
		KEY_SPACE:
			sel = {}
			corners = []
			ent_sel = []
		KEY_X: flip()
		KEY_C: copy()
		KEY_V: paste()
		KEY_Z, KEY_U: undo()
		KEY_I: redo()
		KEY_Y:
			if ctrl:
				redo()
			else:
				_y_used = false
		KEY_DELETE, KEY_BACKSPACE: delete()
		KEY_0: _toggle("all_faces")
		KEY_F1: _help.visible = not _help.visible
		KEY_F2: _open_picker(func(id): _apply_texture(id))
		KEY_F3: _open_tex_panel()
		KEY_F5:
			if editor.current_path != "":
				editor.save_map(editor.current_path)
				say("Saved %s" % editor.current_path.get_file())
			else:
				say("Save it from the editor first (File > Save) - then F5 saves here")
		KEY_F9: say("Texture: %s" % _slot_text(_slot_here()))
		KEY_J: goto_sel()
		KEY_N:
			model = null
			sel = {}
			say("The next cubes you build in the air start a new cube object")
		KEY_H:
			hmap = not hmap
			say("Heightmap mode %s (B + wheel: brush = %s)" % ["on" if hmap else "off", CubeWorld.BRUSHES[brush][0]])
		KEY_M: _toggle("mats")
		KEY_5: _toggle("hud")
		KEY_6: _toggle("snap")
		KEY_7: _toggle("outline")
		KEY_8: _toggle("wireframe")
		KEY_L: _toggle("fullbright")
		KEY_K: say("Lighting is live in MALLET - nothing to bake")
		KEY_T: _open_commands()
		KEY_TAB: _open_place_menu()
		KEY_KP_ENTER: _select_ents_in_sel()
		KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5:
			blend_mode = e.keycode - KEY_KP_0
			say(["Blend painting off", "Blend paint: set", "Blend paint: paint the layer in", "Blend paint: paint it out",
				"Blend paint: in (inverted)", "Blend paint: out (inverted)"][blend_mode] + ("" if blend_mode == 0 else
				"  -  left mouse paints faces that have a blend layer (F3)"))
		KEY_KP_8, KEY_KP_9:
			blend_radius = clampf(blend_radius * (0.8 if e.keycode == KEY_KP_8 else 1.25), 0.25, 32.0)
			say("Blend brush: %.1f m" % blend_radius)


func _toggle(what: String) -> void:
	match what:
		"all_faces":
			all_faces = not all_faces
			say("Texture all faces: %s" % ("on" if all_faces else "off"))
		"mats":
			var on := true
			for m in models.get_children():
				on = not m.world.show_mats
				break
			for m in models.get_children():
				m.set_show_mats(on)
			say("Invisible materials (clip, death...) %s" % ("shown" if on else "hidden"))
		"hud":
			_hud_on = not _hud_on
			_info.visible = _hud_on
			_help.visible = _hud_on and _help.visible
		"snap":
			entsnap = not entsnap
			say("Entities snap to the grid: %s" % ("on" if entsnap else "off"))
		"outline":
			var on := not CubeModelNode.outline_mode
			CubeModelNode.outline_mode = on
			for m in models.get_children():
				m.rebuild_all()
			say("Cube outlines %s" % ("on" if on else "off"))
		"wireframe":
			var vp := get_viewport()
			vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED if vp.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME else Viewport.DEBUG_DRAW_WIREFRAME
		"fullbright":
			var vp := get_viewport()
			vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED if vp.debug_draw == Viewport.DEBUG_DRAW_UNSHADED else Viewport.DEBUG_DRAW_UNSHADED


## The selection, or if there's none the face under the crosshair.
func op_sel() -> Dictionary:
	if not sel.is_empty():
		return sel
	return target.get("sel", {})


func hmap_on() -> bool:
	return hmap or Input.is_key_pressed(KEY_ALT)


## Plain wheel notches on a selection wait here until the frame's end, then run as one edit (pull_n / push_n): a
## fast spin over a big selection is one quick edit and one mesh update, not one of each per notch.
var _wheel_pending := 0


func _flush_wheel() -> void:
	var n := _wheel_pending
	_wheel_pending = 0
	if n == 0 or sel.is_empty():
		return
	var s := sel
	var tex := texture
	var out = _edit(s, func(w: CubeWorld): return w.push_n(s, n) if n > 0 else w.pull_n(s, -n, tex))
	if out != null and not sel.is_empty():
		var keep_model = sel.get("model")
		sel = (out as Dictionary).duplicate()
		sel["model"] = keep_model if keep_model != null else model


## What the mouse wheel does: dir 1 = rolled away from you (push in), -1 = towards you (pull out).
func wheel(dir: int) -> void:
	if _wheel_pending != 0:
		var plain := not hmap_on() and corners.is_empty() and ent_sel.is_empty()
		for k in [KEY_G, KEY_B, KEY_Y, KEY_O, KEY_P, KEY_R, KEY_F, KEY_Q]:
			plain = plain and not Input.is_key_pressed(k)
		if not plain:
			_flush_wheel()                               # (keep the order: gathered notches first)
	if Input.is_key_pressed(KEY_G):
		grid_p = clampi(grid_p + dir, CubeWorld.MIN_P, CubeWorld.MAX_P)
		sel = {}
		corners = []
		say("Grid: %s cubes" % _metres_text(CubeWorld.metres(grid_p)))
		return
	if Input.is_key_pressed(KEY_B):
		brush = posmod(brush + dir, CubeWorld.BRUSHES.size())
		say("Heightmap brush: %s" % CubeWorld.BRUSHES[brush][0])
		return
	if not ent_sel.is_empty():
		for i in 4:
			if Input.is_key_pressed(KEY_1 + i):
				_ent_prop(i + 1, dir)
				return
		if Input.is_key_pressed(KEY_R):
			for o in ent_sel:
				var before: Dictionary = o.to_dict()
				o.rotate_by(15.0 * dir)
				_push_history({"t": "ent", "obj": o, "before": before, "after": o.to_dict()})
			return
	var s := op_sel()
	if s.is_empty():
		return
	if Input.is_key_pressed(KEY_Y):
		_y_used = true
		var ids := _texture_cycle()
		texture = ids[posmod(ids.find(texture) + dir, ids.size())]
		_apply_texture(texture)
		return
	if Input.is_key_pressed(KEY_O) or Input.is_key_pressed(KEY_P):
		var key := "u" if Input.is_key_pressed(KEY_O) else "v"
		_edit(s, func(w: CubeWorld):
			w.set_slot_param(s, all_faces, func(d: Dictionary) -> Dictionary:
				d[key] = fposmod(float(d[key]) + 0.0625 * dir, 1.0)
				return d)
			return s)
		return
	if hmap_on():
		_hmap(dir)
		return
	var out = null
	if Input.is_key_pressed(KEY_R):
		out = _edit(s, func(w: CubeWorld): return w.rotate(s, dir))
	elif Input.is_key_pressed(KEY_F):
		out = _edit(s, func(w: CubeWorld): return w.push_face(s, dir))
	elif Input.is_key_pressed(KEY_Q):
		var cn: int = int(target.get("corner", 0))
		out = _edit(s, func(w: CubeWorld): return w.push_face(s, dir, cn))
	elif not corners.is_empty() and not sel.is_empty():
		var rect := corners.duplicate()
		out = _edit(s, func(w: CubeWorld): return w.push_corner_quads(s, rect, dir))
	elif not sel.is_empty():
		_wheel_pending += dir                            # (run at the end of the frame, with any other notches)
		return
	elif dir > 0:
		out = _edit(s, func(w: CubeWorld): return w.push(s))
	else:
		var tex := texture
		out = _edit(s, func(w: CubeWorld): return w.pull(s, tex))
	if out != null and not sel.is_empty():
		var keep_model = sel.get("model")
		sel = (out as Dictionary).duplicate()
		sel["model"] = keep_model if keep_model != null else model


## Run an edit on a selection's cube object (making a new object if it's the first cube): one undo step.
func _edit(s: Dictionary, fn: Callable):
	var m: CubeModelNode = s.get("model")
	var created := false
	if m == null or not is_instance_valid(m) or not m.is_inside_tree():
		m = CubeModelNode.new()
		models.add_child(m)
		created = true
	var w := m.world
	w.begin()
	var out = fn.call(w)
	var changed := w.commit()
	if created:
		if changed:
			_push_history({"t": "new", "m": m})
			_push_history({"t": "cubes", "m": m})
			if not sel.is_empty():
				sel["model"] = m
			say("A new cube object")
		else:
			models.remove_child(m)
			m.queue_free()
			return out
	elif changed:
		_push_history({"t": "cubes", "m": m})
	model = m
	return out


func _push_history(e: Dictionary) -> void:
	_history.append(e)
	if _history.size() > 400:
		_history.pop_front()
	_redo.clear()


func _texture_cycle() -> Array:
	var ids: Array = mru.duplicate()
	for e in MaterialLibrary.entries():
		if not e["id"] in ids:
			ids.append(e["id"])
	if not "" in ids:
		ids.append("")
	return ids


func _use_texture(id: String) -> void:
	texture = id
	mru.erase(id)
	mru.push_front(id)
	if mru.size() > 24:
		mru.pop_back()


func _apply_texture(id: String) -> void:
	_use_texture(id)
	var s := op_sel()
	if not s.is_empty():
		_edit(s, func(w: CubeWorld):
			w.set_texture(s, id, all_faces)
			return s)
	say("Texture: %s" % _tex_name(id))


## Y on its own: pick up the texture you aim at (Sauerbraten's gettex).
func _get_texture() -> void:
	var slot := _slot_here()
	if slot == "" and target.get("model") == null:
		return
	_use_texture(CubeWorld.slot_id(slot))
	say("Picked up: %s" % _tex_name(texture))


func _slot_here() -> String:
	var s := op_sel()
	var m = s.get("model")
	if s.is_empty() or m == null or not is_instance_valid(m):
		return ""
	return (m as CubeModelNode).world.slot_at(s)


func _hmap(dir: int) -> void:
	var m = target.get("model")
	if not target.get("hit", false) or m == null or target["sel"]["orient"] != 3:
		say("Heightmap: aim at the top of some cubes")
		return
	var lp: Vector3 = target["local"]
	var g := CubeWorld.size_of(grid_p)
	var center := Vector3i(roundi(lp.x / g) * g, 0, roundi(lp.z / g) * g)
	var b: Array = CubeWorld.BRUSHES[brush][1]
	var s: Dictionary = target["sel"]
	_edit(s, func(w: CubeWorld):
		w.hmap_edit(center, int(lp.y), grid_p, b, dir)
		return s)


func _paint() -> void:
	var m: CubeModelNode = _drag_from.get("model")
	if m == null or target.get("model") != m or not target["hit"]:
		return
	var n: int = m.world.paint_blend(target["local"], blend_radius / CubeWorld.TICK, blend_mode)
	if n == 0 and parse_layer_missing():
		say("Give the face a blend layer first (F3)")


func parse_layer_missing() -> bool:
	return CubeWorld.parse_slot(_slot_here())["l"] == ""


func flip() -> void:
	if not ent_sel.is_empty() and sel.is_empty():
		for o in ent_sel:
			var before: Dictionary = o.to_dict()
			o.rotate_by(180.0)
			_push_history({"t": "ent", "obj": o, "before": before, "after": o.to_dict()})
		return
	var s := op_sel()
	if s.is_empty():
		return
	_edit(s, func(w: CubeWorld):
		w.flip(s)
		return s)
	say("Flipped")


func copy() -> void:
	var s := op_sel()
	clip = {}
	if not s.is_empty() and s.get("model") != null and is_instance_valid(s["model"]):
		clip = (s["model"] as CubeModelNode).world.copy(s)
		clip["origin"] = _frame(s["model"]) * (Vector3(s["o"]) * CubeWorld.TICK)
	if not ent_sel.is_empty():
		clip["ents"] = editor._clip_of(ent_sel)
		if not clip.has("origin"):
			clip["origin"] = (ent_sel[0] as Node3D).center()
	if clip.is_empty():
		say("Nothing to copy here")
		return
	say("Copied %d cubes%s - aim somewhere and press V" % [(clip.get("cubes", []) as Array).size(),
		(" and %d entities" % ent_sel.size()) if not ent_sel.is_empty() else ""])


## V: paste into the selection, or with none, on top of the face you aim at.
func paste() -> void:
	var s := op_sel()
	if s.is_empty() or clip.is_empty():
		return
	if sel.is_empty() and target.get("hit", false):
		s = CubeWorld.moved(s, 1)
		s["model"] = target["model"]
	var dest: Vector3 = _frame(s.get("model")) * (Vector3(s["o"]) * CubeWorld.TICK)
	if clip.has("cubes"):
		var out = _edit(s, func(w: CubeWorld): return w.paste(s, clip))
		sel = (out as Dictionary).duplicate()
		sel["model"] = model
	if clip.has("ents"):
		var objs: Array = editor._paste(clip["ents"], dest - (clip["origin"] as Vector3), true)
		for o in objs:
			_push_history({"t": "ent_add", "obj": o, "clip": editor._clip_of([o])})
		ent_sel = objs
	say("Pasted")


func delete() -> void:
	if not ent_sel.is_empty():
		for o in ent_sel:
			_push_history({"t": "ent_del", "obj": o, "clip": editor._clip_of([o])})
			o.get_parent().remove_child(o)
			o.queue_free()
		say("Deleted %d" % ent_sel.size())
		ent_sel = []
		return
	var s := op_sel()
	if s.is_empty():
		return
	_edit(s, func(w: CubeWorld):
		w.delete(s)
		return s)


func undo() -> void:
	if _history.is_empty():
		say("Nothing to undo")
		return
	var e: Dictionary = _history.pop_back()
	_undo_entry(e, true)
	_redo.append(e)
	say("Undone")


func redo() -> void:
	if _redo.is_empty():
		say("Nothing to redo")
		return
	var e: Dictionary = _redo.pop_back()
	_undo_entry(e, false)
	_history.append(e)
	say("Redone")


func _undo_entry(e: Dictionary, back: bool) -> void:
	match e["t"]:
		"cubes":
			if is_instance_valid(e["m"]):
				if back:
					e["m"].world.undo()
				else:
					e["m"].world.redo()
		"new":
			var m: CubeModelNode = e["m"]
			if back and m.is_inside_tree():
				models.remove_child(m)
				if model == m:
					model = null
				sel = {}
			elif not back and not m.is_inside_tree():
				models.add_child(m)
		"ent":
			if is_instance_valid(e["obj"]):
				e["obj"].from_dict(e["before"] if back else e["after"])
		"ent_add", "ent_del":
			var remove: bool = (e["t"] == "ent_add") == back
			if remove:
				if is_instance_valid(e["obj"]) and e["obj"].is_inside_tree():
					ent_sel.erase(e["obj"])
					e["obj"].get_parent().remove_child(e["obj"])
					e["obj"].queue_free()
			else:
				var old = e["obj"]
				var objs: Array = editor._paste(e["clip"], Vector3.ZERO, true)
				if not objs.is_empty():
					for h in _history + _redo:          # later steps refer to the re-made object
						if h.get("obj") == old:
							h["obj"] = objs[0]
					e["obj"] = objs[0]


func goto_sel() -> void:
	var s := op_sel()
	if s.is_empty():
		return
	var g := CubeWorld.metres(s["p"])
	var xf := _frame(s.get("model"))
	var c := xf * ((Vector3(s["o"]) + Vector3(s["s"]) * CubeWorld.size_of(s["p"]) * 0.5) * CubeWorld.TICK)
	var n := (xf.basis * CubeWorld.orient_normal(s["orient"])).normalized()
	var size := Vector3(s["s"]).length() * g
	cam.global_position = c + n * (size + 4.0) + Vector3.UP * 0.01
	var f := (c - cam.global_position).normalized()
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))
	_apply_cam()


func _play_here() -> void:
	resume_after_play = true
	_leave()
	var at := Transform3D(Basis(Vector3.UP, yaw), cam.global_position)
	editor._play_from_build(at)


## Ctrl+P: a proper run from the map's start, as Play does in the editor; Esc comes back here.
func _play_from_start() -> void:
	resume_after_play = true
	_leave()
	editor._play_clicked()


# ------------------------------------------------------------------------------------------------ selections
func _in_sel(s: Dictionary) -> bool:
	if sel.is_empty() or s.get("model") != sel.get("model") or s["p"] != sel["p"]:
		return false
	var o: Vector3i = s["o"]
	var lo: Vector3i = sel["o"]
	var hi: Vector3i = lo + (sel["s"] as Vector3i) * CubeWorld.size_of(sel["p"])
	return o.x >= lo.x and o.y >= lo.y and o.z >= lo.z and o.x < hi.x and o.y < hi.y and o.z < hi.z


func _bounds(a: Dictionary, b: Dictionary) -> Dictionary:
	if a["p"] != b["p"] or a.get("model") != b.get("model"):
		return b.duplicate()
	var g := CubeWorld.size_of(a["p"])
	var lo: Vector3i = (a["o"] as Vector3i).min(b["o"])
	var hi: Vector3i = ((a["o"] as Vector3i) + (a["s"] as Vector3i) * g).max((b["o"] as Vector3i) + (b["s"] as Vector3i) * g)
	var out := CubeWorld.make_sel(lo, a["p"], a["orient"], (hi - lo) / g)
	out["model"] = a.get("model")
	return out


## Which half-cell square of the face the crosshair is on (counted in half cells along the face's two axes): each
## cube face is 4 squares, one per corner.
static func _quad_of(t: Dictionary) -> Vector2i:
	var s: Dictionary = t["sel"]
	var o: int = s["orient"]
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var g := CubeWorld.size_of(s["p"])
	var cell: Vector3i = s["o"]
	var lp: Vector3 = t["local"]
	var qa := clampi(floori(lp[a] * 2.0 / g), cell[a] * 2 / g, cell[a] * 2 / g + 1)
	var qb := clampi(floori(lp[b] * 2.0 / g), cell[b] * 2 / g, cell[b] * 2 / g + 1)
	return Vector2i(qa, qb)


## Middle drag: the cubes from the one you started on to the one you're on now, and the corners between the corner
## you started at and the one you're nearest. Only ever over cubes (it's for shaping what's there): aiming at empty
## space, another object or another side doesn't change it.
func _update_corner_drag() -> void:
	if not _on_cube(target) or not _on_cube(_drag_from) or target["sel"].get("model") != _drag_from["sel"].get("model") 			or target["sel"]["orient"] != _drag_from["sel"]["orient"] or target["sel"]["p"] != _drag_from["sel"]["p"]:
		return
	var q0 := _quad_of(_drag_from)
	var q1 := _quad_of(target)
	corners = [mini(q0.x, q1.x), maxi(q0.x, q1.x), mini(q0.y, q1.y), maxi(q0.y, q1.y)]
	sel = _bounds(_drag_from["sel"], target["sel"])
	sel["orient"] = _drag_from["sel"]["orient"]


static func _on_cube(t: Dictionary) -> bool:
	return not t.is_empty() and t.get("on_cube", false)


# ------------------------------------------------------------------------------------------------ moving cubes (editcut)
func _start_cut() -> void:
	var m: CubeModelNode = sel["model"]
	m.world.begin()
	_drag = "cut"
	_cut = {"model": m, "applied": Vector3i.ZERO, "start": _plane_cell(sel)}


## The cell (in the selection's object) where the crosshair crosses the selection's face plane.
func _plane_cell(s: Dictionary) -> Vector3i:
	var xf := _frame(s.get("model")).affine_inverse()
	var from := xf * cam.global_position
	var dir := (xf.basis * -cam.global_basis.z).normalized()
	var o: int = s["orient"]
	var d := o >> 1
	var g := CubeWorld.size_of(s["p"])
	var plane_t := float((s["o"] as Vector3i)[d] + (((s["s"] as Vector3i)[d]) * g if o & 1 else 0)) * CubeWorld.TICK
	if absf(dir[d]) < 1e-4:
		return _cut.get("start", Vector3i.ZERO)
	var t := (plane_t - from[d]) / dir[d]
	var p := (from + dir * maxf(t, 0.0)) / CubeWorld.TICK
	return Vector3i(floori(p.x / g) * g, floori(p.y / g) * g, floori(p.z / g) * g)


func _update_cut() -> void:
	var now := _plane_cell(sel)
	var delta: Vector3i = now - (_cut["start"] as Vector3i)
	delta[sel["orient"] >> 1] = 0
	var step: Vector3i = delta - (_cut["applied"] as Vector3i)
	if step == Vector3i.ZERO:
		return
	var m: CubeModelNode = _cut["model"]
	var keep = sel["model"]
	sel = m.world.move_cubes(sel, step)
	sel["model"] = keep
	_cut["applied"] = delta


# ------------------------------------------------------------------------------------------------ entities
func _entity_of(c: Object) -> Node3D:
	for key in ["light", "entity", "prop", "text"]:
		if c.has_meta(key):
			return c.get_meta(key)
	return null


func _select_ents_in_sel() -> void:
	var s := op_sel()
	if s.is_empty():
		return
	var xf := _frame(s.get("model"))
	var lo := Vector3(s["o"]) * CubeWorld.TICK
	var box := AABB(lo, Vector3(s["s"]) * CubeWorld.metres(s["p"]))
	ent_sel = []
	for root in [editor.lights_root, editor.entities_root, editor.props_root, editor.texts_root]:
		for o in root.get_children():
			if box.has_point(xf.affine_inverse() * (o as Node3D).center()):
				ent_sel.append(o)
	say("%d entities in the selection selected (C copies them with the cubes)" % ent_sel.size())


func _update_ent_drag() -> void:
	if ent_sel.is_empty():
		return
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var vertical := Input.is_key_pressed(KEY_SHIFT)
	var start: Vector3 = _ent_drag["start"]
	var plane := Plane(Vector3.UP, float(_ent_drag["plane_y"]))
	if vertical:
		var n := Vector3(dir.x, 0, dir.z).normalized()
		plane = Plane(n, n.dot(start))
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return
	var delta: Vector3 = (hit as Vector3) - Vector3(start.x, float(_ent_drag["plane_y"]) if not vertical else start.y, start.z)
	if not vertical:
		delta.y = 0.0
	else:
		delta = Vector3(0, delta.y, 0)
	if entsnap:
		delta = delta.snapped(Vector3.ONE * CubeWorld.metres(grid_p))
	for o in ent_sel:
		var before: Dictionary = _ent_drag["before"].get(o, {})
		if before.is_empty():
			continue
		o.from_dict(before)
		o.translate_by(delta)


## 1-4 + wheel: an entity's settings (Sauerbraten's entity attributes).
func _ent_prop(idx: int, dir: int) -> void:
	var lines := PackedStringArray()
	for o in ent_sel:
		var before: Dictionary = o.to_dict()
		var d: Dictionary = before.duplicate(true)
		var what := ""
		if o is LightNode:
			match idx:
				1:
					d["range"] = maxf(float(d["range"]) + dir * 1.0, 1.0)
					what = "reach %.0f m" % d["range"]
				_:
					var c := Color.html(d["color"])
					c[idx - 2] = clampf(c[idx - 2] + dir * 16.0 / 255.0, 0.0, 1.0)
					d["color"] = c.to_html(false)
					what = "colour #%s" % d["color"]
		elif o is EntityNode:
			match idx:
				1:
					d["yaw"] = wrapf(float(d["yaw"]) + dir * 15.0, -180.0, 180.0)
					what = "facing %.0f°" % d["yaw"]
				2, 3, 4:
					var sz: Array = d["size"]
					var axis: int = [0, 2, 1][idx - 2]
					sz[axis] = maxf(float(sz[axis]) + dir * 1.0, 1.0)
					what = "size %.0f x %.0f x %.0f m" % [sz[0], sz[1], sz[2]]
			if o.kind == "booster" and idx == 4:
				d["strength"] = maxf(float(d.get("strength", 1000.0)) + dir * 50.0, 0.0)
				what = "push %.0f u/s" % d["strength"]
			if o.kind in ["stage", "teleport"] and idx == 4:
				d["number"] = maxi(int(d.get("number", 2)) + dir, 1)
				what = "stage %d" % d["number"]
		elif o is PropNode:
			match idx:
				1:
					d["yaw"] = wrapf(float(d["yaw"]) + dir * 15.0, -180.0, 180.0)
					what = "facing %.0f°" % d["yaw"]
				2:
					d["size"] = maxf(float(d["size"]) * (1.1 if dir > 0 else 1.0 / 1.1), 0.01)
					what = "size x%.2f" % d["size"]
		elif o is TextNode:
			match idx:
				1:
					d["yaw"] = wrapf(float(d["yaw"]) + dir * 15.0, -180.0, 180.0)
					what = "facing %.0f°" % d["yaw"]
				2:
					d["height"] = maxf(float(d["height"]) + dir * 0.25, 0.25)
					what = "text size %.2f m" % d["height"]
				3:
					d["depth"] = maxf(float(d["depth"]) + dir * 0.1, 0.05)
					what = "depth %.2f m" % d["depth"]
		if what == "":
			continue
		o.from_dict(d)
		_push_history({"t": "ent", "obj": o, "before": before, "after": o.to_dict()})
		lines.append("%s: %s" % [o.label(), what])
	if not lines.is_empty():
		say(", ".join(lines))


func _open_place_menu() -> void:
	_menu.clear()
	_menu.set_meta("kind", "place")
	var items := [["Light", 100], ["Spot light", 101], ["Start platform", 102], ["Finish platform", 103], ["Stage plate", 104],
		["Teleport", 105], ["Kill zone", 106], ["Booster", 107], ["Text", 108]]
	for it in items:
		_menu.add_item(it[0], it[1])
	_show_menu()


func _place(id: int) -> void:
	var at: Vector3 = cam.global_position - cam.global_basis.z * 6.0
	var n := cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 600.0)
	q.collision_mask = 1
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		at = hit["position"]
		n = hit["normal"]
	var o: Node3D
	match id:
		100, 101:
			var l := LightNode.new()
			editor.lights_root.add_child(l)
			var p := at + n * 1.5
			l.from_dict({"kind": "point" if id == 100 else "spot", "position": [p.x, p.y, p.z]})
			o = l
		102, 103, 104, 105, 106, 107:
			var kind: String = ["start", "finish", "stage", "teleport", "kill", "booster"][id - 102]
			var e := EntityNode.create(kind)
			editor.entities_root.add_child(e)
			e.position = at + (Vector3.UP * e.size.y * 0.5 if e.is_volume() else Vector3.ZERO)
			e.yaw = rad_to_deg(yaw)
			e.rebuild()
			o = e
		108:
			var t := TextNode.new()
			editor.texts_root.add_child(t)
			var z := n.normalized()
			var x := Vector3.UP.cross(z)
			if x.length() < 0.1:
				x = Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z).cross(Vector3.UP)
			x = x.normalized()
			var eu := Basis(x, z.cross(x).normalized(), z).get_euler(EULER_ORDER_YXZ)
			var p := at + z * 0.005
			t.from_dict({"text": "SURF", "position": [p.x, p.y, p.z], "pitch": rad_to_deg(eu.x), "yaw": rad_to_deg(eu.y), "roll": rad_to_deg(eu.z)})
			o = t
	if o:
		ent_sel = [o]
		_push_history({"t": "ent_add", "obj": o, "clip": editor._clip_of([o])})
		say("%s placed - 1-4 + wheel change it, drag to move it" % o.label())


# ------------------------------------------------------------------------------------------------ menus and panels
func _show_menu() -> void:
	_ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.reset_size()
	_menu.popup_centered()


func _ui_closed() -> void:
	if not active:
		return
	_ui_open = _tex_panel.visible
	if not _ui_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_commands() -> void:
	_menu.clear()
	_menu.set_meta("kind", "commands")
	_menu.add_separator("Fill the selection with")
	for i in CubeWorld.MATERIALS.size():
		var m: String = CubeWorld.MATERIALS[i]
		_menu.add_item(("air (clear the material)" if m == "air" else CubeWorld.MATERIAL_INFO[m]), i)
	_menu.add_separator("Textures")
	_menu.add_item("Replace the texture you aim at, everywhere, with the current one", 50)
	_menu.add_item("...the same, just in the selection", 51)
	_menu.add_item("Reset texture settings of the selected faces (vreset)", 52)
	_menu.add_separator("Selection")
	_menu.add_item("Select the entities inside the selection (Keypad Enter)", 60)
	_menu.add_item("Go to the selection (J)", 61)
	_menu.add_item("Start a new cube object (N)", 62)
	_show_menu()


func _menu_pressed(id: int) -> void:
	if _menu.get_meta("kind", "") == "place":
		_place(id)
		return
	run_command(id)


## A command from the T menu (also callable directly, for tests).
func run_command(id: int) -> void:
	var s := op_sel()
	if id < CubeWorld.MATERIALS.size():
		if s.is_empty():
			return
		var mat: String = CubeWorld.MATERIALS[id]
		_edit(s, func(w: CubeWorld):
			w.set_material(s, mat)
			return s)
		say("Material: %s" % mat)
		return
	match id:
		50, 51:
			var old := CubeWorld.slot_id(_slot_here())
			var n := 0
			for m in models.get_children():
				if id == 51 and m != s.get("model"):
					continue
				var w: CubeWorld = m.world
				w.begin()
				n += w.replace_texture(old, texture, s if id == 51 else {})
				if w.commit():
					_push_history({"t": "cubes", "m": m})
			say("Replaced %s with %s on %d faces" % [_tex_name(old), _tex_name(texture), n])
		52:
			if not s.is_empty():
				_edit(s, func(w: CubeWorld):
					w.set_slot_param(s, all_faces, func(d: Dictionary) -> Dictionary:
						var keep: String = d["id"]
						var out := CubeWorld.SLOT_DEFAULTS.duplicate()
						out["id"] = keep
						return out)
					return s)
		60: _select_ents_in_sel()
		61: goto_sel()
		62:
			model = null
			sel = {}


func _open_picker(cb: Callable) -> void:
	_ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._open_picker(cb)
	var picker: Window = editor._picker
	if not picker.popup_hide.is_connected(_ui_closed):
		picker.popup_hide.connect(_ui_closed)


## F3: Sauerbraten's texture settings (vscale, vrotate, voffset, vscroll, vcolor, valpha, vlayer) for the selected faces.
func _build_tex_panel() -> void:
	_tex_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.11, 0.14, 0.95)
	bg.set_content_margin_all(12)
	bg.set_corner_radius_all(8)
	_tex_panel.add_theme_stylebox_override("panel", bg)
	_tex_panel.visible = false
	_hud.add_child(_tex_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	_tex_panel.add_child(box)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 16)
	box.add_child(head)
	_tex_fields["head"] = head
	var pick := Button.new()
	pick.text = "Texture…"
	pick.pressed.connect(func(): _open_picker(func(id):
		_apply_texture(id)
		_ui_open = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_tex_panel()))
	box.add_child(pick)
	for spec in [["s", "Scale", 0.25, 8.0, 0.05], ["u", "Shift across", 0.0, 1.0, 0.01], ["v", "Shift up", 0.0, 1.0, 0.01],
			["su", "Scroll across (per second)", -2.0, 2.0, 0.05], ["sv", "Scroll up (per second)", -2.0, 2.0, 0.05],
			["a", "See-through (1 = solid)", 0.05, 1.0, 0.05]]:
		var l := Label.new()
		l.text = spec[1]
		box.add_child(l)
		var sl := HSlider.new()
		sl.min_value = spec[2]
		sl.max_value = spec[3]
		sl.step = spec[4]
		var key: String = spec[0]
		sl.value_changed.connect(func(v): _tex_param(key, v))
		box.add_child(sl)
		_tex_fields[key] = sl
	var rot := OptionButton.new()
	for t in ["Not turned", "Turned 90°", "Turned 180°", "Turned 270°", "Flipped across", "Flipped up"]:
		rot.add_item(t)
	rot.item_selected.connect(func(i): _tex_param("r", i))
	box.add_child(rot)
	_tex_fields["r"] = rot
	var col := ColorPickerButton.new()
	col.text = "Colour"
	col.custom_minimum_size = Vector2(0, 28)
	col.color_changed.connect(func(c): _tex_param("c", c.to_html(false)))
	box.add_child(col)
	_tex_fields["c"] = col
	var lrow := HBoxContainer.new()
	box.add_child(lrow)
	var layer := Button.new()
	layer.text = "Blend layer…"
	layer.pressed.connect(func(): _open_picker(func(id):
		_tex_param("l", id)
		_ui_open = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_tex_panel()))
	lrow.add_child(layer)
	var nolayer := Button.new()
	nolayer.text = "No layer"
	nolayer.pressed.connect(func(): _tex_param("l", ""); _refresh_tex_panel())
	lrow.add_child(nolayer)
	var allf := CheckButton.new()
	allf.text = "All faces of the selected cubes (0)"
	allf.toggled.connect(func(on): all_faces = on)
	box.add_child(allf)
	_tex_fields["all"] = allf
	var close := Button.new()
	close.text = "Done (F3)"
	close.pressed.connect(_close_tex_panel)
	box.add_child(close)


func _open_tex_panel() -> void:
	if op_sel().is_empty():
		say("Aim at a face (or select some) first")
		return
	_tex_panel.visible = true
	_ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_tex_panel()


func _close_tex_panel() -> void:
	_tex_panel.visible = false
	_ui_closed()


func _refresh_tex_panel() -> void:
	_tex_updating = true
	var d := CubeWorld.parse_slot(_slot_here())
	(_tex_fields["head"] as Label).text = "Texture: %s%s" % [_tex_name(d["id"]), ("   (layer: %s)" % _tex_name(d["l"])) if d["l"] != "" else ""]
	for k in ["s", "u", "v", "su", "sv", "a"]:
		(_tex_fields[k] as HSlider).value = float(d[k])
	(_tex_fields["r"] as OptionButton).select(int(d["r"]))
	(_tex_fields["c"] as ColorPickerButton).color = Color.html(d["c"])
	(_tex_fields["all"] as CheckButton).set_pressed_no_signal(all_faces)
	_tex_updating = false


func _tex_param(key: String, value) -> void:
	if _tex_updating:
		return
	var s := op_sel()
	if s.is_empty():
		return
	_edit(s, func(w: CubeWorld):
		w.set_slot_param(s, all_faces, func(d: Dictionary) -> Dictionary:
			d[key] = value
			return d)
		return s)


static func _tex_name(id: String) -> String:
	return MaterialLibrary.display_name(id) if id != "" else "plain (grid)"


static func _slot_text(slot: String) -> String:
	var d := CubeWorld.parse_slot(slot)
	return _tex_name(d["id"]) + ("" if not "|" in slot else "  (" + slot.get_slice("|", 1) + ")")


static func _metres_text(m: float) -> String:
	return ("%d m" % roundi(m)) if m >= 1.0 else ("%s m" % str(m))


# ------------------------------------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	_flush_wheel()
	if not active:
		return
	if not _ui_open:
		var move := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): move -= cam.global_basis.z
		if Input.is_key_pressed(KEY_S): move += cam.global_basis.z
		if Input.is_key_pressed(KEY_A): move -= cam.global_basis.x
		if Input.is_key_pressed(KEY_D): move += cam.global_basis.x
		if move != Vector3.ZERO and _drag != "cut":
			cam.global_position += move.normalized() * speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0) * delta
	update_target()
	match _drag:
		"select":
			if not target.is_empty():
				sel = _bounds(_drag_from, target["sel"])
				sel["orient"] = _drag_from["orient"]
		"corners":
			_update_corner_drag()
		"cut":
			_update_cut()
		"entity":
			_update_ent_drag()
		"paint":
			_paint_time -= delta
			if _paint_time <= 0.0:
				_paint_time = 0.05
				_paint()
	_draw()
	_layout_hud()
	_msg_time -= delta
	_msg.visible = _msg_time > 0.0
	var mode := ""
	if hmap_on():
		mode = "  ·  HEIGHTMAP (%s)" % CubeWorld.BRUSHES[brush][0]
	if blend_mode > 0:
		mode += "  ·  BLEND PAINT %d (%.1f m)" % [blend_mode, blend_radius]
	var size_txt := ""
	if not sel.is_empty():
		var s: Vector3i = sel["s"]
		size_txt = "  ·  selection %d x %d x %d%s" % [s.x, s.y, s.z, " (corners)" if not corners.is_empty() else ""]
	if not ent_sel.is_empty():
		size_txt += "  ·  %s selected" % (ent_sel[0].label() if ent_sel.size() == 1 else "%d entities" % ent_sel.size())
	var obj := "new object" if model == null or not is_instance_valid(model) or not model.is_inside_tree() else \
		String(model.get_meta("name", "cube object %d" % (model.get_index() + 1)))
	_info.text = "BUILD  ·  %s  ·  grid %s  ·  texture: %s%s%s%s  ·  F1 keys  ·  E editor" % [obj,
		_metres_text(CubeWorld.metres(grid_p)), _tex_name(texture), " (all faces)" if all_faces else "", mode, size_txt]


## Work out what the crosshair is on: a cube face (snapped to the grid, in the cube object's own space), an entity,
## or a spot in the air in front of you.
func update_target() -> void:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0)
	q.collision_mask = 1
	if _drag == "entity":
		var ex := []
		for o in ent_sel:
			for c in o.get_children():
				if c is CollisionObject3D:
					ex.append(c.get_rid())
		q.exclude = ex
	var hit := space.intersect_ray(q)
	var qe := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0)
	qe.collision_mask = 1 | PICK_LAYER
	var ehit := space.intersect_ray(qe)
	var ent: Node3D = null
	if not ehit.is_empty():
		ent = _entity_of(ehit["collider"])
	var hm: CubeModelNode = null
	if not hit.is_empty() and hit["collider"].has_meta("cube_model"):
		hm = hit["collider"].get_meta("cube_model")
	var fm = hm if hm != null else (model if model != null and is_instance_valid(model) and model.is_inside_tree() else null)
	var xf := _frame(fm)
	var inv := xf.affine_inverse()
	var p := grid_p
	var g := CubeWorld.size_of(p)
	var orient: int
	var cell: Vector3i
	var corner := 0
	var point: Vector3
	var lp: Vector3
	if not hit.is_empty():
		point = hit["position"]
		lp = inv * point
		var n := (inv.basis * (hit["normal"] as Vector3)).normalized()
		orient = CubeWorld.orient_of(n)
		var behind := (lp - n * 0.01) / CubeWorld.TICK
		if hm != null and Input.is_key_pressed(KEY_CTRL):        # passthrough: the cube itself, at its own size
			var lk = hm.world.leaf_at(behind)
			if lk != null:
				p = lk.w
				g = CubeWorld.size_of(p)
		cell = Vector3i(floori(behind.x / g) * g, floori(behind.y / g) * g, floori(behind.z / g) * g)
		var local := (lp / CubeWorld.TICK - Vector3(cell)) / float(g) * 8.0
		var best := INF
		var quad := CubeWorld.face_corners(orient)
		for i in 4:
			var dd := CubeWorld.corner(CubeWorld.FULL, quad[i]).distance_to(local)
			if dd < best:
				best = dd
				corner = i
	else:
		var gm := CubeWorld.metres(p)
		point = from + dir * clampf(gm * 6.0, 3.0, 40.0)
		lp = inv * point
		orient = CubeWorld.orient_of(-(inv.basis * dir))
		var t := lp / CubeWorld.TICK
		var c := Vector3i(floori(t.x / g) * g, floori(t.y / g) * g, floori(t.z / g) * g)
		cell = c - CubeWorld.orient_step(orient) * g
	# a cell with anything in it (part of a cube, a material) counts as a whole block: aim at the first one along the
	# line of sight, on the face you look into it through - even where its own faces have been pushed in
	var on_cube := hm != null
	var hit_any := not hit.is_empty()
	if fm != null and not (hm != null and Input.is_key_pressed(KEY_CTRL)):
		var max_d := from.distance_to(hit["position"]) + CubeWorld.metres(p) * 2.0 if not hit.is_empty() else 600.0
		var found := _first_occupied(fm, from, dir, max_d, p)
		if not found.is_empty():
			cell = found["cell"]
			orient = found["orient"]
			lp = found["point"]
			point = xf * lp
			on_cube = true
			hit_any = true
			var local := (lp / CubeWorld.TICK - Vector3(cell)) / float(g) * 8.0
			var best := INF
			var quad := CubeWorld.face_corners(orient)
			for i in 4:
				var dd := CubeWorld.corner(CubeWorld.FULL, quad[i]).distance_to(local)
				if dd < best:
					best = dd
					corner = i
	var ts := CubeWorld.make_sel(cell, p, orient)
	ts["model"] = fm
	var ent_first := ent != null and (hit.is_empty() or (ehit["position"] as Vector3).distance_to(from) <= from.distance_to(hit["position"]) + 0.05)
	target = {"model": fm, "sel": ts, "corner": corner, "hit": hit_any, "point": point, "on_cube": on_cube,
		"local": lp / CubeWorld.TICK, "entity": ent if ent_first else null}


## Walk the line of sight through a cube object's grid (cells of grid power p) and return the first cell with
## anything in it: {cell (ticks), orient (the face it was entered through), point (where, metres, object space)}.
func _first_occupied(m: CubeModelNode, from_w: Vector3, dir_w: Vector3, max_d: float, p: int) -> Dictionary:
	var w: CubeWorld = m.world
	if w.count() == 0 and w.mats.is_empty():
		return {}
	var inv := m.global_transform.affine_inverse()
	var o := (inv * from_w) / CubeWorld.TICK
	var d := (inv.basis * dir_w).normalized()
	var g := float(CubeWorld.size_of(p))
	var bb := w.bounds()
	var box := AABB(bb.position / CubeWorld.TICK - Vector3.ONE * g, bb.size / CubeWorld.TICK + Vector3.ONE * 2.0 * g)
	var t0 := 0.0
	var t1 := max_d / CubeWorld.TICK
	for i in 3:                                          # only the part of the ray inside the object
		if absf(d[i]) < 1e-9:
			if o[i] < box.position[i] or o[i] > box.end[i]:
				return {}
		else:
			var ta := (box.position[i] - o[i]) / d[i]
			var tb := (box.end[i] - o[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return {}
	var start := o + d * (t0 + 1e-4)
	var cell := Vector3i(floori(start.x / g), floori(start.y / g), floori(start.z / g))
	var step := Vector3i(signi(int(signf(d.x))), signi(int(signf(d.y))), signi(int(signf(d.z))))
	var tmax := Vector3(INF, INF, INF)
	var tdelta := Vector3(INF, INF, INF)
	for i in 3:
		if absf(d[i]) > 1e-9:
			var edge := float(cell[i] + (1 if step[i] > 0 else 0)) * g
			tmax[i] = t0 + (edge - start[i]) / d[i]
			tdelta[i] = g / absf(d[i])
	var t := t0
	var axis := -1
	var inside := false                                  # the camera is inside cubes: aim at the face you'd leave by
	var last := Vector3i.ZERO
	for n in 6000:
		if t > t1:
			break
		var ct := cell * int(g)
		var occ := w.cell_occupied(ct, p)
		if n == 0 and occ and t0 <= 0.0:
			inside = true
		if inside:
			if not occ:                                  # out in the open: the last cube's side facing this way
				return {"cell": last, "orient": axis * 2 + (1 if step[axis] > 0 else 0), "point": (o + d * t) * CubeWorld.TICK,
					"inside": true}
			last = ct
		elif occ:
			var orient := axis * 2 + (1 if step[axis] < 0 else 0) if axis >= 0 else CubeWorld.orient_of(-d)
			return {"cell": ct, "orient": orient, "point": (o + d * t) * CubeWorld.TICK}
		axis = 0 if tmax.x <= tmax.y and tmax.x <= tmax.z else (1 if tmax.y <= tmax.z else 2)
		t = tmax[axis]
		cell[axis] += step[axis]
		tmax[axis] += tdelta[axis]
	return {}


func _layout_hud() -> void:
	var vp := get_viewport().get_visible_rect().size
	_cross.position = vp * 0.5 - _cross.size * 0.5
	_info.position = Vector2(16, vp.y - _info.size.y - 14)
	_help.position = Vector2(vp.x - _help.size.x - 16, 16)
	_msg.position = Vector2(vp.x * 0.5 - _msg.size.x * 0.5, vp.y - 120)
	var notes := PackedStringArray()
	if hmap_on():
		notes.append("HEIGHTMAP MODE - the wheel sculpts terrain (%s)" % ("hold Alt" if not hmap else "H to turn it off"))
	if blend_mode > 0:
		notes.append("BLEND PAINTING - left mouse paints (keypad 0 to stop)")
	_banner.text = "
".join(notes)
	_banner.visible = not notes.is_empty()
	_banner.reset_size()
	_banner.position = Vector2(vp.x * 0.5 - _banner.size.x * 0.5, 18)
	_tex_panel.position = Vector2(24, 24)


func _draw() -> void:
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	if not target.is_empty():
		var ts: Dictionary = target["sel"]
		var xf := _frame(ts.get("model"))
		if target.get("entity") != null and _drag == "":
			for seg in (target["entity"] as Node3D).outline_lines():
				for i in range(0, seg.size() - 1):
					_line(seg[i], seg[i + 1], Color(1.0, 0.6, 0.2, 0.6))
		elif not (target["hit"] and _true_face(xf, ts, Color(1.0, 0.85, 0.2))):
			_face_rect(xf, ts, Color(1.0, 0.85, 0.2) if target["hit"] else Color(1.0, 0.85, 0.2, 0.5))
		if Input.is_key_pressed(KEY_Q) or _drag == "corners":
			var g := CubeWorld.metres(ts["p"])
			var o := Vector3(ts["o"]) * CubeWorld.TICK
			var cp := xf * (o + CubeWorld.corner(CubeWorld.FULL, CubeWorld.face_corners(ts["orient"])[target["corner"]]) / 8.0 * g)
			for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				_line(cp - ax * g * 0.2, cp + ax * g * 0.2, Color(1, 0.3, 0.2))
		if hmap_on() and target["hit"] and ts["orient"] == 3:
			var b: Array = CubeWorld.BRUSHES[brush][1]
			var lp: Vector3 = target["local"]
			var gt := CubeWorld.size_of(grid_p)
			var c := Vector3(roundi(lp.x / gt) * gt, lp.y, roundi(lp.z / gt) * gt) * CubeWorld.TICK
			var n := b.size() if b.size() > 0 else 5
			for i in n:
				for j in n:
					if b.size() > 0 and b[i][j] == 0:
						continue
					var pt := xf * (c + Vector3((i - n / 2) * gt, 0, (j - n / 2) * gt) * CubeWorld.TICK)
					var hgt := CubeWorld.metres(grid_p) * 0.3 * (1 + (int(b[i][j]) if b.size() > 0 else 1))
					_line(pt, pt + Vector3.UP * hgt, Color(0.4, 1.0, 0.5))
		if blend_mode > 0 and target["hit"]:
			var pc: Vector3 = target["point"]
			for i in 24:
				var a0 := TAU * i / 24.0
				var a1 := TAU * (i + 1) / 24.0
				_line(pc + Vector3(cos(a0), 0.02, sin(a0)) * blend_radius, pc + Vector3(cos(a1), 0.02, sin(a1)) * blend_radius, Color(1, 0.4, 0.9))
	if not sel.is_empty():
		var xf := _frame(sel.get("model"))
		var g := CubeWorld.metres(sel["p"])
		var lo := Vector3(sel["o"]) * CubeWorld.TICK
		var hi := lo + Vector3(sel["s"]) * g
		_box(xf, lo, hi, Color(1, 1, 1, 0.55))
		var layer := sel.duplicate()
		var s: Vector3i = sel["s"]
		var d: int = sel["orient"] >> 1
		if sel["orient"] & 1:
			layer["o"] = (sel["o"] as Vector3i) + CubeWorld.orient_step(sel["orient"]) * CubeWorld.size_of(sel["p"]) * (s[d] - 1)
		s[d] = 1
		layer["s"] = s
		_face_rect(xf, layer, Color(0.25, 0.75, 1.0), Color(0.2, 0.6, 1.0, 0.25))   # the selected face: filled blue
		if not corners.is_empty():
			_corner_grid(xf)
	for e in ent_sel:
		if is_instance_valid(e):
			for seg in (e as Node3D).outline_lines():
				for i in range(0, seg.size() - 1):
					_line(seg[i], seg[i + 1], Color(1.0, 0.55, 0.1))
	_line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)
	_im.surface_end()
	last_fill_count = _fills.filter(func(f): return f.size() == 4).size()   # (corner squares; the face fill has a colour)
	if not _fills.is_empty():                            # the selected corner squares, filled
		_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in _fills:
			var fc: Color = f[4] if f.size() > 4 else Color(0.25, 0.6, 1.0, 0.38)
			for i in [0, 1, 2, 0, 2, 3]:
				_im.surface_set_color(fc)
				_im.surface_add_vertex(f[i])
		_im.surface_end()
	_fills.clear()


var _fills: Array = []                   ## quads to fill this frame (4 points each)
var last_fill_count := 0                 ## how many corner squares were filled in the last frame


## Corner selection: a half-size grid over the selected cubes' faces (on each cell's side, as if the cell were full),
## with the selected squares - one per corner - filled in blue.
func _corner_grid(xf: Transform3D) -> void:
	var m = sel.get("model")
	if m == null or not is_instance_valid(m):
		return
	var w: CubeWorld = (m as CubeModelNode).world
	var o: int = sel["orient"]
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var p: int = sel["p"]
	var g := CubeWorld.size_of(p)
	var half := g / 2
	var s: Vector3i = sel["s"]
	for i in s[a]:
		for j in s[b]:
			for depth in s[d]:                           # the outermost cell with something in it, like the push
				var c := Vector3i.ZERO
				c[a] = i
				c[b] = j
				c[d] = (s[d] - 1 - depth) if o & 1 else depth
				var cell: Vector3i = (sel["o"] as Vector3i) + c * g
				if not w.cell_occupied(cell, p):
					continue
				var plane := float(cell[d] + (g if o & 1 else 0)) * CubeWorld.TICK + (0.012 if o & 1 else -0.012)
				for qa in 2:
					for qb in 2:
						var sa := cell[a] * 2 / g + qa
						var sb := cell[b] * 2 / g + qb
						var pts := []
						for ab in [[0, 0], [1, 0], [1, 1], [0, 1]]:
							var v := Vector3.ZERO
							v[d] = plane
							v[a] = float(cell[a] + qa * half + ab[0] * half) * CubeWorld.TICK
							v[b] = float(cell[b] + qb * half + ab[1] * half) * CubeWorld.TICK
							pts.append(xf * v)
						var on: bool = sa >= corners[0] and sa <= corners[1] and sb >= corners[2] and sb <= corners[3]
						for k in 4:
							_line(pts[k], pts[(k + 1) % 4], Color(0.35, 0.7, 1.0, 1.0 if on else 0.45))
						if on:
							_fills.append(pts)
				break


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_add_vertex(a)
	_im.surface_set_color(c)
	_im.surface_add_vertex(b)


func _box(xf: Transform3D, lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := []
	for i in 8:
		p.append(xf * Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line(p[e[0]], p[e[1]], c)


## The aimed face as the cubes really are there (pushed in, sloped, cut), not the cell's full square. False when it
## can't be drawn that way (empty cell, a bigger cube around it) - then the cell's square is drawn instead.
func _true_face(xf: Transform3D, s: Dictionary, c: Color) -> bool:
	var m = s.get("model")
	if m == null or not is_instance_valid(m) or s.get("s", Vector3i.ONE) != Vector3i.ONE:
		return false
	var w: CubeWorld = (m as CubeModelNode).world
	var p: int = s["p"]
	var g := CubeWorld.size_of(p)
	var o: int = s["orient"]
	var keys := w.leaves_in(s["o"], Vector3i(g, g, g))
	if keys.is_empty():
		return false
	var lift := Vector3(CubeWorld.orient_step(o)) * 0.01   # (just off the face, so it isn't hidden in it)
	var drew := false
	for k in keys:
		if k.w > p:
			return false
		var v: Array = w.leaves[k]
		var origin := Vector3(k.x, k.y, k.z) * CubeWorld.TICK
		var unit := CubeWorld.metres(k.w) / 8.0
		var polys := []
		var cut: Array = v[3] if v.size() > 3 else []
		if not cut.is_empty():
			for f in CubeWorld.cut_faces(cut):
				if int(f[0]) == o:
					polys.append(Array(f[2]))
		else:
			var poly := []
			for n in CubeWorld.face_corners(o):
				poly.append(CubeWorld.corner(v[0], n))
			polys.append(poly)
		for poly in polys:
			var pts := []
			for q in poly:
				var wp: Vector3 = xf * (origin + (q as Vector3) * unit + lift)
				if pts.is_empty() or not (pts[pts.size() - 1] as Vector3).is_equal_approx(wp):
					pts.append(wp)
			if pts.size() < 3:
				continue                                 # (squashed flat: nothing to show on this side)
			for i in pts.size():
				_line(pts[i], pts[(i + 1) % pts.size()], c)
			drew = true
	return drew


func _face_rect(xf: Transform3D, s: Dictionary, c: Color, fill := Color(0, 0, 0, 0)) -> void:
	var o: int = s["orient"]
	var d := o >> 1
	var g := CubeWorld.metres(s["p"])
	var lo := Vector3(s["o"]) * CubeWorld.TICK
	var hi := lo + Vector3(s["s"]) * g
	var plane := hi[d] if o & 1 else lo[d]
	plane += 0.01 if o & 1 else -0.01
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var pts := []
	for ab in [[0, 0], [1, 0], [1, 1], [0, 1]]:
		var v := Vector3.ZERO
		v[d] = plane
		v[a] = hi[a] if ab[0] else lo[a]
		v[b] = hi[b] if ab[1] else lo[b]
		pts.append(xf * v)
	for i in 4:
		_line(pts[i], pts[(i + 1) % 4], c)
	if fill.a > 0.0:                                     # filled, with a second edge just inside: reads as a thick line
		var mid: Vector3 = (pts[0] + pts[2]) * 0.5
		var inset := minf(g * 0.04, 0.05)
		var inner := []
		for p in pts:
			inner.append(p + ((mid - p) as Vector3).normalized() * inset)
		for i in 4:
			_line(inner[i], inner[(i + 1) % 4], c)
		_fills.append(pts + [fill])
