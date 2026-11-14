extends SceneTree
## The Move / Rotate / Scale gizmo (0.29.0): drags every kind of handle on every kind of object through the views'
## own mouse input, checks what changed, that each drag is one undo step and that undo puts it back. Also: the
## mode keys (W, 1, 2, 3), hover highlight, the ortho views' handles, locked objects and multi-selection.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/gizmo_test.gd -- <out folder>

var ok := true
var ed
var pane: ViewPane


func check(label: String, good: bool, detail := "") -> void:
	print("%-78s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame


func mouse(p: ViewPane, kind: String, at: Vector2) -> void:
	var e: InputEvent
	if kind == "move":
		var mm := InputEventMouseMotion.new()
		mm.position = at
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mm
	elif kind == "hover":
		var hm := InputEventMouseMotion.new()
		hm.position = at
		e = hm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = kind == "down"
		mb.position = at
		e = mb
	ed.pane_input(p, e)


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


## Press on handle `id`, move through `steps` points along the path to `to`, let go.
func drag_to(p: ViewPane, id: String, to: Vector2) -> bool:
	var from: Vector2 = ed.gizmo.grab_point(p, id)
	if from.x < 0:
		print("    (no handle %s in %s)" % [id, ViewPane.NAMES[p.kind]])
		return false
	mouse(p, "down", from)
	for i in 8:
		mouse(p, "move", from.lerp(to, (i + 1) / 8.0))
		await process_frame
	mouse(p, "up", to)
	await frames(1)
	return true


## Drag a handle by a world-space offset of the 3D point under its grab point (axes and planes).
func drag_by(p: ViewPane, id: String, offset: Vector3) -> bool:
	var from: Vector2 = ed.gizmo.grab_point(p, id)
	var c: Vector3 = ed.gizmo.center()
	var world := c
	for h in ed.gizmo.handles(p):
		if h["id"] == id:
			var r := p.ray(from)
			if h["kind"] == "axis":
				world = c + (h["axis"] as Vector3) * TransformGizmo._line_param(r[0], r[1], c, h["axis"])
			elif h["kind"] == "plane":
				world = Plane(h["axis"], c).intersects_ray(r[0], r[1])
	if ed.gizmo.pick(p, from) != id:
		print("    (%s grabs %s)" % [id, ed.gizmo.pick(p, from)])
	return await drag_to(p, id, p.camera.unproject_position(world + offset))


## Drag a ring handle round the gizmo's center by `deg` on screen (positive: counterclockwise as you see it).
func drag_ring(p: ViewPane, id: String, deg: float) -> bool:
	var from: Vector2 = ed.gizmo.grab_point(p, id)
	if from.x < 0:
		print("    (no ring %s)" % id)
		return false
	var c2: Vector2 = p.camera.unproject_position(ed.gizmo.center())
	mouse(p, "down", from)
	for i in 8:
		mouse(p, "move", c2 + (from - c2).rotated(-deg_to_rad(deg) * (i + 1) / 8.0))
		await process_frame
	mouse(p, "up", c2 + (from - c2).rotated(-deg_to_rad(deg)))
	await frames(1)
	return true


func nth(root: Node, i: int) -> Node3D:
	return root.get_child(i)


func focus(o: Node3D, mode: int, radius := 30.0) -> void:
	ed._select(o)
	ed.set_gizmo_mode(mode)
	pane.frame(o.center(), radius)
	await frames(3)


## One drag = one undo step, and undo gives back the state from before.
func undo_check(label: String, root: Node, i: int, before: Dictionary, steps_before: int) -> void:
	check(label + ": one undo step", ed._undo.size() == steps_before + 1, "%d -> %d" % [steps_before, ed._undo.size()])
	ed.undo()
	await frames(2)
	var now: Dictionary = nth(root, i).to_dict()
	check(label + ": undo puts it back", str(now) == str(before))


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await frames(2)
	ed.welcome.hide()
	ed._load_dict({
		"blocks": [{"position": [0.0, 0.0, 0.0], "size": [16.0, 8.0, 16.0]}, {"position": [300.0, 0.0, 0.0], "size": [8.0, 8.0, 8.0]}],
		"entities": [{"kind": "teleport", "position": [100.0, 10.0, 0.0], "size": [12.0, 8.0, 12.0], "number": 2},
			{"kind": "booster", "position": [100.0, 10.0, 100.0], "size": [8.0, 4.0, 8.0], "pitch": 20.0}],
		"lights": [{"kind": "spot", "position": [200.0, 10.0, 0.0], "pitch": -60.0, "range": 30.0},
			{"kind": "strip", "position": [200.0, 10.0, 100.0], "length": 4.0}],
		"particles": [{"preset": "fire", "position": [0.0, 10.0, 200.0], "area": [2.0, 0.5, 2.0]}],
		"texts": [{"text": "GO", "position": [100.0, 10.0, 200.0]}],
		"props": [{"source": "", "position": [200.0, 10.0, 200.0], "size": 1.0}],
		"ramps": [{"points": [[-20.0, 40.0, 300.0], [0.0, 30.0, 300.0], [20.0, 20.0, 300.0]]}],
	})
	await frames(3)
	pane = ed.panes[0]
	ed.maximise_pane(pane)
	await frames(3)
	ed.snap_enabled = true
	ed.snap_step = 4.0
	var M := TransformGizmo.Mode

	# ---- keys
	var b: BlockNode = nth(ed.blocks_root, 0)
	await focus(b, M.MOVE)
	await key(KEY_W)
	check("W switches Move -> Rotate", ed.gizmo.mode == M.ROTATE)
	await key(KEY_W)
	check("W again -> Scale (and the toolbar shows it)", ed.gizmo.mode == M.SCALE and ed._fields["gizmo_2"].button_pressed)
	await key(KEY_1)
	check("1 -> Move", ed.gizmo.mode == M.MOVE and ed._fields["gizmo_0"].button_pressed)
	await key(KEY_2)
	check("2 -> Rotate", ed.gizmo.mode == M.ROTATE)
	await key(KEY_3)
	check("3 -> Scale", ed.gizmo.mode == M.SCALE)

	var out_dir: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	for m in 3:                                          # pictures of the three gizmos, for the eye
		await focus(b, m, 20.0)
		await frames(2)
		if out_dir != "":
			root.get_texture().get_image().save_png(out_dir.path_join("gizmo_%s.png" % TransformGizmo.MODE_NAMES[m].to_lower()))

	# ---- move a block
	await focus(b, M.MOVE)
	var ids: Array = ed.gizmo.handles(pane).map(func(h): return h["id"])
	check("Move shows 3 arrows, plane squares and the dot", ids.has("m0") and ids.has("m1") and ids.has("m2") and ids.has("p1") and ids.has("c"), str(ids))
	mouse(pane, "hover", ed.gizmo.grab_point(pane, "m0"))
	check("hovering the X arrow lights it", ed.gizmo.hover == "m0", ed.gizmo.hover)
	var before: Dictionary = b.to_dict()
	var n0: int = ed._undo.size()
	await drag_by(pane, "m0", Vector3(8, 0, 0))
	var p: Array = b.data["position"]
	check("X arrow: moved 8 m along X only (grid 4)", is_equal_approx(p[0], 8.0) and is_equal_approx(p[1], 0.0) and is_equal_approx(p[2], 0.0), str(p))
	await undo_check("X arrow", ed.blocks_root, 0, before, n0)
	b = nth(ed.blocks_root, 0)
	await focus(b, M.MOVE)
	n0 = ed._undo.size()
	await drag_by(pane, "m1", Vector3(0, 12, 0))
	p = b.data["position"]
	check("Y arrow: moved 12 m up", is_equal_approx(p[1], 12.0) and is_equal_approx(p[0], 0.0), str(p))
	await undo_check("Y arrow", ed.blocks_root, 0, before, n0)
	b = nth(ed.blocks_root, 0)
	await focus(b, M.MOVE)
	n0 = ed._undo.size()
	await drag_by(pane, "p1", Vector3(8, 0, -8))
	p = b.data["position"]
	check("XZ square: moved across the ground, height kept", is_equal_approx(p[0], 8.0) and is_equal_approx(p[2], -8.0) and is_equal_approx(p[1], 0.0), str(p))
	await undo_check("XZ square", ed.blocks_root, 0, before, n0)

	# ---- rotate a block
	b = nth(ed.blocks_root, 0)
	await focus(b, M.ROTATE)
	ids = ed.gizmo.handles(pane).map(func(h): return h["id"])
	check("Rotate shows the ball, three rings and the view ring", ids.has("ball") and ids.has("r0") and ids.has("r1") and ids.has("r2") and ids.has("rv"), str(ids))
	var c0: Vector3 = b.center()
	var xdir0: Vector2 = pane.camera.unproject_position(c0 + b.global_basis.x * 6.0) - pane.camera.unproject_position(c0)
	n0 = ed._undo.size()
	await drag_ring(pane, "r1", 30.0)
	var yaw := float(b.data["yaw"])
	check("Y ring: turned 30° (snapped to 15° steps)", is_equal_approx(absf(yaw), 30.0), str(yaw))
	var xdir1: Vector2 = pane.camera.unproject_position(c0 + b.global_basis.x * 6.0) - pane.camera.unproject_position(c0)
	check("...the way the mouse went round", signf(xdir0.angle_to(xdir1)) == signf(-1.0), "%.1f°" % rad_to_deg(xdir0.angle_to(xdir1)))
	check("...about its middle", b.center().is_equal_approx(c0), str(b.center()))
	await undo_check("Y ring", ed.blocks_root, 0, before, n0)
	b = nth(ed.blocks_root, 0)
	await focus(b, M.ROTATE)
	n0 = ed._undo.size()
	await drag_ring(pane, "r0", 45.0)
	check("X ring: the block tilts (pitch)", absf(float(b.data["pitch"])) > 10.0, "pitch %.1f roll %.1f" % [b.data["pitch"], b.data["roll"]])
	check("...about its middle", b.center().distance_to(c0) < 0.01, str(b.center()))
	await undo_check("X ring", ed.blocks_root, 0, before, n0)
	b = nth(ed.blocks_root, 0)
	await focus(b, M.ROTATE)
	n0 = ed._undo.size()
	await drag_ring(pane, "rv", 30.0)
	var bb: Basis = b.global_basis
	check("view ring: turned about the line of sight", absf(rad_to_deg(bb.get_rotation_quaternion().get_angle()) - 30.0) < 0.5,
		"%.1f°" % rad_to_deg(bb.get_rotation_quaternion().get_angle()))
	await undo_check("view ring", ed.blocks_root, 0, before, n0)

	# ---- scale a block
	b = nth(ed.blocks_root, 0)
	await focus(b, M.SCALE)
	ids = ed.gizmo.handles(pane).map(func(h): return h["id"])
	check("Scale shows 3 cube handles, plane squares and the middle square", ids.has("s0") and ids.has("s1") and ids.has("s2") and ids.has("q1") and ids.has("u"), str(ids))
	n0 = ed._undo.size()
	var L: float = ed.gizmo.length(pane)
	await drag_by(pane, "s0", Vector3(L * 0.9, 0, 0))
	var sz: Array = b.data["size"]
	check("X cube: width doubled to 32 m on the grid, the rest kept", is_equal_approx(sz[0], 32.0) and is_equal_approx(sz[1], 8.0) and is_equal_approx(sz[2], 16.0), str(sz))
	check("...about its middle", b.center().is_equal_approx(c0), str(b.center()))
	await undo_check("X cube", ed.blocks_root, 0, before, n0)
	b = nth(ed.blocks_root, 0)
	await focus(b, M.SCALE)
	n0 = ed._undo.size()
	var u0: Vector2 = ed.gizmo.grab_point(pane, "u")
	await drag_to(pane, "u", u0 + Vector2(104, 0))
	sz = b.data["size"]
	check("middle square: scaled evenly x2", is_equal_approx(sz[0], 32.0) and is_equal_approx(sz[1], 16.0) and is_equal_approx(sz[2], 32.0), str(sz))
	check("...about its middle", b.center().distance_to(c0) < 0.01, str(b.center()))
	await undo_check("middle square", ed.blocks_root, 0, before, n0)

	# ---- entities
	var tp: EntityNode = nth(ed.entities_root, 0)
	before = tp.to_dict()
	await focus(tp, M.MOVE)
	n0 = ed._undo.size()
	await drag_by(pane, "m1", Vector3(0, 8, 0))
	check("teleport: Y arrow moves it up 8 m", is_equal_approx(tp.position.y, 18.0), str(tp.position))
	await undo_check("teleport move", ed.entities_root, 0, before, n0)
	tp = nth(ed.entities_root, 0)
	await focus(tp, M.SCALE)
	n0 = ed._undo.size()
	await drag_by(pane, "s2", Vector3(0, 0, ed.gizmo.length(pane) * 0.9 * 0.5))
	check("teleport: Z cube makes it deeper (12 -> 16 or 20 m, on the grid)", tp.size.z > 12.5 and is_equal_approx(fmod(tp.size.z - 12.0, 4.0), 0.0), str(tp.size))
	await undo_check("teleport scale", ed.entities_root, 0, before, n0)
	var bo: EntityNode = nth(ed.entities_root, 1)
	before = bo.to_dict()
	await focus(bo, M.ROTATE)
	ids = ed.gizmo.handles(pane).map(func(h): return h["id"])
	check("booster: a yaw ring and a tilt ring, no roll", ids.has("r1") and ids.has("r0") and not ids.has("r2"), str(ids))
	n0 = ed._undo.size()
	await drag_ring(pane, "r0", 30.0)
	check("booster: the tilt ring changes its push pitch", not is_equal_approx(bo.pitch, 20.0), "%.1f" % bo.pitch)
	await undo_check("booster tilt", ed.entities_root, 1, before, n0)

	# ---- lights
	var spot: LightNode = nth(ed.lights_root, 0)
	before = spot.to_dict()
	await focus(spot, M.ROTATE)
	n0 = ed._undo.size()
	await drag_ring(pane, "r0", 30.0)
	check("spot light: the tilt ring aims it (pitch)", not is_equal_approx(float(spot.data["pitch"]), -60.0), str(spot.data["pitch"]))
	await undo_check("spot tilt", ed.lights_root, 0, before, n0)
	spot = nth(ed.lights_root, 0)
	await focus(spot, M.SCALE)
	n0 = ed._undo.size()
	u0 = ed.gizmo.grab_point(pane, "u")
	await drag_to(pane, "u", u0 + Vector2(104, 0))
	check("spot light: the middle square doubles its reach", is_equal_approx(float(spot.data["range"]), 60.0), str(spot.data["range"]))
	await undo_check("spot reach", ed.lights_root, 0, before, n0)
	var strip: LightNode = nth(ed.lights_root, 1)
	before = strip.to_dict()
	await focus(strip, M.SCALE, 15.0)
	n0 = ed._undo.size()
	await drag_by(pane, "s0", strip.global_basis.x.normalized() * ed.gizmo.length(pane) * 0.9)
	check("light strip: the X cube makes it longer", float(strip.data["length"]) > 6.0, str(strip.data["length"]))
	await undo_check("strip length", ed.lights_root, 1, before, n0)

	# ---- particles, text, prop
	var fx: ParticleNode = nth(ed.particles_root, 0)
	before = fx.to_dict()
	await focus(fx, M.SCALE, 10.0)
	n0 = ed._undo.size()
	await drag_by(pane, "s0", Vector3(ed.gizmo.length(pane) * 0.9, 0, 0))
	var area: Array = fx.data["area"]
	check("particles: the X cube widens the area x2", is_equal_approx(area[0], 4.0) and is_equal_approx(area[2], 2.0), str(area))
	await undo_check("particle area", ed.particles_root, 0, before, n0)
	var tx: TextNode = nth(ed.texts_root, 0)
	before = tx.to_dict()
	await focus(tx, M.ROTATE, 15.0)
	n0 = ed._undo.size()
	await drag_ring(pane, "r2", 30.0)
	check("text: the Z ring turns it", absf(float(tx.data["roll"])) > 5.0 or absf(float(tx.data["pitch"])) > 5.0,
		"p %.1f y %.1f r %.1f" % [tx.data["pitch"], tx.data["yaw"], tx.data["roll"]])
	await undo_check("text turn", ed.texts_root, 0, before, n0)
	tx = nth(ed.texts_root, 0)
	await focus(tx, M.SCALE, 15.0)
	n0 = ed._undo.size()
	u0 = ed.gizmo.grab_point(pane, "u")
	await drag_to(pane, "u", u0 + Vector2(104, 0))
	check("text: the middle square makes the letters twice as tall", is_equal_approx(float(tx.data["height"]), 8.0), str(tx.data["height"]))
	await undo_check("text size", ed.texts_root, 0, before, n0)
	var pr: PropNode = nth(ed.props_root, 0)
	before = pr.to_dict()
	await focus(pr, M.SCALE, 10.0)
	n0 = ed._undo.size()
	await drag_by(pane, "s1", Vector3(0, ed.gizmo.length(pane) * 0.9, 0))
	check("prop: any cube scales it evenly (x2)", is_equal_approx(pr.size, 2.0), str(pr.size))
	await undo_check("prop scale", ed.props_root, 0, before, n0)

	# ---- a ramp: its point, its turn, its stretch
	var rp: RampNode = nth(ed.ramps_root, 0)
	before = rp.to_dict()
	await focus(rp, M.MOVE, 40.0)
	ed.selected_point = 2
	await frames(1)
	check("ramp point picked: the Move gizmo sits on it", ed.gizmo.center().is_equal_approx(rp.points[2]))
	n0 = ed._undo.size()
	await drag_by(pane, "m1", Vector3(0, 8, 0))
	check("ramp point: Y arrow lifts only that point 8 m", is_equal_approx(rp.points[2].y, 28.0) and is_equal_approx(rp.points[1].y, 30.0), str(rp.points))
	await undo_check("ramp point", ed.ramps_root, 0, before, n0)
	rp = nth(ed.ramps_root, 0)
	await focus(rp, M.ROTATE, 40.0)
	n0 = ed._undo.size()
	await drag_ring(pane, "r1", 90.0)
	var run: Vector3 = rp.points[2] - rp.points[0]
	check("ramp: the Y ring turns it a quarter turn", absf(run.x) < 0.5 and absf(absf(run.z) - 40.0) < 0.5, str(run))
	await undo_check("ramp turn", ed.ramps_root, 0, before, n0)
	rp = nth(ed.ramps_root, 0)
	await focus(rp, M.SCALE, 40.0)
	n0 = ed._undo.size()
	await drag_by(pane, "s0", Vector3(ed.gizmo.length(pane) * 0.9 * 0.5, 0, 0))
	run = rp.points[2] - rp.points[0]
	check("ramp: the X cube stretches it 1.5x along X", absf(run.x - 60.0) < 0.5 and absf(run.y + 20.0) < 0.01, str(run))
	await undo_check("ramp stretch", ed.ramps_root, 0, before, n0)

	# ---- the ortho views
	var top: ViewPane = null
	for q in ed.panes:
		if q.kind == ViewPane.Kind.TOP:
			top = q
	ed.maximise_pane(top)
	b = nth(ed.blocks_root, 0)
	before = b.to_dict()
	ed._select(b)
	ed.set_gizmo_mode(M.MOVE)
	top.frame(b.center(), 30.0)
	await frames(3)
	ids = ed.gizmo.handles(top).map(func(h): return h["id"])
	check("Top view: X and Z arrows and the dot, no Y arrow, no squares", ids.has("m0") and ids.has("m2") and not ids.has("m1") and not ids.has("p1"), str(ids))
	ed.set_gizmo_mode(M.ROTATE)
	ids = ed.gizmo.handles(top).map(func(h): return h["id"])
	check("Top view: only the Y ring", ids.has("r1") and not ids.has("r0") and not ids.has("r2") and not ids.has("rv"), str(ids))
	ed.set_gizmo_mode(M.MOVE)
	n0 = ed._undo.size()
	await drag_by(top, "m2", Vector3(0, 0, 8))
	p = b.data["position"]
	check("Top view: Z arrow moves it 8 m along Z", is_equal_approx(p[2], 8.0) and is_equal_approx(p[0], 0.0), str(p))
	await undo_check("Top Z arrow", ed.blocks_root, 0, before, n0)
	ed.maximise_pane(pane)
	await frames(2)

	# ---- several objects, a cube object, a locked one
	var b2: BlockNode = nth(ed.blocks_root, 1)
	b = nth(ed.blocks_root, 0)
	ed._set_selection([b, b2])
	ed.set_gizmo_mode(M.MOVE)
	pane.frame(b.center(), 30.0)
	await frames(3)
	await drag_by(pane, "m0", Vector3(8, 0, 0))
	check("two selected: the X arrow moves both", is_equal_approx(b.data["position"][0], 8.0) and is_equal_approx(b2.data["position"][0], 308.0))
	ed.undo()
	await frames(2)
	b = nth(ed.blocks_root, 0)
	b2 = nth(ed.blocks_root, 1)
	ed._set_selection([b, b2])
	ed.set_gizmo_mode(M.SCALE)
	await frames(1)
	check("two selected: Scale says one at a time, no handles", ed.gizmo.handles(pane).is_empty() and ed.gizmo.unsupported() != "")
	ed.set_gizmo_mode(M.MOVE)
	b = nth(ed.blocks_root, 0)
	ed._select(b)
	b.set_meta("locked", true)
	await frames(1)
	before = b.to_dict()
	check("a locked block shows no gizmo", ed.gizmo.handles(pane).is_empty())
	n0 = ed._undo.size()
	var mid: Vector2 = pane.camera.unproject_position(b.center())
	mouse(pane, "down", mid + Vector2(70, 0))
	for i in 4:
		mouse(pane, "move", mid + Vector2(70 + 30 * (i + 1), 0))
	mouse(pane, "up", mid + Vector2(190, 0))
	check("...and dragging there changes nothing", str(b.to_dict()) == str(before) and ed._undo.size() == n0)
	b.remove_meta("locked")

	print("\nRESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
