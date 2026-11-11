extends SceneTree
## Build mode, driven like a player: E into first person, wheel cubes out of thin air and out of faces, F / Q + wheel
## slopes, G + wheel grid, Y + wheel / Y textures, select / copy / paste, undo; then the newer Sauerbraten features:
## T materials, F3 texture settings, O + wheel, middle-drag corners, Shift-drag moving, heightmap, blend painting,
## Tab entities with 1-4 + wheel, N new object, P play and back. Back in the editor the cube object moves, turns,
## copies and is still editable where it went; save / load, play on the cubes, both exports and a CS:S compile.
## Screenshots: build_fp.png (first person), build_editor.png.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/build_test.gd -- <out>

var ok := true
var ed
var bm: BuildMode


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func key(k: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap(k: Key) -> void:
	key(k)
	key(k, false)
	await frames(1)


func wheel(dir: int, times := 1) -> void:
	for i in times:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		Input.parse_input_event(e)
		await frames(2)


func held_wheel(k: Key, dir: int, times := 1) -> void:
	key(k)
	await wheel(dir, times)
	key(k, false)


func click(button: MouseButton, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame
	await physics_frame


func look(from: Vector3, at: Vector3) -> void:
	bm.cam.global_position = from
	var f := (at - from).normalized()
	bm.yaw = atan2(-f.x, -f.z)
	bm.pitch = asin(clampf(f.y, -0.9999, 0.9999))
	bm._apply_cam()


func models() -> Array:
	return ed.cube_models_root.get_children()


func cubes() -> int:
	var n := 0
	for m in models():
		n += m.world.count()
	return n


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._load_dict({})                                     # an empty map: nothing but what we build
	bm = ed.build
	await tap(KEY_E)
	check("E: into build mode (editor UI hidden, first-person camera)", bm.active and not ed._ui.visible and bm.cam.current)

	# ---- out of thin air
	look(Vector3(0.5, 12.5, 12), Vector3(0.5, 12.5, 0))
	await frames(2)
	check("aiming at nothing: the target is a spot in the air", not bm.target["hit"])
	await wheel(-1)
	check("wheel towards you: a cube appears, in a new cube object", cubes() == 1 and models().size() == 1, "(%d cubes, %d objects)" % [cubes(), models().size()])
	await frames(6)
	check("...and the crosshair is now on its face", bm.target["hit"] and bm.target["sel"]["orient"] == 5)
	await wheel(-1, 3)
	check("three more: a row of 4 coming towards you", cubes() == 4, "(%d cubes, %d objects)" % [cubes(), models().size()])
	await wheel(1)
	check("wheel away: the nearest one is pushed back in", cubes() == 3, "(%d cubes, %d objects)" % [cubes(), models().size()])

	# ---- a floor: G + wheel to 4 m, drag a selection across the air, pull it out
	await held_wheel(KEY_G, 1, 2)
	check("G + wheel: the grid goes up to 4 m", bm.grid_p == 2)
	look(Vector3(-8, 20, -2), Vector3(-8, 0, -2))
	await frames(2)
	click(MOUSE_BUTTON_LEFT, true)
	await frames(1)
	look(Vector3(8, 20, -2), Vector3(8, 0, -2))
	await frames(2)
	click(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	await wheel(-1)
	check("drag + wheel: a 5-cube floor (same cube object)", cubes() == 8 and models().size() == 1, "(%d cubes, %d objects)" % [cubes(), models().size()])
	await tap(KEY_SPACE)

	# ---- F / Q + wheel slopes, Y textures
	look(Vector3(0.5, 20, -1.5), Vector3(0.5, 0, -1.5))
	await frames(3)
	await held_wheel(KEY_F, 1, 4)
	var w: CubeWorld = models()[0].world
	var lk = w.leaf_at(Vector3(0.5, -0.5, -1.5) / CubeWorld.TICK)
	check("F + wheel: the face you aim at went down 4/8", lk != null and CubeWorld.corner(w.leaves[lk][0], 7).y == 4)
	await frames(3)
	await held_wheel(KEY_Q, 1, 4)
	var lows := 0
	for n in 8:
		if (n >> 1) & 1 and CubeWorld.corner(w.leaves[lk][0], n).y == 0:
			lows += 1
	check("Q + wheel: the corner you aim at went down (a slope)", lows == 1)
	# that cube's top is pushed in now: aiming at it still lands on the cell's own top, as if it were full
	look(Vector3(0.5, 20, -1.5), Vector3(0.5, 0, -1.5))
	await frames(3)
	var tl: Vector3 = (bm.target["local"] as Vector3) * CubeWorld.TICK
	check("a pushed-in cube still counts as a full block when you aim at it", bm.target["on_cube"] and bm.target["sel"]["orient"] == 3
		and absf(tl.y) < 0.05 and bm.target["sel"]["o"] == Vector3i(0, -32, -32), "(aim at y %.2f, cell %s)" % [tl.y, bm.target["sel"]["o"]])
	click(MOUSE_BUTTON_MIDDLE, true)
	await frames(1)
	click(MOUSE_BUTTON_MIDDLE, false)
	await frames(1)
	check("...so the middle mouse can select its corners", not bm.corners.is_empty())
	await frames(1)
	check("the blue half-size grid shows the selected square (one corner)", bm.last_fill_count == 1, "(%d squares)" % bm.last_fill_count)
	await tap(KEY_SPACE)
	await tap(KEY_H)
	await frames(1)
	check("heightmap mode shows a banner across the top", bm._banner.visible and bm._banner.text.contains("HEIGHTMAP"))
	await tap(KEY_H)
	await frames(1)
	check("...gone again when it's off", not bm._banner.visible)
	await held_wheel(KEY_Y, 1, 3)
	var top_slot: String = w.leaves[lk][1][3]
	check("Y + wheel: a texture on the face you aim at", bm.texture != "" and CubeWorld.slot_id(top_slot) == bm.texture)
	var tex_now := bm.texture
	await held_wheel(KEY_Y, 1, 2)
	look(Vector3(0.5, 20, -1.5), Vector3(0.5, 0, -1.5))
	await frames(2)
	key(KEY_Y)
	key(KEY_Y, false)
	await frames(1)
	check("Y on its own: picks up the texture you aim at", bm.texture != "")
	# O + wheel: shift the texture
	await held_wheel(KEY_O, -1, 2)
	var shifted := CubeWorld.parse_slot(w.leaves[lk][1][3])
	check("O + wheel: the texture shifted across", absf(float(shifted["u"]) - 0.875) < 0.001, "(%s)" % w.leaves[lk][1][3])

	# ---- T: materials (water in a pool), M shows / hides the invisible ones
	look(Vector3(8.5, 20, -1.5), Vector3(8.5, 0, -1.5))
	await frames(3)
	bm.sel = bm.target["sel"]
	check("the push counter reads a selected block's face", bm._face_pushes() >= 0 and bm._face_pushes() <= 4, str(bm._face_pushes()))
	# ---- U7: a pick looks through the air a folded face leaves, at the block behind it
	var probe := CubeModelNode.new()
	probe.world.begin()
	probe.world.set_cell(Vector3i(0, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	probe.world.set_cell(Vector3i(-8, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	probe.world.commit()
	probe.world.begin()
	for face in [1, 5]:                                        # the +X and +Z faces, folded in four notches
		var ps := CubeWorld.make_sel(Vector3i(0, 0, 0), 0, face)
		for i in 4:
			probe.world.push_face(ps, 1)
	probe.world.commit()
	var through := bm._first_occupied(probe, Vector3(2.0, 0.5, 0.875), Vector3.LEFT, 6.0, 0)
	check("a pick looks through the air a folded face leaves", not through.is_empty()
		and (through["cell"] as Vector3i).x == -8, str(through.get("cell", "none")))
	var solid := bm._first_occupied(probe, Vector3(2.0, 0.5, 0.25), Vector3.LEFT, 6.0, 0)
	check("...and still stops on the cube where it is solid", not solid.is_empty()
		and (solid["cell"] as Vector3i).x == 0, str(solid.get("cell", "none")))
	probe.free()
	# ---- D: the draw tool turns corners into a center in one place
	var db: Dictionary = ed._draw_box(Vector3(8, 0, 8), Vector3(16, 0, 16), Vector3(1, 0, 1), [4, 4, 4], 0.0)
	check("a block drawn grid point to grid point is the size you dragged", (db["size"] as Vector3).is_equal_approx(Vector3(8, 4, 8)), str(db["size"]))
	check("...and sits where you started, not two steps off", (db["base"] as Vector3).is_equal_approx(Vector3(12, 0, 12)), str(db["base"]))
	# ---- D: a small cube's face against a bigger cube's face is not drawn twice (no flicker)
	var wq := CubeWorld.new()
	wq.begin()
	wq.set_cell(Vector3i(8, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	wq.set_cell(Vector3i(16, 0, 0), 1, CubeWorld.FULL, CubeWorld.blank_tex())
	wq.commit()
	var colq: PackedVector3Array = wq.chunk_mesh(CubeWorld.render_key(Vector4i(0, 0, 0, 0)))[1]
	var shared := 0
	for i in range(0, colq.size(), 3):
		var flatq := true
		for j in 3:
			var pt: Vector3 = colq[i + j]
			if absf(pt.x - 2.0) > 0.001 or pt.y < 0.999 or pt.y > 2.001 or pt.z < 0.999 or pt.z > 2.001:
				flatq = false
		if flatq:
			shared += 1
	check("a small cube's face against a bigger cube's face is not drawn", shared == 0, str(shared))
	var water_sel := CubeWorld.moved(bm.target["sel"], 1)
	bm.sel = water_sel
	bm.run_command(CubeWorld.MATERIALS.find("water"))
	check("T: fill the space above the floor with water", w.mat_at((Vector3(water_sel["o"]) + Vector3.ONE * 2)) == "water")
	bm.sel = {}

	# ---- F3: texture settings (scale) on the face you aim at
	look(Vector3(-7.5, 20, -1.5), Vector3(-7.5, 0, -1.5))
	await frames(3)
	bm._tex_param("s", 2.0)
	var lk2 = w.leaf_at(Vector3(-7.5, -0.5, -1.5) / CubeWorld.TICK)
	check("F3 settings: the texture scale of that face", float(CubeWorld.parse_slot(w.leaves[lk2][1][3])["s"]) == 2.0)

	# ---- middle drag: select corners across two floor cubes, wheel pushes just those
	look(Vector3(-4.3, 20, -0.7), Vector3(-4.3, 0, -0.7))         # near the corner at x = -4, z = 0 between floor cubes
	await frames(3)
	click(MOUSE_BUTTON_MIDDLE, true)
	await frames(2)
	click(MOUSE_BUTTON_MIDDLE, false)
	await frames(1)
	check("middle drag: a corner selection", not bm.corners.is_empty())
	await wheel(1, 2)
	var left_k = w.leaf_at(Vector3(-7.5, -0.5, -3.5) / CubeWorld.TICK)
	var dipped := false
	if left_k != null:
		for n in 8:
			dipped = dipped or ((n >> 1) & 1 and CubeWorld.corner(w.leaves[left_k][0], n).y < 8)
	check("...and the wheel pushes just those corners", dipped)
	await tap(KEY_SPACE)
	# drag from one floor cube onto the next: exactly those two, and pulling never adds cubes
	look(Vector3(-6.0, 20, -2.7), Vector3(-6.0, 0, -2.7))
	await frames(3)
	click(MOUSE_BUTTON_MIDDLE, true)
	await frames(1)
	look(Vector3(-2.0, 20, -2.7), Vector3(-2.0, 0, -2.7))
	await frames(3)
	click(MOUSE_BUTTON_MIDDLE, false)
	await frames(1)
	check("middle drag from one cube to the next: just those two cubes", bm.sel.get("s") == Vector3i(2, 1, 1), "(%s)" % bm.sel.get("s"))
	var n_cubes := cubes()
	await wheel(-1, 12)
	check("...and rolling towards you never adds cubes", cubes() == n_cubes, "(%d -> %d)" % [n_cubes, cubes()])
	look(Vector3(-6.0, 20, 6.0), Vector3(-6.0, 0, 6.0))            # (no floor here)
	await frames(3)
	click(MOUSE_BUTTON_MIDDLE, true)
	await frames(1)
	click(MOUSE_BUTTON_MIDDLE, false)
	check("a corner selection can't start in empty space", bm.corners.is_empty() or bm.sel.get("s") == Vector3i(2, 1, 1))
	await tap(KEY_SPACE)

	# ---- heightmap (H): raise the floor's middle
	await tap(KEY_H)
	look(Vector3(2.0, 20, -2.0), Vector3(2.0, 0, -2.0))
	await frames(3)
	await held_wheel(KEY_B, -1, 2)                                    # brush: Small round
	var before_top := _top(w)
	await wheel(-1, 3)
	check("H + wheel: heightmap raises the ground", _top(w) > before_top + 0.1, "(%.2f -> %.2f m)" % [before_top, _top(w)])
	await tap(KEY_H)

	# ---- Shift + drag: move the 4-cube row along
	await held_wheel(KEY_G, -1, 2)
	look(Vector3(0.5, 12.5, 20), Vector3(0.5, 12.5, 0))
	await frames(3)
	click(MOUSE_BUTTON_LEFT, true)
	await frames(1)
	click(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	var row_before = w.leaf_at(Vector3(0.5, 12.5, 8.5) / CubeWorld.TICK)
	click(MOUSE_BUTTON_LEFT, true, true)
	await frames(1)
	look(Vector3(3.5, 12.5, 20), Vector3(3.5, 12.5, 0))
	await frames(6)
	click(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	check("Shift + drag: the selected cube moves across", row_before != null and w.leaf_at(Vector3(0.5, 12.5, 8.5) / CubeWorld.TICK) == null
		and w.leaf_at(Vector3(3.5, 12.5, 8.5) / CubeWorld.TICK) != null)
	await tap(KEY_SPACE)

	# ---- Tab: place a light on the floor, 1 + wheel changes its reach; Delete; undo
	look(Vector3(-6, 6, 3), Vector3(-6, 0, -2))
	await frames(3)
	# lights moved off Tab: they are the T menu's own tab (world pieces stay on Tab)
	var place_ids := []
	for it in bm.PLACE_ITEMS:
		place_ids.append(int(it[1]))
	check("Tab places world pieces, not lights", not (100 in place_ids) and not (101 in place_ids) and (102 in place_ids), str(place_ids))
	var light_tab: Array = bm.ENT_TABS["lights"][1]
	check("T's Lights tab has point, spot and strip", light_tab.size() == 3 and int(light_tab[1][1]) == 101, str(light_tab))
	bm._open_commands()
	check("T opens a panel with tabs, on Lights", bm._ent_menu.visible and bm._ent_pages["lights"].visible and bm._ent_tab_buttons.size() == 4,
		"menu %s lights %s tabs %s hud %s" % [bm._ent_menu.visible, bm._ent_pages["lights"].visible, bm._ent_tab_buttons.size(), bm._hud.visible])
	bm._ent_show("world")
	check("hovering another tab switches the page", bm._ent_pages["world"].visible and not bm._ent_pages["lights"].visible)
	bm._close_ent_menu()
	check("closing it hands the mouse back", not bm._ent_menu.visible and not bm._ui_open)
	bm._place(100)
	var light: LightNode = bm.ent_sel[0] if not bm.ent_sel.is_empty() else null
	check("T menu: a light placed where you aim", light != null and ed.lights_root.get_child_count() == 1)
	var reach := float(light.data["range"])
	await held_wheel(KEY_1, 1, 2)
	check("1 + wheel: its reach grows", float(light.data["range"]) == reach + 2.0)
	# ---- F4: the light's own panel
	bm._open_light_panel()
	check("F4 opens the light panel for the selected light", bm._light_panel.visible and bm._light_fields.size() >= 7)
	bm._light_set("energy", 6.5)
	check("its brightness control changes the light", is_equal_approx(float(light.data["energy"]), 6.5), str(light.data["energy"]))
	bm._light_set("color", "00ff00")
	check("...and its color", String(light.data["color"]) == "00ff00")
	bm._close_light_panel()
	check("closing it hands the mouse back", not bm._light_panel.visible and not bm._ui_open)
	await tap(KEY_DELETE)
	await frames(2)
	check("Delete removes it", ed.lights_root.get_child_count() == 0)
	await tap(KEY_Z)
	await frames(2)
	check("Z brings it back", ed.lights_root.get_child_count() == 1)

	# ---- N: a second cube object
	await tap(KEY_N)
	look(Vector3(30.5, 12.5, 12), Vector3(30.5, 12.5, 0))
	await frames(5)                                       # (after a CS:S compile the machine is busy: a few more)
	await wheel(-1)
	await frames(2)
	check("N, then building: a second cube object", models().size() == 2)

	# ---- P: play from here, Esc comes back to build mode
	await tap(KEY_P)
	await frames(3)
	check("P: playing from where you were", ed.play.active and not bm.active)
	ed.play.stop()
	await frames(2)
	check("...and stopping play comes back to build mode", bm.active and not ed._ui.visible)

	# ---- Ctrl+P: play from the map's start (like the editor's Play), Esc comes back to build mode
	var plate := EntityNode.create("start")
	plate.position = Vector3(80, 6, -40)
	ed.entities_root.add_child(plate)
	var where := bm.cam.global_position
	for down in [true, false]:                          # Ctrl+P as the keyboard sends it (with the Ctrl modifier)
		var ce := InputEventKey.new()
		ce.keycode = KEY_P
		ce.physical_keycode = KEY_P
		ce.ctrl_pressed = true
		ce.pressed = down
		Input.parse_input_event(ce)
		Input.flush_buffered_events()
	await frames(3)
	var spawn_at: Vector3 = plate.spawn_transform().origin
	var got: Vector3 = ed.play.player.global_position if ed.play.active else Vector3.INF
	check("Ctrl+P: playing from the start plate, not from here", ed.play.active and not bm.active
		and got.distance_to(spawn_at) < 3.0 and got.distance_to(where) > 20.0, "(at %s, plate %s)" % [got, spawn_at])
	ed.play.stop()
	await frames(2)
	check("...and stopping play comes back to build mode", bm.active and not ed._ui.visible)
	ed.entities_root.remove_child(plate)
	plate.queue_free()

	# a look in first person
	look(Vector3(14, 10, 22), Vector3(0, 2, -2))
	await frames(6)
	root.get_viewport().get_texture().get_image().save_png(out + "/build_fp.png")

	# ---- back to the editor: the cube object is one object you can move
	await tap(KEY_E)
	check("E: back to the editor", not bm.active and ed._ui.visible)
	var cm: CubeModelNode = models()[0]
	ed._select(cm)
	var hb: AABB = cm.world.bounds()
	var hpt: Vector3 = cm.global_transform.affine_inverse() * ed._move_handle_point(cm)
	check("its move handle sits in the middle of its cubes (not at its origin)", hb.grow(0.01).has_point(hpt)
		and hpt.distance_to(hb.get_center()) < 0.01, "(handle %s, cubes %s)" % [hpt, hb])
	var c0: Vector3 = cm.center()
	ed._checkpoint()
	cm.translate_by(Vector3(40, 0, 0))
	ed._rotate_selected(90.0)
	check("in the editor: the cube object moves and turns as one", cm.center().distance_to(c0 + Vector3(40, 0, 0)) < 0.5 and absf(cm.yaw - 90.0) < 0.01)
	ed._duplicate_clicked()
	check("...and duplicates", models().size() == 3)
	ed.undo()
	ed.undo()
	ed.undo()
	cm = models()[0]
	check("editor undo puts it back", cm.center().distance_to(c0) < 0.5 and models().size() == 2)
	cm.translate_by(Vector3(0, 0, -60))
	# back into build mode: it edits the moved object where it is now
	ed._select(cm)
	ed._build_clicked()
	await frames(2)
	var tgt: Vector3 = cm.global_transform * Vector3(-7.5, 0.0, -1.5)
	look(tgt + Vector3(0, 20, 0), tgt)
	await frames(3)
	var n_before := cm.world.count()
	await wheel(-1)
	check("build mode edits the moved object where it is now", bm.target["model"] == cm and cm.world.count() > n_before)
	await tap(KEY_E)

	var total := cubes()
	var cm_pos: Vector3 = cm.position
	ed.save_map(out + "/build_test.mallet")
	ed._new_map()
	ed.load_map(out + "/build_test.mallet")
	await frames(3)
	check("cube objects come back with the map (every cube, where they were)", cubes() == total and models().size() == 2
		and models()[0].position.distance_to(cm_pos) < 0.01)

	# ---- play on them
	var fl: CubeModelNode = models()[0]
	var drop: Vector3 = fl.global_transform * Vector3(-6, 12, -2)
	ed.play.start(Transform3D(Basis(), drop))
	for i in 150:
		await physics_frame
	var py: float = ed.play.player.global_position.y
	ed.play.stop()
	check("play: the player lands on the cube floor", py > -1.0 and py < 8.0, "(y %.2f)" % py)

	# ---- exports
	var st := EntityNode.create("start")
	st.position = Vector3(60, 4, 60)
	ed.entities_root.add_child(st)
	var fin := EntityNode.create("finish")
	fin.position = Vector3(-60, 4, 60)
	ed.entities_root.add_child(fin)
	var map: Dictionary = ed._map_dict()
	var scene: Node = SurfsUpExporter.build_scene(map, "sf_build")
	var cnode: Node = scene.get_node_or_null("Cubes")
	check("SurfsUp export: both cube objects, with collision", cnode != null and cnode.get_child_count() == 2)
	scene.free()
	var css := VmfExporter.find_css()
	if css != "":
		var vmf := "D:/SurfForge_exports/css/sf_build.vmf"
		var res := VmfExporter.export_vmf(map, vmf)
		var txt := FileAccess.get_file_as_string(vmf)
		check("CS:S: water brushes for the pool", txt.to_upper().contains("LIQUIDS/AZTECWATER"))
		var cc := VmfExporter.compile(vmf, css, "fast", res.get("materials", []))
		var bad := 0
		for line in String(cc["log"]).split("\n"):
			var l := line.to_lower()
			if l.contains("brush") and (l.contains("error") or l.contains("invalid") or l.contains("duplicate") or l.contains("out of range")):
				bad += 1
				if bad <= 4:
					print("      ", line.strip_edges())
		check("CS:S: every cube a brush, compiles cleanly", res["error"] == "" and cc["error"] == "" and bad == 0,
			"(%d brushes) %s %s" % [res["brushes"], res["error"], cc["error"]])
	var cam := ed.panes[0].camera as OrbitCamera
	cam.focus = fl.center()
	cam.distance = 50.0
	cam.yaw = deg_to_rad(30)
	cam.pitch = deg_to_rad(-30)
	cam._apply()
	ed._select(fl)
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/build_editor.png")
	print("BUILD: ", "PASS" if ok else "FAIL")
	quit()


func _top(w: CubeWorld) -> float:
	var t := -INF
	for k in w.leaves:
		if k.y > 0:
			continue                                     # just the floor (the row floats higher up)
		for n in 8:
			t = maxf(t, (k.y + CubeWorld.corner(w.leaves[k][0], n).y * CubeWorld.size_of(k.w) / 8.0) * CubeWorld.TICK)
	return t
