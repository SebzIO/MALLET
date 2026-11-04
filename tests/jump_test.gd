extends SceneTree
## Jump checker: arcs on the starter map, a too-far finish (red), and the prediction vs the real SUCC player.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/jump_test.gd -- <out_dir>

var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func report(tag: String) -> void:
	ed._update_arcs()
	for a in ed._arcs:
		print("%s: exit %d u/s from %s | full: %s @ %s | 85%%: %s" % [tag, roundi(a["speed"] * JumpCheck.U), a["ref"],
			a["runs"][0]["label"], a["runs"][0]["hit_point"].snapped(Vector3.ONE * 0.1), a["runs"][1]["label"]])


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	for i in 3: await physics_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	ed._select(r)
	report("starter map")
	ed._frame_clicked()
	await shot("j01_good_jump")

	# move the finish far away: the jump should turn red
	var fin: EntityNode = ed._find_entity("finish")
	fin.position = Vector3(260, 40, 0)
	for i in 2: await physics_frame
	report("finish moved to x=260")
	ed._select(null)
	ed._frame_clicked()
	ed._select(r)
	await shot("j02_too_far")
	fin.position = Vector3(110, 60, 0)
	for i in 2: await physics_frame

	# prediction vs the real controller: launch SUCC from the same point at the same speed, no input
	ed._update_arcs()
	var a: Dictionary = ed._arcs[0]
	var predicted: Vector3 = a["runs"][0]["hit_point"]
	var ex := JumpCheck.exit_of(r.ridge)
	ed._play_clicked()
	await physics_frame
	var p: SUCC = ed.play.player
	p.command = SUCCInput.new()
	p.command.yaw = atan2(-ex[1].x, -ex[1].z)
	p.teleport(Transform3D(Basis(), Vector3(0, 300, 0)))       # leave the start zone first (its 400 u/s cap)
	for i in 5: await physics_frame
	p.teleport(Transform3D(Basis(), ex[0] - Vector3(0, 0.9, 0)))
	p.velocity = ex[1] * a["speed"]
	var landed := Vector3.ZERO
	for i in 60 * 6:
		await physics_frame
		if i > 3 and (p.is_on_floor() or p.get_slide_collision_count() > 0):
			landed = p.global_position
			break
	# note: the arc stops where it ENTERS the finish zone (10 m above the slab), SUCC lands on the slab itself
	print("prediction vs SUCC: arc reaches the finish zone at %s, SUCC lands on the slab at %s, horizontal gap %.1f m"
		% [predicted.snapped(Vector3.ONE * 0.1), landed.snapped(Vector3.ONE * 0.1), Vector2(predicted.x - landed.x, predicted.z - landed.z).length()])
	ed.play.stop()
	ed.show_all_arcs = true
	report("all ramps")
	quit()
