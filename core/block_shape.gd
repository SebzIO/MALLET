class_name BlockShape
extends RefCounted
## Block geometry: the convex pieces of each block shape (in the block's own space: origin at the middle of its
## base, size x / y / z, facing -Z), hollowing, cuts, and the mesh. Shared by the editor and both exporters.

const SHAPES := ["box", "wedge", "cylinder", "stairs", "arch", "pyramid", "cone", "sphere"]
const LABELS := {"box": "Box", "wedge": "Wedge (slope)", "cylinder": "Cylinder", "stairs": "Stairs", "arch": "Arch (doorway)",
	"pyramid": "Pyramid", "cone": "Cone", "sphere": "Sphere"}
const UV_METRES := 4.0                   ## textures repeat every 4 m, lined up across blocks (world-aligned)

const DEFAULTS := {
	"shape": "box", "position": [0.0, 0.0, 0.0], "size": [16.0, 8.0, 16.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0,
	"sides": 16, "steps": 8, "hollow": false, "wall": 1.0, "cutter": false,
	"look": "grid", "color": "9aa3ad",
	"material": "",                      ## library material for the whole block ("" = use look + colour)
	"uv_scale": 1.0, "uv_offset": [0.0, 0.0], "uv_rot": 0.0,   ## texture size multiplier, shift (repeats), turn
	"faces": {},                         ## per side: {slot: {material, uv_scale, uv_offset, uv_rot}} overriding the above
}
## The sides of a block, in its own space (front = -Z, the way it faces).
const SLOTS := ["top", "bottom", "front", "back", "left", "right"]
const SLOT_LABELS := {"top": "Top", "bottom": "Bottom", "front": "Front", "back": "Back", "left": "Left", "right": "Right"}


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not s["shape"] in SHAPES:
		s["shape"] = "box"
	return s


## Turned by yaw, then tilted by pitch (forward / back) and roll (sideways), about the middle of its base.
static func transform_of(s: Dictionary) -> Transform3D:
	var p: Array = s["position"]
	return Transform3D(basis_of(s), Vector3(p[0], p[1], p[2]))


static func basis_of(s: Dictionary) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(float(s.get("pitch", 0.0))), deg_to_rad(float(s["yaw"])),
		deg_to_rad(float(s.get("roll", 0.0)))), EULER_ORDER_YXZ)


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
			var ring: Array = []
			var n: int = clampi(int(s["sides"]), 3, 64)
			for i in n:
				var a := TAU * i / n
				ring.append(Vector3(cos(a) * hx, 0, sin(a) * hz))
			out.append(Convex.extrude(ring, Vector3(0, sz.y, 0)))
		"stairs":
			# steps climbing towards -Z, each a solid box down to the ground
			var n: int = clampi(int(s["steps"]), 2, 64)
			for i in n:
				var z0 := hz - sz.z * (i + 1) / n
				var z1 := hz - sz.z * i / n
				out.append(_box(Vector3(-hx, 0, z0), Vector3(hx, sz.y * (i + 1) / n, z1)))
		"arch":
			# a wall with a round-topped doorway through it (front to back); `wall` is the frame's thickness
			var t: float = clampf(float(s["wall"]), 0.2, hx * 0.9)
			var r := maxf(hx - t, 0.2)
			var spring := maxf(sz.y - t - r, 0.0)                # where the round top starts
			var n: int = clampi(int(s["sides"]), 6, 64)
			var arc: Array = []
			for i in n + 1:
				var a := PI * i / n
				arc.append(Vector3(cos(a) * r, spring + sin(a) * r, -hz - 1.0))
			var opening := Convex.extrude(arc, Vector3(0, 0, sz.z + 2.0))
			var lower := _box(Vector3(-r, -1.0, -hz - 1.0), Vector3(r, spring + 0.001, hz + 1.0))
			out = Convex.carve_all([_box(Vector3(-hx, 0, -hz), Vector3(hx, sz.y, hz))], [lower, opening])
		"pyramid":
			out.append(Convex.from_points([Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz),
				Vector3(0, sz.y, 0)]))
		"cone":
			var apex := Vector3(0, sz.y, 0)
			var cn: int = clampi(int(s["sides"]), 3, 64)
			var base: Array = []
			for i in cn:
				var a := TAU * i / cn
				base.append(Vector3(cos(a) * hx, 0, sin(a) * hz))
			var cf: Array = [[base[0], base[1], base[2]]]
			for i in cn:
				cf.append([base[i], base[(i + 1) % cn], apex])
			out.append(Convex.from_faces(cf, Vector3(0, sz.y * 0.25, 0)))
		"sphere":
			# faces between rings of latitude are flat (even squashed into an ellipsoid)
			var sn: int = clampi(int(s["sides"]), 6, 32)
			var rings := maxi(sn / 2, 3)
			var at := func(j: int, i: int) -> Vector3:
				var phi := PI * j / rings
				var a := TAU * i / sn
				return Vector3(cos(a) * sin(phi) * hx, sz.y * 0.5 - cos(phi) * sz.y * 0.5, sin(a) * sin(phi) * hz)
			var sf: Array = []
			for j in rings:
				for i in sn:
					if j == 0:
						sf.append([at.call(0, 0), at.call(1, i), at.call(1, i + 1)])
					elif j == rings - 1:
						sf.append([at.call(j, i), at.call(j, i + 1), at.call(rings, 0)])
					else:
						sf.append([at.call(j, i), at.call(j, i + 1), at.call(j + 1, i)])
			out.append(Convex.from_faces(sf, Vector3(0, sz.y * 0.5, 0)))
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


## Which side of the block a face belongs to, from its normal in the block's own space.
static func slot_of(local_normal: Vector3) -> String:
	if local_normal.y > 0.7:
		return "top"
	if local_normal.y < -0.7:
		return "bottom"
	if absf(local_normal.x) > absf(local_normal.z):
		return "right" if local_normal.x > 0.0 else "left"
	return "back" if local_normal.z > 0.0 else "front"


## The material and texture placement for one side: the block's settings, overridden by that side's own.
static func face_settings(s: Dictionary, slot: String) -> Dictionary:
	var out := {"material": s.get("material", ""), "uv_scale": float(s.get("uv_scale", 1.0)),
		"uv_offset": s.get("uv_offset", [0.0, 0.0]), "uv_rot": float(s.get("uv_rot", 0.0))}
	var own: Dictionary = s.get("faces", {}).get(slot, {})
	for k in own:
		out[k] = own[k]
	return out


## Texture coordinates for a point on a face: world-aligned (so textures line up across blocks), sized to the
## material's real-world size x the face's scale, then turned and shifted.
static func face_uv(p: Vector3, n: Vector3, f: Dictionary) -> Vector2:
	var metres := _uv(p, n) * UV_METRES
	if f["material"] == "":
		return metres / UV_METRES
	var size := MaterialLibrary.world_size(f["material"]) * maxf(float(f["uv_scale"]), 0.01)
	var uv := (metres / size).rotated(deg_to_rad(float(f["uv_rot"])))
	return uv + Vector2(f["uv_offset"][0], f["uv_offset"][1])


## The block's mesh with a surface per material (library materials per side, or the look + colour), in the
## block's own space. Returns [ArrayMesh, Array of the surfaces' materials].
static func mesh_faces(pieces: Array, xf: Transform3D, s: Dictionary) -> Array:
	var inv := xf.affine_inverse()
	var groups := {}                                     # material key -> [SurfaceTool, Material]
	for piece in pieces:
		for f in Convex.faces(piece):
			var n: Vector3 = (f[0] as Plane).normal
			var local_n: Vector3 = (inv.basis * n).normalized()
			var fs := face_settings(s, slot_of(local_n))
			var key: String = fs["material"] if fs["material"] != "" and MaterialLibrary.has(fs["material"]) else "look"
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var mat: Material = Look.ramp_material(s["look"], Color.html(s["color"])) if key == "look" \
					else MaterialLibrary.material(key, Color.html(s["color"]))
				groups[key] = [st, mat]
			var st2: SurfaceTool = groups[key][0]
			if key == "look":
				fs["material"] = ""
			var poly: Array = f[1]
			for i in range(1, poly.size() - 1):
				for v in [poly[0], poly[i + 1], poly[i]]:       # Godot winds front faces clockwise
					st2.set_normal(local_n)
					st2.set_uv(face_uv(v, n, fs))
					st2.add_vertex(inv * (v as Vector3))
	var m := ArrayMesh.new()
	var mats := []
	for key in groups:
		var st3: SurfaceTool = groups[key][0]
		st3.generate_tangents()
		st3.commit(m)
		mats.append(groups[key][1])
	for i in mats.size():
		m.surface_set_material(i, mats[i])
	return [m, mats]


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z) / UV_METRES
	if a.x >= a.z:
		return Vector2(p.z, -p.y) / UV_METRES
	return Vector2(p.x, -p.y) / UV_METRES
