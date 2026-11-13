class_name TextNode
extends Node3D
## Text in the map: a flat sign or solid 3D letters.

const PICK_ONLY_LAYER := 1 << 19

var data := TextShape.DEFAULTS.duplicate(true)
var _mesh := MeshInstance3D.new()
var _body := StaticBody3D.new()
var local_box := AABB()

signal pieces_ready


func _ready() -> void:
	add_child(_mesh)
	_body.set_meta("text", self)
	_body.collision_mask = 0
	add_child(_body)


func label() -> String:
	return "Text"


func rebuild() -> void:
	var s := TextShape.spec(data)
	var xf := TextShape.transform_of(s)
	transform = xf
	_mesh.mesh = TextShape.mesh(s)
	local_box = _mesh.mesh.get_aabb()
	_mesh.material_override = TextShape.material(s)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if s["mode"] == "3d" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_collision(s)


## Collision from the letters' convex pieces (solid 3D letters stand on them; otherwise they're for clicking). Splitting
## letters into convex pieces takes a moment for long text, so it happens on a worker thread: until it's done, a
## box around the text stands in.
func _build_collision(s: Dictionary) -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var unit = TextShape.cached_unit_polygons(s)
	if unit == null:
		var box := BoxShape3D.new()
		box.size = local_box.size.max(Vector3.ONE * 0.05)
		var cs0 := CollisionShape3D.new()
		cs0.shape = box
		cs0.position = local_box.get_center()
		_body.add_child(cs0)
		_request_pieces(s)
	else:
		var h := float(s["height"])
		var d := maxf(TextShape.depth_of(s), 0.05)
		for poly in unit:
			var pts := PackedVector3Array()
			for p in poly:
				pts.append(Vector3(p.x * h, p.y * h, 0.0))
				pts.append(Vector3(p.x * h, p.y * h, d))
			var shape := ConvexPolygonShape3D.new()
			shape.points = pts
			var cs := CollisionShape3D.new()
			cs.shape = shape
			_body.add_child(cs)
	_body.collision_layer = 1 if s["mode"] == "3d" and bool(s["solid"]) else PICK_ONLY_LAYER


## True while the letters' convex pieces are still being worked out.
func pieces_pending() -> bool:
	return TextShape.cached_unit_polygons(TextShape.spec(data)) == null


var _working := false
var _wanted := {}
## Worker tasks started and not yet collected. A finished task Godot was never asked about keeps its function (and
## this script's code) until shutdown, and freeing it then, after the scripts are gone, crashed every quit after a
## text sign was made (signal 11). Collected on the main thread as each one reports back, and at exit.
static var _tasks: Array[int] = []


func _request_pieces(s: Dictionary) -> void:
	_wanted = s.duplicate(true)
	if _working:
		return                                           # the one running now will start the latest when it's done
	_working = true
	var sd: Dictionary = _wanted
	var me: WeakRef = weakref(self)
	_tasks.append(WorkerThreadPool.add_task(func():
		var polys := TextShape.unit_polygons(sd)
		TextNode._pieces_done.call_deferred(me, sd, polys)))


## Collect the worker tasks that have finished (or, with `all`, wait for every one: when MALLET closes).
static func collect_tasks(all := false) -> void:
	for t in _tasks.duplicate():
		if all or WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_tasks.erase(t)


static func _pieces_done(me: WeakRef, sd: Dictionary, polys: Array) -> void:
	collect_tasks()
	TextShape.store_unit_polygons(sd, polys)
	var node: TextNode = me.get_ref()
	if node == null:
		return
	node._working = false
	var now := TextShape.spec(node.data)
	if TextShape.cached_unit_polygons(now) == null:
		node._request_pieces(now)                        # typed on while that ran: do the latest
	elif node.is_inside_tree():
		node._build_collision(now)
		node.pieces_ready.emit()


func set_selected(_on: bool) -> void:
	pass


func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var c: Array[Vector3] = []
	for i in 8:
		c.append(global_transform * (local_box.position + local_box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append(PackedVector3Array([c[e[0]], c[e[1]]]))
	return out


func center() -> Vector3:
	return global_transform * local_box.get_center()


func translate_by(delta: Vector3) -> void:
	var p: Array = data["position"]
	data["position"] = [p[0] + delta.x, p[1] + delta.y, p[2] + delta.z]
	transform = TextShape.transform_of(TextShape.spec(data))


func rotate_by(deg: float) -> void:
	data["yaw"] = wrapf(float(data["yaw"]) + deg, -180.0, 180.0)
	transform = TextShape.transform_of(TextShape.spec(data))


func to_dict() -> Dictionary:
	var d := data.duplicate(true)
	var p: Array = d["position"]
	d["position"] = [snappedf(p[0], 0.001), snappedf(p[1], 0.001), snappedf(p[2], 0.001)]
	return d


func from_dict(d: Dictionary) -> void:
	data = TextShape.spec(d)
	transform = TextShape.transform_of(data)
	if is_inside_tree():
		rebuild()
