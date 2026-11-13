class_name TextShape
extends RefCounted
## Text as geometry. The letters lie in the text's own XY plane (reading left to right along +X, up along +Y) and are
## extruded towards the viewer along +Z, from z = 0 (the back, sitting on a surface) to z = depth.
##   flat     a sign: a hair-thin layer of letters, no collision
##   3d       solid letters you can stand on (embossed when placed on a surface)
## (Engraving into blocks was tried in 0.4 and dropped in 0.5.3: as convex brushes it means hundreds of pieces per
## word, visible seams and a slow editor. Old engraved text loads as 3D letters.)
## Letter shapes come from Godot's TextMesh (any installed font or a font file); for collision and CS:S brushes the
## letters are split into convex pieces, merged as far as they stay convex to keep the count down.

const MODES := ["flat", "3d"]
const MODE_LABELS := {"flat": "Flat sign (2D)", "3d": "3D letters"}
const FONTS := ["Arial", "Arial Black", "Impact", "Segoe UI", "Verdana", "Tahoma", "Georgia", "Times New Roman",
	"Courier New", "Trebuchet MS", "Comic Sans MS"]
const FLAT_DEPTH := 0.02
const DECAL_LIFT := 0.001        ## letters sit 1 mm proud of the surface they're placed on: no z-fighting with it
const DEFAULTS := {
	"text": "SURF", "font": "Arial Black", "height": 4.0, "depth": 0.6, "mode": "3d", "align": "center",
	"position": [0.0, 0.0, 0.0], "yaw": 0.0, "pitch": 0.0, "roll": 0.0, "material": "", "color": "f2f2f2",
	"glow": 0.0, "solid": true,
}

static var _fonts := {}
static var _polys := {}


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not s["mode"] in MODES:
		s["mode"] = "3d"
	return s


static func depth_of(s: Dictionary) -> float:
	return FLAT_DEPTH if s["mode"] == "flat" else maxf(float(s["depth"]), 0.05)


static func transform_of(s: Dictionary) -> Transform3D:
	var p: Array = s["position"]
	var b := Basis.from_euler(Vector3(deg_to_rad(float(s["pitch"])), deg_to_rad(float(s["yaw"])), deg_to_rad(float(s["roll"]))), EULER_ORDER_YXZ)
	return Transform3D(b, Vector3(p[0], p[1], p[2]))


## Let go of the cached fonts when the editor closes, so they are freed while Godot's text server is still up (a
## static var is only cleared after it). The exit crash itself was TextNode's uncollected worker tasks.
static func release_fonts() -> void:
	_fonts.clear()


## An installed font by name, or a font file (.ttf / .otf / .woff).
static func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var f: Font
	if name.get_extension().to_lower() in ["ttf", "otf", "woff", "woff2"] and FileAccess.file_exists(name):
		var ff := FontFile.new()
		ff.load_dynamic_font(name)
		f = ff
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([name, "Arial", "Segoe UI"])
		f = sf
	_fonts[name] = f
	return f


## A TextMesh for these settings (letters about `height` meters tall, centered on the origin, z -depth/2..+depth/2).
static func text_mesh(s: Dictionary, depth: float) -> TextMesh:
	var tm := TextMesh.new()
	tm.text = String(s["text"]) if String(s["text"]) != "" else " "
	tm.font = font(s["font"])
	tm.font_size = 64
	tm.pixel_size = float(s["height"]) / 64.0
	tm.depth = depth
	tm.curve_step = 2.0                                  # smooth enough, and far fewer pieces than the default
	tm.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(s["align"], HORIZONTAL_ALIGNMENT_CENTER)
	return tm


## The letters as convex 2D polygons (meters, in the text's plane). Worked out once per text / font / alignment at
## 1 m letters and scaled, so changing the letter height costs nothing.
static func convex_polygons(s: Dictionary) -> Array:
	var unit = cached_unit_polygons(s)
	if unit == null:
		unit = unit_polygons(s)
		_polys[_poly_key(s)] = unit
	var h := float(s["height"])
	var out: Array = []
	for poly in unit:
		var scaled: Array = []
		for p in poly:
			scaled.append(p * h)
		out.append(scaled)
	return out


static func _poly_key(s: Dictionary) -> String:
	return "%s|%s|%s" % [s["text"], s["font"], s["align"]]


## The cached 1 m polygons, or null if they haven't been worked out yet.
static func cached_unit_polygons(s: Dictionary):
	return _polys.get(_poly_key(s))


## Remember polygons worked out elsewhere (on a worker thread).
static func store_unit_polygons(s: Dictionary, polys: Array) -> void:
	_polys[_poly_key(s)] = polys


## The convex polygons for 1 m letters. Doesn't touch the cache, so it can run on a worker thread.
static func unit_polygons(s0: Dictionary) -> Array:
	var s := s0.duplicate()
	s["height"] = 1.0
	var arr := text_mesh(s, 1.0).get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var index = arr[Mesh.ARRAY_INDEX]
	var count: int = (index.size() if index else verts.size()) / 3
	var tris: Array = []
	for t in count:
		var ids: Array = [index[t * 3], index[t * 3 + 1], index[t * 3 + 2]] if index else [t * 3, t * 3 + 1, t * 3 + 2]
		if normals[ids[0]].z < 0.9:
			continue                                     # only the front face: the letter shapes themselves
		var tri := [Vector2(verts[ids[0]].x, verts[ids[0]].y), Vector2(verts[ids[1]].x, verts[ids[1]].y), Vector2(verts[ids[2]].x, verts[ids[2]].y)]
		if absf((tri[1] - tri[0]).cross(tri[2] - tri[0])) < 1e-8:
			continue
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]) < 0.0:
			tri = [tri[0], tri[2], tri[1]]               # counter-clockwise
		tris.append(tri)
	return _merge_convex(tris)


## Hertel-Mehlhorn: merge neighboring polygons across shared edges as long as the result stays convex.
static func _merge_convex(tris: Array) -> Array:
	var polys: Array = tris.duplicate(true)
	var changed := true
	while changed:                                       # a few passes; each merges as much as it can
		changed = false
		var edges := {}                                  # rounded edge -> [polygon index, edge index]
		for pi in polys.size():
			var p: Array = polys[pi]
			if p.is_empty():
				continue
			var merged_here := false
			for ei in p.size():
				var a: Vector2 = p[ei]
				var b: Vector2 = p[(ei + 1) % p.size()]
				var k := _edge_key(b, a)                 # the neighbor runs the same edge the other way
				if edges.has(k):
					var other: Array = edges[k]
					var q: Array = polys[other[0]]
					# the entry may be stale (that polygon grew this pass): check the edge is still there
					if q.size() > other[1] and _edge_key(q[other[1]], q[(other[1] + 1) % q.size()]) == k:
						var merged := _join(q, other[1], p, ei)
						if not merged.is_empty() and _convex(merged):
							polys[other[0]] = merged
							polys[pi] = []
							changed = true
							merged_here = true
							break
			if not merged_here:
				for ei in p.size():
					edges[_edge_key(p[ei], p[(ei + 1) % p.size()])] = [pi, ei]
	return polys.filter(func(p): return not p.is_empty())


static func _edge_key(a: Vector2, b: Vector2) -> String:
	return "%d,%d>%d,%d" % [roundi(a.x * 10000), roundi(a.y * 10000), roundi(b.x * 10000), roundi(b.y * 10000)]


## Join polygon p (whose edge pe runs a->b) with q (whose edge qe runs b->a) into one polygon.
static func _join(p: Array, pe: int, q: Array, qe: int) -> Array:
	# p's edge runs x -> y and q's runs y -> x. Walk p from y all the way round to x, then q's other corners.
	var out: Array = []
	var n := p.size()
	for i in n:
		out.append(p[(pe + 1 + i) % n])                  # y ... x
	var m := q.size()
	for i in m - 2:
		out.append(q[(qe + 2 + i) % m])                  # the corners of q that aren't on the shared edge
	return out


static func _convex(poly: Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	var area := 0.0
	for i in n:
		if (poly[i] as Vector2).distance_to(poly[(i + 1) % n]) < 1e-6:
			return false                                 # a repeated corner: not a proper polygon
		area += (poly[i] as Vector2).cross(poly[(i + 1) % n])
	if area <= 1e-9:
		return false
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var c: Vector2 = poly[(i + 2) % n]
		if (b - a).cross(c - b) < -1e-7:
			return false
	return true


## The letters as world-space convex pieces: z from `z0` to `z1` in the text's own space.
static func pieces(s: Dictionary, z0: float, z1: float) -> Array:
	var xf := transform_of(s)
	var out: Array = []
	for poly in convex_polygons(s):
		var base: Array = []
		for p in poly:
			base.append(Vector3(p.x, p.y, z0))
		out.append(Convex.transformed(Convex.extrude(base, Vector3(0, 0, z1 - z0)), xf))
	return out


## The pieces that collide / become brushes for this text. They get the same 1 mm lift as the letters: a flat sign
## placed exactly on a wall face would otherwise export a brush side in the wall's own plane (a VBSP duplicate
## plane), and a brush that doesn't line up with the letters it stands for.
static func solid_pieces(s: Dictionary) -> Array:
	return pieces(s, DECAL_LIFT, DECAL_LIFT + depth_of(s))


## The visible mesh (in the text's own space) - smooth curved letters straight from the font.
static func mesh(s: Dictionary) -> Mesh:
	var d := depth_of(s)
	var tm := text_mesh(s, d)
	var arr := tm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] += Vector3(0, 0, d * 0.5 + DECAL_LIFT)  # back face 1 mm off z = 0 (the surface it sits on)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func material(s: Dictionary) -> Material:
	var c := Color.html(s["color"])
	var m: StandardMaterial3D
	if s["material"] != "" and MaterialLibrary.has(s["material"]):
		m = MaterialLibrary.material(s["material"], c).duplicate()
		m.uv1_triplanar = true                           # text has no texture layout of its own: project it
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / MaterialLibrary.world_size(s["material"])
	else:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.45
	if float(s["glow"]) > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = float(s["glow"])
	return m
