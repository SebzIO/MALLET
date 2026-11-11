extends SceneTree
## Render chunks by cube size (0.18.15): a map of big blocks spread out stays a handful of chunks (each chunk is a draw
## call and a physics body; 4 m chunks for everything made a 0.18.4 map 14,000 chunks, 7 fps, and too many bodies for
## the player to move), small cubes go in small chunks, and an edit next to a cube of the other size redraws both.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/chunk_budget_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func put(w: CubeWorld, at: Vector3i, p: int) -> void:
	w.set_cell(at, p, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("getridou_envmarble"))


func _run() -> void:
	# 400 blocks of 4 m, 8 m apart, over 160 m: 10 x 10 big chunks
	var big := CubeWorld.new()
	for x in 20:
		for z in 20:
			put(big, Vector3i(x * 64, 0, z * 64), 2)
	check("400 spread-out 4 m blocks make 100 chunks, not one each", big.render_chunks().size() == 100, "(%d)" % big.render_chunks().size())
	# an 8 m slab of 0.125 m cubes: 2 x 2 small chunks
	var small := CubeWorld.new()
	for x in 64:
		for z in 64:
			put(small, Vector3i(x, 0, z), -3)
	check("an 8 m slab of small cubes makes 4 small chunks", small.render_chunks().size() == 4, "(%d)" % small.render_chunks().size())
	var keys := small.render_chunks()
	var c := CubeWorld.chunk_center(keys[0])
	check("a small chunk's middle is inside the slab's area", c.x > 0 and c.x < 64 and c.z > 0 and c.z < 64, str(c))
	c = CubeWorld.chunk_center(big.render_chunks()[0])
	check("a big chunk's middle is where its blocks are", c.y == 64.0 and int(c.x) % 128 == 64, str(c))
	# a small cube against a big one: both chunks redraw
	var mix := CubeWorld.new()
	put(mix, Vector3i(0, 0, 0), 2)
	var bk := CubeWorld.render_key(Vector4i(0, 0, 0, 2))
	mix.dirty.clear()
	put(mix, Vector3i(32, 0, 0), -3)
	var sk := CubeWorld.render_key(Vector4i(32, 0, 0, -3))
	check("small and big cubes go in different chunks", sk != bk)
	check("placing a small cube against a big one redraws the big one's chunk", mix.dirty.has(bk) and mix.dirty.has(sk))
	var m: Variant = ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_bodies", 0)
	check("the physics engine allows enough bodies for big maps", int(m) >= 65536, "(%s)" % m)
	print("CHUNK BUDGET: ", "PASS" if ok else "FAIL")
	print("chunk_budget_test: ", "PASS" if ok else "FAIL")
	quit()
