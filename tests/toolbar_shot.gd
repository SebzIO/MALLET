extends SceneTree
## Screenshot of the toolbar (snap + grid size together) and the generator panel. Output: toolbar.png

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._select(ed.ramps_root.get_child(0))
	ed._generate_clicked()
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/toolbar.png")
	quit()
