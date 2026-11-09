class_name ViewPane
extends SubViewportContainer
## One editor view onto the shared world: a 3D perspective view or an orthographic top / front / side view.
## Handles its own camera navigation; selection and dragging are forwarded to the editor with this pane's camera.
##
## Ortho views: right- or middle-drag pans, wheel zooms (towards the mouse).

enum Kind { PERSPECTIVE, TOP, FRONT, SIDE }
## Named like Hammer's views: Front looks down the X axis, Side looks across it (down Z here, Source's Y).
const NAMES := ["Perspective", "Top  (X / Z)", "Front  (Z / Y)", "Side  (X / Y)"]
const FAR := 6000.0

var kind := Kind.PERSPECTIVE
var editor: Node
var viewport := SubViewport.new()
var camera: Camera3D
var overlay := Control.new()

var _pan := false
var _ortho_center := Vector3(0, 100, 0)
var mouse_here := false                     ## the pointer is over this view (co-editors see where it is)
var mouse_world := Vector3.ZERO             ## and what it points at in the world


func _init(k: int, ed: Node) -> void:
	kind = k
	editor = ed
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.own_world_3d = false
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.physics_object_picking = false
	add_child(viewport)
	if kind == Kind.PERSPECTIVE:
		camera = OrbitCamera.new()
		(camera as OrbitCamera).fly_speed_changed.connect(func(v: float):
			if editor and editor.has_method("_set_status"):
				editor._set_status("Fly speed: %.0f m/s  (right mouse + wheel: faster / slower)" % v))
	else:
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 300.0
		camera.near = 0.05
		camera.far = FAR * 2.0
		camera.cull_mask = 1                                # hide the 3D ground grid (layer 2)
		var env := Environment.new()                         # flat backdrop instead of the sky
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.13, 0.14, 0.16)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.78, 0.85)
		env.ambient_light_energy = 0.8
		camera.environment = env
	viewport.add_child(camera)
	camera.current = true
	# never smooth editor cameras between physics ticks: the 3D image would trail the true camera that the
	# overlay (outline, handles, arcs, grid) is drawn with. The setting doesn't inherit across the SubViewport.
	viewport.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)  # the container only sizes its SubViewport, not Controls
	overlay.clip_contents = true                         # handles/outlines/arcs never spill into neighboring views
	clip_contents = true
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)


func _ready() -> void:
	_apply_ortho()


func is_ortho() -> bool:
	return kind != Kind.PERSPECTIVE


## Plane the mouse drags across in this view, through `p`. In the perspective view it's the ground plane,
## or a camera-facing vertical plane when `vertical` (Shift) is held.
func drag_plane(p: Vector3, vertical: bool) -> Plane:
	match kind:
		Kind.TOP: return Plane(Vector3.UP, p)
		Kind.SIDE: return Plane(Vector3.BACK, p)
		Kind.FRONT: return Plane(Vector3.RIGHT, p)
	if vertical:
		var n := camera.global_basis.z
		n.y = 0.0
		return Plane(n.normalized() if n.length() > 1e-3 else Vector3.BACK, p)
	return Plane(Vector3.UP, p)


## Which world axes a drag in this view may change: in ortho views only the two visible axes.
func drag_axes(vertical: bool) -> Vector3:
	match kind:
		Kind.TOP: return Vector3(1, 0, 1)
		Kind.SIDE: return Vector3(1, 1, 0)
		Kind.FRONT: return Vector3(0, 1, 1)
	return Vector3(0, 1, 0) if vertical else Vector3(1, 0, 1)


func ray(mouse: Vector2) -> Array:
	return [camera.project_ray_origin(mouse), camera.project_ray_normal(mouse)]


## Where the pointer reads in the world: the ground in the perspective view, the flat plane this ortho view is
## looked at through. Null when the ray misses (a perspective view aimed at the sky).
func mouse_point(at: Vector2) -> Variant:
	var o := camera.project_ray_origin(at)
	var n := camera.project_ray_normal(at)
	var plane := Plane(Vector3.UP, 0.0)
	if is_ortho():
		var back := -camera.global_basis.z
		plane = Plane(back, back.dot(_ortho_center))
	return plane.intersects_ray(o, n)


func frame(center: Vector3, radius: float) -> void:
	if kind == Kind.PERSPECTIVE:
		(camera as OrbitCamera).frame(center, radius)
	else:
		_ortho_center = center
		camera.size = clamp(radius * 2.6, 20.0, 8000.0)
		_apply_ortho()


func _apply_ortho() -> void:
	if not is_ortho():
		return
	var c := _ortho_center
	match kind:
		Kind.TOP:
			camera.global_position = Vector3(c.x, FAR, c.z)
			camera.look_at(Vector3(c.x, 0, c.z), Vector3.FORWARD)      # north (-Z) up the screen
		Kind.SIDE:
			camera.global_position = Vector3(c.x, c.y, FAR)
			camera.look_at(Vector3(c.x, c.y, 0), Vector3.UP)
		Kind.FRONT:
			camera.global_position = Vector3(FAR, c.y, c.z)
			camera.look_at(Vector3(0, c.y, c.z), Vector3.UP)
	overlay.queue_redraw()


## Right / middle drag (orbit, fly, pan) holds on to the mouse: the cursor is hidden and can't run into the edge of
## the screen (or onto another display); letting go puts it back where the drag started.
var _grab_button := -1
var _grab_pos := Vector2.ZERO


func _begin_grab(button: int) -> void:
	_grab_button = button
	_grab_pos = get_viewport().get_mouse_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _end_grab() -> void:
	if _grab_button < 0:
		return
	_grab_button = -1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_viewport().warp_mouse(_grab_pos)


func is_grabbing() -> bool:
	return _grab_button >= 0


## Let go of the mouse now, as if the button came up (build / play mode starting, or the release went elsewhere).
func release_grab() -> void:
	if _grab_button < 0:
		return
	var up := InputEventMouseButton.new()
	up.button_index = _grab_button as MouseButton
	up.pressed = false
	if kind == Kind.PERSPECTIVE:
		(camera as OrbitCamera).handle_input(up)
	else:
		_ortho_nav(up)
	_end_grab()


## While grabbed, every mouse event comes here (the hidden cursor isn't over the view any more).
func _input(event: InputEvent) -> void:
	if _grab_button < 0 or not (event is InputEventMouse):
		return
	get_viewport().set_input_as_handled()
	if kind == Kind.PERSPECTIVE:
		(camera as OrbitCamera).handle_input(event)
	elif not (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		_ortho_nav(event)                                # (wheel zoom aims at the cursor, which is hidden: skipped)
	if event is InputEventMouseButton and not event.pressed and event.button_index == _grab_button:
		_end_grab()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_grab()                                   # (alt-tab mid-drag: the release never arrives - let go now)
	elif what == NOTIFICATION_MOUSE_EXIT:
		mouse_here = false


func _gui_input(event: InputEvent) -> void:
	editor.set_active_pane(self)
	if event is InputEventMouse:
		var hit = mouse_point(event.position)
		mouse_here = hit != null
		if hit != null:
			mouse_world = hit
	if _grab_button < 0 and event is InputEventMouseButton and event.pressed 			and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		_begin_grab(event.button_index)
	if kind == Kind.PERSPECTIVE:
		if (camera as OrbitCamera).handle_input(event):
			accept_event()
			return
	elif _ortho_nav(event):
		accept_event()
		return
	if editor.pane_input(self, event):
		accept_event()


func _ortho_nav(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_pan = event.pressed
			return true
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before: Vector3 = camera.project_position(event.position, FAR)
			camera.size = clamp(camera.size * (0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.88), 10.0, 10000.0)
			var after: Vector3 = camera.project_position(event.position, FAR)
			_ortho_center += before - after                 # keep the point under the mouse fixed
			_apply_ortho()
			return true
	elif event is InputEventMouseMotion and _pan:
		var world_per_px: float = camera.size / maxf(size.y, 1.0)
		_ortho_center += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * world_per_px
		_apply_ortho()
		return true
	return false


func _process(_delta: float) -> void:
	if _grab_button >= 0 and not Input.is_mouse_button_pressed(_grab_button as MouseButton):
		release_grab()                                   # (its release went somewhere else: never keep the mouse)
	if overlay.size != size or overlay.position != Vector2.ZERO:
		overlay.position = Vector2.ZERO
		overlay.size = size
	overlay.queue_redraw()


func _draw_overlay() -> void:
	if is_ortho():
		_draw_grid()
	editor.draw_pane_overlay(self, overlay)
	var active: bool = editor.active_pane == self
	overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.6, 1.0, 0.9) if active else Color(0.1, 0.1, 0.12), false, 2.0)
	overlay.draw_string(get_theme_default_font(), Vector2(8, 18), NAMES[kind], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1, 1, 1, 0.85))


## Meter grid for the ortho views, with spacing that adapts to the zoom level and labeled major lines.
func _draw_grid() -> void:
	var world_per_px: float = camera.size / maxf(size.y, 1.0)
	var spacing := 1.0
	for s in [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0]:
		spacing = s
		if s / world_per_px >= 18.0:
			break
	var major := spacing * 5.0
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var center := camera.global_position
	var half: Vector2 = Vector2(size.x, size.y) * 0.5 * world_per_px
	var font := get_theme_default_font()
	for axis in 2:
		var dir: Vector3 = right if axis == 0 else up
		var c: float = center.dot(dir)
		var extent: float = half.x if axis == 0 else half.y
		var v: float = floorf((c - extent) / spacing) * spacing
		while v <= c + extent:
			var is_major := is_zero_approx(fmod(absf(v), major))
			var is_axis := is_zero_approx(v)
			var col := Color(0.9, 0.55, 0.2, 0.7) if is_axis else (Color(1, 1, 1, 0.16) if is_major else Color(1, 1, 1, 0.06))
			var px: float = (v - c) / world_per_px
			if axis == 0:
				var x: float = size.x * 0.5 + px
				overlay.draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
				if is_major:
					overlay.draw_string(font, Vector2(x + 3, size.y - 6), "%d" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
			else:
				var y: float = size.y * 0.5 - px
				overlay.draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
				if is_major:
					overlay.draw_string(font, Vector2(4, y - 3), "%d" % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
			v += spacing
