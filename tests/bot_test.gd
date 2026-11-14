extends SceneTree
## Can the bot surf the templates to the finish with SUCC? Prints progress per ramp and the finish time.
## Run: godot --path . --resolution 1280x720 -s res://tests/bot_test.gd -- <template file name>

var ed
var bot: SurfBot


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var which: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "2_first_surf"
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.template_chosen.emit("res://templates/%s.mallet" % which)
	for i in 3:
		await physics_frame
	ed._play_clicked()
	await physics_frame
	var bf := "res://demo/bots/%s.json" % which.substr(2)
	bot = SurfBot.new(ed, JSON.parse_string(FileAccess.get_file_as_string(bf))["params"] if FileAccess.file_exists(bf) else {})
	var last_ramp = null
	var top := 0.0
	var resets := 0
	var last_y := 0.0
	var trace_from := -1
	for i in 60 * 90:
		await physics_frame
		bot.tick(1.0 / 60.0)
		var p: SUCC = ed.play.player
		var h := Vector2(p.velocity.x, p.velocity.z).length() * 39.37
		top = maxf(top, h)
		var near := bot._nearest(p.global_position + Vector3(0, 0.9, 0))
		if bot.on_ramp and near.get("ramp") != last_ramp:
			last_ramp = near["ramp"]
			if last_ramp.get_index() == 2 and trace_from < 0:
				trace_from = i + 150
			var ideal := sqrt(pow(400.0 / 39.37, 2) + 2.0 * 20.32 * maxf(ed.play.spawn.origin.y - p.global_position.y, 0.0)) * 39.37
			print("  t=%5.1f s  on ramp %d at %d u/s (%d%% of the ideal %d)" % [ed.play.run_time, last_ramp.get_index(), roundi(h),
				roundi(p.velocity.length() * 39.37 / ideal * 100.0), roundi(ideal)])
		if p.global_position.y > last_y + 30.0:
			resets += 1
			print("  t=%5.1f s  respawned (fell?) -> y %.0f" % [ed.play.run_time, p.global_position.y])
		last_y = p.global_position.y
		if trace_from >= 0 and i >= trace_from and i < trace_from + 400 and i % 12 == 0:
			var n2 := bot._nearest(p.global_position + Vector3(0, 0.9, 0))
			print("    %.1fs pos %s vel %s on_floor %s on_ramp %s dist %.1f move %s yaw %.0f slides %d" % [i / 60.0, p.global_position.snapped(Vector3.ONE * 0.1),
				p.velocity.snapped(Vector3.ONE * 0.1), p.is_on_floor(), bot.on_ramp, n2.get("dist", -1.0), p.command.move if p.command else Vector2.ZERO,
				rad_to_deg(bot.yaw), p.get_slide_collision_count()], " target ", bot._target_ramp.get_index() if bot._target_ramp else -1, " landing ", bot._landing.snapped(Vector3.ONE))
		if ed.play.run_state == PlayMode.Run.FINISHED:
			print("%s: FINISHED in %s, top %d u/s, %d respawns" % [which, PlayMode.format_time(ed.play.run_time), roundi(top), resets])
			quit()
			return
	print("%s: did not finish (state %d, t %.1f)" % [which, ed.play.run_state, ed.play.run_time])
	quit()
