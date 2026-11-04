class_name PropNode
extends Node3D
## A piece of scenery imported from a glTF model (.glb / .gltf): placed, turned and sized in the editor, solid
## (players and jumps hit it) or decoration only, and exported with the map.

const PICK_ONLY_LAYER := 1 << 19        ## decoration: the editor can still click it, players fly through

var source := ""                        ## the model file on disk
var yaw := 0.0                          ## degrees
var size := 1.0                         ## uniform scale
var solid := true                       ## players collide with it (and the jump checker sees it)
var error := ""
var triangles := 0
var local_box := AABB()                 ## the scaled model's box in the prop's own space

var _visual := Node3D.new()
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _built_key := ""


func _ready() -> void:
	add_child(_visual)
	_body.add_child(_shape)
	_body.set_meta("prop", self)
	_body.collision_mask = 0
	add_child(_body)
	rebuild()


func rebuild() -> void:
	rotation = Vector3(0, deg_to_rad(yaw), 0)
	var key := "%s|%s|%s" % [source, size, solid]
	if key == _built_key:
		return                                          # only moved or turned: nothing to rebuild
	_built_key = key
	for c in _visual.get_children():
		c.queue_free()
	var data := PropLoader.load_model(source)
	error = data["error"]
	triangles = data["triangles"]
	var b := Basis().scaled(Vector3.ONE * size)
	if data["meshes"].is_empty():
		# stand-in so the prop can still be seen, picked and replaced
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4, 4, 4)
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.2, 0.8)
		mi.material_override = m
		mi.position.y = 2.0
		_visual.add_child(mi)
		local_box = AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4))
		var sh := BoxShape3D.new()
		sh.size = Vector3(4, 4, 4)
		_shape.shape = sh
		_shape.position.y = 2.0
		_body.collision_layer = PICK_ONLY_LAYER
		return
	for m in data["meshes"]:
		var mi := MeshInstance3D.new()
		mi.mesh = m[0]
		mi.transform = Transform3D(b, Vector3.ZERO) * (m[1] as Transform3D)
		_visual.add_child(mi)
	local_box = Transform3D(b, Vector3.ZERO) * (data["aabb"] as AABB)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(PropLoader.collision_faces(source, size))
	shape.backface_collision = true                     # models are often single-sided
	_shape.shape = shape
	_shape.position = Vector3.ZERO
	_body.collision_layer = 1 if solid else PICK_ONLY_LAYER


func label() -> String:
	return "Prop"


func set_selected(_on: bool) -> void:
	pass                                                # shown with the outline only


## The 12 edges of the prop's box, in world space.
func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var c: Array[Vector3] = []
	for i in 8:
		c.append(global_transform * (local_box.position + local_box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append(PackedVector3Array([c[e[0]], c[e[1]]]))
	return out


func world_size() -> Vector3:
	return local_box.size


func center() -> Vector3:
	return position


func translate_by(delta: Vector3) -> void:
	position += delta


func rotate_by(deg: float) -> void:
	yaw = wrapf(yaw + deg, -180.0, 180.0)
	rebuild()


func to_dict() -> Dictionary:
	return {"source": source, "position": [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)],
		"yaw": yaw, "size": size, "solid": solid}


func from_dict(d: Dictionary) -> void:
	source = d.get("source", "")
	var p: Array = d.get("position", [0, 0, 0])
	position = Vector3(p[0], p[1], p[2])
	yaw = d.get("yaw", 0.0)
	size = d.get("size", 1.0)
	solid = d.get("solid", true)
	if is_inside_tree():
		rebuild()
