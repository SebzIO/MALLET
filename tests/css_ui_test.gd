extends SceneTree
## The CS:S export dialog end to end: open it on the Three Stages template, export + compile on the background
## thread, and wait for the .bsp to land in cstrike/maps. Screenshot of the dialog: css_dialog.png
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/css_ui_test.gd -- <out>

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# (the dialogs remember folders in your real settings file: keep a copy and put it back at the end)
	var saved_settings := FileAccess.get_file_as_string("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else ""
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.template_chosen.emit("res://templates/3_three_stages.mallet")
	await process_frame
	ed._css_clicked()
	ed._css_name.text = "sf_dialog_test"
	ed._css_dir.text = out + "/css"
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/css_dialog.png")
	var bsp := VmfExporter.find_css() + "/cstrike/maps/sf_dialog_test.bsp"
	if FileAccess.file_exists(bsp):
		DirAccess.remove_absolute(bsp)
	ed._css_dialog.hide()
	ed._do_css_export()
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while ed._css_thread != null and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
		frames += 1
	print("editor kept drawing while compiling: %d frames in %.1f s" % [frames, (Time.get_ticks_msec() - t0) / 1000.0])
	print("status: ", ed._status.text)
	var ok: bool = FileAccess.file_exists(bsp) and ed._status.text.contains("map sf_dialog_test") and frames > 10
	print("CSS UI: ", "PASS" if ok else "FAIL")
	if saved_settings == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var sf := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		sf.store_string(saved_settings)
		sf.close()
	quit()
