extends SceneTree
## The experimental heightmap (0.19.7, Shift+H): the same brush makes a different shape every time (normal mode makes
## the same one wherever you use it), and the terrain stays joined - rays dropped onto it a few centimeters apart
## never fall into a crack or a pit (heights next to each other stay close), in both modes. Saves a picture.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/hmap_rough_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func terrain(rough: bool) -> CubeWorld:
	var w := CubeWorld.new()
	for x in 32:
		for z in 32:
			w.set_cell(Vector3i(x * 8, 0, z * 8), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("Grass004"))
	for spot in [Vector2i(64, 64), Vector2i(176, 64), Vector2i(64, 176), Vector2i(176, 176)]:
		for k in 3:
			w.hmap_edit(Vector3i(spot.x, 0, spot.y), 8 + k * 8, 0, CubeWorld.BRUSHES[2][1], -1, rough)
	return w


## The surface's height at every point of a fine grid (rays from above), or INF where a ray falls through.
func heights(cm: CubeModelNode, n: int, step: float) -> Array:
	var space := cm.get_world_3d().direct_space_state
	var out := []
	for i in n:
		var row := []
		for j in n:
			var p := Vector3(2.0 + i * step, 50.0, 2.0 + j * step)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 100.0))
			row.append(float(hit["position"].y) if not hit.is_empty() else INF)
		out.append(row)
	return out


func worst_jump(h: Array) -> float:
	var worst := 0.0
	for i in h.size():
		for j in (h[i] as Array).size():
			if i > 0:
				worst = maxf(worst, absf(float(h[i][j]) - float(h[i - 1][j])))
			if j > 0:
				worst = maxf(worst, absf(float(h[i][j]) - float(h[i][j - 1])))
	return worst


func _diff(a: Array, b: Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(float(a[i]) - float(b[i])))
	return m


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var shapes := {}
	for rough in [false, true]:
		var cm := CubeModelNode.new()
		root.add_child(cm)
		cm.from_dict({"position": [0.0, 0.0, 0.0], "yaw": 0.0, "cubes": terrain(rough).to_dict()})
		cm.finish_background()
		for f in 3:
			await physics_frame
		var h := heights(cm, 120, 0.25)
		var jump := worst_jump(h)
		check("%s heightmap: no cracks or pits (rays 25 cm apart)" % ("experimental" if rough else "normal"), jump < 0.6, "(biggest step %.2f m)" % jump)
		# the four strokes' shapes, relative to their middles
		var pats := []
		for spot in [Vector2(8, 8), Vector2(22, 8), Vector2(8, 22), Vector2(22, 22)]:
			var pat := []
			var mid: float = h[int(spot.x * 4) - 8][int(spot.y * 4) - 8]
			for a in range(-8, 9, 2):
				for b in range(-8, 9, 2):
					pat.append(snappedf(float(h[int(spot.x * 4) - 8 + a][int(spot.y * 4) - 8 + b]) - mid, 0.01))
			pats.append(pat)
		shapes[rough] = pats
		if rough:
			var cam := Camera3D.new()
			root.add_child(cam)
			cam.look_at_from_position(Vector3(-6, 14, 34), Vector3(16, 1, 14))
			var sun := DirectionalLight3D.new()
			sun.rotation = Vector3(-0.8, 0.5, 0)
			root.add_child(sun)
			for f in 4:
				await process_frame
			root.get_texture().get_image().save_png(out + "/hmap_rough.png")
		cm.queue_free()
		await process_frame
	var dn := maxf(_diff(shapes[false][0], shapes[false][1]), _diff(shapes[false][0], shapes[false][3]))
	var dr := minf(minf(_diff(shapes[true][0], shapes[true][1]), _diff(shapes[true][0], shapes[true][3])), _diff(shapes[true][1], shapes[true][2]))
	check("normal mode: the same brush makes the same shape everywhere", dn < 0.1, "(differs by up to %.2f m)" % dn)
	check("experimental: the same brush makes a different shape each time", dr > 0.3, "(differs by at least %.2f m)" % dr)
	print("hmap_rough_test: ", "PASS" if ok else "FAIL")
	quit()
