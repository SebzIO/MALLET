class_name EntityNode
extends Node3D
## A placeable gameplay object.
##   Platforms (start, finish): `position` is the centre of the platform's top surface, where the player stands.
##   Volumes (kill zone, booster): `position` is the centre of the box. Players pass through them.

const KINDS := {
	"start": {"label": "Start platform", "size": Vector3(20, 2, 26), "color": Color(0.25, 0.75, 0.4), "zone": 10.0},
	"finish": {"label": "Finish platform", "size": Vector3(40, 2, 40), "color": Color(0.25, 0.5, 0.95), "zone": 10.0},
	"kill": {"label": "Kill zone", "size": Vector3(40, 20, 40), "color": Color(0.95, 0.15, 0.15), "volume": true},
	"booster": {"label": "Booster", "size": Vector3(20, 12, 20), "color": Color(1.0, 0.8, 0.1), "volume": true},
}
## Volumes are pickable in the editor but must never block the player: their picking body lives on this layer only.
const PICK_ONLY_LAYER := 1 << 19

var kind := "start"
var size := Vector3(20, 2, 26)          ## width (x), height/thickness (y), depth (z) in metres
var yaw := 0.0                          ## degrees; start platform: spawn facing; booster: push direction
var strength := 1000.0                  ## booster: speed in u/s (SurfsUp units, 39.37 per metre)
var pitch := 20.0                       ## booster: degrees above horizontal the push points
var mode := 0                           ## booster: 0 = add to the player's speed, 1 = set it

var _mesh := MeshInstance3D.new()
var _zone_mesh := MeshInstance3D.new()
var _arrow := Node3D.new()
var _arrow_shaft := MeshInstance3D.new()
var _arrow_head := MeshInstance3D.new()
var _flat_arrow := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _mat := StandardMaterial3D.new()
var _zone_mat := StandardMaterial3D.new()
var _selected := false


static func create(k: String) -> EntityNode:
	var e := EntityNode.new()
	e.kind = k
	e.size = KINDS[k]["size"]
	return e


func is_volume() -> bool:
	return KINDS[kind].get("volume", false)


func _ready() -> void:
	_mat.roughness = 0.6
	_mesh.material_override = _mat
	add_child(_mesh)
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone_mesh.material_override = _zone_mat
	_zone_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_zone_mesh)
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.albedo_color = Color(1, 1, 1, 0.9)
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flat_arrow.material_override = am
	add_child(_flat_arrow)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1.0, 0.95, 0.5)
	_arrow_shaft.material_override = bm
	_arrow_head.material_override = bm
	_arrow.add_child(_arrow_shaft)
	_arrow.add_child(_arrow_head)
	add_child(_arrow)
	_body.add_child(_shape)
	_body.set_meta("entity", self)
	add_child(_body)
	rebuild()


func label() -> String:
	return KINDS[kind]["label"]


func rebuild() -> void:
	basis = Basis(Vector3.UP, deg_to_rad(yaw))
	var c: Color = KINDS[kind]["color"]
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	if is_volume():
		# a see-through box centred on `position`; the picking body never collides with the player
		var box := BoxMesh.new()
		box.size = size
		_mesh.mesh = box
		_mesh.position = Vector3.ZERO
		_shape.position = Vector3.ZERO
		_body.collision_layer = PICK_ONLY_LAYER
		_body.collision_mask = 0
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.no_depth_test = false
		_zone_mesh.visible = false
		_flat_arrow.visible = false
	else:
		var box := BoxMesh.new()
		box.size = size
		_mesh.mesh = box
		_mesh.position = Vector3(0, -size.y / 2, 0)
		_shape.position = _mesh.position
		_body.collision_layer = 1
		_body.collision_mask = 1
		var zh: float = KINDS[kind]["zone"]
		var zone := BoxMesh.new()
		zone.size = Vector3(size.x, zh, size.z)
		_zone_mesh.mesh = zone
		_zone_mesh.position = Vector3(0, zh / 2, 0)
		_zone_mesh.visible = true
		_zone_mat.albedo_color = Color(c.r, c.g, c.b, 0.12)
		# arrow on the start platform showing which way the player will face
		_flat_arrow.visible = kind == "start"
		if kind == "start":
			var pm := PrismMesh.new()
			pm.size = Vector3(min(size.x, size.z) * 0.5, min(size.x, size.z) * 0.6, 0.2)
			_flat_arrow.mesh = pm
			_flat_arrow.position = Vector3(0, 0.15, 0)
			_flat_arrow.rotation = Vector3(-PI / 2, 0, 0)     # lay it flat, pointing towards -Z (forward)
	# booster: a 3D arrow along the push direction
	_arrow.visible = kind == "booster"
	if kind == "booster":
		var length: float = clamp(min(size.x, size.z) * 0.8, 4.0, 40.0)
		var shaft := CylinderMesh.new()
		shaft.top_radius = length * 0.06
		shaft.bottom_radius = length * 0.06
		shaft.height = length * 0.7
		_arrow_shaft.mesh = shaft
		_arrow_shaft.position = Vector3(0, -length * 0.15, 0)
		var head := CylinderMesh.new()
		head.top_radius = 0.0
		head.bottom_radius = length * 0.16
		head.height = length * 0.3
		_arrow_head.mesh = head
		_arrow_head.position = Vector3(0, length * 0.35, 0)
		var local_dir := Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Vector3.FORWARD      # -Z tipped up by pitch
		_arrow.basis = Basis(Quaternion(Vector3.UP, local_dir.normalized()))
	_update_material()


func set_selected(on: bool) -> void:
	_selected = on
	_update_material()


func _update_material() -> void:
	var c: Color = KINDS[kind]["color"]
	_mat.albedo_color = Color(c.r, c.g, c.b, 0.28) if is_volume() else c
	_mat.emission_enabled = false              # selection is shown with an outline


## Booster push direction in world space (unit vector).
func boost_direction() -> Vector3:
	return (Basis(Vector3.UP, deg_to_rad(yaw)) * (Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Vector3.FORWARD)).normalized()


## The object's box edges in world space (for the selection outline).
func outline_lines() -> Array[PackedVector3Array]:
	var h := size / 2
	var y0 := 0.0 if is_volume() else -h.y
	var out: Array[PackedVector3Array] = []
	var corners := {}
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				corners[Vector3i(x, y, z)] = global_transform * Vector3(x * h.x, y0 + y * h.y, z * h.z)
	for y in [-1, 1]:
		out.append(PackedVector3Array([corners[Vector3i(-1, y, -1)], corners[Vector3i(1, y, -1)], corners[Vector3i(1, y, 1)],
			corners[Vector3i(-1, y, 1)], corners[Vector3i(-1, y, -1)]]))
	for x in [-1, 1]:
		for z in [-1, 1]:
			out.append(PackedVector3Array([corners[Vector3i(x, -1, z)], corners[Vector3i(x, 1, z)]]))
	return out


## Platforms: world-space box the player must be inside (start: leaving it starts the timer; finish: entering it
## stops it).
func zone_aabb() -> AABB:
	var zh: float = KINDS[kind].get("zone", size.y)
	var corners := []
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			corners.append(global_transform * Vector3(size.x * x, 0, size.z * z))
	var box := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		box = box.expand(c)
	return AABB(box.position, Vector3(box.size.x, zh, box.size.z))


## Volumes: is the world point inside the (rotated) box?
func contains(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) <= size.x / 2 and absf(l.y) <= size.y / 2 and absf(l.z) <= size.z / 2


## Where (and facing which way) the player spawns on a start platform.
func spawn_transform() -> Transform3D:
	# stand towards the back of the platform (local +Z), facing forward (local -Z)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), global_transform * Vector3(0, 0.1, size.z * 0.25))


func to_dict() -> Dictionary:
	var d := {"kind": kind, "position": [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)],
		"size": [size.x, size.y, size.z], "yaw": yaw}
	if kind == "booster":
		d["strength"] = strength
		d["pitch"] = pitch
		d["mode"] = mode
	return d


func from_dict(d: Dictionary) -> void:
	kind = d.get("kind", "start")
	var p: Array = d.get("position", [0, 0, 0])
	position = Vector3(p[0], p[1], p[2])
	var s: Array = d.get("size", [20, 2, 26])
	size = Vector3(s[0], s[1], s[2])
	yaw = d.get("yaw", 0.0)
	strength = d.get("strength", 1000.0)
	pitch = d.get("pitch", 20.0)
	mode = d.get("mode", 0)
	if is_inside_tree():
		rebuild()


func center() -> Vector3:
	return position


func translate_by(delta: Vector3) -> void:
	position += delta


func rotate_by(deg: float) -> void:
	yaw = fposmod(yaw + deg + 180.0, 360.0) - 180.0
	rebuild()
