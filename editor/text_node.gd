class_name TextNode
extends Node3D
## Text in the map: a flat sign or solid 3D letters.

const PICK_ONLY_LAYER := 1 << 19

var data := TextShape.DEFAULTS.duplicate(true)
var _mesh := MeshInstance3D.new()
var _body := StaticBody3D.new()
var local_box := AABB()


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
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	# collision: the letters' convex pieces (solid 3D letters); otherwise just for clicking in the editor
	var inv := xf.affine_inverse()
	var pcs := TextShape.pieces(s, 0.0, maxf(TextShape.depth_of(s), 0.05))
	for p in pcs:
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for v in Convex.points(p):
			pts.append(inv * v)
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_body.add_child(cs)
	_body.collision_layer = 1 if s["mode"] == "3d" and bool(s["solid"]) else PICK_ONLY_LAYER


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
