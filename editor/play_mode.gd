class_name PlayMode
extends Node
## Surf the map inside the editor with SUCC, Mark Arneman's SurfsUp character controller (MIT, addons/SUCC).
## Same movement code and SurfsUp preset as the game, so what you feel here is what players feel.

signal stopped
signal attempt_ended(attempt: Dictionary)   ## every run, for test builds (see Tester): outcome, time, deaths, route...
signal ghost_recorded(ghost: Dictionary)   ## a new best run: {"time", "hz", "samples": [x, y, z, speed m/s, ...]}
signal live(at: Vector3, speed: float, stage: int, state: String, attempt: int)   ## ~10 a second (a test build sends these)

const SUCC_SCENE := "res://addons/SUCC/scenes/succ_character.tscn"
const UNITS_PER_METRE := 39.37            # SurfsUp's HUD shows Source units/s
const KEYS := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE,
	"crouch": KEY_CTRL, "sprint": KEY_SHIFT}
const PRESPEED_CAP := 400.0                ## u/s: SurfsUp's default mode caps speed in the start zone
const GHOST_HZ := 20.0                     ## best-run samples per second kept in the map file

var active := false
var player: SUCC
var spawn := Transform3D.IDENTITY
var top_speed := 0.0
var best_time := 0.0
var finish_speed := 0.0                 ## u/s you were moving when you entered the finish on your last finished run (0 = none yet)

enum Run { WAITING, RUNNING, FINISHED }
var run_state := Run.WAITING
var run_time := 0.0
var _start_boxes: Array = []           ## the start zone's boxes (AABB each)
var _stage_boxes: Array = []           ## extra stage zone boxes: [stage number, AABB]
var _kill_y := -60.0
var _volumes: Array = []
var _inside := {}                      ## booster / teleport -> was the player inside last tick
var _stages := {}                      ## stage number -> EntityNode plate
var _reached: Array = []               ## stage numbers reached this run, in order
var _splits: Array = []                ## [stage number, time] for each stage reached
var _checkpoint := Transform3D.IDENTITY
var _message := ""
var _message_time := 0.0
var _finish_boxes: Array = []          ## the finish zone's boxes
var _flash := 0.0
var _time_label := Label.new()

var ghost: Dictionary = {}             ## the best run to race (empty = none)
var show_ghost := true
var _rec := PackedFloat32Array()       ## this run, every physics tick: x, y, z, speed
var _rec_dt := 0.0
var _prev_feet = null                    ## where the feet were last tick (for timing the exact moment a zone edge is crossed)
var _ghost_node: Node3D = null
var _ghost_label: Label3D = null
var _last_delta := ""                  ## "+1.234 vs best" after a finish
var _deaths: Array = []                 ## this attempt: where the player fell / died ([x, y, z] each)
var _attempt_top := 0.0                 ## this attempt's top speed (u/s)
var _attempt_start := 0.0               ## when it began (unix seconds)
var attempt_no := 0                     ## which attempt this is (live messages are labeled with it)
var _live_t := 0.0                      ## (live position timer)

## Practice tools (0.20.0): saved position (Q / E), noclip (N), go to a stage (2-9). Any of them makes the run
## practice: the timer says so, and nothing counts towards the best time, the ghost or tester data until R.
var practice := false
var noclip := false
var show_triggers := false
var trigger_nodes: Array = []           ## the map's zones / teleports / boosters (the editor's EntityNodes), shown with T
var _saved := {}                        ## {at: Transform3D, velocity, pitch}
const NOCLIP_SPEED := 30.0              ## m/s flying through things (Shift: 3x)

var _hud := CanvasLayer.new()
var _hud_box: VBoxContainer
var _hud_cross: Label
var _speed_label := Label.new()
var _info_label := Label.new()


func _ready() -> void:
	_ensure_input_actions()
	_hud.layer = 5
	_hud.visible = false
	add_child(_hud)
	var box := VBoxContainer.new()
	_hud.add_child(box)
	_hud_box = box
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
	cross.add_theme_font_size_override("font_size", 22)
	_hud.add_child(cross)
	_hud_cross = cross


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
func start(at: Transform3D, start_box = AABB(), finish_box = AABB(), kill_y := -60.0, volumes: Array = [],
		stages := {}, best_ghost := {}, stage_boxes: Array = []) -> void:
	if active:
		return
	spawn = at
	_start_boxes = _boxes(start_box)                     # (one AABB, or several: a zone made of several boxes)
	_finish_boxes = _boxes(finish_box)
	_stage_boxes = stage_boxes
	_kill_y = kill_y
	_volumes = volumes
	_stages = stages
	_inside.clear()
	ghost = best_ghost
	best_time = float(ghost.get("time", 0.0))
	_build_ghost()
	player = load(SUCC_SCENE).instantiate()
	add_child(player)
	player._action_available["sprint"] = false           # (no sprint in SurfsUp: Shift does nothing here, as in the game)
	apply_mouse_settings()
	_place()
	active = true
	top_speed = 0.0
	practice = false
	noclip = false
	_saved = {}
	show_triggers = bool(Settings.value("play_triggers"))
	_apply_triggers()
	_hud.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Your mouse sensitivity (View > Mouse sensitivity): Source-style, so the number you use in SurfsUp / CS:S works.
func apply_mouse_settings() -> void:
	if player == null or player.config == null:
		return
	if not player.has_meta("own_config"):
		player.config = player.config.duplicate()       # (don't change the shared default)
		player.set_meta("own_config", true)
	player.config.mouse_sensitivity = Settings.play_mouse()
	player.config.invert_y = Settings.invert_y()
	player.apply_config()


func stop() -> void:
	if not active:
		return
	_end_attempt("quit")
	active = false
	_hud.visible = false
	for e in trigger_nodes:                              # (the editor shows every zone again)
		if is_instance_valid(e):
			e.visible = true
			e.rebuild()
	player.queue_free()
	player = null
	if _ghost_node:
		_ghost_node.queue_free()
		_ghost_node = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stopped.emit()


func respawn() -> void:
	if active:
		_end_attempt("restart")
		_place()


## The attempt so far, as tester data: outcome "finish" / "restart" / "quit", time, splits, deaths, finish and top
## speed (u/s) and the route at 10 per second ([x, y, z, speed u/s] each). Only attempts that left the start count.
func _end_attempt(outcome: String) -> void:
	if practice:
		run_state = Run.WAITING
		return                                           # (practice isn't a run anyone timed)
	if run_state == Run.WAITING or (run_state == Run.FINISHED and outcome != "finish"):
		return                                           # (not started yet, or already recorded as a finish)
	var route := []
	for i in range(0, _rec.size(), 24):                 # every 6th tick of 60 = 10 a second
		route.append([snappedf(_rec[i], 0.01), snappedf(_rec[i + 1], 0.01), snappedf(_rec[i + 2], 0.01), roundf(_rec[i + 3] * UNITS_PER_METRE)])
	attempt_ended.emit({"outcome": outcome, "time": snappedf(run_time, 0.001), "started": _attempt_start,
		"splits": _splits.duplicate(true), "deaths": _deaths.duplicate(true),
		"finish_speed": roundf(finish_speed) if outcome == "finish" else 0.0, "top_speed": roundf(_attempt_top), "route": route})
	run_state = Run.WAITING


## Back to the start: a fresh run.
func _place() -> void:
	run_state = Run.WAITING
	run_time = 0.0
	_rec = PackedFloat32Array()
	_last_delta = ""
	if not ghost.is_empty():
		_build_ghost()                                  # a best set this session races you from the next run
	_reached.clear()
	_splits.clear()
	_deaths.clear()
	_attempt_top = 0.0
	_attempt_start = Time.get_unix_time_from_system()
	attempt_no += 1
	practice = false
	if noclip:
		_set_noclip(false)
	_checkpoint = spawn
	_put(spawn, Vector3.ZERO)


## Back to the current checkpoint (start or the last stage reached); the run keeps going.
func _to_checkpoint() -> void:
	if run_state == Run.RUNNING and player:
		var p := player.global_position
		_deaths.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	if _reached.is_empty():
		_end_attempt("restart")                          # (no stage reached: the fall ends this attempt)
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
	_prev_feet = null


const HULL_HALF := 0.4065                ## half the player's width (SUCC width 0.813 m)
const HULL_HEIGHT := 1.829               ## the player's standing height (SUCC stand_height)


## Will this tick's move bring the player's body into volume `v`, with nothing solid in between?
func _will_touch(v: EntityNode, delta: float) -> bool:
	var step := player.velocity * delta
	if step.length_squared() < 1e-8:
		return false
	var feet := player.global_position
	var t := v.hull_entry(feet, feet + step, HULL_HALF, HULL_HEIGHT)
	if t < 0.0:
		return false
	if t <= 0.0001:
		return true
	var from := feet + Vector3(0, HULL_HEIGHT * 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + step * t)
	q.collision_mask = player.collision_mask
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	if not active:
		return
	if noclip:
		_fly(delta)
		return
	if player.global_position.y < _kill_y:
		_to_checkpoint()
		return
	var feet := player.global_position + Vector3(0, 0.5, 0)
	var prev = _prev_feet
	_prev_feet = feet
	var body := player.global_position + Vector3(0, 0.9, 0)
	for v in _volumes:
		var inside: bool = v.contains(body)
		if v.kind == "kill" and inside:
			_to_checkpoint()
			return
		if v.kind in ["booster", "teleport"]:
			# Touching it this tick: the body is in it now, or this tick's move (still at full speed - this runs
			# before the player moves) would carry the body into it with nothing solid on the way. Checking only
			# where the player stood missed thin teleports against a wall at speed: the move hit the wall first,
			# the velocity went to zero, and the teleport then sent the player on standing still (0.24.2).
			var touch: bool = inside or _will_touch(v, delta)
			var entered: bool = touch and not _inside.get(v, false)
			_inside[v] = touch
			if entered and v.kind == "booster":
				_boost(v)                        # once per entry, like a trigger
			if entered and v.kind == "teleport" and v.to_dest:
				# to a destination: on with your speed (its direction kept, your view turned to the arrow, as SurfsUp's
				# point teleport does); no stage is reached, so dying after it sends you back where you'd respawn anyway
				var dest: EntityNode = null
				for d in _volumes:
					if d is EntityNode and d.kind == "destination" and d.number == v.number:
						dest = d
				if dest == null:
					_flash_message("This teleport goes to destination %d, which doesn't exist yet" % v.number)
				else:
					_put(dest.dest_transform(), player.velocity if v.keep_speed else Vector3.ZERO)
					return
			elif entered and v.kind == "teleport":
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
	for sb in _stage_boxes:
		if not sb[0] in _reached and _stages.has(sb[0]) and (sb[1] as AABB).has_point(feet):
			_reach_stage(_stages[sb[0]])
	match run_state:
		Run.WAITING:
			# no prespeed: bhopping on the platform can't build speed, and you leave it at 400 u/s at most
			_cap_horizontal_speed(PRESPEED_CAP / UNITS_PER_METRE)
			if _start_boxes.is_empty() or _box_at(_start_boxes, feet) == null:
				run_state = Run.RUNNING              # left the start zone (or there is none): go
				# the clock starts the moment the feet crossed the zone's edge, not at the tick after
				var left = _box_at(_start_boxes, prev) if prev != null else null   # (no previous tick yet: from the spot)
				run_time = (1.0 - crossing(prev, feet, left, false)) * delta if left != null else 0.0
		Run.RUNNING:
			run_time += delta
			_rec_dt = delta
			_attempt_top = maxf(_attempt_top, Vector2(player.velocity.x, player.velocity.z).length() * UNITS_PER_METRE)
			_record()
			var fin = _box_at(_finish_boxes, feet)
			if fin != null:
				var missing := _stages.keys().filter(func(n): return not n in _reached)
				if not missing.is_empty():
					missing.sort()
					_flash_message("Finish blocked: reach stage %d first" % missing[0])
					return
				if practice:
					run_state = Run.FINISHED
					_flash_message("Finished (practice: not timed - R for a real run)")
					return
				run_state = Run.FINISHED
				finish_speed = Vector2(player.velocity.x, player.velocity.z).length() * UNITS_PER_METRE
				# ...and stops the moment they crossed into the finish zone (between two ticks)
				run_time -= (1.0 - crossing(prev, feet, fin, true)) * delta
				_flash = 3.0
				_last_delta = "" if best_time <= 0.0 else "%+.3f vs best" % (run_time - best_time)
				if best_time <= 0.0 or run_time < best_time:
					best_time = run_time
					_save_ghost()
				_end_attempt("finish")
				run_state = Run.FINISHED


## How far through the last tick (0..1) the feet crossed a zone's edge, going in (`entering`) or out. Physics runs
## in steps of 1/60 s, so without this every time would be a whole number of steps (6.383, 6.400, 6.417...).
static func crossing(from, to: Vector3, box: AABB, entering: bool) -> float:
	if from == null or (from as Vector3).distance_to(to) < 1e-6 or (from as Vector3).distance_to(to) > 30.0:
		return 1.0                                       # no previous step (or a teleport): count the whole tick
	var a: Vector3 = from
	var hit = box.intersects_segment(a, to) if entering else box.intersects_segment(to, a)
	if hit == null:
		return 1.0
	return clampf(a.distance_to(hit) / a.distance_to(to), 0.0, 1.0)


# ------------------------------------------------------------------------------------------------ ghost
func _record() -> void:
	var p := player.global_position
	_rec.append_array([p.x, p.y, p.z, Vector2(player.velocity.x, player.velocity.z).length()])


## Keep this run as the best: resampled to GHOST_HZ so it stays small in the map file.
func _save_ghost() -> void:
	var n := _rec.size() / 4
	if n < 2:
		return
	var out := []
	var count := int(run_time * GHOST_HZ) + 1
	for k in count + 1:
		var t := minf(k / GHOST_HZ, run_time)
		var f := t / maxf(_rec_dt, 1e-4) - 1.0
		var i := clampi(int(floor(f)), 0, n - 2)
		var w := clampf(f - i, 0.0, 1.0)
		for c in 4:
			out.append(snappedf(lerpf(_rec[i * 4 + c], _rec[(i + 1) * 4 + c], w), 0.01))
	ghost = {"time": run_time, "hz": GHOST_HZ, "samples": out}
	ghost_recorded.emit(ghost)


## Where the best run was `t` seconds in (and its speed). Static so the editor can draw the line too.
static func ghost_at(g: Dictionary, t: float) -> Array:
	var s: Array = g.get("samples", [])
	var n := s.size() / 4
	if n == 0:
		return [Vector3.ZERO, 0.0]
	var f := clampf(t * float(g.get("hz", GHOST_HZ)), 0.0, n - 1.0)
	var i := mini(int(f), n - 2) if n > 1 else 0
	var w := f - i
	var j := mini(i + 1, n - 1)
	var a := Vector3(s[i * 4], s[i * 4 + 1], s[i * 4 + 2])
	var b := Vector3(s[j * 4], s[j * 4 + 1], s[j * 4 + 2])
	return [a.lerp(b, w), lerpf(s[i * 4 + 3], s[j * 4 + 3], w)]


func _build_ghost() -> void:
	if _ghost_node:
		_ghost_node.queue_free()
	_ghost_node = null
	if ghost.is_empty():
		return
	_ghost_node = Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.8
	body.mesh = cap
	body.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.45, 0.85, 1.0, 0.45)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	body.material_override = m
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_node.add_child(body)
	_ghost_label = Label3D.new()
	_ghost_label.text = "best  " + format_time(float(ghost["time"]))
	_ghost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ghost_label.no_depth_test = true
	_ghost_label.fixed_size = true
	_ghost_label.pixel_size = 0.0012
	_ghost_label.position.y = 2.6
	_ghost_label.modulate = Color(0.6, 0.9, 1.0)
	_ghost_label.outline_size = 8
	_ghost_node.add_child(_ghost_label)
	_ghost_node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ghost_node)


func _update_ghost() -> void:
	if _ghost_node == null:
		return
	_ghost_node.visible = show_ghost
	var t := run_time if run_state != Run.WAITING else 0.0
	var at := ghost_at(ghost, t)
	_ghost_node.global_position = at[0]
	_ghost_label.text = "best  %s   %d u/s" % [format_time(float(ghost["time"])), roundi(at[1] * UNITS_PER_METRE)]


## SurfsUp booster: Add pushes along the arrow on top of your speed, Set replaces your speed with exactly this.
static func _boxes(b) -> Array:
	if b is AABB:
		return [b] if (b as AABB).has_volume() else []
	return (b as Array).filter(func(x): return (x as AABB).has_volume())


## The box the point is in, or null.
static func _box_at(boxes: Array, p: Vector3):
	for b in boxes:
		if (b as AABB).has_point(p):
			return b
	return null


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
	_turn_binds(_delta)
	var h := Vector2(player.velocity.x, player.velocity.z).length() * UNITS_PER_METRE
	top_speed = max(top_speed, h)
	_live_t += _delta
	if _live_t >= 0.1:                                  # (10 a second, the same rate as a recorded route)
		_live_t = 0.0
		live.emit(player.global_position, h, int(_reached.max()) if not _reached.is_empty() else 0,
			"wait" if run_state == Run.WAITING else ("finish" if run_state == Run.FINISHED else "run"), attempt_no)
	_update_ghost()
	_speed_label.text = "%d" % roundi(h)
	match run_state:
		Run.WAITING: _time_label.text = "leave the start zone to begin" if not _start_boxes.is_empty() else ""
		Run.RUNNING: _time_label.text = format_time(run_time) if not practice else "PRACTICE"
		Run.FINISHED: _time_label.text = "FINISHED  %s%s" % [format_time(run_time),
			"   (best!)" if is_equal_approx(run_time, best_time) else "   " + _last_delta]
	_time_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5) if run_state == Run.FINISHED else Color.WHITE)
	_message_time = maxf(_message_time - _delta, 0.0)
	if _message_time > 0.0 and run_state != Run.FINISHED:
		_time_label.text += "\n" + _message
	var best := "   ·   best %s" % format_time(best_time) if best_time > 0.0 else ""
	var stage := ""
	if not _stages.is_empty():
		var cur: int = _reached.max() if not _reached.is_empty() else 1
		stage = "   ·   stage %d / %d" % [cur, _stages.size() + 1]
	var fin := "   ·   finish %d u/s" % roundi(finish_speed) if finish_speed > 0.0 else ""
	_info_label.text = "top %d u/s%s%s%s   ·   R restart   ·   Backspace checkpoint   ·   Q / E save / load   ·   N noclip   ·   T triggers   ·   2-9 stages%s   ·   Esc editor" % [roundi(top_speed), fin, stage, best,
		("   ·   G ghost " + ("on" if show_ghost else "off")) if not ghost.is_empty() else ""]
	# center the HUD for the window, once its text is set (anchors don't apply under a CanvasLayer)
	var vp := get_viewport().get_visible_rect().size
	_hud_box.reset_size()
	_hud_box.position = Vector2((vp.x - _hud_box.size.x) * 0.5, vp.y - _hud_box.size.y - 24)
	_hud_cross.position = (vp - _hud_cross.size) * 0.5


# ------------------------------------------------------------------------------------------------ practice tools
## Hold the left mouse button to turn left, the right one to turn right, at Settings turn_speed (Source's turn binds).
func _turn_binds(delta: float) -> void:
	if player == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var dir := 0.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dir += 1.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		dir -= 1.0
	if dir != 0.0:
		player._set_yaw(player.rotation.y + deg_to_rad(float(Settings.value("turn_speed"))) * dir * delta)


## Q: remember where you are, how fast you're going and where you look.
func save_position() -> void:
	_saved = {"at": Transform3D(Basis(Vector3.UP, player.rotation.y), player.global_position), "velocity": player.velocity,
		"pitch": player.camera_rig.pitch if player.camera_rig else 0.0}
	_flash_message("Position saved (E: back to it)")


## E: back to the saved position, with its speed and view. The run is practice from here.
func load_position() -> void:
	if _saved.is_empty():
		_flash_message("No position saved yet (Q saves one)")
		return
	practice = true
	if run_state == Run.WAITING:
		run_state = Run.RUNNING                          # (underway: the start platform's speed cap doesn't apply)
	_put(_saved["at"], _saved["velocity"])
	if player.camera_rig:
		player.camera_rig.pitch = float(_saved["pitch"])


## 2-9: to that stage's plate (practice). 1 is the start (a real run, like R).
func go_to_stage(n: int) -> void:
	var plate: EntityNode = _stages.get(n)
	if plate == null:
		_flash_message("There is no stage %d" % n)
		return
	practice = true
	if run_state == Run.WAITING:
		run_state = Run.RUNNING
	_checkpoint = plate.spawn_transform()
	if not n in _reached:
		_reached.append(n)
	_put(_checkpoint, Vector3.ZERO)
	_flash_message("Stage %d (practice)" % n)


## N: fly through everything (WASD, Space up, Ctrl down, Shift faster). The run is practice from here.
func _set_noclip(on: bool) -> void:
	noclip = on
	if player == null:
		return
	player.set_physics_process(not on)
	player.velocity = Vector3.ZERO
	if on:
		practice = true
	_flash_message("Noclip %s" % ("on" if on else "off"))


func _fly(delta: float) -> void:
	var cam: Camera3D = player.camera_rig.camera if player.camera_rig else null
	var b := cam.global_basis if cam else player.global_basis
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): move -= b.z
	if Input.is_physical_key_pressed(KEY_S): move += b.z
	if Input.is_physical_key_pressed(KEY_A): move -= b.x
	if Input.is_physical_key_pressed(KEY_D): move += b.x
	if Input.is_physical_key_pressed(KEY_SPACE): move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL): move -= Vector3.UP
	if move.length() > 0.0:
		player.global_position += move.normalized() * NOCLIP_SPEED * (3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * delta


## T: the map's zones, teleports, boosters and kill zones shown or hidden (hidden, as in the game, by default).
func _apply_triggers() -> void:
	for e in trigger_nodes:
		if not is_instance_valid(e):
			continue
		if e.is_volume():
			e.visible = show_triggers
		else:
			e._zone_mesh.visible = show_triggers
			e._flat_arrow.visible = show_triggers and e.kind in ["start", "stage"]


## Returns true if the event was a play-mode control.
func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			stop()
			return true
		match event.keycode:
			KEY_Q:
				save_position()
				return true
			KEY_E:
				load_position()
				return true
			KEY_N:
				_set_noclip(not noclip)
				return true
			KEY_T:
				show_triggers = not show_triggers
				Settings.set_value("play_triggers", show_triggers)
				_apply_triggers()
				_flash_message("Triggers %s" % ("shown" if show_triggers else "hidden"))
				return true
			KEY_1:
				respawn()
				return true
			KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				go_to_stage(event.keycode - KEY_0)
				return true
		if event.keycode == KEY_R:
			respawn()
			return true
		if event.keycode == KEY_BACKSPACE:
			_to_checkpoint()
			return true
		if event.keycode == KEY_G:
			show_ghost = not show_ghost
			return true
	return true            # while playing, the editor ignores everything else
