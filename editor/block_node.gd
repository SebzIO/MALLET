class_name BlockNode
extends Node3D
## A structure block: box, wedge, cylinder or stairs; optionally hollow; or a cutter that cuts holes in the solid
## blocks it overlaps (live: move the cutter and the hole moves). Built from convex pieces (see BlockShape), each
## of which is a collision shape here and a brush in a CS:S export.

const PICK_ONLY_LAYER := 1 << 19
const CUTTER_COLOR := Color(1.0, 0.25, 0.2, 0.28)

var data := BlockShape.DEFAULTS.duplicate(true)  ## everything about the block (BlockShape.spec format)
var pieces: Array = []                         ## world-space convex pieces after cuts
var _mesh := MeshInstance3D.new()
var _body := StaticBody3D.new()
var _material_key := ""


func _ready() -> void:
	add_child(_mesh)
	_body.set_meta("block", self)
	_body.collision_mask = 0
	add_child(_body)


func is_cutter() -> bool:
	return bool(data["cutter"])


func size() -> Vector3:
	return Vector3(data["size"][0], data["size"][1], data["size"][2])


func label() -> String:
	return "Cutter" if is_cutter() else "Block"


## Rebuild from `data`, cut by `cutters` (dictionaries of the cutter blocks that may overlap this one).
func rebuild(cutters: Array = []) -> void:
	var s := BlockShape.spec(data)
	var xf := BlockShape.transform_of(s)
	transform = xf
	pieces = BlockShape.world_pieces(s, cutters)
	_mesh.mesh = BlockShape.mesh(pieces, xf)
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var inv := xf.affine_inverse()
	for p in pieces:
		var shape := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for v in Convex.points(p):
			pts.append(inv * v)
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_body.add_child(cs)
	_body.collision_layer = PICK_ONLY_LAYER if is_cutter() else 1
	_update_material()


func _update_material() -> void:
	var key := "%s|%s|%s" % [data["look"], data["color"], is_cutter()]
	if key == _material_key:
		return
	_material_key = key
	if is_cutter():
		var m := StandardMaterial3D.new()
		m.albedo_color = CUTTER_COLOR
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh.material_override = m
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_mesh.material_override = Look.ramp_material(data["look"], Color.html(data["color"]))
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func set_selected(_on: bool) -> void:
	pass


## Every edge of every piece, for the selection outline.
func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var show: Array = pieces
	if is_cutter() or pieces.is_empty():
		show = []
		var xf := BlockShape.transform_of(BlockShape.spec(data))
		for p in BlockShape.local_pieces(BlockShape.spec(data)):
			show.append(Convex.transformed(p, xf))
	for piece in show:
		for f in Convex.faces(piece):
			var poly: Array = f[1]
			var line := PackedVector3Array(poly)
			line.append(poly[0])
			out.append(line)
	return out


## Resize handles: the middle of each side of the block's box, as [world point, world outward normal, axis, sign].
func face_handles() -> Array:
	var sz := size()
	var xf := global_transform
	var out := []
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var local := Vector3(0, sz.y * 0.5, 0)
			var n := Vector3.ZERO
			n[axis] = sgn
			if axis == 1:
				local.y = sz.y if sgn > 0 else 0.0
			else:
				local[axis] = sz[axis] * 0.5 * sgn
			out.append([xf * local, (xf.basis * n).normalized(), axis, sgn])
	return out


## Move one side of the box by `amount` metres along its outward normal; the opposite side stays put.
static func resized(d: Dictionary, axis: int, sgn: float, amount: float) -> Dictionary:
	var out := d.duplicate(true)
	var sz := Vector3(d["size"][0], d["size"][1], d["size"][2])
	var new_len := maxf(sz[axis] + amount, 0.25)
	var grow := new_len - sz[axis]
	sz[axis] = new_len
	var b := BlockShape.basis_of(BlockShape.spec(d))
	var pos := Vector3(d["position"][0], d["position"][1], d["position"][2])
	if axis == 1:
		if sgn < 0.0:
			pos -= b * Vector3(0, grow, 0)              # moving the bottom down
	else:
		var shift := Vector3.ZERO
		shift[axis] = grow * 0.5 * sgn
		pos += b * shift
	out["size"] = [sz.x, sz.y, sz.z]
	out["position"] = [pos.x, pos.y, pos.z]
	return out


func center() -> Vector3:
	return global_transform * Vector3(0, size().y * 0.5, 0)


func translate_by(delta: Vector3) -> void:
	var p: Array = data["position"]
	data["position"] = [p[0] + delta.x, p[1] + delta.y, p[2] + delta.z]
	transform = BlockShape.transform_of(BlockShape.spec(data))


func rotate_by(deg: float) -> void:
	data["yaw"] = wrapf(float(data["yaw"]) + deg, -180.0, 180.0)
	transform = BlockShape.transform_of(BlockShape.spec(data))


func to_dict() -> Dictionary:
	var d := data.duplicate(true)
	var p: Array = d["position"]
	d["position"] = [snappedf(p[0], 0.001), snappedf(p[1], 0.001), snappedf(p[2], 0.001)]
	return d


func from_dict(d: Dictionary) -> void:
	data = BlockShape.spec(d)
	transform = BlockShape.transform_of(data)


## Set the length along `axis` (0 = width, 2 = depth) keeping the block's middle where it is.
static func resized_centered(d: Dictionary, axis: int, length: float) -> Dictionary:
	var out := d.duplicate(true)
	out["size"][axis] = maxf(length, 0.25)
	return out
