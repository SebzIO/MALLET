extends SceneTree
## Play-mode test: editor -> Play on a long ramp -> a bot surfs it through SUCC -> screenshots -> back to editor.
## Run: godot --path . --resolution 1600x900 -s res://tests/play_test.gd -- <out_dir>

var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	# a long gently-curving ramp
	var r: RampNode = ed.selected
	r.points = PackedVector3Array([Vector3(-200, 220, 0), Vector3(0, 180, 30), Vector3(200, 140, 0), Vector3(380, 100, -60)])
	r.rebuild()
	ed._play_clicked()
	print("playing: ", ed.play.active)
	var p: SUCC = ed.play.player
	p.command = SUCCInput.new()
	p.command.yaw = p.rotation.y
	for i in 60 * 6:
		await physics_frame
		var near := RampShape.nearest_on_path(r.points, p.global_position)
		var ridge: Vector3 = near["point"]
		var ahead: Vector3 = ridge + (p.velocity.normalized() * 6.0 if p.velocity.length() > 1 else Vector3.ZERO)
		var next: Vector3 = RampShape.nearest_on_path(r.points, ahead)["point"]
		var along: Vector3 = next - ridge
		along.y = 0
		if along.length() > 0.5:
			p.command.yaw = atan2(-along.x, -along.z)          # look down the ramp
		var off := Vector2(p.global_position.x - ridge.x, p.global_position.z - ridge.z).length()
		var right := Vector3(cos(p.command.yaw), 0, -sin(p.command.yaw))
		var to_ridge := (ridge - p.global_position).dot(right)
		var dirn := 1.0 if to_ridge > 0 else -1.0
		p.command.move = Vector2(dirn, 0) if off > 3.0 else (Vector2(-0.3 * dirn, 0) if off < 1.5 else Vector2.ZERO)
		if i == 150:
			p.camera_rig.pitch = deg_to_rad(-12)
			await shot("play_1")
		if i == 300:
			await shot("play_2")
	print("speed after 6 s: %d u/s (top %d)" % [roundi(Vector2(p.velocity.x, p.velocity.z).length() * 39.37), roundi(ed.play.top_speed)])
	ed.play.stop()
	await shot("back_in_editor")
	print("status: ", ed._status.text)
	quit()
