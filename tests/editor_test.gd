extends SceneTree
## Editor test: four views, moving a whole ramp with a real mouse drag, nudge/rotate, solid ramps, undo,
## platforms and a timed run. Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/editor_test.gd -- <out>

var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name, "   | ", ed._status.text.strip_edges())


func mouse(pane: ViewPane, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	pane._gui_input(e)


func motion(pane: ViewPane, pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	pane._gui_input(e)


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	ed._unhandled_input(e)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await shot("e01_quad_view")

	# drag the whole ramp 40 m along X in the top view, using real mouse events on its body
	var r: RampNode = ed.selected
	var top: ViewPane = ed.panes[1]
	var c0 := r.center()
	var c0s := top.camera.unproject_position(r.points[0].lerp(r.points[1], 0.5) + Vector3(0, 0, 3))   # on a face, not a handle
	var px_per_m := top.size.y / top.camera.size
	mouse(top, c0s, true)
	for i in 10:
		motion(top, c0s + Vector2(px_per_m * 40.0 * (i + 1) / 10.0, 0))
	mouse(top, c0s + Vector2(px_per_m * 40.0, 0), false)
	print("ramp center moved by ", (r.center() - c0).snapped(Vector3.ONE * 0.1), " (expected ~(40, 0, 0))")

	# nudge up twice (PgUp) and rotate 15 degrees
	key(KEY_PAGEUP); key(KEY_PAGEUP); key(KEY_BRACKETRIGHT)
	print("after nudge+rotate center ", r.center().snapped(Vector3.ONE * 0.1))
	# make it solid with a base
	ed._edit_prop("solid", true)
	ed._edit_prop("base_depth", 12.0)
	await shot("e02_moved_rotated_solid")

	# undo everything back to the start
	var before: int = ed._undo.size()
	for i in before:
		ed.undo()
	print("after %d undos: center %s solid %s" % [before, (ed.ramps_root.get_child(0) as RampNode).center().snapped(Vector3.ONE * 0.1), (ed.ramps_root.get_child(0) as RampNode).solid])
	for i in before:
		ed.redo()

	ed._toggle_views()
	await shot("e03_single_view")
	ed._toggle_views()

	# recolor the selected ramp: it must show its real color (outline, not tint)
	ed._select(ed.ramps_root.get_child(0))
	ed._edit_prop("color", Color(0.9, 0.2, 0.6))
	await shot("e03b_recolour_selected")
	# Space over the top view maximizes it, Space again restores four views
	var topv: ViewPane = ed.panes[1]
	root.warp_mouse(topv.get_global_rect().get_center())
	await process_frame
	key(KEY_SPACE)
	print("after Space: visible panes ", ed.panes.filter(func(x): return x.visible).size(), " -> ", ed._status.text.strip_edges())
	await shot("e03c_space_top")
	key(KEY_SPACE)
	print("after Space again: visible panes ", ed.panes.filter(func(x): return x.visible).size())

	# timed run: play, then teleport the player off the start (timer starts) and onto the finish (timer stops)
	ed._play_clicked()
	await physics_frame
	var p: SUCC = ed.play.player
	print("spawned at ", p.global_position.snapped(Vector3.ONE * 0.1), " state ", ed.play.run_state)
	await shot("e04_play_on_start")
	# prehop attempt: 900 u/s on the platform must be capped to 400
	p.velocity = Vector3(900.0 / 39.37, 0, 0)
	for i in 2: await physics_frame
	print("prespeed on start: %d u/s (cap 400)" % roundi(Vector2(p.velocity.x, p.velocity.z).length() * 39.37))
	p.teleport(Transform3D(Basis(), Vector3(0, 140, 0)))
	for i in 30: await physics_frame
	print("left start: state ", ed.play.run_state, " time %.2f" % ed.play.run_time)
	var fin: EntityNode = ed._find_entity("finish")
	p.teleport(Transform3D(Basis(), fin.global_position + Vector3(0, 1, 0)))
	p.velocity = Vector3.ZERO
	for i in 10: await physics_frame
	print("on finish: state ", ed.play.run_state, " time %.2f best %.2f" % [ed.play.run_time, ed.play.best_time])
	await shot("e05_finished")
	ed.play.stop()
	await shot("e06_back")
	quit()
