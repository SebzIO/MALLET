extends SceneTree
## Camera shots' path math (0.30.0): the path goes through every key at its time, rotation never flips (yaw across
## +-180, a roll), even timing gives a constant speed, ease slows the camera down at a key, tension 1 = straight
## lines, and a look-at target is looked at.
##   godot --headless --path . -s res://tests/camera_path_test.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func key(p: Vector3, yaw: float, pitch := 0.0, roll := 0.0, dur := 2.0, fov := 70.0) -> Dictionary:
	return {"pos": [p.x, p.y, p.z], "yaw": yaw, "pitch": pitch, "roll": roll, "fov": fov, "dur": dur,
		"ease_in": 0.0, "ease_out": 0.0}


func _init() -> void:
	var shot := CameraPath.new_shot("test")
	shot["keys"] = [key(Vector3(0, 10, 0), 170.0, -10.0, 0.0, 1.5), key(Vector3(40, 12, 3), -170.0, 5.0, 20.0, 3.0),
		key(Vector3(42, 30, 60), -90.0, -40.0, 0.0, 0.7), key(Vector3(0, 5, 61), 0.0, 0.0, 0.0, 2.0, 40.0),
		key(Vector3(1, 5, 62), 10.0)]                  # (last two keys close together: centripetal must not loop)
	var path := CameraPath.new(shot)
	check(is_equal_approx(path.duration(), 1.5 + 3.0 + 0.7 + 2.0), "timed: duration is the sum of the keys' times (%.3f)" % path.duration())
	# 1. through every key, at its time, with its rotation and FOV
	var worst_p := 0.0
	var worst_r := 0.0
	for i in shot["keys"].size():
		var k: Dictionary = shot["keys"][i]
		var s := path.sample(path.key_time(i))
		var want := CameraPath.key_transform(k)
		worst_p = maxf(worst_p, (s["xf"] as Transform3D).origin.distance_to(want.origin))
		worst_r = maxf(worst_r, (s["xf"] as Transform3D).basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()))
		check(absf(float(s["fov"]) - float(k["fov"])) < 1e-3, "key %d: FOV %.2f" % [i, float(s["fov"])])
	check(worst_p < 1e-3, "passes through every key (worst %.5f m)" % worst_p)
	check(worst_r < 1e-3, "has every key's rotation at its time (worst %.5f rad)" % worst_r)
	# 2. no flips: from yaw 170 to yaw -170 is 20 degrees, never the 340 the long way round
	var steps := 600
	var max_step := 0.0
	var turned := 0.0
	var prev: Quaternion = (path.sample(0.0)["xf"] as Transform3D).basis.get_rotation_quaternion()
	for j in range(1, steps + 1):
		var t := path.key_time(1) * j / steps
		var q: Quaternion = (path.sample(t)["xf"] as Transform3D).basis.get_rotation_quaternion()
		var a := q.angle_to(prev)
		max_step = maxf(max_step, a)
		turned += a
		prev = q
	var direct := CameraPath.key_transform(shot["keys"][0]).basis.get_rotation_quaternion().angle_to(
		CameraPath.key_transform(shot["keys"][1]).basis.get_rotation_quaternion())
	check(turned < direct * 1.6 + 0.05, "yaw 170 -> -170 turns the short way (%.1f deg turned, %.1f apart)" % [rad_to_deg(turned), rad_to_deg(direct)])
	check(max_step < 0.02, "no sudden turn anywhere in the first stretch (largest step %.4f rad)" % max_step)
	# the whole shot: no frame turns more than a few degrees (60 fps)
	var big := 0.0
	prev = (path.sample(0.0)["xf"] as Transform3D).basis.get_rotation_quaternion()
	var f := 1
	while f / 60.0 <= path.duration():
		var q2: Quaternion = (path.sample(f / 60.0)["xf"] as Transform3D).basis.get_rotation_quaternion()
		big = maxf(big, rad_to_deg(q2.angle_to(prev)))
		prev = q2
		f += 1
	check(big < 6.0, "whole shot at 60 fps: largest turn in one frame %.2f deg" % big)
	# position steps are smooth too (no jumps between frames)
	var jump := 0.0
	var last: Vector3 = (path.sample(0.0)["xf"] as Transform3D).origin
	f = 1
	while f / 60.0 <= path.duration():
		var p: Vector3 = (path.sample(f / 60.0)["xf"] as Transform3D).origin
		jump = maxf(jump, p.distance_to(last))
		last = p
		f += 1
	check(jump < 2.0, "largest move in one frame %.3f m" % jump)
	# 3. close keys: the curve between keys 3 and 4 stays near them (centripetal: no loop)
	var far := 0.0
	for j in 101:
		var t := lerpf(path.key_time(3), path.key_time(4), j / 100.0)
		far = maxf(far, (path.sample(t)["xf"] as Transform3D).origin.distance_to(Vector3(0.5, 5, 61.5)))
	check(far < 2.5, "two close keys: no loop between them (furthest %.3f m from their middle)" % far)
	# 4. even timing: constant speed all the way
	var even := shot.duplicate(true)
	even["timing"] = "even"
	even["length"] = 12.0
	var ep := CameraPath.new(even)
	check(is_equal_approx(ep.duration(), 12.0), "even: duration is the shot length")
	var want_v := ep.length() / 12.0
	var lo := INF
	var hi := 0.0
	var a0: Vector3 = (ep.sample(0.0)["xf"] as Transform3D).origin
	for j in range(1, 721):
		var v := 0.0                                      # (summed over tenths of a frame: chords cut sharp bends)
		for sub in range(1, 11):
			var b0: Vector3 = (ep.sample((j - 1 + sub / 10.0) / 60.0)["xf"] as Transform3D).origin
			v += a0.distance_to(b0) * 60.0
			a0 = b0
		lo = minf(lo, v)
		hi = maxf(hi, v)
	check(lo > want_v * 0.97 and hi < want_v * 1.03, "even: speed %.2f..%.2f m/s, want %.2f" % [lo, hi, want_v])
	# 5. ease: slow near the eased key, the same total time
	var eased := shot.duplicate(true)
	eased["keys"][1]["ease_in"] = 1.0
	eased["keys"][1]["ease_out"] = 1.0
	var zp := CameraPath.new(eased)
	var t1 := zp.key_time(1)
	var v_near: float = (zp.sample(t1 - 0.01)["xf"] as Transform3D).origin.distance_to((zp.sample(t1)["xf"] as Transform3D).origin) / 0.01
	var v_mid: float = (zp.sample(t1 * 0.5)["xf"] as Transform3D).origin.distance_to((zp.sample(t1 * 0.5 + 0.01)["xf"] as Transform3D).origin) / 0.01
	check(v_near < v_mid * 0.1, "ease: arriving at the eased key %.2f m/s vs %.2f mid-stretch" % [v_near, v_mid])
	var back := 0
	var dist_prev := -1.0
	for j in 201:
		var p: Vector3 = (zp.sample(t1 * j / 200.0)["xf"] as Transform3D).origin
		var d := p.distance_to(CameraPath.key_pos(eased["keys"][0]))
		if dist_prev >= 0.0 and d < dist_prev - 0.05:
			back += 1
		dist_prev = d
	check(back == 0, "ease never moves the camera backwards (%d backward steps)" % back)
	# 6. tension 1: straight between keys
	var tight := shot.duplicate(true)
	tight["tension"] = 1.0
	var tp := CameraPath.new(tight)
	var mid: Vector3 = (tp.sample(tp.key_time(1) * 0.5)["xf"] as Transform3D).origin
	var seg_a := CameraPath.key_pos(tight["keys"][0])
	var seg_b := CameraPath.key_pos(tight["keys"][1])
	var off := mid.distance_to(Geometry3D.get_closest_point_to_segment(mid, seg_a, seg_b))
	check(off < 1e-3, "tension 1: straight line between keys (%.5f m off)" % off)
	# 7. look-at
	var target := Vector3(20, 0, 30)
	var lp := CameraPath.new(shot, target)
	var worst := 0.0
	for j in 50:
		var xf: Transform3D = lp.sample(lp.duration() * j / 49.0)["xf"]
		worst = maxf(worst, (-xf.basis.z).angle_to(target - xf.origin))
	check(worst < 1e-3, "look-at: always looks at the target (worst %.5f rad)" % worst)
	# 8. key_from <-> key_transform round trip (with roll)
	var xf0 := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-25), deg_to_rad(130), deg_to_rad(12))), Vector3(1, 2, 3))
	var k0 := CameraPath.key_from(xf0, 55.0)
	var back_xf := CameraPath.key_transform(k0)
	check(back_xf.origin.distance_to(xf0.origin) < 1e-3 and back_xf.basis.get_rotation_quaternion().angle_to(xf0.basis.get_rotation_quaternion()) < 1e-4,
		"a key made from a camera gives that camera back (yaw %.1f pitch %.1f roll %.1f)" % [k0["yaw"], k0["pitch"], k0["roll"]])
	# 9. one key / no keys
	var one := CameraPath.new({"keys": [key(Vector3(1, 2, 3), 45.0)]})
	check(is_zero_approx(one.duration()) and (one.sample(5.0)["xf"] as Transform3D).origin == Vector3(1, 2, 3), "one key: a still shot")
	check(is_zero_approx(CameraPath.new({}).duration()), "no keys: an empty shot")
	print("camera_path_test: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
