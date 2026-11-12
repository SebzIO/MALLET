class_name CoAvatar
extends Node3D
## A co-editor's body in the world (U17, a person since 0.19.1): legs with feet pointing forward, a torso, arms, a
## neck and a head with a bright visor band across the face, about 1.8 m tall, facing where they look. The body
## turns with their view around the vertical only; the head follows the aim up and down and stops at 40 degrees, the
## way a body in any first-person game does.
## The editor keeps one of these per co-editor and calls `place` with their last cursor message.

const WIDTH := 0.58                       ## shoulder width, meters
const HEAD_AT := 1.63                     ## head center above the feet
const EYE_AT := 1.65                      ## the visor band above the feet: where their camera really is
const PITCH_LIMIT := 0.6981317            ## 40 degrees, radians
const HEAD_R := 0.15                      ## (a little big, so it reads at a distance)

var yaw := 0.0                            ## compass direction, radians (0 = looking down -Z)
var head_pitch := 0.0                     ## where the head points up/down, already clamped
var color := Color(0.35, 0.78, 1.0)
var who := ""

var _parts: Array[MeshInstance3D] = []    ## the body in their color (legs, torso, arms, neck)
var _feet: Array[MeshInstance3D] = []
var _head: Node3D
var _skull: MeshInstance3D
var _bezel: MeshInstance3D
var _vis: MeshInstance3D
var _label: Label3D


func _part(mesh: Mesh, at: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	m.rotation = rot
	add_child(m)
	return m


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func _box(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _init() -> void:
	for side in [-1.0, 1.0]:
		_parts.append(_part(_capsule(0.095, 0.9), Vector3(side * 0.12, 0.47, 0.0)))                       # leg
		_parts.append(_part(_capsule(0.07, 0.66), Vector3(side * (WIDTH * 0.5 - 0.04), 1.14, -0.02), Vector3(0.12, 0, side * 0.08)))   # arm
		_feet.append(_part(_box(Vector3(0.12, 0.08, 0.27)), Vector3(side * 0.12, 0.04, -0.07)))        # foot, toes forward
	_parts.append(_part(_box(Vector3(0.36, 0.22, 0.22)), Vector3(0.0, 0.92, 0.0)))                        # hips
	_parts.append(_part(_box(Vector3(WIDTH - 0.08, 0.5, 0.26)), Vector3(0.0, 1.22, 0.0)))                 # chest
	var neck := CylinderMesh.new()
	neck.top_radius = 0.06
	neck.bottom_radius = 0.08
	neck.height = 0.14
	neck.radial_segments = 10
	_parts.append(_part(neck, Vector3(0.0, 1.52, 0.0)))

	_head = Node3D.new()
	_head.position.y = HEAD_AT
	add_child(_head)
	_skull = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = HEAD_R
	sph.height = HEAD_R * 2.2
	sph.radial_segments = 16
	sph.rings = 8
	_skull.mesh = sph
	_head.add_child(_skull)

	_bezel = MeshInstance3D.new()
	_bezel.mesh = _box(Vector3(0.25, 0.09, 0.03))          # (a dark surround, so the band reads on a light body too)
	_bezel.position = Vector3(0.0, 0.02, -HEAD_R + 0.005)
	_head.add_child(_bezel)

	_vis = MeshInstance3D.new()
	_vis.mesh = _box(Vector3(0.21, 0.06, 0.05))            # the band across the face, at eye level
	_vis.position = Vector3(0.0, 0.02, -HEAD_R - 0.015)   # (the face looks down -Z, like a camera)
	_head.add_child(_vis)

	_label = Label3D.new()
	_label.position = Vector3(0.0, HEAD_AT + 0.45, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.pixel_size = 0.0042
	_label.outline_size = 18
	_label.outline_modulate = Color(0, 0, 0, 0.9)        # (so the name reads against sky or concrete)
	_label.modulate = Color.WHITE
	add_child(_label)
	set_color(color)


## Their color (the same one their cursor and their name are drawn in) and name above the head.
func setup(c: Color, name: String) -> void:
	who = name
	_label.text = name
	set_color(c)


func set_color(c: Color) -> void:
	color = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.55
	for m in _parts:
		m.material_override = mat
	var dark := StandardMaterial3D.new()
	dark.albedo_color = c.darkened(0.55)                   # (shoes: the feet show which way is front)
	dark.roughness = 0.7
	for m in _feet:
		m.material_override = dark
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = c.lightened(0.28)
	head_mat.roughness = 0.5
	_skull.material_override = head_mat
	var bezel_mat := StandardMaterial3D.new()
	bezel_mat.albedo_color = Color(0.05, 0.05, 0.06)
	bezel_mat.roughness = 0.8
	_bezel.material_override = bezel_mat
	var vis_mat := StandardMaterial3D.new()
	vis_mat.albedo_color = c.lightened(0.35)              # a glowing band in their own color (not a white sticker)
	vis_mat.emission_enabled = true
	vis_mat.emission = c
	vis_mat.emission_energy_multiplier = 1.6
	_vis.material_override = vis_mat


## Put the body at a place and turn it (and its head) to look along `aim`. A zero aim direction keeps the last turn.
func place(at: Vector3, aim: Vector3) -> void:
	global_position = at
	if aim.length_squared() > 1e-8:
		var a := aim.normalized()
		if Vector2(a.x, a.z).length_squared() > 1e-6:
			yaw = atan2(-a.x, -a.z)                      # (0 = down -Z, the way every camera here looks)
		head_pitch = clampf(asin(clampf(a.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = yaw
	_head.rotation.x = head_pitch
