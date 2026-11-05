class_name BuildMode
extends Node
## Build mode: walk (fly) around the map in first person and build with cubes in real time, the way Cube 2:
## Sauerbraten's editor works - point at a face, roll the mouse wheel to pull cubes out of it or push them in, hold
## a key while rolling to push faces or corners in 1/8 steps (slopes), change the grid, texture, rotate, flip, copy.
## Same keys as Sauerbraten where it can; E (or Esc) goes back to the editor.

signal stopped

const HELP := [
	["Look", "mouse"], ["Fly", "W A S D   (Shift: fast)"], ["", ""],
	["Mouse wheel", "pull cubes out / push them in"],
	["F + wheel", "push / pull the face 1/8 at a time"],
	["Q + wheel", "push / pull the corner you aim at"],
	["G + wheel", "grid size (smaller = finer)"],
	["Y + wheel", "change texture"], ["F2", "pick a texture"],
	["0", "texture all faces on / off"],
	["R + wheel", "rotate the selection"], ["X", "flip the selection"], ["", ""],
	["Left click (drag)", "select faces"], ["Right click", "extend the selection to here"],
	["Space", "drop the selection"], ["C / V", "copy / paste"], ["Delete", "delete the selection"],
	["Z or U  /  I", "undo / redo"], ["", ""],
	["E or Esc", "back to the editor"], ["F1", "hide this"],
]

var active := false
var editor: Node
var cubes: CubeWorldNode
var cam := Camera3D.new()
var yaw := 0.0
var pitch := 0.0
var speed := 10.0
var grid_p := 0                          ## grid power: 0 = 1 m cubes
var sel := {}                            ## the selection (empty = none: edits use the face you aim at)
var target := {}                         ## what the crosshair is on: {sel, corner, hit}
var texture := ""                        ## texture for new faces and for Y / F2
var all_faces := false
var clip := {}
var _dragging := false
var _drag_from := {}
var _ui_open := false
var _hud := CanvasLayer.new()
var _info := Label.new()
var _help := PanelContainer.new()
var _msg := Label.new()
var _msg_time := 0.0
var _cross: Label
var _lines := MeshInstance3D.new()
var _im := ImmediateMesh.new()


func setup(ed: Node, cube_node: CubeWorldNode) -> void:
	editor = ed
	cubes = cube_node


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
	_lines.material_override = m
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lines.visible = false
	add_child(_lines)
	_hud.layer = 6
	_hud.visible = false
	add_child(_hud)
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 26)
	cross.add_theme_color_override("font_outline_color", Color.BLACK)
	cross.add_theme_constant_override("outline_size", 6)
	_hud.add_child(cross)
	_cross = cross
	for l in [_info, _msg]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		_hud.add_child(l)
	_info.add_theme_font_size_override("font_size", 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
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
	var tip := Label.new()
	tip.text = "Aim at a face: the yellow square is where you build."
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hb.add_child(tip)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 0)
	hb.add_child(grid)
	for row in HELP:
		for i in 2:
			var l := Label.new()
			l.text = row[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_constant_override("line_spacing", 0)
			if i == 0:
				l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
			grid.add_child(l)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.custom_minimum_size = Vector2(800, 0)
	_msg.add_theme_font_size_override("font_size", 20)


func start(from: Transform3D) -> void:
	if active:
		return
	active = true
	cam.global_position = from.origin
	var f := -from.basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = asin(clampf(f.y, -1.0, 1.0))
	_apply_cam()
	cam.current = true
	_hud.visible = true
	_lines.visible = true
	sel = {}
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	say("Build mode. Aim at something and roll the mouse wheel. F1 shows the keys.")


func stop() -> void:
	if not active:
		return
	active = false
	_dragging = false
	cam.clear_current(false)                             # (don't hand the main view to another camera)
	_hud.visible = false
	_lines.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stopped.emit()


func say(t: String) -> void:
	_msg.text = t
	_msg_time = 3.5


func _apply_cam() -> void:
	cam.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


# ------------------------------------------------------------------------------------------------ input
func _input(event: InputEvent) -> void:
	if not active or _ui_open:
		return
	if event is InputEventKey and event.keycode == KEY_F11:
		return                                           # fullscreen: let the editor have it
	get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * 0.0025
		pitch = clampf(pitch - event.relative.y * 0.0025, deg_to_rad(-89), deg_to_rad(89))
		_apply_cam()
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key(event)


func _mouse_button(e: InputEventMouseButton) -> void:
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			if e.pressed and not target.is_empty():
				_dragging = true
				_drag_from = target["sel"]
				sel = _drag_from.duplicate()
			elif not e.pressed:
				_dragging = false
		MOUSE_BUTTON_RIGHT:
			if e.pressed and not target.is_empty():
				sel = target["sel"].duplicate() if sel.is_empty() else _bounds(sel, target["sel"])
		MOUSE_BUTTON_WHEEL_UP:
			if e.pressed:
				wheel(1)
		MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				wheel(-1)


func _key(e: InputEventKey) -> void:
	var ctrl := e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_E, KEY_ESCAPE: stop()
		KEY_SPACE:
			sel = {}
		KEY_X: flip()
		KEY_C: copy()
		KEY_V: paste()
		KEY_Z, KEY_U:
			undo()
		KEY_I: redo()
		KEY_Y:
			if ctrl:
				redo()
		KEY_DELETE, KEY_BACKSPACE: delete()
		KEY_0:
			all_faces = not all_faces
			say("Texture all faces: %s" % ("on" if all_faces else "off (just the face you aim at)"))
		KEY_F1: _help.visible = not _help.visible
		KEY_F2: _open_picker()


## The selection, or if there's none the face under the crosshair.
func op_sel() -> Dictionary:
	if not sel.is_empty():
		return sel
	return target.get("sel", {})


## What the mouse wheel does: dir 1 = rolled away from you (push in), -1 = towards you (pull out).
func wheel(dir: int) -> void:
	if Input.is_key_pressed(KEY_G):
		grid_p = clampi(grid_p + dir, CubeWorld.MIN_P, CubeWorld.MAX_P)
		sel = {}
		say("Grid: %s cubes" % _metres_text(CubeWorld.metres(grid_p)))
		return
	var s := op_sel()
	if s.is_empty():
		return
	var w := cubes.world
	w.begin()
	var out := s
	if Input.is_key_pressed(KEY_Y):
		var ids := [""] + MaterialLibrary.entries().map(func(e): return e["id"])
		texture = ids[posmod(ids.find(texture) + dir, ids.size())]
		w.set_texture(s, texture, all_faces)
		say("Texture: %s" % _tex_name(texture))
	elif Input.is_key_pressed(KEY_R):
		out = w.rotate(s, dir)
	elif Input.is_key_pressed(KEY_F):
		out = w.push_face(s, dir)
	elif Input.is_key_pressed(KEY_Q):
		out = w.push_face(s, dir, int(target.get("corner", 0)) if sel.is_empty() else int(sel.get("corner", target.get("corner", 0))))
	elif dir > 0:
		out = w.push(s)
	else:
		out = w.pull(s, texture)
	w.commit()
	if not sel.is_empty():
		sel = out


func flip() -> void:
	var s := op_sel()
	if s.is_empty():
		return
	cubes.world.begin()
	cubes.world.flip(s)
	cubes.world.commit()
	say("Flipped")


func copy() -> void:
	var s := op_sel()
	if s.is_empty():
		return
	clip = cubes.world.copy(s)
	say("Copied %d cubes - aim somewhere and press V" % (clip["cubes"] as Array).size())


## V: paste into the selection, or with none, on top of the face you aim at.
func paste() -> void:
	var s := op_sel()
	if s.is_empty() or clip.is_empty():
		return
	if sel.is_empty() and target.get("hit", false):
		s = CubeWorld.moved(s, 1)
	cubes.world.begin()
	var out := cubes.world.paste(s, clip)
	cubes.world.commit()
	sel = out
	say("Pasted")


func delete() -> void:
	var s := op_sel()
	if s.is_empty():
		return
	cubes.world.begin()
	cubes.world.delete(s)
	cubes.world.commit()


func undo() -> void:
	say("Undone" if cubes.world.undo() else "Nothing to undo")


func redo() -> void:
	say("Redone" if cubes.world.redo() else "Nothing to redo")


func _open_picker() -> void:
	_ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._open_picker(func(id):
		texture = id
		var s := op_sel()
		if not s.is_empty():
			cubes.world.begin()
			cubes.world.set_texture(s, id, all_faces)
			cubes.world.commit()
		say("Texture: %s" % _tex_name(id)))
	var picker: Window = editor._picker
	if not picker.popup_hide.is_connected(_picker_closed):
		picker.popup_hide.connect(_picker_closed)


func _picker_closed() -> void:
	if not active:
		return
	_ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func _tex_name(id: String) -> String:
	return MaterialLibrary.display_name(id) if id != "" else "plain (grid)"


static func _metres_text(m: float) -> String:
	return ("%d m" % roundi(m)) if m >= 1.0 else ("%s m" % str(m))


## The box covering two selections (same grid).
func _bounds(a: Dictionary, b: Dictionary) -> Dictionary:
	if a["p"] != b["p"]:
		return b.duplicate()
	var g := CubeWorld.size_of(a["p"])
	var lo: Vector3i = (a["o"] as Vector3i).min(b["o"])
	var hi: Vector3i = ((a["o"] as Vector3i) + (a["s"] as Vector3i) * g).max((b["o"] as Vector3i) + (b["s"] as Vector3i) * g)
	return CubeWorld.make_sel(lo, a["p"], a["orient"], (hi - lo) / g)


# ------------------------------------------------------------------------------------------------ every frame
func _process(delta: float) -> void:
	if not active:
		return
	if not _ui_open:
		var move := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): move -= cam.global_basis.z
		if Input.is_key_pressed(KEY_S): move += cam.global_basis.z
		if Input.is_key_pressed(KEY_A): move -= cam.global_basis.x
		if Input.is_key_pressed(KEY_D): move += cam.global_basis.x
		if move != Vector3.ZERO:
			cam.global_position += move.normalized() * speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0) * delta
	update_target()
	if _dragging and not target.is_empty():
		sel = _bounds(_drag_from, target["sel"])
		sel["orient"] = _drag_from["orient"]
	_draw()
	_layout_hud()
	_msg_time -= delta
	_msg.visible = _msg_time > 0.0
	var size_txt := ""
	if not sel.is_empty():
		var s: Vector3i = sel["s"]
		size_txt = "  ·  selection %d x %d x %d" % [s.x, s.y, s.z]
	_info.text = "BUILD  ·  grid %s  ·  texture: %s%s  ·  %d cubes%s  ·  F1 keys  ·  E back to the editor" % [
		_metres_text(CubeWorld.metres(grid_p)), _tex_name(texture), " (all faces)" if all_faces else "",
		cubes.world.count(), size_txt]


## Work out the face under the crosshair (snapped to the grid), or a spot in the air in front of you.
func update_target() -> void:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0)
	q.collision_mask = 1
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var g := CubeWorld.size_of(grid_p)
	var gm := CubeWorld.metres(grid_p)
	var orient: int
	var cell: Vector3i
	var corner := 0
	if not hit.is_empty():
		var n: Vector3 = hit["normal"]
		orient = CubeWorld.orient_of(n)
		var behind: Vector3 = ((hit["position"] as Vector3) - n * 0.01) / CubeWorld.TICK
		cell = Vector3i(floori(behind.x / g) * g, floori(behind.y / g) * g, floori(behind.z / g) * g)
		# the corner of the face nearest the crosshair (for Q)
		var local: Vector3 = ((hit["position"] as Vector3) / CubeWorld.TICK - Vector3(cell)) / float(g) * 8.0
		var best := INF
		var quad := CubeWorld.face_corners(orient)
		for i in 4:
			var dd := CubeWorld.corner(CubeWorld.FULL, quad[i]).distance_to(local)
			if dd < best:
				best = dd
				corner = i
	else:
		var pt := from + dir * clampf(gm * 6.0, 3.0, 40.0)
		orient = CubeWorld.orient_of(-dir)
		var t := pt / CubeWorld.TICK
		var c := Vector3i(floori(t.x / g) * g, floori(t.y / g) * g, floori(t.z / g) * g)
		cell = c - CubeWorld.orient_step(orient) * g    # the cell behind, so pulling builds right where you look
	target = {"sel": CubeWorld.make_sel(cell, grid_p, orient), "corner": corner, "hit": not hit.is_empty()}


func _draw() -> void:
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	if not target.is_empty():
		var ts: Dictionary = target["sel"]
		_face_rect(ts, Color(1.0, 0.85, 0.2) if target["hit"] else Color(1.0, 0.85, 0.2, 0.5))
		if Input.is_key_pressed(KEY_Q):
			var g := CubeWorld.metres(ts["p"])
			var o := Vector3(ts["o"]) * CubeWorld.TICK
			var cp := o + CubeWorld.corner(CubeWorld.FULL, CubeWorld.face_corners(ts["orient"])[target["corner"]]) / 8.0 * g
			for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
				_line(cp - ax * g * 0.2, cp + ax * g * 0.2, Color(1, 0.3, 0.2))
	if not sel.is_empty():
		var g := CubeWorld.metres(sel["p"])
		var lo := Vector3(sel["o"]) * CubeWorld.TICK
		var hi := lo + Vector3(sel["s"]) * g
		_box(lo, hi, Color(1, 1, 1))
		var layer := sel.duplicate()
		var s: Vector3i = sel["s"]
		var d: int = sel["orient"] >> 1
		if sel["orient"] & 1:
			layer["o"] = (sel["o"] as Vector3i) + CubeWorld.orient_step(sel["orient"]) * CubeWorld.size_of(sel["p"]) * (s[d] - 1)
		s[d] = 1
		layer["s"] = s
		_face_rect(layer, Color(0.35, 0.7, 1.0))
	_line(Vector3.ZERO, Vector3.ZERO, Color.BLACK)       # (never an empty surface)
	_im.surface_end()


## Place the HUD for the window's size (anchors don't apply to Controls straight under a CanvasLayer).
func _layout_hud() -> void:
	var vp := get_viewport().get_visible_rect().size
	_cross.position = vp * 0.5 - _cross.size * 0.5
	_info.position = Vector2(16, vp.y - _info.size.y - 14)
	_help.position = Vector2(vp.x - _help.size.x - 16, 16)
	_msg.position = Vector2(vp.x * 0.5 - _msg.size.x * 0.5, vp.y - 120)


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	_im.surface_set_color(c)
	_im.surface_add_vertex(a)
	_im.surface_set_color(c)
	_im.surface_add_vertex(b)


func _box(lo: Vector3, hi: Vector3, c: Color) -> void:
	var p := []
	for i in 8:
		p.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line(p[e[0]], p[e[1]], c)


## The outline of a selection's faces on its face side (just off the surface so it never hides inside it).
func _face_rect(s: Dictionary, c: Color) -> void:
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
		pts.append(v)
	for i in 4:
		_line(pts[i], pts[(i + 1) % 4], c)
