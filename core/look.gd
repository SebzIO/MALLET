class_name Look
extends RefCounted
## Map environment (sky / sun / fog) and ramp materials, shared by the editor, play mode and the exporters.
## Everything is built from embedded resources (shader code, image data) so an exported map is self-contained,
## and nothing here is a script, so SurfsUp accepts it.

const SHADER_DIR := "res://core/shaders/"

const ENV_PRESETS := {
	"day": {"label": "Clear day", "sky_top": "5277ad", "sky_horizon": "adbdd1", "ground": "2e3038", "sun_yaw": -35.0, "sun_pitch": 55.0,
		"sun_color": "fff2e0", "sun_energy": 1.0, "ambient_color": "c8d4e6", "ambient_energy": 0.6, "stars": 0.0, "aurora": 0.0, "nebula": 0.0,
		"fog": false, "fog_color": "adbdd1", "fog_density": 0.0006},
	"sunset": {"label": "Sunset", "sky_top": "2c3566", "sky_horizon": "f58c59", "ground": "2a2230", "sun_yaw": 70.0, "sun_pitch": 7.0,
		"sun_color": "ffb070", "sun_energy": 1.2, "ambient_color": "d9a090", "ambient_energy": 0.6, "stars": 0.15, "aurora": 0.0, "nebula": 0.0,
		"fog": true, "fog_color": "e89a72", "fog_density": 0.00035},
	"overcast": {"label": "Overcast", "sky_top": "8a9099", "sky_horizon": "b8bcc2", "ground": "4a4d52", "sun_yaw": -20.0, "sun_pitch": 60.0,
		"sun_color": "d8dde5", "sun_energy": 0.6, "ambient_color": "c0c4ca", "ambient_energy": 0.9, "stars": 0.0, "aurora": 0.0, "nebula": 0.0,
		"fog": true, "fog_color": "b0b5bc", "fog_density": 0.0015},
	"night": {"label": "Night", "sky_top": "030612", "sky_horizon": "101a33", "ground": "05070c", "sun_yaw": 30.0, "sun_pitch": 40.0,
		"sun_color": "8fa8ff", "sun_energy": 0.35, "ambient_color": "4a5a8a", "ambient_energy": 0.7, "stars": 1.0, "aurora": 0.0, "nebula": 0.0,
		"fog": false, "fog_color": "101a33", "fog_density": 0.0006},
	"aurora": {"label": "Aurora", "sky_top": "02060f", "sky_horizon": "0b1d2b", "ground": "03060a", "sun_yaw": 10.0, "sun_pitch": 35.0,
		"sun_color": "9fc0ff", "sun_energy": 0.3, "ambient_color": "3a6a70", "ambient_energy": 0.7, "stars": 0.8, "aurora": 1.0, "nebula": 0.0,
		"fog": false, "fog_color": "0b1d2b", "fog_density": 0.0006},
	"space": {"label": "Deep space", "sky_top": "000000", "sky_horizon": "06030f", "ground": "000000", "sun_yaw": -60.0, "sun_pitch": 25.0,
		"sun_color": "ffffff", "sun_energy": 1.1, "ambient_color": "4a3a6a", "ambient_energy": 0.7, "stars": 1.0, "aurora": 0.0, "nebula": 1.0,
		"fog": false, "fog_color": "06030f", "fog_density": 0.0006},
}

## Ramp looks: [label, shader file or "" for a plain StandardMaterial3D, uses the colour as]
const RAMP_LOOKS := {
	"color": ["Plain colour", "", "colour"],
	"ceramic": ["Glazed ceramic", "ramp_ceramic", "rim colour"],
	"steel": ["Brushed steel", "ramp_steel", "tint"],
	"grid": ["Dev grid", "ramp_grid", "tint"],
	"aurora": ["Aurora (animated)", "ramp_aurora", "main colour"],
	"nebula": ["Nebula", "ramp_nebula", "cloud colour"],
	"neon": ["Neon edges", "ramp_neon", "glow colour"],
	"texture": ["Image texture", "", "tint"],
	"material": ["Library material", "", "tint"],
}
const LOOK_ORDER := ["color", "ceramic", "steel", "grid", "aurora", "nebula", "neon", "texture", "material"]

static var _shaders := {}
static var _ramp_mats := {}
static var _textures := {}


static func default_environment() -> Dictionary:
	var d: Dictionary = ENV_PRESETS["day"].duplicate()
	d.erase("label")
	d["preset"] = "day"
	return d


static func preset_environment(key: String) -> Dictionary:
	var d: Dictionary = ENV_PRESETS[key].duplicate()
	d.erase("label")
	d["preset"] = key
	return d


## A fresh copy of a shader, embedded (no resource path) so saving a scene stores its code inline.
static func shader(file: String) -> Shader:
	if not _shaders.has(file):
		var s := Shader.new()
		s.code = FileAccess.get_file_as_string(SHADER_DIR + file + ".gdshader")
		_shaders[file] = s
	return _shaders[file]


static func _c(env: Dictionary, key: String) -> Color:
	return Color.html(env.get(key, default_environment()[key]))


static func build_environment(env: Dictionary) -> Environment:
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader("sky")
	mat.set_shader_parameter("top_color", _c(env, "sky_top"))
	mat.set_shader_parameter("horizon_color", _c(env, "sky_horizon"))
	mat.set_shader_parameter("ground_color", _c(env, "ground"))
	mat.set_shader_parameter("stars", float(env.get("stars", 0.0)))
	mat.set_shader_parameter("aurora", float(env.get("aurora", 0.0)))
	mat.set_shader_parameter("nebula", float(env.get("nebula", 0.0)))
	sky.sky_material = mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if float(env.get("aurora", 0.0)) > 0.0 or float(env.get("nebula", 0.0)) > 0.0 \
		or float(env.get("stars", 0.0)) > 0.0 else Sky.PROCESS_MODE_AUTOMATIC
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = _c(env, "ambient_color")
	e.ambient_light_energy = float(env.get("ambient_energy", 0.6))
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	e.fog_enabled = bool(env.get("fog", false))
	e.fog_light_color = _c(env, "fog_color")
	e.fog_density = float(env.get("fog_density", 0.0006))
	e.fog_sky_affect = 0.4
	return e


static func apply_sun(light: DirectionalLight3D, env: Dictionary) -> void:
	light.rotation_degrees = Vector3(-float(env.get("sun_pitch", 55.0)), float(env.get("sun_yaw", -35.0)), 0.0)
	light.light_color = _c(env, "sun_color")
	light.light_energy = float(env.get("sun_energy", 1.0))
	light.shadow_enabled = true


## Downscaled, compressed, embeddable texture from an image file on disk (null if it can't be read).
static func image_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	var longest: int = max(img.get_width(), img.get_height())
	if longest > 1024:
		var k := 1024.0 / longest
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true          # without this the image data is not saved into the map
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, false, 0.85)
	_textures[path] = tex
	return tex


## Material for a ramp. `texture_scale` = how many metres one copy of the image covers.
## `square`: for blocks and cubes (world-metre UVs): the Dev grid as even 1 m squares instead of the ramp layout.
static func ramp_material(look: String, color: Color, texture_path := "", texture_scale := 20.0, material_id := "",
		face_length := 10.5, square := false) -> Material:
	if look == "material" and MaterialLibrary.has(material_id):
		# ramp UVs: u = 0..1 across the face, v = metres along / 20; size the library texture to the real world
		var size := MaterialLibrary.world_size(material_id) * maxf(texture_scale / 20.0, 0.05)
		var key := "%s|%s|%s|%s" % [material_id, color.to_html(), size, face_length]
		if not _ramp_mats.has(key):
			var m: StandardMaterial3D = MaterialLibrary.material(material_id, color).duplicate()
			m.uv1_scale = Vector3(face_length / size, 20.0 / size, 1.0)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			_ramp_mats[key] = m
		return _ramp_mats[key]
	var info: Array = RAMP_LOOKS.get(look, RAMP_LOOKS["color"])
	if info[1] != "":
		var m := ShaderMaterial.new()
		m.shader = shader(info[1])
		m.set_shader_parameter("tint", color)
		if look == "grid":
			m.set_shader_parameter("square", square)
		return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = color
	sm.roughness = 0.25
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if look == "texture":
		var tex := image_texture(texture_path)
		if tex:
			sm.albedo_texture = tex
			sm.roughness = 0.6
			# ramp UVs: u = 0..1 across the riding face, v = metres along / 20
			sm.uv1_scale = Vector3(1.0, 20.0 / max(texture_scale, 0.5), 1.0)
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return sm
