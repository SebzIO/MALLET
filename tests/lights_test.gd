extends SceneTree
## Lights in build mode (0.19.4): an invisible light is a handle box (its bulb hides); aiming picks the light alone
## even with a cube right behind it; clicking it doesn't move it; dragging moves it freely (off the grid) across the
## plane of the face you grabbed; a copied light pastes onto the middle of the face you aim at. Color cycles: pulse
## flows through the colors, flicker jumps between them. A light reaches up to 2,000 m. Cube faces closer than 44
## degrees share smoothed normals (soft light on slopes); a cube's 90 degree edges stay sharp.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/lights_test.gd -- <out folder>

var ok := true
var bm: BuildMode


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func look(from: Vector3, at: Vector3) -> void:
	bm.cam.global_position = from
	var f := (at - from).normalized()
	bm.yaw = atan2(-f.x, -f.z)
	bm.pitch = asin(clampf(f.y, -0.9999, 0.9999))
	bm._apply_cam()


func mouse(button: int, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	bm._input(e)


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var w := CubeWorld.new()
	for x in 4:
		for y in 4:
			w.set_cell(Vector3i(x * 8, y * 8, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("Bricks104"))   # a wall at z 0..1
	ed._load_dict({"cube_models": [{"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}],
		"lights": [{"kind": "point", "position": [2.0, 2.0, 1.75], "color": "ffaa00", "energy": 2.0, "range": 10.0}]})
	await process_frame
	ed._build_clicked()
	for i in 3: await process_frame
	bm = ed.build
	var l: LightNode = ed.lights_root.get_child(0)
	check("in build mode a light's bulb hides (a handle box instead)", not l._bulb.visible)
	# aiming at the light, the wall right behind it
	look(Vector3(2.0, 2.0, 8.0), Vector3(2.0, 2.0, 0.0))
	await process_frame
	bm.update_target()
	check("aiming at a light in front of a cube picks the light alone", bm.target.get("entity") == l and int(bm.target.get("ent_face", -1)) == 5,
		"(%s, face %d)" % [bm.target.get("entity"), bm.target.get("ent_face", -1)])
	var at0 := l.global_position
	mouse(MOUSE_BUTTON_LEFT, true)
	bm._update_ent_drag()
	check("clicking it doesn't move it", l.global_position.is_equal_approx(at0) and bm.ent_sel == [l], str(l.global_position))
	# drag across the grabbed face's plane (the +z face: x and y move, z doesn't), off the grid
	look(Vector3(2.0, 2.0, 8.0), Vector3(2.37, 2.53, 1.75))
	bm._update_ent_drag()
	mouse(MOUSE_BUTTON_LEFT, false)
	var moved := l.global_position - at0
	check("dragging moves it across that face's plane, off the grid", absf(moved.z) < 1e-3 and absf(moved.x - 0.37) < 0.02 and absf(moved.y - 0.53) < 0.02,
		str(moved))
	# copy it, paste onto the top of the wall
	bm.copy()
	look(Vector3(1.5, 8.0, 0.5), Vector3(1.5, 4.0, 0.5))
	await process_frame
	bm.update_target()
	var n0: int = ed.lights_root.get_child_count()
	bm.paste()
	var pasted: LightNode = ed.lights_root.get_child(ed.lights_root.get_child_count() - 1) if ed.lights_root.get_child_count() > n0 else null
	check("a copied light pastes onto the middle of the face you aim at", pasted != null and pasted.global_position.is_equal_approx(Vector3(1.5, 4.5, 0.5)),
		str(pasted.global_position if pasted else Vector3.INF))
	# color cycles
	var s := LightNode.spec({"kind": "point", "color": "ff0000", "effect": "pulse", "colors": ["00ff00", "0000ff"], "speed": 0.5})
	var rig := LightNode.make_rig(s)
	var cp: AnimationPlayer = rig.get_node_or_null("Colors")
	var anim: Animation = cp.get_animation("colors") if cp else null
	check("pulse with 3 colors: a color animation through them, 0.5 s each", anim != null and is_equal_approx(anim.length, 1.5)
		and anim.track_get_key_value(0, 1) == Color.html("00ff00"))
	s["effect"] = "flicker"
	s["random"] = true
	rig.free()
	rig = LightNode.make_rig(s)
	cp = rig.get_node_or_null("Colors")
	anim = cp.get_animation("colors") if cp else null
	var jumps := anim != null and anim.track_get_interpolation_type(0) == Animation.INTERPOLATION_NEAREST
	check("flicker jumps between the colors", jumps)
	rig.free()
	check("a light reaches up to 2,000 m", float((bm._light_fields["range"] as HSlider).max_value) >= 2000.0)
	# smoothed normals: a gentle slope next to flat, and a plain cube's edge
	var sw := CubeWorld.new()
	var slope := CubeWorld.FULL.duplicate()
	for n in 8:
		if (n >> 1) & 1 and (n & 1):
			slope[n * 3 + 1] = 6                          # (its +x top edge 2/8 lower: a gentle slope)
	sw.set_cell(Vector3i(0, 0, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	sw.set_cell(Vector3i(8, 0, 0), 0, slope, CubeWorld.blank_tex())
	var arr := sw.chunk_arrays(CubeWorld.render_key(Vector4i(0, 0, 0, 0)))
	var soft := false
	var sharp := true
	for key in arr["groups"]:
		var g: Array = arr["groups"][key]
		for i in (g[0] as PackedVector3Array).size():
			var v: Vector3 = g[0][i]
			var n: Vector3 = g[1][i]
			if v.is_equal_approx(Vector3(1, 1, 0)) and n.y > 0.5 and n.x > 0.01:
				soft = true                               # (the flat top's corner at the slope leans towards it)
			if v.is_equal_approx(Vector3(0, 1, 0)) and n.y > 0.5 and not n.is_equal_approx(Vector3.UP):
				sharp = false                             # (the top's outer edge must stay straight up)
	check("faces under 44 degrees apart share smoothed normals; 90 degree edges stay sharp", soft and sharp)
	print("lights_test: ", "PASS" if ok else "FAIL")
	quit()
