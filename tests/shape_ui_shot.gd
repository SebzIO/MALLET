extends SceneTree
## Screenshots of the ramp panel: a half ramp, Freeform, and a too-tight bend marked red.
## Run: godot --path . --resolution 1600x900 -s res://tests/shape_ui_shot.gd -- <out>

func _init() -> void:
	call_deferred("_run")


func shot(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	ed._select(r)
	ed._edit_prop("style", "half_left")
	ed._edit_prop("solid", true)
	ed._edit_prop("base_depth", 6.0)
	ed._refresh_props()
	await shot(out + "/shape_half.png")
	ed._edit_prop("style", "v")
	ed._edit_prop("solid", false)
	ed._edit_prop("freeform", true)
	ed._edit_prop("angle_right", 68.0)
	ed._refresh_props()
	await shot(out + "/shape_freeform.png")
	ed._edit_prop("freeform", false)
	r.points = PackedVector3Array([Vector3(-60, 120, 0), Vector3(-40, 116, -6), Vector3(-50, 112, -14), Vector3(60, 90, 0)])
	r.rebuild()
	ed._refresh_props()
	await shot(out + "/shape_fold.png")
	print("folds: ", r.folds.size(), "  freeform after off: ", r.freeform, " right=", r.angle_right)
	quit()
