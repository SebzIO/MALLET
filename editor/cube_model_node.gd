class_name CubeModelNode
extends Node3D
## A cube object: cubes built in build mode, on the object's own grid. In the editor it's one object you can select,
## move, turn, copy, group and save as a prefab; in build mode you edit it cube by cube (wherever it's been moved to).
## Its mesh and collision are rebuilt per 16 m chunk as soon as something in a chunk changes.

const PICK_ONLY_LAYER := 1 << 19

static var outline_mode := false         ## build mode's "7": draw every cube's edges

var world := CubeWorld.new()
var yaw := 0.0                           ## degrees
var _chunks := {}                        ## Vector3i -> [MeshInstance3D, StaticBody3D, CollisionShape3D, MeshInstance3D outline]
var _selected := false


func _ready() -> void:
	rebuild_all()


func _process(_delta: float) -> void:
	rebuild_dirty()


func label() -> String:
	return "Cube object"


func rebuild_all() -> void:
	for ck in world.render_chunks():
		world.dirty[ck] = true
	for ck in _chunks:
		world.dirty[ck] = true
	rebuild_dirty()


func rebuild_dirty() -> void:
	if world.dirty.is_empty() or not is_inside_tree():
		return
	var keys := world.dirty.keys()
	world.dirty.clear()
	for ck in keys:
		_rebuild(ck)


func _rebuild(ck: Vector3i) -> void:
	var got := world.chunk_mesh(ck, false, true)         # (outlines are always made with the mesh: 7 only shows or hides them)
	var mesh: ArrayMesh = got[0]
	var col: PackedVector3Array = got[1]
	if mesh.get_surface_count() == 0 and col.is_empty():
		if _chunks.has(ck):
			for n in _chunks[ck]:
				if n is MeshInstance3D or n is StaticBody3D:
					n.queue_free()
			_chunks.erase(ck)
		return
	if not _chunks.has(ck):
		var mi := MeshInstance3D.new()
		add_child(mi)
		var body := StaticBody3D.new()
		body.set_meta("cube_model", self)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		var lines := MeshInstance3D.new()
		lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lines)
		_chunks[ck] = [mi, body, cs, lines]
	var parts: Array = _chunks[ck]
	(parts[0] as MeshInstance3D).mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(col)
	shape.backface_collision = true
	(parts[2] as CollisionShape3D).shape = shape
	(parts[2] as CollisionShape3D).disabled = col.is_empty()
	(parts[3] as MeshInstance3D).mesh = got[2]
	(parts[3] as MeshInstance3D).visible = outline_mode


func set_outline(on: bool) -> void:
	if outline_mode == on:
		return
	outline_mode = on
	show_outlines()


## Show or hide the outlines already made with the mesh (no rebuilding).
func show_outlines() -> void:
	for ck in _chunks:
		(_chunks[ck][3] as MeshInstance3D).visible = outline_mode


func set_selected(on: bool) -> void:
	_selected = on


## Box outline for the editor's selection display.
func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	if world.count() == 0:
		return out
	var b := world.bounds()
	var c: Array[Vector3] = []
	for i in 8:
		c.append(global_transform * (b.position + b.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append(PackedVector3Array([c[e[0]], c[e[1]]]))
	return out


func center() -> Vector3:
	if world.count() == 0:
		return global_position
	return global_transform * world.bounds().get_center()


func translate_by(delta: Vector3) -> void:
	position += delta


## Turn about the object's center (keeps it in place on screen).
func rotate_by(deg: float) -> void:
	var c := center()
	yaw = wrapf(yaw + deg, -180.0, 180.0)
	basis = Basis(Vector3.UP, deg_to_rad(yaw))
	position += c - center()


func to_dict() -> Dictionary:
	return {"position": [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)],
		"yaw": snappedf(yaw, 0.001), "cubes": world.to_dict()}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("position", [0.0, 0.0, 0.0])
	position = Vector3(p[0], p[1], p[2])
	yaw = float(d.get("yaw", 0.0))
	basis = Basis(Vector3.UP, deg_to_rad(yaw))
	world.load_dict(d.get("cubes", {}))
	if is_inside_tree():
		rebuild_dirty()


## Lava and death material as kill volumes for play mode (the same interface as kill zones).
class KillBox:
	var kind := "kill"
	var xf: Transform3D
	var box: AABB

	func contains(p: Vector3) -> bool:
		return box.has_point(xf.affine_inverse() * p)


func kill_volumes() -> Array:
	var out := []
	var boxes := world.material_boxes()
	for m in ["lava", "death"]:
		for b in boxes.get(m, []):
			var kb := KillBox.new()
			kb.xf = global_transform
			kb.box = b
			out.append(kb)
	return out


## Show the invisible materials (clip, death...)? Off while playing, like Sauerbraten outside edit mode.
func set_show_mats(on: bool) -> void:
	if world.show_mats == on:
		return
	world.show_mats = on
	for ck in world.hidden_mat_chunks():                 # (only these look different: P and Esc must not re-mesh a whole object)
		world.dirty[ck] = true
	rebuild_dirty()


## A point in the world, in this object's grid (ticks).
func to_local_ticks(p: Vector3) -> Vector3:
	return (global_transform.affine_inverse() * p) / CubeWorld.TICK


## A direction in the world, in this object's axes.
func to_local_dir(v: Vector3) -> Vector3:
	return (global_basis.inverse() * v).normalized()
