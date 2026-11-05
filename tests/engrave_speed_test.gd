extends SceneTree
## Engraving: the default text engraved into blocks (top, sides, a turned block, a wide wall, a wedge) must rebuild
## quickly (it once took 100 s) and every carved piece must stay inside its block (a dropped plane once sent a
## piece shooting up into the sky).
## Run: godot --headless --path D:/SurfForge -s res://tests/engrave_speed_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-40s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func case(label: String, block: Dictionary, text: Dictionary) -> void:
	var bs := BlockShape.spec(block)
	var whole := AABB()
	var first := true
	for p in BlockShape.world_pieces(bs):
		var bb := Convex.aabb(p)
		whole = bb if first else whole.merge(bb)
		first = false
	var td := TextShape.spec(text)
	var t0 := Time.get_ticks_msec()
	var pieces := BlockShape.world_pieces(bs, TextShape.cut_pieces(td))
	BlockShape.mesh_faces(pieces, BlockShape.transform_of(bs), bs)
	var ms := Time.get_ticks_msec() - t0
	var worst := 0.0
	for p in pieces:
		for v in Convex.points(p):
			var c := v.clamp(whole.position, whole.end)
			worst = maxf(worst, c.distance_to(v))
	check(label, ms < 3000 and worst < 0.05 and pieces.size() > 20,
		"(%d ms, %d pieces, sticks out %.2f m)" % [ms, pieces.size(), worst])


func _run() -> void:
	case("top of a default block", {"position": [0, 0, 0]}, {"position": [0, 8, 0], "pitch": -90.0, "mode": "engrave"})
	case("+X side, facing 90", {"position": [0, 0, 0]}, {"position": [8, 4, 0], "yaw": 90.0, "mode": "engrave"})
	case("-Z side", {"position": [0, 0, 0]}, {"position": [0, 4, -8], "yaw": 180.0, "mode": "engrave"})
	case("a turned block", {"position": [0, 0, 0], "yaw": 30.0}, {"position": [-4.0, 8, 6.93], "pitch": -90.0, "yaw": 30.0, "mode": "engrave"})
	case("a wide wall", {"position": [100, 140, 140], "size": [40, 16, 32]},
		{"position": [120, 148, 140], "yaw": 90.0, "mode": "engrave"})
	case("a wedge's slope", {"position": [0, 0, 0], "shape": "wedge"}, {"position": [0, 4, 0], "pitch": -63.4, "mode": "engrave"})
	print("ENGRAVE: ", "PASS" if ok else "FAIL")
	quit()
