class_name CameraPath
extends RefCounted
## A camera shot's motion: a smooth path through its keys (0.30.0).
##
## A shot is plain data, saved with the map under "shots" (never exported):
##   {"name", "keys": [key...], "timing": "timed" | "even", "length": seconds (even), "tension": 0..1,
##    "look": "none" | "point" | "object", "look_point": [x, y, z], "look_object": object name}
## A key: {"pos": [x, y, z], "yaw", "pitch", "roll", "fov" (degrees, vertical), "dur": seconds to the next key,
##   "ease_in", "ease_out": 0..1 (how much the camera slows down arriving at / leaving this key)}
##
## Position: centripetal Catmull-Rom through every key (no loops or overshoot at uneven spacing), tension 1 = straight
## lines. Rotation: spherical cubic interpolation of quaternions (always the short way round: no flips). Speed: within
## each stretch the camera moves along the curve by distance, its speed eased smoothly from one key's speed to the
## next's (a cubic in distance). "even" timing gives each stretch time in proportion to its length, so with no ease
## the speed is the same all the way.

const DEFAULT_FOV := 70.0
const DEFAULT_DUR := 2.0
const ARC_STEPS := 256                      ## samples per stretch for its length table
const MAX_SLOPE := 2.1                       ## (keeps the distance cubic from ever going backwards: slopes^2 sum <= 9)

var keys: Array = []
var tension := 0.0
var target = null                            ## look-at point (Vector3) or null
var _p: Array[Vector3] = []
var _q: Array[Quaternion] = []
var _tan: Array[Vector3] = []                ## Catmull-Rom tangents, in each stretch's own knot units (see _segment)
var _knot: PackedFloat64Array = []           ## centripetal knot spans
var _len: PackedFloat64Array = []            ## each stretch's length
var _arc: Array[PackedFloat64Array] = []     ## cumulative length at ARC_STEPS + 1 even steps of the curve parameter
var _times: PackedFloat64Array = []          ## when the camera is at each key
var _key_speed: PackedFloat64Array = []


## `look_target`: where the camera looks (a point, or an object's center resolved by the caller), null = its keys.
func _init(shot: Dictionary, look_target = null) -> void:
	keys = (shot.get("keys", []) as Array)
	tension = clampf(float(shot.get("tension", 0.0)), 0.0, 1.0)
	target = look_target
	for k in keys:
		_p.append(key_pos(k))
		var q := Basis.from_euler(_euler(k)).get_rotation_quaternion()
		if not _q.is_empty() and _q[_q.size() - 1].dot(q) < 0.0:
			q = -q                                      # (same rotation, nearer sign: the short way round)
		_q.append(q)
	var n := _p.size()
	for i in maxi(n - 1, 0):
		_knot.append(maxf(sqrt(_p[i].distance_to(_p[i + 1])), 1e-4))
	for i in n:
		_tan.append(_tangent(i))
	for i in maxi(n - 1, 0):
		var table := PackedFloat64Array([0.0])
		var prev := _p[i]
		for s in range(1, ARC_STEPS + 1):
			var at := _curve(i, float(s) / ARC_STEPS)
			table.append(table[s - 1] + prev.distance_to(at))
			prev = at
		_arc.append(table)
		_len.append(table[ARC_STEPS])
	_time_keys(shot)


# ================================================================================================= keys
static func key_pos(k: Dictionary) -> Vector3:
	var p: Array = k.get("pos", [0, 0, 0])
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func _euler(k: Dictionary) -> Vector3:
	return Vector3(deg_to_rad(float(k.get("pitch", 0.0))), deg_to_rad(float(k.get("yaw", 0.0))),
		deg_to_rad(float(k.get("roll", 0.0))))


static func key_transform(k: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(_euler(k)), key_pos(k))


## A key where a camera is now (its rotation as yaw / pitch / roll in degrees, the order Godot's cameras use).
static func key_from(xf: Transform3D, fov: float, dur := DEFAULT_DUR) -> Dictionary:
	var e := xf.basis.orthonormalized().get_euler()
	var r := func(v: float) -> float: return snappedf(v, 0.001)
	return {"pos": [r.call(xf.origin.x), r.call(xf.origin.y), r.call(xf.origin.z)], "yaw": r.call(rad_to_deg(e.y)),
		"pitch": r.call(rad_to_deg(e.x)), "roll": r.call(rad_to_deg(e.z)), "fov": r.call(fov), "dur": dur,
		"ease_in": 0.0, "ease_out": 0.0}


static func new_shot(shot_name: String) -> Dictionary:
	return {"name": shot_name, "keys": [], "timing": "timed", "length": 10.0, "tension": 0.0, "look": "none",
		"look_point": [0, 0, 0], "look_object": ""}


# ================================================================================================= timing
func _time_keys(shot: Dictionary) -> void:
	var n := _p.size()
	var durs := PackedFloat64Array()
	var even := String(shot.get("timing", "timed")) == "even"
	var total_len := 0.0
	for l in _len:
		total_len += l
	var total := maxf(float(shot.get("length", 10.0)), 0.01)
	for i in maxi(n - 1, 0):
		if even:
			durs.append(total * (_len[i] / total_len if total_len > 1e-6 else 1.0 / (n - 1)))
		else:
			durs.append(maxf(float((keys[i] as Dictionary).get("dur", DEFAULT_DUR)), 0.01))
	_times = PackedFloat64Array([0.0])
	for d in durs:
		_times.append(_times[_times.size() - 1] + d)
	# each key's speed: the average of the stretches on either side (so the speed carries smoothly through it)
	var seg_v := PackedFloat64Array()
	for i in durs.size():
		seg_v.append(_len[i] / maxf(durs[i], 1e-6))
	for i in n:
		if seg_v.is_empty():
			_key_speed.append(0.0)
		elif i == 0:
			_key_speed.append(seg_v[0])
		elif i == n - 1:
			_key_speed.append(seg_v[i - 1])
		else:
			_key_speed.append((seg_v[i - 1] + seg_v[i]) * 0.5)


func duration() -> float:
	return _times[_times.size() - 1] if not _times.is_empty() else 0.0


func key_time(i: int) -> float:
	return _times[clampi(i, 0, _times.size() - 1)] if not _times.is_empty() else 0.0


## How long each stretch takes (the "dur" a timed shot would need to play the same way).
func stretch_time(i: int) -> float:
	return key_time(i + 1) - key_time(i)


func length() -> float:
	var t := 0.0
	for l in _len:
		t += l
	return t


## The stretch that time `t` falls in, and how far through it (0..1 of its distance).
func _locate(t: float) -> Array:
	var n := _p.size()
	t = clampf(t, 0.0, duration())
	var i := 0
	while i < n - 2 and t > _times[i + 1]:
		i += 1
	var span := _times[i + 1] - _times[i]
	var u := clampf((t - _times[i]) / span, 0.0, 1.0) if span > 1e-9 else 1.0
	var k0: Dictionary = keys[i]
	var k1: Dictionary = keys[i + 1]
	var a := 1.0 - clampf(float(k0.get("ease_out", 0.0)), 0.0, 1.0)
	var b := 1.0 - clampf(float(k1.get("ease_in", 0.0)), 0.0, 1.0)
	if _len[i] > 1e-6:                                    # (slopes in "fraction of the stretch per fraction of its time")
		a *= _key_speed[i] * span / _len[i]
		b *= _key_speed[i + 1] * span / _len[i]
	a = clampf(a, 0.0, MAX_SLOPE)
	b = clampf(b, 0.0, MAX_SLOPE)
	var u2 := u * u
	var u3 := u2 * u
	var f := (u3 - 2.0 * u2 + u) * a + (-2.0 * u3 + 3.0 * u2) + (u3 - u2) * b
	return [i, clampf(f, 0.0, 1.0)]


# ================================================================================================= the curve
func _pt(i: int) -> Vector3:
	var n := _p.size()
	if i < 0:
		return _p[0] * 2.0 - _p[1] if n > 1 else _p[0]
	if i >= n:
		return _p[n - 1] * 2.0 - _p[n - 2] if n > 1 else _p[n - 1]
	return _p[i]


func _span(i: int) -> float:
	if i < 0:
		return _knot[0]
	if i >= _knot.size():
		return _knot[_knot.size() - 1]
	return _knot[i]


## The curve's direction at key i, per unit of knot (non-uniform Catmull-Rom).
func _tangent(i: int) -> Vector3:
	if _p.size() < 2:
		return Vector3.ZERO
	var d0 := _span(i - 1)
	var d1 := _span(i)
	var p0 := _pt(i - 1)
	var p1 := _pt(i)
	var p2 := _pt(i + 1)
	return (p1 - p0) / d0 - (p2 - p0) / (d0 + d1) + (p2 - p1) / d1


## Point at curve parameter s (0..1) of stretch i.
func _curve(i: int, s: float) -> Vector3:
	var m0 := _tan[i] * _knot[i] * (1.0 - tension)
	var m1 := _tan[i + 1] * _knot[i] * (1.0 - tension)
	var s2 := s * s
	var s3 := s2 * s
	return _p[i] * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + _p[i + 1] * (-2.0 * s3 + 3.0 * s2) + m1 * (s3 - s2)


## The curve parameter at a fraction `f` of stretch i's length.
func _param_at(i: int, f: float) -> float:
	var table := _arc[i]
	var want := f * _len[i]
	if _len[i] <= 1e-9:
		return f
	var lo := 0
	var hi := ARC_STEPS
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if table[mid] < want:
			lo = mid
		else:
			hi = mid
	var seg := table[hi] - table[lo]
	var w := (want - table[lo]) / seg if seg > 1e-12 else 0.0
	return (lo + w) / ARC_STEPS


func _scalar(i: int, f: float, key: String, fallback: float) -> float:
	var n := keys.size()
	var v := func(j: int) -> float: return float((keys[clampi(j, 0, n - 1)] as Dictionary).get(key, fallback))
	var p0: float = v.call(i - 1)
	var p1: float = v.call(i)
	var p2: float = v.call(i + 1)
	var p3: float = v.call(i + 2)
	return Vector2(p1, 0).cubic_interpolate(Vector2(p2, 0), Vector2(p0, 0), Vector2(p3, 0), f).x


# ================================================================================================= sampling
## Where the camera is at time t: {"xf": Transform3D, "fov": degrees}.
func sample(t: float) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {"xf": Transform3D.IDENTITY, "fov": DEFAULT_FOV}
	if n == 1:
		return _aimed(key_transform(keys[0]), float(keys[0].get("roll", 0.0)), float(keys[0].get("fov", DEFAULT_FOV)))
	var at := _locate(t)
	var i: int = at[0]
	var f: float = at[1]
	var pos := _curve(i, _param_at(i, f))
	var qa := _q[maxi(i - 1, 0)]
	var qd := _q[mini(i + 2, n - 1)]
	var q := _q[i].spherical_cubic_interpolate(_q[i + 1], qa, qd, f).normalized()
	var fov := clampf(_scalar(i, f, "fov", DEFAULT_FOV), 1.0, 179.0)
	return _aimed(Transform3D(Basis(q), pos), _scalar(i, f, "roll", 0.0), fov)


func _aimed(xf: Transform3D, roll_deg: float, fov: float) -> Dictionary:
	if target is Vector3:
		var fwd: Vector3 = (target as Vector3) - xf.origin
		if fwd.length() > 1e-3 and absf(fwd.normalized().dot(Vector3.UP)) < 0.999:
			var b := Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg))
			xf = Transform3D(b, xf.origin)
	return {"xf": xf, "fov": fov}


## The path as points (for drawing): `per_stretch` points per stretch, plus the last key.
func polyline(per_stretch := 24) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _len.size():
		for s in per_stretch:
			out.append(_curve(i, float(s) / per_stretch))
	if not _p.is_empty():
		out.append(_p[_p.size() - 1])
	return out
