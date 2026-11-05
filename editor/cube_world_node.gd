class_name CubeWorldNode
extends Node3D
## The cubes in the editor: a mesh and collision (for building, picking and play-testing) per 16 m chunk, rebuilt
## as soon as something in a chunk changes.

var world := CubeWorld.new()
var _chunks := {}                        ## Vector3i -> [MeshInstance3D, StaticBody3D, CollisionShape3D]


func _process(_delta: float) -> void:
	rebuild_dirty()


func rebuild_dirty() -> void:
	if world.dirty.is_empty():
		return
	var keys := world.dirty.keys()
	world.dirty.clear()
	for ck in keys:
		_rebuild(ck)


func _rebuild(ck: Vector3i) -> void:
	var got := world.chunk_mesh(ck)
	var mesh: ArrayMesh = got[0]
	var col: PackedVector3Array = got[1]
	if mesh.get_surface_count() == 0:
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
		body.set_meta("cubes", self)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var cs := CollisionShape3D.new()
		body.add_child(cs)
		_chunks[ck] = [mi, body, cs]
	var parts: Array = _chunks[ck]
	(parts[0] as MeshInstance3D).mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(col)
	shape.backface_collision = true                     # (one-sided triangles depend on winding: be safe)
	(parts[2] as CollisionShape3D).shape = shape


func load_dict(data: Dictionary) -> void:
	world.load_dict(data)
	rebuild_dirty()


func chunk_count() -> int:
	return _chunks.size()
