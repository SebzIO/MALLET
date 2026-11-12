class_name LightNode
extends Node3D
## A light: a point light shining all around, a spot light shining a cone (along its facing, tilted by pitch), or a
## strip (a glowing tube lighting along its length: neon, fluorescent tubes). Effects (flicker, candle, pulse, strobe,
## fluorescent buzz) are an AnimationPlayer - SurfsUp maps can't hold scripts - and Source's own light styles in CS:S.
## Lights the editor view straight away, and exports as real lights to SurfsUp and as light / light_spot to CS:S.

const PICK_ONLY_LAYER := 1 << 19
const KINDS := ["point", "spot", "strip"]
const DEFAULTS := {
	"kind": "point", "position": [0.0, 0.0, 0.0], "color": "ffd9a0", "energy": 2.0, "range": 30.0,
	"angle": 40.0, "yaw": 0.0, "pitch": -60.0, "shadows": true,
	"effect": "none",                    ## EFFECTS: none, flicker, candle, pulse, strobe, fluorescent
	"length": 4.0,                       ## strip: meters long (along its local x axis)
	"colors": [],                        ## more colors to cycle through (pulse: flows through them; flicker: jumps)
	"speed": 1.0,                        ## seconds per color of the cycle (flicker: a fifth of that per jump)
	"random": false,                     ## flicker: jump between the colors in any order
}
const EFFECTS := ["none", "flicker", "candle", "pulse", "strobe", "fluorescent"]
const EFFECT_LABELS := ["Steady", "Flicker (fire)", "Candle", "Slow pulse", "Strobe", "Fluorescent buzz"]
const CSS_STYLES := {"none": 0, "flicker": 1, "candle": 6, "pulse": 2, "strobe": 4, "fluorescent": 10}   ## Source light styles
## Presets: a starting point, everything stays editable.
const PRESETS := {
	"lamp": {"label": "Lamp", "kind": "point", "color": "ffd9a0", "energy": 2.0, "range": 30.0, "effect": "none"},
	"torch": {"label": "Torch", "kind": "point", "color": "ff9a40", "energy": 2.5, "range": 14.0, "effect": "candle"},
	"candle": {"label": "Candle", "kind": "point", "color": "ffb060", "energy": 0.8, "range": 6.0, "effect": "candle", "shadows": false},
	"campfire": {"label": "Campfire", "kind": "point", "color": "ff7a2a", "energy": 3.5, "range": 20.0, "effect": "flicker"},
	"spotlight": {"label": "Spotlight", "kind": "spot", "color": "ffffff", "energy": 4.0, "range": 60.0, "angle": 35.0, "effect": "none"},
	"neon_pink": {"label": "Neon strip (pink)", "kind": "strip", "color": "ff3ad0", "energy": 3.0, "range": 10.0, "length": 4.0,
		"effect": "none", "shadows": false},
	"neon_cyan": {"label": "Neon strip (cyan)", "kind": "strip", "color": "30e8ff", "energy": 3.0, "range": 10.0, "length": 4.0,
		"effect": "none", "shadows": false},
	"fluorescent": {"label": "Fluorescent tube", "kind": "strip", "color": "e8f4ff", "energy": 2.5, "range": 14.0, "length": 2.5,
		"effect": "fluorescent", "shadows": false},
	"alarm": {"label": "Alarm (red strobe)", "kind": "point", "color": "ff2020", "energy": 4.0, "range": 25.0, "effect": "strobe"},
	"party": {"label": "Party (purple pulse)", "kind": "point", "color": "8a5cff", "energy": 3.0, "range": 20.0, "effect": "pulse"},
}
const PRESET_ORDER := ["lamp", "torch", "candle", "campfire", "spotlight", "neon_pink", "neon_cyan", "fluorescent", "alarm", "party"]

var data := DEFAULTS.duplicate(true)
var _light: Light3D
var _rig: Node3D
var _bulb := MeshInstance3D.new()
var _body := StaticBody3D.new()


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not s["kind"] in KINDS:
		s["kind"] = "point"
	if not s["effect"] in EFFECTS:
		s["effect"] = "none"
	if not s["colors"] is Array:
		s["colors"] = []
	s["speed"] = clampf(float(s["speed"]), 0.05, 30.0)
	return s


## The colors the light cycles through: its own, then the extra ones.
static func palette(s: Dictionary) -> Array:
	var out := [Color.html(String(s["color"]))]
	for c in (s["colors"] as Array):
		out.append(Color.html(String(c)))
	return out


## How many lights a strip spreads its light over (one per 2.5 m, up to 4).
static func strip_count(s: Dictionary) -> int:
	return clampi(ceili(float(s["length"]) / 2.5), 1, 4)


## Where a strip's lights sit, along its local x axis (meters).
static func strip_points(s: Dictionary) -> Array:
	var n := strip_count(s)
	var length := float(s["length"])
	var out := []
	for i in n:
		out.append(Vector3(-length * 0.5 + length * (i + 0.5) / n, 0, 0))
	return out


## Everything the light is, as nodes (the editor's and the SurfsUp export's): the light(s), a strip's glowing tube,
## and the effect's AnimationPlayer (autoplay, no script). Not positioned: the caller sets its transform.
static func make_rig(s: Dictionary) -> Node3D:
	var rig := Node3D.new()
	var lights: Array = []
	if s["kind"] == "strip":
		var each := s.duplicate()
		each["kind"] = "point"
		var n := strip_count(s)
		each["energy"] = float(s["energy"]) / sqrt(float(n))
		var pts := strip_points(s)
		for i in n:
			var l := make_light(each)
			l.name = "Light%d" % i
			l.position = pts[i]
			rig.add_child(l)
			lights.append(l)
		var tube := MeshInstance3D.new()
		tube.name = "Tube"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = float(s["length"])
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.albedo_color = Color.html(s["color"]).lightened(0.4)
		cyl.material = tm
		tube.mesh = cyl
		tube.rotation = Vector3(0, 0, PI / 2)
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(tube)
	else:
		var l := make_light(s)
		l.name = "Light0"
		rig.add_child(l)
		lights.append(l)
	if s["effect"] != "none":
		rig.add_child(_effect_player(s, lights))
	if s["effect"] in ["pulse", "flicker"] and not (s["colors"] as Array).is_empty():
		rig.add_child(_color_player(s, lights))
	return rig


## Color cycles (0.19.4): pulse flows through the light's colors, flicker jumps between them (in order, or at random),
## `speed` seconds a color. Its own looping animation, so it keeps its own pace beside the brightness effect.
static func _color_player(s: Dictionary, lights: Array) -> AnimationPlayer:
	var cols := palette(s)
	var speed := float(s["speed"])
	var keys := []                       # [time, color]
	var length: float
	var flow := String(s["effect"]) == "pulse"
	if flow:
		length = speed * cols.size()
		for i in cols.size():
			keys.append([speed * i, cols[i]])
		keys.append([length, cols[0]])
	else:
		var step := speed * 0.2
		var n := maxi(cols.size() * 4, 12)
		length = step * n
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var last := -1
		for i in n:
			var pick := i % cols.size()
			if bool(s["random"]) and cols.size() > 1:
				pick = rng.randi_range(0, cols.size() - 1)
				if pick == last:
					pick = (pick + 1) % cols.size()
			last = pick
			keys.append([step * i, cols[pick]])
		keys.append([length, keys[0][1]])
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	for l in lights:
		var t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t, NodePath("%s:light_color" % (l as Node).name))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR if flow else Animation.INTERPOLATION_NEAREST)
		anim.value_track_set_update_mode(t, Animation.UPDATE_CONTINUOUS if flow else Animation.UPDATE_DISCRETE)
		for k in keys:
			anim.track_insert_key(t, minf(k[0], length), k[1])
	var lib := AnimationLibrary.new()
	lib.add_animation("colors", anim)
	var ap := AnimationPlayer.new()
	ap.name = "Colors"
	ap.add_animation_library("", lib)
	ap.autoplay = "colors"
	return ap


## The effect: the lights' brightness over time, looped, as an Animation (plays by itself, also in SurfsUp).
static func _effect_player(s: Dictionary, lights: Array) -> AnimationPlayer:
	var e := float(s["energy"]) / (sqrt(float(lights.size())) if s["kind"] == "strip" else 1.0)
	var keys := []                       # [time, brightness x]
	var length := 2.0
	var nearest := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	match s["effect"]:
		"flicker":
			length = 1.6
			for i in 17:
				keys.append([length * i / 16.0, rng.randf_range(0.55, 1.15)])
		"candle":
			length = 2.4
			for i in 13:
				keys.append([length * i / 12.0, rng.randf_range(0.8, 1.05)])
		"pulse":
			length = 2.0
			for i in 9:
				keys.append([length * i / 8.0, 0.55 + 0.45 * cos(TAU * i / 8.0)])
		"strobe":
			length = 0.5
			nearest = true
			keys = [[0.0, 1.3], [0.08, 0.0], [0.5, 0.0]]
		"fluorescent":
			length = 3.0
			nearest = true
			keys = [[0.0, 1.0], [1.7, 0.15], [1.76, 1.0], [1.84, 0.3], [1.9, 1.0], [3.0, 1.0]]
	keys[keys.size() - 1][1] = keys[0][1]                   # (seamless loop)
	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR
	for l in lights:
		var t := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(t, NodePath("%s:light_energy" % (l as Node).name))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_NEAREST if nearest else Animation.INTERPOLATION_LINEAR)
		anim.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE if nearest else Animation.UPDATE_CONTINUOUS)
		for k in keys:
			anim.track_insert_key(t, minf(k[0], length), e * float(k[1]))
	var lib := AnimationLibrary.new()
	lib.add_animation("fx", anim)
	var ap := AnimationPlayer.new()
	ap.name = "Effect"
	ap.add_animation_library("", lib)
	ap.autoplay = "fx"
	return ap


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


## In build mode a light is an invisible handle: its bulb hides and build mode draws a box around it instead.
static var hide_bulbs := false
const HANDLE := 1.0                       ## the handle box's size, meters (the bulb's size)


static func show_bulbs(root: Node, on: bool) -> void:
	hide_bulbs = not on
	for l in root.get_children():
		if l is LightNode:
			(l as LightNode)._bulb.visible = on


## The handle box around the light, world space.
func handle_box() -> AABB:
	return AABB(global_position - Vector3.ONE * HANDLE * 0.5, Vector3.ONE * HANDLE)


func label() -> String:
	return {"spot": "Spot light", "strip": "Light strip"}.get(data["kind"], "Light")


func rebuild() -> void:
	var s := spec(data)
	var p: Array = s["position"]
	transform = Transform3D(basis_of(s), Vector3(p[0], p[1], p[2]))
	if _rig:
		_rig.queue_free()
	_rig = make_rig(s)
	add_child(_rig)
	_light = _rig.get_child(0) as Light3D                  # (the main light: the only one, or a strip's first)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color.html(s["color"]).lightened(0.3)
	_bulb.material_override = m
	_bulb.visible = not hide_bulbs


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
	elif data["kind"] == "strip":
		var hl := float(data["length"]) * 0.5                 # the tube, and its reach around it
		out.append(PackedVector3Array([xf * Vector3(-hl, 0, 0), xf * Vector3(hl, 0, 0)]))
		for sgn in [-1.0, 1.0]:
			var ring := PackedVector3Array()
			for i in 17:
				var a := PI * i / 16.0
				ring.append(xf * Vector3(sgn * hl + sgn * sin(a) * r, cos(a) * r, 0))
			out.append(ring)
		out.append(PackedVector3Array([xf * Vector3(-hl, r, 0), xf * Vector3(hl, r, 0)]))
		out.append(PackedVector3Array([xf * Vector3(-hl, -r, 0), xf * Vector3(hl, -r, 0)]))
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
