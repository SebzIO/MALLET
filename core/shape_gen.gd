class_name ShapeGen
extends RefCounted
## Geometry generation for build mode's Geometry menu: turns a shape and its dimensions into cubes of the
## CubeWorld octree - each cell is a convex cube with its own 8 corners on the 0..8 grid, exactly like a cube you
## pushed by hand. Nothing here is a mesh: the result is cells, so the shape stays editable by every build mode
## tool and exports to SurfsUp and CS:S like any other cubes.
##
## Two kinds of cells come out:
## - cells that are wholly inside the shape (large ones in the middle, so a box is not thousands of little cubes);
## - cells the surface passes through, split down to the finest level the detail setting allows, with the shape's
##   own plane kept as that cell's cut (the exact form a pushed face uses). That is what makes a ramp a real slope
##   and a cone round: the face is the plane, not a staircase of corner steps, and neighboring cells always share
##   their edges because no corner is ever pulled.
##
## Every shape is defined as a convex set (planes, a sphere, or an axis-aligned box), so "the whole cell is inside"
## and "the whole cell is outside" can both be decided exactly from the cell's corners.
##
## Dimensions are in grid units (the build mode grid), so 4 means four squares of the current grid.

const MAX_CELLS := 60000
const MIN_STEP := 0.125                                  ## finest corner step: the octree's smallest cube

## The shapes the menu offers. Each: id, name, and parameters [key, label, default, min, max, step] in grid units.
const SHAPES := [
	{"id": "box", "name": "Box / rectangular prism", "params": [
		["w", "Width", 4.0, 0.125, 64.0, 0.125], ["h", "Height", 2.0, 0.125, 64.0, 0.125],
		["d", "Depth", 4.0, 0.125, 64.0, 0.125]]},
	{"id": "sphere", "name": "Sphere", "params": [["r", "Radius", 2.0, 0.125, 32.0, 0.125]]},
	{"id": "cylinder", "name": "Cylinder", "params": [
		["r", "Radius", 2.0, 0.125, 32.0, 0.125], ["h", "Height", 4.0, 0.125, 64.0, 0.125],
		["sides", "Sides", 24.0, 3.0, 64.0, 1.0]]},
	{"id": "cone", "name": "Cone", "params": [
		["r", "Base radius", 2.0, 0.125, 32.0, 0.125], ["h", "Height", 4.0, 0.125, 64.0, 0.125],
		["sides", "Sides", 24.0, 3.0, 64.0, 1.0]]},
	{"id": "pyramid", "name": "Pyramid", "params": [
		["w", "Base width", 4.0, 0.125, 64.0, 0.125], ["d", "Base depth", 4.0, 0.125, 64.0, 0.125],
		["h", "Height", 3.0, 0.125, 64.0, 0.125]]},
	{"id": "prism", "name": "Triangular prism", "params": [
		["w", "Width", 4.0, 0.125, 64.0, 0.125], ["h", "Height", 2.0, 0.125, 64.0, 0.125],
		["l", "Length", 4.0, 0.125, 64.0, 0.125]]},
	{"id": "rhomboid", "name": "Rhomboid", "params": [
		["w", "Width", 4.0, 0.125, 64.0, 0.125], ["h", "Height", 2.0, 0.125, 64.0, 0.125],
		["d", "Depth", 4.0, 0.125, 64.0, 0.125], ["slant", "Slant", 1.0, 0.0, 16.0, 0.125]]},
	{"id": "stairs", "name": "Stairs", "params": [
		["w", "Width", 4.0, 0.125, 64.0, 0.125], ["run", "Step depth", 1.0, 0.125, 8.0, 0.125],
		["rise", "Step height", 0.5, 0.125, 8.0, 0.125], ["steps", "Steps", 4.0, 1.0, 32.0, 1.0]]},
	{"id": "ramp", "name": "Ramp", "params": [
		["w", "Width", 4.0, 0.125, 64.0, 0.125], ["l", "Length", 8.0, 0.125, 64.0, 0.125],
		["h", "Height", 2.0, 0.125, 32.0, 0.125]]},
	{"id": "quarter_pipe", "name": "Quarter pipe", "params": [
		["l", "Length", 8.0, 0.125, 64.0, 0.125], ["r", "Radius", 4.0, 0.5, 32.0, 0.125],
		["t", "Floor under it", 1.0, 0.0, 8.0, 0.125], ["deck", "Deck behind", 1.0, 0.0, 16.0, 0.125]]},
	{"id": "halfpipe", "name": "Halfpipe", "params": [
		["l", "Length", 8.0, 0.125, 64.0, 0.125], ["r", "Radius", 4.0, 0.5, 32.0, 0.125],
		["flat", "Flat bottom", 2.0, 0.0, 32.0, 0.125], ["t", "Floor under it", 1.0, 0.0, 8.0, 0.125]]},
]
## Turning a shape (0.19.8): degrees, applied to its planes before it's cut into cubes, so a turned shape is still
## exact octree cut cubes. Not for spheres (no use) or stairs (boxes on the grid: turn them in 90 degree steps).
const ROT_PARAMS := [["yaw", "Yaw (°)", 0.0, -180.0, 180.0, 1.0], ["pitch", "Pitch (°)", 0.0, -90.0, 90.0, 1.0],
	["roll", "Roll (°)", 0.0, -180.0, 180.0, 1.0]]
const NO_ROTATION := ["sphere", "stairs"]


static func defs() -> Array:
	return SHAPES


static func def_of(id: String) -> Dictionary:
	for s in SHAPES:
		if s["id"] == id:
			if id in NO_ROTATION:
				return s
			var d: Dictionary = s.duplicate(true)
			d["params"] = (d["params"] as Array) + ROT_PARAMS
			return d
	return def_of(String(SHAPES[0]["id"]))


static func defaults(id: String) -> Dictionary:
	var out := {}
	for p in def_of(id)["params"]:
		out[p[0]] = float(p[2])
	return out


## Build the cells for a shape. `vals` are in grid units, `p` is the build mode grid power the shape is aligned to,
## `detail` how many levels finer than that the surface may be cut (0-4). Returns
## {cells: [[Vector3i origin, int power, PackedByteArray corners], ...], size: Vector3 meters, count: int,
##  finest: float, error: String} - `error` set means nothing to place, with the reason in plain words.
static func generate(id: String, vals: Dictionary, p: int, detail: int) -> Dictionary:
	var grid := CubeWorld.metres(p)
	var spec := _spec(id, vals, grid)
	if spec.has("error"):
		return {"cells": [], "error": String(spec["error"])}
	var q_min := maxi(CubeWorld.MIN_P, p - clampi(detail, 0, 6))
	spec = _rotated(spec, Vector3(float(vals.get("pitch", 0.0)), float(vals.get("yaw", 0.0)), float(vals.get("roll", 0.0))))
	var g := CubeWorld.size_of(p)
	var sz: Vector3 = spec["size"]
	if sz.x <= 0.0001 or sz.y <= 0.0001 or sz.z <= 0.0001:
		return {"cells": [], "error": "One of those sizes is zero."}
	var nx := maxi(1, ceili(sz.x / grid - 0.0001))
	var ny := maxi(1, ceili(sz.y / grid - 0.0001))
	var nz := maxi(1, ceili(sz.z / grid - 0.0001))
	if nx * ny * nz > MAX_CELLS:
		return {"cells": [], "error": "That shape needs more than %d starting cells: make it smaller or use a bigger grid." % MAX_CELLS}
	var cells: Array = []
	if String(spec["type"]) == "stairs":
		for b in spec["boxes"]:
			_emit_box(b, p, cells)
	elif String(spec["type"]) == "ramp" and not spec.get("turned", false):
		_cut_ramp(spec, p, cells)
	else:
		for x in nx:
			for y in ny:
				for z in nz:
					if cells.size() > MAX_CELLS:
						return {"cells": [], "error": "That is more than %d cubes: use a bigger grid or less detail." % MAX_CELLS}
					_walk(spec, Vector3i(x * g, y * g, z * g), p, q_min, cells)
	if cells.is_empty():
		return {"cells": [], "error": "Nothing landed inside the grid: make it bigger than %s." % _m(grid)}
	var whole := verify(id, vals, spec, cells, CubeWorld.metres(q_min))
	if whole != "":
		return {"cells": [], "error": whole}             # (it would come out with pieces missing: not shown, not placed)
	return {"cells": cells, "size": sz, "count": cells.size(), "finest": CubeWorld.metres(q_min), "error": ""}


## The octree's own test (0.19.8): points spread through the true shape must each land in a cube (and, in a cut
## cube, on its solid side). A shape the octree can't make whole at this grid and detail - parts thinner than its
## finest cube, details it can't hold - fails this and isn't shown or placed; the reason says what to change.
## "" = whole (up to 8% of the points may miss: a stair's edges and a curve's facets miss a few right on them).
static func verify(id: String, vals: Dictionary, spec: Dictionary, cells: Array, finest: float) -> String:
	var sz: Vector3 = spec["size"]
	var have := {}
	var levels := {}
	for c in cells:
		var o: Vector3i = c[0]
		have[Vector4i(o.x, o.y, o.z, int(c[1]))] = c
		levels[int(c[1])] = true
	var samples := 0
	var misses := 0
	var n := 11
	for ix in n:
		for iy in n:
			for iz in n:
				var pt := Vector3((ix + 0.5) / n * sz.x, (iy + 0.5) / n * sz.y, (iz + 0.5) / n * sz.z)
				if not _inside(spec, pt):
					continue
				samples += 1
				if not _covered(have, levels, pt):
					misses += 1
	if samples > 0 and misses > maxi(2, samples * 8 / 100):   # (edges and curves miss a few points: real failures miss most)
		return "The octree can't make this whole at this grid and detail (%d of %d points of it would be missing): raise the detail, make the thin parts bigger, or use a smaller grid." % [misses, samples]
	return ""


## Is this point (meters) in one of the cells, on its solid side?
static func _covered(have: Dictionary, levels: Dictionary, pt: Vector3) -> bool:
	var t := (pt - Vector3.ONE * 0.002) / CubeWorld.TICK   # (2 mm in: a point on a face isn't a miss)
	for q in levels:
		var sz := CubeWorld.size_of(q)
		var k := Vector4i(floori(t.x / sz) * sz, floori(t.y / sz) * sz, floori(t.z / sz) * sz, q)
		if not have.has(k):
			continue
		var c: Array = have[k]
		if c.size() <= 3:
			return true
		var u := (t - Vector3(k.x, k.y, k.z)) / float(sz) * 8.0
		var solid := true
		for pl in _cut_planes_of(c):
			if (pl[0] as Vector3).dot(u) > float(pl[1]) + 0.05:
				solid = false
				break
		return solid
	return false


## A shape turned by pitch / yaw / roll (degrees) around its middle, as planes (or carved planes), moved back so its
## box starts at 0 again. Spheres and stairs come back as they are.
static func _rotated(s: Dictionary, rot: Vector3) -> Dictionary:
	if rot.is_zero_approx() or String(s["type"]) in ["sphere", "stairs"]:
		return s
	var b := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)), EULER_ORDER_YXZ)
	var sz: Vector3 = s["size"]
	var c := sz * 0.5
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in 8:
		var p := Vector3(sz.x if i & 1 else 0.0, sz.y if i & 2 else 0.0, sz.z if i & 4 else 0.0)
		var q := b * (p - c) + c
		lo = lo.min(q)
		hi = hi.max(q)
	var shift := -lo                                     # (p' = b (p - c) + c + shift)
	var turn := func(pl: Array) -> Array:
		var n: Vector3 = pl[0]
		var n2 := b * n
		return [n2, float(pl[1]) - n.dot(c) + n2.dot(c + shift)]
	var out := {"type": "planes", "size": hi - lo, "turned": true}
	if String(s["type"]) == "carve":
		out["type"] = "carve"
		var bp: Array = []
		for pl in s["box_planes"]:
			bp.append(turn.call(pl))
		out["box_planes"] = bp
		var holes: Array = []
		for h in s["holes"]:
			if String(h["kind"]) == "cyl":
				holes.append({"kind": "cyl", "a": b * ((h["a"] as Vector3) - c) + c + shift, "u": (b * (h["u"] as Vector3)).normalized(), "r": h["r"]})
			else:
				var hp: Array = []
				for pl in h["planes"]:
					hp.append(turn.call(pl))
				holes.append({"kind": "planes", "planes": hp})
		out["holes"] = holes
		return out
	var planes: Array = []
	for pl in _world_planes(s):
		planes.append(turn.call(pl))
	out["planes"] = planes
	return out


## Put generated cells into a CubeWorld at `offset` (ticks), every face using `tex`. Returns how many cells landed.
static func place(w: CubeWorld, cells: Array, offset: Vector3i, tex: String) -> int:
	var t := CubeWorld.blank_tex(tex)
	var n := 0
	for c in cells:
		var o: Vector3i = (c[0] as Vector3i) + offset
		var q: int = c[1]
		var cut: Array = (c[3] as Array).duplicate(true) if c.size() > 3 else []
		w.set_cell(o, q, (c[2] as PackedByteArray).duplicate(), t.duplicate(), PackedByteArray(), cut)
		n += 1
	return n


## A preview mesh for the Geometry menu and its placing ghost: one surface of triangles, no textures, built straight
## from the cells, so it can follow a slider. Returns [ArrayMesh, PackedVector3Array of the surface's edges].
## Only faces that face no cell of the same size are drawn (culling those keeps a solid's inside out of the picture),
## and a cut cell's faces are clipped by its planes, so a ramp or a cone shows its real slanted surface.
static func preview_mesh(cells: Array) -> Array:
	var arrays := preview_arrays(cells)
	return [mesh_of(arrays), arrays[2]]


## The preview's geometry as plain arrays: [vertices, normals, edge lines]. Nothing here touches the scene tree or the
## renderer, so a shape that takes a long time can be built on a worker thread and turned into a mesh afterwards.
static func preview_arrays(cells: Array) -> Array:
	var have := {}
	var levels := {}
	for c in cells:
		var o: Vector3i = c[0]
		have[Vector4i(o.x, o.y, o.z, int(c[1]))] = true
		levels[int(c[1])] = true
	var lv: Array = levels.keys()
	lv.sort()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var lines := PackedVector3Array()
	for c in cells:
		var o: Vector3i = c[0]
		var q: int = c[1]
		var step := CubeWorld.size_of(q)
		var unit := CubeWorld.metres(q) / 8.0
		var base := Vector3(o) * CubeWorld.TICK
		var planes := _cut_planes_of(c)
		for oi in 6:
			var n: Vector3 = CubeWorld.orient_normal(oi)
			var d := Vector3i(roundi(n.x), roundi(n.y), roundi(n.z))
			if _covered_by(have, lv, o, q, d):
				continue                                 # (a cell sits against this face: it is inside the shape)
			var poly := PackedVector3Array()
			for cn in CubeWorld.face_corners(oi):
				poly.append(CubeWorld.corner(CubeWorld.FULL, cn))
			for pl in planes:
				poly = _clip_poly(poly, pl[0], float(pl[1]))
				if poly.size() < 3:
					break
			_emit_face(poly, n, base, unit, verts, normals, lines)
		for i in planes.size():
			var poly := _plane_square(planes[i][0], float(planes[i][1]))
			for wi in 6:
				poly = _clip_poly(poly, CubeWorld.orient_normal(wi), 8.0 if wi & 1 else 0.0)
				if poly.size() < 3:
					break
			for j in planes.size():
				if j == i:
					continue
				poly = _clip_poly(poly, planes[j][0], float(planes[j][1]))
				if poly.size() < 3:
					break
			_emit_face(poly, planes[i][0], base, unit, verts, normals, lines)
	return [verts, normals, lines]


## The mesh for preview_arrays' vertices and normals (made on the main thread, where the renderer is).
static func mesh_of(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	var verts: PackedVector3Array = arrays[0]
	if verts.is_empty():
		return m
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = arrays[1]
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## True when a cell of the same size or a bigger one sits against a face: that face is inside the shape.
static func _covered_by(have: Dictionary, levels: Array, o: Vector3i, q: int, dir: Vector3i) -> bool:
	var np := o + dir * CubeWorld.size_of(q)
	if have.has(Vector4i(np.x, np.y, np.z, q)):
		return true
	for q2 in levels:
		if q2 <= q:
			continue
		var s := CubeWorld.size_of(q2)
		var b := Vector3i(floori(float(np.x) / s) * s, floori(float(np.y) / s) * s, floori(float(np.z) / s) * s)
		if have.has(Vector4i(b.x, b.y, b.z, q2)):
			return true
	return false


## A cell's cuts as planes in its own 0..8 units: [unit normal, offset], solid where normal . p <= offset.
static func _cut_planes_of(c: Array) -> Array:
	var out := []
	if c.size() <= 3:
		return out
	for pl in c[3]:
		var n := Vector3(pl[0])
		var l := n.length()
		if l < 1e-9:
			continue
		out.append([n / l, float(pl[1]) / l])
	return out


## A square on a plane, big enough to hold any cut face and then some (the cell's walls trim it).
static func _plane_square(n: Vector3, off: float) -> PackedVector3Array:
	var nn := n.normalized()
	var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := nn.cross(u)
	var c := nn * off
	var r := 16.0
	return PackedVector3Array([c + (u + v) * r, c + (-u + v) * r, c + (-u - v) * r, c + (u - v) * r])


## Sutherland-Hodgman: the part of a polygon where normal . p <= offset. A convex polygon that is wholly on one
## side is returned or dropped as it is: most clips in a many-sided cone hit that case, and skipping them is what
## keeps a cut cell with dozens of planes quick.
static func _clip_poly(poly: PackedVector3Array, n: Vector3, off: float) -> PackedVector3Array:
	var cnt := poly.size()
	if cnt == 0:
		return poly
	var all_in := true
	var all_out := true
	for i in cnt:
		if n.dot(poly[i]) > off + 1e-6:
			all_in = false
		else:
			all_out = false
		if not all_in and not all_out:
			break
	if all_in:
		return poly
	if all_out:
		return PackedVector3Array()
	var out := PackedVector3Array()
	for i in cnt:
		var a := poly[i]
		var b := poly[(i + 1) % cnt]
		var da := n.dot(a) - off
		var db := n.dot(b) - off
		if da <= 1e-6:
			out.append(a)
			if db > 1e-6:
				out.append(a + (b - a) * (da / (da - db)))
		elif db <= 1e-6:
			out.append(a + (b - a) * (da / (da - db)))
	return out


## Add a polygon facing `want` as triangles (Godot winds front faces clockwise) and its edges as lines.
static func _emit_face(poly: PackedVector3Array, want: Vector3, base: Vector3, unit: float,
		verts: PackedVector3Array, normals: PackedVector3Array, lines: PackedVector3Array) -> void:
	if poly.size() < 3:
		return
	var nrm := _poly_normal(poly)
	if nrm.length() < 1e-9:
		return
	if nrm.dot(want) < 0.0:
		poly.reverse()
		nrm = -nrm
	nrm = nrm.normalized()
	var w := PackedVector3Array()
	for p in poly:
		var wp := base + p * unit
		if w.size() > 0 and wp.distance_squared_to(w[w.size() - 1]) < 1e-10:
			continue                                 # (clipping can repeat a point: dropping it keeps slivers out)
		w.append(wp)
	if w.size() > 1 and w[0].distance_squared_to(w[w.size() - 1]) < 1e-10:
		w.remove_at(w.size() - 1)
	for i in range(1, w.size() - 1):
		if (w[i + 1] - w[0]).cross(w[i] - w[0]).length() < 1e-9:
			continue
		verts.append(w[0])
		verts.append(w[i + 1])
		verts.append(w[i])
		for _j in 3:
			normals.append(nrm)
	for i in w.size():
		lines.append(w[i])
		lines.append(w[(i + 1) % w.size()])


## The direction a polygon faces, from its plane: a fan of cross products around its middle.
static func _poly_normal(poly: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in poly:
		c += p
	c /= float(poly.size())
	var n := Vector3.ZERO
	for i in poly.size():
		n += (poly[i] - c).cross(poly[(i + 1) % poly.size()] - c)
	return n * 0.5


## The box the cells fill, in ticks (for the placement preview and its outline).
static func cell_bounds(cells: Array) -> AABB:
	if cells.is_empty():
		return AABB()
	var lo := Vector3i.MAX
	var hi := Vector3i.MIN
	for c in cells:
		var o: Vector3i = c[0]
		var s := CubeWorld.size_of(c[1])
		lo = lo.min(o)
		hi = hi.max(o + Vector3i(s, s, s))
	return AABB(Vector3(lo), Vector3(hi - lo))


# ------------------------------------------------------------------------------------------------ the shapes
## Meters and planes for a shape. Planes are [normal, offset] with "inside" meaning normal . p <= offset.
static func _spec(id: String, vals: Dictionary, grid: float) -> Dictionary:
	var v := {}
	for p in def_of(id)["params"]:
		v[p[0]] = maxf(float(vals.get(p[0], p[2])), 0.0)
	var w := float(v.get("w", 4.0)) * grid
	var h := float(v.get("h", 2.0)) * grid
	var d := float(v.get("d", 4.0)) * grid
	match id:
		"box":
			return {"type": "box", "size": Vector3(w, h, d), "planes": [
				[Vector3.RIGHT, w], [Vector3.LEFT, 0.0], [Vector3.UP, h], [Vector3.DOWN, 0.0],
				[Vector3.BACK, d], [Vector3.FORWARD, 0.0]]}
		"sphere":
			var r := float(v.get("r", 2.0)) * grid
			if r <= 0.0:
				return {"error": "The radius has to be bigger than zero."}
			return {"type": "sphere", "size": Vector3(r * 2.0, r * 2.0, r * 2.0),
				"center": Vector3(r, r, r), "r": r}
		"cylinder", "cone":
			var r := float(v.get("r", 2.0)) * grid
			var sides := clampi(roundi(float(v.get("sides", 24.0))), 3, 64)
			if r <= 0.0 or h <= 0.0:
				return {"error": "The radius and the height have to be bigger than zero."}
			var planes: Array = []
			for i in sides:                                   # a many-sided prism: the octree's slanted faces
				var a := TAU * float(i) / float(sides)
				var n := Vector3(cos(a), (r / h) if id == "cone" else 0.0, sin(a))
				planes.append([n, r + cos(a) * r + sin(a) * r])   # (the cone/cylinder stand on 0..2r: the axis is at (r, 0, r))
			planes.append([Vector3.UP, h])
			planes.append([Vector3.DOWN, 0.0])
			return {"type": "planes", "size": Vector3(r * 2.0, h, r * 2.0), "planes": planes}
		"pyramid":
			if w <= 0.0 or h <= 0.0 or d <= 0.0:
				return {"error": "The base and the height have to be bigger than zero."}
			return {"type": "planes", "size": Vector3(w, h, d), "planes": [
				[Vector3(1.0, w / (2.0 * h), 0.0), w],
				[Vector3(-1.0, w / (2.0 * h), 0.0), 0.0],
				[Vector3(0.0, d / (2.0 * h), 1.0), d],
				[Vector3(0.0, d / (2.0 * h), -1.0), 0.0],
				[Vector3.UP, h], [Vector3.DOWN, 0.0]]}
		"prism":
			if w <= 0.0 or h <= 0.0 or d <= 0.0:
				return {"error": "The width, height and length have to be bigger than zero."}
			return {"type": "planes", "size": Vector3(w, h, d), "planes": [
				[Vector3(1.0, 0.0, 0.0), w], [Vector3(-1.0, 0.0, 0.0), 0.0],
				[Vector3(h / w, 1.0, 0.0), h], [Vector3.DOWN, 0.0],
				[Vector3(0.0, 0.0, 1.0), d], [Vector3(0.0, 0.0, -1.0), 0.0]]}
		"rhomboid":
			var slant := float(v.get("slant", 1.0)) * grid
			if w <= 0.0 or h <= 0.0 or d <= 0.0:
				return {"error": "The width, height and depth have to be bigger than zero."}
			return {"type": "planes", "size": Vector3(w + slant, h, d), "planes": [
				[Vector3(1.0, -slant / h, 0.0), w], [Vector3(-1.0, slant / h, 0.0), 0.0],
				[Vector3.UP, h], [Vector3.DOWN, 0.0],
				[Vector3(0.0, 0.0, 1.0), d], [Vector3(0.0, 0.0, -1.0), 0.0]]}
		"stairs":
			var run := float(v.get("run", 1.0)) * grid
			var rise := float(v.get("rise", 0.5)) * grid
			var steps := clampi(roundi(float(v.get("steps", 4.0))), 1, 32)
			if w <= 0.0 or run <= 0.0 or rise <= 0.0:
				return {"error": "The width, step depth and step height have to be bigger than zero."}
			var boxes: Array = []
			for i in steps:
				boxes.append(AABB(Vector3(0.0, 0.0, i * run), Vector3(w, (i + 1) * rise, run)))
			return {"type": "stairs", "size": Vector3(w, steps * rise, steps * run), "boxes": boxes}
		"ramp":
			var l := float(v.get("l", 8.0)) * grid
			if w <= 0.0 or h <= 0.0 or l <= 0.0:
				return {"error": "The width, length and height have to be bigger than zero."}
			return {"type": "ramp", "size": Vector3(w, h, l), "w": w, "h": h, "l": l}
		"quarter_pipe", "halfpipe":
			# a block with round channels carved out of it (0.19.8): a concave shape is "the box, minus these"
			var l := float(v.get("l", 8.0)) * grid
			var r := float(v.get("r", 4.0)) * grid
			var t := float(v.get("t", 0.5)) * grid
			if l <= 0.0 or r <= 0.0:
				return {"error": "The length and the radius have to be bigger than zero."}
			var top := r + t
			var holes: Array = []
			var depth: float
			if id == "quarter_pipe":
				depth = r + float(v.get("deck", 1.0)) * grid
				holes.append({"kind": "cyl", "a": Vector3(0.0, top, 0.0), "u": Vector3.RIGHT, "r": r})
			else:
				var flat := float(v.get("flat", 2.0)) * grid
				depth = r * 2.0 + flat
				holes.append({"kind": "cyl", "a": Vector3(0.0, top, r), "u": Vector3.RIGHT, "r": r})
				holes.append({"kind": "cyl", "a": Vector3(0.0, top, r + flat), "u": Vector3.RIGHT, "r": r})
				if flat > 0.0:
					holes.append({"kind": "planes", "planes": [[Vector3.DOWN, -t], [Vector3.BACK, r + flat], [Vector3.FORWARD, -r]]})
			return {"type": "carve", "size": Vector3(l, top, depth), "holes": holes, "box_planes": [
				[Vector3.RIGHT, l], [Vector3.LEFT, 0.0], [Vector3.UP, top], [Vector3.DOWN, 0.0],
				[Vector3.BACK, depth], [Vector3.FORWARD, 0.0]]}
	return {"error": "Unknown shape: %s." % id}


static func _inside(s: Dictionary, pt: Vector3) -> bool:
	match String(s["type"]):
		"box":
			var sz: Vector3 = s["size"]
			return pt.x >= 0.0 and pt.y >= 0.0 and pt.z >= 0.0 and pt.x <= sz.x and pt.y <= sz.y and pt.z <= sz.z
		"sphere":
			return (pt - (s["center"] as Vector3)).length_squared() <= float(s["r"]) * float(s["r"])
		"planes":
			for pl in s["planes"]:
				if (pl[0] as Vector3).dot(pt) > float(pl[1]) + 1e-5:
					return false
			return true
		"ramp":
			if pt.x < -1e-5 or pt.z < -1e-5 or pt.y < -1e-5:
				return false
			if pt.x > float(s["w"]) + 1e-5 or pt.z > float(s["l"]) + 1e-5:
				return false
			return pt.y <= float(s["h"]) * pt.z / float(s["l"]) + 1e-5
		"carve":
			for pl in s["box_planes"]:
				if (pl[0] as Vector3).dot(pt) > float(pl[1]) + 1e-5:
					return false
			for h in s["holes"]:
				if _hole_state(h, pt, 0.0) == 1:
					return false
			return true
		"stairs":
			for b in s["boxes"]:
				if (b as AABB).has_point(pt):
					return true
				if pt.x >= b.position.x and pt.x <= b.end.x and pt.z >= b.position.z and pt.z <= b.end.z \
						and pt.y >= b.position.y and pt.y <= b.end.y:
					return true
	return false


static func _corners_of_box(o: Vector3i, q: int) -> Array:
	var size := float(CubeWorld.size_of(q))
	var lo := Vector3(o) * CubeWorld.TICK
	var hi := lo + Vector3(size, size, size) * CubeWorld.TICK
	return [lo, hi]


## -1 the cell is wholly outside the shape, 1 wholly inside, 0 the surface passes through it.
static func _state(s: Dictionary, o: Vector3i, q: int) -> int:
	var box := _corners_of_box(o, q)
	var lo: Vector3 = box[0]
	var hi: Vector3 = box[1]
	var corners: Array = []
	for i in 8:
		corners.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	match String(s["type"]):
		"box":
			var sz: Vector3 = s["size"]
			if lo.x >= sz.x - 1e-6 or lo.y >= sz.y - 1e-6 or lo.z >= sz.z - 1e-6:
				return -1
			if lo.x >= -1e-6 and lo.y >= -1e-6 and lo.z >= -1e-6 and hi.x <= sz.x + 1e-6 \
					and hi.y <= sz.y + 1e-6 and hi.z <= sz.z + 1e-6:
				return 1
			return 0
		"sphere":
			var c: Vector3 = s["center"]
			var r: float = s["r"]
			var near := Vector3(clampf(c.x, lo.x, hi.x), clampf(c.y, lo.y, hi.y), clampf(c.z, lo.z, hi.z))
			if (near - c).length_squared() >= r * r:
				return -1
			var far := 0.0
			for p in corners:
				far = maxf(far, (p - c).length_squared())
			return 1 if far <= r * r else 0
		"planes":
			# (one dot at the cell's middle decides each side: a cube reaches rad * (|nx| + |ny| + |nz|) along n,
			#  so a whole cell is decided without testing its 8 corners - the biggest shape-generation saving)
			var mid := (lo + hi) * 0.5
			var rad := (hi.x - lo.x) * 0.5
			var all_in := true
			for pl in s["planes"]:
				var n: Vector3 = pl[0]
				var reach := rad * (absf(n.x) + absf(n.y) + absf(n.z))
				var d := n.dot(mid) - float(pl[1])
				if d > reach + 1e-5:
					return -1
				if d > -reach + 1e-5:
					all_in = false
			return 1 if all_in else 0
		"ramp":
			var w: float = s["w"]
			var h: float = s["h"]
			var l: float = s["l"]
			if lo.x >= w - 1e-6 or lo.z >= l - 1e-6 or lo.y >= h - 1e-6:
				return -1
			if lo.x >= -1e-6 and lo.z >= -1e-6 and lo.y >= -1e-6 and hi.x <= w + 1e-6 \
					and hi.z <= l + 1e-6 and hi.y <= h * lo.z / l + 1e-6:
				return 1
			if lo.y >= h * hi.z / l - 1e-6:
				return -1
			return 0
		"carve":
			var mid := (lo + hi) * 0.5
			var rad := (hi.x - lo.x) * 0.5
			var all_in := true
			for pl in s["box_planes"]:
				var n: Vector3 = pl[0]
				var reach := rad * (absf(n.x) + absf(n.y) + absf(n.z))
				var d := n.dot(mid) - float(pl[1])
				if d > reach + 1e-5:
					return -1
				if d > -reach + 1e-5:
					all_in = false
			for h in s["holes"]:
				var hs := _hole_state(h, mid, rad)
				if hs == 1:
					return -1                            # (wholly in a channel: air)
				if hs == 0:
					all_in = false
			return 1 if all_in else 0
		"stairs":
			for b in s["boxes"]:
				var bb: AABB = b
				if lo.x >= bb.position.x - 1e-6 and lo.y >= bb.position.y - 1e-6 and lo.z >= bb.position.z - 1e-6 \
						and hi.x <= bb.end.x + 1e-6 and hi.y <= bb.end.y + 1e-6 and hi.z <= bb.end.z + 1e-6:
					return 1
			for b in s["boxes"]:
				var bb: AABB = b
				if lo.x < bb.end.x and hi.x > bb.position.x and lo.y < bb.end.y and hi.y > bb.position.y \
						and lo.z < bb.end.z and hi.z > bb.position.z:
					return 0
			return -1
	return -1


## A carved hole against a cell (middle `mid`, half size `rad`): 1 the cell is wholly in it, -1 wholly out, 0 the
## hole's surface passes through.
static func _hole_state(h: Dictionary, mid: Vector3, rad: float) -> int:
	if String(h["kind"]) == "cyl":
		var a: Vector3 = h["a"]
		var u: Vector3 = h["u"]
		var off := mid - a
		var dist := (off - u * u.dot(off)).length()
		var reach := rad * sqrt(3.0)
		if dist + reach <= float(h["r"]) - 1e-6:
			return 1
		if dist - reach >= float(h["r"]) + 1e-6:
			return -1
		return 0
	var inside := true
	for pl in h["planes"]:
		var n: Vector3 = pl[0]
		var reach := rad * (absf(n.x) + absf(n.y) + absf(n.z))
		var d := n.dot(mid) - float(pl[1])
		if d > reach + 1e-5:
			return -1
		if d > -reach + 1e-5:
			inside = false
	return 1 if inside else 0


## A ramp is one plane, and every cell can carry that plane as its own cut, so the slope is a truly flat face: cells
## wholly under it are full cubes, and the cells the plane runs through are cubes cut along it.
static func _cut_ramp(s: Dictionary, p: int, cells: Array) -> void:
	var g := CubeWorld.size_of(p)
	var size := CubeWorld.metres(p)
	var sz: Vector3 = s["size"]
	var nx := maxi(1, ceili(sz.x / size - 0.0001))
	var ny := maxi(1, ceili(sz.y / size - 0.0001))
	var nz := maxi(1, ceili(sz.z / size - 0.0001))
	var m := 1000                                        # (thousandths of a meter: the plane stays exact as integers)
	var l := roundi(float(s["l"]) * m)
	var h := roundi(float(s["h"]) * m)
	var n := Vector3i(0, l, -h)                          # y - (h/l) z <= 0, scaled: l y - h z <= 0
	for x in nx:
		for y in ny:
			for z in nz:
				var o := Vector3i(x * g, y * g, z * g)
				var c := roundi((float(h) * float(o.z) - float(l) * float(o.y)) / size)
				if 8 * l <= c:                           # (the whole cell is under the slope)
					cells.append([o, p, CubeWorld.FULL.duplicate()])
				elif -8 * h >= c:                        # (the whole cell is above it)
					continue
				else:
					cells.append([o, p, CubeWorld.FULL.duplicate(), [[n, c, 3]]])


## Stairs are exact boxes, so they are laid out as aligned cells of their own size: no trimming, no gaps at a step.
static func _emit_box(b: AABB, p: int, cells: Array) -> void:
	var lo := Vector3i(roundi(b.position.x / CubeWorld.TICK), roundi(b.position.y / CubeWorld.TICK), roundi(b.position.z / CubeWorld.TICK))
	var hi := Vector3i(roundi(b.end.x / CubeWorld.TICK), roundi(b.end.y / CubeWorld.TICK), roundi(b.end.z / CubeWorld.TICK))
	var q := p
	while q > CubeWorld.MIN_P:
		var s := CubeWorld.size_of(q)
		if lo.x % s == 0 and lo.y % s == 0 and lo.z % s == 0 and hi.x % s == 0 and hi.y % s == 0 and hi.z % s == 0:
			break
		q -= 1
	var step := CubeWorld.size_of(q)
	for x in range(lo.x, hi.x, step):
		for y in range(lo.y, hi.y, step):
			for z in range(lo.z, hi.z, step):
				cells.append([Vector3i(x, y, z), q, CubeWorld.FULL.duplicate()])


static func _walk(s: Dictionary, o: Vector3i, q: int, q_min: int, cells: Array) -> void:
	var st := _state(s, o, q)
	if st < 0:
		return
	if st == 1:
		cells.append([o, q, CubeWorld.FULL.duplicate()])
		return
	if q > q_min:
		var cs := CubeWorld.size_of(q - 1)
		for i in 8:
			_walk(s, o + Vector3i(i & 1, (i >> 1) & 1, (i >> 2) & 1) * cs, q - 1, q_min, cells)
		return
	var cut := _cell_cut(s, o, q)
	if cut.is_empty():
		cells.append([o, q, CubeWorld.FULL.duplicate()])
	else:
		cells.append([o, q, CubeWorld.FULL.duplicate(), cut])


## The world planes that bound a shape, as [normal, offset], inside meaning normal . p <= offset.
static func _world_planes(s: Dictionary) -> Array:
	var sz: Vector3 = s.get("size", Vector3.ONE)
	match String(s["type"]):
		"planes":
			return s["planes"]
		"box":
			return [[Vector3.RIGHT, sz.x], [Vector3.LEFT, 0.0], [Vector3.UP, sz.y], [Vector3.DOWN, 0.0],
				[Vector3.BACK, sz.z], [Vector3.FORWARD, 0.0]]
		"ramp":
			return [[Vector3(0.0, 1.0, -float(s["h"]) / float(s["l"])), 0.0], [Vector3.LEFT, 0.0],
				[Vector3.RIGHT, float(s["w"])], [Vector3.FORWARD, 0.0], [Vector3.BACK, float(s["l"])],
				[Vector3.DOWN, 0.0]]
	return []


## One world plane as a cell cut plane: [normal Vector3i, offset int, slot orient], inside = normal . u <= offset.
static func _local_plane(n: Vector3, off: float, lo: Vector3, size: float) -> Array:
	var m := 100000  # (fine enough that neighboring cells' pieces of one plane meet exactly)
	var nn := Vector3i(roundi(n.x * m), roundi(n.y * m), roundi(n.z * m))
	var c := roundi((off - n.dot(lo)) * 8.0 / size * m)
	var unit := n.normalized()
	var slot := 0
	var best := -2.0
	for o in 6:
		var dot := CubeWorld.orient_normal(o).dot(unit)
		if dot > best:
			best = dot
			slot = o
	return [nn, c, slot]


## The planes that actually cut this cell. Every plane leaves the cell wholly inside or wholly outside it, so the
## cell's own 8 corners stay a full cube and the face is the exact plane - no corner is pulled, so neighbors always
## share their edges and there are no gaps. A sphere gets the plane touching it nearest the cell's middle.
static func _cell_cut(s: Dictionary, o: Vector3i, q: int) -> Array:
	var size := CubeWorld.metres(q)
	var lo := Vector3(o) * CubeWorld.TICK
	if String(s["type"]) == "sphere":
		var c: Vector3 = s["center"]
		var d := lo + Vector3.ONE * size * 0.5 - c
		if d.length() < 1e-6:
			return []
		var n := d.normalized()
		return [_local_plane(n, n.dot(c) + float(s["r"]), lo, size)]
	var out: Array = []
	if String(s["type"]) == "carve":                     # the box's own sides, then each channel's surface, flipped
		var mid := lo + Vector3.ONE * size * 0.5
		for pl in s["box_planes"]:
			var n: Vector3 = pl[0]
			for i in 8:
				var p := lo + Vector3(size if i & 1 else 0.0, size if i & 2 else 0.0, size if i & 4 else 0.0)
				if n.dot(p) > float(pl[1]) + 1e-6:
					out.append(_local_plane(n, float(pl[1]), lo, size))
					break
		for h in s["holes"]:
			if _hole_state(h, mid, size * 0.5) != 0:
				continue
			if String(h["kind"]) == "cyl":
				var a: Vector3 = h["a"]
				var u: Vector3 = h["u"]
				var off := mid - a
				var radial := off - u * u.dot(off)
				if radial.length() < 1e-6:
					continue
				var dir := radial.normalized()
				var qs := a + u * u.dot(off) + dir * float(h["r"])
				out.append(_local_plane(-dir, -dir.dot(qs), lo, size))   # (solid outside the channel's round wall)
			else:
				var best: Array = []
				var bd := -INF
				for pl in h["planes"]:                   # (the channel's side this cell is against)
					var d := (pl[0] as Vector3).dot(mid) - float(pl[1])
					if d > bd:
						bd = d
						best = pl
				if not best.is_empty():
					out.append(_local_plane(-(best[0] as Vector3), -float(best[1]), lo, size))
		return out
	for pl in _world_planes(s):
		var n: Vector3 = pl[0]
		var off := float(pl[1])
		var cuts := false
		for i in 8:
			var p := lo + Vector3(size if i & 1 else 0.0, size if i & 2 else 0.0, size if i & 4 else 0.0)
			if n.dot(p) > off + 1e-6:
				cuts = true
				break
		if cuts:
			out.append(_local_plane(n, off, lo, size))
	return out


static func _m(metres: float) -> String:
	return ("%.3f m" % metres).trim_suffix("0").trim_suffix("0").trim_suffix(".")
