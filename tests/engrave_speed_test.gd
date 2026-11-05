extends SceneTree
## Engraving speed: the default text engraved into the top of a default block must rebuild in well under a second
## or two (it once took 100 s: duplicate corner points from Godot and SurfaceTool.generate_tangents).
## Run: godot --headless --path D:/SurfForge -s res://tests/engrave_speed_test.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [0, 0, 0]})
	var t := TextNode.new()
	ed.texts_root.add_child(t)
	t.from_dict({"position": [0, 8, 0], "pitch": -90.0})
	ed._rebuild_blocks()
	var polys := TextShape.convex_polygons(TextShape.spec(t.data))
	print("letter pieces: ", polys.size())
	var t0 := Time.get_ticks_msec()
	ed._select(t)
	ed._edit_prop("text_mode", "engrave")
	ed._rebuild_blocks()
	var ms := Time.get_ticks_msec() - t0
	print("engrave rebuild took %d ms, block pieces %d" % [ms, b.pieces.size()])
	print("ENGRAVE SPEED: ", "PASS" if ms < 3000 and b.pieces.size() > 50 else "FAIL")
	quit()
