class_name PlayMode
extends Node
## Surf the map inside the editor with SUCC, Mark Arneman's SurfsUp character controller (MIT, addons/SUCC).
## Same movement code and SurfsUp preset as the game, so what you feel here is what players feel.

signal stopped

const SUCC_SCENE := "res://addons/SUCC/scenes/succ_character.tscn"
const UNITS_PER_METRE := 39.37            # SurfsUp's HUD shows Source units/s
const KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE,
	"crouch": KEY_CTRL, "sprint": KEY_SHIFT}
const KILL_Y := -60.0                     # below this you respawn (stand-in for the map's kill floor)

var active := false
var player: SUCC
var spawn := Transform3D.IDENTITY
var top_speed := 0.0

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


func start(at: Transform3D) -> void:
	if active:
		return
	spawn = at
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
	player.teleport(Transform3D(Basis(Vector3.UP, spawn.basis.get_euler().y), spawn.origin))
	player.velocity = Vector3.ZERO
	if player.camera_rig:
		player.camera_rig.pitch = 0.0


func _physics_process(_delta: float) -> void:
	if active and player.global_position.y < KILL_Y:
		_place()


func _process(_delta: float) -> void:
	if not active:
		return
	var h := Vector2(player.velocity.x, player.velocity.z).length() * UNITS_PER_METRE
	top_speed = max(top_speed, h)
	_speed_label.text = "%d" % roundi(h)
	_info_label.text = "top %d u/s   ·   R respawn   ·   Esc back to editor" % roundi(top_speed)


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
