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

var active := false
var player: SUCC
var spawn := Transform3D.IDENTITY
var top_speed := 0.0
var best_time := 0.0

enum Run { WAITING, RUNNING, FINISHED }
var run_state := Run.WAITING
var run_time := 0.0
var _start_box := AABB()
var _kill_y := -60.0
var _volumes: Array = []
var _inside := {}                      ## booster / teleport -> was the player inside last tick
var _stages := {}                      ## stage number -> EntityNode plate
var _reached: Array = []               ## stage numbers reached this run, in order
var _splits: Array = []                ## [stage number, time] for each stage reached
var _checkpoint := Transform3D.IDENTITY
var _message := ""
var _message_time := 0.0
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
func start(at: Transform3D, start_box := AABB(), finish_box := AABB(), kill_y := -60.0, volumes: Array = [],
		stages := {}) -> void:
	if active:
		return
	spawn = at
	_start_box = start_box
	_finish_box = finish_box
	_kill_y = kill_y
	_volumes = volumes
	_stages = stages
	_inside.clear()
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


## Back to the start: a fresh run.
func _place() -> void:
	run_state = Run.WAITING
	run_time = 0.0
	_reached.clear()
	_splits.clear()
	_checkpoint = spawn
	_put(spawn, Vector3.ZERO)


## Back to the current checkpoint (start or the last stage reached); the run keeps going.
func _to_checkpoint() -> void:
	if _reached.is_empty():
		_place()
	else:
		_put(_checkpoint, Vector3.ZERO)


func _put(at: Transform3D, velocity: Vector3) -> void:
	player.teleport(Transform3D(Basis(Vector3.UP, at.basis.get_euler().y), at.origin))
	player.velocity = velocity
	if player.camera_rig:
		player.camera_rig.pitch = 0.0
	for k in _inside.keys():
		_inside[k] = false


func _physics_process(delta: float) -> void:
	if not active:
		return
	if player.global_position.y < _kill_y:
		_to_checkpoint()
		return
	var feet := player.global_position + Vector3(0, 0.5, 0)
	var body := player.global_position + Vector3(0, 0.9, 0)
	for v in _volumes:
		var inside: bool = v.contains(body)
		if v.kind == "kill" and inside:
			_to_checkpoint()
			return
		if v.kind in ["booster", "teleport"]:
			var entered: bool = inside and not _inside.get(v, false)
			_inside[v] = inside
			if entered and v.kind == "booster":
				_boost(v)                        # once per entry, like a trigger
			if entered and v.kind == "teleport":
				var plate: EntityNode = _stages.get(v.number)
				if plate == null:
					_flash_message("This teleport goes to stage %d, which doesn't exist yet" % v.number)
				else:
					# keep speed: SurfsUp's point teleport keeps the velocity as it is (same direction of travel)
					_put(plate.spawn_transform(), player.velocity if v.keep_speed else Vector3.ZERO)
					_reach_stage(plate)
					return
	# landing on a stage plate also reaches it
	for n in _stages:
		var plate: EntityNode = _stages[n]
		if not n in _reached and plate.zone_aabb().has_point(feet):
			_reach_stage(plate)
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
				var missing := _stages.keys().filter(func(n): return not n in _reached)
				if not missing.is_empty():
					missing.sort()
					_flash_message("Finish blocked: reach stage %d first" % missing[0])
					return
				run_state = Run.FINISHED
				_flash = 3.0
				if best_time <= 0.0 or run_time < best_time:
					best_time = run_time


## SurfsUp booster: Add pushes along the arrow on top of your speed, Set replaces your speed with exactly this.
func _boost(v: EntityNode) -> void:
	var push: Vector3 = v.boost_direction() * (v.strength / UNITS_PER_METRE)
	var change: Vector3 = push if v.mode == 0 else push - player.velocity
	player.add_impulse(change)


func _reach_stage(plate: EntityNode) -> void:
	_checkpoint = plate.spawn_transform()
	if plate.number in _reached:
		return
	_reached.append(plate.number)
	if run_state == Run.RUNNING:
		_splits.append([plate.number, run_time])
		_flash_message("Stage %d   %s" % [plate.number, format_time(run_time)])


func _flash_message(t: String) -> void:
	_message = t
	_message_time = 2.5


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
	_message_time = maxf(_message_time - _delta, 0.0)
	if _message_time > 0.0 and run_state != Run.FINISHED:
		_time_label.text += "\n" + _message
	var best := "   ·   best %s" % format_time(best_time) if best_time > 0.0 else ""
	var stage := ""
	if not _stages.is_empty():
		var cur: int = _reached.max() if not _reached.is_empty() else 1
		stage = "   ·   stage %d / %d" % [cur, _stages.size() + 1]
	_info_label.text = "top %d u/s%s%s   ·   R restart   ·   Backspace checkpoint   ·   Esc editor" % [roundi(top_speed), stage, best]


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
		if event.keycode == KEY_BACKSPACE:
			_to_checkpoint()
			return true
	return true            # while playing, the editor ignores everything else
