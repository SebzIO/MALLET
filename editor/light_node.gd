class_name LightNode
extends Node3D
## A light: a point light shining all around, or a spot light shining a cone (along its facing, tilted by pitch).
## Lights the editor view straight away, and exports as a real light to SurfsUp and as light / light_spot to CS:S.

const PICK_ONLY_LAYER := 1 << 19
const KINDS := ["point", "spot"]
const DEFAULTS := {
	"kind": "point", "position": [0.0, 0.0, 0.0], "color": "ffd9a0", "energy": 2.0, "range": 30.0,
	"angle": 40.0, "yaw": 0.0, "pitch": -60.0, "shadows": true,
}

var data := DEFAULTS.duplicate(true)
var _light: Light3D
var _bulb := MeshInstance3D.new()
var _body := StaticBody3D.new()


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not s["kind"] in KINDS:
		s["kind"] = "point"
	return s


static func basis_of(s: Dictionary) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(float(s["pitch"])), deg_to_rad(float(s["yaw"])), 0.0), EULER_ORDER_YXZ)


## A Godot light for these settings (used in the editor and in the SurfsUp export).
static func make_light(s: Dictionary) -> Light3D:
	var l: Light3D
	if s["kind"] == "spot":
		var sl := SpotLight3D.new()
		sl.spot_range = float(s["range"])
		sl.spot_angle = float(s["angle"]) * 0.5
		l = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = float(s["range"])
		l = ol
	l.light_color = Color.html(s["color"])
	l.light_energy = float(s["energy"])
	l.shadow_enabled = bool(s["shadows"])
	return l


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	_bulb.mesh = sphere
	_bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulb)
	var shape := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 1.5
	shape.shape = ss
	_body.add_child(shape)
	_body.set_meta("light", self)
	_body.collision_layer = PICK_ONLY_LAYER
	_body.collision_mask = 0
	add_child(_body)
	rebuild()


func label() -> String:
	return "Spot light" if data["kind"] == "spot" else "Light"


func rebuild() -> void:
	var s := spec(data)
	var p: Array = s["position"]
	transform = Transform3D(basis_of(s), Vector3(p[0], p[1], p[2]))
	if _light:
		_light.queue_free()
	_light = make_light(s)
	add_child(_light)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.html(s["color"]).lightened(0.3)
	_bulb.material_override = m


func set_selected(_on: bool) -> void:
	pass


## Rings showing how far it reaches (and, for a spot, its direction).
func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var r: float = float(data["range"])
	var xf := global_transform
	if data["kind"] == "spot":
		var half := deg_to_rad(float(data["angle"]) * 0.5)
		var ring := PackedVector3Array()
		for i in 33:
			var a := TAU * i / 32.0
			ring.append(xf * (Vector3(cos(a) * sin(half), sin(a) * sin(half), -cos(half)) * r))
		out.append(ring)
		for i in 4:
			out.append(PackedVector3Array([xf.origin, ring[i * 8]]))
	else:
		for axis in 3:
			var ring := PackedVector3Array()
			for i in 33:
				var a := TAU * i / 32.0
				var v := Vector3(cos(a), sin(a), 0) if axis == 0 else (Vector3(cos(a), 0, sin(a)) if axis == 1 else Vector3(0, cos(a), sin(a)))
				ring.append(xf.origin + v * r)
			out.append(ring)
	return out


func center() -> Vector3:
	return global_position


func translate_by(delta: Vector3) -> void:
	var p: Array = data["position"]
	data["position"] = [p[0] + delta.x, p[1] + delta.y, p[2] + delta.z]
	global_position += delta


func rotate_by(deg: float) -> void:
	data["yaw"] = wrapf(float(data["yaw"]) + deg, -180.0, 180.0)
	rebuild()


func to_dict() -> Dictionary:
	var d := data.duplicate(true)
	var p: Array = d["position"]
	d["position"] = [snappedf(p[0], 0.001), snappedf(p[1], 0.001), snappedf(p[2], 0.001)]
	return d


func from_dict(d: Dictionary) -> void:
	data = spec(d)
	if is_inside_tree():
		rebuild()
	else:
		var p: Array = data["position"]
		position = Vector3(p[0], p[1], p[2])
