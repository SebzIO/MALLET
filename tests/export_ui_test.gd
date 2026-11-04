extends SceneTree
## Drives the editor's Export dialog: exports the starter map into SurfsUp's Maps folder as sf_starter.
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
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
	quit()
