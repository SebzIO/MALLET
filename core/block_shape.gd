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
	"material": "",                      ## library material for the whole block ("" = use look + color)
	"uv_scale": 1.0, "uv_offset": [0.0, 0.0], "uv_rot": 0.0,   ## texture size multiplier, shift (repeats), turn
	"faces": {},                         ## per side: {slot: {material, uv_scale, uv_offset, uv_rot}} overriding the above
	"glow": 0.0,                         ## makes the block's surfaces shine (neon, lamps, lava)
	"water": false,                      ## a water volume: a moving see-through surface, players pass through
	"deadly": false,                     ## water only: touching it sends players back (lava, acid)
	"water_color": "1f6b8c", "clarity": 0.55,
	"liquid": "water",                   ## water only: a Look.LIQUIDS preset (water, pool, tropical, lake, swamp, river, acid, lava...)
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
## (projected along each face's main axis), so textures line up across neighboring blocks like in Hammer.
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


## The block's mesh with a surface per material (library materials per side, or the look + color), in the
## block's own space. Returns [ArrayMesh, Array of the surfaces' materials].
static func mesh_faces(pieces: Array, xf: Transform3D, s: Dictionary) -> Array:
	var inv := xf.affine_inverse()
	if s.get("water", false):
		return _water_mesh(pieces, inv, s)
	# plain arrays rather than vertex by vertex: a block with several cutters through it can have thousands of faces
	var groups := {}                                     # material key -> [verts, normals, tangents, uvs, Material]
	var settings := {}                                   # side -> its settings (the same for every face on it)
	for piece in pieces:
		for f in Convex.faces(piece):
			var n: Vector3 = (f[0] as Plane).normal
			var local_n: Vector3 = (inv.basis * n).normalized()
			var slot := slot_of(local_n)
			if not settings.has(slot):
				var fs0 := face_settings(s, slot)
				var key0: String = fs0["material"] if fs0["material"] != "" and MaterialLibrary.has(fs0["material"]) else "look"
				if key0 == "look":
					fs0["material"] = ""
				settings[slot] = [fs0, key0]
			var fs: Dictionary = settings[slot][0]
			var key: String = settings[slot][1]
			if not groups.has(key):
				var mat: Material = Look.ramp_material(s["look"], Color.html(s["color"]), "", 20.0, "", 10.5, true) if key == "look" 					else MaterialLibrary.material(key, Color.html(s["color"]))
				if float(s.get("glow", 0.0)) > 0.0 and mat is StandardMaterial3D:
					mat = _glowing(mat, float(s["glow"]))
				groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(), mat]
			var g: Array = groups[key]
			var verts: PackedVector3Array = g[0]
			var normals: PackedVector3Array = g[1]
			var tangents: PackedFloat32Array = g[2]
			var uvs: PackedVector2Array = g[3]
			g[0] = null                                  # drop the group's references so appends don't copy
			g[1] = null
			g[2] = null
			g[3] = null
			var poly: Array = f[1]
			var tangent := _face_tangent(poly, n, fs, inv, local_n)
			var luv: Array = []
			var lpos: Array = []
			for v in poly:
				luv.append(face_uv(v, n, fs))
				lpos.append(inv * (v as Vector3))
			for i in range(1, poly.size() - 1):
				for j in [0, i + 1, i]:                          # Godot winds front faces clockwise
					verts.append(lpos[j])
					normals.append(local_n)
					tangents.append_array([tangent.normal.x, tangent.normal.y, tangent.normal.z, tangent.d])
					uvs.append(luv[j])
			g[0] = verts
			g[1] = normals
			g[2] = tangents
			g[3] = uvs
	var m := ArrayMesh.new()
	var mats := []
	for key in groups:
		var g: Array = groups[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_TANGENT] = g[2]
		arrays[Mesh.ARRAY_TEX_UV] = g[3]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mats.append(g[4])
	for i in mats.size():
		m.surface_set_material(i, mats[i])
	return [m, mats]


## A flat face's tangent (the direction its texture's u runs, in block space), worked out from its UVs. Every face
## is flat, so this is exact - and SurfaceTool.generate_tangents takes a minute on a carved block (many cutters).
static func _face_tangent(poly: Array, n: Vector3, fs: Dictionary, inv: Transform3D, local_n: Vector3) -> Plane:
	var p0: Vector3 = poly[0]
	var p1: Vector3 = poly[1]
	var p2: Vector3 = poly[poly.size() - 1]
	var uv0 := face_uv(p0, n, fs)
	var e1 := p1 - p0
	var e2 := p2 - p0
	var d1 := face_uv(p1, n, fs) - uv0
	var d2 := face_uv(p2, n, fs) - uv0
	var det := d1.x * d2.y - d2.x * d1.y
	if absf(det) < 1e-9:
		var any := local_n.cross(Vector3.UP if absf(local_n.y) < 0.9 else Vector3.RIGHT).normalized()
		return Plane(any, 1.0)
	var t := (e1 * d2.y - e2 * d1.y) / det
	var b := (e2 * d1.x - e1 * d2.x) / det
	t = inv.basis * t
	b = inv.basis * b
	t = (t - local_n * local_n.dot(t)).normalized()
	var w := -1.0 if local_n.cross(t).dot(b) < 0.0 else 1.0
	return Plane(t, w)


static func _glowing(mat: StandardMaterial3D, glow: float) -> StandardMaterial3D:
	var g: StandardMaterial3D = mat.duplicate()
	g.emission_enabled = true
	g.emission = mat.albedo_color
	g.emission_energy_multiplier = glow
	if mat.albedo_texture:
		g.emission_texture = mat.albedo_texture       # the texture itself shines (a lit sign, a lamp)
		g.emission = Color.WHITE * mat.albedo_color
	return g


## Water: just the upward faces, with the moving water surface.
static func _water_mesh(pieces: Array, inv: Transform3D, s: Dictionary) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for piece in pieces:
		for f in Convex.faces(piece):
			var n: Vector3 = (f[0] as Plane).normal
			if n.y < 0.7:
				continue
			var poly: Array = f[1]
			for i in range(1, poly.size() - 1):
				for v in [poly[0], poly[i + 1], poly[i]]:
					st.set_normal(inv.basis * n)
					st.set_uv(Vector2((v as Vector3).x, (v as Vector3).z))
					st.add_vertex(inv * (v as Vector3))
			any = true
	var m := ArrayMesh.new()
	var mat := water_material(s)
	if any:
		st.commit(m)
		m.surface_set_material(0, mat)
	return [m, [mat]]


static func water_material(s: Dictionary) -> ShaderMaterial:
	var id: String = s.get("liquid", "water")
	var p: Dictionary = Look.LIQUIDS.get(id, Look.LIQUIDS["water"])
	var own: String = String(s.get("water_color", p["color"])).to_lower()
	# the block's own color only when someone changed it: not the preset's, and not the plain default for another preset
	var plain := own == String(p["color"]).to_lower() or (own == String(DEFAULTS["water_color"]).to_lower() and id != "water")
	var mat := Look.liquid_material(id, null if plain else Color.html(own),
		float(s.get("clarity", p.get("clarity", 0.55))))
	if float(s.get("glow", 0.0)) > 0.0 and p["style"] == "water":
		mat.set_shader_parameter("glow", float(s["glow"]))
	return mat


static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector2(p.x, p.z) / UV_METRES
	if a.x >= a.z:
		return Vector2(p.z, -p.y) / UV_METRES
	return Vector2(p.x, -p.y) / UV_METRES
