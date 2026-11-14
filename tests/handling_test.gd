extends SceneTree
## Editor handling (0.5.4): top / bottom block handles in the 3D view, text staying on the face it was placed on while
## dragged (in the 3D view and a 2D view), typing and letter height staying fast, and the panel's position fields.
## Run: godot --path . --resolution 1600x900 -s res://tests/handling_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-64s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func mouse(pane: ViewPane, world: Vector3, pressed: bool, motion := false) -> void:
	var ev: InputEvent
	if motion:
		ev = InputEventMouseMotion.new()
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	else:
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
	ev.position = pane.camera.unproject_position(world)
	if not ed.pane_input(pane, ev) and motion:
		ed._input(ev) if ed.has_method("_input") else null
	ed._unhandled_input(ev)


func settle() -> void:
	await process_frame
	for i in 3:
		await physics_frame


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._new_map()
	for o in ed.ramps_root.get_children() + ed.entities_root.get_children():
		o.free()                                          # the starter ramp would sit over the top view's clicks
	ed.snap_enabled = false
	var persp: ViewPane = ed.panes[0]
	var cam := persp.camera as OrbitCamera
	cam.focus = Vector3(0, 4, 0)
	cam.distance = 50.0
	cam.yaw = deg_to_rad(30)
	cam.pitch = deg_to_rad(-20)
	cam._apply()
	var b := BlockNode.new()
	ed.blocks_root.add_child(b)
	b.from_dict({"position": [0, 0, 0], "size": [16, 8, 16]})
	ed._rebuild_blocks()
	ed._select(b)
	await settle()

	ed.set_gizmo_mode(TransformGizmo.Mode.SCALE)            # (side squares are part of Scale since 0.29.0)
	# top handle in the 3D view: drag it up 4 m
	var top: Array = b.face_handles()[3]                  # axis 1 (Y), + side
	check("handle 3 is the top one", (top[1] as Vector3).is_equal_approx(Vector3.UP))
	mouse(persp, top[0], true)
	mouse(persp, top[0] + Vector3(0, 4, 0), false, true)
	mouse(persp, top[0] + Vector3(0, 4, 0), false)
	check("top handle in the 3D view: 4 m taller", absf(b.size().y - 12.0) < 0.05, "(%.2f)" % b.size().y)
	var bottom: Array = b.face_handles()[2]
	mouse(persp, bottom[0], true)
	mouse(persp, bottom[0] + Vector3(0, -2, 0), false, true)
	mouse(persp, bottom[0] + Vector3(0, -2, 0), false)
	check("bottom handle in the 3D view: 2 m lower, top stays", absf(b.size().y - 14.0) < 0.05 and absf(b.global_position.y + 2.0) < 0.05,
		"(%.2f, base %.2f)" % [b.size().y, b.global_position.y])

	ed.set_gizmo_mode(TransformGizmo.Mode.MOVE)
	# text on the +X face (x = 8)
	var t := TextNode.new()
	ed.texts_root.add_child(t)
	t.from_dict({"text": "HI", "height": 2.0, "depth": 0.3, "position": [8.005, 5, 3], "yaw": 90.0})
	ed._select(t)
	await settle()
	var face: Dictionary = ed._text_face(t)
	check("text knows the face it's on", not face.is_empty() and (face["normal"] as Vector3).is_equal_approx(Vector3.RIGHT))
	# drag it in the 3D view, aiming at a point off the face (out and up): it must stay on the face
	var start: Vector3 = t.center()
	mouse(persp, start, true)
	mouse(persp, start + Vector3(0, 2, -3), false, true)
	mouse(persp, start + Vector3(0, 2, -3), false)
	var c: Vector3 = t.center()
	check("dragged in the 3D view: still on the face (x stays 8)", absf(t.global_position.x - 8.005) < 0.01, "(x %.3f)" % t.global_position.x)
	check("...and it moved along the face", c.distance_to(start) > 1.0, "(moved %.2f)" % c.distance_to(start))
	# drag in the top view (X/Z): the X part would pull it off the face
	var topv: ViewPane = ed.panes[1]
	topv.frame(Vector3(0, 0, 0), 40.0)
	await settle()                                        # (physics picks up moved bodies on its next frame)
	start = t.center()
	mouse(topv, start, true)
	mouse(topv, start + Vector3(6, 0, -2), false, true)
	mouse(topv, start + Vector3(6, 0, -2), false)
	check("dragged in the top view: stays on the face, slides along Z", absf(t.global_position.x - 8.005) < 0.01
		and absf(t.center().z - (start.z - 2.0)) < 0.05, "(x %.3f, z %.2f)" % [t.global_position.x, t.center().z])
	# can't be dragged off the face's edge
	await settle()
	start = t.center()
	mouse(topv, start, true)
	mouse(topv, start + Vector3(0, 0, -40), false, true)
	mouse(topv, start + Vector3(0, 0, -40), false)
	var half := t.local_box.size.x * 0.5
	check("can't be dragged past the face's edge (the whole text stays on)", absf(t.center().z - (-8.0 + half)) < 0.05,
		"(z %.2f, edge at %.2f)" % [t.center().z, -8.0 + half])

	# position fields: Across / Up for text on a face; typing 0 centers it
	await settle()
	ed._process(0.0)
	check("panel shows Across / Up for text on a face", ed._pos_box.visible and ed._pos_labels[0].text == "Across")
	ed._pos_fields[0].typed.emit(0.0)
	ed._pos_fields[1].typed.emit(0.0)
	ed._process(0.0)
	var fc: Vector3 = ed._text_face(t)["center"]
	var mid: Vector3 = t.global_transform * Vector3(t.local_box.get_center().x, t.local_box.get_center().y, 0)
	check("typing 0 / 0 centers it on the face", mid.distance_to(fc) < 0.02, "(%.3f m off)" % mid.distance_to(fc))
	ed._pos_fields[1].changed_by.emit(1.5)
	mid = t.global_transform * Vector3(t.local_box.get_center().x, t.local_box.get_center().y, 0)
	check("dragging the Up field moves it 1.5 m up the face", absf(mid.y - fc.y - 1.5) < 0.02)
	ed._select(b)
	ed._process(0.0)
	check("a block shows X / Y / Z", ed._pos_labels[0].text == "X" and ed._pos_fields[2].visible)
	var bx: float = b.center().x
	ed._pos_fields[0].changed_by.emit(-10.0)
	check("dragging X moves the block", absf(b.center().x - (bx - 10.0)) < 0.01)

	# typing and letter height are quick
	ed._select(t)
	var worst := 0
	for s in ["HI ", "HI T", "HI TH", "HI THE", "HI THERE\nSECOND LINE OF TEXT"]:
		var t0 := Time.get_ticks_msec()
		ed._edit_prop("text_text", s)
		worst = maxi(worst, Time.get_ticks_msec() - t0)
	check("typing: every key under 60 ms", worst < 60, "(worst %d ms)" % worst)
	worst = 0
	for h in [2.2, 2.4, 2.6]:
		var t0 := Time.get_ticks_msec()
		ed._edit_prop("text_height", h)
		worst = maxi(worst, Time.get_ticks_msec() - t0)
	check("letter height: every step under 60 ms", worst < 60, "(worst %d ms)" % worst)
	for i in 120:
		await process_frame
		if not t.pieces_pending():
			break
	check("exact collision arrives from the worker thread", not t.pieces_pending() and t._body.get_child_count() > 2,
		"(%d shapes)" % t._body.get_child_count())
	print("HANDLING: ", "PASS" if ok else "FAIL")
	quit()
