class_name RampNode
extends Node3D
## One ramp in the editor: its editable data, the generated mesh and the collision used for picking
## (and later, play mode).

signal changed

const DEFAULT_COLOR := Color(0.93, 0.92, 0.89)

var points := PackedVector3Array()   ## control points the ridge passes through (world space)
var width := 13.0                    ## metres edge to edge
var height := 8.125                  ## ridge height above the edges (face steepness = height / (width / 2))
var detail := 1.0                    ## segments per metre of path (smoothness / polygon count)
var roll := 0.0                      ## degrees the cross-section is tilted around the path
var solid := false                   ## closed flat bottom instead of the open V
var base_depth := 0.0                ## solid only: how far the flat bottom sits below the face edges
var color := DEFAULT_COLOR

var _mesh_instance := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _material := StandardMaterial3D.new()
var _selected := false
var triangle_count := 0
var length := 0.0


func _ready() -> void:
	_material.roughness = 0.25
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	_body.add_child(_shape)
	_body.set_meta("ramp", self)
	add_child(_body)
	rebuild()


func rebuild() -> void:
	var spacing: float = 1.0 / max(detail, 0.05)
	var ridge := RampShape.sample_path(points, spacing)
	var mesh := RampShape.build_mesh(ridge, width, height, roll, solid, base_depth)
	_mesh_instance.mesh = mesh
	_shape.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
	triangle_count = 0
	if mesh.get_surface_count() > 0:
		triangle_count = mesh.surface_get_array_len(0) / 3
	length = RampShape.path_length(ridge)
	_update_material()
	changed.emit()


func set_selected(on: bool) -> void:
	_selected = on
	_update_material()


func _update_material() -> void:
	_material.albedo_color = color
	_material.emission_enabled = _selected
	_material.emission = Color(0.15, 0.35, 0.9)
	_material.emission_energy_multiplier = 0.35


## Plain-data snapshot for save files and undo.
func to_dict() -> Dictionary:
	var pts := []
	for p in points:
		pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return {"points": pts, "width": width, "height": height, "detail": detail, "roll": roll, "solid": solid, "base_depth": base_depth,
		"color": color.to_html(false)}


func from_dict(data: Dictionary) -> void:
	points = PackedVector3Array()
	for p in data.get("points", []):
		points.append(Vector3(p[0], p[1], p[2]))
	width = data.get("width", 13.0)
	height = data.get("height", 8.125)
	detail = data.get("detail", 1.0)
	roll = data.get("roll", 0.0)
	solid = data.get("solid", false)
	base_depth = data.get("base_depth", 0.0)
	color = Color.html(data.get("color", DEFAULT_COLOR.to_html(false)))
	if is_inside_tree():
		rebuild()


func center() -> Vector3:
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / max(points.size(), 1)


func translate_by(delta: Vector3) -> void:
	var pts := points
	for i in pts.size():
		pts[i] += delta
	points = pts
	rebuild()


## Turn the whole ramp around its centre (degrees, seen from above).
func rotate_by(deg: float) -> void:
	var c := center()
	var b := Basis(Vector3.UP, deg_to_rad(deg))
	var pts := points
	for i in pts.size():
		pts[i] = c + b * (pts[i] - c)
	points = pts
	rebuild()
