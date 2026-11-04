class_name RampShape
extends RefCounted
## Builds surf-ramp geometry from a handful of control points.
##
## A ramp is a smooth path (centripetal Catmull-Rom through the control points) swept with a V-shaped
## cross-section: the ridge follows the path and two riding faces fall away to either side.
## Everything here is plain data in, mesh out - no scene knowledge - so exporters (SurfsUp, CS:S, glTF)
## can share it.

const UV_METRES := 20.0          # texture repeats every 20 m along the ramp


## Points along the path, roughly `spacing` metres apart (always at least 2 per span).
static func sample_path(points: PackedVector3Array, spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n < 2:
		return out
	for i in n - 1:
		var p0 := points[max(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[min(i + 2, n - 1)]
		if i == 0:
			p0 = p1 - (p2 - p1)                   # mirror the first span so the ends stay straight-ish
		if i + 2 >= n:
			p3 = p2 + (p2 - p1)
		var steps: int = max(2, int(ceil(p1.distance_to(p2) / max(spacing, 0.05))))
		for s in steps:
			out.append(_catmull_rom(p0, p1, p2, p3, float(s) / steps))
	out.append(points[n - 1])
	return out


## Point on the smooth path nearest `target`, and the index of the control-point span it lies in.
static func nearest_on_path(points: PackedVector3Array, target: Vector3) -> Dictionary:
	var best := {"span": 0, "point": points[0], "distance": INF}
	var n := points.size()
	for i in n - 1:
		var p0 := points[i - 1] if i > 0 else points[0] - (points[1] - points[0])
		var p3 := points[i + 2] if i + 2 < n else points[n - 1] + (points[n - 1] - points[n - 2])
		for s in 41:
			var q := _catmull_rom(p0, points[i], points[i + 1], p3, s / 40.0)
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


## Cross-section as (lateral, vertical) pairs measured from the ramp's base line under the ridge.
## Order: left edge, ridge, right edge, then the thin underside back to the left edge.
static func profile(width: float, height: float) -> PackedVector2Array:
	var w := width * 0.5
	return PackedVector2Array([Vector2(-w, 0), Vector2(0, height), Vector2(w, 0),
		Vector2(w * 0.9, -height * 0.0625), Vector2(0, height * 0.84), Vector2(-w * 0.9, -height * 0.0625)])


## Full ramp mesh. `ridge` is the sampled path of the ridge line.
## `roll` (degrees) tilts the cross-section around the path; positive tips the right face down.
static func build_mesh(ridge: PackedVector3Array, width: float, height: float, roll_deg := 0.0) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var n := ridge.size()
	if n < 2:
		return mesh
	var prof := profile(width, height)
	var pc := prof.size()
	# frame at every sample
	var rings: Array[PackedVector3Array] = []
	var dist := PackedFloat32Array()
	var d := 0.0
	for i in n:
		var t: Vector3 = (ridge[min(i + 1, n - 1)] - ridge[max(i - 1, 0)]).normalized()
		var side := Vector3.UP.cross(t)
		if side.length() < 1e-3:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := t.cross(side).normalized()
		if roll_deg != 0.0:
			var r := Basis(t, deg_to_rad(roll_deg))
			side = r * side
			up = r * up
		var base := ridge[i] - up * height
		var ring := PackedVector3Array()
		for p in prof:
			ring.append(base + side * p.x + up * p.y)
		rings.append(ring)
		if i > 0:
			d += ridge[i].distance_to(ridge[i - 1])
		dist.append(d)
	# u along the cross-section: riding surface spans exactly 0..1 so textures can frame the edges
	var ucoord := PackedFloat32Array([0.0, 0.5, 1.0, 1.05, 1.5, 1.95, 2.0])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in pc:
		var a := f
		var b := (f + 1) % pc
		for i in n - 1:
			var q0 := rings[i][a]
			var q1 := rings[i][b]
			var q2 := rings[i + 1][b]
			var q3 := rings[i + 1][a]
			var v0 := dist[i] / UV_METRES
			var v1 := dist[i + 1] / UV_METRES
			_quad(st, q0, q1, q2, q3,
				Vector2(ucoord[f], v0), Vector2(ucoord[f + 1], v0), Vector2(ucoord[f + 1], v1), Vector2(ucoord[f], v1))
	# end caps (two quads each: left half and right half of the hollow V)
	for end in [0, n - 1]:
		var r: PackedVector3Array = rings[end]
		for quad in [[0, 1, 4, 5], [1, 2, 3, 4]]:
			var pts := [r[quad[0]], r[quad[1]], r[quad[2]], r[quad[3]]]
			var uv := []
			for k in quad:
				uv.append(Vector2(prof[k].x / UV_METRES, prof[k].y / UV_METRES))
			if end == 0:
				_quad(st, pts[0], pts[3], pts[2], pts[1], uv[0], uv[3], uv[2], uv[1])
			else:
				_quad(st, pts[0], pts[1], pts[2], pts[3], uv[0], uv[1], uv[2], uv[3])
	st.generate_normals()
	st.commit(mesh)
	return mesh


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
