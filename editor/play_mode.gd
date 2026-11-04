class_name PlayMode
extends Node
## Surf the map inside the editor with SUCC, Mark Arneman's SurfsUp character controller (MIT, addons/SUCC).
## Same movement code and SurfsUp preset as the game, so what you feel here is what players feel.

signal stopped

const SUCC_SCENE := "res://addons/SUCC/scenes/succ_character.tscn"
const UNITS_PER_METRE := 39.37            # SurfsUp's HUD shows Source units/s
const KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE,
	"crouch": KEY_CTRL, "sprint": KEY_SHIFT}
const PRESPEED_CAP := 400.0                ## u/s: SurfsUp's default mode caps speed in the start zone
const KILL_Y := -60.0                     # below this you respawn (stand-in for the map's kill floor)

var active := false
var player: SUCC
var spawn := Transform3D.IDENTITY
var top_speed := 0.0
var best_time := 0.0

enum Run { WAITING, RUNNING, FINISHED }
var run_state := Run.WAITING
var run_time := 0.0
var _start_box := AABB()
var _finish_box := AABB()
var _flash := 0.0
var _time_label := Label.new()

var _hud := CanvasLayer.new()
var _speed_label := Label.new()
var _info_label := Label.new()


func _ready() -> void:
	_ensure_input_actions()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-160, -150)
	box.custom_minimum_size = Vector2(320, 0)
	_hud.add_child(box)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 30)
	_time_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_time_label.add_theme_constant_override("outline_size", 8)
	box.add_child(_time_label)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.add_theme_font_size_override("font_size", 44)
	_speed_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_speed_label.add_theme_constant_override("outline_size", 8)
	box.add_child(_speed_label)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_info_label.add_theme_constant_override("outline_size", 6)
	box.add_child(_info_label)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.add_theme_font_size_override("font_size", 22)
	_hud.add_child(cross)


## Creates any missing movement actions with WASD / Space / Ctrl / Shift.
func _ensure_input_actions() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, ev)


## `start_box` / `finish_box` are the start and finish zones (empty AABB = none): leaving the start starts the
## timer, entering the finish stops it.
func start(at: Transform3D, start_box := AABB(), finish_box := AABB()) -> void:
	if active:
		return
	spawn = at
	_start_box = start_box
	_finish_box = finish_box
	best_time = 0.0
	player = load(SUCC_SCENE).instantiate()
	add_child(player)
	_place()
	active = true
	top_speed = 0.0
	_hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func stop() -> void:
	if not active:
		return
	active = false
	_hud.visible = false
	player.queue_free()
	player = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stopped.emit()


func respawn() -> void:
	if active:
		_place()


func _place() -> void:
	run_state = Run.WAITING
	run_time = 0.0
	player.teleport(Transform3D(Basis(Vector3.UP, spawn.basis.get_euler().y), spawn.origin))
	player.velocity = Vector3.ZERO
	if player.camera_rig:
		player.camera_rig.pitch = 0.0


func _physics_process(delta: float) -> void:
	if not active:
		return
	if player.global_position.y < KILL_Y:
		_place()
		return
	var feet := player.global_position + Vector3(0, 0.5, 0)
	match run_state:
		Run.WAITING:
			# no prespeed: bhopping on the platform can't build speed, and you leave it at 400 u/s at most
			_cap_horizontal_speed(PRESPEED_CAP / UNITS_PER_METRE)
			if not _start_box.has_volume() or not _start_box.has_point(feet):
				run_state = Run.RUNNING              # left the start zone (or there is none): go
				run_time = 0.0
		Run.RUNNING:
			run_time += delta
			if _finish_box.has_volume() and _finish_box.has_point(feet):
				run_state = Run.FINISHED
				_flash = 3.0
				if best_time <= 0.0 or run_time < best_time:
					best_time = run_time


func _cap_horizontal_speed(limit: float) -> void:
	var h := Vector2(player.velocity.x, player.velocity.z)
	if h.length() > limit:
		h = h.normalized() * limit
		player.velocity.x = h.x
		player.velocity.z = h.y


static func format_time(t: float) -> String:
	return "%d:%06.3f" % [int(t) / 60, fmod(t, 60.0)]


func _process(_delta: float) -> void:
	if not active:
		return
	var h := Vector2(player.velocity.x, player.velocity.z).length() * UNITS_PER_METRE
	top_speed = max(top_speed, h)
	_speed_label.text = "%d" % roundi(h)
	match run_state:
		Run.WAITING: _time_label.text = "leave the start zone to begin" if _start_box.has_volume() else ""
		Run.RUNNING: _time_label.text = format_time(run_time)
		Run.FINISHED: _time_label.text = "FINISHED  %s%s" % [format_time(run_time), "   (best!)" if is_equal_approx(run_time, best_time) else ""]
	_time_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if run_state == Run.FINISHED else Color.WHITE)
	var best := "   ·   best %s" % format_time(best_time) if best_time > 0.0 else ""
	_info_label.text = "top %d u/s%s   ·   R restart   ·   Esc back to editor" % [roundi(top_speed), best]


## Returns true if the event was a play-mode control.
func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			stop()
			return true
		if event.keycode == KEY_R:
			respawn()
			return true
	return true            # while playing, the editor ignores everything else
