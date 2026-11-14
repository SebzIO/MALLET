extends SceneTree
## Particle areas (0.23.3): changing the effect (Sparks -> Rain) keeps the area you made (and your own color); a
## particle effect has side squares like zones and blocks, and dragging one stretches the area from that side.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/particle_area_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame


func mouse(pane: ViewPane, kind: String, at: Vector2) -> void:
	var e: InputEvent
	if kind == "move":
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = kind == "down"
		mb.position = at
		e = mb
	ed.pane_input(pane, e)


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await frames(2)
	ed.welcome.hide()
	ed._load_dict({"particles": [{"preset": "sparks", "position": [0.0, 5.0, 0.0], "area": [0.1, 0.1, 0.1]}]})
	await frames(2)
	var pn: ParticleNode = ed.particles_root.get_child(0)
	ed._select(pn)
	ed.set_gizmo_mode(TransformGizmo.Mode.SCALE)            # (side squares are part of Scale since 0.29.0)
	await frames(1)
	ed._edit_prop("fx_area_x", 12.0)
	ed._edit_prop("fx_area_z", 6.0)
	ed._edit_prop("fx_own_color", true)
	var col := String(pn.data["color"])
	ed._edit_prop("fx_preset", "rain")
	var a: Array = pn.data["area"]
	check("Sparks -> Rain keeps the area you set (12 x 0.1 x 6)", pn.data["preset"] == "rain" and is_equal_approx(a[0], 12.0)
		and is_equal_approx(a[2], 6.0), str(a))
	check("...and your own color", String(pn.data["color"]) == col and col != "")
	# side squares
	var hs: Array = pn.face_handles()
	check("a particle effect has six side squares on its area", hs.size() == 6 and (hs[1][0] as Vector3).is_equal_approx(Vector3(6, 5, 0)), str(hs[1][0]))
	var top: ViewPane = null
	for p in ed.panes:
		if p.is_ortho() and absf(p.camera.global_basis.z.y) > 0.9:
			top = p
	top.frame(Vector3(0, 5, 0), 40.0)
	ed.snap_enabled = false
	await frames(3)
	var from: Vector2 = top.camera.unproject_position(hs[1][0])
	var to: Vector2 = top.camera.unproject_position(hs[1][0] + Vector3(4, 0, 0))
	mouse(top, "down", from)
	for i in 6:
		mouse(top, "move", from.lerp(to, (i + 1) / 6.0))
		await process_frame
	mouse(top, "up", to)
	await frames(1)
	a = pn.data["area"]
	var left := pn.global_position.x - float(a[0]) * 0.5
	check("dragging the +x square 4 m stretches the area to 16 m", absf(float(a[0]) - 16.0) < 0.3, str(a))
	check("...and the -x side stays where it was", absf(left - (-6.0)) < 0.3, "(left side at %.2f)" % left)
	var d := ParticleNode.resized(pn.to_dict(), 1, -1.0, -50.0)
	check("an area can't be dragged smaller than 0.1 m", is_equal_approx(float(d["area"][1]), ParticleNode.MIN_AREA))
	ed.undo()
	await frames(1)
	check("undo puts the area back", absf(float(pn.data["area"][0]) - 12.0) < 0.01 if is_instance_valid(pn) else
		absf(float(ed.particles_root.get_child(0).data["area"][0]) - 12.0) < 0.01)
	print("particle_area_test: ", "PASS" if ok else "FAIL")
	quit()
