extends SceneTree
## Surf physics in play mode match Source / SurfsUp (0.18.17). Flicking away from a ramp mid-surf (a j-turn) never
## throws you down the ramp: air strafing is horizontal, as in Source, not tilted along the ramp face (SUCC did that,
## and while you were still moving up, the speed cap let one tick add up to 17 m/s down the slope).
## Run: godot --path . --resolution 1280x720 -s res://tests/surf_flick_test.gd -- <out folder>

var ok := true
var player: SUCC
var cmd := SUCCInput.new()
const N := Vector3(0.8660254, 0.5, 0.0)                  # the ramp face: 60 degrees, facing +X
const UP_SLOPE := Vector3(-0.5, 0.8660254, 0.0)


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func ramp() -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	var h := 40.0
	var top := Vector2(-h / 1.7320508, h)                 # cross-section: (0, 0) up the face to top, back down at x = top.x
	var f := PackedVector3Array()
	for z in [[-50.0, 600.0]]:
		var a := Vector3(0, 0, z[0]); var b := Vector3(0, 0, z[1])
		var c := Vector3(top.x, top.y, z[0]); var d := Vector3(top.x, top.y, z[1])
		f.append_array([a, c, b, b, c, d])               # the face
		var e := Vector3(top.x, 0, z[0]); var g := Vector3(top.x, 0, z[1])
		f.append_array([c, e, d, d, e, g])               # the back
	shape.set_faces(f)
	cs.shape = shape
	body.add_child(cs)
	return body


func on_face(y: float) -> Vector3:
	return Vector3(-y / 1.7320508, y, 0.0) + N * 0.6       # a little out from the face at height y


## Put the player against the face at height y moving at `vel`, let it settle a tick, return it.
func place(y: float, vel: Vector3) -> void:
	player.global_position = on_face(y) + N * 0.5
	cmd.move = Vector2.ZERO
	for i in 40:                                          # pressed onto the face until it rides it
		player.velocity = vel - N * 4.0
		await physics_frame
		if player.floor_type == SUCC.FloorType.RAMP:
			break
	player.velocity = vel


func _run() -> void:
	root.add_child(ramp())
	player = load("res://addons/SUCC/scenes/succ_character.tscn").instantiate()
	root.add_child(player)
	player.command = cmd
	cmd.yaw = 0.0                                         # forward = -Z, move.x = +1 = +X (away from the ramp)
	await physics_frame
	# riding up the face, then a flick away from it
	var worst := 0.0
	for up in [0.0, 3.0, 6.0, 10.0]:
		await place(20.0, Vector3(0, 0, -20) + UP_SLOPE * up)
		var vy0 := player.velocity.y
		var ft := player.floor_type
		cmd.move = Vector2(1, 0)
		await physics_frame
		var dv := vy0 - player.velocity.y
		print("  moving up the ramp at %.0f m/s (floor %d): flick away, vertical speed %.2f -> %.2f" % [up, ft, vy0, player.velocity.y])
		worst = maxf(worst, dv - 20.32 / Engine.physics_ticks_per_second)
	check("a flick away from the ramp doesn't pull you down (beyond gravity)", worst < 0.2, "(%.2f m/s extra)" % worst)
	# holding into the ramp while falling: no free climb
	await place(30.0, Vector3(0, -8, -20))
	cmd.move = Vector2(-1, 0)
	var vy0 := player.velocity.y
	var ft0 := player.floor_type
	await physics_frame
	# Source: gravity, then AirAccelerate along the horizontal wish (capped by horizontal speed), then ClipVelocity
	var c := player.config
	var dt := 1.0 / Engine.physics_ticks_per_second
	var v := Vector3(0, -8, -20) + Vector3.DOWN * c.gravity * dt
	var wish := Vector3(-1, 0, 0)
	v += wish * minf(c.air_acceleration * c.max_speed * dt, c.max_air_speed - Vector3(v.x, 0, v.z).dot(wish))
	v -= N * minf(v.dot(N), 0.0)
	print("  falling at 8 m/s (floor %d), strafe into the ramp: vertical speed %.2f -> %.2f (Source: %.2f)" % [ft0, vy0, player.velocity.y, v.y])
	check("strafing into the ramp while falling: the same as Source", player.velocity.distance_to(v) < 0.05, "(%s vs %s)" % [player.velocity, v])
	# surfing still works: hold into the ramp for 2 s, stay on it, gain speed going down it
	await place(36.0, Vector3(0, 0, -20))
	cmd.move = Vector2(-1, 0)
	var on := 0
	var t := 2 * Engine.physics_ticks_per_second
	for i in t:
		await physics_frame
		if player.floor_type == SUCC.FloorType.RAMP:
			on += 1
	var sp := player.velocity.length()
	print("  2 s holding into the ramp from 20 m/s: on it %d / %d ticks, %.1f m/s, %.1f m down" % [on, t, sp, 36.0 - player.global_position.y])
	check("surfing: holding into the ramp keeps you on it, speed kept", on > t * 0.9 and sp > 19.5)
	var y0 := player.global_position.y
	cmd.move = Vector2.ZERO
	for i in Engine.physics_ticks_per_second:
		await physics_frame
	print("  then 1 s letting go: %.1f m/s, %.1f m down" % [player.velocity.length(), y0 - player.global_position.y])
	check("...and letting go, you slide down it and speed up", player.velocity.length() > sp + 3.0 and player.global_position.y < y0 - 2.0)
	print("surf_flick_test: ", "PASS" if ok else "FAIL")
	quit()
