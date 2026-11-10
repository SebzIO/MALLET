class_name ShapeGen
extends RefCounted
## Geometry generation for build mode's Geometry menu: turns a shape and its dimensions into cubes of the
## CubeWorld octree - each cell is a convex cube with its own 8 corners on the 0..8 grid, exactly like a cube you
## pushed by hand. Nothing here is a mesh: the result is cells, so the shape stays editable by every build mode
## tool and exports to SurfsUp and CS:S like any other cubes.
##
## Two kinds of cells come out:
## - cells that are wholly inside the shape (large ones in the middle, so a box is not thousands of little cubes);
## - cells the surface passes through, split down to the finest level the detail setting allows, with the corners
##   that are outside the shape pulled in to it. That is what makes a ramp a real slope instead of stairs, and a
##   sphere round instead of cubic. A pulled cell is checked with CubeWorld.is_valid_shape; if it would not be
##   convex, a full cube is used instead (or the cell is left out).
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
]


static func defs() -> Array:
	return SHAPES


static func def_of(id: String) -> Dictionary:
	for s in SHAPES:
		if s["id"] == id:
			return s
	return SHAPES[0]


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
	elif String(spec["type"]) == "ramp":
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
	return {"cells": cells, "size": sz, "count": cells.size(), "finest": CubeWorld.metres(q_min), "error": ""}


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
				planes.append([n, r + cos(a) * r + sin(a) * r])
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
			var all_in := true
			for pl in s["planes"]:
				var n: Vector3 = pl[0]
				var off: float = float(pl[1])
				var inside_n := 0
				for p in corners:
					if n.dot(p) - off <= 1e-5:
						inside_n += 1
					else:
						all_in = false
				if inside_n == 0:
					return -1
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


static func _at(lo: Vector3, metres: float, co: Vector3i) -> Vector3:
	return lo + Vector3(co) / 8.0 * metres


## Corners for the cell with the ones outside the shape pulled in to it (one 1/8 step at a time, then pushed back
## along each axis as far as it can go while staying inside). Empty when the result would not be a convex cube.
## A ramp is one plane, so its cells are cut along Y only: every top corner is lowered to the slope, as far as the
## 1/8 corner grid goes. A cell that would end up thinner than one corner step is left out: the cell below it
## already reaches that far, and keeping it one step tall is what made the first ramps look like terraces.
static func _trim_ramp(s: Dictionary, o: Vector3i, q: int) -> PackedByteArray:
	var size := CubeWorld.metres(q)
	var step := size / 8.0
	var base := float(o.y) * CubeWorld.TICK
	var c := PackedByteArray()
	c.resize(24)
	var z0 := float(o.z) * CubeWorld.TICK
	var above := (float(s["h"]) * (z0 + size) / float(s["l"]) - base) / step
	if above <= 0.0:
		return PackedByteArray()                     # (this cell is entirely above the slope)
	var k1 := clampi(floori(above), 0, 8)
	var k0 := clampi(floori((float(s["h"]) * z0 / float(s["l"]) - base) / step + 1e-6), 0, k1)
	if k1 <= k0:
		return PackedByteArray()                     # (thinner than one corner step: the cell below already fills it)
	for n in 8:
		c[n * 3] = 8 if n & 1 else 0
		c[n * 3 + 1] = (k1 if n & 4 else k0) if n & 2 else 0
		c[n * 3 + 2] = 8 if n & 4 else 0
	if CubeWorld.is_empty_shape(c) or not CubeWorld.is_valid_shape(c):
		return PackedByteArray()
	return c


static func _trim(s: Dictionary, o: Vector3i, q: int) -> PackedByteArray:
	if String(s["type"]) == "ramp":
		return _trim_ramp(s, o, q)
	var metres := CubeWorld.metres(q)
	var lo := Vector3(o) * CubeWorld.TICK
	var c := PackedByteArray()
	c.resize(24)
	for n in 8:
		var want := Vector3i(8 if n & 1 else 0, 8 if n & 2 else 0, 8 if n & 4 else 0)
		var co := want
		if not _inside(s, _at(lo, metres, co)):
			var guard := 0
			while guard < 32 and not _inside(s, _at(lo, metres, co)):
				guard += 1
				for d in 3:
					if co[d] > 4:
						co[d] -= 1
					elif co[d] < 4:
						co[d] += 1
			if not _inside(s, _at(lo, metres, co)):
				return PackedByteArray()                 # (the shape does not reach this corner at all)
			for d in 3:                                  # back out along each axis, as far as it stays inside
				var out := 1 if want[d] == 8 else -1
				while true:
					var t := co[d] + out
					if t < 0 or t > 8:
						break
					var test := co
					test[d] = t
					if not _inside(s, _at(lo, metres, test)):
						break
					co[d] = t
		for d in 3:
			c[n * 3 + d] = co[d]
	if CubeWorld.is_empty_shape(c) or not CubeWorld.is_valid_shape(c):
		return PackedByteArray()
	return c


## A ramp is one plane, and every cell can carry that plane as its own cut (the exact form the octree already keeps
## for pushed faces), so the slope is a truly flat face: cells wholly under it are full cubes, and the cells the
## plane runs through are cubes cut along it. Both exporters read cuts, so the slope stays one brush face in CS:S
## and one slanted face in SurfsUp.
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
	var corners := _trim(s, o, q)
	if corners.is_empty():
		corners = _inset(s, o, q)                    # (a cell the surface only grazes: the biggest box inside it)
	if corners.is_empty() and _any_inside(s, o, q):
		corners = CubeWorld.FULL.duplicate()         # (a sliver thinner than the corner grid: fill it, no hole)
	if not corners.is_empty():
		cells.append([o, q, corners])


## The largest box the cell's 1/8 lattice allows that is wholly inside the shape, anywhere in the cell (the surface
## may only clip a corner). Used where no corner of the cell can be pulled in: the cell becomes a smaller box that
## is genuinely inside the shape instead of a full cube poking out of it. Empty when not even the smallest is.
static func _inset(s: Dictionary, o: Vector3i, q: int) -> PackedByteArray:
	var metres := CubeWorld.metres(q)
	var lo := Vector3(o) * CubeWorld.TICK
	for k in [4, 3, 2, 1]:
		var span: int = 8 - 2 * int(k)
		for ox in range(span + 1):
			for oy in range(span + 1):
				for oz in range(span + 1):
					var c := PackedByteArray()
					c.resize(24)
					var inside := true
					for n in 8:
						c[n * 3] = ox + (2 * int(k) if n & 1 else 0)
						c[n * 3 + 1] = oy + (2 * int(k) if n & 2 else 0)
						c[n * 3 + 2] = oz + (2 * int(k) if n & 4 else 0)
						if inside and not _inside(s, _at(lo, metres, Vector3i(c[n * 3], c[n * 3 + 1], c[n * 3 + 2]))):
							inside = false
					if inside and not CubeWorld.is_empty_shape(c) and CubeWorld.is_valid_shape(c):
						return c
	return PackedByteArray()


static func _any_inside(s: Dictionary, o: Vector3i, q: int) -> bool:
	var box := _corners_of_box(o, q)
	var lo: Vector3 = box[0]
	var hi: Vector3 = box[1]
	for i in 8:
		if _inside(s, Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z)):
			return true
	return _inside(s, (lo + hi) * 0.5)


static func _m(metres: float) -> String:
	return ("%.3f m" % metres).trim_suffix("0").trim_suffix("0").trim_suffix(".")
