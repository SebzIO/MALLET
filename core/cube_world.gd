class_name CubeWorld
extends RefCounted
## Cube geometry you build by hand, the way Cube 2: Sauerbraten's editor works (its ideas re-implemented here, not
## its code): a grid of cubes at power-of-two sizes; pull cubes out of faces and push them back in, push a face or
## corners in 1/8 steps for slopes and bevels, sculpt it like a heightmap, texture each face (with Sauerbraten's
## texture settings: scale, rotate, offset, scroll, color, see-through, a blend layer you paint in), and fill empty
## space with materials (water, lava, glass, clip, noclip, gameclip, death, alpha).
##
## A cube is 8 corners, each on its own 0..8 grid inside the cube (Sauerbraten stores the same thing as 12 edges of
## two 4-bit values; corner n's coordinate along axis d is one end of the edge along d - the same 24 numbers).
## A cube is always convex, so every cube is one convex solid: one collision shape, and one brush in a CS:S export.
##
## Positions are in ticks of 1/8 m in the cube object's own space. A cube of grid power p is 2^p m (p = -3 .. 6:
## 0.125 m .. 64 m) and sits on a multiple of its size. Cubes never overlap: making a small cube inside a big one
## splits the big one into 8.

const TICK := 0.125
const MIN_P := -3
const MAX_P := 6
const INDEX_TICKS := 512                 ## 64 m: the biggest cube, so no cube straddles an index cell
## Render chunks come in two sizes, by the size of the cube. Cubes of half a meter or less (generated shapes, detail)
## go in 4 m chunks, so an edit there redraws little. Bigger cubes go in 16 m chunks: a cube goes in the chunk it
## starts in, so 4 m chunks for a build of big cubes would be a chunk (a draw call, a physics body) per cube; a map of
## big blocks made 14,000 chunks that way, ran at 7 fps and went past the physics engine's body limit.
const RENDER_TICKS := 128                ## 16 m: the big chunks
const FINE_TICKS := 32                   ## 4 m: the small chunks
const FINE_MAX_P := -1                   ## cubes up to this size (0.5 m) go in the small chunks
const _RENDER_SHIFT := 7                 ## RENDER_TICKS = 1 << this
const _FINE_SHIFT := 5                   ## FINE_TICKS = 1 << this
const COARSE_TAG := 1 << 22              ## a big chunk's key has this added to y (keeps the two kinds of key apart)
const _INDEX_SHIFT := 9                  ## INDEX_TICKS = 1 << this
## Faces, numbered like Sauerbraten's orientations: axis * 2 + side (side 1 = the + side). Y is up here.
const ORIENT_SLOTS := ["left", "right", "bottom", "top", "front", "back"]   ## -X, +X, -Y, +Y, -Z, +Z
## Sauerbraten's materials (what fills empty space). "air" = none.
const MATERIALS := ["air", "water", "lava", "glass", "clip", "noclip", "gameclip", "death", "alpha"]
const MATERIAL_INFO := {
	"water": "water: see-through and moving (in CS:S real water; SurfsUp has no swimming)",
	"lava": "lava: glows, and touching it sends you back",
	"glass": "glass: see-through but solid",
	"clip": "clip: an invisible wall",
	"noclip": "noclip: cubes inside are drawn but you pass through them",
	"gameclip": "gameclip: an invisible wall (like clip)",
	"death": "death: an invisible area that sends you back",
	"alpha": "alpha: cubes inside are see-through",
}
const MAT_COLORS := {"water": Color(0.2, 0.5, 0.9, 0.35), "lava": Color(1.0, 0.35, 0.05, 0.6), "glass": Color(0.7, 0.9, 1.0, 0.18),
	"clip": Color(0.6, 0.2, 0.9, 0.22), "noclip": Color(0.2, 0.9, 0.3, 0.22), "gameclip": Color(0.45, 0.2, 0.7, 0.22),
	"death": Color(0.9, 0.1, 0.1, 0.28), "alpha": Color(0.3, 0.9, 0.9, 0.2)}
## Heightmap brushes (Sauerbraten's B + wheel): how many 1/8 steps each corner point moves.
const BRUSHES := [
	["Point", [[1]]],
	["Small round", [[0, 1, 0], [1, 2, 1], [0, 1, 0]]],
	["Round", [[0, 0, 1, 0, 0], [0, 1, 2, 1, 0], [1, 2, 3, 2, 1], [0, 1, 2, 1, 0], [0, 0, 1, 0, 0]]],
	["Big round", [[0, 0, 0, 1, 0, 0, 0], [0, 0, 1, 1, 1, 0, 0], [0, 1, 2, 2, 2, 1, 0], [1, 1, 2, 3, 2, 1, 1],
		[0, 1, 2, 2, 2, 1, 0], [0, 0, 1, 1, 1, 0, 0], [0, 0, 0, 1, 0, 0, 0]]],
	["Square", [[1, 1, 1], [1, 1, 1], [1, 1, 1]]],
	["Big square", [[1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1], [1, 1, 1, 1, 1]]],
	["Smooth", []],
]

static var FULL := _full_corners()
static var _slot_cache := {}
static var _materials := {}
static var _shaders := {}

var leaves := {}                         ## Vector4i(x, y, z, p) -> [corners PackedByteArray(24), slots PackedStringArray(6), blend PackedByteArray(0 or 8)]
var mats := {}                           ## Vector4i(x, y, z, p) -> material name (cells of empty space filled with water etc.)
const FACE_GROW := 0.0005                ## meters: a cut cube's faces are drawn this much bigger, so neighbors overlap
const CUT_THREADS_FROM := 256            ## a chunk with this many cut cubes works them out on all cores
var show_mats := true                    ## draw the invisible materials (clip, death...) - Sauerbraten's M
var dirty := {}                          ## render chunk Vector3i -> true
var reading_task := -1                   ## a WorkerThreadPool group task reading this world (a background redraw), or -1


## Wait for a background redraw that reads this world (before anything changes it).
func finish_reading() -> void:
	if reading_task >= 0:
		Trail.note("  (a change waits for the background redraw)")
		WorkerThreadPool.wait_for_group_task_completion(reading_task)
		reading_task = -1


var revision := 0
var _index := {}                         ## Vector3i (64 m cell) -> {Vector4i: true}
var _render := {}                        ## Vector3i (16 m chunk) -> {Vector4i: true}
var _mrender := {}                       ## render chunk -> {material cell: true}
var _occ := {}                           ## Vector4i(cell, q) -> how many smaller cubes are inside that cell (fast "is anything there")
var _mocc := {}                          ## the same for material cells
var _edit = null                         ## while an edit is open: {key: value before the edit (or null)}
var _undo: Array = []
var _redo: Array = []
var _saved_rev := -1
var _saved := {}


static func _full_corners() -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(24)
	for n in 8:
		for d in 3:
			c[n * 3 + d] = 8 if (n >> d) & 1 else 0
	return c


static func size_of(p: int) -> int:
	return 1 << (p + 3)


static func metres(p: int) -> float:
	return size_of(p) * TICK


static func _fdiv(a: int, b: int) -> int:
	return floori(float(a) / float(b))


static func blank_tex(id := "") -> PackedStringArray:
	var t := PackedStringArray()
	t.resize(6)
	t.fill(id)
	return t


## The face direction (0..5) a normal points along most.
static func orient_of(n: Vector3) -> int:
	var a := n.abs()
	var d := 0 if a.x >= a.y and a.x >= a.z else (1 if a.y >= a.z else 2)
	return d * 2 + (1 if n[d] > 0.0 else 0)


static func orient_normal(o: int) -> Vector3:
	var v := Vector3.ZERO
	v[o >> 1] = 1.0 if o & 1 else -1.0
	return v


const _STEPS := [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]


static func orient_step(o: int) -> Vector3i:
	var v := Vector3i.ZERO
	v[o >> 1] = 1 if o & 1 else -1
	return v


# ------------------------------------------------------------------------------------------------ texture slots
## A face's texture: a library material id plus Sauerbraten's texture settings (vscale, vrotate, voffset, vscroll,
## vcolor, valpha, vlayer), written as "id" or "id|s=2;r=1;u=0.25;..." so faces with equal settings share a mesh
## surface. Keys: s scale, r rotate (0-3 quarter turns, 4 flip across, 5 flip up), u / v offset (repeats),
## su / sv scroll (repeats a second), c color (hex), a see-through (0-1), l blend layer texture.
const SLOT_DEFAULTS := {"id": "", "s": 1.0, "r": 0, "u": 0.0, "v": 0.0, "su": 0.0, "sv": 0.0, "sp": 0.0, "sw": 0.0,
	"c": "ffffff", "a": 1.0, "l": ""}                    ## sp spin (degrees a second), sw swirl (degrees): spiral motion


static func parse_slot(slot: String) -> Dictionary:
	if _slot_cache.has(slot):
		return _slot_cache[slot]
	var main := OS.get_thread_caller_id() == OS.get_main_thread_id()   # (workers only read the cache: no racing writes)
	var out := SLOT_DEFAULTS.duplicate()
	var parts := slot.split("|", true, 1)
	out["id"] = parts[0]
	if parts.size() > 1:
		for kv in parts[1].split(";", false):
			var pair := kv.split("=", true, 1)
			if pair.size() == 2 and out.has(pair[0]):
				var def = SLOT_DEFAULTS[pair[0]]
				out[pair[0]] = int(pair[1]) if def is int else (float(pair[1]) if def is float else pair[1])
	if main:
		_slot_cache[slot] = out
	return out


static func make_slot(d: Dictionary) -> String:
	var bits := PackedStringArray()
	for k in ["s", "r", "u", "v", "su", "sv", "sp", "sw", "c", "a", "l"]:
		var v = d.get(k, SLOT_DEFAULTS[k])
		if v is float:
			v = snappedf(v, 0.0001)
		if v != SLOT_DEFAULTS[k]:
			bits.append("%s=%s" % [k, str(v)])
	return String(d.get("id", "")) + ("" if bits.is_empty() else "|" + ";".join(bits))


static func slot_id(slot: String) -> String:
	return slot.get_slice("|", 0)


## The same slot with another texture (keeping its settings).
static func with_id(slot: String, id: String) -> String:
	var d := parse_slot(slot).duplicate()
	d["id"] = id
	return make_slot(d)


## Texture coordinates for a point on a face: world-aligned like blocks, then the slot's scale, turn / flip, offset.
static func slot_uv(p: Vector3, n: Vector3, sl: Dictionary, layer := false) -> Vector2:
	var id: String = sl["l"] if layer else sl["id"]
	var m := BlockShape._uv(p, n) * BlockShape.UV_METRES
	var size := (MaterialLibrary.world_size(id) if id != "" and MaterialLibrary.has(id) else BlockShape.UV_METRES) \
		* maxf(float(sl["s"]), 0.01)
	var uv := m / size
	match int(sl["r"]):
		1: uv = Vector2(-uv.y, uv.x)
		2: uv = -uv
		3: uv = Vector2(uv.y, -uv.x)
		4: uv.x = -uv.x
		5: uv.y = -uv.y
	return uv + Vector2(sl["u"], sl["v"])


## The material for a face slot (texture, color, see-through, scrolling, blend layer).
static func material_for(slot: String, alpha_mat := false) -> Material:
	var key := slot + ("#alpha" if alpha_mat else "")
	if _materials.has(key):
		return _materials[key]
	var sl := parse_slot(slot)
	var id: String = sl["id"]
	var lib := id != "" and MaterialLibrary.has(id)
	var tint := Color.html(sl["c"])
	var alpha := float(sl["a"]) * (0.5 if alpha_mat and float(sl["a"]) >= 1.0 else 1.0)
	var plain: bool = tint == Color.WHITE and alpha >= 1.0 and float(sl["su"]) == 0.0 and float(sl["sv"]) == 0.0 and sl["l"] == "" 		and float(sl["sp"]) == 0.0 and float(sl["sw"]) == 0.0
	var m: Material
	if plain:
		m = MaterialLibrary.material(id, Color.WHITE) if lib else Look.ramp_material("grid", Color.html("9aa3ad"), "", 20.0, "", 10.5, true)
	else:
		var sm := ShaderMaterial.new()
		sm.shader = _surface_shader(alpha < 1.0)
		var base: StandardMaterial3D = MaterialLibrary.material(id, Color.WHITE) if lib else null
		if base:
			sm.set_shader_parameter("albedo_tex", base.albedo_texture)
			if base.normal_texture:
				sm.set_shader_parameter("normal_tex", base.normal_texture)
				sm.set_shader_parameter("has_normal", true)
			if base.roughness_texture:
				sm.set_shader_parameter("rough_tex", base.roughness_texture)
				sm.set_shader_parameter("has_rough", true)
			if base.emission_texture:
				sm.set_shader_parameter("glow_tex", base.emission_texture)
				sm.set_shader_parameter("has_glow", true)
				sm.set_shader_parameter("glow_energy", MaterialLibrary.GLOW_ENERGY)
		else:
			tint = tint * Color.html("9aa3ad")
		sm.set_shader_parameter("tint", tint)
		sm.set_shader_parameter("alpha", alpha)
		sm.set_shader_parameter("scroll", Vector2(sl["su"], sl["sv"]))
		sm.set_shader_parameter("spin", float(sl["sp"]))
		sm.set_shader_parameter("swirl", float(sl["sw"]))
		if lib:
			MaterialLibrary.shader_finish(sm, id)
		var lid: String = sl["l"]
		if lid != "" and MaterialLibrary.has(lid):
			var lm := MaterialLibrary.material(lid, Color.WHITE)
			sm.set_shader_parameter("use_layer", true)
			sm.set_shader_parameter("layer_tex", lm.albedo_texture)
			if lm.normal_texture:
				sm.set_shader_parameter("layer_normal", lm.normal_texture)
				sm.set_shader_parameter("layer_has_normal", true)
		m = sm
	_materials[key] = m
	return m


static func _surface_shader(see_through: bool, double_sided := false) -> Shader:
	var k := ("alpha" if see_through else "solid") + ("2" if double_sided else "")
	if not _shaders.has(k):
		var s := Shader.new()
		var code := FileAccess.get_file_as_string("res://core/shaders/cube_surface.gdshader")
		s.code = ("#define SEE_THROUGH\n" if see_through else "") + ("#define DOUBLE_SIDED\n" if double_sided else "") + code
		_shaders[k] = s
	return _shaders[k]


## The map's looks for build mode's water / lava / glass cubes (the Map panel): preset ids from Look.LIQUIDS / GLASS.
static var mat_looks := {"water": "water", "lava": "lava", "glass": "clear"}


## Use these looks (from the map's environment: water_look, lava_look, glass_look). True if anything changed.
static func set_mat_looks(env: Dictionary) -> bool:
	var want := {"water": env.get("water_look", "water"), "lava": env.get("lava_look", "lava"), "glass": env.get("glass_look", "clear"),
		"water_params": env.get("water_params", {}), "lava_params": env.get("lava_params", {}), "glass_params": env.get("glass_params", {})}
	if want == mat_looks:
		return false
	mat_looks = want
	for k in ["mat:water", "mat:lava", "mat:glass"]:     # (cells with a look of their own keep it)
		_materials.erase(k)
	return true


## A material cell's kind: "water", "lava", "glass", "clip"... A cell can name its own look after a colon (0.23.0):
## "water:pool", "lava:magma", "glass:frosted" (Look.LIQUIDS / Look.GLASS ids); without one it takes the map's.
static func mat_kind(name: String) -> String:
	return name.get_slice(":", 0)


static func mat_variant(name: String) -> String:
	return name.get_slice(":", 1) if ":" in name else ""


## The material for a kind with a look of its own ("" = the map's), as stored in a cell.
static func mat_name(kind: String, look: String) -> String:
	return kind + (":" + look if look != "" and kind in ["water", "lava", "glass"] else "")


static func material_look(name: String) -> Material:
	var kind := mat_kind(name)
	var own := mat_variant(name)
	var key := "mat:" + kind + ((":" + own) if own != "" else "")
	if _materials.has(key):
		return _materials[key]
	var m: Material
	match kind:
		"water":
			m = Look.liquid_material(own if own != "" else mat_looks.get("water", "water"))
			if own == "":
				Look.apply_params(m, "lava" if Look.LIQUIDS.get(mat_looks.get("water", "water"), {}).get("style", "") == "lava" else "water",
					mat_looks.get("water_params", {}))
		"lava":
			m = Look.liquid_material(own if own != "" else mat_looks.get("lava", "lava"))
			if own == "":
				Look.apply_params(m, "lava", mat_looks.get("lava_params", {}))
		"glass":
			m = Look.glass_material(own if own != "" else mat_looks.get("glass", "clear"))
			if own == "":
				Look.apply_params(m, "glass", mat_looks.get("glass_params", {}))
		_:
			var sm := StandardMaterial3D.new()
			var c: Color = MAT_COLORS.get(name, Color(1, 1, 1, 0.2))
			sm.albedo_color = c
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.no_depth_test = false
			m = sm
	_materials[key] = m
	return m


# ------------------------------------------------------------------------------------------------ cube shape
static func corner(c: PackedByteArray, n: int) -> Vector3:
	return Vector3(c[n * 3], c[n * 3 + 1], c[n * 3 + 2])


## The 4 corners of face o, counter-clockwise seen from outside.
static func face_corners(o: int) -> Array:
	if _fc_table.is_empty():                              # (built once: meshing asks for these millions of times)
		for f in 6:
			_fc_table.append(_make_face_corners(f))
	return _fc_table[o]


static var _fc_table := []                               ## face_corners per orient - shared, never modify


static func _make_face_corners(o: int) -> Array:
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var out := []
	for ab in [[0, 0], [1, 0], [1, 1], [0, 1]]:
		out.append(((o & 1) << d) | (ab[0] << a) | (ab[1] << b))
	if not o & 1:
		out.reverse()
	return out


static func is_empty_shape(c: PackedByteArray) -> bool:
	for d in 3:
		var all_closed := true
		for n in 8:
			if (n >> d) & 1:
				continue
			if c[(n | (1 << d)) * 3 + d] > c[n * 3 + d]:
				all_closed = false
				break
		if all_closed:
			return true
	return false


## The face as triangles of corner numbers, split along whichever diagonal keeps the cube convex.
static func face_tri_indices(c: PackedByteArray, o: int) -> Array:
	var q: Array = face_corners(o)
	var p := []
	for n in q:
		p.append(corner(c, n))
	var n0: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var diag_ac := n0.length() < 1e-6 or n0.dot(p[3] - p[0]) <= 1e-6
	var cand := [[0, 1, 2], [0, 2, 3]] if diag_ac else [[1, 2, 3], [1, 3, 0]]
	var out := []
	for t in cand:
		if (p[t[1]] - p[t[0]]).cross(p[t[2]] - p[t[0]]).length() > 1e-6:
			out.append([q[t[0]], q[t[1]], q[t[2]]])
	return out


static func face_triangles(c: PackedByteArray, o: int) -> Array:
	var out := []
	for t in face_tri_indices(c, o):
		out.append([corner(c, t[0]), corner(c, t[1]), corner(c, t[2])])
	return out


static func is_valid_shape(c: PackedByteArray) -> bool:
	var pts := []
	for n in 8:
		pts.append(corner(c, n))
	for o in 6:
		var want := orient_normal(o)
		for t in face_triangles(c, o):
			var nrm: Vector3 = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
			if nrm.dot(want) < -1e-4:
				return false
			for p in pts:
				if nrm.dot(p - t[0]) > 1e-3:
					return false
	return true


static func face_is_full(c: PackedByteArray, o: int) -> bool:
	if c == FULL:
		return true
	for n in face_corners(o):
		for d in 3:
			if c[n * 3 + d] != FULL[n * 3 + d]:
				return false
	return true


static func _nudge(c: PackedByteArray, o: int, n: int, dir: int) -> void:
	var d := o >> 1
	var i := n * 3 + d
	var partner: int = c[(n ^ (1 << d)) * 3 + d]
	var v: int = c[i]
	if o & 1:
		v = clampi(v - dir, partner, 8)
	else:
		v = clampi(v + dir, 0, partner)
	c[i] = v


## A child's corners when a cube is split into 8 (octant o = its x / y / z bits): each child corner goes to the point
## of (the parent's solid inside the child's cell) nearest to where that corner would sit on a full cube - so the
## children follow the parent's slopes instead of approximating them edge by edge (which could bend a child inside
## out, or step out of the slope). Rounded to the child's 1/8 grid; a child that ends up a hair concave is nudged
## back to convex.
static func child_corners(c: PackedByteArray, o: int) -> PackedByteArray:
	if c == FULL:
		return FULL
	var off := Vector3(4.0 * (o & 1), 4.0 * ((o >> 1) & 1), 4.0 * ((o >> 2) & 1))
	var planes := solid_planes(c)
	for d in 3:                                          # ...and the child's cell
		var lo_n := Vector3.ZERO
		lo_n[d] = -1.0
		planes.append([lo_n, -off[d]])
		var hi_n := Vector3.ZERO
		hi_n[d] = 1.0
		planes.append([hi_n, off[d] + 4.0])
	if not _region_has_volume(planes, off):
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(24)
	for m in 8:
		var home := off + Vector3(4.0 * (m & 1), 4.0 * ((m >> 1) & 1), 4.0 * ((m >> 2) & 1))
		var q := _corner_spot(planes, home)
		for d in 3:
			out[m * 3 + d] = clampi(roundi((q[d] - off[d]) * 2.0), 0, 8)
	for d in 3:                                          # an edge's ends never cross
		for m in 8:
			if not (m >> d) & 1:
				var hi_i := (m | (1 << d)) * 3 + d
				if out[hi_i] < out[m * 3 + d]:
					out[hi_i] = out[m * 3 + d]
	if is_empty_shape(out):
		return PackedByteArray()
	if not is_valid_shape(out):
		out = _make_valid(out)
	if out.is_empty() or is_empty_shape(out):
		return PackedByteArray()
	return out


## Where a child's corner goes: it stays on as many of its cell's walls as it can, so neighboring pieces still meet
## edge to edge. Its own spot if that's solid; else the nearest solid point sliding along one of its 3 edges; else
## within one of its 3 walls; else anywhere. (Taking the nearest point in any direction moved corners off the
## walls diagonally, leaving wedge-shaped gaps between pieces of a slope.)
static func _corner_spot(planes: Array, home: Vector3) -> Vector3:
	if _in_planes(planes, home):
		return home
	var best = null
	var best_d := INF
	for d in 3:                                          # slide along an edge (only coordinate d changes)
		var lo := -INF
		var hi := INF
		var empty := false
		for pl in planes:
			var n: Vector3 = pl[0]
			var room: float = float(pl[1]) - n.dot(home)  # n_d * t <= room
			if absf(n[d]) < 1e-9:
				if room < -1e-6:
					empty = true
					break
			elif n[d] > 0.0:
				hi = minf(hi, room / n[d])
			else:
				lo = maxf(lo, room / n[d])
		if empty or lo > hi + 1e-6:
			continue
		var t := clampf(0.0, lo, hi)
		if absf(t) < best_d:
			best_d = absf(t)
			best = home
			best[d] += t
	if best != null:
		return best
	for d in 3:                                          # within a wall (coordinate d stays put)
		var on_wall := planes.duplicate()
		var e := Vector3.ZERO
		e[d] = 1.0
		on_wall.append([e, home[d]])
		on_wall.append([-e, -home[d]])
		var q := _nearest_in(on_wall, home)
		if _in_planes(on_wall, q, 1e-3) and q.distance_to(home) < best_d:
			best_d = q.distance_to(home)
			best = q
	if best != null:
		return best
	return _nearest_in(planes, home)


static func _in_planes(planes: Array, p: Vector3, eps := 1e-6) -> bool:
	for pl in planes:
		if (pl[0] as Vector3).dot(p) - float(pl[1]) > eps:
			return false
	return true


## The point of a convex region (outward planes [normal, d]) nearest to p: Dykstra's alternating projections.
static func _nearest_in(planes: Array, p: Vector3) -> Vector3:
	var x := p
	var fixes := []
	fixes.resize(planes.size())
	fixes.fill(Vector3.ZERO)
	for it in 60:
		var moved := 0.0
		for i in planes.size():
			var n: Vector3 = planes[i][0]
			var k: float = planes[i][1]
			var y: Vector3 = x + fixes[i]
			var dist := n.dot(y) - k
			var z: Vector3 = y - n * dist if dist > 0.0 else y
			fixes[i] = y - z
			moved += (z - x).length_squared()
			x = z
		if moved < 1e-10:
			break
	return x


## Is there anything (more than a sliver) of the region inside the child cell? (Some point of the cell's 4 x 4 x 4
## sample grid strictly inside it.)
static func _region_has_volume(planes: Array, off: Vector3) -> bool:
	for i in 5:
		for j in 5:
			for k in 5:
				var pt := off + Vector3(0.1 + 0.95 * i, 0.1 + 0.95 * j, 0.1 + 0.95 * k)
				var ok := true
				for pl in planes:
					if (pl[0] as Vector3).dot(pt) - float(pl[1]) > -0.02:
						ok = false
						break
				if ok:
					return true
	return false


## The outward planes of a cube's solid, in its 0..8 units: [normal, d] for each face triangle.
static func solid_planes(c: PackedByteArray) -> Array:
	var out := []
	for o in 6:
		for t in face_triangles(c, o):
			var n: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).normalized()
			out.append([n, n.dot(t[0])])
	return out


## Rounding a child to whole 1/8 steps can leave it a hair concave: move the offending corners towards the inside
## until it's a proper convex cube again (or give up and drop it).
static func _make_valid(c: PackedByteArray) -> PackedByteArray:
	var cur := c.duplicate()
	for attempt in 24:
		if is_valid_shape(cur):
			return cur
		var moved := false
		for n in 8:
			for d in 3:
				var i := n * 3 + d
				var partner := (n ^ (1 << d)) * 3 + d
				var trial := cur.duplicate()
				if (n >> d) & 1:
					trial[i] = maxi(trial[i] - 1, trial[partner])
				else:
					trial[i] = mini(trial[i] + 1, trial[partner])
				if trial[i] != cur[i] and _concavity(trial) < _concavity(cur):
					cur = trial
					moved = true
		if not moved:
			break
	return cur if is_valid_shape(cur) else PackedByteArray()


## How far the corners stick out past the faces (0 = convex).
static func _concavity(c: PackedByteArray) -> float:
	var worst := 0.0
	var pts := []
	for n in 8:
		pts.append(corner(c, n))
	for o in 6:
		var want := orient_normal(o)
		for t in face_triangles(c, o):
			var nrm: Vector3 = ((t[1] - t[0]) as Vector3).cross(t[2] - t[0]).normalized()
			if nrm.dot(want) < 0.0:
				worst += 1.0 - nrm.dot(want)
			for p in pts:
				worst += maxf(0.0, nrm.dot(p - t[0]))
	return worst


# ------------------------------------------------------------------------------------------------ exact cut pieces
## When a shaped cube is split into smaller ones, a piece's share of the slope often can't be drawn with its own 8
## corners (their 1/8 steps don't land where the slope crosses the piece). Such a piece keeps the original's exact
## shape instead: a "cut" = the original's face planes, moved into the piece's own 0..8 units. The piece's solid is
## its cell minus everything outside those planes - convex and exact at any depth (whole-number maths: halving the
## cell doubles a plane's offset, nothing is ever rounded). Its corners (v[0]) still hold the nearest 8-corner shape,
## for tools that work on corners (pushing faces / corners, heightmap); editing those corners drops the cut.
## A cut plane is [normal Vector3i, offset int, slot orient int]: solid where normal . u <= offset.

static func _cut_of(v: Array) -> Array:
	return v[3] if v.size() > 3 else []


static func _idot(a: Vector3i, b: Vector3i) -> int:
	return a.x * b.x + a.y * b.y + a.z * b.z


static func _icross(a: Vector3i, b: Vector3i) -> Vector3i:
	return Vector3i(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)


static func _gcd(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a


## A corner cube's solid as exact cut planes (cell walls left out: the cell bounds every piece anyway).
static func cut_from_corners(c: PackedByteArray) -> Array:
	var out := []
	var seen := {}
	for o in 6:
		for t in face_tri_indices(c, o):
			var a := Vector3i(corner(c, t[0]))
			var n := _icross(Vector3i(corner(c, t[1])) - a, Vector3i(corner(c, t[2])) - a)
			var g := _gcd(_gcd(n.x, n.y), n.z)
			if g == 0:
				continue
			n /= g
			var d := _idot(n, a)
			var key := [n, d]
			if seen.has(key):
				continue
			seen[key] = true
			var cuts_in := false                         # a face lying on the cell's own wall adds nothing
			for m in 8:
				if _idot(n, Vector3i(corner(FULL, m))) > d:
					cuts_in = true
					break
			if cuts_in:
				out.append([n, d, o])
	return out


## A cut moved into child octant o's units (child = half the size: offsets double, minus the child's offset).
static func _cut_child(cut: Array, o: int) -> Array:
	var off := Vector3i(8 * (o & 1), 8 * ((o >> 1) & 1), 8 * ((o >> 2) & 1))
	var out := []
	for pl in cut:
		out.append([pl[0], 2 * int(pl[1]) - _idot(pl[0], off), pl[2]])
	return out


## The cell walls plus a cut, as unit-normal float planes [normal, offset] (the form _corner_spot / solid_planes use).
static func cut_planes(cut: Array) -> Array:
	var out := []
	for d in 3:
		var e := Vector3.ZERO
		e[d] = 1.0
		out.append([-e, 0.0])
		out.append([e, 8.0])
	for pl in cut:
		var n := Vector3(pl[0])
		var l := n.length()
		out.append([n / l, float(pl[1]) / l])
	return out


## A cut piece's planes as plain floats [nx, ny, nz, d] (unit normals, walls first in orient order), inside = n . p <= d.
## GDScript floats are doubles but a Vector3 is single precision, and where two nearly parallel planes meet (the seams
## of a many-sided cone) single-precision rounding is bigger than any sensible tolerance: corners got rejected and
## whole faces vanished. So everything about a cut's corners is worked out here, in doubles, from its integer planes.
static func _cut_rows(cut: Array) -> Array:
	var rows := []
	for o in 6:
		var e := orient_normal(o)
		rows.append([float(e.x), float(e.y), float(e.z), 8.0 if o & 1 else 0.0])
	for pl in cut:
		var x := float(pl[0].x)
		var y := float(pl[0].y)
		var z := float(pl[0].z)
		var l := sqrt(x * x + y * y + z * z)
		rows.append([x / l, y / l, z / l, float(pl[1]) / l])
	return rows


## One polygon per plane: the face that plane leaves on the solid, flat [x, y, z, x, y, z...] in doubles, counter-clockwise
## from outside (empty: no face). Each face starts as a square on its plane and is clipped by the others, which costs
## far less than trying every combination of three planes.
static func _cut_polys(rows: Array, skip_walls := 0) -> Array:
	var out := []
	for fi in rows.size():
		if fi < 6 and skip_walls & (1 << fi):
			out.append(PackedFloat64Array())             # (a wall known to be hidden: no need to work it out)
			continue
		var r: Array = rows[fi]
		var nx: float = r[0]
		var ny: float = r[1]
		var nz: float = r[2]
		var tx: float
		var ty: float
		var tz: float
		if absf(nx) < 0.9:                               # t = n x X
			tx = 0.0
			ty = nz
			tz = -ny
		else:                                            # t = n x Y
			tx = -nz
			ty = 0.0
			tz = nx
		var tl := sqrt(tx * tx + ty * ty + tz * tz)
		tx /= tl
		ty /= tl
		tz /= tl
		var bx := ny * tz - nz * ty
		var by := nz * tx - nx * tz
		var bz := nx * ty - ny * tx
		var wall := fi < 6
		var h := 4.0 if wall else 64.0                   # (a wall is exactly its square; a slanted plane is cut down by the walls)
		var cx: float = nx * r[3] + (0.0 if wall and nx != 0.0 else 4.0 if wall else 0.0)
		var cy: float = ny * r[3] + (0.0 if wall and ny != 0.0 else 4.0 if wall else 0.0)
		var cz: float = nz * r[3] + (0.0 if wall and nz != 0.0 else 4.0 if wall else 0.0)
		var poly := PackedFloat64Array([cx + (tx + bx) * h, cy + (ty + by) * h, cz + (tz + bz) * h,
			cx + (bx - tx) * h, cy + (by - ty) * h, cz + (bz - tz) * h,
			cx - (tx + bx) * h, cy - (ty + by) * h, cz - (tz + bz) * h,
			cx + (tx - bx) * h, cy + (ty - by) * h, cz + (tz - bz) * h])
		for j in range(6 if wall else 0, rows.size()):
			if j == fi:
				continue
			poly = _clip_rows(poly, rows[j])
			if poly.size() < 9:
				break
		out.append(poly if poly.size() >= 9 and _poly_area2(poly) > 1e-9 else PackedFloat64Array())
	return out


## A polygon cut down to the inside of one plane row.
static func _clip_rows(poly: PackedFloat64Array, r: Array) -> PackedFloat64Array:
	var nx: float = r[0]
	var ny: float = r[1]
	var nz: float = r[2]
	var d: float = r[3]
	var n := poly.size()
	var all_in := true
	for i in range(0, n, 3):
		if nx * poly[i] + ny * poly[i + 1] + nz * poly[i + 2] - d > 1e-9:
			all_in = false
			break
	if all_in:
		return poly
	var out := PackedFloat64Array()
	var px := poly[n - 3]
	var py := poly[n - 2]
	var pz := poly[n - 1]
	var pd := nx * px + ny * py + nz * pz - d
	for i in range(0, n, 3):
		var x := poly[i]
		var y := poly[i + 1]
		var z := poly[i + 2]
		var cd := nx * x + ny * y + nz * z - d
		if (pd > 1e-9 and cd < -1e-9) or (pd < -1e-9 and cd > 1e-9):
			var t := pd / (pd - cd)
			out.append_array([px + (x - px) * t, py + (y - py) * t, pz + (z - pz) * t])
		if cd <= 1e-9:
			out.append_array([x, y, z])
		px = x
		py = y
		pz = z
		pd = cd
	return out


static func _poly_area2(p: PackedFloat64Array) -> float:
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	for i in range(3, p.size() - 3, 3):
		var ux := p[i] - p[0]
		var uy := p[i + 1] - p[1]
		var uz := p[i + 2] - p[2]
		var vx := p[i + 3] - p[0]
		var vy := p[i + 4] - p[1]
		var vz := p[i + 5] - p[2]
		ax += uy * vz - uz * vy
		ay += uz * vx - ux * vz
		az += ux * vy - uy * vx
	return sqrt(ax * ax + ay * ay + az * az)


## The corners of a cut piece's solid (empty if nothing is left).
static func cut_vertices(cut: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for poly in _cut_polys(_cut_rows(cut)):
		for i in range(0, poly.size(), 3):
			var v := Vector3(poly[i], poly[i + 1], poly[i + 2])
			var dup := false
			for q in out:
				if q.distance_squared_to(v) < 1e-10:
					dup = true
					break
			if not dup:
				out.append(v)
	return out


static func _has_volume(pts: PackedVector3Array) -> bool:
	if pts.size() < 4:
		return false
	var a := pts[0]
	for i in range(1, pts.size()):
		for j in range(i + 1, pts.size()):
			var n := (pts[i] - a).cross(pts[j] - a)
			if n.length() < 1e-9:
				continue
			for k in range(j + 1, pts.size()):
				if absf(n.dot(pts[k] - a)) > 1e-7:
					return true
	return false


## A cut, tidied: [corners, cut] for a piece (cut empty when 8 corners show it exactly), or [] when nothing's left.
static func shape_from_cut(cut: Array) -> Array:
	var cell_corners := []
	for n in 8:
		cell_corners.append(Vector3i(corner(FULL, n)))
	var live := []
	for pl in cut:                                       # only planes that actually cut into the cell
		for p in cell_corners:
			if _idot(pl[0], p) > int(pl[1]):
				live.append(pl)
				break
	if live.is_empty():
		return [FULL, []]
	var pts := cut_vertices(live)
	if not _has_volume(pts):
		return []
	var faces := []                                      # drop planes that only touch an edge or a corner
	for pl in live:
		var n := Vector3(pl[0])
		var on := 0
		for p in pts:
			if absf(n.dot(p) - float(pl[1])) < 1e-6 * n.length() * 8.0:
				on += 1
		if on >= 3:
			faces.append(pl)
	var planes := cut_planes(faces)
	var exact := PackedByteArray()                       # can its own 8 corners show it exactly?
	exact.resize(24)
	var whole := true
	for m in 8:
		var q := _corner_spot(planes, corner(FULL, m))
		for d in 3:
			var r := roundf(q[d])
			if absf(q[d] - r) > 1e-6:
				whole = false
			exact[m * 3 + d] = clampi(int(r), 0, 8)
	if whole and is_valid_shape(exact) and not is_empty_shape(exact) and _same_points(_corner_points(exact), pts):
		return [exact, []]
	return [_approx_corners(planes, pts), faces]


static func _corner_points(c: PackedByteArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in 8:
		var p := corner(c, n)
		if not out.has(p):
			out.append(p)
	return out


static func _same_points(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for p in a:
		var found := false
		for q in b:
			if p.distance_squared_to(q) < 1e-10:
				found = true
				break
		if not found:
			return false
	return true


## The nearest 8-corner shape to a region (for corner tools); if rounding leaves nothing valid, its bounding box.
static func _approx_corners(planes: Array, pts: PackedVector3Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(24)
	for m in 8:
		var q := _corner_spot(planes, corner(FULL, m))
		for d in 3:
			out[m * 3 + d] = clampi(roundi(q[d]), 0, 8)
	for d in 3:
		for m in 8:
			if not (m >> d) & 1:
				var hi_i := (m | (1 << d)) * 3 + d
				if out[hi_i] < out[m * 3 + d]:
					out[hi_i] = out[m * 3 + d]
	if not is_empty_shape(out) and not is_valid_shape(out):
		out = _make_valid(out)
	if not out.is_empty() and not is_empty_shape(out):
		return out
	var lo := Vector3.ONE * 8.0
	var hi := Vector3.ZERO
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var box := PackedByteArray()
	box.resize(24)
	for m in 8:
		for d in 3:
			box[m * 3 + d] = clampi(ceili(hi[d] - 1e-6), 1, 8) if (m >> d) & 1 else clampi(floori(lo[d] + 1e-6), 0, 7)
	return box


## A leaf's child in octant o, exact: [] if the child is empty.
static func split_child(v: Array, o: int) -> Array:
	var c: PackedByteArray = v[0]
	var cut := _cut_of(v)
	var bl := child_blend(_blend_of(v), o)
	if cut.is_empty():
		if c == FULL:
			return _v(FULL, v[1], bl)
		cut = cut_from_corners(c)
	var shp := shape_from_cut(_cut_child(cut, o))
	if shp.is_empty():
		return []
	return _v(shp[0], v[1], bl, shp[1])


## A leaf's solid as unit-normal float planes in its 0..8 units (cell walls included).
static func leaf_planes(v: Array) -> Array:
	var cut := _cut_of(v)
	if not cut.is_empty():
		return cut_planes(cut)
	return cut_planes(cut_from_corners(v[0]))


## Is wall o of a leaf a whole, flat square (so a neighbor's full face can hide it)?
static func leaf_face_full(v: Array, o: int) -> bool:
	var cut := _cut_of(v)
	if cut.is_empty():
		return v[0] == FULL or face_is_full(v[0], o)
	# the wall's four corners all inside every plane: each plane's worst corner is known without visiting them
	var d := o >> 1
	var at := 8 if o & 1 else 0
	for pl in cut:
		var n: Vector3i = pl[0]
		var worst := n[d] * at
		var a := n[(d + 1) % 3]
		var b := n[(d + 2) % 3]
		if a > 0:
			worst += a * 8
		if b > 0:
			worst += b * 8
		if worst > int(pl[1]):
			return false
	return true


## A cut piece's faces: [[slot orient, wall orient or -1, polygon PackedVector3Array counter-clockwise from outside, unit normal], ...]
static func cut_faces(cut: Array) -> Array:
	var rows := _cut_rows(cut)
	return _faces_of(cut, rows, _cut_polys(rows))


static func _faces_of(cut: Array, rows: Array, polys: Array) -> Array:
	var out := []
	for fi in rows.size():
		var poly: PackedFloat64Array = polys[fi]
		if poly.is_empty():
			continue
		var pts := PackedVector3Array()
		for i in range(0, poly.size(), 3):
			var v := Vector3(poly[i], poly[i + 1], poly[i + 2])
			if pts.is_empty() or pts[pts.size() - 1].distance_squared_to(v) > 1e-10:
				pts.append(v)
		if pts.size() > 1 and pts[0].distance_squared_to(pts[pts.size() - 1]) <= 1e-10:
			pts.remove_at(pts.size() - 1)
		if pts.size() < 3:
			continue
		var r: Array = rows[fi]
		out.append([fi if fi < 6 else int(cut[fi - 6][2]), fi if fi < 6 else -1, pts, Vector3(r[0], r[1], r[2])])
	return out


## Blend weights for a child (trilinear from the parent's corners).
static func child_blend(b: PackedByteArray, o: int) -> PackedByteArray:
	if b.is_empty():
		return b
	var out := PackedByteArray()
	out.resize(8)
	for m in 8:
		var t := Vector3((float(o & 1) + float(m & 1)) * 0.5, (float((o >> 1) & 1) + float((m >> 1) & 1)) * 0.5,
			(float((o >> 2) & 1) + float((m >> 2) & 1)) * 0.5)
		var v := 0.0
		for n in 8:
			var w := (t.x if n & 1 else 1.0 - t.x) * (t.y if (n >> 1) & 1 else 1.0 - t.y) * (t.z if (n >> 2) & 1 else 1.0 - t.z)
			v += w * b[n]
		out[m] = clampi(roundi(v), 0, 255)
	return out


static func _v(c: PackedByteArray, t: PackedStringArray, b := PackedByteArray(), cut := []) -> Array:
	return [c, t, b] if cut.is_empty() else [c, t, b, cut]


static func _blend_of(v: Array) -> PackedByteArray:
	return v[2] if v.size() > 2 else PackedByteArray()


# ------------------------------------------------------------------------------------------------ storage
func clear() -> void:
	finish_reading()
	for k in leaves.keys():
		_mark(k)
	for k in mats.keys():
		_mark(k)
	if change_log != null and not (leaves.is_empty() and mats.is_empty()):
		changed_all = true                               # (a list of changes can't say this: the whole object goes)
	leaves.clear()
	mats.clear()
	_index.clear()
	_render.clear()
	_mrender.clear()
	_occ.clear()
	_mocc.clear()
	_undo.clear()
	_redo.clear()
	revision += 1


func count() -> int:
	return leaves.size()


static func _index_key(k: Vector4i) -> Vector3i:
	return Vector3i(_fdiv(k.x, INDEX_TICKS), _fdiv(k.y, INDEX_TICKS), _fdiv(k.z, INDEX_TICKS))


static func render_key(k: Vector4i) -> Vector3i:
	if k.w <= FINE_MAX_P:
		return Vector3i(k.x >> _FINE_SHIFT, k.y >> _FINE_SHIFT, k.z >> _FINE_SHIFT)     # (shifts floor like _fdiv)
	return Vector3i(k.x >> _RENDER_SHIFT, (k.y >> _RENDER_SHIFT) + COARSE_TAG, k.z >> _RENDER_SHIFT)


## The middle of a render chunk, in ticks (for drawing the nearest chunks first).
static func chunk_center(ck: Vector3i) -> Vector3:
	if ck.y >= COARSE_TAG >> 1:
		return Vector3(ck.x, ck.y - COARSE_TAG, ck.z) * RENDER_TICKS + Vector3.ONE * (RENDER_TICKS * 0.5)
	return Vector3(ck) * FINE_TICKS + Vector3.ONE * (FINE_TICKS * 0.5)


## Mark every render chunk (of both sizes) that overlaps ticks lo..hi as needing a redraw. Only chunks that hold
## something can look different, so with a big box it's quicker to go through the chunks there are.
func _mark_box(lo: Vector3i, hi: Vector3i) -> void:
	for sh in [_FINE_SHIFT, _RENDER_SHIFT]:
		var tag := 0 if sh == _FINE_SHIFT else COARSE_TAG
		var a := Vector3i(lo.x >> sh, (lo.y >> sh) + tag, lo.z >> sh)
		var b := Vector3i(hi.x >> sh, (hi.y >> sh) + tag, hi.z >> sh)
		var n := (b.x - a.x + 1) * (b.y - a.y + 1) * (b.z - a.z + 1)
		if n > _render.size() + _mrender.size():
			for src in [_render, _mrender]:
				for ck in src:
					if ck.x >= a.x and ck.y >= a.y and ck.z >= a.z and ck.x <= b.x and ck.y <= b.y and ck.z <= b.z:
						dirty[ck] = true
			continue
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				for z in range(a.z, b.z + 1):
					var ck := Vector3i(x, y, z)
					if _render.has(ck) or _mrender.has(ck):
						dirty[ck] = true


const _MAT_TAG := 32                     ## undo records keep material cells apart from cubes by w + 32


func _put(k: Vector4i, v) -> void:
	if reading_task >= 0:
		finish_reading()
	if _edit != null and not (_edit as Dictionary).has(k):
		_edit[k] = leaves.get(k)
	if change_log != null:
		change_log[k] = true
	var ik := Vector3i(k.x >> _INDEX_SHIFT, k.y >> _INDEX_SHIFT, k.z >> _INDEX_SHIFT)       # (= _index_key: shifts floor like _fdiv)
	var rk := render_key(k)
	if v == null:
		if leaves.erase(k):
			_index[ik].erase(k)
			_render[rk].erase(k)
			_count_occ(k, -1)
	else:
		if not leaves.has(k):
			_count_occ(k, 1)
		leaves[k] = v
		if not _index.has(ik):
			_index[ik] = {}
		_index[ik][k] = true
		if not _render.has(rk):
			_render[rk] = {}
		_render[rk][k] = true
	_mark(k)
	revision += 1


func _count_occ(k: Vector4i, add: int, occ = null) -> void:
	var into: Dictionary = _occ if occ == null else occ
	for q in range(k.w + 1, MAX_P + 1):
		var sh := q + 3                                  # (size_of(q) = 1 << sh)
		var ck := Vector4i((k.x >> sh) << sh, (k.y >> sh) << sh, (k.z >> sh) << sh, q)
		var n: int = into.get(ck, 0) + add
		if n <= 0:
			into.erase(ck)
		else:
			into[ck] = n


## How many smaller cubes are inside this grid cell (instant: kept up to date as cubes change).
func cubes_in_cell(c: Vector3i, p: int) -> int:
	return _occ.get(Vector4i(c.x, c.y, c.z, p), 0)


## Is there anything in this grid cell - part of a cube, or a material? (Build mode aims at cells like this: a cell
## with something in it counts as a whole block, even where its faces have been pushed in.)
func cell_occupied(c: Vector3i, p: int) -> bool:
	if leaves.has(Vector4i(c.x, c.y, c.z, p)) or _occ.get(Vector4i(c.x, c.y, c.z, p), 0) > 0:
		return true
	var g := size_of(p)
	for q in range(p + 1, MAX_P + 1):                   # part of a bigger cube: is its solid in this cell?
		var s := size_of(q)
		var bk := Vector4i(floori(float(c.x) / s) * s, floori(float(c.y) / s) * s, floori(float(c.z) / s) * s, q)
		if leaves.has(bk):
			var bc: PackedByteArray = leaves[bk][0]
			if bc == FULL and _cut_of(leaves[bk]).is_empty():
				return true
			var planes := leaf_planes(leaves[bk])
			for i in 3:
				for j in 3:
					for kk in 3:
						var pt := (Vector3(c) + Vector3(0.1 + 0.4 * i, 0.1 + 0.4 * j, 0.1 + 0.4 * kk) * g - Vector3(bk.x, bk.y, bk.z)) / s * 8.0
						var ins := true
						for pl in planes:
							if (pl[0] as Vector3).dot(pt) - float(pl[1]) > 1e-4:
								ins = false
								break
						if ins:
							return true
			break
	if not mats.is_empty():
		# (a material this size, a smaller one inside, or a bigger one around it; mats_in scanned every material
		#  cell for every cell a build-mode aim walked through: thousands of times a frame on a map with lava)
		if mats.has(Vector4i(c.x, c.y, c.z, p)) or _mocc.get(Vector4i(c.x, c.y, c.z, p), 0) > 0 				or mat_at(Vector3(c) + Vector3.ONE * g * 0.5) != "":
			return true
	return false


## The biggest grid power q >= p whose cell around `c` (a cell of power p, ticks) is completely empty: no cube or
## material in it or around it. p - 1 when that can't be said cheaply (a bigger cube or material contains the cell:
## ask cell_occupied). Lets a look along the line of sight jump over empty space instead of crossing it cell by cell.
func empty_level(c: Vector3i, p: int) -> int:
	for q in range(p, MAX_P + 1):                       # inside a bigger cube or material: no jumping
		var s := size_of(q)
		var k := Vector4i(floori(float(c.x) / s) * s, floori(float(c.y) / s) * s, floori(float(c.z) / s) * s, q)
		if leaves.has(k) or mats.has(k):
			return p - 1
	var best := p - 1
	for q in range(p, MAX_P + 1):                       # (counts only grow going up: stop at the first that isn't 0)
		var s := size_of(q)
		var k := Vector4i(floori(float(c.x) / s) * s, floori(float(c.y) / s) * s, floori(float(c.z) / s) * s, q)
		if _occ.get(k, 0) > 0 or _mocc.get(k, 0) > 0:
			break
		best = q
	return best


func _put_mat(k: Vector4i, m) -> void:
	if reading_task >= 0:
		finish_reading()
	var tk := Vector4i(k.x, k.y, k.z, k.w + _MAT_TAG)
	if _edit != null and not (_edit as Dictionary).has(tk):
		_edit[tk] = mats.get(k)
	if change_log != null:
		change_log[tk] = true
	var rk := render_key(k)
	if m == null:
		if mats.erase(k):
			_mrender[rk].erase(k)
			_count_occ(k, -1, _mocc)
	else:
		if not mats.has(k):
			_count_occ(k, 1, _mocc)
		mats[k] = m
		if not _mrender.has(rk):
			_mrender[rk] = {}
		_mrender[rk][k] = true
	_mark(k)
	revision += 1


## Many cubes changing at once (a big wheel edit): note only the box they're in, and mark the render chunks once at
## the end (_bulk_end) instead of per cube.
var _bulk = null                         ## [lo Vector3i, hi Vector3i] ticks, while a bulk edit runs


func _bulk_begin() -> void:
	if _bulk == null:
		_bulk = []


func _bulk_end() -> void:
	var b = _bulk
	_bulk = null
	if b == null or b.is_empty():
		return
	var lo: Vector3i = b[0] - Vector3i.ONE
	var hi: Vector3i = b[1] + Vector3i.ONE
	_mark_box(lo, hi)
	for k in leaves_in(lo, hi - lo + Vector3i.ONE):     # big neighbors that start in another chunk
		dirty[render_key(k)] = true


func _mark(k: Vector4i) -> void:
	var s := size_of(k.w)
	if _bulk != null:
		var klo := Vector3i(k.x, k.y, k.z)
		var khi := klo + Vector3i(s - 1, s - 1, s - 1)
		if _bulk.is_empty():
			_bulk.append_array([klo, khi])
		else:
			_bulk[0] = (_bulk[0] as Vector3i).min(klo)
			_bulk[1] = (_bulk[1] as Vector3i).max(khi)
		return
	var lo := Vector3i(k.x - 1, k.y - 1, k.z - 1)
	var hi := Vector3i(k.x + s, k.y + s, k.z + s)
	_mark_box(lo, hi)
	for o in 6:
		var nk = leaf_at(_beyond(k, o))
		if nk != null:
			dirty[render_key(nk)] = true


static func _beyond(k: Vector4i, o: int) -> Vector3:
	var s := float(size_of(k.w))
	var p := Vector3(k.x + s * 0.5, k.y + s * 0.5, k.z + s * 0.5)
	var d := o >> 1
	p[d] = (k[d] + s + 0.5) if o & 1 else (k[d] - 0.5)
	return p


func leaf_at(pt: Vector3):
	return _leaf_at_from(pt, MIN_P)


## The cube at a point (ticks) of size p_min or bigger, or null.
func _leaf_at_from(pt: Vector3, p_min: int):
	for p in range(p_min, MAX_P + 1):
		var s := size_of(p)
		var k := Vector4i(floori(pt.x / s) * s, floori(pt.y / s) * s, floori(pt.z / s) * s, p)
		if leaves.has(k):
			return k
	return null


## The material at a point (ticks): "" for none.
func mat_at(pt: Vector3) -> String:
	if mats.is_empty():
		return ""
	for p in range(MIN_P, MAX_P + 1):
		var s := size_of(p)
		var k := Vector4i(floori(pt.x / s) * s, floori(pt.y / s) * s, floori(pt.z / s) * s, p)
		if mats.has(k):
			return mats[k]
	return ""


## Every cube overlapping the box o .. o + size (ticks). Walks the octree, so only cells that hold something are
## visited (scanning the 64 m index cell was millions of checks when clearing a few cells of a big shape).
func leaves_in(o: Vector3i, size: Vector3i) -> Array:
	var out := []
	var hi := o + size
	var top := size_of(MAX_P)
	for x in range(_fdiv(o.x, top), _fdiv(hi.x - 1, top) + 1):
		for y in range(_fdiv(o.y, top), _fdiv(hi.y - 1, top) + 1):
			for z in range(_fdiv(o.z, top), _fdiv(hi.z - 1, top) + 1):
				_leaves_walk(Vector3i(x, y, z) * top, MAX_P, o, hi, out)
	return out


func _leaves_walk(co: Vector3i, q: int, lo: Vector3i, hi: Vector3i, out: Array) -> void:
	var k := Vector4i(co.x, co.y, co.z, q)
	if leaves.has(k):
		out.append(k)
		return
	if q <= MIN_P or _occ.get(k, 0) == 0:
		return
	var cs := size_of(q - 1)
	for i in 8:
		var c := co + Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1) * cs
		if c.x < hi.x and c.x + cs > lo.x and c.y < hi.y and c.y + cs > lo.y and c.z < hi.z and c.z + cs > lo.z:
			_leaves_walk(c, q - 1, lo, hi, out)


## Every material cell overlapping the box o .. o + size (ticks). Walks the octree like leaves_in (scanning every
## material cell for each filled cell made a big fill quadratic: minutes for a 32,000-cell glass fill).
func mats_in(o: Vector3i, size: Vector3i) -> Array:
	var out := []
	if mats.is_empty():
		return out
	var hi := o + size
	var top := size_of(MAX_P)
	for x in range(_fdiv(o.x, top), _fdiv(hi.x - 1, top) + 1):
		for y in range(_fdiv(o.y, top), _fdiv(hi.y - 1, top) + 1):
			for z in range(_fdiv(o.z, top), _fdiv(hi.z - 1, top) + 1):
				_mats_walk(Vector3i(x, y, z) * top, MAX_P, o, hi, out)
	return out


func _mats_walk(co: Vector3i, q: int, lo: Vector3i, hi: Vector3i, out: Array) -> void:
	var k := Vector4i(co.x, co.y, co.z, q)
	if mats.has(k):
		out.append(k)
		return
	if q <= MIN_P or _mocc.get(k, 0) == 0:
		return
	var cs := size_of(q - 1)
	for i in 8:
		var c := co + Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1) * cs
		if c.x < hi.x and c.x + cs > lo.x and c.y < hi.y and c.y + cs > lo.y and c.z < hi.z and c.z + cs > lo.z:
			_mats_walk(c, q - 1, lo, hi, out)


func _split(k: Vector4i) -> void:
	var v: Array = leaves[k]
	var cs := size_of(k.w - 1)
	_put(k, null)
	for o in 8:
		var cv := split_child(v, o)
		if cv.is_empty():
			continue
		_put(Vector4i(k.x + (o & 1) * cs, k.y + ((o >> 1) & 1) * cs, k.z + ((o >> 2) & 1) * cs, k.w - 1), cv)


func _prepare(o: Vector3i, p: int) -> void:
	var guard := 0
	while guard < 16:
		guard += 1
		var found = null
		for q in range(p + 1, MAX_P + 1):
			var s := size_of(q)
			var k := Vector4i(floori(float(o.x) / s) * s, floori(float(o.y) / s) * s, floori(float(o.z) / s) * s, q)
			if leaves.has(k):
				found = k
				break
		if found == null:
			return
		_split(found)


func _prepare_mat(o: Vector3i, p: int) -> void:
	var guard := 0
	while guard < 16:
		guard += 1
		var found = null
		for q in range(p + 1, MAX_P + 1):
			var s := size_of(q)
			var k := Vector4i(floori(float(o.x) / s) * s, floori(float(o.y) / s) * s, floori(float(o.z) / s) * s, q)
			if mats.has(k):
				found = k
				break
		if found == null:
			return
		var m: String = mats[found]
		_put_mat(found, null)
		var cs := size_of(found.w - 1)
		for i in 8:
			_put_mat(Vector4i(found.x + (i & 1) * cs, found.y + ((i >> 1) & 1) * cs, found.z + ((i >> 2) & 1) * cs, found.w - 1), m)


func cell_state(o: Vector3i, p: int) -> Array:
	var k := Vector4i(o.x, o.y, o.z, p)
	if leaves.has(k):
		return [k]
	_prepare(o, p)
	if leaves.has(k):
		return [k]
	return ["mixed"] if _occ.get(k, 0) > 0 else []        # (_occ counts the smaller cubes in it: no index scan)


func _clear_cell(o: Vector3i, p: int) -> void:
	_prepare(o, p)
	var k := Vector4i(o.x, o.y, o.z, p)
	if leaves.has(k):
		_put(k, null)
	if _occ.get(k, 0) == 0:
		return
	var s := size_of(p)
	for lk in leaves_in(o, Vector3i(s, s, s)):
		_put(lk, null)


func set_cell(o: Vector3i, p: int, corners: PackedByteArray, tex: PackedStringArray, blend := PackedByteArray(), cut := []) -> void:
	_clear_cell(o, p)
	_put(Vector4i(o.x, o.y, o.z, p), _v(corners, tex, blend, cut))


## _merge_up for many cells of size p at once: each parent is looked at once per level, not once per cell.
func _merge_up_many(cells: Array, p: int) -> void:
	var cur := {}
	for o in cells:
		cur[o] = true
	while p < MAX_P and not cur.is_empty():
		var ps := size_of(p + 1)
		var cs := size_of(p)
		var parents := {}
		for o in cur:
			parents[Vector3i(floori(float(o.x) / ps) * ps, floori(float(o.y) / ps) * ps, floori(float(o.z) / ps) * ps)] = true
		var nxt := {}
		for po in parents:
			var tex = null
			var ok := true
			for i in 8:
				var v = leaves.get(Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p))
				if v == null or v[0] != FULL or not _cut_of(v).is_empty() or not _blend_of(v).is_empty() or (tex != null and v[1] != tex):
					ok = false
					break
				tex = v[1]
			if not ok:
				continue
			for i in 8:
				_put(Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p), null)
			_put(Vector4i(po.x, po.y, po.z, p + 1), _v(FULL, tex))
			nxt[po] = true
		cur = nxt
		p += 1


func _merge_up(o: Vector3i, p: int) -> void:
	while p < MAX_P:
		var ps := size_of(p + 1)
		var po := Vector3i(floori(float(o.x) / ps) * ps, floori(float(o.y) / ps) * ps, floori(float(o.z) / ps) * ps)
		var cs := size_of(p)
		var tex = null
		for i in 8:
			var k := Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p)
			var v = leaves.get(k)
			if v == null or v[0] != FULL or not _cut_of(v).is_empty() or not _blend_of(v).is_empty() or (tex != null and v[1] != tex):
				return
			tex = v[1]
		for i in 8:
			_put(Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p), null)
		_put(Vector4i(po.x, po.y, po.z, p + 1), _v(FULL, tex))
		o = po
		p += 1


# ------------------------------------------------------------------------------------------------ undo
func begin() -> void:
	_edit = {}


func commit() -> bool:
	var before: Dictionary = _edit
	_edit = null
	var changed := false
	var after := {}
	for k in before:
		after[k] = mats.get(Vector4i(k.x, k.y, k.z, k.w - _MAT_TAG)) if k.w >= _MAT_TAG - 8 else leaves.get(k)
		if after[k] != before[k]:
			changed = true
	if not changed:
		return false
	_undo.append([before, after])
	if _undo.size() > 200:
		_undo.pop_front()
	_redo.clear()
	return true


func undo() -> bool:
	if _undo.is_empty():
		return false
	var step: Array = _undo.pop_back()
	_apply(step[0])
	_redo.append(step)
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var step: Array = _redo.pop_back()
	_apply(step[1])
	_undo.append(step)
	return true


func _apply(state: Dictionary) -> void:
	for k in state:
		if k.w >= _MAT_TAG - 8:
			_put_mat(Vector4i(k.x, k.y, k.z, k.w - _MAT_TAG), state[k])
		else:
			_put(k, state[k])


# ------------------------------------------------------------------------------------------------ selections
## A selection is a box of cells: {o: Vector3i ticks (a multiple of the cell size), s: Vector3i cells, p: grid power,
## orient: the face direction it was made on}. Face edits work on the box's outer layer on that side.
static func make_sel(o: Vector3i, p: int, orient: int, s := Vector3i.ONE) -> Dictionary:
	return {"o": o, "s": s, "p": p, "orient": orient}


static func face_layer(sel: Dictionary, shift := 0) -> Array:
	var o: int = sel["orient"]
	var d := o >> 1
	var g := size_of(sel["p"])
	var s: Vector3i = sel["s"]
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var out := []
	var layer: int = (s[d] - 1 + shift) if o & 1 else -shift
	for i in s[a]:
		for j in s[b]:
			var c := Vector3i.ZERO
			c[d] = layer
			c[a] = i
			c[b] = j
			out.append((sel["o"] as Vector3i) + c * g)
	return out


static func box_cells(sel: Dictionary) -> Array:
	var g := size_of(sel["p"])
	var s: Vector3i = sel["s"]
	var out := []
	for x in s.x:
		for y in s.y:
			for z in s.z:
				out.append((sel["o"] as Vector3i) + Vector3i(x, y, z) * g)
	return out


static func moved(sel: Dictionary, cells: int) -> Dictionary:
	var out := sel.duplicate()
	out["o"] = (sel["o"] as Vector3i) + orient_step(sel["orient"]) * size_of(sel["p"]) * cells
	return out


func _tex_from(behind: Vector3i, p: int, fallback: String) -> PackedStringArray:
	var s := float(size_of(p))
	var k = leaf_at(Vector3(behind) + Vector3.ONE * s * 0.5)
	return (leaves[k][1] as PackedStringArray).duplicate() if k != null else blank_tex(fallback)


# ------------------------------------------------------------------------------------------------ geometry edits
## Mouse wheel: pull new cubes out of the selected faces (the selection follows them out).
func pull(sel: Dictionary, tex := "") -> Dictionary:
	var p: int = sel["p"]
	var front := moved(sel, 1)
	var new_cells := face_layer(front)
	var g := size_of(p)
	var lo: Vector3i = new_cells[0]
	var hi: Vector3i = new_cells[0]
	for c in new_cells:
		lo = lo.min(c)
		hi = hi.max(c)
	var empty := leaves_in(lo, hi - lo + Vector3i(g, g, g)).is_empty()   # nothing there yet: no cells to clear
	var texs := {}                                       # the cube behind -> its textures (they're shared, not copied)
	_bulk_begin()
	for c in face_layer(sel):
		var f: Vector3i = c + orient_step(sel["orient"]) * g
		var bk = leaf_at(Vector3(c) + Vector3.ONE * g * 0.5)
		if not texs.has(bk):
			texs[bk] = (leaves[bk][1] as PackedStringArray).duplicate() if bk != null else blank_tex(tex)
		if empty:
			_put(Vector4i(f.x, f.y, f.z, p), _v(FULL, texs[bk]))
		else:
			set_cell(f, p, FULL, texs[bk])
	_merge_up_many(new_cells, p)
	_bulk_end()
	return front


## Several wheel notches at once (build mode gathers the notches of one frame): pull n layers out in one go. The
## new block is laid down as the biggest aligned cubes that fit (each with the texture of the cubes behind it), so
## pulling 8 layers of 0.125 m cubes out of an 8 m face makes 64 1 m cubes, not 32768 small ones.
func pull_n(sel: Dictionary, n: int, tex := "") -> Dictionary:
	if n <= 1:
		return pull(sel, tex)
	var p: int = sel["p"]
	var g := size_of(p)
	var o: int = sel["orient"]
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var step := orient_step(o) * g
	var colbk := {}                                      # column (a, b ticks) -> the cube behind it
	var texs := {}
	var uniform := true
	var first_bk = null
	var lo := Vector3i.MAX
	var hi := Vector3i.MIN
	for c in face_layer(sel):
		var bk = leaf_at(Vector3(c) + Vector3.ONE * g * 0.5)
		if not texs.has(bk):
			texs[bk] = (leaves[bk][1] as PackedStringArray).duplicate() if bk != null else blank_tex(tex)
		if colbk.is_empty():
			first_bk = bk
		elif bk != first_bk:
			uniform = false
		colbk[Vector2i(c[a], c[b])] = bk
		for i in [1, n]:
			lo = lo.min(c + step * i)
			hi = hi.max(c + step * i)
	hi += Vector3i(g, g, g)                              # (exclusive)
	var cubes := []
	_box_decompose(lo, hi, p, cubes, func(co: Vector3i, sz: int) -> bool:
		if uniform:
			return true
		var want = colbk[Vector2i(co[a], co[b])]
		for i in range(co[a], co[a] + sz, g):
			for j in range(co[b], co[b] + sz, g):
				if colbk[Vector2i(i, j)] != want:
					return false
		return true)
	var empty := leaves_in(lo, hi - lo).is_empty()
	var by_level := {}
	_bulk_begin()
	for cq in cubes:
		var co: Vector3i = cq[0]
		var q: int = cq[1]
		var t: PackedStringArray = texs[colbk[Vector2i(co[a], co[b])]]
		if empty:
			_put(Vector4i(co.x, co.y, co.z, q), _v(FULL, t))
		else:
			set_cell(co, q, FULL, t)
		if not by_level.has(q):
			by_level[q] = []
		by_level[q].append(co)
	var levels := by_level.keys()
	levels.sort()
	for q in levels:
		_merge_up_many(by_level[q], q)
	_bulk_end()
	return moved(sel, n)


## Several wheel notches the other way at once: push n layers of the selection away (the selection follows them in).
func push_n(sel: Dictionary, n: int) -> Dictionary:
	if n <= 1:
		return push(sel)
	var p: int = sel["p"]
	var g := size_of(p)
	var lo := Vector3i.MAX
	var hi := Vector3i.MIN
	for c in face_layer(sel) + face_layer(moved(sel, -(n - 1))):
		lo = lo.min(c)
		hi = hi.max(c)
	hi += Vector3i(g, g, g)
	var cubes := []
	_box_decompose(lo, hi, p, cubes, func(_co: Vector3i, _sz: int) -> bool: return true)
	_bulk_begin()
	for cq in cubes:
		_clear_cell(cq[0], cq[1])
	_bulk_end()
	return moved(sel, -n)


## The box lo..hi (ticks, exclusive, on the size-p grid) as the biggest aligned cubes that fit: [[origin, size p], ...].
## `ok(origin, size ticks)` can refuse a cube that fits (it's split further, down to size p).
func _box_decompose(lo: Vector3i, hi: Vector3i, p: int, out: Array, ok: Callable) -> void:
	var top := size_of(MAX_P)
	for x in range(_fdiv(lo.x, top), _fdiv(hi.x - 1, top) + 1):
		for y in range(_fdiv(lo.y, top), _fdiv(hi.y - 1, top) + 1):
			for z in range(_fdiv(lo.z, top), _fdiv(hi.z - 1, top) + 1):
				_box_part(Vector3i(x, y, z) * top, MAX_P, lo, hi, p, out, ok)


func _box_part(co: Vector3i, q: int, lo: Vector3i, hi: Vector3i, p: int, out: Array, ok: Callable) -> void:
	var sz := size_of(q)
	var inside := co.x >= lo.x and co.y >= lo.y and co.z >= lo.z and co.x + sz <= hi.x and co.y + sz <= hi.y 		and co.z + sz <= hi.z
	if inside and (q == p or ok.call(co, sz)):
		out.append([co, q])
		return
	if q == p:
		return
	var cs := size_of(q - 1)
	for i in 8:
		var c := co + Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1) * cs
		if c.x < hi.x and c.x + cs > lo.x and c.y < hi.y and c.y + cs > lo.y and c.z < hi.z and c.z + cs > lo.z:
			_box_part(c, q - 1, lo, hi, p, out, ok)


## Mouse wheel the other way: push the selected layer of cubes out of existence (the selection follows it in).
func push(sel: Dictionary) -> Dictionary:
	_bulk_begin()
	for c in face_layer(sel):
		_clear_cell(c, sel["p"])
	_bulk_end()
	return moved(sel, -1)


## F + wheel: move the selected faces in (dir 1) or out (dir -1) by 1/8 of a cube. Q + wheel: only one corner
## (`only_corner`, 0-3 around the face). Pulling corners already at their cube's side starts a thin new cube in front.
func push_face(sel: Dictionary, dir: int, only_corner := -1) -> Dictionary:
	var o: int = sel["orient"]
	var quad: Array = face_corners(o)
	return _push_corners(sel, dir, func(_cell: Vector3i, n: int) -> bool: return only_corner < 0 or n == quad[only_corner])


## Wheel with corners selected (middle mouse drag): reshape just the selected corners of the cubes already in the
## selection - it only ever shapes, never adds: no new cubes, nothing grows past a cube's own side, empty spots stay
## empty. Corners are picked on a half-size grid over the face (Sauerbraten's corner selection): each cube's face is 4
## squares, one per corner; `quads` = [a0, a1, b0, b1] are the selected squares, counted in half cells along the face's
## two axes. In each column of the box the outermost cube there (on the face's side) is the one shaped, so cubes at
## different heights are both reached.
func push_corner_quads(sel: Dictionary, quads: Array, dir: int) -> Dictionary:
	push_note = ""
	var o: int = sel["orient"]
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var p: int = sel["p"]
	var g := size_of(p)
	var s: Vector3i = sel["s"]
	for i in s[a]:
		for j in s[b]:
			for depth in s[d]:
				var c := Vector3i.ZERO
				c[a] = i
				c[b] = j
				c[d] = (s[d] - 1 - depth) if o & 1 else depth   # from the face's side inwards
				var cell: Vector3i = (sel["o"] as Vector3i) + c * g
				var st := cell_state(cell, p)
				if st.is_empty():
					continue
				_shape_cell(cell, p, o, dir, func(_c: Vector3i, n: int) -> bool:
					var qa: int = cell[a] * 2 / g + ((n >> a) & 1)
					var qb: int = cell[b] * 2 / g + ((n >> b) & 1)
					return qa >= quads[0] and qa <= quads[1] and qb >= quads[2] and qb <= quads[3])
				break                                        # only the outermost cube of the column
	return sel


## Set when the last push or pull changed nothing: a plain-language reason (build mode shows it). Empty otherwise.
var push_note := ""


func _push_corners(sel: Dictionary, dir: int, pick: Callable) -> Dictionary:
	push_note = ""
	var o: int = sel["orient"]
	var p: int = sel["p"]
	var d := o >> 1
	var cells := face_layer(sel)
	var side := 8 if o & 1 else 0
	if dir < 0:
		var all_out := true
		var any_cube := false
		for c in cells:
			var st := cell_state(c, p)
			if st.is_empty():
				continue
			if not st[0] is Vector4i:
				all_out = false
				break
			any_cube = true
			var cc: PackedByteArray = leaves[st[0]][0]
			for n in face_corners(o):
				if pick.call(c, n) and cc[n * 3 + d] != side:
					all_out = false
			if not all_out:
				break
		if all_out and any_cube:
			var front := moved(sel, 1)
			for c in cells:
				var f: Vector3i = c + orient_step(o) * size_of(p)
				if not cell_state(f, p).is_empty() or cell_state(c, p).is_empty():
					continue
				var nc := FULL.duplicate()                  # a flat cube on the near side, then out by one step
				for n in face_corners(o):
					nc[n * 3 + d] = 0 if o & 1 else 8
				var any := false
				for n in face_corners(o):
					if pick.call(c, n):
						_nudge(nc, o, n, -1)
						any = true
				if any and not is_empty_shape(nc) and is_valid_shape(nc):
					set_cell(f, p, nc, _tex_from(c, p, ""))
			return front
	var moved := 0
	for c in cells:
		moved += _shape_cell(c, p, o, dir, pick)
	if moved > 0:
		push_note = ""
	return sel


## Shape one cell's cubes on face `o` by one step (dir 1 in, -1 out). A cell holding one cube shapes that cube; a cell
## made of smaller cubes shapes the cubes that are actually out on this face, so a shape at one power doesn't stop the
## push at another. Returns how many cubes changed.
func _shape_cell(cell: Vector3i, p: int, o: int, dir: int, pick: Callable) -> int:
	var st := cell_state(cell, p)
	if st.is_empty():
		return 0
	if st[0] is Vector4i:
		return 1 if _shape_leaf(st[0], o, dir, pick, cell) else 0
	var d := o >> 1
	var side := 8 if o & 1 else 0
	var s := size_of(p)
	var did := 0
	for k in leaves_in(cell, Vector3i(s, s, s)):
		var c: PackedByteArray = leaves[k][0]
		var outer := false
		for n in face_corners(o):
			if c[n * 3 + d] == side and pick.call(cell, n):
				outer = true
				break
		if outer and _shape_leaf(k, o, dir, pick, cell):
			did += 1
	return did


## One cube, one step. Never loses a shape: a push that would fold the cube into itself keeps the cube as it was and
## sets `push_note` instead of leaving a half-applied cell. And a folded face always has a way back: a pull that can't
## step back (the corners would cross, or the shape refuses the step) unfolds the picked corners to the cube's own
## side, so the 45 degree limit is a limit and not a dead end.
func _shape_leaf(k: Vector4i, o: int, dir: int, pick: Callable, cell: Vector3i) -> bool:
	var d := o >> 1
	var side := 8 if o & 1 else 0
	var v: Array = leaves[k]
	var nc: PackedByteArray = (v[0] as PackedByteArray).duplicate()
	var picked := []
	for n in face_corners(o):
		if pick.call(cell, n):
			picked.append(n)
			_nudge(nc, o, n, dir)
	if picked.is_empty():
		return false
	if dir < 0 and (nc == v[0] or not is_valid_shape(nc)):
		for n in picked:
			nc[n * 3 + d] = side                      # (unfold: back to the cube's own side)
	if nc == v[0]:
		if dir > 0:
			push_note = "can't go further here - this face is already folded as far as it goes"
		return false
	if is_empty_shape(nc):
		_put(k, null)
		return true
	if is_valid_shape(nc):
		_put(k, _v(nc, v[1], _blend_of(v)))
		return true
	push_note = ("can't go further here - the cube would fold into itself" if dir > 0
		else "can't pull back from here - this part is already as full as it gets")
	return false


func delete(sel: Dictionary) -> void:
	for c in box_cells(sel):
		_clear_cell(c, sel["p"])


# ------------------------------------------------------------------------------------------------ textures
## Y + wheel / F2: give the selected faces a texture (every face of the selected cubes when `all_faces`). Keeps each
## face's texture settings.
func set_texture(sel: Dictionary, id: String, all_faces := false) -> void:
	_edit_slots(sel, all_faces, func(slot: String) -> String: return with_id(slot, id))


## Change texture settings of the selected faces: `fn` gets the slot dictionary and returns it changed.
func set_slot_param(sel: Dictionary, all_faces: bool, fn: Callable) -> void:
	_edit_slots(sel, all_faces, func(slot: String) -> String: return make_slot(fn.call(parse_slot(slot).duplicate())))


func _edit_slots(sel: Dictionary, all_faces: bool, fn: Callable) -> void:
	var p: int = sel["p"]
	var g := size_of(p)
	for c in box_cells(sel):
		_prepare(c, p)
	for k in leaves_in(sel["o"], (sel["s"] as Vector3i) * g):
		var v: Array = leaves[k]
		var t: PackedStringArray = (v[1] as PackedStringArray).duplicate()
		for o in 6:
			if all_faces or o == sel["orient"]:
				t[o] = fn.call(t[o])
		if t != v[1]:
			_put(k, _v(v[0], t, _blend_of(v), _cut_of(v)))


## F3's Center / Fit: place the texture on the selected faces so its middle is in the middle of the selection (Hammer's
## "justify center"); `fit` also sizes it so one repeat spans the selection's longer side. Works out the shift through
## slot_uv itself, so turned and flipped textures land right too. Only the faces the selection is on change.
func place_texture(sel: Dictionary, fit: bool) -> void:
	var o: int = sel["orient"]
	var d := o >> 1
	var g := metres(sel["p"])
	var lo := Vector3(sel["o"]) * TICK
	var hi := lo + Vector3(sel["s"]) * g
	var n := Vector3(orient_step(o))
	var c := (lo + hi) * 0.5
	c[d] = hi[d] if o & 1 else lo[d]
	var span := 0.0
	for i in 3:
		if i != d:
			span = maxf(span, hi[i] - lo[i])
	set_slot_param(sel, false, func(sl: Dictionary) -> Dictionary:
		if fit and sl["id"] != "":
			sl["s"] = maxf(span / maxf(MaterialLibrary.world_size(sl["id"]) if MaterialLibrary.has(sl["id"]) else BlockShape.UV_METRES, 0.001), 0.01)
		sl["u"] = 0.0
		sl["v"] = 0.0
		var at := slot_uv(c, n, sl)                      # where the selection's middle falls in the texture
		sl["u"] = snappedf(fposmod(0.5 - at.x, 1.0), 0.0001)
		sl["v"] = snappedf(fposmod(0.5 - at.y, 1.0), 0.0001)
		return sl)


## The texture slot of the face a selection is on (the first cube in it), or "".
func slot_at(sel: Dictionary) -> String:
	var g := size_of(sel["p"])
	for c in face_layer(sel):
		var k = leaf_at(Vector3(c) + Vector3.ONE * g * 0.5)
		if k != null:
			return leaves[k][1][sel["orient"]]
	return ""


## Sauerbraten's replace / replacesel: every face with texture `old` gets `new` (in the box, or everywhere).
func replace_texture(old: String, new: String, sel := {}) -> int:
	var keys: Array = leaves.keys() if sel.is_empty() else leaves_in(sel["o"], (sel["s"] as Vector3i) * size_of(sel["p"]))
	var n := 0
	for k in keys:
		var v: Array = leaves[k]
		var t: PackedStringArray = (v[1] as PackedStringArray).duplicate()
		for o in 6:
			if slot_id(t[o]) == old:
				t[o] = with_id(t[o], new)
				n += 1
		if t != v[1]:
			_put(k, _v(v[0], t, _blend_of(v), _cut_of(v)))
	return n


## Blend painting (Sauerbraten's blendpaintmode, keypad 1-5): paint how much of each face's blend layer shows, with a
## round brush of `radius` ticks around `pt` (ticks). Modes: 1 set, 2 paint the layer in, 3 paint it out,
## 4 / 5 the same two inverted (strongest at the brush edge).
func paint_blend(pt: Vector3, radius: float, mode: int) -> int:
	var r := maxf(radius, 1.0)
	var lo := Vector3i((pt - Vector3.ONE * r).floor())
	var hi := Vector3i((pt + Vector3.ONE * r).ceil())
	var changed := 0
	for k in leaves_in(lo, hi - lo + Vector3i.ONE):
		var v: Array = leaves[k]
		var s := float(size_of(k.w))
		var bl: PackedByteArray = _blend_of(v).duplicate()
		if bl.is_empty():
			bl.resize(8)
			bl.fill(0)
		var before := bl.duplicate()
		for n in 8:
			var cp := Vector3(k.x, k.y, k.z) + Vector3(n & 1, (n >> 1) & 1, (n >> 2) & 1) * s
			var dist := cp.distance_to(pt)
			if dist > r:
				continue
			var b := int(255.0 * clampf(1.0 - dist / r, 0.0, 1.0) * 1.5)
			b = mini(b, 255)
			var cur: int = bl[n]
			match mode:
				1: cur = b
				2: cur = maxi(cur, b)
				3: cur = mini(cur, 255 - b)
				4: cur = maxi(cur, 255 - b)
				5: cur = mini(cur, b)
			bl[n] = cur
		if bl != before:
			var all_zero := true
			for x in bl:
				all_zero = all_zero and x == 0
			_put(k, _v(v[0], v[1], PackedByteArray() if all_zero else bl, _cut_of(v)))
			changed += 1
	return changed


# ------------------------------------------------------------------------------------------------ materials
## Fill the selection's cells with a material ("air" takes it away), like Sauerbraten's editmat.
func set_material(sel: Dictionary, mat: String) -> void:
	var p: int = sel["p"]
	var s := size_of(p)
	var parents := {}
	for c in box_cells(sel):
		_prepare_mat(c, p)
		for k in mats_in(c, Vector3i(s, s, s)):
			_put_mat(k, null)
		if mat != "air" and mat != "":
			_put_mat(Vector4i(c.x, c.y, c.z, p), mat)
			if p < MAX_P:
				var ps := size_of(p + 1)
				parents[Vector4i(_fdiv(c.x, ps) * ps, _fdiv(c.y, ps) * ps, _fdiv(c.z, ps) * ps, p + 1)] = true
	_merge_mats(parents)


## A fill is one thing, not thousands of cells: wherever all 8 cells of a bigger cell hold the same material, they
## become that one bigger cell, all the way up (a 32 x 32 x 32 fill of small cells is a handful of big ones).
func _merge_mats(parents: Dictionary) -> void:
	while not parents.is_empty():
		var up := {}
		for pk in parents:
			var cs := size_of(pk.w - 1)
			var m = null
			var all_same := true
			for i in 8:
				var ck := Vector4i(pk.x + (i & 1) * cs, pk.y + ((i >> 1) & 1) * cs, pk.z + ((i >> 2) & 1) * cs, pk.w - 1)
				var here = mats.get(ck)
				if here == null or (m != null and here != m):
					all_same = false
					break
				m = here
			if not all_same:
				continue
			for i in 8:
				_put_mat(Vector4i(pk.x + (i & 1) * cs, pk.y + ((i >> 1) & 1) * cs, pk.z + ((i >> 2) & 1) * cs, pk.w - 1), null)
			_put_mat(pk, m)
			if pk.w < MAX_P:
				var ps := size_of(pk.w + 1)
				up[Vector4i(_fdiv(pk.x, ps) * ps, _fdiv(pk.y, ps) * ps, _fdiv(pk.z, ps) * ps, pk.w + 1)] = true
		parents = up


## Material cells as boxes in meters (this object's space): {material: [AABB, ...]}.
## The render chunks holding a material that's only drawn while show_mats is on (clip, death...).
func hidden_mat_chunks() -> Array:
	var out := []
	for ck in _mrender:
		for k in _mrender[ck]:
			if not mat_kind(mats[k]) in ["water", "lava", "glass"]:
				out.append(ck)
				break
	return out


func material_boxes() -> Dictionary:
	var out := {}
	for k in mats:
		var m: String = mat_kind(mats[k])               # (by kind: a pool's own look is only how it's drawn)
		if not out.has(m):
			out[m] = []
		out[m].append(AABB(Vector3(k.x, k.y, k.z) * TICK, Vector3.ONE * metres(k.w)))
	return out


## Is this cube inside a material cell of this kind (noclip, alpha)?
func cube_in_mat(k: Vector4i, m: String) -> bool:
	if mats.is_empty():
		return false
	var s := float(size_of(k.w))
	return mat_kind(mat_at(Vector3(k.x, k.y, k.z) + Vector3.ONE * s * 0.5)) == m


# ------------------------------------------------------------------------------------------------ heightmap
## Heightmap mode (Sauerbraten's hmapedit): treat the tops of the cubes as terrain and move its corner points with a
## brush centered on `center` (ticks, a corner point of the grid) - dir 1 lowers, -1 raises. `around_y` (ticks) is
## roughly where the surface is. Raising past a cube's top builds new cubes; lowering past its bottom digs them away.
func hmap_edit(center: Vector3i, around_y: int, p: int, brush: Array, dir: int, rough := false) -> void:
	_top_cache = {}                                      # column tops don't change until the columns are written
	_hmap_rough = rough
	_hmap_edit(center, around_y, p, brush, dir)
	_hmap_rough = false
	_top_cache = null


## The experimental heightmap mode (0.19.7): every corner's push is scaled by a noise value at that corner (0.1 to
## 1.9 times the brush), so the brush's shape doesn't repeat. The terrain stays joined because a heightmap is corner
## heights its columns share: whatever a corner's height, every face that meets there meets there.
var _hmap_rough := false
static var _rough_noise: FastNoiseLite


static func _rough_factor(pt: Vector2i, g: int) -> float:
	if _rough_noise == null:
		_rough_noise = FastNoiseLite.new()
		_rough_noise.seed = 1729
		_rough_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_rough_noise.fractal_octaves = 3
	_rough_noise.frequency = 0.45 / float(g)            # (a few grid cells per bump, whatever the grid size)
	return 1.0 + 0.9 * clampf(_rough_noise.get_noise_2d(float(pt.x), float(pt.y)) * 1.6, -1.0, 1.0)


var _top_cache = null                                    ## column -> top cube (or null) while a heightmap edit reads


func _hmap_edit(center: Vector3i, around_y: int, p: int, brush: Array, dir: int) -> void:
	var g := size_of(p)
	var step := g / 8
	var pts := {}                                        # Vector2i corner point (ticks) -> current height (ticks)
	var n := brush.size()
	var smooth := n == 0
	var reach := 2 if smooth else n / 2
	for i in range(-reach - 1, reach + 2):
		for j in range(-reach - 1, reach + 2):
			var pt := Vector2i(center.x + i * g, center.z + j * g)
			var h = _surface_height(pt, around_y, p)
			if h != null:
				pts[pt] = h
	var new_h := {}
	if smooth:
		for i in range(-reach, reach + 1):
			for j in range(-reach, reach + 1):
				var pt := Vector2i(center.x + i * g, center.z + j * g)
				if not pts.has(pt):
					continue
				var sum := 0.0
				var cnt := 0
				for di in [-1, 0, 1]:
					for dj in [-1, 0, 1]:
						var q := pt + Vector2i(di * g, dj * g)
						if pts.has(q):
							sum += pts[q]
							cnt += 1
				new_h[pt] = roundi(sum / cnt / step) * step
	else:
		for i in n:
			for j in n:
				var w: int = brush[i][j]
				if w == 0:
					continue
				var pt := Vector2i(center.x + (i - n / 2) * g, center.z + (j - n / 2) * g)
				if pts.has(pt):
					var wr := w if not _hmap_rough else maxi(roundi(float(w) * _rough_factor(pt, g)), 0)
					new_h[pt] = int(pts[pt]) - dir * wr * step
	if new_h.is_empty():
		return
	# Sauerbraten's ripple: no column's corners may cross into the next layer of cubes (except one corner, diagonally,
	# with the two beside it exactly on the boundary) - otherwise a cube built on top would have nothing under part of
	# it (the floating sheets). Raising pulls the low corners up to the layer; lowering pulls the high ones down; each
	# change ripples out to the columns sharing that corner.
	var heights := pts.duplicate()
	for pt in new_h:
		heights[pt] = new_h[pt]
	_hmap_ripple(heights, pts, new_h.keys(), around_y, p, dir < 0, reach + 16)
	_top_cache = null                                    # (writing changes the tops)
	new_h.clear()
	for pt in heights:
		if heights[pt] != pts[pt]:
			new_h[pt] = heights[pt]
	if new_h.is_empty():
		return
	# rewrite every column touching a moved point
	var cols := {}
	for pt in new_h:
		for di in [-1, 0]:
			for dj in [-1, 0]:
				cols[Vector2i(pt.x + di * g, pt.y + dj * g)] = true
	for col in cols:
		var hs := []
		var ok := true
		for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var pt: Vector2i = col + c * g
			if new_h.has(pt):
				hs.append(new_h[pt])
			elif pts.has(pt):
				hs.append(pts[pt])
			else:
				ok = false
		if ok:
			_write_column(col, hs, around_y, p)


## Sauerbraten's hmap ripple (pullhmap) on corner heights (ticks, Vector2i point -> int), starting from the columns
## around `changed`; `up` = raising (pull low corners up), else pull high corners down. Heights of points not yet in
## `h` are read as needed (and noted in `orig`); columns more than `limit` cells from the first point are left alone.
func _hmap_ripple(h: Dictionary, orig: Dictionary, changed: Array, around_y: int, p: int, up: bool, limit: int) -> void:
	var g := size_of(p)
	if changed.is_empty():
		return
	var origin: Vector2i = changed[0]
	var queue := []
	var queued := {}
	for pt in changed:
		for di in [-1, 0]:
			for dj in [-1, 0]:
				var col := Vector2i(pt.x + di * g, pt.y + dj * g)
				if not queued.has(col):
					queued[col] = true
					queue.append(col)
	var guard := 0
	while not queue.is_empty() and guard < 20000:
		guard += 1
		var col: Vector2i = queue.pop_front()
		queued.erase(col)
		if absi(col.x - origin.x) > limit * g or absi(col.y - origin.y) > limit * g:
			continue
		if _column_top(col, around_y, p) == null:
			continue                                     # not terrain: nothing to keep in shape
		var cp := [col, col + Vector2i(g, 0), col + Vector2i(0, g), col + Vector2i(g, g)]   # index = x + 2 z
		var o := []
		var ok := true
		for q in cp:
			if not h.has(q):
				var sh = _surface_height(q, around_y, p)
				if sh == null:
					ok = false
					break
				h[q] = sh
				orig[q] = sh                             # (read as it was)
			o.append(int(h[q]))
		if not ok:
			continue
		var before := o.duplicate()
		if up:
			var q := 0
			for i in 4:
				if o[i] > o[q]:
					q = i
			var par := floori(float(o[q] - g / 8) / g) * g   # the bottom of the layer the highest corner is in
			if o[q ^ 3] < par and not (o[q ^ 1] > par or o[q ^ 2] > par):
				o[q ^ 3] = maxi(o[q ^ 3], par - g)       # dual layer: the opposite corner may go one layer lower
				o[q ^ 1] = par
				o[q ^ 2] = par
			else:
				for i in 4:
					o[i] = maxi(o[i], par)
		else:
			var q := 0
			for i in 4:
				if o[i] < o[q]:
					q = i
			var par := floori(float(o[q]) / g) * g + g    # the top of the layer the lowest corner is in
			if o[q ^ 3] > par and not (o[q ^ 1] < par or o[q ^ 2] < par):
				o[q ^ 3] = mini(o[q ^ 3], par + g)
				o[q ^ 1] = par
				o[q ^ 2] = par
			else:
				for i in 4:
					o[i] = mini(o[i], par)
		if o == before:
			continue
		for i in 4:
			if o[i] == before[i]:
				continue
			h[cp[i]] = o[i]
			for di in [-1, 0]:                           # the columns sharing that corner need another look
				for dj in [-1, 0]:
					var nc := Vector2i(cp[i].x + di * g, cp[i].y + dj * g)
					if not queued.has(nc):
						queued[nc] = true
						queue.append(nc)


## The height (ticks) of the terrain at a corner point: the highest cube top touching it, near `around_y`.
func _surface_height(pt: Vector2i, around_y: int, p: int):
	var g := size_of(p)
	var best = null
	for di in [-1, 0]:
		for dj in [-1, 0]:
			var col := Vector2i(pt.x + di * g, pt.y + dj * g)
			var top = _column_top(col, around_y, p)
			if top == null:
				continue
			var h: int = _column_height(top, (-di) | ((-dj) << 2), p)
			best = h if best == null else maxi(best, h)
	return best


## A column's terrain height (ticks) at one of its corners (b = that corner's bottom corner index: x bit, z bit<<2),
## from its top cube k. A corner with no thickness there (folded away on a cube resting on a slope, or a sheet)
## isn't the surface: the cube under it is.
func _column_height(k: Vector4i, b: int, p: int) -> int:
	var g := size_of(p)
	var c: PackedByteArray = leaves[k][0]
	var t := b | 2
	var home_x := 8 if b & 1 else 0
	var flat: bool = c[t * 3 + 1] == c[b * 3 + 1] or c[t * 3] != home_x
	if flat:
		var below = leaves.get(Vector4i(k.x, k.y - g, k.z, k.w))
		if below != null and not ((below[0] as PackedByteArray)[t * 3 + 1] == (below[0] as PackedByteArray)[b * 3 + 1]):
			return k.y - g + int((below[0] as PackedByteArray)[t * 3 + 1]) * g / 8
		if c[t * 3] != home_x:
			return k.y
	return k.y + c[t * 3 + 1] * g / 8


## The topmost cube in a column near `around_y`, or null.
func _column_top(col: Vector2i, around_y: int, p: int):
	if _top_cache != null and _top_cache.has(col):
		return _top_cache[col]
	var top = _find_column_top(col, around_y, p)
	if _top_cache != null:
		_top_cache[col] = top
	return top


func _find_column_top(col: Vector2i, around_y: int, p: int):
	var g := size_of(p)
	var base := floori(float(around_y) / g) * g
	for i in range(12, -13, -1):
		var o := Vector3i(col.x, base + i * g, col.y)
		var st := cell_state(o, p)
		if st.size() == 1 and st[0] is Vector4i:
			return st[0]
	return null


## Give one column's terrain the corner heights `hs` (ticks; order (0,0) (1,0) (0,1) (1,1) in x, z). Only the
## heights of the top corners of the cubes that are there change - their sides (bevels, slopes) stay as they were;
## raising past the top cube builds new cubes on it, lowering past its bottom carries on into the cube below. Like
## Sauerbraten, every cube down to one layer under the surface is reshaped too, so the cubes under a raised part are
## whole again (a cube left part-empty by an earlier edit would leave air under the new ones).
func _write_column(col: Vector2i, hs: Array, around_y: int, p: int) -> void:
	var g := size_of(p)
	var top = _column_top(col, around_y, p)
	if top == null:
		return
	var k: Vector4i = top
	var tex: PackedStringArray = (leaves[k][1] as PackedStringArray).duplicate()
	var idx := [0, 1, 4, 5]                               # the bottom corner under each column corner (x, z bits)
	# raise: cubes on top of the top one, flat underneath, their tops at the new heights
	for y in range(k.y + g, ceili(float(hs.max()) / g) * g, g):
		var c := FULL.duplicate()
		var any := false
		for i in 4:
			var hl := clampi(roundi(float(hs[i] - y) * 8.0 / g), 0, 8)
			c[(idx[i] | 2) * 3 + 1] = hl
			any = any or hl > 0
		_fold_flat_corners(c)
		if any and not is_empty_shape(c) and is_valid_shape(c):
			set_cell(Vector3i(col.x, y, col.y), p, c, tex)
	# the top cube, then (while digging below it) the ones under it
	var cur = k
	while cur != null:
		var ck: Vector4i = cur
		var v: Array = leaves[ck]
		var c: PackedByteArray = (v[0] as PackedByteArray).duplicate()
		for i in 4:
			var b: int = idx[i]
			var home_x := 8 if b & 1 else 0                  # a corner folded away before comes back out first
			if c[b * 3] == 8 - home_x and c[(b | 2) * 3] == 8 - home_x:
				c[b * 3] = home_x
				c[(b | 2) * 3] = home_x
			var t: int = (b | 2) * 3 + 1
			var floor_y: int = c[b * 3 + 1]
			c[t] = clampi(roundi(float(hs[i] - ck.y) * 8.0 / g), floor_y, 8)
		_fold_flat_corners(c)
		if c != v[0]:
			if is_empty_shape(c):
				_put(ck, null)
			elif is_valid_shape(c):
				_put(ck, _v(c, v[1], _blend_of(v)))
		var st := cell_state(Vector3i(col.x, ck.y - g, col.y), p)
		var nxt = st[0] if st.size() == 1 and st[0] is Vector4i else null
		if ck.y < floori(float(hs.min()) / g) * g and (nxt == null or _top_whole(leaves[nxt][0])):
			break                                        # done: under the surface, and the rest below is whole
		cur = nxt


## Is a cube's top whole (all four top corners up at 8, none folded away)?
static func _top_whole(c: PackedByteArray) -> bool:
	for b in [0, 1, 4, 5]:
		var home_x := 8 if b & 1 else 0
		if c[(b | 2) * 3 + 1] != 8 or c[(b | 2) * 3] != home_x or c[b * 3] != home_x:
			return false
	return true


## Sauerbraten's pushside: a top corner with no height whose two neighbors have none either is moved across to the
## other side (along x), so the cube only covers the part of its cell where it has height (on a slope, the part
## where the cube below is full) - otherwise its flat bottom would hang over empty space.
static func _fold_flat_corners(c: PackedByteArray) -> void:
	var idx := [0, 1, 4, 5]
	var f := []
	for i in 4:
		f.append(int(c[(idx[i] | 2) * 3 + 1]) - int(c[idx[i] * 3 + 1]))
	var fold := []
	for i in 4:
		if f[i] <= 0 and f[i ^ 1] <= 0 and f[i ^ 2] <= 0 and f[i ^ 3] > 0:
			fold.append(i)
	for i in fold:                                       # (to the far side, whatever it was: folding twice is folding once)
		var b: int = idx[i]
		var far := 0 if b & 1 else 8
		c[b * 3] = far
		c[(b | 2) * 3] = far


# ------------------------------------------------------------------------------------------------ copy, rotate, flip
func _take(sel: Dictionary) -> Array:
	var p: int = sel["p"]
	var g := size_of(p)
	for c in box_cells(sel):
		_prepare(c, p)
	var out := []
	for k in leaves_in(sel["o"], (sel["s"] as Vector3i) * g):
		for piece in _split_to(k, leaves[k], p):
			var pk: Vector4i = piece[0]
			out.append([Vector4i(pk.x - sel["o"].x, pk.y - sel["o"].y, pk.z - sel["o"].z, pk.w), piece[1]])
	return out


func _take_mats(sel: Dictionary) -> Array:
	var p: int = sel["p"]
	var g := size_of(p)
	for c in box_cells(sel):
		_prepare_mat(c, p)
	var out := []
	for k in mats_in(sel["o"], (sel["s"] as Vector3i) * g):
		out.append([Vector4i(k.x - sel["o"].x, k.y - sel["o"].y, k.z - sel["o"].z, k.w), mats[k]])
	return out


static func _split_to(k: Vector4i, v: Array, max_p: int) -> Array:
	if k.w <= max_p:
		return [[k, v]]
	var out := []
	var cs := size_of(k.w - 1)
	for o in 8:
		var cv := split_child(v, o)
		if cv.is_empty():
			continue
		out.append_array(_split_to(Vector4i(k.x + (o & 1) * cs, k.y + ((o >> 1) & 1) * cs, k.z + ((o >> 2) & 1) * cs, k.w - 1),
			cv, max_p))
	return out


func copy(sel: Dictionary) -> Dictionary:
	return {"s": (sel["s"] as Vector3i) * size_of(sel["p"]), "p": sel["p"], "cubes": _take(sel), "mats": _take_mats(sel)}


func paste(sel: Dictionary, clip: Dictionary) -> Dictionary:
	if clip.is_empty():
		return sel
	var o: Vector3i = sel["o"]
	var g0 := size_of(sel["p"])
	var cs0: Vector3i = clip["s"]
	for c in box_cells(make_sel(o, sel["p"], 3, Vector3i(maxi(cs0.x / g0, 1), maxi(cs0.y / g0, 1), maxi(cs0.z / g0, 1)))):
		_clear_cell(c, sel["p"])                         # (the copy's air is air here too, as in Sauerbraten: what was
	for item in clip["cubes"]:                           #  there doesn't show through its holes)
		for piece in _split_to(item[0], item[1], sel["p"]):
			var k: Vector4i = piece[0]
			set_cell(Vector3i(k.x, k.y, k.z) + o, k.w, piece[1][0], piece[1][1], _blend_of(piece[1]), _cut_of(piece[1]))
	for item in clip.get("mats", []):
		var k: Vector4i = item[0]
		set_material(make_sel(Vector3i(k.x, k.y, k.z) + o, k.w, 3), item[1])
	var g := size_of(sel["p"])
	var cs: Vector3i = clip["s"]
	return make_sel(o, sel["p"], sel["orient"], Vector3i(maxi(cs.x / g, 1), maxi(cs.y / g, 1), maxi(cs.z / g, 1)))


func rotate(sel: Dictionary, steps: int) -> Dictionary:
	var out := sel
	for i in posmod(steps, 4):
		out = _rotate_once(out)
	return out


func _rotate_once(sel: Dictionary) -> Dictionary:
	var d: int = sel["orient"] >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var g := size_of(sel["p"])
	var ext: Vector3i = (sel["s"] as Vector3i) * g
	var items := _take(sel)
	var mitems := _take_mats(sel)
	delete(sel)
	set_material(sel, "air")
	var o: Vector3i = sel["o"]
	for it in items:
		var k: Vector4i = it[0]
		var s := size_of(k.w)
		var nk := k
		nk[a] = ext[b] - (k[b] + s)                      # (u, v) -> (H - v, u): a quarter turn, a -> b
		nk[b] = k[a]
		var c: PackedByteArray = it[1][0]
		var nc := PackedByteArray()
		nc.resize(24)
		var bl := _blend_of(it[1])
		var nbl := PackedByteArray()
		if not bl.is_empty():
			nbl.resize(8)
		for n in 8:
			var bits := [(n >> 0) & 1, (n >> 1) & 1, (n >> 2) & 1]
			var nb := bits.duplicate()
			nb[a] = 1 - bits[b]
			nb[b] = bits[a]
			var m: int = nb[0] | (nb[1] << 1) | (nb[2] << 2)
			nc[m * 3 + d] = c[n * 3 + d]
			nc[m * 3 + a] = 8 - c[n * 3 + b]
			nc[m * 3 + b] = c[n * 3 + a]
			if not bl.is_empty():
				nbl[m] = bl[n]
		var t: PackedStringArray = it[1][1]
		var nt := t.duplicate()
		nt[b * 2 + 1] = t[a * 2 + 1]                     # +a -> +b, +b -> -a, -a -> -b, -b -> +a
		nt[a * 2] = t[b * 2 + 1]
		nt[b * 2] = t[a * 2]
		nt[a * 2 + 1] = t[b * 2]
		var ncut := []
		var omap := {a * 2 + 1: b * 2 + 1, b * 2 + 1: a * 2, a * 2: b * 2, b * 2: a * 2 + 1}
		for pl in _cut_of(it[1]):
			var n: Vector3i = pl[0]
			var nn := n
			nn[a] = -n[b]
			nn[b] = n[a]
			ncut.append([nn, int(pl[1]) - 8 * n[b], omap.get(int(pl[2]), int(pl[2]))])
		set_cell(Vector3i(nk.x, nk.y, nk.z) + o, nk.w, nc, nt, nbl, ncut)
	for it in mitems:
		var k: Vector4i = it[0]
		var s := size_of(k.w)
		var nk := k
		nk[a] = ext[b] - (k[b] + s)
		nk[b] = k[a]
		set_material(make_sel(Vector3i(nk.x, nk.y, nk.z) + o, nk.w, 3), it[1])
	var ns: Vector3i = sel["s"]
	var sw := ns
	sw[a] = ns[b]
	sw[b] = ns[a]
	return make_sel(sel["o"], sel["p"], sel["orient"], sw)


func flip(sel: Dictionary) -> void:
	var d: int = sel["orient"] >> 1
	var g := size_of(sel["p"])
	var ext: Vector3i = (sel["s"] as Vector3i) * g
	var items := _take(sel)
	var mitems := _take_mats(sel)
	delete(sel)
	set_material(sel, "air")
	for it in items:
		var k: Vector4i = it[0]
		var nk := k
		nk[d] = ext[d] - (k[d] + size_of(k.w))
		var c: PackedByteArray = it[1][0]
		var nc := PackedByteArray()
		nc.resize(24)
		var bl := _blend_of(it[1])
		var nbl := PackedByteArray()
		if not bl.is_empty():
			nbl.resize(8)
		for n in 8:
			var m := n ^ (1 << d)
			for e in 3:
				nc[m * 3 + e] = (8 - c[n * 3 + e]) if e == d else c[n * 3 + e]
			if not bl.is_empty():
				nbl[m] = bl[n]
		var t: PackedStringArray = (it[1][1] as PackedStringArray).duplicate()
		var tmp := t[d * 2]
		t[d * 2] = t[d * 2 + 1]
		t[d * 2 + 1] = tmp
		var ncut := []
		for pl in _cut_of(it[1]):
			var n: Vector3i = pl[0]
			var nn := n
			nn[d] = -n[d]
			var po := int(pl[2])
			ncut.append([nn, int(pl[1]) - 8 * n[d], (po ^ 1) if po >> 1 == d else po])
		set_cell(Vector3i(nk.x, nk.y, nk.z) + (sel["o"] as Vector3i), nk.w, nc, t, nbl, ncut)
	for it in mitems:
		var k: Vector4i = it[0]
		var nk := k
		nk[d] = ext[d] - (k[d] + size_of(k.w))
		set_material(make_sel(Vector3i(nk.x, nk.y, nk.z) + (sel["o"] as Vector3i), nk.w, 3), it[1])


## Move the selection's cubes (and materials) by `delta` ticks (Sauerbraten's editcut drag).
func move_cubes(sel: Dictionary, delta: Vector3i) -> Dictionary:
	var items := _take(sel)
	var mitems := _take_mats(sel)
	delete(sel)
	set_material(sel, "air")
	var o: Vector3i = (sel["o"] as Vector3i) + delta
	for it in items:
		var k: Vector4i = it[0]
		set_cell(Vector3i(k.x, k.y, k.z) + o, k.w, it[1][0], it[1][1], _blend_of(it[1]), _cut_of(it[1]))
	for it in mitems:
		var k: Vector4i = it[0]
		set_material(make_sel(Vector3i(k.x, k.y, k.z) + o, k.w, 3), it[1])
	var out := sel.duplicate()
	out["o"] = o
	return out


# ------------------------------------------------------------------------------------------------ meshes
func _face_hidden(k: Vector4i, c: PackedByteArray, o: int) -> bool:
	if not leaf_face_full(leaves[k], o):
		return false
	var sz := size_of(k.w)
	var st := orient_step(o) * sz
	var nk = Vector4i(k.x + st.x, k.y + st.y, k.z + st.z, k.w)   # (usually a neighbor of the same size: one lookup)
	if not leaves.has(nk):
		var same := Vector3i(nk.x, nk.y, nk.z)
		nk = _leaf_at_from(_beyond(k, o), k.w + 1)
		if nk == null:                                   # smaller cubes beyond: hidden if they cover all of it
			return _covered(same, k.w, o, _see_through(k))
	if not mats.is_empty() and (cube_in_mat(nk, "alpha") or cube_in_mat(nk, "noclip")) != (cube_in_mat(k, "alpha") or cube_in_mat(k, "noclip")):
		return false                                     # a see-through or pass-through neighbor doesn't hide it
	return leaf_face_full(leaves[nk], o ^ 1)


func _see_through(k: Vector4i) -> bool:
	return not mats.is_empty() and (cube_in_mat(k, "alpha") or cube_in_mat(k, "noclip"))


## Is the side of cell (size q) facing back along orient o (its side o ^ 1) completely covered by whole faces of the
## cubes in it? (A big cube's face against many small cubes is hidden when they fill it - it was drawn before.)
func _covered(cell: Vector3i, q: int, o: int, see_through: bool) -> bool:
	var k := Vector4i(cell.x, cell.y, cell.z, q)
	if leaves.has(k):
		return _see_through(k) == see_through and leaf_face_full(leaves[k], o ^ 1)
	if q <= MIN_P or _occ.get(k, 0) == 0:
		return false
	var h := size_of(q - 1)
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	for i in 2:
		for j in 2:
			var c := cell
			c[d] += 0 if o & 1 else h                    # (the half next to the face)
			c[a] += i * h
			c[b] += j * h
			if not _covered(c, q - 1, o, see_through):
				return false
	return true


func cube_points(k: Vector4i) -> PackedVector3Array:
	var c: PackedByteArray = leaves[k][0]
	var origin := Vector3(k.x, k.y, k.z) * TICK
	var unit := metres(k.w) / 8.0
	var out := PackedVector3Array()
	var cut := _cut_of(leaves[k])
	if not cut.is_empty():
		for p in cut_vertices(cut):
			out.append(origin + p * unit)
		return out
	for n in 8:
		var p := origin + corner(c, n) * unit
		if not out.has(p):
			out.append(p)
	return out


static func _tri_tangent(w: Array, uv: Array, n: Vector3) -> Plane:
	var e1: Vector3 = w[1] - w[0]
	var e2: Vector3 = w[2] - w[0]
	var d1: Vector2 = uv[1] - uv[0]
	var d2: Vector2 = uv[2] - uv[0]
	var det := d1.x * d2.y - d2.x * d1.y
	if absf(det) < 1e-9:
		return Plane(n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized(), 1.0)
	var t := (e1 * d2.y - e2 * d1.y) / det
	var b := (e2 * d1.x - e1 * d2.x) / det
	t = (t - n * n.dot(t)).normalized()
	return Plane(t, -1.0 if n.cross(t).dot(b) < 0.0 else 1.0)


## A render chunk's mesh (a surface per texture slot, plus materials), its collision triangles, and (with
## `outline`: faces unmerged; with `lines_too`: faces still merged) a lines mesh of every cube face's edges.
func chunk_mesh(ck: Vector3i, outline := false, lines_too := false) -> Array:
	return chunk_build(ck, chunk_arrays(ck, outline, lines_too))


## The math of chunk_mesh, nothing made: {groups, col, lines}. Only reads the world, so it can run on a worker thread
## (`threads` false there: it must not start tasks of its own).
func chunk_arrays(ck: Vector3i, outline := false, lines_too := false, threads := true) -> Dictionary:
	var groups := {}
	var col := PackedVector3Array()
	var lines := PackedVector3Array()
	var flats := {}                                      # slot key -> [slot, alpha, noclip, {Vector3i(orient, plane, size): {Vector2i cell: true}}]
	var no_mats := mats.is_empty()
	var pre := _cut_visible_all(ck) if threads else {}
	for k in _render.get(ck, {}):
		var v: Array = leaves[k]
		var c: PackedByteArray = v[0]
		var bl := _blend_of(v)
		var origin := Vector3(k.x, k.y, k.z) * TICK
		var unit := metres(k.w) / 8.0
		var noclip := cube_in_mat(k, "noclip")
		var alpha := cube_in_mat(k, "alpha")
		var cut := _cut_of(v)
		if not cut.is_empty():
			_cut_mesh(k, v, cut, origin, unit, noclip, alpha, groups, col, lines, outline or lines_too, pre.get(k))
			continue
		var flat := not outline and c == FULL and bl.is_empty()
		var sz := size_of(k.w)
		var quick := c == FULL and no_mats                   # whole cube, no materials: inline same-size neighbor test
		for o in 6:
			if quick:
				var st: Vector3i = _STEPS[o]
				var nv = leaves.get(Vector4i(k.x + st.x * sz, k.y + st.y * sz, k.z + st.z * sz, k.w))
				if nv == null:                               # a bigger neighbor? (the one holding the tick beyond)
					var np := Vector3i(k.x, k.y, k.z)
					np[o >> 1] += sz if o & 1 else -1
					for q in range(k.w + 1, MAX_P + 1):
						var sh := q + 3
						nv = leaves.get(Vector4i((np.x >> sh) << sh, (np.y >> sh) << sh, (np.z >> sh) << sh, q))
						if nv != null:
							break
					if nv != null and (nv as Array).size() <= 3 and nv[0] == FULL:
						continue                             # (the bigger cube's wall covers this square: one wall, no flicker)
					if nv == null:
						var sc := Vector3i(k.x + st.x * sz, k.y + st.y * sz, k.z + st.z * sz)
						if _occ.get(Vector4i(sc.x, sc.y, sc.z, k.w), 0) > 0 and _covered(sc, k.w, o, false):
							continue                             # (smaller cubes cover all of it)
					elif nv.size() <= 3 and nv[0] == FULL:
						continue
					elif _face_hidden(k, c, o):
						continue
				elif nv.size() <= 3 and nv[0] == FULL:
					continue                                 # (hidden by a whole cube the same size)
				elif _face_hidden(k, c, o):
					continue
			elif _face_hidden(k, c, o):
				continue
			if not quick and face_is_full(c, o):
				var bg = leaves.get(Vector4i(k.x + _STEPS[o].x * sz, k.y + _STEPS[o].y * sz, k.z + _STEPS[o].z * sz, k.w))
				if bg == null:                               # a bigger cube right next door: its wall covers this square
					var np2 := Vector3i(k.x, k.y, k.z)
					np2[o >> 1] += sz if o & 1 else -1
					for q in range(k.w + 1, MAX_P + 1):
						var sh2 := q + 3
						bg = leaves.get(Vector4i((np2.x >> sh2) << sh2, (np2.y >> sh2) << sh2, (np2.z >> sh2) << sh2, q))
						if bg != null:
							break
				if bg != null and (bg as Array).size() <= 3 and bg[0] == FULL:
					continue                             # (two coplanar walls would flicker: only the bigger one is drawn)
			if flat:                                         # whole faces: merged with their neighbors below
				if lines_too:                                # (the outline still shows each cube)
					var fq: Array = face_corners(o)
					for i in 4:
						lines.append(origin + corner(c, fq[i]) * unit)
						lines.append(origin + corner(c, fq[(i + 1) % 4]) * unit)
				var d := o >> 1
				var sk: String = v[1][o]
				if alpha or noclip:
					sk += "#a" if alpha else "#n"
					sk += "#n" if noclip and alpha else ""
				if not flats.has(sk):
					flats[sk] = [v[1][o], alpha, noclip, {}]
				var planes: Dictionary = flats[sk][3]
				var pk := Vector3i(o, k[d] + (sz if o & 1 else 0), k.w)
				if not planes.has(pk):
					planes[pk] = {}
				planes[pk][Vector2i(k[(d + 1) % 3] / sz, k[(d + 2) % 3] / sz)] = true
				continue
			var slot: String = v[1][o]
			var sl := parse_slot(slot)
			var key := slot + ("#alpha" if alpha else "")
			if not groups.has(key):
				groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(),
					PackedVector2Array(), PackedColorArray(), slot, alpha]
			var g: Array = groups[key]
			var verts: PackedVector3Array = g[0]
			var normals: PackedVector3Array = g[1]
			var tangents: PackedFloat32Array = g[2]
			var uvs: PackedVector2Array = g[3]
			var uv2s: PackedVector2Array = g[4]
			var cols: PackedColorArray = g[5]
			for i in 6:
				g[i] = null
			var layered: bool = sl["l"] != ""
			for t in face_tri_indices(c, o):
				var w := [origin + corner(c, t[0]) * unit, origin + corner(c, t[1]) * unit, origin + corner(c, t[2]) * unit]
				var n: Vector3 = (w[1] - w[0]).cross(w[2] - w[0]).normalized()
				var uv := [slot_uv(w[0], n, sl), slot_uv(w[1], n, sl), slot_uv(w[2], n, sl)]
				var tan := _tri_tangent(w, uv, n)
				for j in [0, 2, 1]:                          # Godot winds front faces clockwise
					verts.append(w[j])
					normals.append(n)
					tangents.append_array([tan.normal.x, tan.normal.y, tan.normal.z, tan.d])
					uvs.append(uv[j])
					uv2s.append(slot_uv(w[j], n, sl, true) if layered else Vector2.ZERO)
					cols.append(Color(1, 1, 1, float(bl[t[j]]) / 255.0 if not bl.is_empty() else 0.0))
					if not noclip:
						col.append(w[j])
			if outline or lines_too:
				var q: Array = face_corners(o)
				for i in 4:
					var pa := origin + corner(c, q[i]) * unit
					var pb := origin + corner(c, q[(i + 1) % 4]) * unit
					if pa != pb:
						lines.append(pa)
						lines.append(pb)
			g[0] = verts
			g[1] = normals
			g[2] = tangents
			g[3] = uvs
			g[4] = uv2s
			g[5] = cols
	for sk in flats:
		var f: Array = flats[sk]
		for pk in f[3]:
			_flat_quads([f[0], f[1], f[2], pk.x, pk.y, pk.z], f[3][pk], groups, col)
	if smooth_light:
		_smooth_normals(groups)
	return {"groups": groups, "col": col, "lines": lines}


static var smooth_light := true           ## (tests compare with it off)
const LERP_ANGLE := 44.0                 ## Sauerbraten's lerpangle: faces closer than this share smoothed normals


## Soft light across sloped faces (0.19.4), as Sauerbraten's lerpangle: where faces meet at less than 44 degrees, the
## corner they share gets the average of their normals, so light rolls across a slope instead of stepping at every
## triangle; sharper edges (a cube's 90 degree corners) stay crisp. Tangents follow the new normals.
static func _smooth_normals(groups: Dictionary) -> void:
	var lim := cos(deg_to_rad(LERP_ANGLE))
	var at := {}                                         # corner (snapped) -> the face normals that meet there
	for key in groups:
		var g: Array = groups[key]
		var vs: PackedVector3Array = g[0]
		var ns: PackedVector3Array = g[1]
		for i in vs.size():
			var kp := vs[i].snapped(Vector3.ONE * 0.002)
			var here = at.get(kp)
			if here == null:
				at[kp] = [ns[i]]
			elif not (here as Array).has(ns[i]):
				(here as Array).append(ns[i])
	for key in groups:
		var g: Array = groups[key]
		var vs: PackedVector3Array = g[0]
		var ns: PackedVector3Array = g[1]
		var tg: PackedFloat32Array = g[2]
		var changed := false
		for i in vs.size():
			var here: Array = at[vs[i].snapped(Vector3.ONE * 0.002)]
			if here.size() < 2:
				continue
			var n := ns[i]
			var sum := Vector3.ZERO
			for m in here:
				if n.dot(m) >= lim:
					sum += m
			var nn := sum.normalized()
			if nn.is_equal_approx(n) or nn == Vector3.ZERO:
				continue
			ns[i] = nn
			var t := Vector3(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])
			t = (t - nn * nn.dot(t)).normalized()
			tg[i * 4] = t.x
			tg[i * 4 + 1] = t.y
			tg[i * 4 + 2] = t.z
			changed = true
		if changed:
			g[1] = ns
			g[2] = tg


## chunk_arrays' result as meshes [mesh, collision triangles, lines mesh] (main thread: materials, the renderer).
func chunk_build(ck: Vector3i, arr: Dictionary) -> Array:
	var groups: Dictionary = arr["groups"]
	var col: PackedVector3Array = arr["col"]
	var lines: PackedVector3Array = arr["lines"]
	var m := ArrayMesh.new()
	for key in groups:
		var g: Array = groups[key]
		if (g[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g[0]
		arrays[Mesh.ARRAY_NORMAL] = g[1]
		arrays[Mesh.ARRAY_TANGENT] = g[2]
		arrays[Mesh.ARRAY_TEX_UV] = g[3]
		arrays[Mesh.ARRAY_TEX_UV2] = g[4]
		arrays[Mesh.ARRAY_COLOR] = g[5]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(m.get_surface_count() - 1, material_for(g[6], g[7]))
	_material_surfaces(ck, m, col)
	var lm := ArrayMesh.new()
	if not lines.is_empty():
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = lines
		lm.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
		if _line_mat == null:
			_line_mat = ShaderMaterial.new()
			_line_mat.shader = load("res://core/shaders/cube_lines.gdshader")
		lm.surface_set_material(0, _line_mat)
	return [m, col, lm]


## Greedy meshing: the visible whole faces of same-size cubes on one plane, with the same texture slot, drawn as
## the fewest rectangles that cover them (a flat 8 m floor of 0.125 m cubes is 8 triangles (2 per 4 m chunk), not 8192). Texture
## coordinates are planar in world space, so a merged rectangle looks exactly like the faces it replaces.
func _flat_quads(fk: Array, cells: Dictionary, groups: Dictionary, col: PackedVector3Array) -> void:
	var slot: String = fk[0]
	var alpha: bool = fk[1]
	var noclip: bool = fk[2]
	var o: int = fk[3]
	var plane: int = fk[4]
	var s := size_of(fk[5])
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var sl := parse_slot(slot)
	var key := slot + ("#alpha" if alpha else "")
	if not groups.has(key):
		groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(),
			PackedVector2Array(), PackedColorArray(), slot, alpha]
	var g: Array = groups[key]
	var verts: PackedVector3Array = g[0]
	var normals: PackedVector3Array = g[1]
	var tangents: PackedFloat32Array = g[2]
	var uvs: PackedVector2Array = g[3]
	var uv2s: PackedVector2Array = g[4]
	var cols: PackedColorArray = g[5]
	for i in 6:
		g[i] = null
	var layered: bool = sl["l"] != ""
	var q: Array = face_corners(o)
	var keys: Array = cells.keys()
	keys.sort_custom(func(l: Vector2i, r: Vector2i) -> bool: return l.y < r.y or (l.y == r.y and l.x < r.x))
	var used := {}
	for c0 in keys:
		if used.has(c0):
			continue
		var wa := 1                                      # grow along a, then whole rows along b
		while cells.has(Vector2i(c0.x + wa, c0.y)) and not used.has(Vector2i(c0.x + wa, c0.y)):
			wa += 1
		var wb := 1
		while true:
			var row_ok := true
			for i in wa:
				var cc := Vector2i(c0.x + i, c0.y + wb)
				if not cells.has(cc) or used.has(cc):
					row_ok = false
					break
			if not row_ok:
				break
			wb += 1
		for i in wa:
			for j in wb:
				used[Vector2i(c0.x + i, c0.y + j)] = true
		var pts := []                                    # the rectangle's corners, in face_corners order
		for n in q:
			var u := corner(FULL, n) / 8.0
			var pt := Vector3.ZERO
			pt[d] = plane
			pt[a] = (c0.x + u[a] * wa) * s
			pt[b] = (c0.y + u[b] * wb) * s
			pts.append(pt * TICK)
		for t in [[0, 1, 2], [0, 2, 3]]:
			var w := [pts[t[0]], pts[t[1]], pts[t[2]]]
			var nrm: Vector3 = (w[1] - w[0]).cross(w[2] - w[0]).normalized()
			var uv := [slot_uv(w[0], nrm, sl), slot_uv(w[1], nrm, sl), slot_uv(w[2], nrm, sl)]
			var tan := _tri_tangent(w, uv, nrm)
			for j in [0, 2, 1]:                          # Godot winds front faces clockwise
				verts.append(w[j])
				normals.append(nrm)
				tangents.append_array([tan.normal.x, tan.normal.y, tan.normal.z, tan.d])
				uvs.append(uv[j])
				uv2s.append(slot_uv(w[j], nrm, sl, true) if layered else Vector2.ZERO)
				cols.append(Color(1, 1, 1, 0))
				if not noclip:
					col.append(w[j])
	g[0] = verts
	g[1] = normals
	g[2] = tangents
	g[3] = uvs
	g[4] = uv2s
	g[5] = cols


static var _line_mat: ShaderMaterial = null    ## outline mode's lines (bright, drawn just in front of the faces)


## An exact cut piece's faces into the chunk's surfaces (same layout as chunk_mesh's corner cubes).
func _cut_mesh(k: Vector4i, v: Array, cut: Array, origin: Vector3, unit: float, noclip: bool, alpha: bool,
		groups: Dictionary, col: PackedVector3Array, lines: PackedVector3Array, outline: bool, pre = null) -> void:
	var bl := _blend_of(v)
	for f in (pre if pre != null else _cut_visible(k)):
		var slot: String = v[1][int(f[0])]
		var sl := parse_slot(slot)
		var key := slot + ("#alpha" if alpha else "")
		if not groups.has(key):
			groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array(),
				PackedVector2Array(), PackedColorArray(), slot, alpha]
		var g: Array = groups[key]
		var verts: PackedVector3Array = g[0]
		var normals: PackedVector3Array = g[1]
		var tangents: PackedFloat32Array = g[2]
		var uvs: PackedVector2Array = g[3]
		var uv2s: PackedVector2Array = g[4]
		var cols: PackedColorArray = g[5]
		for i in 6:
			g[i] = null
		var layered: bool = sl["l"] != ""
		var poly: PackedVector3Array = f[2]
		var n: Vector3 = f[3]
		# drawn a hair bigger than it is, so neighbors overlap: no rounding can open a pinhole between them (same plane,
		# same texture, so the overlap can't be seen). Collision keeps the exact shape.
		var cen := Vector3.ZERO
		for q in poly:
			cen += q
		cen = origin + cen / poly.size() * unit
		var drawn := PackedVector3Array()
		var exact := PackedVector3Array()
		for q in poly:
			var p := origin + q * unit
			exact.append(p)
			drawn.append(p + (p - cen).normalized() * FACE_GROW)
		for i in range(1, poly.size() - 1):
			var lp := [poly[0], poly[i], poly[i + 1]]
			var w := [drawn[0], drawn[i], drawn[i + 1]]
			var ex := [exact[0], exact[i], exact[i + 1]]
			var uv := [slot_uv(w[0], n, sl), slot_uv(w[1], n, sl), slot_uv(w[2], n, sl)]
			var tan := _tri_tangent(w, uv, n)
			for j in [0, 2, 1]:                              # Godot winds front faces clockwise
				verts.append(w[j])
				normals.append(n)
				tangents.append_array([tan.normal.x, tan.normal.y, tan.normal.z, tan.d])
				uvs.append(uv[j])
				uv2s.append(slot_uv(w[j], n, sl, true) if layered else Vector2.ZERO)
				cols.append(Color(1, 1, 1, _blend_at(bl, lp[j]) / 255.0 if not bl.is_empty() else 0.0))
				if not noclip:
					col.append(ex[j])
		if outline:
			for i in poly.size():
				lines.append(origin + poly[i] * unit)
				lines.append(origin + poly[(i + 1) % poly.size()] * unit)
		g[0] = verts
		g[1] = normals
		g[2] = tangents
		g[3] = uvs
		g[4] = uv2s
		g[5] = cols


## A cut cube's faces that can be seen. Most of a cut shape's cells only touch other cells, so skipping the walls a
## neighbor covers is most of its faces (and most of the work of finding them). Only reads the world: safe on a thread.
func _cut_visible(k: Vector4i) -> Array:
	var v: Array = leaves[k]
	var cut: Array = v[3]
	var rows := _cut_rows(cut)
	var skip := 0
	var nbs := [null, null, null, null, null, null]
	for o in 6:
		var nk = _wall_neighbor(k, o)
		if nk == null:
			if _face_hidden(k, v[0], o):                 # (smaller cubes beyond may cover it)
				skip |= 1 << o
			continue
		var nv: Array = leaves[nk]
		if leaf_face_full(nv, o ^ 1):
			skip |= 1 << o
		elif nv.size() > 3 and not (nv[3] as Array).is_empty():
			nbs[o] = nk
	var polys := _cut_polys(rows, skip)
	for o in 6:
		if nbs[o] != null and not (polys[o] as PackedFloat64Array).is_empty() and _wall_inside(k, polys[o], nbs[o]):
			polys[o] = PackedFloat64Array()
	return _faces_of(cut, rows, polys)


## Every cut cube's visible faces in a chunk, key -> faces, worked out across the CPU's cores when there are enough.
func _cut_visible_all(ck: Vector3i) -> Dictionary:
	var keys := []
	for k in _render.get(ck, {}):
		var v: Array = leaves[k]
		if v.size() > 3 and not (v[3] as Array).is_empty():
			keys.append(k)
	var out := {}
	if keys.size() < CUT_THREADS_FROM:
		return out                                       # (a few cubes: _cut_mesh does them as it goes)
	for o in 6:
		face_corners(o)                                  # (fills its cache here: threads only read it)
	var res := []
	res.resize(keys.size())
	var task := WorkerThreadPool.add_group_task(func(i: int): res[i] = _cut_visible(keys[i]), keys.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i in keys.size():
		out[keys[i]] = res[i]
	return out


## The cube of the same size or bigger across wall o, if a wall can be hidden by it (null: empty, smaller cubes, or
## one side see-through and the other not).
func _wall_neighbor(k: Vector4i, o: int):
	var sz := size_of(k.w)
	var st := orient_step(o) * sz
	var nk = Vector4i(k.x + st.x, k.y + st.y, k.z + st.z, k.w)
	if not leaves.has(nk):
		nk = _leaf_at_from(_beyond(k, o), k.w + 1)
		if nk == null:
			return null
	if not mats.is_empty() and _see_through(nk) != _see_through(k):
		return null
	return nk


## Does neighbor nk's solid cover all of this wall polygon (k's 0..8 units)? The tolerance is tight on purpose: shapes
## saved with coarser planes don't quite line up, and there the wall stays to plug the hairline between the two.
func _wall_inside(k: Vector4i, poly: PackedFloat64Array, nk: Vector4i) -> bool:
	var ks := float(size_of(k.w)) / 8.0
	var ns := 8.0 / float(size_of(nk.w))
	var ox := (float(k.x) - float(nk.x)) * ns
	var oy := (float(k.y) - float(nk.y)) * ns
	var oz := (float(k.z) - float(nk.z)) * ns
	var sc := ks * ns
	for pl in _cut_of(leaves[nk]):
		var n: Vector3i = pl[0]
		var nx := float(n.x)
		var ny := float(n.y)
		var nz := float(n.z)
		var lim := float(pl[1]) + 2e-4 * sqrt(nx * nx + ny * ny + nz * nz)
		for i in range(0, poly.size(), 3):
			if nx * (ox + poly[i] * sc) + ny * (oy + poly[i + 1] * sc) + nz * (oz + poly[i + 2] * sc) > lim:
				return false
	return true


## A blend weight anywhere in a cube (trilinear from its 8 corner weights; p in 0..8 units).
static func _blend_at(b: PackedByteArray, p: Vector3) -> float:
	var t := p / 8.0
	var out := 0.0
	for n in 8:
		var w := (t.x if n & 1 else 1.0 - t.x) * (t.y if (n >> 1) & 1 else 1.0 - t.y) * (t.z if (n >> 2) & 1 else 1.0 - t.z)
		out += w * b[n]
	return out


## Material cells: the faces you can see (not against the same material or a full cube face), drawn with each
## material's look; glass and clip add collision.
func _material_surfaces(ck: Vector3i, m: ArrayMesh, col: PackedVector3Array) -> void:
	var by := {}
	for k in _mrender.get(ck, {}):
		var name: String = mats[k]
		var kind := mat_kind(name)
		var visible_kind := kind in ["water", "lava", "glass"]
		var s := float(size_of(k.w))
		var lo := Vector3(k.x, k.y, k.z) * TICK
		var hi := lo + Vector3.ONE * s * TICK
		var sz := size_of(k.w)
		for o in 6:
			if kind in ["water", "lava"] and o == 2:
				continue                                 # (no underside to a pool)
			var st := orient_step(o) * sz
			var pieces := []
			_mat_face_pieces(name, Vector3i(k.x + st.x, k.y + st.y, k.z + st.z), k.w, o, pieces)
			var ax := o >> 1
			for piece in pieces:
				if piece[0] is String:                   # (the open part of a face a pushed-in cube half covers)
					_mat_quad(name, piece[1], o, visible_kind, col, by)
					continue
				var plo: Vector3 = piece[0]
				var phi: Vector3 = piece[1]
				plo[ax] = lo[ax]                         # (the piece of our face that this part of the neighbor touches)
				phi[ax] = hi[ax]
				_mat_quad(name, _box_face(plo, phi, o), o, visible_kind, col, by)
	_mat_surfaces_out(by, m)


## Which parts of a material cell's face to draw, looking at the cell beyond it (origin b, power q, ticks): none where
## the same material or a full solid is there, all of it where it's empty or another material, and where the cell
## beyond is mixed (smaller cubes or materials), its four quarters along the face, each the same way. A one-point
## look drew fills against smaller cubes (and inside faces once a fill merges into bigger cells).
func _mat_face_pieces(name: String, b: Vector3i, q: int, o: int, out: Array) -> void:
	var s := size_of(q)
	var mixed := false
	for qq in range(q, MAX_P + 1):                       # a material covering the whole cell beyond
		var ss := size_of(qq)
		var mk := Vector4i(_fdiv(b.x, ss) * ss, _fdiv(b.y, ss) * ss, _fdiv(b.z, ss) * ss, qq)
		if mats.has(mk):
			if mats[mk] == name:
				return
			break
	if _mocc.get(Vector4i(b.x, b.y, b.z, q), 0) > 0:
		mixed = true
	for qq in range(q, MAX_P + 1):                       # a cube covering it
		var ss := size_of(qq)
		var lk := Vector4i(_fdiv(b.x, ss) * ss, _fdiv(b.y, ss) * ss, _fdiv(b.z, ss) * ss, qq)
		if leaves.has(lk):
			var v: Array = leaves[lk]
			if (qq == q and leaf_face_full(v, o ^ 1)) or (qq > q and v[0] == FULL and _cut_of(v).is_empty()):
				return
			if qq == q:                                  # (a pushed-in cube beside: only the part of the face it leaves open)
				var nopen := _open_parts(v, b, q, o ^ 1)
				if not nopen.is_empty() and not nopen[0] is String:
					for poly in nopen:
						var rev: Array = (poly as Array).duplicate()
						rev.reverse()                    # (seen from our side)
						out.append(["poly", rev])
					return
			break
	if _occ.get(Vector4i(b.x, b.y, b.z, q), 0) > 0:
		mixed = true
	# our own side: a cube in the fill's cell whose face is right here already covers it (glass poured over a block
	# isn't drawn on the block's faces: the two flickered against each other)
	var st := orient_step(o) * s
	var inn := Vector3i(b.x - st.x, b.y - st.y, b.z - st.z)
	var ax := o >> 1
	for qq in range(q, MAX_P + 1):
		var ss := size_of(qq)
		var ik := Vector4i(_fdiv(inn.x, ss) * ss, _fdiv(inn.y, ss) * ss, _fdiv(inn.z, ss) * ss, qq)
		if leaves.has(ik):
			var iv: Array = leaves[ik]
			if qq == q:
				if leaf_face_full(iv, o):
					return
				var open := _open_parts(iv, inn, q, o)
				if not open.is_empty():
					if open[0] is String:                # (its face doesn't lie on this square: the whole square)
						break
					for poly in open:
						out.append(["poly", poly])
					return
			elif iv[0] == FULL and _cut_of(iv).is_empty():
				return
			elif inn[ax] + (s if o & 1 else 0) == ik[ax] + (ss if o & 1 else 0) and leaf_face_full(iv, o):
				return                                   # (on the bigger cube's own full face)
			break
	if _occ.get(Vector4i(inn.x, inn.y, inn.z, q), 0) > 0:
		mixed = true
	if mixed and q > MIN_P:
		var cs := size_of(q - 1)
		var near := 0 if (o & 1) == 1 else 1              # (the children of the cell beyond that touch our face)
		for i in 8:
			var c := Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1)
			if c[ax] != near:
				continue
			_mat_face_pieces(name, b + c * cs, q - 1, o, out)
		return
	out.append([Vector3(b) * TICK, Vector3(b + Vector3i(s, s, s)) * TICK])


## A fill face over a cube's face that a fold left only partly covering it: the square minus the cube's face polygon,
## as convex polygons (meters, counter-clockwise from outside), so the fill and the cube never share a surface. ["full"]
## when the cube's face doesn't lie on this square (pushed off it): then the fill's whole square is drawn.
func _open_parts(v: Array, cell: Vector3i, q: int, o: int) -> Array:
	var ax := o >> 1
	var a := (ax + 1) % 3
	var b := (ax + 2) % 3
	var side := 8.0 if o & 1 else 0.0
	var c: PackedByteArray = v[0]
	if not _cut_of(v).is_empty():
		return ["full"]
	var poly: Array[Vector2] = []
	for n in face_corners(o):
		var p := corner(c, n)
		if absf(p[ax] - side) > 1e-4:
			return ["full"]
		var p2 := Vector2(p[a], p[b])
		if poly.is_empty() or not poly[poly.size() - 1].is_equal_approx(p2):
			poly.append(p2)
	if poly.size() > 1 and poly[0].is_equal_approx(poly[poly.size() - 1]):
		poly.pop_back()
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	if poly.size() < 3 or absf(area) < 1e-6:
		return ["full"]                                  # (squashed to nothing on this side)
	if area < 0.0:
		poly.reverse()
	var square: Array[Vector2] = [Vector2(0, 0), Vector2(8, 0), Vector2(8, 8), Vector2(0, 8)]
	var pieces := []
	for i in poly.size():                                # outside edge i, inside the edges before it: disjoint pieces
		var piece := _clip_half(square, poly[(i + 1) % poly.size()], poly[i])
		for j in i:
			piece = _clip_half(piece, poly[j], poly[(j + 1) % poly.size()])
		if piece.size() >= 3:
			pieces.append(piece)
	var sz := float(size_of(q))
	var out := []
	var n3 := orient_normal(o)
	for piece in pieces:
		var pts := []
		for p2 in piece:
			var w := Vector3.ZERO
			w[ax] = float(cell[ax]) + side / 8.0 * sz
			w[a] = float(cell[a]) + p2.x / 8.0 * sz
			w[b] = float(cell[b]) + p2.y / 8.0 * sz
			pts.append(w * TICK)
		if ((pts[1] as Vector3) - pts[0]).cross((pts[2] as Vector3) - pts[0]).dot(n3) < 0.0:
			pts.reverse()
		out.append(pts)
	return out


## The part of a convex polygon to the left of the line p0 -> p1 (Sutherland-Hodgman, one edge).
static func _clip_half(poly: Array[Vector2], p0: Vector2, p1: Vector2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var d := p1 - p0
	for i in poly.size():
		var cur: Vector2 = poly[i]
		var nxt: Vector2 = poly[(i + 1) % poly.size()]
		var sc := d.cross(cur - p0)
		var sn := d.cross(nxt - p0)
		if sc >= -1e-9:
			out.append(cur)
		if (sc >= -1e-9) != (sn >= -1e-9) and absf(sc - sn) > 1e-12:
			out.append(cur.lerp(nxt, sc / (sc - sn)))
	return out


func _mat_quad(name: String, quad: Array, o: int, visible_kind: bool, col: PackedVector3Array, by: Dictionary) -> void:
	if mat_kind(name) in ["glass", "clip", "gameclip"]:
		for i in range(1, quad.size() - 1):
			col.append_array([quad[0], quad[i], quad[i + 1]])
	if not visible_kind and not show_mats:
		return
	if not by.has(name):
		by[name] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
	var arr: Array = by[name]
	var vs: PackedVector3Array = arr[0]
	var ns: PackedVector3Array = arr[1]
	var us: PackedVector2Array = arr[2]
	arr[0] = null
	arr[1] = null
	arr[2] = null
	var n := orient_normal(o)
	for i in range(1, quad.size() - 1):                  # (a fan: a quad, or the open part of one)
		for j in [0, i + 1, i]:
			vs.append(quad[j])
			ns.append(n)
			us.append(BlockShape._uv(quad[j], n))
	arr[0] = vs
	arr[1] = ns
	arr[2] = us


func _mat_surfaces_out(by: Dictionary, m: ArrayMesh) -> void:
	for name in by:
		var arr: Array = by[name]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = arr[0]
		a[Mesh.ARRAY_NORMAL] = arr[1]
		a[Mesh.ARRAY_TEX_UV] = arr[2]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		m.surface_set_material(m.get_surface_count() - 1, material_look(name))


## A box face's corners, counter-clockwise from outside.
static func _box_face(lo: Vector3, hi: Vector3, o: int) -> Array:
	var out := []
	for n in face_corners(o):
		out.append(Vector3(hi.x if n & 1 else lo.x, hi.y if (n >> 1) & 1 else lo.y, hi.z if (n >> 2) & 1 else lo.z))
	return out


func render_chunks() -> Array:
	var out := {}
	for k in _render:
		if not (_render[k] as Dictionary).is_empty():
			out[k] = true
	for k in _mrender:
		if not (_mrender[k] as Dictionary).is_empty():
			out[k] = true
	return out.keys()


## The cubes of a render chunk (for export collision).
func chunk_cubes(ck: Vector3i) -> Array:
	return (_render.get(ck, {}) as Dictionary).keys()


# ------------------------------------------------------------------------------------------------ saving
## For the .mallet: a palette of texture slots and the cubes packed into base64, plus material cells.
func to_dict() -> Dictionary:
	if _saved_rev == revision:
		return _saved
	if leaves.is_empty() and mats.is_empty():
		_saved = {}
		_saved_rev = revision
		return _saved
	var palette := [""]
	var buf := StreamPeerBuffer.new()
	for k in leaves:
		_write_leaf(buf, palette, k)
	var mlist := []
	for k in mats:
		mlist.append([k.x, k.y, k.z, k.w, mats[k]])
	_saved = {"v": 3, "palette": palette, "count": leaves.size(), "data": Marshalls.raw_to_base64(buf.data_array),
		"mats": mlist}
	_saved_rev = revision
	return _saved


func _write_leaf(buf: StreamPeerBuffer, palette: Array, k: Vector4i) -> void:
	var v: Array = leaves[k]
	buf.put_32(k.x)
	buf.put_32(k.y)
	buf.put_32(k.z)
	buf.put_8(k.w)
	buf.put_data(v[0])
	for id in v[1]:
		var i := palette.find(id)
		if i < 0:
			palette.append(id)
			i = palette.size() - 1
		buf.put_u16(i)
	var bl := _blend_of(v)
	buf.put_u8(1 if not bl.is_empty() else 0)
	if not bl.is_empty():
		buf.put_data(bl)
	var cut := _cut_of(v)                            # v3: an exact cut piece's planes
	buf.put_u8(cut.size())
	for pl in cut:
		var n: Vector3i = pl[0]
		buf.put_32(n.x)
		buf.put_32(n.y)
		buf.put_32(n.z)
		buf.put_64(int(pl[1]))
		buf.put_u8(int(pl[2]))


static func _read_leaf(buf: StreamPeerBuffer, palette: Array, ver: int) -> Array:
	var k := Vector4i(buf.get_32(), buf.get_32(), buf.get_32(), buf.get_8())
	var got: Array = buf.get_data(24)
	var t := PackedStringArray()
	for j in 6:
		var pi := buf.get_u16()
		t.append(palette[pi] if pi < palette.size() else "")
	var bl := PackedByteArray()
	if ver >= 2 and buf.get_u8() == 1:
		bl = buf.get_data(8)[1]
	var cut := []
	if ver >= 3:
		for j in buf.get_u8():
			var n := Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
			cut.append([n, buf.get_64(), buf.get_u8()])
	return [k, _v(got[1] as PackedByteArray, t, bl, cut)]


## Co-editing: while this is a Dictionary, every cube and material cell that changes is noted in it (materials under
## w + _MAT_TAG), so only what changed goes to the others instead of the whole object (a big object is megabytes).
## changed_all: the whole world was replaced (cleared) since, so a list of changes can't describe it.
var change_log = null
var changed_all := false


## The cells that changed since the last call, as data (the save format for the cubes there now, and the cells
## emptied), and start a fresh list.
func take_changes() -> Dictionary:
	var palette := [""]
	var buf := StreamPeerBuffer.new()
	var n := 0
	var gone := []
	var mset := []
	for k in (change_log as Dictionary):
		if k.w >= _MAT_TAG - 8:
			var mk := Vector4i(k.x, k.y, k.z, k.w - _MAT_TAG)
			mset.append([mk.x, mk.y, mk.z, mk.w, mats.get(mk, "")])
		elif leaves.has(k):
			_write_leaf(buf, palette, k)
			n += 1
		else:
			gone.append([k.x, k.y, k.z, k.w])
	change_log = {}
	return {"v": 3, "palette": palette, "count": n, "data": Marshalls.raw_to_base64(buf.data_array),
		"gone": gone, "mats": mset}


## Make the same changes another copy made (take_changes there). Not undoable here, and not noted as our own changes.
func apply_changes(d: Dictionary) -> void:
	finish_reading()
	var palette: Array = d.get("palette", [""])
	var buf := StreamPeerBuffer.new()
	buf.data_array = Marshalls.base64_to_raw(String(d.get("data", "")))
	for g in d.get("gone", []):
		if g is Array and (g as Array).size() >= 4:
			_put(Vector4i(int(g[0]), int(g[1]), int(g[2]), int(g[3])), null)
	for i in int(d.get("count", 0)):
		var r := _read_leaf(buf, palette, int(d.get("v", 3)))
		_put(r[0], r[1])
	for m in d.get("mats", []):
		if m is Array and (m as Array).size() >= 5:
			var mk := Vector4i(int(m[0]), int(m[1]), int(m[2]), int(m[3]))
			_put_mat(mk, null if String(m[4]) == "" else String(m[4]))
	_undo.clear()                                        # (the steps here no longer match what's there)
	_redo.clear()
	if change_log != null:
		change_log = {}


func load_dict(data: Dictionary) -> void:
	finish_reading()
	if data == to_dict():
		return
	if not data.is_empty() and not (leaves.is_empty() and mats.is_empty()):
		_load_changes_only(data)                         # (an undo step on a big object: only what differs is touched)
		return
	clear()
	if data.is_empty():
		return
	var ver := int(data.get("v", 1))
	var palette: Array = data.get("palette", [""])
	var buf := StreamPeerBuffer.new()
	buf.data_array = Marshalls.base64_to_raw(data.get("data", ""))
	_bulk = []                                           # (a fresh load: no per-cube chunk marking, every chunk at the end)
	for i in int(data.get("count", 0)):
		var r := _read_leaf(buf, palette, ver)
		_put(r[0], r[1])
	for m in data.get("mats", []):
		_put_mat(Vector4i(int(m[0]), int(m[1]), int(m[2]), int(m[3])), String(m[4]))
	if merge_on_load:
		merge_cubes()                                    # (fewer, bigger cubes: a big map opens and draws much faster)
	_bulk = null
	for ck in render_chunks():
		dirty[ck] = true
	_undo.clear()
	_redo.clear()


## Join cubes into bigger ones wherever all 8 cubes of a bigger cell are the same full cube (same textures, no fold,
## cut or blend paint, the same fill material around them), level by level up to the biggest size, like Sauerbraten's
## remip. Nothing looks different (textures are mapped by position, not per cube); there are just far fewer cubes to
## load, draw, save and edit. Returns how many cubes were saved.
static var merge_on_load := true          ## (tests that need a file's cubes exactly as written turn this off)


func merge_cubes() -> int:
	var before := leaves.size()
	var was_bulk = _bulk
	if _bulk == null:
		_bulk = []
	for q in range(MIN_P, MAX_P):
		var parents := {}
		var ps := size_of(q + 1)
		for k in leaves:
			if k.w == q:
				parents[Vector4i(_fdiv(k.x, ps) * ps, _fdiv(k.y, ps) * ps, _fdiv(k.z, ps) * ps, q + 1)] = true
		var cs := size_of(q)
		for pk in parents:
			var first = null
			var same := true
			var mat = null
			for i in 8:
				var ck := Vector4i(pk.x + (i & 1) * cs, pk.y + ((i >> 1) & 1) * cs, pk.z + ((i >> 2) & 1) * cs, q)
				var v = leaves.get(ck)
				if v == null or (v as Array)[0] != FULL or not _cut_of(v).is_empty() or not _blend_of(v).is_empty():
					same = false
					break
				if first == null:
					first = v
				elif v != first:
					same = false
					break
				if not mats.is_empty():
					var m := mat_at(Vector3(ck.x, ck.y, ck.z) + Vector3.ONE * cs * 0.5)
					if mat == null:
						mat = m
					elif m != mat:
						same = false
						break
			if not same or (not mats.is_empty() and mat_at(Vector3(pk.x, pk.y, pk.z) + Vector3.ONE * ps * 0.5) != mat):
				continue
			for i in 8:
				_put(Vector4i(pk.x + (i & 1) * cs, pk.y + ((i >> 1) & 1) * cs, pk.z + ((i >> 2) & 1) * cs, q), null)
			_put(pk, (first as Array).duplicate(true))
	if was_bulk == null:
		_bulk_end()
	return before - leaves.size()


## load_dict over a world that has cubes: change only the cells that differ, so only their chunks redraw (an undo
## step that changed a few cubes of a big object reloaded and re-meshed all of it).
func _load_changes_only(data: Dictionary) -> void:
	var ver := int(data.get("v", 1))
	var palette: Array = data.get("palette", [""])
	var buf := StreamPeerBuffer.new()
	buf.data_array = Marshalls.base64_to_raw(data.get("data", ""))
	var want := {}
	for i in int(data.get("count", 0)):
		var r := _read_leaf(buf, palette, ver)
		want[r[0]] = r[1]
	var want_m := {}
	for m in data.get("mats", []):
		want_m[Vector4i(int(m[0]), int(m[1]), int(m[2]), int(m[3]))] = String(m[4])
	for k in leaves.keys():
		if not want.has(k):
			_put(k, null)
	for k in want:
		if leaves.get(k) != want[k]:
			_put(k, want[k])
	for k in mats.keys():
		if not want_m.has(k):
			_put_mat(k, null)
	for k in want_m:
		if mats.get(k) != want_m[k]:
			_put_mat(k, want_m[k])
	_undo.clear()
	_redo.clear()


## Every cube object in a map: [[CubeWorld, Transform3D], ...] (0.6.0 maps kept their cubes under "cubes").
static func models_of(map: Dictionary) -> Array:
	var out := []
	var list: Array = map.get("cube_models", [])
	if list.is_empty() and not (map.get("cubes", {}) as Dictionary).is_empty():
		list = [{"cubes": map["cubes"]}]
	for d in list:
		var p: Array = d.get("position", [0.0, 0.0, 0.0])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(d.get("yaw", 0.0)))), Vector3(p[0], p[1], p[2]))
		out.append([from_dict(d.get("cubes", {})), xf])
	return out


static func from_dict(data: Dictionary) -> CubeWorld:
	var w := CubeWorld.new()
	w.load_dict(data)
	return w


func lowest() -> float:
	var y := INF
	for k in leaves:
		y = minf(y, k.y * TICK)
	return y


var _bounds_rev := -1
var _bounds_cache := AABB()


func bounds() -> AABB:
	if _bounds_rev == revision:                          # (unchanged since last asked: arcs ask every frame while dragging)
		return _bounds_cache
	_bounds_rev = revision
	_bounds_cache = _find_bounds()
	return _bounds_cache


func _find_bounds() -> AABB:
	var box := AABB()
	var first := true
	for k in leaves:
		var b := AABB(Vector3(k.x, k.y, k.z) * TICK, Vector3.ONE * metres(k.w))
		box = b if first else box.merge(b)
		first = false
	for k in mats:
		var b := AABB(Vector3(k.x, k.y, k.z) * TICK, Vector3.ONE * metres(k.w))
		box = b if first else box.merge(b)
		first = false
	return box
