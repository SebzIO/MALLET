extends SceneTree
## A picture of a co-editor's body in build mode (U17 visual check). This opens a real MALLET window.
## Run: godot --path . --resolution 1600x900 -s res://tools/shoot_avatar.gd -- <out folder>

var ed


func _init() -> void:
	call_deferred("_run")


func _shot(dir: Vector3, at: Vector3, dist: float, look_y: float, file: String) -> void:
	var cam = ed.panes[0].camera                    # (the perspective pane: the view the editor really renders)
	cam.focus = at + Vector3(0, look_y, 0)
	cam.distance = dist
	cam.yaw = atan2(-dir.x, -dir.z)
	cam.pitch = deg_to_rad(-2.0)
	cam._apply()
	ed.co_cursors["peer1"] = {"pos": [at.x, at.y, at.z], "aim": [-dir.x * 0.98, 0.08, -dir.z * 0.98],
		"name": "Alex", "view": "build"}
	ed._update_co_avatars()
	for i in 14:
		await process_frame
	var body: CoAvatar = ed._co_avatars.get("peer1")
	if body != null:
		print("SHOT ", file.get_file(), " cam ", cam.global_position, " yaw ", body.yaw,
			" visor ", body._vis.global_position, " head ", body._head.global_position,
			" skull ", body._skull.global_position, " aabb ", body._skull.get_aabb().size)
	root.get_viewport().get_texture().get_image().save_png(file)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame
	ed.relay = Relay.new()                       # (nothing connects: a body only needs a session to exist)
	ed.show_co_editors = true
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 0.2, 40)
	ground.mesh = box
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.62, 0.6)
	ground.material_override = gm
	ground.position = Vector3(0, -0.1, 0)
	ed.add_child(ground)
	var dir := Vector3(1, 0, 0.35).normalized()
	await _shot(dir, Vector3(0, 0, 0), 5.0, 0.95, out + "/avatar.png")
	await _shot(Vector3(0, 0, 1), Vector3(0, 0, 0), 2.6, 1.05, out + "/avatar_close.png")
	await _shot(Vector3(1, 0, 0), Vector3(0, 0, 0), 2.6, 1.05, out + "/avatar_side.png")
	await _shot(Vector3(0, 0, -1), Vector3(0, 0, 0), 2.6, 1.05, out + "/avatar_back.png")
	await _shot(Vector3(0, 0, 1), Vector3(0, 0, 0), 1.3, 1.63, out + "/avatar_head.png")
	print("AVATAR SHOT DONE")
	quit()
