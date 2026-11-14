extends SceneTree
## Camera shots in the editor (0.30.0): keys added from the 3D view, number fields, reorder / delete, drag in a view,
## saved with the map and read back, undo / redo, co-editing op, and both exporters ignoring shots (the VMF text and
## the SurfsUp scene are the same with and without them, and neither carries a shot's name).
##   godot --path . --resolution 1600x900 -s res://tests/shots_test.gd -- <existing out folder>
## (Opens a MALLET window.)

const MARK := "ZZShotNameMarker"
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else OS.get_user_data_dir()
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed.show_shots(true)
	await process_frame
	var sp: ShotPanel = ed.shot_panel
	var cam: OrbitCamera = ed.panes[0].camera
	check(sp.visible and ed.shots.is_empty(), "View > Camera shots opens the strip; a new map has no shots")
	# 1. add keys from the 3D view
	var undo0: int = ed._undo.size()
	cam.set_view(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), deg_to_rad(30), 0)), Vector3(0, 150, 100)), 60.0)
	sp.add_key_here()
	check(ed.shots.size() == 1 and sp.shot_keys().size() == 1, "Add key here with no shot makes Shot 1 with one key")
	var k0: Dictionary = sp.shot_keys()[0]
	check(CameraPath.key_pos(k0).distance_to(Vector3(0, 150, 100)) < 1e-3 and absf(float(k0["yaw"]) - 30.0) < 0.01 \
		and absf(float(k0["pitch"]) + 20.0) < 0.01 and absf(float(k0["fov"]) - 60.0) < 0.01, "the key is the 3D view's camera (position, yaw, pitch, FOV)")
	cam.set_view(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-10), deg_to_rad(80), 0)), Vector3(80, 130, 60)), 70.0)
	sp.add_key_here()
	cam.set_view(Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(140), 0)), Vector3(120, 110, -40)), 70.0)
	sp.add_key_here()
	check(sp.shot_keys().size() == 3 and sp.key == 2, "three keys, the newest selected")
	check(ed._undo.size() >= undo0 + 4, "each step is undoable (%d undo steps)" % (ed._undo.size() - undo0))
	# 2. the number fields
	sp.select_key(1)
	(sp._f["fov"] as DragNumber).typed.emit(45.0)
	(sp._f["dur"] as DragNumber).typed.emit(3.5)
	(sp._f["x"] as DragNumber).drag_started.emit()
	(sp._f["x"] as DragNumber).changed_by.emit(2.5)
	var k1: Dictionary = sp.shot_keys()[1]
	check(absf(float(k1["fov"]) - 45.0) < 1e-4 and absf(float(k1["dur"]) - 3.5) < 1e-4 and absf(float(k1["pos"][0]) - 82.5) < 1e-3,
		"typed FOV / time and a dragged X land on the key")
	check(absf(sp.path().duration() - 5.5) < 1e-3, "the shot lasts the keys' times (%.2f s)" % sp.path().duration())
	# 3. reorder and delete, undo / redo
	sp.move_key(-1)
	check(absf(float(sp.shot_keys()[0]["fov"]) - 45.0) < 1e-4 and sp.key == 0, "move key earlier")
	ed.undo()
	check(absf(float(sp.shot_keys()[1]["fov"]) - 45.0) < 1e-4, "undo puts it back")
	ed.redo()
	check(absf(float(sp.shot_keys()[0]["fov"]) - 45.0) < 1e-4, "redo moves it again")
	ed.undo()
	sp.select_key(2)
	sp.delete_key()
	check(sp.shot_keys().size() == 2, "delete key")
	ed.undo()
	check(sp.shot_keys().size() == 3, "undo brings the key back")
	# 4. dragging a key in the Top view
	var top: ViewPane = ed.panes[1]
	await process_frame
	var kp := CameraPath.key_pos(sp.shot_keys()[2])
	var at: Vector2 = top.camera.unproject_position(kp)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	check(ed.pane_input(top, press), "a press on a key in the Top view takes it")
	var move := InputEventMouseMotion.new()
	move.position = at + Vector2(40, 0)
	ed.pane_input(top, move)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = at + Vector2(40, 0)
	ed.pane_input(top, rel)
	var moved := CameraPath.key_pos(sp.shot_keys()[2])
	check(moved.x > kp.x + 1.0 and absf(moved.y - kp.y) < 1e-3 and absf(moved.z - kp.z) < 1e-3, "dragging moves the key across the Top view only (%s -> %s)" % [kp, moved])
	ed.undo()
	check(CameraPath.key_pos(sp.shot_keys()[2]).distance_to(kp) < 1e-3, "one undo takes the drag back")
	# 5. preview: the time bar puts the 3D camera on the path
	sp.scrub_to(sp.path().key_time(1))
	check(cam.global_position.distance_to(CameraPath.key_pos(sp.shot_keys()[1])) < 1e-3 and absf(cam.fov - float(sp.shot_keys()[1]["fov"])) < 1e-3,
		"the time bar at key 2 shows key 2 in the 3D view")
	sp.toggle_play()
	for i in 10:
		await process_frame
	check(sp.playing and sp.time > 0.0, "Play runs the shot (%.2f s in)" % sp.time)
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	check(not sp.playing, "Esc stops playing")
	# 6. a second shot, look-at, rename
	sp.new_shot()
	cam.set_view(Transform3D(Basis(), Vector3(0, 120, 50)), 70.0)
	sp.add_key_here()
	cam.set_view(Transform3D(Basis(), Vector3(40, 120, 50)), 70.0)
	sp.add_key_here()
	sp._name_edit.text = MARK
	sp._rename()
	sp._set_look("point")
	check(ed.shots.size() == 2 and ed.shots[1]["name"] == MARK and ed.shots[1]["look"] == "point", "a second shot, renamed, looking at a point")
	# 7. save and open again
	var path := ProjectSettings.globalize_path("user://test_maps/shots_test.mallet")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var before: Array = ed.shots.duplicate(true)
	ed.save_map(path)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved is Dictionary and saved.has("shots") and (saved["shots"] as Array).size() == 2, "the .mallet file has the shots")
	ed._new_map()
	check(ed.shots.is_empty() and sp.shot_keys().is_empty(), "File > New: no shots")
	ed.load_map(path)
	check(JSON.stringify(ed.shots) == JSON.stringify(JSON.parse_string(JSON.stringify(before))), "opening the map brings the shots back exactly")
	check(not ed.has_unsaved_changes(), "a map just opened has no unsaved changes")
	# 8. co-editing: a shots op replaces them, without an undo step
	var u: int = ed._undo.size()
	ed._co_shots_op({"act": "shots", "shots": [CameraPath.new_shot("From a co-editor")]})
	check(ed.shots.size() == 1 and ed.shots[0]["name"] == "From a co-editor" and ed._undo.size() == u, "a co-editor's shots arrive (no undo step here)")
	ed.load_map(path)
	# 9. the exporters ignore shots
	var with: Dictionary = ed._map_dict()
	var without: Dictionary = with.duplicate(true)
	without.erase("shots")
	check(with.has("shots"), "the map data has the shots")
	var vmf_a := VmfExporter.new().build(with)
	var vmf_b := VmfExporter.new().build(without)
	check(vmf_a != "" and vmf_a == vmf_b, "CS:S: the .vmf is the same with and without shots")
	check(not vmf_a.contains(MARK), "CS:S: no shot name in the .vmf")
	var sa := SurfsUpExporter.build_scene(with, "sf_shots_test")
	var sb := SurfsUpExporter.build_scene(without, "sf_shots_test")
	var da := _describe(sa)
	var db := _describe(sb)
	sa.free()
	sb.free()
	check(da == db, "SurfsUp: the scene is the same with and without shots (%d nodes)" % da.count("\n"))
	var maps := out.path_join("shots_maps")
	DirAccess.make_dir_recursive_absolute(maps)
	var err := SurfsUpExporter.export_pack(with, "sf_shots_test", maps)
	var pck := FileAccess.get_file_as_bytes(maps.path_join("sf_shots_test.pck"))
	check(err == "" and pck.size() > 0, "SurfsUp export works with shots in the map (%s)" % (err if err != "" else "%d bytes" % pck.size()))
	check(pck.get_string_from_ascii().find(MARK) < 0 and _find(pck, MARK.to_ascii_buffer()) < 0, "SurfsUp: no shot name in the .pck")
	print("shots_test: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)


func _describe(n: Node, depth := 0) -> String:
	var s := "%s%s <%s>" % [" ".repeat(depth), n.name, n.get_class()]
	if n is Node3D:
		s += " " + str((n as Node3D).transform)
	s += "\n"
	for c in n.get_children():
		s += _describe(c, depth + 1)
	return s


func _find(hay: PackedByteArray, needle: PackedByteArray) -> int:
	for i in hay.size() - needle.size():
		if hay[i] == needle[0] and hay.slice(i, i + needle.size()) == needle:
			return i
	return -1
