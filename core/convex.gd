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


## Outward planes from known faces (each three points on a face), oriented away from `inside`. Much faster than
## searching the hull when the shape's faces are known (cylinders, cones, spheres).
static func from_faces(faces: Array, inside: Vector3) -> Array:
	var planes: Array = []
	for f in faces:
		var nrm: Vector3 = (f[1] - f[0]).cross(f[2] - f[0])
		if nrm.length() < 1e-9:
			continue
		var pl := Plane(nrm.normalized(), (f[0] as Vector3).dot(nrm.normalized()))
		if pl.distance_to(inside) > 0.0:
			pl = Plane(-pl.normal, -pl.d)
		planes.append(pl)
	return planes


## A convex polygon (points in order) pushed along `dir`: a prism.
static func extrude(poly: Array, dir: Vector3) -> Array:
	var c := Vector3.ZERO
	for p in poly:
		c += p
	c = c / poly.size() + dir * 0.5
	var faces: Array = [[poly[0], poly[1], poly[2]], [poly[0] + dir, poly[1] + dir, poly[2] + dir]]
	for i in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		faces.append([a, b, a + dir])
	return from_faces(faces, c)


## The corner points of a piece.
static func points(piece: Array) -> PackedVector3Array:
	# Godot lists a corner once for every set of three planes meeting there, so a carved piece (many planes) can
	# repeat each corner dozens of times: keep one of each
	var raw := Geometry3D.compute_convex_mesh_points(piece)
	var out := PackedVector3Array()
	var seen := {}
	for p in raw:
		var k := Vector3i(roundi(p.x * 1000.0), roundi(p.y * 1000.0), roundi(p.z * 1000.0))
		if not seen.has(k):
			seen[k] = true
			out.append(p)
	return out


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
		var c := Vector3.ZERO
		for p in pts:
			if absf(plane.distance_to(p)) < EPS * 10.0:
				on.append(p)
				c += p
		if on.size() < 3:
			continue
		c /= on.size()
		var u: Vector3 = (on[0] - c).normalized()
		var v := plane.normal.cross(u)
		var angles: Array = []
		for p in on:
			angles.append(atan2((p - c).dot(v), (p - c).dot(u)))
		for i in range(1, on.size()):                           # insertion sort: a face has a handful of corners
			var ang: float = angles[i]
			var pt: Vector3 = on[i]
			var j := i - 1
			while j >= 0 and float(angles[j]) > ang:
				angles[j + 1] = angles[j]
				on[j + 1] = on[j]
				j -= 1
			angles[j + 1] = ang
			on[j + 1] = pt
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
	var out: Array = []
	for e in _carve_boxed(_boxed(piece), cutter, aabb(cutter)):
		out.append(e[0])
	return out


## Carve every piece by every cutter. Each piece carries its bounding box, so cutters that don't reach a piece
## cost almost nothing (engraved text is ~100 cutters, and a carve can leave hundreds of pieces).
static func carve_all(pieces: Array, cutters: Array) -> Array:
	var result: Array = []
	for p in pieces:
		var e := _boxed(p)
		if not e.is_empty():
			result.append(e)
	for c in cutters:
		var cbox := aabb(c)
		var next: Array = []
		for e in result:
			if not (e[1] as AABB).grow(-0.001).intersects(cbox):
				next.append(e)
			else:
				next.append_array(_carve_boxed(e, c, cbox))
		result = next
	var out: Array = []
	for e in result:
		out.append(e[0])
	return out


## [piece with only the planes that touch it, its box], or [] when nothing is left of it.
static func _boxed(piece: Array) -> Array:
	var pts := points(piece)
	if pts.size() < 4:
		return []
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	if box.size.x <= 0.01 or box.size.y <= 0.01 or box.size.z <= 0.01:
		return []
	var kept: Array = []
	for pl in piece:
		var plane: Plane = pl
		var deepest := 0.0
		var touching := 0
		for p in pts:
			var dist := plane.distance_to(p)
			deepest = maxf(deepest, -dist)
			if absf(dist) < EPS * 10.0:
				touching += 1
		if touching >= 3 and deepest < 0.02:
			return []                                            # a sliver (thinner than 2 cm across): drop it
		if touching > 0:
			kept.append(plane)
	# planes nowhere near the piece only cost time later (carving adds lots) - but only drop them if the piece
	# without them is provably the same: Godot's corner finder can miss a corner, and dropping the plane that
	# bounds it would send that piece shooting off into the distance
	if kept.size() < piece.size():
		for v in points(kept):
			for pl in piece:
				if (pl as Plane).distance_to(v) > EPS * 10.0:
					return [piece, box]
		return [kept, box]
	return [piece, box]


static func _carve_boxed(e: Array, cutter: Array, cbox: AABB) -> Array:
	if not (e[1] as AABB).grow(-0.001).intersects(cbox):
		return [e]
	var out: Array = []
	var rest: Array = (e[0] as Array).duplicate()
	for pl in cutter:
		var plane: Plane = pl
		var outside: Array = rest.duplicate()
		outside.append(Plane(-plane.normal, -plane.d))           # the part in front of this cutter face
		var o := _boxed(outside)
		if not o.is_empty():
			out.append(o)
		rest.append(plane)                                       # carry on with the part behind it
		if not solid(rest):
			return out                                           # the cutter only clipped an edge: done
	return out                                                   # what's left in `rest` is inside the cutter
