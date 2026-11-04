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
	"face_length": 10.5,           ## slant length of each face, ridge to edge (left face in Freeform), metres
	"angle_right": 56.0,           ## Freeform only
	"face_length_right": 10.5,     ## Freeform only
	"slice": "vertical",           ## "vertical" or "perpendicular" (how the profile is held on climbs and drops)
	"detail": 1.0,                 ## stations per metre along the spine (smoothness / polygon count)
	"freeform": false,             ## unlocks different left/right faces and twist
	"twist": 0.0,                  ## Freeform only: the profile rolls from 0 at the start to this at the end (degrees)
}


## A complete, consistent set of ramp settings from a (possibly partial) dictionary. Outside Freeform the right
## face mirrors the left and there is no twist. A dictionary with only width/height is converted.
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
	for k in ["base_depth", "angle", "face_length", "angle_right", "face_length_right", "detail", "twist"]:
		s[k] = float(s[k])
	s["solid"] = bool(s["solid"])
	s["freeform"] = bool(s["freeform"])
	if not s["style"] in STYLES:
		s["style"] = "v"
	if not s["freeform"]:
		s["angle_right"] = s["angle"]
		s["face_length_right"] = s["face_length"]
		s["twist"] = 0.0
	return s


## How far the lowest point of the cross-section sits below the spine (for kill floors and framing).
static func depth_below_spine(s: Dictionary) -> float:
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
static func _span(points: PackedVector3Array, i: int) -> Array:
	var n := points.size()
	var p1 := points[i]
	var p2 := points[i + 1]
	var p0 := points[i - 1] if i > 0 else p1 - (p2 - p1)          # mirror the ends so they stay straight-ish
	var p3 := points[i + 2] if i + 2 < n else p2 + (p2 - p1)
	return [p0, p1, p2, p3]


static func _eval(points: PackedVector3Array, i: int, t: float) -> Vector3:
	var c := _span(points, i)
	return _catmull_rom(c[0], c[1], c[2], c[3], t)


## Stations evenly spaced by arc length (about `spacing` metres apart, the ends exactly on the first and last
## point), each with the spine's own tangent there (the curve's derivative, not differences between vertices).
## Returns {"pos": PackedVector3Array, "tan": PackedVector3Array, "dist": PackedFloat32Array, "length": float}.
static func stations(points: PackedVector3Array, spacing: float) -> Dictionary:
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
			var q := _eval(points, i, t)
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
		var p := points[n - 1] if k == count else (points[0] if k == 0 else _eval(points, i, tt))
		var h := 1e-3
		var d := _eval(points, i, minf(tt + h, 1.0)) - _eval(points, i, maxf(tt - h, 0.0))
		if d.length() > 1e-7:
			last_tan = d.normalized()
		pos.append(p)
		tan.append(last_tan)
		dist.append(s)
	return {"pos": pos, "tan": tan, "dist": dist, "length": total}


## Points along the spine about `spacing` metres apart.
static func sample_path(points: PackedVector3Array, spacing: float) -> PackedVector3Array:
	return stations(points, spacing)["pos"]


## Point on the smooth path nearest `target`, and the index of the control-point span it lies in.
static func nearest_on_path(points: PackedVector3Array, target: Vector3) -> Dictionary:
	var best := {"span": 0, "point": points[0], "distance": INF}
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


## The upright frame at every station: right (always level) and up. Twist (Freeform) rolls both around the
## tangent. Returns [rights, ups].
static func frames(st: Dictionary, s: Dictionary) -> Array:
	var tan: PackedVector3Array = st["tan"]
	var n := tan.size()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	rights.resize(n)
	ups.resize(n)
	# right = horizontal heading x world up. Where the spine is (nearly) vertical there is no heading: reuse the
	# neighbour's right, so nothing jumps and no NaN appears.
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
	var total: float = st["length"]
	for i in n:
		var r := rights[i]
		var up := Vector3.UP if s["slice"] != "perpendicular" else r.cross(tan[i]).normalized()
		if up.length() < 1e-4:
			up = Vector3.UP
		var tw: float = s["twist"]
		if tw != 0.0 and total > 0.0:
			var roll := Basis(tan[i], deg_to_rad(tw * st["dist"][i] / total))
			r = roll * r
			up = roll * up
		rights[i] = r
		ups[i] = up
	return [rights, ups]


## Everything about one ramp: stations, frames, cross-section rings, the mesh and any folds.
## Returns {"ridge", "tan", "rights", "ups", "rings", "profile", "mesh", "folds", "length", "triangles"}.
static func build(points: PackedVector3Array, s: Dictionary) -> Dictionary:
	var st := stations(points, 1.0 / maxf(s["detail"], 0.05))
	var out := {"ridge": st["pos"], "tan": st["tan"], "rights": PackedVector3Array(), "ups": PackedVector3Array(),
		"rings": [], "profile": {}, "mesh": ArrayMesh.new(), "folds": PackedInt32Array(), "length": st["length"], "triangles": 0}
	var ridge: PackedVector3Array = st["pos"]
	var n := ridge.size()
	if n < 2:
		return out
	var fr := frames(st, s)
	var rights: PackedVector3Array = fr[0]
	var ups: PackedVector3Array = fr[1]
	var prof := profile(s)
	var pp: PackedVector2Array = prof["pts"]
	var pc := pp.size()
	var rings: Array[PackedVector3Array] = []
	for i in n:
		var ring := PackedVector3Array()
		for q in pp:
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
			var v0 := dist[i] / UV_METRES
			var v1 := dist[i + 1] / UV_METRES
			_quad(stool, rings[i][a], rings[i][b], rings[i + 1][b], rings[i + 1][a],
				Vector2(ucoord[f], v0), Vector2(ucoord[f + 1], v0), Vector2(ucoord[f + 1], v1), Vector2(ucoord[f], v1))
			tris += 2
	# end caps, wound the same way as the sides: a side quad's geometric normal tells us which winding faces out
	var e0 := pp[1] - pp[0]
	var out2 := Vector2(e0.y, -e0.x)                     # outward normal of a counter-clockwise polygon edge
	var side_out := rights[0] * out2.x + ups[0] * out2.y
	var gn := (rings[0][1] - rings[0][0]).cross(rings[1][1] - rings[0][0])
	var conv := signf(gn.dot(side_out))
	var cap_idx := Geometry2D.triangulate_polygon(pp)
	for end in [0, n - 1]:
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
				stool.set_uv(pp[k] / UV_METRES)
				stool.add_vertex(ring[k])
			tris += 1
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
	return out


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, e: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ue: Vector2) -> void:
	st.set_smooth_group(-1)                 # flat shading: crisp faces, like real surf ramps
	for pair in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [e, ue]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## Length of a sampled path in metres.
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
	var twisted: bool = s["twist"] != 0.0
	var symmetric: bool = s["style"] == "v" and not twisted and not s["freeform"]
	for i in ridge.size():
		var r: Vector3 = res["rights"][i]
		var up: Vector3 = res["ups"][i]
		var ring: PackedVector3Array = res["rings"][i]
		for q in ring:
			if is_nan(q.x) or is_nan(q.y) or is_nan(q.z):
				problems.append("station %d: NaN" % i)
				return problems
		if not twisted and absf(r.y) > tol:
			problems.append("station %d: right is not level (y = %.4f)" % [i, r.y])
		if not twisted and s["slice"] == "vertical" and up.distance_to(Vector3.UP) > tol:
			problems.append("station %d: profile is not upright" % i)
		for k in prof["edges"]:
			var e: Vector3 = ring[k] - ridge[i]
			var left: bool = pp[k].x < 0.0
			var want_l: float = s["face_length"] if left else s["face_length_right"]
			var want_a: float = s["angle"] if left else s["angle_right"]
			if absf(e.length() - want_l) > tol * 10.0:
				problems.append("station %d: face length %.3f, expected %.3f" % [i, e.length(), want_l])
			var got := rad_to_deg(atan2(-e.dot(up), absf(e.dot(r))))
			if absf(got - want_a) > 0.05:
				problems.append("station %d: face angle %.2f, expected %.2f" % [i, got, want_a])
		if symmetric and absf((ring[0] - ring[2]).dot(up)) > tol * 10.0:
			problems.append("station %d: the bar across the edges is not level" % i)
		if symmetric and s["slice"] == "vertical":
			var mid: Vector3 = (ring[0] + ring[2]) * 0.5
			if Vector2(mid.x - ridge[i].x, mid.z - ridge[i].z).length() > tol * 10.0:
				problems.append("station %d: apex is not above the middle of the profile" % i)
		if problems.size() > 20:
			break
	if not res["folds"].is_empty():
		problems.append("%d station(s) where the inner edge folds over" % res["folds"].size())
	return problems
