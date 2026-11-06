class_name OrbitCamera
extends Camera3D
## Editor camera.
##   Right mouse drag      orbit around the focus point
##   Middle mouse drag     pan
##   Mouse wheel           zoom
##   Right mouse + WASD/QE fly (Shift = faster)
##   F                     frame the selection (called by the editor)

var focus := Vector3.ZERO
var distance := 220.0
var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-30.0)
var fly_speed := 60.0

var _orbiting := false
var _panning := false


func _ready() -> void:
	far = 8000.0
	fov = 70.0
	_apply()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = max(distance * 0.88, 2.0)
			_apply()
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = min(distance / 0.88, 5000.0)
			_apply()
			return true
	elif event is InputEventMouseMotion:
		if _orbiting:
			var k := 0.006 * Settings.editor_mouse()          # (View > Mouse sensitivity)
			yaw -= event.relative.x * k
			pitch = clamp(pitch - event.relative.y * k * Settings.y_sign(), deg_to_rad(-89), deg_to_rad(89))
			_apply()
			return true
		if _panning:
			var scale := distance * 0.0016
			focus += (-global_basis.x * event.relative.x + global_basis.y * event.relative.y) * scale
			_apply()
			return true
	return false


func _process(delta: float) -> void:
	if not _orbiting:
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move -= global_basis.z
	if Input.is_key_pressed(KEY_S): move += global_basis.z
	if Input.is_key_pressed(KEY_A): move -= global_basis.x
	if Input.is_key_pressed(KEY_D): move += global_basis.x
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP
	if move != Vector3.ZERO:
		var speed := fly_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		focus += move.normalized() * speed * delta
		_apply()


func frame(center: Vector3, radius: float) -> void:
	focus = center
	distance = clamp(radius * 2.2, 20.0, 4000.0)
	_apply()


func _apply() -> void:
	var dir := Vector3(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
	global_position = focus + dir * distance
	look_at(focus, Vector3.UP)
