extends SceneTree
## Performance probe on a real map (run: godot --path D:/SurfForge --resolution 1600x900 -s res://tools/perf_probe.gd -- <map> [noshadow|nolights|noanim|manylights]): frame time (vsync off), each view's GPU time and draw calls, in the four views,
## one view, build mode and play mode. Args: <map> [label]

var ed


func _init() -> void:
	call_deferred("_run")


func measure(label: String, frames := 120) -> void:
	for i in 20:
		await process_frame
	var vps := []
	for p in ed.panes:
		if p.is_visible_in_tree():
			RenderingServer.viewport_set_measure_render_time(p.viewport.get_viewport_rid(), true)
			vps.append(p)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var t0 := Time.get_ticks_usec()
	var gpu := {}
	var draws := 0.0
	for i in frames:
		await process_frame
		for p in vps:
			gpu[p.kind] = float(gpu.get(p.kind, 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(p.viewport.get_viewport_rid())
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / frames
	var parts := PackedStringArray()
	for k in gpu:
		parts.append("%s %.1f" % [["persp", "top", "front", "side"][k], gpu[k] / frames])
	var root_gpu := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
	print("%-34s %5.1f ms/frame (%3d fps)  GPU ms: %s  window %.1f  draws %d" % [label, ms, roundi(1000.0 / ms), " ".join(parts), root_gpu, roundi(draws / frames)])


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed.load_map(OS.get_cmdline_user_args()[0])
	for i in 30:
		await process_frame
	for cm in ed.cube_models_root.get_children():
		cm.finish_background()
	await process_frame
	for cm in ed.cube_models_root.get_children():
		cm.merge_all()
		print("cube object draws: ", cm.draw_count())
	var mode: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
	for l in ed.lights_root.get_children():
		if mode == "noshadow":
			l.from_dict(l.to_dict().merged({"shadows": false}, true))
		elif mode == "nolights":
			l.visible = false
		elif mode == "noanim":
			l.from_dict(l.to_dict().merged({"effect": "none"}, true))
	if mode == "manylights":
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 150:
			var ln := LightNode.new()
			ed.lights_root.add_child(ln)
			ln.from_dict({"kind": "point", "position": [rng.randf_range(-120, 120), rng.randf_range(120, 260), rng.randf_range(-700, 0)],
				"color": "ff60c0", "energy": 2.0, "range": 40.0, "effect": ("none" if OS.get_cmdline_user_args().size() > 2 else "pulse"), "shadows": true})
		await process_frame
	print("mode: ", mode, "  lights: ", ed.lights_root.get_child_count())
	for p in ed.panes:
		p.frame(Vector3(0, 150, -300), 900.0)
	var pc := ed.panes[0].camera as OrbitCamera
	pc.focus = Vector3(0, 150, -300)
	pc.distance = 500.0
	pc._apply()
	await measure("four views")
	ed._toggle_views()
	await measure("one 3D view")
	ed._toggle_views()
	ed._build_clicked()
	await measure("build mode (E)")
	ed.build.stop()
	await process_frame
	ed._play_clicked()
	var p: SUCC = ed.play.player
	for at in [Vector3(0, 205, -40), Vector3(0, 160, -230), Vector3(0, 300, -600)]:
		p.global_position = at
		p.velocity = Vector3.ZERO
		await measure("play at %s" % at)
	ed.play.stop()
	quit()
