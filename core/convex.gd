class_name Convex
extends RefCounted
## Convex solids, the building material of blocks. A piece is an Array of Planes with outward normals; the solid is
## the region behind all of them. Convex pieces are exactly what a Source brush is, so blocks export to CS:S
## one-to-one, and they make exact collision shapes.
##
## Includes Hammer's "carve": subtracting one convex solid from another leaves a handful of convex pieces.

const EPS := 0.001


## Outward planes of the convex hull of some points.
static func from_points(points: Array) -> Array:
	var pts: Array = []
	for p in points:
		var dup := false
		for q in pts:
			if (q as Vector3).distance_to(p) < 1e-4:
				dup = true
				break
		if not dup:
			pts.append(p)
	var planes: Array = []
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm: Vector3 = (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length() < 1e-6:
					continue
				nrm = nrm.normalized()
				var d: float = nrm.dot(pts[i])
				var front := false
				var back := false
				for p in pts:
					var sd: float = nrm.dot(p) - d
					if sd > EPS:
						front = true
					elif sd < -EPS:
						back = true
				if front and back:
					continue
				if front:
					nrm = -nrm
					d = -d
				var seen := false
				for pl in planes:
					if (pl as Plane).normal.dot(nrm) > 0.99999 and absf((pl as Plane).d - d) < EPS * 10.0:
						seen = true
						break
				if not seen:
					planes.append(Plane(nrm, d))
	return planes


## The corner points of a piece.
static func points(piece: Array) -> PackedVector3Array:
	return Geometry3D.compute_convex_mesh_points(piece)


## Is there anything left of this piece (a real volume, not a sliver)?
static func solid(piece: Array) -> bool:
	var pts := points(piece)
	if pts.size() < 4:
		return false
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box.size.x > 0.01 and box.size.y > 0.01 and box.size.z > 0.01


## Each face of a piece: [plane, polygon points in order around the face (counter-clockwise seen from outside)].
static func faces(piece: Array) -> Array:
	var pts := points(piece)
	var out: Array = []
	for pl in piece:
		var plane: Plane = pl
		var on: Array = []
		for p in pts:
			if absf(plane.distance_to(p)) < EPS * 10.0:
				on.append(p)
		if on.size() < 3:
			continue
		var c := Vector3.ZERO
		for p in on:
			c += p
		c /= on.size()
		var u: Vector3 = (on[0] - c).normalized()
		var v := plane.normal.cross(u)
		on.sort_custom(func(a, b): return atan2((a - c).dot(v), (a - c).dot(u)) < atan2((b - c).dot(v), (b - c).dot(u)))
		out.append([plane, on])
	return out


## Move a piece by a transform.
static func transformed(piece: Array, xf: Transform3D) -> Array:
	var out: Array = []
	for pl in piece:
		out.append(xf * (pl as Plane))
	return out


## The same piece shrunk inwards by `t` on every side (for hollowing).
static func shrunk(piece: Array, t: float) -> Array:
	var out: Array = []
	for pl in piece:
		out.append(Plane((pl as Plane).normal, (pl as Plane).d - t))
	return out


static func aabb(piece: Array) -> AABB:
	var pts := points(piece)
	if pts.is_empty():
		return AABB()
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	return box


## Hammer's carve: what's left of `piece` outside the convex `cutter`, as convex pieces.
static func carve(piece: Array, cutter: Array) -> Array:
	if not aabb(piece).grow(-0.001).intersects(aabb(cutter)):
		return [piece]
	var out: Array = []
	var rest: Array = piece.duplicate()
	for pl in cutter:
		var plane: Plane = pl
		var outside: Array = rest.duplicate()
		outside.append(Plane(-plane.normal, -plane.d))           # the part in front of this cutter face
		if solid(outside):
			out.append(outside)
		rest.append(plane)                                       # carry on with the part behind it
		if not solid(rest):
			return out                                           # the cutter only clipped an edge: done
	return out                                                   # what's left in `rest` is inside the cutter


## Carve every piece by every cutter.
static func carve_all(pieces: Array, cutters: Array) -> Array:
	var result := pieces
	for c in cutters:
		var next: Array = []
		for p in result:
			next.append_array(carve(p, c))
		result = next
	return result
