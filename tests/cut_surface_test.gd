extends SceneTree
## Cut cubes keep every face (0.18.6). Where two nearly parallel planes meet, single-precision math lost corners and
## whole faces went missing: see-through pits along a cone's seams. For many-sided shapes: every plane that crosses a
## cell has its face in cut_faces, and the real mesh's slanted surface adds up to the shape's true area.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/cut_surface_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func area(poly: PackedVector3Array) -> float:
	var a := 0.0
	for i in range(1, poly.size() - 1):
		a += (poly[i] - poly[0]).cross(poly[i + 1] - poly[0]).length() * 0.5
	return a


func missing_faces(cells: Array) -> int:
	var bad := 0
	for c in cells:
		if c.size() < 4:
			continue
		var pl := ShapeGen._cut_planes_of(c)
		var faces := CubeWorld.cut_faces(c[3])
		for i in pl.size():
			var poly := ShapeGen._plane_square(pl[i][0], float(pl[i][1]))
			for wi in 6:
				poly = ShapeGen._clip_poly(poly, CubeWorld.orient_normal(wi), 8.0 if wi & 1 else 0.0)
				if poly.size() < 3:
					break
			for j in pl.size():
				if j != i and poly.size() >= 3:
					poly = ShapeGen._clip_poly(poly, pl[j][0], float(pl[j][1]))
			if poly.size() < 3 or area(poly) < 0.01:
				continue
			var found := 0.0
			for f in faces:
				if f[1] == -1 and absf(Vector3(f[2][0]).dot(pl[i][0]) - float(pl[i][1])) < 1e-3:
					found = maxf(found, area(f[2]))
			if found < area(poly) * 0.98:
				bad += 1
	return bad


## Area of the mesh's triangles that aren't axis-aligned (the slanted surface), and of its collision's.
func slanted_area(w: CubeWorld) -> Array:
	var ms := 0.0
	var cs := 0.0
	var t0 := Time.get_ticks_msec()
	for ck in w._render:
		var res: Array = w.chunk_mesh(ck)
		var m: ArrayMesh = res[0]
		for s in m.get_surface_count():
			ms += _slanted(m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		cs += _slanted(res[1])
	return [ms, cs, Time.get_ticks_msec() - t0]


func _slanted(v: PackedVector3Array) -> float:
	var a := 0.0
	for i in range(0, v.size(), 3):
		var c := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		if c.length() < 1e-9:
			continue
		var n := c.normalized().abs()
		if maxf(n.x, maxf(n.y, n.z)) < 0.9999:
			a += c.length() * 0.5
	return a


## A rendered cone against bright green: looking straight at it from four sides, no green may show through.
func _see_through_check() -> void:
	var r := 4.0
	var h := 8.0
	var cells: Array = ShapeGen.generate("cone", {"r": r, "h": h, "sides": 30}, 0, 2)["cells"]
	var w := CubeWorld.new()
	ShapeGen.place(w, cells, Vector3i.ZERO, "")
	var scene := Node3D.new()
	root.add_child(scene)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0, 1, 0)
	scene.add_child(we)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.BLACK
	for ck in w._render:
		var mi := MeshInstance3D.new()
		mi.mesh = w.chunk_mesh(ck)[0]
		mi.material_override = mat
		scene.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 30.0
	scene.add_child(cam)
	cam.current = true
	var target := Vector3(r, h * 0.25, r)
	var green := 0
	var looked := 0
	for yaw in [0.3, 1.9, 3.4, 5.0]:
		cam.position = target + Vector3(sin(yaw), 0.15, cos(yaw)).normalized() * 14.0
		cam.look_at(target)
		for i in 3:
			await process_frame
		var img := root.get_texture().get_image()
		var mid := Vector2i(img.get_width() / 2, img.get_height() / 2)
		var half := img.get_height() / 5
		for y in range(mid.y - half, mid.y + half):
			for x in range(mid.x - half, mid.x + half):
				looked += 1
				if img.get_pixel(x, y).g > 0.2:
					green += 1
	check("a rendered cone shows no sky through its surface", green == 0 and looked > 0, "%d of %d pixels" % [green, looked])
	scene.queue_free()


func _run() -> void:
	for spec in [["cone", {"r": 11.13, "h": 21.25, "sides": 30}], ["cone", {"r": 7.125, "h": 21.25, "sides": 64}], ["cone", {"r": 4.0, "h": 4.0, "sides": 25}]]:
		var v: Dictionary = spec[1]
		var g := ShapeGen.generate(spec[0], v, 0, 0)
		var cells: Array = g["cells"]
		check("%s r %s, %d sides: every plane crossing a cell has its face" % [spec[0], v["r"], v["sides"]], missing_faces(cells) == 0, "%d cells" % cells.size())
		var w := CubeWorld.new()
		ShapeGen.place(w, cells, Vector3i.ZERO, "")
		var r: float = v["r"]
		var h: float = v["h"]
		var want: float = v["sides"] * r * tan(PI / v["sides"]) * sqrt(h * h + r * r)
		var got := slanted_area(w)
		check("...the mesh's slanted surface is the cone's true area", absf(got[0] / want - 1.0) < 0.01, "%.1f of %.1f m2, meshed in %d ms" % [got[0], want, got[2]])
		check("...and so is its collision", absf(got[1] / want - 1.0) < 0.01, "%.1f m2" % got[1])
		var vx := VmfExporter.new()
		var wrong := 0
		var brushes := 0
		for key in w.leaves:
			if (w.leaves[key] as Array).size() <= 3:
				continue
			var pts: PackedVector3Array = w.cube_points(key)
			if pts.size() < 4:
				continue
			var mid := Vector3.ZERO
			for q in pts:
				mid += vx.src(q)
			mid /= pts.size()
			brushes += 1
			for sd in vx._cut_sides(w, key, Transform3D.IDENTITY):
				var n: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
				if n.dot(mid - sd[0]) > 1e-3:
					wrong += 1
		check("...every CS:S brush side from the exact planes faces outward", wrong == 0 and brushes > 0, "%d cut brushes, %d wrong" % [brushes, wrong])
	await _see_through_check()
	print("cut_surface_test: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
