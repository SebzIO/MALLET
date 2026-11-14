extends SceneTree
## Mouse sensitivity (View > Mouse sensitivity): the editor's 3D view, build mode and play mode each turn at their
## own speed, invert flips up / down, it's saved for next time, and the dialog's sliders change it. Your own settings
## file is put back afterwards.
## Run: godot --path . --resolution 1600x900 -s res://tests/settings_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func motion(dx: float, dy: float) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(dx, dy)
	e.screen_relative = Vector2(dx, dy)
	return e


func _run() -> void:
	var saved := FileAccess.get_file_as_string(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else ""
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._load_dict({})
	for k in Settings.DEFAULTS:
		Settings.set_value(k, Settings.DEFAULTS[k])

	# editor 3D view: right-drag orbit
	var cam: OrbitCamera = ed.panes[0].camera
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	cam.handle_input(press)
	var y0 := cam.yaw
	cam.handle_input(motion(100, 0))
	var at1 := y0 - cam.yaw
	Settings.set_value("editor_mouse", 2.0)
	y0 = cam.yaw
	cam.handle_input(motion(100, 0))
	var at2 := y0 - cam.yaw
	check("editor view: 2x sensitivity turns twice as far", absf(at2 - 2.0 * at1) < 1e-4, "(%.4f vs %.4f rad)" % [at2, at1])
	press.pressed = false
	cam.handle_input(press)

	# build mode
	ed._build_clicked()
	await process_frame
	var bm: BuildMode = ed.build
	Settings.set_value("play_mouse", 2.0)
	y0 = bm.yaw
	bm._input(motion(100, 0))
	var b1 := y0 - bm.yaw
	Settings.set_value("play_mouse", 1.0)
	y0 = bm.yaw
	bm._input(motion(100, 0))
	var b2 := y0 - bm.yaw
	check("build mode: the Source number drives it too (half the number, half the turn)", absf(b2 - 0.5 * b1) < 1e-4, "(%.4f vs %.4f rad)" % [b2, b1])
	var p0 := bm.pitch
	bm._input(motion(0, -50))
	var up := bm.pitch - p0
	Settings.set_value("invert_y", true)
	p0 = bm.pitch
	bm._input(motion(0, -50))
	var up_inv := bm.pitch - p0
	check("invert: moving the mouse forward looks the other way", signf(up) == -signf(up_inv) and up != 0.0)
	Settings.set_value("invert_y", false)
	bm.stop()
	await process_frame

	# play mode: the Source-style number, without touching the shared default
	Settings.set_value("play_mouse", 5.5)
	ed.play.start(Transform3D(Basis(), Vector3(0, 50, 0)))
	await physics_frame
	var default_cfg: SUCCConfig = load("res://addons/SUCC/resources/default_config.tres")
	check("play mode: your sensitivity (5.5, same scale as SurfsUp / CS:S)", is_equal_approx(ed.play.player.config.mouse_sensitivity, 5.5)
		and is_equal_approx(default_cfg.mouse_sensitivity, 3.0))
	ed._set_mouse("play_mouse", 2.25)
	check("changing it while playing takes effect straight away", is_equal_approx(ed.play.player.config.mouse_sensitivity, 2.25))
	ed.play.stop()
	await process_frame

	# saved for next time
	Settings._cfg = null
	check("settings are saved for next time", is_equal_approx(Settings.play_mouse(), 2.25) and is_equal_approx(Settings.build_mouse(), 2.25)
		and is_equal_approx(Settings.editor_mouse(), 2.0))

	# the dialog
	ed._open_mouse_settings()
	await process_frame
	var pair: Array = ed._fields["mouse_play_mouse"]
	(pair[0] as HSlider).value = 1.75
	check("View > Mouse sensitivity: one number for build and play", is_equal_approx(Settings.play_mouse(), 1.75)
		and is_equal_approx(Settings.build_mouse(), 1.75) and is_equal_approx((pair[1] as SpinBox).value, 1.75))
	ed._mouse_dialog.hide()

	# put your own settings back
	if saved == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(saved)
		f.close()
	Settings._cfg = null
	print("SETTINGS: ", "PASS" if ok else "FAIL")
	quit()
