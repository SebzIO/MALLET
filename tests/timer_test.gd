extends SceneTree
## The run timer times the exact moment the start and finish zone edges are crossed, between physics ticks (physics
## runs at 60 steps a second; before this every time was a whole number of steps: 6.383, 6.400, 6.417...).
## Checks the crossing maths exactly, then flies a player through a start and a finish zone and compares the timer
## with the true crossing moments worked out from where the player was each tick.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/timer_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## When (seconds) the x coordinate crossed `edge`, from samples taken every `dt`.
func crossing_time(xs: Array, edge: float, dt: float) -> float:
	for i in range(1, xs.size()):
		if xs[i - 1] < edge and xs[i] >= edge:
			return (i - 1 + (edge - xs[i - 1]) / (xs[i] - xs[i - 1])) * dt
	return -1.0


func _run() -> void:
	# the maths: a step from x = -1 to x = 3 crosses x = 0 a quarter of the way through
	var into := AABB(Vector3(0, -5, -5), Vector3(10, 10, 10))
	var out_of := AABB(Vector3(-10, -5, -5), Vector3(10, 10, 10))
	check("entering a zone a quarter of the way through a step", absf(PlayMode.crossing(Vector3(-1, 0, 0), Vector3(3, 0, 0), into, true) - 0.25) < 1e-5)
	check("leaving a zone a quarter of the way through a step", absf(PlayMode.crossing(Vector3(-1, 0, 0), Vector3(3, 0, 0), out_of, false) - 0.25) < 1e-5)
	check("no previous position (spawn, teleport): the whole step counts", PlayMode.crossing(null, Vector3(3, 0, 0), into, true) == 1.0)

	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._load_dict({})
	var play: PlayMode = ed.play
	var dt := 1.0 / Engine.physics_ticks_per_second
	var speed := 900.0 / PlayMode.UNITS_PER_METRE
	for gap in [11.37, 23.81]:
		var start_box := AABB(Vector3(-20, 400, -20), Vector3(20, 200, 40))   # ends at x = 0
		var finish_box := AABB(Vector3(gap, 400, -20), Vector3(20, 200, 40))  # starts at x = gap
		play.start(Transform3D(Basis(), Vector3(-0.6, 560, 0)), start_box, finish_box, -1000.0)
		var xs := []
		var frames := 0
		while play.run_state != PlayMode.Run.FINISHED and frames < 600:
			play.player.velocity.x = speed
			play.player.velocity.z = 0.0
			await physics_frame
			xs.append(play.player.global_position.x)
			frames += 1
		await process_frame
		var vp := root.get_viewport().get_visible_rect().size
		var box: Control = play._hud_box
		var cross: Control = play._hud_cross
		check("play HUD (time, speed, keys line) centred in the view", absf(box.position.x + box.size.x * 0.5 - vp.x * 0.5) < 1.5
			and absf(cross.position.x + cross.size.x * 0.5 - vp.x * 0.5) < 1.5 and absf(cross.position.y + cross.size.y * 0.5 - vp.y * 0.5) < 1.5,
			"(box centre %.0f, cross centre %.0f, view %.0f)" % [box.position.x + box.size.x * 0.5, cross.position.x + cross.size.x * 0.5, vp.x * 0.5])
		check("finish speed shown: %d u/s entering the finish at 900" % roundi(play.finish_speed),
			absf(play.finish_speed - 900.0) < 2.0 and play._info_label.text.contains("finish %d u/s" % roundi(play.finish_speed)), play._info_label.text)
		var truth := crossing_time(xs, gap, dt) - crossing_time(xs, 0.0, dt)
		var got: float = play.run_time
		play.stop()
		await process_frame
		check("a %.2f m gap: timer %.4f s, true crossing to crossing %.4f s" % [gap, got, truth], absf(got - truth) < 0.0015,
			"(off by %.2f ms)" % ((got - truth) * 1000.0))
		check("...between ticks, not a whole number of them", absf(got / dt - roundf(got / dt)) > 0.02, "(%.2f ticks)" % (got / dt))
	play.start(Transform3D(Basis(), Vector3(-0.6, 560, 0)), AABB(), AABB(), -1000.0)
	await process_frame
	check("last run's finish speed still shown on the next play", play._info_label.text.contains("finish 900 u/s"), play._info_label.text)
	play.stop()
	check("times show the thousandths", PlayMode.format_time(6.4127) == "0:06.413")
	print("TIMER: ", "PASS" if ok else "FAIL")
	quit()
