extends SceneTree
## Render video for real (0.30.0): a short shot rendered by a second MALLET under Movie Maker, as an .avi and as PNG
## pictures, one of them bigger than the screen. Checks each file appears with the right size, frame rate and frame
## count, the magenta marker is not in the video, and the picture moves.
##   godot --path . --resolution 1600x900 -s res://tests/shot_render_test.gd -- <existing out folder>
## (Opens MALLET windows: the test's own and each render's.) Run with MALLET.exe instead of godot to test a build.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("_run")


func key(p: Vector3, yaw: float, pitch: float, dur: float) -> Dictionary:
	return {"pos": [p.x, p.y, p.z], "yaw": yaw, "pitch": pitch, "roll": 0.0, "fov": 70.0, "dur": dur, "ease_in": 0.0, "ease_out": 0.0}


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else OS.get_user_data_dir()
	var dir := out.path_join("render_test")
	RenderJob._clean(dir, true)
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var s := CameraPath.new_shot("Fly by")
	s["keys"] = [key(Vector3(-80, 140, 60), -60, -20, 0.25), key(Vector3(0, 130, 80), 0, -25, 0.25), key(Vector3(80, 120, 60), 60, -20, 0.1)]
	var s2 := CameraPath.new_shot("Big")
	s2["keys"] = [key(Vector3(0, 150, 120), 0, -30, 0.125), key(Vector3(10, 150, 120), 10, -30, 0.0)]
	var s3 := CameraPath.new_shot("Full HD")
	s3["keys"] = [key(Vector3(-40, 140, 90), -20, -25, 1.4), key(Vector3(40, 130, 90), 20, -25, 0.0)]
	ed.shots = [s, s2, s3]
	var map_path := ProjectSettings.globalize_path("user://test_maps/render_test.mallet")
	DirAccess.make_dir_recursive_absolute(map_path.get_base_dir())
	ed.save_map(map_path)
	print("renderer: ", OS.get_executable_path())
	# 1. AVI, 320 x 180, 24 fps: 0.5 s = 12 frames
	var j := RenderDialog.make_job(ed, [0], dir, 320, 180, 24, "avi")
	var t0 := Time.get_ticks_msec()
	await _wait(j)
	print("  avi render took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	check(j.done and j.failed == "", "AVI render finished (%s)" % (j.failed if j.failed != "" else j.stage))
	var avi := dir.path_join("render_test - Fly by.avi")
	check(FileAccess.file_exists(avi), "the .avi is in the folder")
	var info := AviWriter.info(avi)
	print("  ", info)
	check(info.get("width") == 320 and info.get("height") == 180, "AVI is 320 x 180")
	check(info.get("frames_header") == 12 and info.get("frames_index") == 12, "AVI has 12 frames (0.5 s at 24 fps)")
	check(info.get("rate") == 24, "AVI plays at 24 fps")
	var chunks := AviWriter.video_chunks(avi)
	var fa := FileAccess.open(avi, FileAccess.READ)
	var good := 0
	var marked := 0
	for c in chunks:
		fa.seek(c[0])
		var im := Image.new()
		if im.load_jpg_from_buffer(fa.get_buffer(c[1])) == OK and im.get_size() == Vector2i(320, 180):
			good += 1
			marked += 1 if RenderJob._is_marker(im) else 0
	fa.close()
	check(good == 12 and marked == 0, "every AVI frame is a 320 x 180 JPEG of the shot (%d good, %d marker)" % [good, marked])
	# 2. PNG pictures, bigger than the screen (2560 x 1440), 0.125 s at 24 fps = 3 frames
	var j2 := RenderDialog.make_job(ed, [1], dir, 2560, 1440, 24, "png")
	await _wait(j2)
	check(j2.done and j2.failed == "", "PNG render finished (%s)" % (j2.failed if j2.failed != "" else j2.stage))
	var pdir := dir.path_join("render_test - Big")
	var pngs := Array(DirAccess.get_files_at(pdir)).filter(func(n: String) -> bool: return n.ends_with(".png"))
	pngs.sort()
	check(pngs.size() == 3, "3 PNG frames (%d)" % pngs.size())
	if pngs.size() > 0:
		var img := Image.load_from_file(pdir.path_join(pngs[0]))
		check(img.get_size() == Vector2i(2560, 1440), "each frame is 2560 x 1440, bigger than the screen (%s)" % img.get_size())
		var magenta := RenderJob._is_marker(img)
		check(not magenta, "the first frame is the shot, not the marker")
		var last := Image.load_from_file(pdir.path_join(pngs[pngs.size() - 1]))
		var diff := 0
		for y in range(0, 1440, 40):
			for x in range(0, 2560, 40):
				if img.get_pixel(x, y).to_html() != last.get_pixel(x, y).to_html():
					diff += 1
		check(diff > 10, "the picture moves between the first and last frame (%d samples differ)" % diff)
	# the same as an AVI: its JPEG frames are the full size too, and so is its header
	var j4 := RenderDialog.make_job(ed, [1], dir, 2560, 1440, 24, "avi")
	await _wait(j4)
	var big := dir.path_join("render_test - Big.avi")
	var binfo := AviWriter.info(big)
	var bch := AviWriter.video_chunks(big)
	var bimg := Image.new()
	if not bch.is_empty():
		var bf := FileAccess.open(big, FileAccess.READ)
		bf.seek(bch[0][0])
		bimg.load_jpg_from_buffer(bf.get_buffer(bch[0][1]))
		bf.close()
	check(j4.done and binfo.get("width") == 2560 and binfo.get("height") == 1440 and bch.size() == 3 and bimg.get_size() == Vector2i(2560, 1440),
		"AVI bigger than the screen: 2560 x 1440 header and frames, 3 frames (%s, frame %s)" % [binfo, bimg.get_size()])
	# exactly 1920 x 1080 though the screen's room is smaller (the taskbar and title bar once squeezed it to 1920 x 1061);
	# 1.4 s at 24 fps = 34 frames, enough to measure the speed for the time estimate
	var usable := DisplayServer.screen_get_usable_rect()
	print("  usable screen: ", usable.size, "  (screen ", DisplayServer.screen_get_size(), ")")
	Settings.set_value("render_measured", {})
	var j5 := RenderDialog.make_job(ed, [2], dir, 1920, 1080, 24, "avi")
	await _wait(j5)
	var fh := dir.path_join("render_test - Full HD.avi")
	var finfo := AviWriter.info(fh)
	var fch := AviWriter.video_chunks(fh)
	var sizes := {}
	var ff := FileAccess.open(fh, FileAccess.READ)
	for c in fch:
		ff.seek(c[0])
		var im := Image.new()
		im.load_jpg_from_buffer(ff.get_buffer(c[1]))
		sizes[im.get_size()] = true
	ff.close()
	check(j5.done and finfo.get("width") == 1920 and finfo.get("height") == 1080 and fch.size() == 34 and sizes.keys() == [Vector2i(1920, 1080)],
		"1920 x 1080 on a screen with %s of room: header %s x %s, %d frames, frame sizes %s" % [usable.size, finfo.get("width"), finfo.get("height"), fch.size(), sizes.keys()])
	var m = Settings.value("render_measured")
	check(m is Dictionary and String(m.get("size", "")) == "1920x1080" and float(m.get("per_frame", 0)) > 0.0, "the render's speed is measured for the estimate (%s)" % [m])
	var est := RenderJob.estimate(34, 3840, 2160, 1)
	check(est > RenderJob.estimate(34, 1920, 1080, 1) and est > 0.0, "a bigger size is estimated to take longer (%.1f s for 4K)" % est)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(RenderJob.TMP)), "the render's scratch frames are cleaned up")
	# 3. cancel
	var j3 := RenderDialog.make_job(ed, [0], dir.path_join("canceled"), 320, 180, 24, "avi")
	j3.start()
	for i in 30:
		j3.tick()
		await process_frame
	j3.cancel()
	await create_timer(1.0).timeout
	check(j3.canceled and not FileAccess.file_exists(dir.path_join("canceled").path_join("render_test - Fly by.avi")), "Cancel stops the render and leaves no file")
	print("shot_render_test: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


func _wait(j: RenderJob) -> void:
	j.start()
	var t0 := Time.get_ticks_msec()
	var last := ""
	while not j.done and j.failed == "" and Time.get_ticks_msec() - t0 < 240000:
		j.tick()
		if j.stage != last:
			print("    ", j.stage)
			last = j.stage
		await create_timer(0.05).timeout
	if not j.done and j.failed == "":
		j.cancel()
		j.failed = "timed out"
