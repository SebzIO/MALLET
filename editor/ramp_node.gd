class_name RampNode
extends Node3D
## One ramp in the editor: its editable data, the generated mesh and the collision used for picking
## (and later, play mode).

signal changed

const DEFAULT_COLOR := Color(0.93, 0.92, 0.89)

var points := PackedVector3Array()   ## control points the ridge passes through (world space)
var style := "v"                     ## "v" (both faces) / "half_left" / "half_right" (one face, seen along travel)
var angle := 56.0                    ## slope angle of the faces, degrees from level (left face in Freeform)
var face_length := 10.5              ## slant length of a face, ridge to edge, metres (left face in Freeform)
var angle_right := 56.0              ## Freeform only: the right face's own angle
var face_length_right := 10.5        ## Freeform only: the right face's own length
var slice := "vertical"              ## profile held in a vertical slice, or "perpendicular" to travel
var detail := 1.0                    ## cross-sections per metre of path (smoothness / polygon count)
var freeform := false                ## unlocks different faces and twist
var twist := 0.0                     ## Freeform only: the profile rolls from 0 at the start to this at the end
var solid := false                   ## closed flat bottom instead of an open shell
var base_depth := 0.0                ## solid only: how far the flat bottom sits below the face edges
## Edge-to-edge width and ridge height of a symmetric V ramp. Setting either keeps the other and recomputes
## the angle and face length.
var width: float:
	get: return 2.0 * face_length * cos(deg_to_rad(angle))
	set(v): _set_size(v, height)
var height: float:
	get: return face_length * sin(deg_to_rad(angle))
	set(v): _set_size(width, v)
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
var ridge := PackedVector3Array()          ## the spine at every cross-section (for the jump checker)
var folds := PackedInt32Array()            ## cross-sections where a too-tight bend folds the inner edge over
var fold_lines: Array[PackedVector3Array] = []   ## those cross-sections' outlines, drawn red in the editor
var geometry := {}                         ## the full RampShape.build() result of the last rebuild


func _ready() -> void:
	add_child(_mesh_instance)
	_body.add_child(_shape)
	_body.set_meta("ramp", self)
	add_child(_body)
	rebuild()


func _set_size(w: float, h: float) -> void:
	face_length = sqrt(w * w * 0.25 + h * h)
	angle = rad_to_deg(atan2(h, w * 0.5))
	if not freeform:
		angle_right = angle
		face_length_right = face_length


## The settings RampShape builds from (Freeform off forces matching faces and no twist).
func shape_spec() -> Dictionary:
	return RampShape.spec(to_dict())


func rebuild() -> void:
	geometry = RampShape.build(points, shape_spec())
	ridge = geometry["ridge"]
	folds = geometry["folds"]
	var mesh: ArrayMesh = geometry["mesh"]
	_mesh_instance.mesh = mesh
	_shape.shape = mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
	triangle_count = geometry["triangles"]
	length = geometry["length"]
	_build_outline()
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


## Lines along each edge of the cross-section, plus the outline of both end caps; and the red fold markers.
func _build_outline() -> void:
	outline.clear()
	fold_lines.clear()
	var rings: Array = geometry.get("rings", [])
	if rings.size() < 2:
		return
	var step: int = max(1, rings.size() / 60)
	var picked: Array = []
	for i in range(0, rings.size(), step):
		picked.append(rings[i])
	if picked[picked.size() - 1] != rings[rings.size() - 1]:
		picked.append(rings[rings.size() - 1])
	for k in geometry["profile"]["lines"]:
		var line := PackedVector3Array()
		for ring in picked:
			line.append(ring[k])
		outline.append(line)
	for ring in [rings[0], rings[rings.size() - 1]]:
		var cap: PackedVector3Array = ring.duplicate()
		cap.append(ring[0])
		outline.append(cap)
	for i in folds:
		var ring: PackedVector3Array = rings[i]
		var cap: PackedVector3Array = ring.duplicate()
		cap.append(ring[0])
		fold_lines.append(cap)


## Plain-data snapshot for save files and undo.
func to_dict() -> Dictionary:
	var pts := []
	for p in points:
		pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return {"points": pts, "style": style, "angle": angle, "face_length": face_length, "angle_right": angle_right,
		"face_length_right": face_length_right, "slice": slice, "detail": detail, "freeform": freeform, "twist": twist,
		"solid": solid, "base_depth": base_depth, "color": color.to_html(false), "look": look, "texture": texture,
		"tex_scale": tex_scale}


func from_dict(data: Dictionary) -> void:
	points = PackedVector3Array()
	for p in data.get("points", []):
		points.append(Vector3(p[0], p[1], p[2]))
	var sp := RampShape.spec(data)
	for k in RampShape.DEFAULTS:
		set(k, sp[k])
	if data.get("freeform", false):                # keep a Freeform ramp's own right-face values
		angle_right = float(data.get("angle_right", angle))
		face_length_right = float(data.get("face_length_right", face_length))
		twist = float(data.get("twist", 0.0))
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


## Edge-to-edge width of the cross-section as built (half ramps: ridge to the face edge).
func geometry_width() -> float:
	var sp := shape_spec()
	var l: float = sp["face_length"] * cos(deg_to_rad(sp["angle"]))
	var r: float = sp["face_length_right"] * cos(deg_to_rad(sp["angle_right"]))
	match style:
		"half_left": return l
		"half_right": return r
	return l + r
