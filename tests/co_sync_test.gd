extends SceneTree
## Co-editing keeps both copies the same through big pastes and deletes (0.18.18), with two real MALLETs on a real
## relay: a paste of more than 8 objects all arrive (the rest used to be dropped), deleting them removes every one
## (every other deletion used to be skipped), an edit to a big cube object goes as just the cubes that changed (it
## used to be refused as too big, so build-mode work on a big object never synced), a pasted big cube object
## arrives in parts, and a copy that drifted apart gets the whole object again.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/co_sync_test.gd -- <out folder>

const PORT := 8797
const URL := "ws://127.0.0.1:%d/ws" % PORT

var ok := true
var relay_pid := -1


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func wait_for(f: Callable, ms := 8000) -> bool:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		if f.call():
			return true
		await process_frame
	return f.call()


func wait_ms(ms: int) -> void:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < ms:
		await process_frame


func blocks(ed) -> int:
	return ed.blocks_root.get_child_count() if "blocks_root" in ed else -1


func cubes_of(ed) -> Array:
	return ed.cube_models_root.get_children()


func same_world(a: CubeWorld, b: CubeWorld) -> bool:
	return a.leaves == b.leaves and a.mats == b.mats


func _run() -> void:
	relay_pid = OS.create_process("python", ["relay/relay.py", "--port", str(PORT), "--quiet"])
	await wait_ms(1200)
	# a map with 12 blocks and a big cube object (several hundred KB as data)
	var w := CubeWorld.new()
	ShapeGen.place(w, ShapeGen.generate("sphere", {"r": 16.0}, -3, 2)["cells"], Vector3i.ZERO, "")
	w.begin()
	w.set_material(CubeWorld.make_sel(Vector3i(0, 80, 0), -1, 3, Vector3i(4, 2, 4)), "lava")
	w.commit()
	var map := {"blocks": [], "cube_models": [{"position": [0.0, 10.0, 0.0], "yaw": 0.0, "cubes": w.to_dict()}]}
	for i in 12:
		map["blocks"].append({"shape": "box", "position": [20.0 + i * 6.0, 0.0, 0.0], "size": [4.0, 2.0, 4.0]})
	var size_kb := JSON.stringify(map["cube_models"][0]).length() / 1024
	var a = load("res://editor/main.tscn").instantiate()
	root.add_child(a)
	await process_frame
	a._load_dict(map)
	a._mark_saved()
	check("A opens a session", a.start_playtest(URL, "", "", "Ann") and await wait_for(func(): return a.relay.is_open()))
	var b = load("res://editor/main.tscn").instantiate()
	root.add_child(b)
	await process_frame
	b._mark_saved()
	b.start_playtest(URL, a.relay.session, a.relay.secret, "Bob", true)
	await wait_for(func(): return b.relay.is_open())
	if b._co_state_dialog != null and b._co_state_dialog.visible:     # ("load their map?": yes)
		b._co_state_dialog.hide()
		b._co_request_state()
	var b_has_it := func(): return b.relay != null and b.relay.is_open() and blocks(b) == 12 and cubes_of(b).size() == 1 and same_world(cubes_of(a)[0].world, cubes_of(b)[0].world)
	var joined := await wait_for(b_has_it, 20000)
	check("B joins and gets A's map (a %d KB cube object, 12 blocks)" % size_kb, joined, "(%d blocks, %d cube objects)" % [blocks(b), cubes_of(b).size()])
	await wait_ms(500)
	# a paste of 12 objects
	a._set_selection(a.blocks_root.get_children())
	a._copy()
	a._paste_clicked()
	check("A pastes 12 blocks", blocks(a) == 24)
	check("...and all 12 arrive at B", await wait_for(func(): return blocks(b) == 24), "(%d)" % blocks(b))
	# deleting them
	a._delete_clicked()
	check("A deletes the 12 pasted blocks", blocks(a) == 12, "(%d)" % blocks(a))
	check("...and every one of them goes at B", await wait_for(func(): return blocks(b) == 12), "(%d)" % blocks(b))
	# a build-mode style edit on the big cube object
	var ca: CubeModelNode = cubes_of(a)[0]
	var cb: CubeModelNode = cubes_of(b)[0]
	var wa := ca.world
	wa.begin()
	for i in 6:
		wa.set_cell(Vector3i(200 + i * 8, 0, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex("Bricks104"))
	var gone: Vector4i = wa.leaves.keys()[10]
	wa._clear_cell(Vector3i(gone.x, gone.y, gone.z), gone.w)                       # (and one taken away)
	wa.commit()
	a._co_queue[ca] = true
	check("an edit to the big cube object arrives at B", await wait_for(func(): return same_world(ca.world, cb.world)),
		"(%d vs %d cubes)" % [ca.world.count(), cb.world.count()])
	check("...as just the cubes that changed (nothing left to send)", (wa.change_log as Dictionary).is_empty() and not wa.changed_all)
	# moving it
	ca.position += Vector3(5, 0, 0)
	a._co_queue[ca] = true
	check("moving it moves B's", await wait_for(func(): return cb.position.is_equal_approx(ca.position)), str(cb.position))
	# pasting the whole big cube object (too big for one message)
	a._set_selection([ca])
	a._copy()
	a._paste_clicked()
	check("A pastes the big cube object", cubes_of(a).size() == 2)
	var both := func(): return cubes_of(b).size() == 2 and same_world(cubes_of(a)[1].world, cubes_of(b)[1].world)
	check("...and it arrives at B in parts, whole", await wait_for(both, 15000), "(%d cube objects)" % cubes_of(b).size())
	# B's copy drifts apart: the next edit notices and B gets the whole object again
	var k0: Vector4i = cb.world.leaves.keys()[5]
	cb.world._put(k0, null)
	cb.world.change_log = {}
	wa.begin()
	wa.set_cell(Vector3i(400, 0, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	wa.commit()
	a._co_queue[ca] = true
	check("a copy that drifted apart gets the whole object again", await wait_for(func(): return same_world(ca.world, cb.world), 15000),
		"(%d vs %d cubes)" % [ca.world.count(), cb.world.count()])
	check("nothing was refused as too big", not String(a._status.text).contains("too big") if "_status" in a else true)
	a._leave_playtest()
	b._leave_playtest()
	OS.kill(relay_pid)
	print("co_sync_test: ", "PASS" if ok else "FAIL")
	quit()
