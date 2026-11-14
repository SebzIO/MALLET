extends SceneTree
func _init():
	call_deferred("_run")
func shot(name: String) -> void:
	for i in 5: await process_frame
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tests/out/" + name + ".png"))
func _run():
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var w0: float = ed.panes[0].size.x
	ed._select(null)
	await process_frame
	await shot("p01_nothing_selected")
	var w1: float = ed.panes[0].size.x
	ed._add_entity("booster")
	await process_frame
	await shot("p02_booster_selected")
	print("perspective view width: ramp selected %d, nothing selected %d, booster selected %d" % [w0, w1, ed.panes[0].size.x])
	quit()
