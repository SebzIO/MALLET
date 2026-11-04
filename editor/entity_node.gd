class_name EntityNode
extends Node3D
## A placeable gameplay object: start platform, finish platform (boosters, kill boxes etc. later).
## `position` is the centre of the platform's top surface, where the player stands.

const KINDS := {
	"start": {"label": "Start platform", "size": Vector3(20, 2, 26), "color": Color(0.25, 0.75, 0.4), "zone": 10.0},
	"finish": {"label": "Finish platform", "size": Vector3(40, 2, 40), "color": Color(0.9, 0.3, 0.25), "zone": 10.0},
}

var kind := "start"
var size := Vector3(20, 2, 26)          ## platform width (x), thickness (y), depth (z) in metres
var yaw := 0.0                          ## degrees; the start platform's spawn faces this way

var _mesh := MeshInstance3D.new()
var _zone_mesh := MeshInstance3D.new()
var _arrow := MeshInstance3D.new()
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
	_arrow.material_override = am
	add_child(_arrow)
	_body.add_child(_shape)
	_body.set_meta("entity", self)
	add_child(_body)
	rebuild()


func label() -> String:
	return KINDS[kind]["label"]


func rebuild() -> void:
	basis = Basis(Vector3.UP, deg_to_rad(yaw))
	var box := BoxMesh.new()
	box.size = size
	_mesh.mesh = box
	_mesh.position = Vector3(0, -size.y / 2, 0)
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	_shape.position = _mesh.position
	var zh: float = KINDS[kind]["zone"]
	var zone := BoxMesh.new()
	zone.size = Vector3(size.x, zh, size.z)
	_zone_mesh.mesh = zone
	_zone_mesh.position = Vector3(0, zh / 2, 0)
	var c: Color = KINDS[kind]["color"]
	_zone_mat.albedo_color = Color(c.r, c.g, c.b, 0.12)
	# arrow on the start platform showing which way the player will face
	_arrow.visible = kind == "start"
	if kind == "start":
		var pm := PrismMesh.new()
		pm.size = Vector3(min(size.x, size.z) * 0.5, min(size.x, size.z) * 0.6, 0.2)
		_arrow.mesh = pm
		_arrow.position = Vector3(0, 0.15, 0)
		_arrow.rotation = Vector3(-PI / 2, 0, 0)          # lay it flat, pointing towards -Z (forward)
	_update_material()


func set_selected(on: bool) -> void:
	_selected = on
	_update_material()


func _update_material() -> void:
	_mat.albedo_color = KINDS[kind]["color"]
	_mat.emission_enabled = _selected
	_mat.emission = Color(0.15, 0.35, 0.9)
	_mat.emission_energy_multiplier = 0.45


## World-space box the player must be inside (start: leaving it starts the timer; finish: entering it stops it).
func zone_aabb() -> AABB:
	var zh: float = KINDS[kind]["zone"]
	var corners := []
	for x in [-0.5, 0.5]:
		for z in [-0.5, 0.5]:
			corners.append(global_transform * Vector3(size.x * x, 0, size.z * z))
	var box := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		box = box.expand(c)
	return AABB(box.position, Vector3(box.size.x, zh, box.size.z))


## Where (and facing which way) the player spawns on a start platform.
func spawn_transform() -> Transform3D:
	# stand towards the back of the platform (local +Z), facing forward (local -Z)
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), global_transform * Vector3(0, 0.1, size.z * 0.25))


func to_dict() -> Dictionary:
	return {"kind": kind, "position": [snappedf(position.x, 0.001), snappedf(position.y, 0.001), snappedf(position.z, 0.001)],
		"size": [size.x, size.y, size.z], "yaw": yaw}


func from_dict(d: Dictionary) -> void:
	kind = d.get("kind", "start")
	var p: Array = d.get("position", [0, 0, 0])
	position = Vector3(p[0], p[1], p[2])
	var s: Array = d.get("size", [20, 2, 26])
	size = Vector3(s[0], s[1], s[2])
	yaw = d.get("yaw", 0.0)
	if is_inside_tree():
		rebuild()


func center() -> Vector3:
	return position


func translate_by(delta: Vector3) -> void:
	position += delta


func rotate_by(deg: float) -> void:
	yaw = fposmod(yaw + deg + 180.0, 360.0) - 180.0
	rebuild()
