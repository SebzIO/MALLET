class_name CubeModelNode
extends Node3D
## A cube object: cubes built in build mode, on the object's own grid. In the editor it's one object you can select,
## move, turn, copy, group and save as a prefab; in build mode you edit it cube by cube (wherever it's been moved to).
## Its mesh and collision are rebuilt per 16 m chunk as soon as something in a chunk changes.

const PICK_ONLY_LAYER := 1 << 19

const REBUILD_MS := 6.0                  ## (rebuild_dirty's optional per-frame budget)
const SYNC_CUBES := 3000                 ## changed chunks holding up to this many cubes are redrawn in the frame
var _bg_keys: Array = []                 ## chunks being redrawn in the background
var _bg_res: Array = []                  ## ...their results (chunk_arrays) as they finish
var _bg_ready: Array = []                ## finished [chunk, arrays] waiting to go in, a few a frame
const APPLY_MS := 6.0                    ## per frame, putting finished background chunks in
static var outline_mode := false         ## build mode's "7": draw every cube's edges

var world := CubeWorld.new()
var yaw := 0.0                           ## degrees
var _chunks := {}                        ## Vector3i -> [MeshInstance3D, StaticBody3D, CollisionShape3D, MeshInstance3D outline]
var _selected := false


func _ready() -> void:
	rebuild_all()


func _process(_delta: float) -> void:
	_poll_background()
	if world.dirty.is_empty() or _bg_keys.size() > 0 or not _bg_ready.is_empty():
		return
	var n := 0
	for ck in world.dirty:
		n += (world._render.get(ck, {}) as Dictionary).size()
	if n <= SYNC_CUBES:
		rebuild_dirty()                                  # (small changes: right away, in this frame)
	else:
		_start_background()                              # (big ones: on every core, while MALLET keeps running)


## Redraw the changed chunks on worker threads; _poll_background swaps the results in when they're done.
func _start_background() -> void:
	MaterialLibrary.entries()                            # (loaded here: workers only read it)
	for o in 6:
		CubeWorld.face_corners(o)
	_bg_keys = world.dirty.keys()
	world.dirty.clear()
	_bg_res = []
	_bg_res.resize(_bg_keys.size())
	var keys := _bg_keys
	var res := _bg_res
	var w := world
	world.reading_task = WorkerThreadPool.add_group_task(func(i: int):
		res[i] = w.chunk_arrays(keys[i], false, true, false), keys.size())


## Finished background work goes in a few chunks a frame (APPLY_MS), nearest first; `all` puts it all in now.
func _poll_background(all := false) -> void:
	if not _bg_keys.is_empty() and (world.reading_task < 0 or WorkerThreadPool.is_group_task_completed(world.reading_task)):
		world.finish_reading()
		for i in _bg_keys.size():
			if _bg_res[i] != null:
				_bg_ready.append([_bg_keys[i], _bg_res[i]])
		_bg_keys = []
		_bg_res = []
		_sort_nearest(_bg_ready)
	var t0 := Time.get_ticks_usec()
	while not _bg_ready.is_empty():
		var r: Array = _bg_ready.pop_front()
		if not world.dirty.has(r[0]):                    # (changed again since: its newer redraw is on the way)
			_apply_chunk(r[0], world.chunk_build(r[0], r[1]))
		if not all and (Time.get_ticks_usec() - t0) / 1000.0 > APPLY_MS:
			break


func _sort_nearest(list: Array) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or list.size() < 2:
		return
	var eye := to_local(cam.global_position) / CubeWorld.TICK
	var half := Vector3.ONE * CubeWorld.RENDER_TICKS * 0.5
	list.sort_custom(func(a: Array, b: Array) -> bool:
		return (Vector3(a[0]) * CubeWorld.RENDER_TICKS + half).distance_squared_to(eye) < (Vector3(b[0]) * CubeWorld.RENDER_TICKS + half).distance_squared_to(eye))


func _exit_tree() -> void:
	world.finish_reading()                               # (never leave a task reading a world that may be freed)


func label() -> String:
	return "Cube object"


func rebuild_all() -> void:
	for ck in world.render_chunks():
		world.dirty[ck] = true
	for ck in _chunks:
		world.dirty[ck] = true
	rebuild_dirty()


## Redraw the chunks that changed. With `budget_ms`, stop once that much of this frame is used (at least one chunk) and
## leave the rest for the next frames, the chunks nearest the camera first.
func rebuild_dirty(budget_ms := -1.0) -> void:
	world.finish_reading()
	_poll_background(true)
	if world.dirty.is_empty() or not is_inside_tree():
		return
	var keys := world.dirty.keys()
	if budget_ms > 0.0 and keys.size() > 1:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var eye := to_local(cam.global_position) / CubeWorld.TICK
			var half := Vector3.ONE * CubeWorld.RENDER_TICKS * 0.5
			keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
				return (Vector3(a) * CubeWorld.RENDER_TICKS + half).distance_squared_to(eye) < (Vector3(b) * CubeWorld.RENDER_TICKS + half).distance_squared_to(eye))
	var t0 := Time.get_ticks_usec()
	for ck in keys:
		world.dirty.erase(ck)
		_rebuild(ck)
		if budget_ms > 0.0 and (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break


func _rebuild(ck: Vector3i) -> void:
	_apply_chunk(ck, world.chunk_mesh(ck, false, true))  # (outlines are always made with the mesh: 7 only shows or hides them)


func _apply_chunk(ck: Vector3i, got: Array) -> void:
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
