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

## Ramp looks: [label, shader file or "" for a plain StandardMaterial3D, uses the color as]
const RAMP_LOOKS := {
	"color": ["Plain color", "", "color"],
	"ceramic": ["Glazed ceramic", "ramp_ceramic", "rim color"],
	"steel": ["Brushed steel", "ramp_steel", "tint"],
	"grid": ["Dev grid", "ramp_grid", "tint"],
	"aurora": ["Aurora (animated)", "ramp_aurora", "main color"],
	"nebula": ["Nebula", "ramp_nebula", "cloud color"],
	"neon": ["Neon edges", "ramp_neon", "glow color"],
	"texture": ["Image texture", "", "tint"],
	"material": ["Library material", "", "tint"],
	"shader": ["Your own shader", "", "fallback color"],
}
const LOOK_ORDER := ["color", "ceramic", "steel", "grid", "aurora", "nebula", "neon", "texture", "material", "shader"]

## Liquids (block water and build mode's water / lava): style "water" (waves, depth, foam) or "lava" (crust over glowing
## cracks). "css": the CS:S water material it exports as (lava exports as a self-lit color).
const LIQUIDS := {
	"water": {"label": "Clear blue water", "style": "water", "color": "2a8fb0", "deep": "0a2f4a", "clarity": 0.65,
		"waves": 1.0, "foam": 0.5, "css": "LIQUIDS/AZTECWATER"},
	"pool": {"label": "Swimming pool", "style": "water", "color": "52c7e0", "deep": "1873a8", "clarity": 0.9,
		"waves": 0.4, "foam": 0.2, "css": "nature/water_canals_water_clear"},
	"tropical": {"label": "Tropical sea", "style": "water", "color": "3fd1c4", "deep": "0d5a78", "clarity": 0.8,
		"waves": 1.3, "foam": 0.8, "css": "nature/water_coast01"},
	"lake": {"label": "Dark lake", "style": "water", "color": "2f5d55", "deep": "0a1c1a", "clarity": 0.35,
		"waves": 0.7, "foam": 0.3, "css": "liquids/militiawater"},
	"swamp": {"label": "Murky swamp", "style": "water", "color": "4d5530", "deep": "1a1c0c", "clarity": 0.08,
		"waves": 0.3, "foam": 0.15, "css": "nature/water_canals_water_murky"},
	"river": {"label": "Flowing river", "style": "water", "color": "3a8aa0", "deep": "103a4a", "clarity": 0.55,
		"waves": 1.0, "foam": 0.7, "flow": [0.0, 1.2], "css": "nature/water_canals_city"},
	"acid": {"label": "Toxic acid (deadly)", "style": "water", "color": "7dff3a", "deep": "1e5a10", "clarity": 0.3,
		"waves": 0.6, "foam": 0.6, "glow": 1.2, "deadly": true, "css": "nature/sewer_water001"},
	"lava": {"label": "Lava (deadly)", "style": "lava", "color": "ff4a0a", "hot": "ffb020", "crust": "2a1208",
		"crust_amount": 0.45, "glow": 3.0, "flow": [0.3, 0.1], "deadly": true},
	"magma": {"label": "Magma, thick crust (deadly)", "style": "lava", "color": "e03008", "hot": "ffd060",
		"crust": "140a06", "crust_amount": 0.65, "glow": 2.5, "flow": [0.12, 0.05], "deadly": true},
	"plasma": {"label": "Plasma (deadly)", "style": "lava", "color": "4a6aff", "hot": "e0f0ff", "crust": "0a0a30",
		"crust_amount": 0.35, "glow": 3.5, "flow": [0.0, 0.6], "deadly": true},
}
const LIQUID_ORDER := ["water", "pool", "tropical", "lake", "swamp", "river", "acid", "lava", "magma", "plasma"]
const GLASS := {
	"clear": {"label": "Clear glass", "color": "e6f4ff", "clarity": 0.85, "frost": 0.0},
	"blue": {"label": "Blue tinted", "color": "6aa8ff", "clarity": 0.7, "frost": 0.0},
	"green": {"label": "Bottle green", "color": "4ac080", "clarity": 0.6, "frost": 0.0},
	"frosted": {"label": "Frosted", "color": "f0f4f8", "clarity": 0.75, "frost": 0.7},
	"smoked": {"label": "Smoked", "color": "30343a", "clarity": 0.45, "frost": 0.1},
}
const GLASS_ORDER := ["clear", "blue", "green", "frosted", "smoked"]

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


# ------------------------------------------------------------------------------------------------ built-in settings
## Every setting (uniform) of every shader MALLET ships is editable somewhere (0.25.1). BUILTIN_COVERED lists the ones
## that have a control of their own (where) or are deliberately internal (why); every other uniform gets a control
## automatically, read from the shader like your own shaders' (param_uniforms), stored with the object as it is for
## your own shaders. A uniform added to a shader later is therefore shown without anyone remembering to; the test
## shader_coverage_test fails if a shader's uniform is in neither place.
const BUILTIN_COVERED := {
	"sky": {"top_color": "Map panel: Sky color (top)", "horizon_color": "Map panel: Sky color (horizon)",
		"ground_color": "Map panel: Below the horizon", "stars": "Map panel: Stars", "aurora": "Map panel: Aurora",
		"nebula": "Map panel: Nebula clouds"},
	"water": {"tint": "the water's Color", "clarity": "the water's Clarity",
		"screen_tex": "internal: the picture behind the water (for refraction)", "depth_tex": "internal: the depth behind the water"},
	"lava": {"tint": "the lava's Color"},
	"glass": {"screen_tex": "internal: the picture behind the glass (for refraction)"},
	"ramp_aurora": {"tint": "the Color (first aurora color)"},
	"ramp_ceramic": {"tint": "the Color (rim)"},
	"ramp_grid": {"tint": "the Color", "square": "internal: square cells on blocks and cubes, set by MALLET"},
	"ramp_nebula": {"tint": "the Color"},
	"ramp_neon": {"tint": "the Color"},
	"ramp_steel": {"tint": "the Color"},
}
## Shaders whose every setting comes from somewhere else (no controls of their own).
const BUILTIN_INTERNAL := {
	"cube_surface": "build mode's texture settings (F3) and the material set all of it",
	"cube_lines": "outline mode's lines (7 in build mode)",
}
## Friendlier names for some settings than the uniform's own ("tint_b" -> "Second color").
const BUILTIN_LABELS := {
	"sky": {"aurora_a": "Aurora color 1", "aurora_b": "Aurora color 2", "nebula_color": "Nebula color", "sun_size": "Sun size"},
	"ramp_aurora": {"tint_b": "Second color"},
	"water": {"deep_color": "Deep color", "flow": "Flow (m/s, x / z)", "refraction": "Refraction", "glow": "Liquid glow"},
	"lava": {"hot_color": "Hottest color", "crust_color": "Crust color", "crust": "Crust amount", "flow": "Flow (m/s, x / z)",
		"scale": "Blob size (bigger = smaller)", "glow": "Lava glow"},
	"glass": {"tint": "Glass color"},
}
static var _param_cache := {}


## The settings of built-in shader `file` that get a control (UserShaders' format), the values shown taken from `base`
## (the material as its preset made it) where it has them.
static func param_uniforms(file: String, base: Material = null) -> Array:
	if not _param_cache.has(file):
		var s := shader(file)
		var covered: Dictionary = BUILTIN_COVERED.get(file, {})
		var list := s.get_shader_uniform_list().filter(func(u): return not covered.has(String(u["name"])))
		var got: Array = UserShaders._read_uniforms(s, list, s.code) if not BUILTIN_INTERNAL.has(file) else []
		var names: Dictionary = BUILTIN_LABELS.get(file, {})
		for c in got:
			if names.has(c["name"]):
				c["label"] = names[c["name"]]
		_param_cache[file] = got
	var out := []
	for u in _param_cache[file]:
		var c: Dictionary = (u as Dictionary).duplicate()
		if base is ShaderMaterial:
			var v = (base as ShaderMaterial).get_shader_parameter(c["name"])
			if v != null:
				c["default"] = Color(v.x, v.y, v.z, 1.0) if c["type"] == "color" and (v is Vector3 or v is Vector4) else v
		out.append(c)
	return out


## Put stored settings (uniform -> value, as UserShaders.encode makes them) on a built-in shader's material.
static func apply_params(m: Material, file: String, params) -> void:
	if not m is ShaderMaterial or not params is Dictionary or (params as Dictionary).is_empty():
		return
	for u in param_uniforms(file):
		if (params as Dictionary).has(u["name"]):
			var v = UserShaders.decode(u, params[u["name"]])
			if v != null:
				(m as ShaderMaterial).set_shader_parameter(u["name"], v)


## The shader file behind a built-in ramp / block look ("" for plain looks).
static func look_shader(look: String) -> String:
	return String(RAMP_LOOKS.get(look, RAMP_LOOKS["color"])[1]) if look in RAMP_LOOKS else ""


static func _c(env: Dictionary, key: String) -> Color:
	return Color.html(env.get(key, default_environment()[key]))


## The map's sky material: your own sky shader (environment "sky_shader" + "sky_params") when it works, else the
## built-in one. Second value: whether it moves (needs redrawing every frame). A canvas_item sky is its live picture
## wrapped around the world (UserShaders.canvas_sky_material); `still` takes a copy of its last frame instead (exports).
static func sky_material(env: Dictionary, still := false) -> Array:
	var id := String(env.get("sky_shader", ""))
	if id != "" and UserShaders.is_canvas(id):
		var cm := UserShaders.canvas_sky_material(id, env.get("sky_params", {}), still)
		if cm:
			return [cm, false if still else bool(UserShaders.entry(id)["animated"])]
	elif id != "":
		var um := UserShaders.material(id, env.get("sky_params", {}))
		if um:
			return [um, UserShaders.entry(id)["animated"]]
	var mat := ShaderMaterial.new()
	mat.shader = shader("sky")
	mat.set_shader_parameter("top_color", _c(env, "sky_top"))
	mat.set_shader_parameter("horizon_color", _c(env, "sky_horizon"))
	mat.set_shader_parameter("ground_color", _c(env, "ground"))
	mat.set_shader_parameter("stars", float(env.get("stars", 0.0)))
	mat.set_shader_parameter("aurora", float(env.get("aurora", 0.0)))
	mat.set_shader_parameter("nebula", float(env.get("nebula", 0.0)))
	apply_params(mat, "sky", env.get("sky_look", {}))     # (aurora colors, nebula color, sun size...)
	return [mat, float(env.get("aurora", 0.0)) > 0.0 or float(env.get("nebula", 0.0)) > 0.0 or float(env.get("stars", 0.0)) > 0.0]


## `still`: for a scene that gets saved (the SurfsUp export): a canvas_item sky as a still picture (sky_material).
static func build_environment(env: Dictionary, still := false) -> Environment:
	var e := Environment.new()
	var sky := Sky.new()
	var sm := sky_material(env, still)
	sky.sky_material = sm[0]
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if sm[1] else Sky.PROCESS_MODE_AUTOMATIC
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
	e.ssr_enabled = bool(env.get("reflections", false))   # (glossy, reflective materials show the map itself too)
	e.ssr_max_steps = 96
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


## Material for a ramp. `texture_scale` = how many meters one copy of the image covers.
## `square`: for blocks and cubes (world-meter UVs): the Dev grid as even 1 m squares instead of the ramp layout.
## `shader_id` / `shader_params`: look "shader" (your own surface shader; a plain `color` while it doesn't work).
## A ramp's texture settings, the same as a cube face's in build mode (0.19.5): r turn / flip (0-5), u / v shift
## (in repeats), su / sv scroll (repeats a second), sp spin (degrees a second) and sw swirl (degrees) for spiral
## motion (0.23.0), a see-through (1 = solid). Missing keys are the defaults.
const RAMP_TEX_DEFAULTS := {"r": 0, "u": 0.0, "v": 0.0, "su": 0.0, "sv": 0.0, "sp": 0.0, "sw": 0.0, "a": 1.0}


static func ramp_tex_plain(t: Dictionary) -> bool:
	for k in RAMP_TEX_DEFAULTS:
		if t.has(k) and t[k] != RAMP_TEX_DEFAULTS[k] and float(t[k]) != float(RAMP_TEX_DEFAULTS[k]):
			return false
	return true


## A ramp mesh with its texture turned, shifted and scrolling as `t` says, drawn with the same surface shader as
## build mode's cube faces; null when there's nothing to do (plain settings, or a look without a texture) - then the
## usual ramp_material is used.
static func ramp_textured(mesh: ArrayMesh, look: String, color: Color, texture_path: String, texture_scale: float,
		material_id: String, face_length: float, t: Dictionary) -> ArrayMesh:
	if ramp_tex_plain(t) or not look in ["material", "texture"]:
		return null
	var base: StandardMaterial3D = null
	var sx := 1.0
	var sy := 20.0 / maxf(texture_scale, 0.5)
	var albedo: Texture2D = null
	if look == "material":
		if not MaterialLibrary.has(material_id):
			return null
		base = MaterialLibrary.material(material_id, Color.WHITE)
		albedo = base.albedo_texture
		var size := MaterialLibrary.world_size(material_id) * maxf(texture_scale / 20.0, 0.05)
		sx = 1.0 if MaterialLibrary.ramp_fit(material_id) else face_length / size
		sy = 20.0 / size
	else:
		albedo = image_texture(texture_path)
		if albedo == null:
			return null
	var r := int(t.get("r", 0))
	var off := Vector2(float(t.get("u", 0.0)), float(t.get("v", 0.0)))
	var a := float(t.get("a", 1.0))
	var sm := ShaderMaterial.new()
	sm.shader = CubeWorld._surface_shader(a < 1.0, true)  # (two-sided, like every ramp material)
	sm.set_shader_parameter("albedo_tex", albedo)
	if base and base.normal_texture:
		sm.set_shader_parameter("normal_tex", base.normal_texture)
		sm.set_shader_parameter("has_normal", true)
	if base and base.roughness_texture:
		sm.set_shader_parameter("rough_tex", base.roughness_texture)
		sm.set_shader_parameter("has_rough", true)
	sm.set_shader_parameter("tint", color if look == "material" else Color.WHITE * color)
	sm.set_shader_parameter("alpha", a)
	sm.set_shader_parameter("scroll", Vector2(float(t.get("su", 0.0)), float(t.get("sv", 0.0))))
	sm.set_shader_parameter("spin", float(t.get("sp", 0.0)))
	sm.set_shader_parameter("swirl", float(t.get("sw", 0.0)))
	if look == "material":
		MaterialLibrary.shader_finish(sm, material_id)
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		for i in uv.size():
			var p := Vector2(uv[i].x * sx, uv[i].y * sy)
			match r:
				1: p = Vector2(-p.y, p.x)
				2: p = -p
				3: p = Vector2(p.y, -p.x)
				4: p = Vector2(-p.x, p.y)
				5: p = Vector2(p.x, -p.y)
			uv[i] = p + off
		arr[Mesh.ARRAY_TEX_UV] = uv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(si, sm)
	return out


static func ramp_material(look: String, color: Color, texture_path := "", texture_scale := 20.0, material_id := "",
		face_length := 10.5, square := false, shader_id := "", shader_params := {}) -> Material:
	# (a built-in shader look keeps its settings in shader_params too: the aurora's second color...)
	if look == "shader":
		var um := UserShaders.material(shader_id, shader_params)
		if um:
			return um
	if look == "material" and MaterialLibrary.has(material_id):
		# ramp UVs: u = 0..1 across the face, v = meters along / 20; size the library texture to the real world
		var size := MaterialLibrary.world_size(material_id) * maxf(texture_scale / 20.0, 0.05)
		var key := "%s|%s|%s|%s" % [material_id, color.to_html(), size, face_length]
		if not _ramp_mats.has(key):
			var m: StandardMaterial3D = MaterialLibrary.material(material_id, color).duplicate()
			m.uv1_scale = Vector3(1.0 if MaterialLibrary.ramp_fit(material_id) else face_length / size, 20.0 / size, 1.0)
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
		apply_params(m, info[1], shader_params)
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
			# ramp UVs: u = 0..1 across the riding face, v = meters along / 20
			sm.uv1_scale = Vector3(1.0, 20.0 / max(texture_scale, 0.5), 1.0)
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return sm


## A liquid preset (LIQUIDS) as a material; `color` / `clarity` (block settings) override the preset's own.
static func liquid_material(id: String, color = null, clarity = null) -> ShaderMaterial:
	var p: Dictionary = LIQUIDS.get(id, LIQUIDS["water"])
	var m := ShaderMaterial.new()
	var c: Color = color if color is Color else Color.html(p["color"])
	var fl: Array = p.get("flow", [0.0, 0.0])
	if p["style"] == "lava":
		m.shader = shader("lava")
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("hot_color", Color.html(p["hot"]))
		m.set_shader_parameter("crust_color", Color.html(p["crust"]))
		m.set_shader_parameter("crust", float(p.get("crust_amount", 0.45)))
		m.set_shader_parameter("glow", float(p.get("glow", 3.0)))
		m.set_shader_parameter("flow", Vector2(fl[0], fl[1]))
	else:
		m.shader = shader("water")
		m.set_shader_parameter("tint", c)
		m.set_shader_parameter("deep_color", Color.html(p["deep"]) if color == null else c.darkened(0.7))
		m.set_shader_parameter("clarity", float(clarity) if clarity != null else float(p["clarity"]))
		m.set_shader_parameter("waves", float(p.get("waves", 1.0)))
		m.set_shader_parameter("foam", float(p.get("foam", 0.5)))
		m.set_shader_parameter("glow", float(p.get("glow", 0.0)))
		m.set_shader_parameter("flow", Vector2(fl[0], fl[1]))
	return m


## A glass preset (GLASS) as a material.
static func glass_material(id: String) -> ShaderMaterial:
	var p: Dictionary = GLASS.get(id, GLASS["clear"])
	var m := ShaderMaterial.new()
	m.shader = shader("glass")
	m.set_shader_parameter("tint", Color.html(p["color"]))
	m.set_shader_parameter("clarity", float(p["clarity"]))
	m.set_shader_parameter("frost", float(p["frost"]))
	return m



## Source's six skybox faces: suffix -> [the way the face looks, the image's up], in Source coordinates (x east,
## y north, z up). Worked out from the seams and suns of CS:S's own skies and maps.
const SKYBOX_FACES := {"rt": [Vector3(1, 0, 0), Vector3(0, 0, 1)], "bk": [Vector3(0, 1, 0), Vector3(0, 0, 1)],
	"lf": [Vector3(-1, 0, 0), Vector3(0, 0, 1)], "ft": [Vector3(0, -1, 0), Vector3(0, 0, 1)],
	"up": [Vector3(0, 0, 1), Vector3(-1, 0, 0)], "dn": [Vector3(0, 0, -1), Vector3(1, 0, 0)]}


## Render the map's sky (built-in or your own shader, with its sun) into the six images of a Source skybox.
## Needs a node in the scene tree to borrow frames from. Returns suffix -> Image (RGB8, size x size).
static func bake_skybox(env: Dictionary, host: Node, size := 512) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var we := WorldEnvironment.new()
	var e := build_environment(env)
	e.glow_enabled = false                               # (glow would bleed differently at each face's edges)
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	apply_sun(sun, env)
	sun.shadow_enabled = false
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 90.0
	cam.far = 100.0
	vp.add_child(cam)
	host.add_child(vp)
	cam.current = true
	var out := {}
	for sfx in SKYBOX_FACES:
		var f: Vector3 = SKYBOX_FACES[sfx][0]
		var u: Vector3 = SKYBOX_FACES[sfx][1]
		cam.basis = Basis.looking_at(Vector3(f.x, f.z, -f.y), Vector3(u.x, u.z, -u.y))   # (Source -> Godot axes)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		out[sfx] = img
	vp.queue_free()
	return out
