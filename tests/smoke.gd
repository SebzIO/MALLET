extends SceneTree
## Smoke test: drives the editor through its own functions and saves screenshots.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/smoke.gd -- <out_dir>

func _init() -> void:
	call_deferred("_run")


func shot(ed, out: String, name: String) -> void:
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name, "  status: ", ed._status.text)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await shot(ed, out, "01_new_map")

	# bend the default ramp: move its middle point sideways and down, then add a bend near the end
	var r: RampNode = ed.selected
	ed._checkpoint()
	var pts := r.points
	pts[1] = pts[1] + Vector3(0, -6, 45)
	r.points = pts
	r.rebuild()
	ed.selected_point = 1
	ed._bend_clicked()
	ed._extend_clicked()
	var p2 := r.points
	p2[p2.size() - 1] += Vector3(-20, -30, 60)
	r.points = p2
	r.rebuild()
	ed._rebuild_handles()
	ed._refresh_props()
	await shot(ed, out, "02_curved")

	# smoothness + second ramp
	ed._edit_prop("detail", 0.15)
	await shot(ed, out, "03_low_poly")
	ed._edit_prop("detail", 2.0)
	ed._duplicate_clicked()
	ed._edit_prop("color", Color(0.15, 0.6, 0.6))
	ed._frame_clicked()
	await shot(ed, out, "04_two_ramps")

	# undo / redo
	var before: int = ed.ramps_root.get_child_count()
	ed.undo(); ed.undo(); ed.undo()
	var after_undo: int = ed.ramps_root.get_child_count()
	ed.redo(); ed.redo(); ed.redo()
	print("ramps before ", before, " after undo ", after_undo, " after redo ", ed.ramps_root.get_child_count())

	# save -> new -> load round trip
	var path := ProjectSettings.globalize_path("res://maps/smoke_test.sfmap")
	ed.save_map(path)
	var saved := FileAccess.get_file_as_string(path)
	ed._new_map()
	ed.load_map(path)
	print("round trip identical: ", JSON.stringify(ed._map_dict(), "  ") == saved)
	await shot(ed, out, "05_reloaded")
	print("triangles of first ramp: ", (ed.ramps_root.get_child(0) as RampNode).triangle_count)
	quit()
