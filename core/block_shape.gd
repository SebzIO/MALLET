class_name BlockShape
extends RefCounted
## Block geometry: the convex pieces of each block shape (in the block's own space: origin at the middle of its
## base, size x / y / z, facing -Z), hollowing, cuts, and the mesh. Shared by the editor and both exporters.

const SHAPES := ["box", "wedge", "cylinder", "stairs"]
const LABELS := {"box": "Box", "wedge": "Wedge (slope)", "cylinder": "Cylinder", "stairs": "Stairs"}
const UV_METRES := 4.0                   ## textures repeat every 4 m, lined up across blocks (world-aligned)

const DEFAULTS := {
	"shape": "box", "position": [0.0, 0.0, 0.0], "size": [16.0, 8.0, 16.0], "yaw": 0.0,
	"sides": 16, "steps": 8, "hollow": false, "wall": 1.0, "cutter": false,
	"look": "grid", "color": "9aa3ad",
}


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not s["shape"] in SHAPES:
		s["shape"] = "box"
	return s


static func transform_of(s: Dictionary) -> Transform3D:
	var p: Array = s["position"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), Vector3(p[0], p[1], p[2]))


## The block's convex pieces in its own space, before cuts.
static func local_pieces(s: Dictionary) -> Array:
	var sz := Vector3(s["size"][0], s["size"][1], s["size"][2])
	var hx := sz.x * 0.5
	var hz := sz.z * 0.5
	var out: Array = []
	match s["shape"]:
		"box":
			out.append(_box(Vector3(-hx, 0, -hz), Vector3(hx, sz.y, hz)))
		"wedge":
			# full height at the back (+Z), sloping down to nothing at the front (-Z)
			out.append(Convex.from_points([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz),
				Vector3(-hx, sz.y, hz), Vector3(hx, sz.y, hz)]))
		"cylinder":
			var pts: Array = []
			var n: int = clampi(int(s["sides"]), 3, 64)
			for i in n:
				var a := TAU * i / n
				pts.append(Vector3(cos(a) * hx, 0, sin(a) * hz))
				pts.append(Vector3(cos(a) * hx, sz.y, sin(a) * hz))
			out.append(Convex.from_points(pts))
		"stairs":
			# steps climbing towards -Z, each a solid box down to the ground
			var n: int = clampi(int(s["steps"]), 2, 64)
			for i in n:
				var z0 := hz - sz.z * (i + 1) / n
				var z1 := hz - sz.z * i / n
				out.append(_box(Vector3(-hx, 0, z0), Vector3(hx, sz.y * (i + 1) / n, z1)))
	if s["hollow"] and s["shape"] in ["box", "cylinder"]:
		var t: float = clampf(float(s["wall"]), 0.1, minf(sz.x, minf(sz.y, sz.z)) * 0.45)
		var hollowed: Array = []
		for p in out:
			hollowed.append_array(Convex.carve(p, Convex.shrunk(p, t)))
		out = hollowed
	return out


static func _box(a: Vector3, b: Vector3) -> Array:
	return [Plane(Vector3.RIGHT, b.x), Plane(Vector3.LEFT, -a.x), Plane(Vector3.UP, b.y), Plane(Vector3.DOWN, -a.y),
		Plane(Vector3.BACK, b.z), Plane(Vector3.FORWARD, -a.z)]


## The block's pieces in world space, with every overlapping cutter's shape carved out.
static func world_pieces(s: Dictionary, cutters: Array = []) -> Array:
	var xf := transform_of(s)
	var pieces: Array = []
	for p in local_pieces(s):
		pieces.append(Convex.transformed(p, xf))
	if s["cutter"] or cutters.is_empty():
		return pieces
	var cuts: Array = []
	for c in cutters:
		var cs := spec(c)
		var cxf := transform_of(cs)
		for p in local_pieces(cs):
			cuts.append(Convex.transformed(p, cxf))
	return Convex.carve_all(pieces, cuts)


## A mesh from world-space pieces, in the block's own space (`xf` = the block's transform). UVs are world-aligned
## (projected along each face's main axis), so textures line up across neighbouring blocks like in Hammer.
static func mesh(pieces: Array, xf: Transform3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inv := xf.affine_inverse()
	var tris := 0
	for piece in pieces:
		for f in Convex.faces(piece):
			var n: Vector3 = (f[0] as Plane).normal
			var poly: Array = f[1]
			for i in range(1, poly.size() - 1):
				for v in [poly[0], poly[i + 1], poly[i]]:       # Godot winds front faces clockwise
					st.set_normal(inv.basis * n)
					st.set_uv(_uv(v, n))
					st.add_vertex(inv * (v as Vector3))
				tris += 1
	var m := ArrayMesh.new()
	if tris > 0:
		st.commit(m)
	return m


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z) / UV_METRES
	if a.x >= a.z:
		return Vector2(p.z, -p.y) / UV_METRES
	return Vector2(p.x, -p.y) / UV_METRES
