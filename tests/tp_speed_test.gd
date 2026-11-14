extends SceneTree
## Teleports at speed (0.24.2): a thin teleport (3 m) flush against a wall used to send a fast player (over about
## 2000-3500 u/s, depending on the gap) on standing still - play mode checked where the player stood before the
## move, the move hit the wall first and zeroed the speed, then the teleport carried that zero over. Now this
## tick's move counts: the player's body touching the teleport on the way is enough, at full speed. A teleport
## behind a wall still can't be reached through it, and a thin booster at speed is still felt.
## Run: godot --path . --resolution 1280x720 -s res://tests/tp_speed_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({"entities": [
		{"kind": "start", "position": [0.0, 0.0, 300.0], "size": [20.0, 2.0, 26.0], "yaw": 0.0},
		# a thin teleport whose far side touches a wall
		{"kind": "teleport", "position": [0.0, 100.0, -100.0], "size": [20.0, 24.0, 3.0], "yaw": 0.0, "number": 1, "to": "destination", "keep_speed": true},
		{"kind": "destination", "position": [300.0, 101.75, 0.0], "size": [2.0, 3.5, 2.0], "yaw": 0.0, "number": 1},
		# a teleport hidden behind a wall
		{"kind": "teleport", "position": [-200.0, 100.0, -106.0], "size": [20.0, 24.0, 3.0], "yaw": 0.0, "number": 2, "to": "destination", "keep_speed": true},
		{"kind": "destination", "position": [300.0, 151.75, 0.0], "size": [2.0, 3.5, 2.0], "yaw": 0.0, "number": 2},
		# a thin booster in open air
		{"kind": "booster", "position": [-400.0, 100.0, -100.0], "size": [20.0, 24.0, 1.0], "yaw": 0.0, "strength": 500.0, "mode": 0, "pitch": 0.0}],
		"blocks": [{"shape": "box", "position": [0.0, 80.0, -101.8], "size": [40.0, 40.0, 4.0]},   # (its face 1.3 m into the teleport)
			{"shape": "box", "position": [-200.0, 80.0, -101.0], "size": [40.0, 40.0, 4.0]}]})
	await process_frame
	# the editor's warning (0.24.3): thin and touching solid geometry
	for i in 3:
		await physics_frame
	var risky: Array = ed.check_teleports()
	var tp1: EntityNode = ed.entities_root.get_child(1)
	var tp2: EntityNode = ed.entities_root.get_child(3)
	check("the editor flags a thin teleport that runs into a wall", tp1 in risky and tp1.risk != "", tp1.risk.left(60))
	check("...but not one clear of the wall", not tp2 in risky)
	ed._select(tp1)
	ed._refresh_info()
	check("...and says why in its info panel", String(ed._info.text).contains("May be missed at speed"))
	ed._select(null)
	tp1.from_dict(tp1.to_dict().merged({"size": [20.0, 24.0, 8.0]}, true))
	for i in 3:
		await physics_frame
	check("...nor one made deep enough", not tp1 in ed.check_teleports())
	tp1.from_dict(tp1.to_dict().merged({"size": [20.0, 24.0, 3.0]}, true))
	for i in 3:
		await physics_frame
	ed.check_teleports()
	ed._play_clicked()
	for i in 5:
		await physics_frame
	var p: SUCC = ed.play.player
	p.global_position = Vector3(-50, 200, 0)
	for i in 3:
		await physics_frame
	var worst := 1e9
	var detail := []
	for ups in [1000.0, 2000.0, 2600.0, 3500.0, 4500.0, 6000.0]:
		var v: float = ups / 39.37
		var low := 1e9
		for phase in 5:                                  # (where in a tick the player meets the teleport)
			p.global_position = Vector3(0, 99.1, -80.0 - v / 60.0 * phase / 5.0)
			p.velocity = Vector3(0, 0, -v)
			var kept := -1.0
			for i in 60:
				await physics_frame
				if p.global_position.x > 250.0:
					await physics_frame
					kept = Vector2(p.velocity.x, p.velocity.z).length() * 39.37
					break
			low = minf(low, kept)
		worst = minf(worst, low / ups if low >= 0.0 else -1.0)
		detail.append("%d->%d" % [ups, roundi(low)])
	check("a thin teleport against a wall keeps the speed, 1000-6000 u/s", worst > 0.97, " ".join(detail))
	p.global_position = Vector3(-200, 99.1, -80.0)
	p.velocity = Vector3(0, 0, -3500.0 / 39.37)
	var through := false
	for i in 30:
		await physics_frame
		if p.global_position.x > 250.0:
			through = true
	check("a teleport behind a wall can't be reached through it", not through, str(p.global_position.snapped(Vector3.ONE * 0.1)))
	p.global_position = Vector3(-400, 99.1, -80.0)
	p.velocity = Vector3(0, 0, -4000.0 / 39.37)
	for i in 20:
		await physics_frame
	check("a thin booster is felt at 4000 u/s", Vector2(p.velocity.x, p.velocity.z).length() * 39.37 > 4300.0,
		"(%d u/s)" % roundi(Vector2(p.velocity.x, p.velocity.z).length() * 39.37))
	ed.play.stop()
	print("tp_speed_test: ", "PASS" if ok else "FAIL")
	quit()
