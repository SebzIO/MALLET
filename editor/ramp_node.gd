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
var twist := 0.0                     ## extra roll spread along the ramp: roll-twist/2 at the start .. roll+twist/2 at the end
var solid := false                   ## closed flat bottom instead of the open V
var base_depth := 0.0                ## solid only: how far the flat bottom sits below the face edges
var color := DEFAULT_COLOR
var look := "color"                  ## material preset (see Look.RAMP_LOOKS)
var texture := ""                    ## look "texture": image file on disk
var tex_scale := 20.0                ## look "texture": metres one copy of the image covers
var _material_key := ""

var _mesh_instance := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _selected := false
var triangle_count := 0
var outline: Array[PackedVector3Array] = []   ## edge polylines for the selection outline
var length := 0.0
var ridge := PackedVector3Array()          ## the sampled ridge line (for the jump checker)


func _ready() -> void:
	add_child(_mesh_instance)
	_body.add_child(_shape)
	_body.set_meta("ramp", self)
	add_child(_body)
	rebuild()


func rebuild() -> void:
	var spacing: float = 1.0 / max(detail, 0.05)
	ridge = RampShape.sample_path(points, spacing)
	var mesh := RampShape.build_mesh(ridge, width, height, roll, solid, base_depth, twist)
	_mesh_instance.mesh = mesh
	_shape.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
	triangle_count = 0
	if mesh.get_surface_count() > 0:
		triangle_count = mesh.surface_get_array_len(0) / 3
	length = RampShape.path_length(ridge)
	_build_outline(ridge)
	_update_material()
	changed.emit()


func set_selected(on: bool) -> void:
	_selected = on
	_update_material()


func _update_material() -> void:
	# selection is shown with an outline, so the material is always the ramp's real look
	var key := "%s|%s|%s|%s" % [look, color.to_html(), texture, tex_scale]
	if key != _material_key:
		_material_key = key
		_mesh_instance.material_override = Look.ramp_material(look, color, texture, tex_scale)


## Lines along each edge of the cross-section, plus the outline of both end caps.
func _build_outline(ridge: PackedVector3Array) -> void:
	outline.clear()
	if ridge.size() < 2:
		return
	var step: int = max(1, ridge.size() / 60)
	var thin := PackedVector3Array()
	for i in range(0, ridge.size(), step):
		thin.append(ridge[i])
	if thin[thin.size() - 1] != ridge[ridge.size() - 1]:
		thin.append(ridge[ridge.size() - 1])
	var rings := RampShape.compute_rings(thin, width, height, roll, solid, base_depth, twist)
	var pc := rings[0].size()
	for k in pc:
		if not solid and k >= 3:
			continue                                 # skip the hollow ramp's underside lines
		var line := PackedVector3Array()
		for ring in rings:
			line.append(ring[k])
		outline.append(line)
	for ring in [rings[0], rings[rings.size() - 1]]:
		var cap: PackedVector3Array = ring.duplicate()
		cap.append(ring[0])
		outline.append(cap)


## Plain-data snapshot for save files and undo.
func to_dict() -> Dictionary:
	var pts := []
	for p in points:
		pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return {"points": pts, "width": width, "height": height, "detail": detail, "roll": roll, "twist": twist, "solid": solid, "base_depth": base_depth,
		"color": color.to_html(false), "look": look, "texture": texture, "tex_scale": tex_scale}


func from_dict(data: Dictionary) -> void:
	points = PackedVector3Array()
	for p in data.get("points", []):
		points.append(Vector3(p[0], p[1], p[2]))
	width = data.get("width", 13.0)
	height = data.get("height", 8.125)
	detail = data.get("detail", 1.0)
	roll = data.get("roll", 0.0)
	twist = data.get("twist", 0.0)
	solid = data.get("solid", false)
	base_depth = data.get("base_depth", 0.0)
	color = Color.html(data.get("color", DEFAULT_COLOR.to_html(false)))
	look = data.get("look", "color")
	texture = data.get("texture", "")
	tex_scale = data.get("tex_scale", 20.0)
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
