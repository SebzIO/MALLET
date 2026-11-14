class_name TransformGizmo
extends RefCounted
## The Move / Rotate / Scale gizmo drawn on the selected object in every view (0.29.0).
##
## Move: red / green / blue arrows (X / Y / Z, Y is up) drag along one world axis, the small squares between two
## arrows drag across that plane (colored by the axis they stay off), the white dot is the old free drag.
## Rotate: a see-through ball with a ring per axis the object can turn about, plus an outer ring that turns about
## the line of sight (blocks and text, which turn every way). Scale: axis lines with cube heads, plane squares and a
## center square that scales evenly. The ortho views show only what can be dragged in them.
##
## Everything is drawn on the view's 2D overlay from 3D points, at a constant size on screen (SIZE_PX). One drag is
## one undo step (the editor's _checkpoint at the first real movement); grid snap applies where the editor snaps.

enum Mode { MOVE, ROTATE, SCALE }
const MODE_NAMES := ["Move", "Rotate", "Scale"]
const SIZE_PX := 80.0                     ## arrow / ring size on screen
const PICK_PX := 8.0
const AXIS_COLORS := [Color(0.96, 0.25, 0.3), Color(0.45, 0.85, 0.12), Color(0.2, 0.5, 1.0)]
const VIEW_RING_COLOR := Color(0.85, 0.85, 0.88)
const ROTATE_SNAP := 15.0                 ## degrees, while grid snap is on (the same as [ and ])
const FACTOR_SNAP := 0.1                  ## scale factor steps for objects without a grid size, while snap is on

var mode := Mode.MOVE
var ed: Node                              ## the editor
var hover := ""                           ## the handle under the mouse ("" = none) ...
var hover_pane: ViewPane = null           ## ... in this view
var active := ""                          ## the handle being dragged

var _pane: ViewPane
var _c0 := Vector3.ZERO                   ## the gizmo's center when the drag began
var _axes := Basis.IDENTITY               ## the handles' axes (columns) when the drag began
var _axis := Vector3.ZERO                 ## the axis / ring axis / plane normal being dragged
var _m0 := Vector2.ZERO
var _t0 := 0.0                            ## where on the axis the press was (meters from the center)
var _hit0 := Vector3.ZERO
var _ang0 := 0.0
var _tangent := Vector2.ZERO              ## edge-on rings: the screen direction that turns the positive way
var _ring_px := 1.0
var _flip := 1.0
var _origins := {}                        ## object -> to_dict() before the drag
var _point0 := Vector3.ZERO               ## a ramp point being moved
var _point := -1
var _applied_move := Vector3.ZERO
var _applied_deg := 0.0
var _pivot := Vector3.ZERO
var _ramp_points := {}                    ## ramp -> its points before a scale
var _turned := 0.0                        ## radians turned on screen so far
var _last_key := ""                       ## the last scale applied (nothing new: no redraw, no undo step)


func _init(editor: Node) -> void:
	ed = editor


# ================================================================================================= what is shown
## The object the gizmo sits on, or null (nothing selected, locked, play mode).
func target() -> Node3D:
	var sel: Node3D = ed.selected
	if sel == null or not is_instance_valid(sel) or ed.is_locked(sel):
		return null
	return sel


func multi() -> bool:
	var s: Array = ed.selection()
	return s.size() > 1


## The ramp point the Move gizmo works on (-1: the whole selection).
func ramp_point() -> int:
	var sel: Node3D = target()
	if mode != Mode.MOVE or not sel is RampNode or multi():
		return -1
	var i: int = ed.selected_point
	if i < 0 or i >= (sel as RampNode).points.size() or i <= (sel as RampNode).lock_index():
		return -1
	return i


func center() -> Vector3:
	var sel: Node3D = target()
	var i := ramp_point()
	if i >= 0:
		return (sel as RampNode).points[i]
	return sel.call("center")


## Why this mode does nothing for the selection ("" = it works).
func unsupported() -> String:
	var sel: Node3D = target()
	if sel == null:
		return ""
	if mode == Mode.SCALE:
		if multi():
			return "Scale works on one object at a time"
		if sel is CubeModelNode:
			return "Cube objects are resized in build mode (E)"
		if sel is RampNode and not (sel as RampNode).frozen.is_empty():
			return "Unlock the ramp's sections to scale it"
	return ""


## The handles' axes for an object: world axes to move, the object's own axes to scale.
func axes_of(o: Node3D) -> Basis:
	if mode != Mode.SCALE:
		return Basis.IDENTITY
	if o is BlockNode:
		return BlockShape.basis_of(BlockShape.spec((o as BlockNode).data)).orthonormalized()
	if o is EntityNode:
		return Basis(Vector3.UP, deg_to_rad((o as EntityNode).yaw))
	if o is ParticleNode:
		return Basis(Vector3.UP, deg_to_rad(float((o as ParticleNode).data["yaw"])))
	if o is LightNode:
		return LightNode.basis_of(LightNode.spec((o as LightNode).data)).orthonormalized()
	return Basis.IDENTITY


## The rings an object can turn about: [[id, axis]]. "rv" turns about the line of sight.
func rings_of(o: Node3D, pane: ViewPane) -> Array:
	var out := [["r1", Vector3.UP]]
	if multi():
		return out
	if o is BlockNode or o is TextNode:
		out = [["r0", Vector3.RIGHT], ["r1", Vector3.UP], ["r2", Vector3.BACK]]
		if not pane.is_ortho():
			out.append(["rv", toward_viewer(pane, center())])
	elif (o is LightNode and String((o as LightNode).data["kind"]) != "point") or (o is EntityNode and (o as EntityNode).kind == "booster"):
		var yaw: float = float((o as LightNode).data["yaw"]) if o is LightNode else (o as EntityNode).yaw
		out.append(["r0", Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT])   # (pitch: the tilt of the beam / push)
	if pane.is_ortho():                          # a flat view can only turn about the axis it looks along
		var look := toward_viewer(pane, center())
		out = out.filter(func(r: Array) -> bool: return absf((r[1] as Vector3).dot(look)) > 0.9)
	return out


func toward_viewer(pane: ViewPane, p: Vector3) -> Vector3:
	if pane.is_ortho():
		return pane.camera.global_basis.z
	return (pane.camera.global_position - p).normalized()


## Meters per screen pixel at a point.
func world_per_px(pane: ViewPane, p: Vector3) -> float:
	var h := maxf(pane.size.y, 1.0)
	var cam := pane.camera
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return cam.size / h
	var depth := -(cam.global_transform.affine_inverse() * p).z
	return maxf(depth, 0.05) * 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / h


func length(pane: ViewPane) -> float:
	return SIZE_PX * world_per_px(pane, center())


## Every handle in this view: {id, kind ("center", "axis", "plane", "ring"), color, axis, pts (screen polygon or
## polyline), tip / base (axis), radius (ring)}.
func handles(pane: ViewPane) -> Array:
	var sel := target()
	if sel == null or unsupported() != "":
		return []
	var cam := pane.camera
	var c := center()
	if cam.is_position_behind(c):
		return []
	var c2 := cam.unproject_position(c)
	var L := length(pane)
	var look := toward_viewer(pane, c)
	var out := []
	if mode == Mode.ROTATE:
		out.append({"id": "ball", "kind": "ball", "radius": SIZE_PX})
		for r in rings_of(sel, pane):
			var ax: Vector3 = r[1]
			var col: Color = VIEW_RING_COLOR if r[0] == "rv" else AXIS_COLORS[int(String(r[0])[1])]
			var rad: float = L * (1.18 if r[0] == "rv" else 1.0)
			var pts := PackedVector2Array()
			var front := []
			var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
			var v := ax.cross(u)
			for k in 65:
				var a := TAU * k / 64.0
				var p := c + (u * cos(a) + v * sin(a)) * rad
				if cam.is_position_behind(p):
					pts.clear()
					break
				pts.append(cam.unproject_position(p))
				front.append(r[0] == "rv" or (p - c).dot(look) >= -0.02 * rad)
			if pts.size() > 0:
				out.append({"id": r[0], "kind": "ring", "color": col, "axis": ax, "pts": pts, "front": front,
					"radius": rad / world_per_px(pane, c)})
		return out
	var axes := axes_of(sel)
	var cube := mode == Mode.SCALE
	for i in 3:
		var ax: Vector3 = axes[i]
		if absf(ax.dot(look)) > (0.9 if pane.is_ortho() else 0.97):
			continue                                   # (pointing at the camera: nothing to grab)
		var tip := c + ax * L
		if cam.is_position_behind(tip):
			continue
		out.append({"id": ("s" if cube else "m") + str(i), "kind": "axis", "color": AXIS_COLORS[i], "axis": ax,
			"base": c2, "tip": cam.unproject_position(tip), "head": _head(cam, c, ax, L, cube)})
	if not pane.is_ortho():
		for i in 3:
			var n: Vector3 = axes[i]
			if absf(n.dot(look)) < 0.2:
				continue                               # (seen edge-on)
			var a1: Vector3 = axes[(i + 1) % 3]
			var a2: Vector3 = axes[(i + 2) % 3]
			var s0 := L * 0.28
			var s1 := L * 0.44
			var quad := PackedVector2Array()
			for q in [a1 * s0 + a2 * s0, a1 * s1 + a2 * s0, a1 * s1 + a2 * s1, a1 * s0 + a2 * s1]:
				if cam.is_position_behind(c + q):
					quad.clear()
					break
				quad.append(cam.unproject_position(c + q))
			if quad.size() == 4:
				out.append({"id": ("q" if cube else "p") + str(i), "kind": "plane", "color": AXIS_COLORS[i], "axis": n, "pts": quad})
	out.append({"id": "u" if cube else "c", "kind": "center", "pos": c2, "color": Color(0.95, 0.95, 0.95)})
	return out


## A cone (move) or a cube (scale) at the end of an axis, as one screen polygon.
func _head(cam: Camera3D, c: Vector3, ax: Vector3, L: float, cube: bool) -> PackedVector2Array:
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := ax.cross(u)
	var pts := PackedVector2Array()
	if cube:
		var h := L * 0.07
		var m := c + ax * L
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p: Vector3 = m + (ax * sx + u * sy + v * sz) * h
					if not cam.is_position_behind(p):
						pts.append(cam.unproject_position(p))
	else:
		var base := c + ax * L * 0.78
		var r := L * 0.08
		if not cam.is_position_behind(c + ax * L * 1.08):
			pts.append(cam.unproject_position(c + ax * L * 1.08))
		for k in 12:
			var a := TAU * k / 12.0
			var p: Vector3 = base + (u * cos(a) + v * sin(a)) * r
			if not cam.is_position_behind(p):
				pts.append(cam.unproject_position(p))
	return Geometry2D.convex_hull(pts) if pts.size() >= 3 else PackedVector2Array()


# ================================================================================================= drawing
func draw(pane: ViewPane, ov: Control) -> void:
	var sel := target()
	if sel == null:
		return
	var why := unsupported()
	if why != "":
		var c := sel.call("center") as Vector3
		if not pane.camera.is_position_behind(c):
			var font := ov.get_theme_default_font()
			var at := pane.camera.unproject_position(c) + Vector2(14, -14)
			ov.draw_string_outline(font, at, why, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
			ov.draw_string(font, at, why, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.5))
		return
	var hs := handles(pane)
	for h in hs:                                         # the ball and planes underneath, axes and rings on top
		if h["kind"] == "ball":
			var c2 := pane.camera.unproject_position(center())
			ov.draw_circle(c2, float(h["radius"]), Color(1, 1, 1, 0.1))
			ov.draw_arc(c2, float(h["radius"]), 0.0, TAU, 64, Color(1, 1, 1, 0.35), 1.5, true)
			ov.draw_circle(c2, 2.5, Color(1, 1, 1, 0.9))
		elif h["kind"] == "plane":
			var col: Color = _shade(h)
			col.a = 0.85 if _lit(h) else 0.55
			ov.draw_colored_polygon(h["pts"], col)
			var loop: PackedVector2Array = (h["pts"] as PackedVector2Array).duplicate()
			loop.append(loop[0])
			ov.draw_polyline(loop, Color(0, 0, 0, 0.45), 1.0, true)
	for h in hs:
		match String(h["kind"]):
			"axis":
				var col := _shade(h)
				var w := 3.5 if _lit(h) else 2.0
				ov.draw_line(h["base"], h["tip"], Color(0, 0, 0, 0.45), w + 2.0, true)
				ov.draw_line(h["base"], h["tip"], col, w, true)
				var head: PackedVector2Array = h["head"]
				if head.size() >= 3:
					ov.draw_colored_polygon(head, col)
					var loop := head.duplicate()
					loop.append(loop[0])
					ov.draw_polyline(loop, col.darkened(0.45), 1.0, true)
			"ring":
				var pts: PackedVector2Array = h["pts"]
				var front: Array = h["front"]
				var col := _shade(h)
				var w := 4.0 if _lit(h) else 2.5
				for k in range(1, pts.size()):
					var f: bool = front[k] and front[k - 1]
					var c := col if f else Color(col.r, col.g, col.b, 0.3)
					ov.draw_line(pts[k - 1], pts[k], c, w if f else 1.5, true)
			"center":
				var p: Vector2 = h["pos"]
				var r := 6.5 if _lit(h) else 5.0
				if mode == Mode.SCALE:
					ov.draw_rect(Rect2(p - Vector2(r + 1.5, r + 1.5), Vector2(r + 1.5, r + 1.5) * 2.0), Color(0, 0, 0, 0.6), true)
					ov.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), _shade(h), true)
				else:
					ov.draw_circle(p, r + 1.5, Color(0, 0, 0, 0.6))
					ov.draw_circle(p, r, _shade(h))


## A side square at `p` would sit on one of the gizmo's own handles (it's then neither drawn nor picked).
func covers(pane: ViewPane, p: Vector2) -> bool:
	for h in handles(pane):
		match String(h["kind"]):
			"center":
				if (h["pos"] as Vector2).distance_to(p) < 14.0:
					return true
			"axis":
				var head: PackedVector2Array = h["head"]
				if (h["tip"] as Vector2).distance_to(p) < 14.0 or (head.size() >= 3 and Geometry2D.is_point_in_polygon(p, head)):
					return true
			"plane":
				if Geometry2D.is_point_in_polygon(p, h["pts"]):
					return true
	return false


func _lit(h: Dictionary) -> bool:
	return h["id"] == active or (active == "" and h["id"] == hover)


func _shade(h: Dictionary) -> Color:
	var col: Color = h["color"]
	return col.lightened(0.55) if _lit(h) else col


# ================================================================================================= picking
## The handle under the mouse in this view, or "".
func pick(pane: ViewPane, mouse: Vector2) -> String:
	var best := ""
	var best_d := PICK_PX
	var hs := handles(pane)
	for h in hs:                                         # the center first (it sits where the axes meet)
		if h["kind"] == "center" and (h["pos"] as Vector2).distance_to(mouse) <= PICK_PX + 1.0:
			return h["id"]
	for h in hs:
		var d := INF
		match String(h["kind"]):
			"axis":
				d = Geometry2D.get_closest_point_to_segment(mouse, h["base"], h["tip"]).distance_to(mouse)
				var head: PackedVector2Array = h["head"]
				if head.size() >= 3 and Geometry2D.is_point_in_polygon(mouse, head):
					d = 0.0
			"plane":
				if Geometry2D.is_point_in_polygon(mouse, h["pts"]):
					d = 1.0                              # (an axis right on top of it still wins)
			"ring":
				var pts: PackedVector2Array = h["pts"]
				var front: Array = h["front"]
				for k in range(1, pts.size()):
					var dd := Geometry2D.get_closest_point_to_segment(mouse, pts[k - 1], pts[k]).distance_to(mouse)
					if not (front[k] and front[k - 1]):
						dd += 3.0                        # (the far side of the ball: only when nothing is nearer)
					d = minf(d, dd)
		if d < best_d:
			best_d = d
			best = h["id"]
	return best


## Where a handle can be grabbed on screen (for tests and the guide's pictures).
func grab_point(pane: ViewPane, id: String) -> Vector2:
	for h in handles(pane):
		if h["id"] != id:
			continue
		match String(h["kind"]):
			"axis": return (h["base"] as Vector2).lerp(h["tip"], 0.9)
			"center": return h["pos"]
			"plane":
				var c := Vector2.ZERO
				for p in h["pts"]:
					c += p
				return c / 4.0
			"ring":
				var pts: PackedVector2Array = h["pts"]
				var front: Array = h["front"]
				var c2 := pane.camera.unproject_position(center())
				var best := pts[0]
				var best_len := -1.0
				for k in pts.size():                     # the front point that sits furthest out on screen
					if front[k] and pts[k].distance_to(c2) > best_len:
						best_len = pts[k].distance_to(c2)
						best = pts[k]
				return best
	return Vector2(-1, -1)


func set_hover(pane: ViewPane, mouse: Vector2) -> void:
	hover = pick(pane, mouse)
	hover_pane = pane if hover != "" else null


func set_mode(m: int) -> void:
	mode = m as Mode
	hover = ""


# ================================================================================================= dragging
## Starts dragging handle `id` (never "c": the editor's own free drag does that). False if nothing can be dragged.
func begin(pane: ViewPane, mouse: Vector2, id: String) -> bool:
	var sel := target()
	if sel == null or id == "" or id == "ball" or ed.call("_deny_locked"):
		return false
	_pane = pane
	active = id
	_m0 = mouse
	_c0 = center()
	_axes = axes_of(sel)
	_point = ramp_point()
	_applied_move = Vector3.ZERO
	_applied_deg = 0.0
	_turned = 0.0
	ed.call("_settle_ramps")
	_origins = {}
	_ramp_points = {}
	_pivot = Vector3.ZERO
	var objs: Array = ed.selection()
	for o in objs:
		_origins[o] = o.call("to_dict")
		_pivot += o.call("center") as Vector3
		if o is RampNode:
			_ramp_points[o] = (o as RampNode).points.duplicate()
	_pivot /= maxf(objs.size(), 1)
	if _point >= 0:
		_point0 = (sel as RampNode).points[_point]
	var kind := id[0]
	var r := pane.ray(mouse)
	if kind in ["m", "s"]:
		_axis = _axes[int(id[1])]
		_t0 = _line_param(r[0], r[1], _c0, _axis)
		if kind == "s" and absf(_t0) < 1e-4:
			_t0 = length(pane)
	elif kind in ["p", "q"]:
		_axis = _axes[int(id[1])]
		var hit = Plane(_axis, _c0).intersects_ray(r[0], r[1])
		if hit == null:
			active = ""
			return false
		_hit0 = hit
	elif kind == "r":
		var ring: Array = []
		for rr in rings_of(sel, pane):
			if rr[0] == id:
				ring = rr
		if ring.is_empty():
			active = ""
			return false
		_axis = ring[1]
		var c2 := pane.camera.unproject_position(_c0)
		_ang0 = (mouse - c2).angle()
		var look := toward_viewer(pane, _c0)
		_flip = 1.0 if _axis.dot(look) >= 0.0 else -1.0
		_tangent = Vector2.ZERO
		_ring_px = SIZE_PX
		if absf(_axis.dot(look)) < 0.3:                  # seen nearly edge-on: turn by dragging along the ring
			var g := _ring_point_near(pane, mouse)
			var t3 := _axis.cross(g - _c0).normalized() * length(pane) * 0.1
			_tangent = (pane.camera.unproject_position(g + t3) - pane.camera.unproject_position(g)).normalized()
	ed.set("_drag_moved", false)
	return true


func _ring_point_near(pane: ViewPane, mouse: Vector2) -> Vector3:
	var u := _axis.cross(Vector3.UP if absf(_axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := _axis.cross(u)
	var L := length(pane)
	var best := _c0 + u * L
	var best_d := INF
	for k in 64:
		var a := TAU * k / 64.0
		var p := _c0 + (u * cos(a) + v * sin(a)) * L
		var d := pane.camera.unproject_position(p).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = p
	return best


## How far along the line (c, a) the mouse ray passes closest, meters from c.
static func _line_param(o: Vector3, d: Vector3, c: Vector3, a: Vector3) -> float:
	var b := a.dot(d)
	var denom := 1.0 - b * b
	if denom < 1e-6:
		return 0.0
	var w0 := c - o
	return (b * d.dot(w0) - a.dot(w0)) / denom


func drag(mouse: Vector2) -> void:
	if active == "" or _pane == null:
		return
	var kind := active[0]
	if kind in ["m", "p"]:
		_drag_move(mouse)
	elif kind == "r":
		_drag_rotate(mouse)
	else:
		_drag_scale(mouse)


func end() -> void:
	active = ""
	_pane = null


## The first real movement makes the undo step (the objects are still as they were).
func _first_move(changed: bool) -> bool:
	if not changed:
		return false
	if not ed.get("_drag_moved"):
		ed.call("_checkpoint")
		ed.set("_drag_moved", true)
	return true


func _snap() -> bool:
	return ed.snap_enabled


# ---------------------------------------------------------------------------------------------------- move
func _drag_move(mouse: Vector2) -> void:
	var r := _pane.ray(mouse)
	var delta := Vector3.ZERO
	if active[0] == "m":
		delta = _axis * (_line_param(r[0], r[1], _c0, _axis) - _t0)
	else:
		var hit = Plane(_axis, _c0).intersects_ray(r[0], r[1])
		if hit == null:
			return
		delta = (hit as Vector3) - _hit0
		delta -= _axis * delta.dot(_axis)
	delta = ed.call("_snap_axes", delta, Vector3.ONE)
	if not _first_move(not delta.is_equal_approx(_applied_move)):
		return
	var sel := target()
	if _point >= 0:
		var pts: PackedVector3Array = (sel as RampNode).points
		pts[_point] = _point0 + delta
		(sel as RampNode).points = pts
		(sel as RampNode).rebuild()
		ed.call("_set_status", "Point %d: (%.1f, %.1f, %.1f)" % [_point, pts[_point].x, pts[_point].y, pts[_point].z])
	else:
		var step := delta - _applied_move
		var any_block := false
		for o in ed.selection():
			if o is RampNode:
				(o as RampNode).shift(step)
			else:
				o.call("translate_by", step)
			any_block = any_block or o is BlockNode or o is TextNode
		if any_block:
			ed.call("_mark_blocks")
		ed.call("_set_status", "Moved by (%.1f, %.1f, %.1f)" % [delta.x, delta.y, delta.z])
	_applied_move = delta
	ed.call("_map_changed")
	ed.call("_refresh_info")


# ---------------------------------------------------------------------------------------------------- rotate
func _drag_rotate(mouse: Vector2) -> void:
	var deg := 0.0
	if _tangent != Vector2.ZERO:
		deg = rad_to_deg((mouse - _m0).dot(_tangent) / maxf(_ring_px, 1.0))
	else:
		var c2 := _pane.camera.unproject_position(_c0)
		if (mouse - c2).length() < 3.0:
			return
		var a := (mouse - c2).angle()
		_turned += wrapf(a - _ang0, -PI, PI)             # (keeps counting past half a turn: round and round turns further)
		_ang0 = a
		deg = -rad_to_deg(_turned) * _flip
	if _snap():
		deg = snappedf(deg, ROTATE_SNAP)
	if not _first_move(not is_equal_approx(deg, _applied_deg)):
		return
	var sel := target()
	var ring := active
	if (ring == "r1" and not (sel is BlockNode or sel is TextNode)) or multi():
		var step := deg - _applied_deg                   # turning about the vertical: every object's own yaw
		var objs: Array = ed.selection()
		if objs.size() == 1:
			sel.call("rotate_by", step)
		else:
			var b := Basis(Vector3.UP, deg_to_rad(step))
			for o in objs:
				var c: Vector3 = o.call("center")
				o.call("translate_by", _pivot + b * (c - _pivot) - c)
				o.call("rotate_by", step)
		if objs.any(func(o: Node3D) -> bool: return o is BlockNode or o is TextNode):
			ed.call("_mark_blocks")
	elif sel is BlockNode or sel is TextNode:            # every way: a new yaw / pitch / roll, turned about the middle
		var d0: Dictionary = _origins[sel]
		var s := BlockShape.spec(d0) if sel is BlockNode else TextShape.spec(d0)
		var b0 := Basis.from_euler(Vector3(deg_to_rad(float(s["pitch"])), deg_to_rad(float(s["yaw"])),
			deg_to_rad(float(s["roll"]))), EULER_ORDER_YXZ)
		var rot := Basis(_axis.normalized(), deg_to_rad(deg))
		var e := (rot * b0).get_euler(EULER_ORDER_YXZ)
		var d := d0.duplicate(true)
		d["pitch"] = snappedf(rad_to_deg(e.x), 0.001)
		d["yaw"] = snappedf(rad_to_deg(e.y), 0.001)
		d["roll"] = snappedf(rad_to_deg(e.z), 0.001)
		var p0 := Vector3(d0["position"][0], d0["position"][1], d0["position"][2])
		var p := _c0 + rot * (p0 - _c0)
		d["position"] = [p.x, p.y, p.z]
		sel.call("from_dict", d)
		ed.call("_mark_blocks")
	else:                                                # a spot light's or booster's tilt
		var d := (_origins[sel] as Dictionary).duplicate(true)
		d["pitch"] = clampf(float(d.get("pitch", 0.0)) + deg, -90.0, 90.0)
		sel.call("from_dict", d)
	_applied_deg = deg
	ed.call("_set_status", "Turned %+.0f°" % deg)
	ed.call("_map_changed")
	ed.call("_refresh_props")


# ---------------------------------------------------------------------------------------------------- scale
func _drag_scale(mouse: Vector2) -> void:
	var f := 1.0
	var kind := active[0]
	var r := _pane.ray(mouse)
	if kind == "s":
		f = _line_param(r[0], r[1], _c0, _axis) / _t0
	elif kind == "q":
		var hit = Plane(_axis, _c0).intersects_ray(r[0], r[1])
		if hit == null:
			return
		f = ((hit as Vector3) - _c0).length() / maxf((_hit0 - _c0).length(), 1e-3)
	else:
		var dm := mouse - _m0
		f = exp((dm.x - dm.y) / 150.0)
	f = maxf(f, 0.02)
	var fv := Vector3.ONE                                # the factor along each of the handles' axes
	if kind == "s":
		fv[int(active[1])] = f
	elif kind == "q":
		fv = Vector3.ONE * f
		fv[int(active[1])] = 1.0
	else:
		fv = Vector3.ONE * f
	var sel := target()
	if _snap() and (kind == "u" or not (sel is BlockNode or sel is EntityNode)):
		fv = Vector3(snappedf(fv.x, FACTOR_SNAP), snappedf(fv.y, FACTOR_SNAP), snappedf(fv.z, FACTOR_SNAP)).max(Vector3.ONE * FACTOR_SNAP)
		f = maxf(snappedf(f, FACTOR_SNAP), FACTOR_SNAP)
	var d := _scaled(sel, _origins[sel], fv, f, kind == "u")
	var key := str(d) + str(fv)
	if not ed.get("_drag_moved"):
		_last_key = str(_origins[sel]) + str(Vector3.ONE)
	if not _first_move(key != _last_key):
		return
	_last_key = key
	if sel is RampNode:
		var ramp := sel as RampNode
		var c := _c0
		var pts := PackedVector3Array()
		for p in (_ramp_points[sel] as PackedVector3Array):
			pts.append(c + (p - c) * fv)
		ramp.points = pts
		ramp.face_length = float(d["face_length"])
		ramp.face_length_right = float(d.get("face_length_right", ramp.face_length_right))
		ramp.rebuild()
	else:
		sel.call("from_dict", d)
		if sel is EntityNode:
			(sel as EntityNode).rebuild()
		if sel is BlockNode or sel is TextNode:
			ed.call("_mark_blocks")
	ed.call("_set_status", _size_text(sel))
	ed.call("_map_changed")
	ed.call("_refresh_props")
	ed.call("_refresh_info")


## The object's state scaled by `fv` along the handles' axes (`f`: the one factor, for objects that only scale evenly).
func _scaled(o: Node3D, d0: Dictionary, fv: Vector3, f: float, uniform: bool) -> Dictionary:
	var d := d0.duplicate(true)
	var grid := _snap() and not uniform
	if o is BlockNode or o is EntityNode:               # sized in meters: the change lands on the grid, like a side drag
		var sz0 := Vector3(d0["size"][0], d0["size"][1], d0["size"][2])
		var sz := sz0
		for i in 3:
			var amount := sz0[i] * (fv[i] - 1.0)
			if grid and not is_equal_approx(fv[i], 1.0):
				amount = snappedf(amount, ed.snap_step)
			sz[i] = maxf(sz0[i] + amount, 0.25)
		d["size"] = [sz.x, sz.y, sz.z]
		if o is BlockNode:                               # (a block stands on its base: keep its middle where it was)
			var b := BlockShape.basis_of(BlockShape.spec(d0))
			var p0 := Vector3(d0["position"][0], d0["position"][1], d0["position"][2])
			var mid := p0 + b * Vector3(0, sz0.y * 0.5, 0)
			var p := mid - b * Vector3(0, sz.y * 0.5, 0)
			d["position"] = [p.x, p.y, p.z]
	elif o is ParticleNode:
		var a: Array = d0["area"]
		d["area"] = [maxf(a[0] * fv.x, ParticleNode.MIN_AREA), maxf(a[1] * fv.y, ParticleNode.MIN_AREA), maxf(a[2] * fv.z, ParticleNode.MIN_AREA)]
	elif o is PropNode:
		d["size"] = maxf(float(d0.get("size", 1.0)) * f, 0.01)
	elif o is TextNode:
		d["height"] = maxf(float(d0.get("height", 4.0)) * f, 0.1)
		d["depth"] = maxf(float(d0.get("depth", 0.6)) * f, 0.05)
	elif o is LightNode:
		if String(d0.get("kind", "")) == "strip" and active == "s0":
			d["length"] = maxf(float(d0.get("length", 4.0)) * f, 0.25)
		else:
			d["range"] = maxf(float(d0.get("range", 30.0)) * f, 0.5)
	elif o is RampNode:
		var even := minf(minf(fv.x, fv.y), fv.z) if uniform else 1.0
		d["face_length"] = maxf(float(d0.get("face_length", 10.5)) * even, 0.5)
		if d0.has("face_length_right"):
			d["face_length_right"] = maxf(float(d0["face_length_right"]) * even, 0.5)
	return d


func _size_text(o: Node3D) -> String:
	if o is BlockNode:
		var s := (o as BlockNode).size()
		return "Size %.2f x %.2f x %.2f m" % [s.x, s.y, s.z]
	if o is EntityNode:
		var s := (o as EntityNode).size
		return "Size %.2f x %.2f x %.2f m" % [s.x, s.y, s.z]
	if o is ParticleNode:
		var a: Array = (o as ParticleNode).data["area"]
		return "Area %.2f x %.2f x %.2f m" % [a[0], a[1], a[2]]
	if o is PropNode:
		return "Scale %.2f" % (o as PropNode).size
	if o is TextNode:
		return "Letters %.2f m tall" % float((o as TextNode).data["height"])
	if o is LightNode:
		var ld: Dictionary = (o as LightNode).data
		return ("Strip %.2f m long" % float(ld["length"])) if active == "s0" and ld["kind"] == "strip" else ("Reach %.1f m" % float(ld["range"]))
	if o is RampNode:
		return "Ramp %.0f m long" % (o as RampNode).length
	return ""
