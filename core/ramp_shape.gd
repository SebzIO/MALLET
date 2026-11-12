class_name RampShape
extends RefCounted
## Builds surf-ramp geometry from a handful of control points.
##
## The spine (ridge line) is a centripetal Catmull-Rom curve through the control points. It is cut into stations
## evenly spaced by arc length, and at every station the cross-section is placed in an UPRIGHT frame:
##   right = the horizontal direction of travel x world up   (always level: never rolls, never flips)
##   up    = world up                     (slice "vertical", the default: the profile stays in a vertical slice
##                                         even on steep climbs or drops)
##         = perpendicular to travel      (slice "perpendicular": the profile leans with the slope)
## The cross-section is an isosceles triangle hanging from the spine:
##   left_edge  = spine - right * L cos(a) - up * L sin(a)
##   right_edge = spine + right * L cos(b) - up * L sin(b)
## with L the face length and a / b the slope angles (equal unless the ramp is Freeform).
## Half ramps keep only one face, with a vertical back wall. Everything here is plain data in, mesh out - no
## scene knowledge - so the editor, the exporters and the tests all share it.

const UV_METRES := 20.0          ## texture repeats every 20 m along the ramp
const HOLLOW_SKIN := 0.6         ## thickness of a hollow ramp's shell (m)
const STYLES := ["v", "half_left", "half_right"]

## Every ramp setting with its default. `spec()` fills these in for any ramp dictionary.
const DEFAULTS := {
	"style": "v",                  ## "v" both faces, "half_left" / "half_right" one face (left/right seen along travel)
	"solid": false,                ## closed flat bottom instead of an open shell
	"base_depth": 0.0,             ## solid: how far the bottom extends below the face edges
	"angle": 56.0,                 ## slope angle of the faces (left face in Freeform), degrees from level
	"face_length": 10.5,           ## slant length of each face, ridge to edge (left face in Freeform), meters
	"angle_right": 56.0,           ## Freeform only
	"face_length_right": 10.5,     ## Freeform only
	"slice": "vertical",           ## "vertical" or "perpendicular" (how the profile is held on climbs and drops)
	"detail": 1.0,                 ## stations per meter along the spine (smoothness / polygon count)
	"freeform": false,             ## lets the right face have its own angle and length
	"frozen": [],                  ## locked sections, first to last: {end, angle, face_length, angle_right,
	                               ## face_length_right, end_ghost, tangent_lock} (see "Sections" below)
	"seam_tangent_lock": true,     ## the editable section leaves its seam along the locked section's tangent
	"profile": {},                 ## a custom cross-section (ramp creator): see profile_spec(). {} = straight faces
	"ends": {},                    ## shaped ends (ramp creator): see end_spec(). {} = square ends
	"path": "smooth",              ## "smooth": a curve through the points (maps before 0.19.6); "corners": straight
	                               ## between the points, rounded only near each one (new ramps)
	"corner": 0.25,                ## "corners": how much of the shorter neighboring stretch each rounding takes (0-0.5)
	"roll": 0.0,                   ## the cross-section banked around the spine, degrees (+ = towards the right)
}
## A face's custom shape: points [t, n] between the ridge and the edge, t = 0..1 along the face, n = how far out of
## the face (+, away from the ramp's body) or into it (-), both as fractions of the face length, so the shape
## follows any angle or face length. "same": the right face mirrors the left. "top": a flat top this wide (m).
const PROFILE_DEFAULTS := {"left": [], "right": [], "same": true, "top": 0.0}
## One end of the ramp. shape "square" / "taper" (grows from a point) / "round" (a quarter circle) / "flare" (wider
## at the very end by `amount`), over `length` meters; `cut` turns the end face in plan view (diagonal cut, degrees);
## `lip` lifts the ramp up to that height over `lip_length` meters (a kicker); `closed` closes a hollow ramp's end.
const END_DEFAULTS := {"shape": "square", "length": 12.0, "amount": 0.5, "cut": 0.0, "lip": 0.0, "lip_length": 10.0,
	"closed": false}
const END_SHAPES := ["square", "taper", "round", "flare"]
const MIN_END_SCALE := 0.05      ## a taper / round end starts this small (a point would be a broken brush in CS:S)
const STAND_NORMAL_Y := 0.7      ## Source: steeper than this (normal.y < 0.7, about 45.6 degrees) is surfable
const STRIP_TOLERANCE := 0.03   ## meters: how far a texture may bend where a ramp changes width (see build)
const MAX_STRIPS := 160               ## (a rounded end widens about 4 m in its first meter)
const SEAM_BLEND := 30.0         ## meters over which a section bends from the inherited seam direction to its own
const SETTINGS_BLEND := 20.0     ## meters over which a section's angle / face length blend in from the seam


## A complete, consistent set of ramp settings from a (possibly partial) dictionary. Outside Freeform the right
## face mirrors the left. A dictionary with only width/height is converted.
static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate()
	if d.has("width") and d.has("height") and not d.has("face_length"):
		var half := float(d["width"]) * 0.5
		var h := float(d["height"])
		s["face_length"] = sqrt(half * half + h * h)
		s["angle"] = rad_to_deg(atan2(h, half))
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	for k in ["base_depth", "angle", "face_length", "angle_right", "face_length_right", "detail", "corner", "roll"]:
		s[k] = float(s[k])
	if not s["path"] in ["smooth", "corners"]:
		s["path"] = "smooth"
	s["corner"] = clampf(s["corner"], 0.02, 0.5)
	s["solid"] = bool(s["solid"])
	s["freeform"] = bool(s["freeform"])
	s["seam_tangent_lock"] = bool(s["seam_tangent_lock"])
	s["frozen"] = (s["frozen"] as Array).duplicate(true)
	s["profile"] = profile_spec(s["profile"] if s["profile"] is Dictionary else {})
	s["ends"] = {"start": end_spec((s["ends"] as Dictionary).get("start", {}) if s["ends"] is Dictionary else {}),
		"end": end_spec((s["ends"] as Dictionary).get("end", {}) if s["ends"] is Dictionary else {})}
	if not s["style"] in STYLES:
		s["style"] = "v"
	if not s["freeform"]:
		s["angle_right"] = s["angle"]
		s["face_length_right"] = s["face_length"]
	return s


## A complete custom cross-section from a (possibly partial) one: points sorted, kept inside the face.
static func profile_spec(d: Dictionary) -> Dictionary:
	var p := PROFILE_DEFAULTS.duplicate(true)
	for k in PROFILE_DEFAULTS:
		if d.has(k):
			p[k] = d[k]
	for side in ["left", "right"]:
		var pts := []
		for q in (p[side] if p[side] is Array else []):
			if q is Array and q.size() >= 2:
				pts.append([clampf(float(q[0]), 0.01, 0.99), clampf(float(q[1]), -0.6, 0.6)])
		pts.sort_custom(func(a, b): return a[0] < b[0])
		p[side] = pts
	p["same"] = bool(p["same"])
	p["top"] = clampf(float(p["top"]), 0.0, 40.0)
	if p["same"]:
		p["right"] = (p["left"] as Array).duplicate(true)
	return p


static func end_spec(d: Dictionary) -> Dictionary:
	var e := END_DEFAULTS.duplicate()
	for k in END_DEFAULTS:
		if d.has(k):
			e[k] = d[k]
	if not e["shape"] in END_SHAPES:
		e["shape"] = "square"
	for k in ["length", "amount", "cut", "lip", "lip_length"]:
		e[k] = float(e[k])
	e["length"] = maxf(e["length"], 0.5)
	e["lip_length"] = maxf(e["lip_length"], 0.5)
	e["cut"] = clampf(e["cut"], -75.0, 75.0)
	e["closed"] = bool(e["closed"])
	return e


## Whether the ramp has a custom cross-section (the plain V / half ramp geometry is kept exactly otherwise).
static func custom_profile(s: Dictionary) -> bool:
	var p: Dictionary = s.get("profile", {})
	return not (p.get("left", []) as Array).is_empty() or not (p.get("right", []) as Array).is_empty() or float(p.get("top", 0.0)) > 0.0


## Whether either end is shaped.
static func custom_ends(s: Dictionary) -> bool:
	var e: Dictionary = s.get("ends", {})
	for k in ["start", "end"]:
		var d: Dictionary = e.get(k, {})
		if d.get("shape", "square") != "square" or float(d.get("cut", 0.0)) != 0.0 or float(d.get("lip", 0.0)) != 0.0 \
				or bool(d.get("closed", false)):
			return true
	return false


## How far the lowest point of the cross-section sits below the spine (for kill floors and framing).
static func depth_below_spine(s: Dictionary) -> float:
	if custom_profile(s):
		var lowest := 0.0
		for q in profile(s)["pts"]:
			lowest = minf(lowest, q.y)
		var fl := float(s["ends"]["start"]["amount"]) if s["ends"]["start"]["shape"] == "flare" else 0.0
		var fr := float(s["ends"]["end"]["amount"]) if s["ends"]["end"]["shape"] == "flare" else 0.0
		return -lowest * (1.0 + maxf(fl, fr))
	var l := float(s["face_length"]) * sin(deg_to_rad(s["angle"]))
	var r := float(s["face_length_right"]) * sin(deg_to_rad(s["angle_right"]))
	return maxf(l, r) + (float(s["base_depth"]) if s["solid"] else HOLLOW_SKIN)


## Slope (tan of the angle) of the face a rider lands on: side +1 = right face, -1 = left. Half ramps only
## have the one face.
static func face_slope(s: Dictionary, side := 1.0) -> float:
	var a: float = s["angle_right"] if side > 0.0 else s["angle"]
	if s["style"] == "half_left":
		a = s["angle"]
	elif s["style"] == "half_right":
		a = s["angle_right"]
	return tan(deg_to_rad(a))


## Which face a jump must land on for this ramp style (+1 right, -1 left), or `wanted` for a V ramp.
static func landing_side(s: Dictionary, wanted: float) -> float:
	match s["style"]:
		"half_left": return -1.0
		"half_right": return 1.0
	return wanted


# ------------------------------------------------------------------------------------------------ spine
## The four Catmull-Rom control points of span i. Past either end the curve normally mirrors the last span (so
## the ends run straight-ish); a "ghost" point given for that end is used instead, which lets a locked section
## keep exactly the curve it had while it was still joined to the points after it.
static func _span(points: PackedVector3Array, i: int, ghosts := []) -> Array:
	var n := points.size()
	var p1 := points[i]
	var p2 := points[i + 1]
	var p0: Vector3 = points[i - 1] if i > 0 else (ghosts[0] if ghosts.size() > 0 and ghosts[0] != null else p1 - (p2 - p1))
	var p3: Vector3 = points[i + 2] if i + 2 < n else (ghosts[1] if ghosts.size() > 1 and ghosts[1] != null else p2 + (p2 - p1))
	return [p0, p1, p2, p3]


static func _eval(points: PackedVector3Array, i: int, t: float, ghosts := []) -> Vector3:
	var c := _span(points, i, ghosts)
	return _catmull_rom(c[0], c[1], c[2], c[3], t)


## Stations evenly spaced by arc length (about `spacing` meters apart, the ends exactly on the first and last
## point), each with the spine's own tangent there (the curve's derivative, not differences between vertices).
## `ghosts` = [before the first point, after the last point] (null = mirror). `start_tangent`, if given, bends
## the first SEAM_BLEND meters so the spine leaves its first point exactly along it (a smooth seam).
## Returns {"pos": PackedVector3Array, "tan": PackedVector3Array, "dist": PackedFloat32Array, "length": float}.
static func stations(points: PackedVector3Array, spacing: float, ghosts := [], start_tangent := Vector3.ZERO,
		corner := -1.0) -> Dictionary:
	if corner > 0.0 and points.size() >= 2:
		var cp := _corner_path(points, spacing * 0.25, corner)
		if start_tangent == Vector3.ZERO:
			return _resample(cp["pos"], cp["tan"], spacing)
	if start_tangent == Vector3.ZERO or points.size() < 2:
		return _stations_raw(points, spacing, ghosts)
	var fine := _stations_raw(points, spacing * 0.25, ghosts) if corner <= 0.0 else _corner_path(points, spacing * 0.25, corner)
	if not fine.has("dist"):
		var cum := PackedFloat32Array([0.0])
		var fp: PackedVector3Array = fine["pos"]
		for i in range(1, fp.size()):
			cum.append(cum[i - 1] + fp[i].distance_to(fp[i - 1]))
		fine["dist"] = cum
	var pos: PackedVector3Array = fine["pos"]
	var tan: PackedVector3Array = fine["tan"]
	var dist: PackedFloat32Array = fine["dist"]
	var corr := start_tangent.normalized() - tan[0]
	if corr.length() < 1e-6:
		return _stations_raw(points, spacing, ghosts)
	# add (T - T0) * f(s), f(s) = s (1 - s/B)^2: zero at both ends of the blend, slope 1 at the seam and 0 at B,
	# so the spine starts along T and rejoins its own shape smoothly
	for i in pos.size():
		var u := dist[i] / SEAM_BLEND
		if u >= 1.0:
			break
		pos[i] += corr * dist[i] * (1.0 - u) * (1.0 - u)
		tan[i] = (tan[i] + corr * (1.0 - u) * (1.0 - 3.0 * u)).normalized()
	return _resample(pos, tan, spacing)


## The "corners" path (0.19.6): straight from point to point, with each inner point's corner rounded by a curve
## that starts and ends `corner` of the shorter neighboring stretch away from it (a quadratic Bezier with the point
## as its control: it leaves and joins the straight lines along them). Dense points `step` meters apart, with
## tangents. The ramp keeps the lines you set instead of sagging under them and flaring up at the end.
static func _corner_path(points: PackedVector3Array, step: float, corner: float) -> Dictionary:
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var n := points.size()
	var a := []                                          # where each corner's rounding starts and ends
	var b := []
	for i in n:
		if i == 0 or i == n - 1:
			a.append(points[i])
			b.append(points[i])
			continue
		var dp := points[i] - points[i - 1]
		var dn := points[i + 1] - points[i]
		var r := corner * minf(dp.length(), dn.length())
		a.append(points[i] - dp.normalized() * r)
		b.append(points[i] + dn.normalized() * r)
	for i in n:
		if i > 0:                                        # the straight from the last corner's end to this one's start
			var p0: Vector3 = b[i - 1]
			var p1: Vector3 = a[i]
			var d := p1 - p0
			var m := maxi(1, ceili(d.length() / maxf(step, 0.01)))
			var t := d.normalized() if d.length() > 1e-6 else (points[i] - points[i - 1]).normalized()
			for k in range(1, m + 1) if not pos.is_empty() else range(0, m + 1):
				pos.append(p0.lerp(p1, float(k) / m))
				tan.append(t)
		if i > 0 and i < n - 1:                          # the rounding at this point
			var c0: Vector3 = a[i]
			var c1: Vector3 = points[i]
			var c2: Vector3 = b[i]
			var arc := c0.distance_to(c1) + c1.distance_to(c2)
			var m := maxi(4, ceili(arc / maxf(step, 0.01)))
			for k in range(1, m + 1):
				var t := float(k) / m
				pos.append(c0 * (1.0 - t) * (1.0 - t) + c1 * 2.0 * t * (1.0 - t) + c2 * t * t)
				var dv := (c1 - c0) * 2.0 * (1.0 - t) + (c2 - c1) * 2.0 * t
				tan.append(dv.normalized() if dv.length() > 1e-6 else (c2 - c0).normalized())
	if pos.is_empty():
		pos.append(points[0])
		tan.append((points[n - 1] - points[0]).normalized())
	return {"pos": pos, "tan": tan}


## Even arc-length stations along a dense polyline (positions and tangents interpolated between its points).
static func _resample(pos: PackedVector3Array, tan: PackedVector3Array, spacing: float) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pos.size()):
		cum.append(cum[i - 1] + pos[i].distance_to(pos[i - 1]))
	var total := cum[cum.size() - 1]
	var count: int = maxi(1, int(ceil(total / maxf(spacing, 0.05))))
	var out_p := PackedVector3Array()
	var out_t := PackedVector3Array()
	var out_d := PackedFloat32Array()
	var j := 0
	for k in count + 1:
		var s := total * k / count
		while j < cum.size() - 2 and cum[j + 1] < s:
			j += 1
		var seg := cum[j + 1] - cum[j]
		var f := clampf((s - cum[j]) / seg, 0.0, 1.0) if seg > 1e-6 else 0.0
		out_p.append(pos[pos.size() - 1] if k == count else (pos[0] if k == 0 else pos[j].lerp(pos[j + 1], f)))
		out_t.append(tan[j].lerp(tan[j + 1], f).normalized())
		out_d.append(s)
	return {"pos": out_p, "tan": out_t, "dist": out_d, "length": total}


static func _stations_raw(points: PackedVector3Array, spacing: float, ghosts := []) -> Dictionary:
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var dist := PackedFloat32Array()
	var n := points.size()
	if n < 2:
		return {"pos": pos, "tan": tan, "dist": dist, "length": 0.0}
	# dense table of (span, t, cumulative length) to invert arc length
	var tab_i := PackedInt32Array()
	var tab_t := PackedFloat32Array()
	var tab_s := PackedFloat32Array()
	var total := 0.0
	var prev := points[0]
	for i in n - 1:
		var m: int = clampi(int(ceil(points[i].distance_to(points[i + 1]) * 4.0)), 8, 4000)
		for k in m + 1:
			if i > 0 and k == 0:
				continue
			var t := float(k) / m
			var q := _eval(points, i, t, ghosts)
			total += q.distance_to(prev)
			prev = q
			tab_i.append(i)
			tab_t.append(t)
			tab_s.append(total)
	var count: int = maxi(1, int(ceil(total / maxf(spacing, 0.05))))
	var j := 0
	var last_tan := (points[1] - points[0]).normalized()
	for k in count + 1:
		var s := total * k / count
		while j < tab_s.size() - 2 and tab_s[j + 1] < s:
			j += 1
		var i: int = tab_i[j + 1]
		var t: float = tab_t[j]
		var t2: float = tab_t[j + 1]
		if tab_i[j] != i:                             # entry j is the end of the previous span = the start of this one
			t = 0.0
		var seg := tab_s[j + 1] - tab_s[j]
		var f := clampf((s - tab_s[j]) / seg, 0.0, 1.0) if seg > 1e-6 else 0.0
		var tt := lerpf(t, t2, f)
		var p := points[n - 1] if k == count else (points[0] if k == 0 else _eval(points, i, tt, ghosts))
		var h := 1e-3
		var d := _eval(points, i, minf(tt + h, 1.0), ghosts) - _eval(points, i, maxf(tt - h, 0.0), ghosts)
		if d.length() > 1e-7:
			last_tan = d.normalized()
		pos.append(p)
		tan.append(last_tan)
		dist.append(s)
	return {"pos": pos, "tan": tan, "dist": dist, "length": total}


# ------------------------------------------------------------------------------------------------ sections
## A ramp with locks is a chain of sections joined at the locked points. Every locked ("frozen") section keeps
## its points, its face settings and a ghost of the point that followed it when it was locked, so its curve can
## never change again; the last section is the editable one. Each section after the first starts exactly where
## the previous one ended, leaving along the same tangent (tangent lock) and blending its face settings in from
## the seam's, so the join has no kink and no step.
## Returns [{from, to, values: [angle, face_length, angle_right, face_length_right], end_ghost, tangent_lock}].
static func sections(points: PackedVector3Array, s: Dictionary) -> Array:
	var out := []
	var start := 0
	for f in s["frozen"]:
		var end: int = int(f["end"])
		var g = f.get("end_ghost")
		out.append({"from": start, "to": end, "values": _values(f, s["freeform"]),
			"end_ghost": Vector3(g[0], g[1], g[2]) if g is Array and g.size() == 3 else null,
			"tangent_lock": bool(f.get("tangent_lock", true))})
		start = end
	out.append({"from": start, "to": points.size() - 1, "values": _values(s, s["freeform"]), "end_ghost": null,
		"tangent_lock": bool(s["seam_tangent_lock"])})
	return out


static func _values(d: Dictionary, freeform: bool) -> Array:
	var a := float(d.get("angle", 56.0))
	var l := float(d.get("face_length", 10.5))
	if freeform:
		return [a, l, float(d.get("angle_right", a)), float(d.get("face_length_right", l))]
	return [a, l, a, l]


## The whole spine, section by section: stations, tangents, distances, the face settings at every station and
## the station index of every seam.
static func spine(points: PackedVector3Array, s: Dictionary) -> Dictionary:
	var spacing := 1.0 / maxf(s["detail"], 0.05)
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var dist := PackedFloat32Array()
	var values: Array = []
	var seams := PackedInt32Array()
	var offset := 0.0
	var prev_tan := Vector3.ZERO
	var prev_vals: Array = []
	var secs := sections(points, s)
	if s["path"] == "corners" and secs.size() > 1:
		return _corner_spine(points, s, secs, spacing)
	for k in secs.size():
		var sec: Dictionary = secs[k]
		var sub := points.slice(sec["from"], sec["to"] + 1)
		if sub.size() < 2:
			continue
		var ghosts := [points[sec["from"] - 1] if sec["from"] > 0 else null, sec["end_ghost"]]
		var st := stations(sub, spacing, ghosts, prev_tan if k > 0 and sec["tangent_lock"] else Vector3.ZERO,
			float(s["corner"]) if s["path"] == "corners" else -1.0)
		var v: Array = sec["values"]
		for i in st["pos"].size():
			if k > 0 and i == 0:
				continue                                # the seam station is the previous section's last one
			pos.append(st["pos"][i])
			tan.append(st["tan"][i])
			dist.append(offset + st["dist"][i])
			if k > 0 and prev_vals != v:
				var w := smoothstep(0.0, SETTINGS_BLEND, st["dist"][i])
				values.append([lerpf(prev_vals[0], v[0], w), lerpf(prev_vals[1], v[1], w),
					lerpf(prev_vals[2], v[2], w), lerpf(prev_vals[3], v[3], w)])
			else:
				values.append(v)
		if k > 0:
			seams.append(pos.size() - st["pos"].size())
		offset += st["length"]
		prev_tan = st["tan"][st["tan"].size() - 1]
		prev_vals = v
	return {"pos": pos, "tan": tan, "dist": dist, "length": offset, "values": values, "seams": seams}


## The spine of a "corners" ramp with locked sections: the path is one rounded polyline over all the points (each
## corner's rounding depends only on its own two stretches, so locking can't move it, and the next section can't
## either); the sections only decide the face settings along it, blended in after each seam as for smooth ramps.
static func _corner_spine(points: PackedVector3Array, s: Dictionary, secs: Array, spacing: float) -> Dictionary:
	var st := stations(points, spacing, [], Vector3.ZERO, float(s["corner"]))
	var pos: PackedVector3Array = st["pos"]
	var values: Array = []
	var seams := PackedInt32Array()
	var prev_k := -1
	var seam_d := 0.0
	var prev_vals: Array = []
	for i in pos.size():
		var span := 0                                    # (the stretch of points this station is on)
		var bd := INF
		for j in points.size() - 1:
			var cp := Geometry3D.get_closest_point_to_segment(pos[i], points[j], points[j + 1])
			var d := cp.distance_to(pos[i])
			if d < bd - 1e-6:
				bd = d
				span = j
		var k := 0
		for kk in secs.size():
			if span >= int(secs[kk]["from"]) and span < int(secs[kk]["to"]):
				k = kk
		if prev_k >= 0 and k > prev_k:
			seams.append(i)
			seam_d = float(st["dist"][i])
			prev_vals = values[values.size() - 1]
		prev_k = maxi(prev_k, k)
		var v: Array = secs[prev_k]["values"]
		if not prev_vals.is_empty() and prev_vals != v:
			var w := smoothstep(0.0, SETTINGS_BLEND, float(st["dist"][i]) - seam_d)
			values.append([lerpf(prev_vals[0], v[0], w), lerpf(prev_vals[1], v[1], w),
				lerpf(prev_vals[2], v[2], w), lerpf(prev_vals[3], v[3], w)])
		else:
			values.append(v)
	return {"pos": pos, "tan": st["tan"], "dist": st["dist"], "length": st["length"], "values": values, "seams": seams}


## Points along the spine about `spacing` meters apart.
static func sample_path(points: PackedVector3Array, spacing: float, corner := -1.0) -> PackedVector3Array:
	return stations(points, spacing, [], Vector3.ZERO, corner)["pos"]


## Point on the smooth path nearest `target`, and the index of the control-point span it lies in.
static func nearest_on_path(points: PackedVector3Array, target: Vector3, corner := -1.0) -> Dictionary:
	var best := {"span": 0, "point": points[0], "distance": INF}
	if corner > 0.0:                                     # (the corners path: its dense points, the span by nearest point)
		for q in _corner_path(points, 0.5, corner)["pos"]:
			var dd := (q as Vector3).distance_to(target)
			if dd < best["distance"]:
				best = {"span": 0, "point": q, "distance": dd}
		var bp: Vector3 = best["point"]
		var span := 0
		var bd := INF
		for i in points.size() - 1:
			var cp := Geometry3D.get_closest_point_to_segment(bp, points[i], points[i + 1])
			if cp.distance_to(bp) < bd:
				bd = cp.distance_to(bp)
				span = i
		best["span"] = span
		return best
	for i in points.size() - 1:
		for s in 41:
			var q := _eval(points, i, s / 40.0)
			var dd := q.distance_to(target)
			if dd < best["distance"]:
				best = {"span": i, "point": q, "distance": dd}
	return best


## Centripetal Catmull-Rom (alpha 0.5): no loops or cusps even with uneven point spacing.
static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + pow(max(p0.distance_to(p1), 1e-4), 0.5)
	var t2 := t1 + pow(max(p1.distance_to(p2), 1e-4), 0.5)
	var t3 := t2 + pow(max(p2.distance_to(p3), 1e-4), 0.5)
	var u := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - u) / (t1 - t0) + p1 * (u - t0) / (t1 - t0)
	var a2 := p1 * (t2 - u) / (t2 - t1) + p2 * (u - t1) / (t2 - t1)
	var a3 := p2 * (t3 - u) / (t3 - t2) + p3 * (u - t2) / (t3 - t2)
	var b1 := a1 * (t2 - u) / (t2 - t0) + a2 * (u - t0) / (t2 - t0)
	var b2 := a2 * (t3 - u) / (t3 - t1) + a3 * (u - t1) / (t3 - t1)
	return b1 * (t2 - u) / (t2 - t1) + b2 * (u - t1) / (t2 - t1)


# ------------------------------------------------------------------------------------------------ profile
## Cross-section in the station frame: x along `right`, y along `up`, the spine (apex) at the origin. The polygon
## runs counter-clockwise. Returns {"pts": PackedVector2Array, "ride": [first, last] riding-surface vertices,
## "edges": indices of the face edge points (for fold checks), "lines": vertices the selection outline follows}.
static func profile(s: Dictionary) -> Dictionary:
	if custom_profile(s):
		return _custom_profile(s)
	var a := deg_to_rad(s["angle"])
	var b := deg_to_rad(s["angle_right"])
	var la: float = s["face_length"]
	var lb: float = s["face_length_right"]
	var le := Vector2(-la * cos(a), -la * sin(a))
	var re := Vector2(lb * cos(b), -lb * sin(b))
	var apex := Vector2.ZERO
	var bd: float = s["base_depth"]
	var t := HOLLOW_SKIN
	var pts := PackedVector2Array()
	match s["style"]:
		"half_left":
			if s["solid"]:
				var bottom := le.y - bd
				pts = PackedVector2Array([Vector2(0, bottom), apex, le])
				if bd > 0.01:
					pts.append(Vector2(le.x, bottom))
			else:
				pts = PackedVector2Array([Vector2(0, -t), apex, le, le + Vector2(0, -t)])
			return {"pts": pts, "ride": [1, 2], "edges": [2], "lines": range(pts.size())}
		"half_right":
			if s["solid"]:
				var bottom := re.y - bd
				pts = PackedVector2Array([re, apex, Vector2(0, bottom)])
				if bd > 0.01:
					pts.append(Vector2(re.x, bottom))
			else:
				pts = PackedVector2Array([re, apex, Vector2(0, -t), re + Vector2(0, -t)])
			return {"pts": pts, "ride": [0, 1], "edges": [0], "lines": range(pts.size())}
	if s["solid"]:
		pts = PackedVector2Array([re, apex, le])
		if bd > 0.01:
			var bottom := minf(le.y, re.y) - bd
			pts.append(Vector2(le.x, bottom))
			pts.append(Vector2(re.x, bottom))
		return {"pts": pts, "ride": [0, 2], "edges": [0, 2], "lines": range(pts.size())}
	# hollow V: a thin shell, the underside a little inside the faces
	pts = PackedVector2Array([re, apex, le, Vector2(le.x * 0.9, le.y - t), Vector2(0, -t * 2.0), Vector2(re.x * 0.9, re.y - t)])
	return {"pts": pts, "ride": [0, 2], "edges": [0, 2], "lines": [0, 1, 2]}


## The riding surface of a custom cross-section, from the right edge over the top to the left edge (only the faces
## the style has), as profile points.
static func surface(s: Dictionary) -> PackedVector2Array:
	var p: Dictionary = s["profile"] if s["profile"] is Dictionary and s["profile"].has("same") else profile_spec(s.get("profile", {}))
	var a := deg_to_rad(s["angle"])
	var b := deg_to_rad(s["angle_right"])
	var la: float = s["face_length"]
	var lb: float = s["face_length_right"]
	var half := float(p["top"]) * 0.5
	var r0 := Vector2(half, 0.0)
	var l0 := Vector2(-half, 0.0)
	var dr := Vector2(cos(b), -sin(b))
	var nr := Vector2(sin(b), cos(b))                     # out of the right face (up and to the right)
	var dl := Vector2(-cos(a), -sin(a))
	var nl := Vector2(-sin(a), cos(a))
	var out := PackedVector2Array()
	if s["style"] != "half_left":
		out.append(r0 + dr * lb)
		var rp: Array = p["right"]
		for i in range(rp.size() - 1, -1, -1):
			out.append(r0 + dr * lb * float(rp[i][0]) + nr * lb * float(rp[i][1]))
		out.append(r0)
	if s["style"] != "half_right":
		if half > 0.0 or s["style"] == "half_left":
			out.append(l0)
		for q in p["left"]:
			out.append(l0 + dl * la * float(q[0]) + nl * la * float(q[1]))
		out.append(l0 + dl * la)
	return out


static func _custom_profile(s: Dictionary) -> Dictionary:
	var surf := surface(s)
	var n := surf.size()
	var pts := PackedVector2Array(surf)
	var lowest := 0.0
	for q in surf:
		lowest = minf(lowest, q.y)
	var bd: float = s["base_depth"]
	var t := HOLLOW_SKIN
	var first := surf[0]
	var last := surf[n - 1]
	match s["style"]:
		"half_left":                                     # surf runs from the back wall's top to the left edge
			if s["solid"]:
				var bottom := lowest - maxf(bd, 0.0)
				if bd > 0.01 or lowest < last.y - 0.01:
					pts.append(Vector2(last.x, bottom))
				pts.append(Vector2(first.x, bottom))
			else:
				for i in range(n - 1, -1, -1):
					pts.append(surf[i] + Vector2(0, -t))
		"half_right":                                    # surf runs from the right edge to the back wall's top
			if s["solid"]:
				var bottom := lowest - maxf(bd, 0.0)
				pts.append(Vector2(last.x, bottom))
				if bd > 0.01 or lowest < first.y - 0.01:
					pts.append(Vector2(first.x, bottom))
			else:
				for i in range(n - 1, -1, -1):
					pts.append(surf[i] + Vector2(0, -t))
		_:
			if s["solid"]:
				if bd > 0.01 or lowest < minf(first.y, last.y) - 0.01:
					var bottom := lowest - maxf(bd, 0.0)
					pts.append(Vector2(last.x, bottom))
					pts.append(Vector2(first.x, bottom))
			else:
				for i in range(n - 1, -1, -1):
					pts.append(surf[i] + Vector2(0, -t))
	var edges := []
	if s["style"] != "half_left":
		edges.append(0)
	if s["style"] != "half_right":
		edges.append(n - 1)
	var lines := range(n) if not s["solid"] else range(pts.size())
	return {"pts": pts, "ride": [0, n - 1], "edges": edges, "lines": lines, "surface": n}


## How a shaped end scales the cross-section `d` meters from that end (1 = full size).
static func end_scale(e: Dictionary, d: float) -> float:
	var u := clampf(d / float(e["length"]), 0.0, 1.0)
	match e["shape"]:
		"taper": return lerpf(MIN_END_SCALE, 1.0, u)
		"round": return maxf(sqrt(1.0 - (1.0 - u) * (1.0 - u)), MIN_END_SCALE)
		"flare": return 1.0 + float(e["amount"]) * (1.0 - u) * (1.0 - u)
	return 1.0


## How much a lip lifts the ramp `d` meters from that end.
static func end_lift(e: Dictionary, d: float) -> float:
	if float(e["lip"]) == 0.0:
		return 0.0
	var u := clampf(1.0 - d / float(e["lip_length"]), 0.0, 1.0)
	return float(e["lip"]) * u * u


## The upright frame at every station: right (always level) and up. Ramps never roll. Returns [rights, ups].
const STEEP_FROM := 60.0                 ## degrees of climb or drop where a vertical slice starts turning with the spine
const STEEP_TO := 85.0                   ## ...and where it stands square to it


static func frames(st: Dictionary, s: Dictionary) -> Array:
	var tan: PackedVector3Array = st["tan"]
	var n := tan.size()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	rights.resize(n)
	ups.resize(n)
	# right = horizontal heading x world up. Where the spine is (nearly) vertical there is no heading: reuse the
	# neighbor's right, so nothing jumps and no NaN appears.
	var valid := -1
	for i in n:
		var ff := Vector3(tan[i].x, 0.0, tan[i].z)
		if ff.length() > 1e-4:
			rights[i] = ff.normalized().cross(Vector3.UP).normalized()
			if valid < 0:
				valid = i
		else:
			rights[i] = Vector3.ZERO
	var fallback := rights[valid] if valid >= 0 else Vector3.RIGHT
	for i in n:
		if rights[i] == Vector3.ZERO:
			rights[i] = fallback
		fallback = rights[i]
	var roll := deg_to_rad(float(s.get("roll", 0.0)))
	for i in n:
		var r := rights[i]
		var perp := r.cross(tan[i]).normalized()
		var up := Vector3.UP if s["slice"] != "perpendicular" else perp
		if s["slice"] != "perpendicular" and perp.length() > 1e-4:
			# a vertical slice can't hold a steep drop (straight down, it collapses to nothing): from 60 to 85 degrees
			# the cross-section turns to stand square to the spine, so the ramp keeps its shape around the spine.
			# Under 60 degrees nothing changes (surf ramps ride as they always have).
			var pitch := rad_to_deg(asin(clampf(absf(tan[i].y), 0.0, 1.0)))
			var w := smoothstep(STEEP_FROM, STEEP_TO, pitch)
			if w > 0.0:
				up = Vector3.UP.lerp(perp, w).normalized() # (right stays level: square to both, so the frame holds)
		if up.length() < 1e-4:
			up = Vector3.UP
		if roll != 0.0:                                  # (banked around the spine)
			var axis := tan[i].normalized()
			r = r.rotated(axis, roll)
			up = up.rotated(axis, roll)
		rights[i] = r
		ups[i] = up
	return [rights, ups]


## Everything about one ramp: stations, frames, cross-section rings, the mesh and any folds.
## Returns {"ridge", "tan", "rights", "ups", "rings", "profile", "mesh", "folds", "length", "triangles"}.
static func build(points: PackedVector3Array, s: Dictionary) -> Dictionary:
	var st := spine(points, s)
	var out := {"ridge": st["pos"], "tan": st["tan"], "rights": PackedVector3Array(), "ups": PackedVector3Array(),
		"rings": [], "profile": {}, "mesh": ArrayMesh.new(), "folds": PackedInt32Array(), "length": st["length"], "triangles": 0,
		"values": st["values"], "seams": st["seams"]}
	var ridge: PackedVector3Array = st["pos"]
	var n := ridge.size()
	if n < 2:
		return out
	var ends: Dictionary = s.get("ends", {}) if (s.get("ends", {}) as Dictionary).has("start") else spec(s)["ends"]
	var shaped := custom_ends(s)
	var scales := PackedFloat32Array()
	scales.resize(n)
	scales.fill(1.0)
	if shaped:                                           # shaped ends: the cross-section's size and a lip's lift
		ridge = ridge.duplicate()
		var total: float = st["length"]
		for i in n:
			var d: float = st["dist"][i]
			scales[i] = end_scale(ends["start"], d) * end_scale(ends["end"], total - d)
			ridge[i].y += end_lift(ends["start"], d) + end_lift(ends["end"], total - d)
		st["pos"] = ridge
		out["ridge"] = ridge
	var fr := frames(st, s)
	var rights: PackedVector3Array = fr[0]
	var ups: PackedVector3Array = fr[1]
	# the cross-section at every station (face settings can vary along a ramp with sections)
	var station_spec := s.duplicate()
	var prof := profile(s)
	var last_vals: Array = []
	var profiles: Array = []
	for i in n:
		var v: Array = st["values"][i]
		if v != last_vals:
			station_spec["angle"] = v[0]
			station_spec["face_length"] = v[1]
			station_spec["angle_right"] = v[2]
			station_spec["face_length_right"] = v[3]
			prof = profile(station_spec)
			last_vals = v
		if scales[i] != 1.0:
			var sc := PackedVector2Array()
			for q in prof["pts"]:
				sc.append(q * scales[i])
			profiles.append(sc)
		else:
			profiles.append(prof["pts"])
	var pp: PackedVector2Array = profiles[0]
	var pc := pp.size()
	var rings: Array[PackedVector3Array] = []
	for i in n:
		var ring := PackedVector3Array()
		for q in profiles[i]:
			ring.append(ridge[i] + rights[i] * q.x + ups[i] * q.y)
		rings.append(ring)
	# folds: a face edge that stops moving forward (or runs backwards) means a bend too tight for the face
	# width - the inner edge creases over itself
	var folds := PackedInt32Array()
	var tans: PackedVector3Array = st["tan"]
	for i in range(1, n):
		var ff := Vector3(tans[i].x, 0.0, tans[i].z) + Vector3(tans[i - 1].x, 0.0, tans[i - 1].z)
		if ff.length() < 1e-4:
			continue
		var spacing := Vector2(ridge[i].x - ridge[i - 1].x, ridge[i].z - ridge[i - 1].z).length()
		for k in prof["edges"]:
			var d: Vector3 = rings[i][k] - rings[i - 1][k]
			if Vector3(d.x, 0, d.z).dot(ff.normalized()) <= spacing * 0.05:
				folds.append(i)
				break
	var touched := {}                                    # stations a diagonal cut trimmed (not checked against the settings)
	if shaped:
		for which in ["start", "end"]:
			if float(ends[which]["cut"]) != 0.0:
				touched.merge(_cut_end(rings, ridge, tans, float(ends[which]["cut"]), which == "end"))
	# u across the profile: the riding surface spans exactly 0..1 so textures can frame it; the rest continues
	# in proportion to its size
	var perim := PackedFloat32Array([0.0])
	for k in pc:
		perim.append(perim[k] + pp[k].distance_to(pp[(k + 1) % pc]))
	var r0: int = prof["ride"][0]
	var r1: int = prof["ride"][1]
	var ride_len := maxf(perim[r1] - perim[r0], 0.01)
	var ucoord := PackedFloat32Array()
	for k in pc + 1:
		ucoord.append((perim[k] - perim[r0]) / ride_len)
	var dist: PackedFloat32Array = st["dist"]

	var stool := SurfaceTool.new()
	stool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	for f in pc:
		var a := f
		var b := (f + 1) % pc
		for i in n - 1:
			# Where two cross-sections differ in width (shaped ends, sections blending) the piece between them is a
			# trapezoid, and two triangles would bend every texture along their diagonal. Cut it into strips along
			# the true across-the-face lines instead, enough that the bend stays under STRIP_TOLERANCE.
			var wa: float = rings[i][a].distance_to(rings[i][b])
			var wb: float = rings[i + 1][a].distance_to(rings[i + 1][b])
			var strips := clampi(int(ceil(absf(wa - wb) / STRIP_TOLERANCE)), 1, MAX_STRIPS)
			for k in strips:
				var f0 := float(k) / strips
				var f1 := float(k + 1) / strips
				var p0: Vector3 = rings[i][a].lerp(rings[i][b], f0)
				var p1: Vector3 = rings[i][a].lerp(rings[i][b], f1)
				var q1: Vector3 = rings[i + 1][a].lerp(rings[i + 1][b], f1)
				var q0: Vector3 = rings[i + 1][a].lerp(rings[i + 1][b], f0)
				var u0 := lerpf(ucoord[f], ucoord[f + 1], f0)
				var u1 := lerpf(ucoord[f], ucoord[f + 1], f1)
				_quad(stool, p0, p1, q1, q0, Vector2(u0, _v_at(i, p0, dist, ridge, tans, touched)),
					Vector2(u1, _v_at(i, p1, dist, ridge, tans, touched)), Vector2(u1, _v_at(i + 1, q1, dist, ridge, tans, touched)),
					Vector2(u0, _v_at(i + 1, q0, dist, ridge, tans, touched)))
				tris += 2
	# end caps, wound the same way as the sides: a side quad's geometric normal tells us which winding faces out
	var e0 := pp[1] - pp[0]
	var out2 := Vector2(e0.y, -e0.x)                     # outward normal of a counter-clockwise polygon edge
	var side_out := rights[0] * out2.x + ups[0] * out2.y
	var gn := (rings[0][1] - rings[0][0]).cross(rings[1][1] - rings[0][0])
	var conv := signf(gn.dot(side_out))
	for end in [0, n - 1]:
		var cap_idx := Geometry2D.triangulate_polygon(profiles[end])
		var ring: PackedVector3Array = rings[end]
		var outward: Vector3 = -tans[0] if end == 0 else tans[n - 1]
		for c in range(0, cap_idx.size(), 3):
			var ia := cap_idx[c]
			var ib := cap_idx[c + 1]
			var ic := cap_idx[c + 2]
			if signf((ring[ib] - ring[ia]).cross(ring[ic] - ring[ia]).dot(outward)) != conv:
				var tmp := ib
				ib = ic
				ic = tmp
			stool.set_smooth_group(-1)
			for k in [ia, ib, ic]:
				stool.set_uv(profiles[end][k] / UV_METRES)
				stool.add_vertex(ring[k])
			tris += 1
	# closed ends: a hollow ramp's end shut from edge to edge (the space under the faces)
	var closures: Array = []
	if shaped and not s["solid"]:
		var surf_n: int = prof.get("surface", 3 if s["style"] == "v" else 2) if custom_profile(s) else (3 if s["style"] == "v" else 2)
		for which in ["start", "end"]:
			if not ends[which]["closed"] or surf_n < 2:
				continue
			var end := 0 if which == "start" else n - 1
			var poly2 := PackedVector2Array()
			var poly3 := PackedVector3Array()
			var ring: PackedVector3Array = rings[end]
			if custom_profile(s) or s["style"] == "v":
				for k in surf_n:
					poly2.append(profiles[end][k])
					poly3.append(ring[k])
			else:                                        # plain half ramp: its shell's surface is points 1..2 / 0..1
				var idx := [1, 2] if s["style"] == "half_left" else [0, 1]
				for k in idx:
					poly2.append(profiles[end][k])
					poly3.append(ring[k])
			if s["style"] != "v":                        # half ramps close down the back wall
				var back := poly2[0] if s["style"] == "half_left" else poly2[poly2.size() - 1]
				var low := minf(poly2[0].y, poly2[poly2.size() - 1].y)
				var wall2 := Vector2(back.x, low)
				var wall3: Vector3 = ridge[end] + rights[end] * wall2.x + ups[end] * wall2.y
				poly2.append(wall2)
				poly3.append(wall3)
			if poly2.size() < 3:
				continue
			var tri := Geometry2D.triangulate_polygon(poly2)
			for c in range(0, tri.size(), 3):
				stool.set_smooth_group(-1)
				for k in [tri[c], tri[c + 1], tri[c + 2]]:
					stool.set_uv(poly2[k] / UV_METRES)
					stool.add_vertex(poly3[k])
				tris += 1
			closures.append(poly3)
	stool.generate_normals()
	var mesh := ArrayMesh.new()
	stool.commit(mesh)
	out["rights"] = rights
	out["ups"] = ups
	out["rings"] = rings
	out["profile"] = prof
	out["mesh"] = mesh
	out["folds"] = folds
	out["triangles"] = tris
	out["scales"] = scales
	out["closures"] = closures
	out["touched"] = touched
	return out


## A diagonal cut at one end: a plane through the end of the spine, turned `cut` degrees from square in plan view.
## Every cross-section point past it is pulled back onto it along the ramp; the end cross-section is laid onto it.
static func _cut_end(rings: Array, ridge: PackedVector3Array, tans: PackedVector3Array, cut: float, at_end: bool) -> Dictionary:
	var touched := {}
	var n := ridge.size()
	var e := n - 1 if at_end else 0
	var th := Vector3(tans[e].x, 0.0, tans[e].z)
	if th.length() < 1e-4:
		return touched
	th = th.normalized() * (1.0 if at_end else -1.0)    # pointing out of the ramp at this end
	var nrm := th.rotated(Vector3.UP, deg_to_rad(cut))
	var along := th.dot(nrm)
	var p: Vector3 = ridge[e]
	for i in n:
		var ring: PackedVector3Array = rings[i]
		var changed := false
		for k in ring.size():
			var sd := (ring[k] - p).dot(nrm)
			if sd > 0.0 or i == e:
				ring[k] -= th * sd / along
				changed = true
		if changed:
			rings[i] = ring
			touched[i] = true
	return touched


## Texture v (meters along the ramp / UV_METRES) of a point of cross-section i. A diagonal cut moved its points along
## the ramp, so there each point's own distance along is used (else the texture smears across the cut).
static func _v_at(i: int, q: Vector3, dist: PackedFloat32Array, ridge: PackedVector3Array, tans: PackedVector3Array,
		touched: Dictionary) -> float:
	if not touched.has(i):
		return dist[i] / UV_METRES
	var th := Vector3(tans[i].x, 0.0, tans[i].z).normalized()
	return (dist[i] + (q - ridge[i]).dot(th)) / UV_METRES


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ue: Vector2) -> void:
	st.set_smooth_group(-1)                 # flat shading: crisp faces, like real surf ramps
	for pair in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [e, ue]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## Length of a sampled path in meters.
static func path_length(ridge: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, ridge.size()):
		l += ridge[i].distance_to(ridge[i - 1])
	return l


# ------------------------------------------------------------------------------------------------ self-check
## Geometry rules, checked after a build. Returns a list of problems (empty = all good): right is level, the
## profile is upright, each face's slant length and angle match the settings, the bar across the edges is level
## and (vertical slice) the apex is straight above its middle, no NaNs, no folds.
static func self_check(s: Dictionary, res: Dictionary, tol := 1e-3) -> PackedStringArray:
	var problems := PackedStringArray()
	var ridge: PackedVector3Array = res["ridge"]
	if ridge.size() < 2:
		return problems
	var prof: Dictionary = res["profile"]
	var pp: PackedVector2Array = prof["pts"]
	var symmetric: bool = s["style"] == "v" and not s["freeform"]
	for i in ridge.size():
		var r: Vector3 = res["rights"][i]
		var up: Vector3 = res["ups"][i]
		var ring: PackedVector3Array = res["rings"][i]
		for q in ring:
			if is_nan(q.x) or is_nan(q.y) or is_nan(q.z):
				problems.append("station %d: NaN" % i)
				return problems
		if absf(r.y) > tol:
			problems.append("station %d: right is not level (y = %.4f)" % [i, r.y])
		var steep: bool = s["slice"] == "vertical" and i < (res.get("tan", PackedVector3Array()) as PackedVector3Array).size() \
			and rad_to_deg(asin(clampf(absf((res["tan"][i] as Vector3).y), 0.0, 1.0))) > STEEP_FROM
		if s["slice"] == "vertical" and not steep and up.distance_to(Vector3.UP) > tol:
			problems.append("station %d: profile is not upright" % i)
		var v: Array = res["values"][i]
		if custom_profile(s) or float((res.get("scales", PackedFloat32Array()) as PackedFloat32Array)[i] if i < (res.get("scales", PackedFloat32Array()) as PackedFloat32Array).size() else 1.0) != 1.0:
			continue                                     # (a custom cross-section / shaped end: lengths differ on purpose)
		if (res.get("touched", {}) as Dictionary).has(i):
			continue                                     # (trimmed by a diagonal cut)
		for k in prof["edges"]:
			var e: Vector3 = ring[k] - ridge[i]
			var left: bool = pp[k].x < 0.0
			var want_l: float = v[1] if left else v[3]
			var want_a: float = v[0] if left else v[2]
			if absf(e.length() - want_l) > tol * 10.0:
				problems.append("station %d: face length %.3f, expected %.3f" % [i, e.length(), want_l])
			var got := rad_to_deg(atan2(-e.dot(up), absf(e.dot(r))))
			if absf(got - want_a) > 0.05:
				problems.append("station %d: face angle %.2f, expected %.2f" % [i, got, want_a])
		if symmetric and absf((ring[0] - ring[2]).dot(up)) > tol * 10.0:
			problems.append("station %d: the bar across the edges is not level" % i)
		if symmetric and s["slice"] == "vertical" and not steep:
			var mid: Vector3 = (ring[0] + ring[2]) * 0.5
			if Vector2(mid.x - ridge[i].x, mid.z - ridge[i].z).length() > tol * 10.0:
				problems.append("station %d: apex is not above the middle of the profile" % i)
		if problems.size() > 20:
			break
	if not res["folds"].is_empty():
		problems.append("%d station(s) where the inner edge folds over" % res["folds"].size())
	return problems
