class_name CoAvatar
extends Node3D
## A co-editor's body in the world (U17): a capsule about 1.8 m tall, a head on top, and a bright visor across the
## face showing which way they look. The body shows the compass direction only; the head follows the aim up and down
## and stops at 40 degrees, the way a body in any first-person game does.
## The editor keeps one of these per co-editor and calls `place` with their last cursor message.

const WIDTH := 0.58                       ## body width, metres
const BODY_HEIGHT := 1.45                 ## capsule length (its caps add the rest of the 1.8 m)
const HEAD_AT := 1.66                     ## head centre above the feet
const PITCH_LIMIT := 0.6981317            ## 40 degrees, radians

var yaw := 0.0                            ## compass direction, radians (0 = looking down -Z)
var head_pitch := 0.0                     ## where the head points up/down, already clamped
var color := Color(0.35, 0.78, 1.0)
var who := ""

var _body: MeshInstance3D
var _head: Node3D
var _vis: MeshInstance3D
var _label: Label3D


func _init() -> void:
	_body = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = WIDTH * 0.5
	cap.height = BODY_HEIGHT
	cap.radial_segments = 16
	cap.rings = 6
	_body.mesh = cap
	_body.position.y = BODY_HEIGHT * 0.5                 # feet on the floor
	add_child(_body)

	_head = Node3D.new()
	_head.position.y = HEAD_AT
	add_child(_head)
	var skull := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.21
	sph.height = 0.42
	sph.radial_segments = 16
	sph.rings = 8
	skull.mesh = sph
	_head.add_child(skull)

	_vis = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.09, 0.07)                 # across the face, a little proud of it
	_vis.mesh = box
	_vis.position = Vector3(0.0, 0.02, -0.19)            # the face looks down -Z, like a camera
	_head.add_child(_vis)

	_label = Label3D.new()
	_label.position = Vector3(0.0, HEAD_AT + 0.42, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 48
	_label.pixel_size = 0.0022
	_label.outline_size = 10
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
	for m in [_body, _vis]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.roughness = 0.6
		(m as MeshInstance3D).material_override = mat
	var skull := _head.get_child(0) as MeshInstance3D
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = c.lightened(0.25)
	head_mat.roughness = 0.5
	skull.material_override = head_mat
	var vis_mat := StandardMaterial3D.new()
	vis_mat.albedo_color = c.lightened(0.55)
	vis_mat.emission_enabled = true
	vis_mat.emission = c
	vis_mat.emission_energy_multiplier = 0.6
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


