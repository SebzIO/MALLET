class_name CubeWorld
extends RefCounted
## Cube geometry you build by hand, the way Cube 2: Sauerbraten's editor works (its ideas re-implemented here, not
## its code): the world is a grid of cubes at power-of-two sizes; you pull cubes out of faces and push them back in,
## push a face or a single corner in 1/8 steps to make slopes and bevels, and texture each face.
##
## A cube is 8 corners, each on its own 0..8 grid inside the cube (Sauerbraten stores the same thing as 12 edges of
## two 4-bit values; corner n's coordinate along axis d is one end of the edge along d - it's the same 24 numbers).
## A cube is always convex, so every cube is one convex solid: one collision shape, and one brush in a CS:S export.
##
## Positions are in ticks of 1/8 m. A cube of grid power p is 2^p m (p = -3 .. 6: 0.125 m .. 64 m) and sits on a
## multiple of its size. Cubes never overlap: making a small cube inside a big one splits the big one into 8.

const TICK := 0.125
const MIN_P := -3
const MAX_P := 6
const INDEX_TICKS := 512                 ## 64 m: the biggest cube, so no cube straddles an index cell
const RENDER_TICKS := 128                ## 16 m render chunks (rebuilt when something in them changes)
## Faces, numbered like Sauerbraten's orientations: axis * 2 + side (side 1 = the + side). Y is up here.
const ORIENT_SLOTS := ["left", "right", "bottom", "top", "front", "back"]   ## -X, +X, -Y, +Y, -Z, +Z
const ORIENT_NAMES := ["west (-X)", "east (+X)", "bottom", "top", "north (-Z)", "south (+Z)"]

static var FULL := _full_corners()

var leaves := {}                         ## Vector4i(x, y, z, p) -> [corners PackedByteArray(24), tex PackedStringArray(6)]
var dirty := {}                          ## render chunk Vector3i -> true
var revision := 0
var _index := {}                         ## Vector3i (64 m cell) -> {Vector4i: true}
var _render := {}                        ## Vector3i (16 m chunk) -> {Vector4i: true}
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


static func orient_step(o: int) -> Vector3i:
	var v := Vector3i.ZERO
	v[o >> 1] = 1 if o & 1 else -1
	return v


# ------------------------------------------------------------------------------------------------ cube shape
## Corner n's position (0..8 per axis) in the cube.
static func corner(c: PackedByteArray, n: int) -> Vector3:
	return Vector3(c[n * 3], c[n * 3 + 1], c[n * 3 + 2])


## The 4 corners of face o, counter-clockwise seen from outside.
static func face_corners(o: int) -> Array:
	var d := o >> 1
	var a := (d + 1) % 3
	var b := (d + 2) % 3
	var out := []
	for ab in [[0, 0], [1, 0], [1, 1], [0, 1]]:
		out.append(((o & 1) << d) | (ab[0] << a) | (ab[1] << b))
	if not o & 1:
		out.reverse()
	return out


## Nothing left of it: along some axis every edge has its two ends together (or crossed).
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


## The face as triangles (cube units), split along whichever diagonal keeps the cube convex.
static func face_triangles(c: PackedByteArray, o: int) -> Array:
	var q := []
	for n in face_corners(o):
		q.append(corner(c, n))
	var tris := []
	var n0: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
	var diag_ac := n0.length() < 1e-6 or n0.dot(q[3] - q[0]) <= 1e-6     # q3 on or behind plane(q0 q1 q2)
	var cand := [[q[0], q[1], q[2]], [q[0], q[2], q[3]]] if diag_ac else [[q[1], q[2], q[3]], [q[1], q[3], q[0]]]
	for t in cand:
		if (t[1] - t[0]).cross(t[2] - t[0]).length() > 1e-6:
			tris.append(t)
	return tris


## Convex and not inside out: every corner on or behind every face's triangles, faces facing their own way.
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
	for n in face_corners(o):
		for d in 3:
			if c[n * 3 + d] != FULL[n * 3 + d]:
				return false
	return true


## The face sits right on the cube's side (all four corners at the side) - pull further and it goes into the next cube.
static func face_at_side(c: PackedByteArray, o: int) -> bool:
	var d := o >> 1
	for n in face_corners(o):
		if c[n * 3 + d] != (8 if o & 1 else 0):
			return false
	return true


## Move one corner of face o along the face's axis: dir +1 = in (towards the opposite side), -1 = out.
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


## A child's corners when a cube is split into 8 (octant o = its x / y / z bits): each edge's range is
## interpolated at the child's position and doubled, like Sauerbraten's subdivision.
static func child_corners(c: PackedByteArray, o: int) -> PackedByteArray:
	if c == FULL:
		return FULL
	var out := PackedByteArray()
	out.resize(24)
	for d in 3:
		var a := (d + 1) % 3
		var b := (d + 2) % 3
		var od := (o >> d) & 1
		for m in 8:
			var ua := (float((o >> a) & 1) + float((m >> a) & 1)) * 0.5
			var ub := (float((o >> b) & 1) + float((m >> b) & 1)) * 0.5
			var end := (m >> d) & 1
			var v := 0.0
			for ia in 2:
				for ib in 2:
					var w := (ua if ia else 1.0 - ua) * (ub if ib else 1.0 - ub)
					if w == 0.0:
						continue
					var pn := (end << d) | (ia << a) | (ib << b)
					v += w * c[pn * 3 + d]
			out[m * 3 + d] = clampi(roundi(v * 2.0 - 8.0 * od), 0, 8)
	return PackedByteArray() if is_empty_shape(out) else out


# ------------------------------------------------------------------------------------------------ storage
func clear() -> void:
	for k in leaves.keys():
		_mark(k)
	leaves.clear()
	_index.clear()
	_render.clear()
	_undo.clear()
	_redo.clear()
	revision += 1


func count() -> int:
	return leaves.size()


static func _index_key(k: Vector4i) -> Vector3i:
	return Vector3i(_fdiv(k.x, INDEX_TICKS), _fdiv(k.y, INDEX_TICKS), _fdiv(k.z, INDEX_TICKS))


static func render_key(k: Vector4i) -> Vector3i:
	return Vector3i(_fdiv(k.x, RENDER_TICKS), _fdiv(k.y, RENDER_TICKS), _fdiv(k.z, RENDER_TICKS))


func _put(k: Vector4i, v) -> void:
	if _edit != null and not (_edit as Dictionary).has(k):
		_edit[k] = leaves.get(k)
	var ik := _index_key(k)
	var rk := render_key(k)
	if v == null:
		if leaves.erase(k):
			_index[ik].erase(k)
			_render[rk].erase(k)
	else:
		leaves[k] = v
		if not _index.has(ik):
			_index[ik] = {}
		_index[ik][k] = true
		if not _render.has(rk):
			_render[rk] = {}
		_render[rk][k] = true
	_mark(k)
	revision += 1


## Re-mesh the chunks this cube touches, and its neighbours' (their faces may show or hide now).
func _mark(k: Vector4i) -> void:
	var s := size_of(k.w)
	var lo := Vector3i(k.x - 1, k.y - 1, k.z - 1)
	var hi := Vector3i(k.x + s, k.y + s, k.z + s)
	for x in range(_fdiv(lo.x, RENDER_TICKS), _fdiv(hi.x, RENDER_TICKS) + 1):
		for y in range(_fdiv(lo.y, RENDER_TICKS), _fdiv(hi.y, RENDER_TICKS) + 1):
			for z in range(_fdiv(lo.z, RENDER_TICKS), _fdiv(hi.z, RENDER_TICKS) + 1):
				dirty[Vector3i(x, y, z)] = true
	for o in 6:                                         # a big neighbour whose corner is in a far chunk
		var nk = leaf_at(_beyond(k, o))
		if nk != null:
			dirty[render_key(nk)] = true


## A point just past the middle of face o (ticks).
static func _beyond(k: Vector4i, o: int) -> Vector3:
	var s := float(size_of(k.w))
	var p := Vector3(k.x + s * 0.5, k.y + s * 0.5, k.z + s * 0.5)
	var d := o >> 1
	p[d] = (k[d] + s + 0.5) if o & 1 else (k[d] - 0.5)
	return p


## The cube containing a point (ticks), or null.
func leaf_at(pt: Vector3):
	for p in range(MIN_P, MAX_P + 1):
		var s := size_of(p)
		var k := Vector4i(floori(pt.x / s) * s, floori(pt.y / s) * s, floori(pt.z / s) * s, p)
		if leaves.has(k):
			return k
	return null


## Every cube overlapping the box [o, o + size) (ticks).
func leaves_in(o: Vector3i, size: Vector3i) -> Array:
	var out := []
	var hi := o + size - Vector3i.ONE
	for x in range(_fdiv(o.x, INDEX_TICKS), _fdiv(hi.x, INDEX_TICKS) + 1):
		for y in range(_fdiv(o.y, INDEX_TICKS), _fdiv(hi.y, INDEX_TICKS) + 1):
			for z in range(_fdiv(o.z, INDEX_TICKS), _fdiv(hi.z, INDEX_TICKS) + 1):
				var cell: Dictionary = _index.get(Vector3i(x, y, z), {})
				for k in cell:
					var s := size_of(k.w)
					if k.x < o.x + size.x and k.x + s > o.x and k.y < o.y + size.y and k.y + s > o.y \
							and k.z < o.z + size.z and k.z + s > o.z:
						out.append(k)
	return out


func _split(k: Vector4i) -> void:
	var v: Array = leaves[k]
	var cs := size_of(k.w - 1)
	_put(k, null)
	for o in 8:
		var cc := child_corners(v[0], o)
		if cc.is_empty():
			continue
		_put(Vector4i(k.x + (o & 1) * cs, k.y + ((o >> 1) & 1) * cs, k.z + ((o >> 2) & 1) * cs, k.w - 1), [cc, v[1]])


## Make the cell (o, p) addressable on its own: split any bigger cube it's part of.
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


## What's in a cell: [] empty, [key] exactly one cube of that size, or ["mixed"] smaller cubes.
func cell_state(o: Vector3i, p: int) -> Array:
	_prepare(o, p)
	var k := Vector4i(o.x, o.y, o.z, p)
	if leaves.has(k):
		return [k]
	var s := size_of(p)
	return ["mixed"] if not leaves_in(o, Vector3i(s, s, s)).is_empty() else []


func _clear_cell(o: Vector3i, p: int) -> void:
	_prepare(o, p)
	var s := size_of(p)
	for k in leaves_in(o, Vector3i(s, s, s)):
		_put(k, null)


func set_cell(o: Vector3i, p: int, corners: PackedByteArray, tex: PackedStringArray) -> void:
	_clear_cell(o, p)
	_put(Vector4i(o.x, o.y, o.z, p), [corners, tex])


## Eight equal full cubes make one cube twice the size (keeps big flat areas cheap). Climbs while it can.
func _merge_up(o: Vector3i, p: int) -> void:
	while p < MAX_P:
		var ps := size_of(p + 1)
		var po := Vector3i(floori(float(o.x) / ps) * ps, floori(float(o.y) / ps) * ps, floori(float(o.z) / ps) * ps)
		var cs := size_of(p)
		var tex = null
		for i in 8:
			var k := Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p)
			var v = leaves.get(k)
			if v == null or v[0] != FULL or (tex != null and v[1] != tex):
				return
			tex = v[1]
		for i in 8:
			_put(Vector4i(po.x + (i & 1) * cs, po.y + ((i >> 1) & 1) * cs, po.z + ((i >> 2) & 1) * cs, p), null)
		_put(Vector4i(po.x, po.y, po.z, p + 1), [FULL, tex])
		o = po
		p += 1


# ------------------------------------------------------------------------------------------------ undo
func begin() -> void:
	_edit = {}


## Close the edit: one undo step. Returns whether anything changed.
func commit() -> bool:
	var before: Dictionary = _edit
	_edit = null
	var changed := false
	var after := {}
	for k in before:
		after[k] = leaves.get(k)
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
		_put(k, state[k])


# ------------------------------------------------------------------------------------------------ selection edits
## A selection is a box of cells: {o: Vector3i ticks (a multiple of the cell size), s: Vector3i cells, p: grid power,
## orient: the face direction it was made on}. Face edits work on the box's outer layer on that side.
static func make_sel(o: Vector3i, p: int, orient: int, s := Vector3i.ONE) -> Dictionary:
	return {"o": o, "s": s, "p": p, "orient": orient}


## The cells of the box's outer layer on its face side (shift = how many cells further out).
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


## The textures a new cube pulled out of `behind` gets: the same as the cube it came out of.
func _tex_from(behind: Vector3i, p: int, fallback: String) -> PackedStringArray:
	var s := float(size_of(p))
	var k = leaf_at(Vector3(behind) + Vector3.ONE * s * 0.5)
	return (leaves[k][1] as PackedStringArray).duplicate() if k != null else blank_tex(fallback)


## Mouse wheel: pull new cubes out of the selected faces (the selection follows them out).
func pull(sel: Dictionary, tex := "") -> Dictionary:
	var p: int = sel["p"]
	var front := moved(sel, 1)
	for c in face_layer(sel):
		var f: Vector3i = c + orient_step(sel["orient"]) * size_of(p)
		set_cell(f, p, FULL, _tex_from(c, p, tex))
	for c in face_layer(front):
		_merge_up(c, p)
	return front


## Mouse wheel the other way: push the selected layer of cubes out of existence (the selection follows it in).
func push(sel: Dictionary) -> Dictionary:
	for c in face_layer(sel):
		_clear_cell(c, sel["p"])
	return moved(sel, -1)


## F + wheel: move the selected faces in (dir 1) or out (dir -1) by 1/8 of a cube. Pulling a face that's already at
## its cube's side starts a thin new cube in front of it. Returns the selection (moved if a new layer started).
func push_face(sel: Dictionary, dir: int, only_corner := -1) -> Dictionary:
	var o: int = sel["orient"]
	var p: int = sel["p"]
	var cells := face_layer(sel)
	var moving: Array = face_corners(o) if only_corner < 0 else [face_corners(o)[only_corner]]
	var side := 8 if o & 1 else 0
	if dir < 0:
		# every moving corner already at its cube's side: start a thin new cube in front instead
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
			for n in moving:
				if cc[n * 3 + (o >> 1)] != side:
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
					nc[n * 3 + (o >> 1)] = 0 if o & 1 else 8
				for n in moving:
					_nudge(nc, o, n, -1)
				if not is_empty_shape(nc) and is_valid_shape(nc):
					set_cell(f, p, nc, _tex_from(c, p, ""))
			return front
	for c in cells:
		var st := cell_state(c, p)
		if st.size() != 1 or not st[0] is Vector4i:
			continue                                     # empty, or made of smaller cubes: pick a smaller grid
		var k: Vector4i = st[0]
		var v: Array = leaves[k]
		var nc: PackedByteArray = (v[0] as PackedByteArray).duplicate()
		for n in moving:
			_nudge(nc, o, n, dir)
		if nc == v[0]:
			continue
		if is_empty_shape(nc):
			_put(k, null)
		elif is_valid_shape(nc):
			_put(k, [nc, v[1]])
	return sel


## Y + wheel: give the selected faces a texture (every face of the selected cubes when `all_faces`).
func set_texture(sel: Dictionary, id: String, all_faces := false) -> void:
	var p: int = sel["p"]
	var g := size_of(p)
	for c in box_cells(sel):
		_prepare(c, p)
	var size: Vector3i = (sel["s"] as Vector3i) * g
	for k in leaves_in(sel["o"], size):
		var v: Array = leaves[k]
		var t: PackedStringArray = (v[1] as PackedStringArray).duplicate()
		if all_faces:
			t.fill(id)
		else:
			t[sel["orient"]] = id
		if t != v[1]:
			_put(k, [v[0], t])


func delete(sel: Dictionary) -> void:
	for c in box_cells(sel):
		_clear_cell(c, sel["p"])


## The selection's cubes, split so none is bigger than a cell, relative to the box: for copy, rotate and flip.
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


static func _split_to(k: Vector4i, v: Array, max_p: int) -> Array:
	if k.w <= max_p:
		return [[k, v]]
	var out := []
	var cs := size_of(k.w - 1)
	for o in 8:
		var cc := child_corners(v[0], o)
		if cc.is_empty():
			continue
		out.append_array(_split_to(Vector4i(k.x + (o & 1) * cs, k.y + ((o >> 1) & 1) * cs, k.z + ((o >> 2) & 1) * cs, k.w - 1),
			[cc, v[1]], max_p))
	return out


## C: copy the selection.
func copy(sel: Dictionary) -> Dictionary:
	return {"s": (sel["s"] as Vector3i) * size_of(sel["p"]), "p": sel["p"], "cubes": _take(sel)}


## V: paste a copy into the selection's corner (empty space in the copy leaves what's there).
func paste(sel: Dictionary, clip: Dictionary) -> Dictionary:
	if clip.is_empty():
		return sel
	var o: Vector3i = sel["o"]
	for item in clip["cubes"]:
		for piece in _split_to(item[0], item[1], sel["p"]):
			var k: Vector4i = piece[0]
			set_cell(Vector3i(k.x, k.y, k.z) + o, k.w, piece[1][0], piece[1][1])
	var g := size_of(sel["p"])
	var cs: Vector3i = clip["s"]
	return make_sel(o, sel["p"], sel["orient"], Vector3i(maxi(cs.x / g, 1), maxi(cs.y / g, 1), maxi(cs.z / g, 1)))


## R + wheel: turn the selection a quarter turn about its face's axis (the box keeps its corner).
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
	delete(sel)
	for it in items:
		var k: Vector4i = it[0]
		var s := size_of(k.w)
		var u := k[a]
		var v := k[b]
		var nk := k
		nk[a] = ext[b] - (v + s)                         # (u, v) -> (H - v, u): a quarter turn, a -> b
		nk[b] = u
		var c: PackedByteArray = it[1][0]
		var nc := PackedByteArray()
		nc.resize(24)
		for n in 8:
			var bits := [(n >> 0) & 1, (n >> 1) & 1, (n >> 2) & 1]
			var nb := bits.duplicate()
			nb[a] = 1 - bits[b]
			nb[b] = bits[a]
			var m: int = nb[0] | (nb[1] << 1) | (nb[2] << 2)
			nc[m * 3 + d] = c[n * 3 + d]
			nc[m * 3 + a] = 8 - c[n * 3 + b]
			nc[m * 3 + b] = c[n * 3 + a]
		var t: PackedStringArray = it[1][1]
		var nt := t.duplicate()
		nt[b * 2 + 1] = t[a * 2 + 1]                     # +a -> +b, +b -> -a, -a -> -b, -b -> +a
		nt[a * 2] = t[b * 2 + 1]
		nt[b * 2] = t[a * 2]
		nt[a * 2 + 1] = t[b * 2]
		var o: Vector3i = sel["o"]
		set_cell(Vector3i(nk.x, nk.y, nk.z) + o, nk.w, nc, nt)
	var ns: Vector3i = sel["s"]
	var sw := ns
	sw[a] = ns[b]
	sw[b] = ns[a]
	return make_sel(sel["o"], sel["p"], sel["orient"], sw)


## X: mirror the selection front to back (along its face's axis).
func flip(sel: Dictionary) -> void:
	var d: int = sel["orient"] >> 1
	var g := size_of(sel["p"])
	var ext: Vector3i = (sel["s"] as Vector3i) * g
	var items := _take(sel)
	delete(sel)
	for it in items:
		var k: Vector4i = it[0]
		var nk := k
		nk[d] = ext[d] - (k[d] + size_of(k.w))
		var c: PackedByteArray = it[1][0]
		var nc := PackedByteArray()
		nc.resize(24)
		for n in 8:
			var m := n ^ (1 << d)
			for e in 3:
				nc[m * 3 + e] = (8 - c[n * 3 + e]) if e == d else c[n * 3 + e]
		var t: PackedStringArray = (it[1][1] as PackedStringArray).duplicate()
		var tmp := t[d * 2]
		t[d * 2] = t[d * 2 + 1]
		t[d * 2 + 1] = tmp
		set_cell(Vector3i(nk.x, nk.y, nk.z) + (sel["o"] as Vector3i), nk.w, nc, t)


# ------------------------------------------------------------------------------------------------ meshes
## Is face o of this cube hidden by a full neighbour face right against it?
func _face_hidden(k: Vector4i, c: PackedByteArray, o: int) -> bool:
	if not face_is_full(c, o):
		return false
	var nk = leaf_at(_beyond(k, o))
	if nk == null or nk.w < k.w:
		return false
	return face_is_full(leaves[nk][0], o ^ 1)


## The world-space points of a cube's corners (metres).
func cube_points(k: Vector4i) -> PackedVector3Array:
	var c: PackedByteArray = leaves[k][0]
	var origin := Vector3(k.x, k.y, k.z) * TICK
	var unit := metres(k.w) / 8.0
	var out := PackedVector3Array()
	for n in 8:
		var p := origin + corner(c, n) * unit
		if not out.has(p):
			out.append(p)
	return out


## A render chunk's mesh (a surface per texture) and its triangles for collision / picking.
func chunk_mesh(ck: Vector3i) -> Array:
	var groups := {}
	var col := PackedVector3Array()
	var fs_cache := {}
	for k in _render.get(ck, {}):
		var v: Array = leaves[k]
		var c: PackedByteArray = v[0]
		var origin := Vector3(k.x, k.y, k.z) * TICK
		var unit := metres(k.w) / 8.0
		for o in 6:
			if _face_hidden(k, c, o):
				continue
			var id: String = v[1][o]
			var key := id if id != "" and MaterialLibrary.has(id) else ""
			if not fs_cache.has(key):
				fs_cache[key] = {"material": key, "uv_scale": 1.0, "uv_offset": [0.0, 0.0], "uv_rot": 0.0}
			var fs: Dictionary = fs_cache[key]
			if not groups.has(key):
				groups[key] = [PackedVector3Array(), PackedVector3Array(), PackedFloat32Array(), PackedVector2Array()]
			var g: Array = groups[key]
			var verts: PackedVector3Array = g[0]
			var normals: PackedVector3Array = g[1]
			var tangents: PackedFloat32Array = g[2]
			var uvs: PackedVector2Array = g[3]
			g[0] = null
			g[1] = null
			g[2] = null
			g[3] = null
			for t in face_triangles(c, o):
				var w := [origin + (t[0] as Vector3) * unit, origin + (t[1] as Vector3) * unit, origin + (t[2] as Vector3) * unit]
				var n: Vector3 = (w[1] - w[0]).cross(w[2] - w[0]).normalized()
				var tan := BlockShape._face_tangent(w, n, fs, Transform3D.IDENTITY, n)
				for j in [0, 2, 1]:                          # Godot winds front faces clockwise
					verts.append(w[j])
					normals.append(n)
					tangents.append_array([tan.normal.x, tan.normal.y, tan.normal.z, tan.d])
					uvs.append(BlockShape.face_uv(w[j], n, fs))
					col.append(w[j])
			g[0] = verts
			g[1] = normals
			g[2] = tangents
			g[3] = uvs
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
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(m.get_surface_count() - 1, material_for(key))
	return [m, col]


static var _materials := {}


static func material_for(id: String) -> Material:
	if not _materials.has(id):
		_materials[id] = MaterialLibrary.material(id, Color.WHITE) if id != "" else Look.ramp_material("grid", Color.html("9aa3ad"))
	return _materials[id]


func render_chunks() -> Array:
	return _render.keys().filter(func(k): return not (_render[k] as Dictionary).is_empty())


# ------------------------------------------------------------------------------------------------ saving
## For the .sfmap: a palette of texture ids and the cubes packed into base64 (cached until something changes).
func to_dict() -> Dictionary:
	if _saved_rev == revision:
		return _saved
	if leaves.is_empty():
		_saved = {}
		_saved_rev = revision
		return _saved
	var palette := PackedStringArray([""])
	var buf := StreamPeerBuffer.new()
	for k in leaves:
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
	_saved = {"v": 1, "palette": Array(palette), "count": leaves.size(), "data": Marshalls.raw_to_base64(buf.data_array)}
	_saved_rev = revision
	return _saved


func load_dict(data: Dictionary) -> void:
	if data == to_dict():
		return                                           # the same cubes: nothing to rebuild (undo of other things)
	clear()
	if data.is_empty():
		return
	var palette: Array = data.get("palette", [""])
	var buf := StreamPeerBuffer.new()
	buf.data_array = Marshalls.base64_to_raw(data.get("data", ""))
	for i in int(data.get("count", 0)):
		var k := Vector4i(buf.get_32(), buf.get_32(), buf.get_32(), buf.get_8())
		var got: Array = buf.get_data(24)
		var t := PackedStringArray()
		for j in 6:
			var pi := buf.get_u16()
			t.append(palette[pi] if pi < palette.size() else "")
		_put(k, [got[1] as PackedByteArray, t])
	_undo.clear()
	_redo.clear()


static func from_dict(data: Dictionary) -> CubeWorld:
	var w := CubeWorld.new()
	w.load_dict(data)
	return w


## Lowest point of any cube (metres), or INF.
func lowest() -> float:
	var y := INF
	for k in leaves:
		y = minf(y, k.y * TICK)
	return y


func bounds() -> AABB:
	var box := AABB()
	var first := true
	for k in leaves:
		var b := AABB(Vector3(k.x, k.y, k.z) * TICK, Vector3.ONE * metres(k.w))
		box = b if first else box.merge(b)
		first = false
	return box
