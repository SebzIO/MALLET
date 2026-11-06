extends SceneTree
## Drives the editor's Export dialog: exports the starter map into SurfsUp's Maps folder as sf_starter.
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	# (the dialogs remember folders in your real settings file: keep a copy and put it back at the end)
	var saved_settings := FileAccess.get_file_as_string("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else ""
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._export_clicked()
	print("detected Maps folder: ", ed._export_dir.text)
	ed._export_name.text = "bad name!"
	ed._do_export()
	print("bad name -> ", ed._status.text.strip_edges())
	ed._export_name.text = "sf_starter"
	ed._do_export()
	print("export -> ", ed._status.text.strip_edges())
	if saved_settings == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var sf := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		sf.store_string(saved_settings)
		sf.close()
	quit()
