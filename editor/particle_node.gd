class_name ParticleNode
extends Node3D
## A particle effect: fire, smoke, sparks, embers, snow, rain, dust, mist or magic sparkles, from a box-shaped area.
## Godot's GPU particles with a soft round sprite made in code, so it plays live in the editor and play mode and goes
## into SurfsUp maps as it is (no script). CS:S gets the nearest stock effect (see VmfExporter).

const PICK_ONLY_LAYER := 1 << 19
const DEFAULTS := {
	"preset": "fire", "position": [0.0, 0.0, 0.0], "yaw": 0.0,
	"area": [1.0, 0.2, 1.0],             ## meters: the box the particles start in (centered on the position)
	"amount": 1.0,                       ## x the preset's number of particles
	"size": 1.0,                         ## x the preset's particle size
	"speed": 1.0,                        ## x the preset's speed
	"color": "",                         ## "" = the preset's own colors
}
## Each preset: count, lifetime (s), how they start moving (dir, spread °, speed m/s), gravity (m/s², +y up), size (m)
## at birth and how it grows, colors over their life, blend (add = glowing, mix = solid), a sprite shape (w, h) and
## the area it suggests. "css": the CS:S entity it becomes.
const PRESETS := {
	"fire": {"label": "Fire", "count": 90, "life": 0.9, "dir": [0, 1, 0], "spread": 14.0, "speed": [1.5, 3.0], "gravity": 1.5,
		"size": 0.7, "grow": 0.2, "colors": ["fff2a0", "ffa020", "e03008", "30100800"], "blend": "add", "area": [0.8, 0.1, 0.8],
		"css": "env_fire"},
	"smoke": {"label": "Smoke", "count": 40, "life": 4.0, "dir": [0, 1, 0], "spread": 18.0, "speed": [0.8, 1.6], "gravity": 0.25,
		"size": 1.0, "grow": 3.0, "colors": ["5a5a5a90", "70707060", "80808000"], "blend": "mix", "area": [0.8, 0.1, 0.8],
		"css": "env_smokestack"},
	"sparks": {"label": "Sparks", "count": 60, "life": 0.8, "dir": [0, 1, 0], "spread": 60.0, "speed": [4.0, 8.0], "gravity": -9.8,
		"size": 0.06, "grow": 1.0, "colors": ["ffffd0", "ffc040", "ff602000"], "blend": "add", "area": [0.1, 0.1, 0.1],
		"css": "env_spark"},
	"embers": {"label": "Embers", "count": 40, "life": 3.0, "dir": [0, 1, 0], "spread": 40.0, "speed": [0.5, 1.5], "gravity": 0.6,
		"size": 0.08, "grow": 1.0, "colors": ["ffd060", "ff6010", "a0200000"], "blend": "add", "area": [2.0, 0.2, 2.0],
		"css": "env_smokestack"},
	"snow": {"label": "Snow", "count": 500, "life": 8.0, "dir": [0, -1, 0], "spread": 25.0, "speed": [0.8, 1.4], "gravity": -0.2,
		"size": 0.08, "grow": 1.0, "colors": ["ffffff", "ffffffe0", "ffffff00"], "blend": "mix", "area": [20.0, 0.5, 20.0],
		"css": "func_precipitation"},
	"rain": {"label": "Rain", "count": 900, "life": 1.2, "dir": [0, -1, 0], "spread": 3.0, "speed": [11.0, 14.0], "gravity": -9.8,
		"size": 0.6, "grow": 1.0, "colors": ["b0c8ff90", "b0c8ff70", "b0c8ff00"], "blend": "mix", "area": [20.0, 0.5, 20.0],
		"shape": [0.03, 1.0], "css": "func_precipitation"},
	"dust": {"label": "Floating dust", "count": 120, "life": 6.0, "dir": [0, 1, 0], "spread": 180.0, "speed": [0.05, 0.2],
		"gravity": 0.0, "size": 0.05, "grow": 1.0, "colors": ["e8dcc000", "e8dcc0a0", "e8dcc000"], "blend": "mix",
		"area": [10.0, 4.0, 10.0], "css": ""},
	"mist": {"label": "Mist / waterfall spray", "count": 30, "life": 6.0, "dir": [0, 1, 0], "spread": 50.0, "speed": [0.2, 0.5],
		"gravity": 0.05, "size": 3.0, "grow": 1.8, "colors": ["ffffff00", "ffffff30", "ffffff00"], "blend": "mix",
		"area": [8.0, 1.0, 8.0], "css": "env_steam"},
	"magic": {"label": "Magic sparkles", "count": 60, "life": 2.5, "dir": [0, 1, 0], "spread": 180.0, "speed": [0.3, 0.8],
		"gravity": 0.2, "size": 0.12, "grow": 0.3, "colors": ["ffffff", "c080ff", "6040ff00"], "blend": "add",
		"area": [2.0, 2.0, 2.0], "css": ""},
}
const PRESET_ORDER := ["fire", "smoke", "sparks", "embers", "snow", "rain", "dust", "mist", "magic"]

var data := DEFAULTS.duplicate(true)
var _fx: GPUParticles3D
var _body := StaticBody3D.new()
var _shape := CollisionShape3D.new()
static var _sprite: Texture2D = null


static func spec(d: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate(true)
	for k in DEFAULTS:
		if d.has(k):
			s[k] = d[k]
	if not PRESETS.has(s["preset"]):
		s["preset"] = "fire"
	return s


## How many particles it keeps alive (for the map's weight readout).
static func particle_count(s: Dictionary) -> int:
	return maxi(int(float(PRESETS[s["preset"]]["count"]) * float(s["amount"])), 1)


## A soft round dot, made once (shared by every emitter, embedded in exports).
static func sprite() -> Texture2D:
	if _sprite == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_sprite = t
	return _sprite


## The effect as a GPUParticles3D for these settings (the editor's and the SurfsUp export's). Not positioned.
static func make_emitter(s: Dictionary) -> GPUParticles3D:
	var p: Dictionary = PRESETS[s["preset"]]
	var area: Array = s["area"]
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area[0], area[1], area[2]) * 0.5
	var dir: Array = p["dir"]
	pm.direction = Vector3(dir[0], dir[1], dir[2])
	pm.spread = float(p["spread"])
	var sp: Array = p["speed"]
	pm.initial_velocity_min = float(sp[0]) * float(s["speed"])
	pm.initial_velocity_max = float(sp[1]) * float(s["speed"])
	pm.gravity = Vector3(0, float(p["gravity"]), 0)
	if s["preset"] in ["embers", "magic", "dust"]:
		pm.turbulence_enabled = true                   # (drifting, not straight lines)
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 1.0))
	grow.add_point(Vector2(1, float(p["grow"])))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var ramp := Gradient.new()
	var cols: Array = p["colors"]
	var own: String = s["color"]
	for i in cols.size():
		var c := Color.html(cols[i])
		if own != "":                                  # the map maker's color, keeping the preset's fading
			var oc := Color.html(own)
			c = Color(oc.r, oc.g, oc.b, c.a)
		var at := float(i) / float(cols.size() - 1)
		if i < 2:
			ramp.set_offset(i, at)
			ramp.set_color(i, c)
		else:
			ramp.add_point(at, c)
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var fx := GPUParticles3D.new()
	fx.process_material = pm
	fx.amount = particle_count(s)
	fx.lifetime = float(p["life"])
	fx.preprocess = float(p["life"])                   # (already going when the map loads)
	var quad := QuadMesh.new()
	var shape: Array = p.get("shape", [1.0, 1.0])
	quad.size = Vector2(shape[0], shape[1]) * float(p["size"]) * float(s["size"]) if p.has("shape") \
		else Vector2.ONE * float(p["size"]) * float(s["size"])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = sprite() if not p.has("shape") else null
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if p["blend"] == "add" else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	fx.draw_pass_1 = quad
	var reach: float = float(sp[1]) * float(s["speed"]) * float(p["life"]) + float(p["size"]) * float(p["grow"]) * 2.0
	fx.visibility_aabb = AABB(-Vector3(area[0], area[1], area[2]) * 0.5 - Vector3.ONE * reach,
		Vector3(area[0], area[1], area[2]) + Vector3.ONE * reach * 2.0)
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return fx


func _ready() -> void:
	_body.add_child(_shape)
	_body.set_meta("particle", self)
	_body.collision_layer = PICK_ONLY_LAYER
	_body.collision_mask = 0
	add_child(_body)
	rebuild()


func label() -> String:
	return PRESETS[spec(data)["preset"]]["label"]


func rebuild() -> void:
	var s := spec(data)
	var p: Array = s["position"]
	transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), Vector3(p[0], p[1], p[2]))
	if _fx:
		_fx.queue_free()
	_fx = make_emitter(s)
	add_child(_fx)
	var bs := BoxShape3D.new()
	var a: Array = s["area"]
	bs.size = Vector3(maxf(a[0], 1.0), maxf(a[1], 1.0), maxf(a[2], 1.0))
	_shape.shape = bs


func set_selected(_on: bool) -> void:
	pass


## The area the particles start in, as a box.
func outline_lines() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	var a: Array = spec(data)["area"]
	var h := Vector3(a[0], a[1], a[2]) * 0.5
	var xf := global_transform
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		out.append(PackedVector3Array([c[e[0]], c[e[1]]]))
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
