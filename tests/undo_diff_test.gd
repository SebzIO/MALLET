extends SceneTree
## Undo and redo rebuild only what the step changed (0.19.0): every step back and forward gives exactly the map that
## was there, objects the step didn't touch stay the very same objects (nothing re-made), and a big map's undo is
## quick (it reloaded the whole map: 18 s on a 76,000-cube map).
## Run: godot --path . --resolution 1280x720 -s res://tests/undo_diff_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var w := CubeWorld.new()
	ShapeGen.place(w, ShapeGen.generate("sphere", {"r": 10.0}, -3, 2)["cells"], Vector3i.ZERO, "")
	var map := {"blocks": [], "cube_models": [{"position": [0.0, 10.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}],
		"ramps": [{"points": [[0, 50, 0], [30, 40, 0], [60, 30, 0]]}, {"points": [[0, 50, 40], [30, 40, 40], [60, 30, 40]]}],
		"lights": [{"kind": "point", "position": [5.0, 20.0, 5.0], "color": "ffaa00", "energy": 2.0, "range": 10.0}]}
	for i in 5:
		map["blocks"].append({"shape": "box", "position": [20.0 + i * 6.0, 0.0, 0.0], "size": [4.0, 2.0, 4.0]})
	ed._load_dict(map)
	await process_frame
	ed._undo.clear()
	var states := [ed._map_dict()]
	var cube_node: CubeModelNode = ed.cube_models_root.get_child(0)
	var steps := {
		"move a ramp": func(): ed.ramps_root.get_child(0).position += Vector3(3, 1, 0); ed.ramps_root.get_child(0).rebuild(),
		"add a block": func(): var b := BlockNode.new(); ed.blocks_root.add_child(b); b.from_dict({"shape": "box", "position": [90.0, 0.0, 0.0], "size": [2.0, 2.0, 2.0]}),
		"delete two blocks": func(): for i in 2: var b = ed.blocks_root.get_child(1); ed.blocks_root.remove_child(b); b.queue_free(),
		"rename and hide a light": func(): var l = ed.lights_root.get_child(0); l.set_meta("name", "Lamp"); l.set_meta("hidden", true); l.visible = false,
		"change the cube object": func(): cube_node.world.set_cell(Vector3i(400, 0, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex()),
		"reorder ramps": func(): ed.ramps_root.move_child(ed.ramps_root.get_child(1), 0),
		"unhide the light": func(): var l = ed.lights_root.get_child(0); l.remove_meta("hidden"); l.visible = true,
	}
	for label in steps:
		ed._checkpoint()
		steps[label].call()
		await process_frame
		states.append(ed._map_dict())
	var n := states.size() - 1
	var undo_ok := true
	var bad := ""
	var kept := true
	var slowest := 0.0
	for i in range(n, 0, -1):
		var t := Time.get_ticks_usec()
		ed.undo()
		slowest = maxf(slowest, (Time.get_ticks_usec() - t) / 1000.0)
		await process_frame
		if ed._map_dict() != states[i - 1]:
			undo_ok = false
			bad = "undo of step %d (%s)" % [i, steps.keys()[i - 1]]
			break
		if not (cube_node in ed._all_objects()):          # (changed or not, the cube object is never re-made)
			kept = false
	check("every undo gives exactly the map before that step", undo_ok, bad)
	check("...and the cube object stays the same object throughout (nothing re-made)", kept)
	var redo_ok := true
	for i in range(1, n + 1):
		ed.redo()
		await process_frame
		if ed._map_dict() != states[i]:
			redo_ok = false
			bad = "redo of step %d (%s)" % [i, steps.keys()[i - 1]]
			break
	check("every redo gives exactly the map after that step", redo_ok, bad)
	check("...and a step is quick (%d cubes)" % cube_node.world.count(), slowest < 300.0, "(slowest %.0f ms)" % slowest)
	print("undo_diff_test: ", "PASS" if ok else "FAIL")
	quit()
