class_name RampNode
extends Node3D
## One ramp in the editor: its editable data, the generated mesh and the collision used for picking
## (and later, play mode).

signal changed

const DEFAULT_COLOR := Color(0.93, 0.92, 0.89)

var points := PackedVector3Array()   ## control points the ridge passes through (world space)
var style := "v"                     ## "v" (both faces) / "half_left" / "half_right" (one face, seen along travel)
var angle := 56.0                    ## slope angle of the faces, degrees from level (left face in Freeform)
var face_length := 10.5              ## slant length of a face, ridge to edge, meters (left face in Freeform)
var angle_right := 56.0              ## Freeform only: the right face's own angle
var face_length_right := 10.5        ## Freeform only: the right face's own length
var slice := "vertical"              ## profile held in a vertical slice, or "perpendicular" to travel
var detail := 1.0                    ## cross-sections per meter of path (smoothness / polygon count)
var freeform := false                ## lets the right face have its own angle and length
var frozen: Array = []               ## locked sections, first to last (see RampShape.sections)
var seam_tangent_lock := true        ## the editable section leaves its seam along the locked section's tangent
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
var material := ""                   ## look "material": a library material id
var tex_scale := 20.0                ## look "texture": meters one copy of the image covers
var _material_key := ""

var _mesh_instance := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
var _selected := false
var triangle_count := 0
var outline: Array[PackedVector3Array] = []   ## edge polylines for the selection outline (the editable part)
var outline_frozen: Array[PackedVector3Array] = []   ## the same for the locked part
var seam_lines: Array[PackedVector3Array] = []       ## the cross-section at each seam
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


## The settings RampShape builds from (Freeform off forces matching faces).
func shape_spec() -> Dictionary:
	return RampShape.spec(to_dict())


func rebuild() -> void:
	position = Vector3.ZERO                              # (shift() moves the node while dragging; the mesh is world space)
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
	var key := "%s|%s|%s|%s|%s|%s" % [look, color.to_html(), texture, tex_scale, material, face_length]
	if key != _material_key:
		_material_key = key
		_mesh_instance.material_override = Look.ramp_material(look, color, texture, tex_scale, material, face_length)


## Lines along each edge of the cross-section and round both end caps (locked part and editable part kept
## apart so they can be drawn differently), the seams, and the red fold markers.
func _build_outline() -> void:
	outline.clear()
	outline_frozen.clear()
	seam_lines.clear()
	fold_lines.clear()
	var rings: Array = geometry.get("rings", [])
	if rings.size() < 2:
		return
	var seams: PackedInt32Array = geometry.get("seams", PackedInt32Array())
	var split: int = seams[seams.size() - 1] if not seams.is_empty() and not frozen.is_empty() else 0
	for part in [[0, split, outline_frozen], [split, rings.size() - 1, outline]]:
		var from: int = part[0]
		var to: int = part[1]
		if to <= from:
			continue
		var step: int = max(1, (to - from) / 60)
		var picked: Array = []
		for i in range(from, to + 1, step):
			picked.append(rings[i])
		if picked[picked.size() - 1] != rings[to]:
			picked.append(rings[to])
		for k in geometry["profile"]["lines"]:
			var line := PackedVector3Array()
			for ring in picked:
				line.append(ring[k])
			part[2].append(line)
	for ring in [rings[0], rings[rings.size() - 1]]:
		outline.append(_closed(ring))
	for i in seams:
		seam_lines.append(_closed(rings[i]))
	for i in folds:
		fold_lines.append(_closed(rings[i]))


static func _closed(ring: PackedVector3Array) -> PackedVector3Array:
	var c: PackedVector3Array = ring.duplicate()
	c.append(ring[0])
	return c


## Plain-data snapshot for save files and undo.
func to_dict() -> Dictionary:
	var pts := []
	for p in points:
		pts.append([snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)])
	return {"points": pts, "style": style, "angle": angle, "face_length": face_length, "angle_right": angle_right,
		"face_length_right": face_length_right, "slice": slice, "detail": detail, "freeform": freeform,
		"frozen": frozen.duplicate(true), "seam_tangent_lock": seam_tangent_lock,
		"solid": solid, "base_depth": base_depth, "color": color.to_html(false), "look": look, "texture": texture,
		"tex_scale": tex_scale, "material": material}


func from_dict(data: Dictionary) -> void:
	points = PackedVector3Array()
	for p in data.get("points", []):
		points.append(Vector3(p[0], p[1], p[2]))
	var sp := RampShape.spec(data)
	for k in RampShape.DEFAULTS:
		set(k, sp[k].duplicate(true) if sp[k] is Array else sp[k])
	if data.get("freeform", false):                # keep a Freeform ramp's own right-face values
		angle_right = float(data.get("angle_right", angle))
		face_length_right = float(data.get("face_length_right", face_length))
	color = Color.html(data.get("color", DEFAULT_COLOR.to_html(false)))
	look = data.get("look", "color")
	texture = data.get("texture", "")
	tex_scale = data.get("tex_scale", 20.0)
	material = data.get("material", "")
	if is_inside_tree():
		rebuild()


## Move the whole ramp without rebuilding it (dragging): the node carries the mesh and collision along, and the
## world-space data (points, ridge, outlines) is shifted to match. settle() rebuilds it in place afterwards.
func shift(delta: Vector3) -> void:
	position += delta
	var pts := points                                    # (packed arrays are values: change a copy, put it back)
	for i in pts.size():
		pts[i] += delta
	points = pts
	var rg := ridge
	for i in rg.size():
		rg[i] += delta
	ridge = rg
	for lines in [outline, outline_frozen, seam_lines, fold_lines]:
		for li in lines.size():
			var l: PackedVector3Array = lines[li]
			for i in l.size():
				l[i] += delta
			lines[li] = l
	_move_ghosts(func(g: Vector3): return g + delta)


## Rebuild after shift() (the texture follows the world, so it's laid out again once the ramp stops moving).
func settle() -> void:
	if position != Vector3.ZERO:
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
	_move_ghosts(func(g: Vector3): return g + delta)
	rebuild()


## Turn the whole ramp around its center (degrees, seen from above).
func rotate_by(deg: float) -> void:
	var c := center()
	var b := Basis(Vector3.UP, deg_to_rad(deg))
	var pts := points
	for i in pts.size():
		pts[i] = c + b * (pts[i] - c)
	points = pts
	_move_ghosts(func(g: Vector3): return c + b * (g - c))
	rebuild()


## Locked sections remember a ghost point; moving or turning the whole ramp must carry it along.
func _move_ghosts(f: Callable) -> void:
	for rec in frozen:
		var g: Array = rec["end_ghost"]
		var v: Vector3 = f.call(Vector3(g[0], g[1], g[2]))
		rec["end_ghost"] = [v.x, v.y, v.z]


# ------------------------------------------------------------------------------------------------ locks
## Index of the most recent locked point (-1 = no locks). It and every point before it are frozen.
func lock_index() -> int:
	return int(frozen[frozen.size() - 1]["end"]) if not frozen.is_empty() else -1


func is_locked_point(i: int) -> bool:
	for rec in frozen:
		if int(rec["end"]) == i:
			return true
	return false


## Why point `i` can't be locked ("" = it can).
func lock_problem(i: int) -> String:
	if i <= 0:
		return "Locking the first point would freeze nothing: pick a point further along."
	if i <= lock_index():
		return "That point is already in a locked section."
	if i >= points.size() - 1:
		return "The last point can't be locked: there has to be ramp after it. Use Extend to add more first."
	return ""


## Freeze everything from the start up to point `i`. Nothing moves: the locked part keeps the exact curve it has
## now (a ghost of the next point is stored) and the rest carries on from it with the same face settings.
func lock_at(i: int) -> void:
	var g := points[i + 1]
	frozen.append({"end": i, "angle": angle, "face_length": face_length, "angle_right": angle_right,
		"face_length_right": face_length_right, "end_ghost": [g.x, g.y, g.z], "tangent_lock": seam_tangent_lock})
	seam_tangent_lock = true
	rebuild()


## Undo locks from number `k` (0 = the first lock) onwards; the sections after it merge into the editable one,
## which keeps the editable section's face settings.
func unlock_from(k: int) -> void:
	if k < 0 or k >= frozen.size():
		return
	seam_tangent_lock = bool(frozen[k].get("tangent_lock", true))
	frozen.resize(k)
	rebuild()


func lock_number(i: int) -> int:
	for k in frozen.size():
		if int(frozen[k]["end"]) == i:
			return k
	return -1


## Edge-to-edge width of the cross-section as built (half ramps: ridge to the face edge).
func geometry_width() -> float:
	var sp := shape_spec()
	var l: float = sp["face_length"] * cos(deg_to_rad(sp["angle"]))
	var r: float = sp["face_length_right"] * cos(deg_to_rad(sp["angle_right"]))
	match style:
		"half_left": return l
		"half_right": return r
	return l + r
