extends SceneTree
## Physics check: SUCC's player surfs a MALLET ramp (holding strafe into the face, as a player does)
## and we compare its speed against the in-game SurfsUp measurement: ~2200 u/s after a 76 m drop.
## Run: godot --headless --path D:/SurfForge -s res://tests/surf_physics.gd

const U := 39.37      # Source units per meter

var ramp: RampNode
var player: SUCC
var start_y := 0.0
var ticks := 0
var log_at := [10.0, 25.0, 50.0, 76.0, 100.0]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	# long straight ramp heading +X, ridge dropping 120 m over 900 m
	ramp = RampNode.new()
	ramp.points = PackedVector3Array([Vector3(0, 300, 0), Vector3(450, 240, 0), Vector3(900, 180, 0)])
	ramp.width = 13.0
	ramp.height = 8.125
	ramp.detail = 1.0
	world.add_child(ramp)
	for a in ["forward", "back", "left", "right", "jump", "crouch", "sprint"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	player = load("res://addons/SUCC/scenes/succ_character.tscn").instantiate()
	world.add_child(player)
	# stand on the -Z face, a little below the ridge, facing down the ramp (+X)
	player.global_position = Vector3(2, 300 - 3.0, -2.6)
	player.command = SUCCInput.new()
	player.command.yaw = -PI / 2           # face +X
	player.command.move = Vector2(1, 0)     # hold "right" = +Z = into the ramp face
	start_y = 300.0
	physics_frame.connect(_tick)


func _tick() -> void:
	ticks += 1
	if ticks % 60 == 1:
		print("t%3d pos %s vel %s floor %d slides %d" % [ticks, player.global_position.snapped(Vector3.ONE * 0.01), player.velocity.snapped(Vector3.ONE * 0.01), player.floor_type, player.get_slide_collision_count()])
	# surf like a player: hold strafe into the ramp when sliding too far down the face, ease off when too high
	var off := absf(player.global_position.z)          # distance out from the ridge line (ramp runs along +X at z=0)
	player.command.move = Vector2(1, 0) if off > 3.0 else (Vector2(-0.3, 0) if off < 1.5 else Vector2.ZERO)
	var drop := start_y - player.global_position.y
	var speed := player.velocity.length()
	if log_at.size() > 0 and drop >= log_at[0]:
		var ideal := sqrt(2.0 * player.config.gravity * drop)
		print("drop %5.1f m  speed %6.1f m/s = %5.0f u/s   frictionless %5.0f u/s   (%.0f%%)   x %.0f  on %s"
			% [drop, speed, speed * U, ideal * U, 100.0 * speed / ideal, player.global_position.x,
			["air", "floor", "ramp"][player.floor_type]])
		log_at.pop_front()
	if ticks > 60 * 40 or log_at.is_empty() or player.global_position.y < 100:
		print("ended after %.1f s, x %.0f, y %.0f" % [ticks / 60.0, player.global_position.x, player.global_position.y])
		quit()
