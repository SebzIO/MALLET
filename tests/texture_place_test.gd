extends SceneTree
## F3's Center on selection / Fit to selection (the user's lamp texture that straddled four 1 m cubes): the texture's
## middle lands in the middle of the selection, Fit makes one repeat span it, turned textures too, and CS:S exports
## put it in the same place - also for a cube object moved off the texture's grid. Saves a top-down picture.
## Run: godot --path D:/SurfForge --resolution 900x900 -s res://tests/texture_place_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


## Texture coordinate (repeats, mod 1) at a point of a face, as the editor draws it.
func uv_at(w: CubeWorld, k: Vector4i, o: int, p: Vector3) -> Vector2:
	var sl := CubeWorld.parse_slot(w.leaves[k][1][o])
	var uv := CubeWorld.slot_uv(p, Vector3(CubeWorld.orient_step(o)), sl)
	return Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var id := "getridou_concretelight"
	var t := PackedStringArray()
	for f in 6:
		t.append(id)
	var w := CubeWorld.new()
	for x in 5:
		for z in 5:
			w.set_cell(Vector3i(24 + x * 8, 0, 40 + z * 8), 0, CubeWorld.FULL, t)     # a 5 x 5 m floor of 1 m cubes at (3, 5) m
	var one := CubeWorld.make_sel(Vector3i(40, 0, 56), 0, 3)                         # the middle cube's top
	var mid := Vector3(5.5, 1.0, 7.5)
	var k := Vector4i(40, 0, 56, 0)
	check("before: the lamp (texture middle) isn't on that cube", uv_at(w, k, 3, mid).distance_to(Vector2(0.5, 0.5)) > 0.1, "(%s)" % uv_at(w, k, 3, mid))
	w.place_texture(one, false)
	check("Center: the texture's middle is the cube's middle", uv_at(w, k, 3, mid).distance_to(Vector2(0.5, 0.5)) < 0.001, "(%s)" % uv_at(w, k, 3, mid))
	check("Center keeps its size (8 m)", is_equal_approx(float(CubeWorld.parse_slot(w.leaves[k][1][3])["s"]), 1.0))
	var nb := Vector4i(48, 0, 56, 0)
	check("...and only the selected face changes", CubeWorld.parse_slot(w.leaves[nb][1][3])["u"] == 0.0)
	w.place_texture(one, true)
	var sl := CubeWorld.parse_slot(w.leaves[k][1][3])
	check("Fit: one repeat spans the 1 m cube (scale 1/8)", is_equal_approx(float(sl["s"]), 0.125), "(s %s)" % sl["s"])
	check("Fit: the cube's corner is the texture's corner", uv_at(w, k, 3, Vector3(5.0, 1.0, 7.0)).distance_to(Vector2.ZERO) < 0.001
		or uv_at(w, k, 3, Vector3(5.0, 1.0, 7.0)).distance_to(Vector2.ONE) < 0.001, "(%s)" % uv_at(w, k, 3, Vector3(5.0, 1.0, 7.0)))
	# a bigger selection, a side face, turned 90 degrees
	var wall := CubeWorld.make_sel(Vector3i(24, 0, 40), 0, 0, Vector3i(1, 1, 5))       # the -x side of the first row
	w.set_slot_param(wall, false, func(d: Dictionary) -> Dictionary:
		d["r"] = 1
		return d)
	w.place_texture(wall, false)
	var wk := Vector4i(24, 0, 56, 0)
	check("Center works on a 5 m side, turned 90 degrees", uv_at(w, wk, 0, Vector3(3.0, 0.5, 7.5)).distance_to(Vector2(0.5, 0.5)) < 0.001,
		"(%s)" % uv_at(w, wk, 0, Vector3(3.0, 0.5, 7.5)))

	# CS:S puts it in the same place, with the object moved off the texture's grid (back at full size, centered)
	w.set_slot_param(one, false, func(d: Dictionary) -> Dictionary:
		d["s"] = 1.0
		return d)
	w.place_texture(one, false)
	var origin := Vector3(13.37, 0.0, -2.5)
	var map := {"format": "mallet-map", "version": 2, "environment": Look.preset_environment("day"), "ramps": [], "props": [],
		"texts": [], "lights": [], "blocks": [],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 200], "size": [40, 2, 40], "yaw": 0.0}],
		"cube_models": [{"position": [origin.x, origin.y, origin.z], "yaw": 0.0, "cubes": w.to_dict()}]}
	var vx := VmfExporter.new()
	var text := vx.build(map)
	var found := false
	var where := Vector2(-1, -1)
	var re := RegEx.create_from_string(r'"plane" "\(([^)]*)\) \(([^)]*)\) \(([^)]*)\)"\s*"material" "[^"]*concretelight[^"]*"\s*"uaxis" "\[([^\]]*)\] ([^"]*)"\s*"vaxis" "\[([^\]]*)\] ([^"]*)"')
	var c_src := vx.src(origin + mid)
	for m in re.search_all(text):
		var ua := m.get_string(4).split(" ")
		var va := m.get_string(6).split(" ")
		var nrm: Vector3 = (_v(m.get_string(3)) - _v(m.get_string(1))).cross(_v(m.get_string(2)) - _v(m.get_string(1)))
		var pt := _v(m.get_string(1))
		if absf(nrm.normalized().z) < 0.99 or absf(pt.z - c_src.z) > 0.01:
			continue                                     # (only top faces at that height)
		var u_t := (c_src.dot(Vector3(float(ua[0]), float(ua[1]), float(ua[2]))) / float(m.get_string(5)) + float(ua[3])) / float(MaterialLibrary.texture_px(id))
		var v_t := (c_src.dot(Vector3(float(va[0]), float(va[1]), float(va[2]))) / float(m.get_string(7)) + float(va[3])) / float(MaterialLibrary.texture_px(id))
		var uv := Vector2(fposmod(u_t, 1.0), fposmod(v_t, 1.0))
		if uv.distance_to(Vector2(0.5, 0.5)) < 0.002:
			found = true
		where = uv
	check("CS:S: the lamp is centered on the same cube (object moved off-grid)", found, "(%s)" % where)

	# a picture: the floor from above, the middle cube centered
	var root3 := Node3D.new()
	root.add_child(root3)
	for ck in w.render_chunks():
		var mm: Array = w.chunk_mesh(ck, true)
		var mi := MeshInstance3D.new()
		mi.mesh = mm[0]
		root3.add_child(mi)
		var li := MeshInstance3D.new()
		li.mesh = mm[2]
		root3.add_child(li)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.9, 0.9)
	root3.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.4
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(5.5, 10, 7.5), Vector3(5.5, 0, 7.5), Vector3.FORWARD)
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/texture_place.png")
	print("TEXTURE PLACE: ", "PASS" if ok else "FAIL")
	quit()


func _v(s: String) -> Vector3:
	var p := s.split(" ")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
