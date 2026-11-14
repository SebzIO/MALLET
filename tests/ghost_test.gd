extends SceneTree
## Ghost replay: a real SUCC run that finishes becomes the best run (recorded at 20 Hz), the ghost follows it on the
## next run, a slower run reports "+x vs best" and keeps the old ghost, the ghost is saved with the map and comes
## back on load, it never reaches an export, and the editor draws its path. Screenshot: ghost_path.png
## Run: godot --path . --resolution 1600x900 -s res://tests/ghost_test.gd -- <out>

var ok := true
var ed


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-58s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## One run with no input: leave the start, then get launched off the ramp's end into the finish.
func do_run(wait_before_launch: int) -> void:
	var r: RampNode = ed.ramps_root.get_child(0)
	ed.show_all_arcs = true
	ed._update_arcs()
	var a: Dictionary = ed._arcs[0]
	var ex := JumpCheck.exit_of(r.ridge)
	var p: SUCC = ed.play.player
	p.command = SUCCInput.new()
	p.command.yaw = atan2(-ex[1].x, -ex[1].z)
	p.teleport(Transform3D(Basis(), Vector3(-30, 300, 0)))    # out of the start zone: the clock starts
	p.velocity = Vector3.ZERO
	for i in wait_before_launch:
		p.velocity = Vector3.ZERO
		await physics_frame
	p.teleport(Transform3D(Basis(), ex[0] - Vector3(0, 0.9, 0)))
	p.velocity = ex[1] * a["speed"]
	for i in 60 * 6:
		await physics_frame
		if ed.play.run_state == PlayMode.Run.FINISHED:
			return


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._select(null)

	# --- first run: becomes the best
	ed._play_clicked()
	await physics_frame
	check("no ghost before the first run", ed.play._ghost_node == null)
	await do_run(10)
	var t1: float = ed.play.run_time
	check("first run finished", ed.play.run_state == PlayMode.Run.FINISHED, "(%s)" % PlayMode.format_time(t1))
	var g: Dictionary = ed.best_ghost
	var n: int = g.get("samples", []).size() / 4
	check("best run recorded at 20 Hz", not g.is_empty() and absf(g["time"] - t1) < 1e-6 and absf(n - (t1 * 20.0 + 2.0)) <= 1.0,
		"(%d samples for %.2f s)" % [n, t1])
	var start_pos: Vector3 = PlayMode.ghost_at(g, 0.0)[0]
	var end_pos: Vector3 = PlayMode.ghost_at(g, t1)[0]
	var fin_box: AABB = ed._find_entity("finish").zone_aabb()
	check("ghost starts where the run left the start", start_pos.distance_to(Vector3(-30, 300, 0)) < 1.5, str(start_pos.snapped(Vector3.ONE * 0.1)))
	check("ghost ends in the finish zone", fin_box.grow(1.0).has_point(end_pos + Vector3(0, 0.5, 0)), str(end_pos.snapped(Vector3.ONE * 0.1)))

	# --- second run: slower, races the ghost, keeps the old best
	ed.play.respawn()
	await process_frame
	await process_frame                                 # process_frame fires before nodes update
	check("ghost is out for the next run", ed.play._ghost_node != null and ed.play._ghost_node.visible)
	var ghost_wait: Vector3 = ed.play._ghost_node.global_position
	check("ghost waits at its start before the clock runs", ghost_wait.distance_to(start_pos) < 0.01)
	await do_run(40)
	var t2: float = ed.play.run_time
	var mid: Vector3 = ed.play._ghost_node.global_position
	check("slower run reports the gap to the best", t2 > t1 and ed.play._last_delta.begins_with("+"), "(%s, %s)" % [PlayMode.format_time(t2), ed.play._last_delta])
	check("the best run is still the first one", absf(ed.best_ghost["time"] - t1) < 1e-6)
	check("ghost moved during the run", mid.distance_to(start_pos) > 5.0)
	ed.play.show_ghost = false
	await process_frame
	await process_frame
	check("G hides the ghost", not ed.play._ghost_node.visible)
	ed.play.stop()
	await process_frame

	# --- saved with the map, back on load, never exported
	var path := out + "/ghost_test.mallet"
	ed.save_map(path)
	var saved_ghost: Dictionary = ed.best_ghost.duplicate(true)
	ed._new_map()
	check("a new map has no best run", ed.best_ghost.is_empty())
	ed.load_map(path)
	check("the best run comes back with the map", absf(float(ed.best_ghost.get("time", 0.0)) - saved_ghost["time"]) < 1e-4
		and ed.best_ghost["samples"].size() == saved_ghost["samples"].size())
	var scene: Node = SurfsUpExporter.build_scene(ed._map_dict(), "sf_check")
	var packed := PackedScene.new()
	packed.pack(scene)
	ResourceSaver.save(packed, "user://ghost_check.tscn")
	var text := FileAccess.get_file_as_string("user://ghost_check.tscn")
	check("nothing of the ghost reaches the export", not text.contains("ghost") and not text.contains("samples"))
	scene.free()
	ed._select(null)
	ed._toggle_views()
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/ghost_path.png")
	print("GHOST: ", "PASS" if ok else "FAIL")
	quit()
