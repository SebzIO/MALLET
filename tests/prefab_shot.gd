extends SceneTree
## Screenshot of every starter prefab in a row, at dusk so the lights and lava show: prefabs.png
## Run: godot --path . --resolution 1600x900 -s res://tests/prefab_shot.gd -- <out>


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	var x := -75.0
	for p in Prefabs.list():
		var objs: Array = ed.place_prefab(p["path"])
		var mid := Vector3.ZERO
		for o in objs:
			mid += o.center()
		mid /= objs.size()
		for o in objs:
			o.translate_by(Vector3(x - mid.x, -mid.y, -300.0 - mid.z) + Vector3(0, 6, 0))
		x += 25.0
	ed._rebuild_blocks()
	var floor_b := BlockNode.new()
	ed.blocks_root.add_child(floor_b)
	floor_b.from_dict({"position": [0, -2, -300], "size": [200, 2, 60], "material": "Grass004"})
	ed._rebuild_blocks()
	ed.maximise_pane(ed.panes[0])
	ed._select(null)
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = Vector3(0, 6, -300)
	cam.distance = 95.0
	cam.yaw = deg_to_rad(0)
	cam.pitch = deg_to_rad(-14)
	cam._apply()
	for i in 20:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/prefabs.png")
	print("PREFAB SHOT: done")
	quit()
