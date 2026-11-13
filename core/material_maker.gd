class_name MaterialMaker
extends SubViewport
## The material maker (0.21.0): your own material from a starting material (or a plain color) and layers on top of
## it, drawn live on this little 2D canvas. Layers, bottom to top:
##   adjust   hue / saturation / brightness / contrast of everything under it
##   fill     one color over all of it
##   stripe   a straight band (vertical = along a ramp, horizontal = across), at any angle, soft or hard
##   rect, ellipse   a shape
##   text     words
##   image    a picture of yours, placed and sized
##   paint    painted by hand with a brush (an image of its own, saved as a PNG next to the material)
## Every layer has a color, an opacity and a blend (mix, add, multiply, subtract). Shapes wrap at the edges, so the
## texture still tiles. Saved materials land in "Made by you" (MaterialLibrary, USER_DIR/made_<name>/), keep their
## recipe so they can be opened and changed again, take the starting material's surface detail (normal, roughness,
## metal and glow maps), and travel inside the maps that use them.

const SIZE := 1024                           ## pixels of a saved material (MaterialLibrary.MAX_SIZE)
const PREVIEW := 512                         ## pixels while editing
const CATEGORY := "Made by you"
const TYPES := ["adjust", "fill", "stripe", "rect", "ellipse", "text", "image", "paint"]
const TYPE_NAMES := {"adjust": "Adjust colors", "fill": "Fill", "stripe": "Stripe / line", "rect": "Rectangle",
	"ellipse": "Ellipse", "text": "Text", "image": "Image", "paint": "Paint"}
const BLENDS := ["mix", "add", "multiply", "subtract"]
const SHAPES := {"fill": 0, "stripe": 1, "rect": 3, "ellipse": 4}

var recipe := {}
var images := {}                              ## layer file name -> Image (paint and image layers)
var _textures := {}                           ## layer file name -> ImageTexture (updated while painting)
static var _shaders := {}


static func new_recipe(base := "") -> Dictionary:
	var r := {"name": "My material", "base": base, "color": "808080", "tint": "ffffff",
		"size": MaterialLibrary.world_size(base) if base != "" and MaterialLibrary.has(base) else 2.0,
		"ramp_fit": false, "layers": [], "next": 1}
	if base != "" and MaterialLibrary.has(base):
		r["name"] = MaterialLibrary.display_name(base) + " (mine)"
	return r


static func new_layer(type: String) -> Dictionary:
	var l := {"type": type, "on": true, "opacity": 1.0, "blend": "mix", "color": "000000"}
	match type:
		"adjust": l.merge({"hue": 0.0, "sat": 1.0, "bright": 0.0, "contrast": 1.0})
		"fill": l["opacity"] = 0.5
		"stripe": l.merge({"dir": "vertical", "pos": 0.5, "width": 0.04, "angle": 0.0, "soft": 0.0})
		"rect", "ellipse": l.merge({"x": 0.5, "y": 0.5, "w": 0.3, "h": 0.3, "angle": 0.0, "soft": 0.0})
		"text": l.merge({"text": "MALLET", "x": 0.5, "y": 0.5, "size": 0.12, "angle": 0.0, "color": "ffffff"})
		"image": l.merge({"file": "", "x": 0.5, "y": 0.5, "w": 0.5, "h": 0.5, "angle": 0.0, "color": "ffffff"})
		"paint": l.merge({"file": "", "color": "ffffff"})
	return l


## A one-line description for the layer list.
static func layer_label(l: Dictionary) -> String:
	var t := String(TYPE_NAMES.get(l.get("type", ""), l.get("type", "")))
	match String(l.get("type", "")):
		"stripe": t += " (%s)" % l.get("dir", "vertical")
		"text": t += ": " + String(l.get("text", "")).left(18)
	if String(l.get("blend", "mix")) != "mix":
		t += ", " + String(l["blend"])
	return ("" if l.get("on", true) else "(hidden) ") + t


func _init(px := PREVIEW) -> void:
	size = Vector2i(px, px)
	transparent_bg = false
	disable_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS


## Layer files (paint, image) as images, from a saved material's folder.
func load_images(dir: String) -> void:
	for l in recipe.get("layers", []):
		var f := String(l.get("file", ""))
		if f != "" and not images.has(f) and FileAccess.file_exists(dir + f):
			var img := Image.load_from_file(dir + f)
			if img:
				img.convert(Image.FORMAT_RGBA8)
				images[f] = img


## A new file name for a layer's own image.
func new_file() -> String:
	var n := int(recipe.get("next", 1))
	recipe["next"] = n + 1
	return "layer_%d.png" % n


## Draw the recipe again (cheap: a handful of nodes).
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var px := float(size.x)
	var base := String(recipe.get("base", ""))
	var base_img: Image = MaterialLibrary.image(base, "color") if base != "" and MaterialLibrary.has(base) else null
	if base_img:
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(base_img)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.size = Vector2(px, px)
		tr.modulate = Color.html(String(recipe.get("tint", "ffffff")))
		add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Color.html(String(recipe.get("color", "808080")))
		cr.size = Vector2(px, px)
		add_child(cr)
	for l in recipe.get("layers", []):
		if l.get("on", true):
			_add_layer(l, px)


func _add_layer(l: Dictionary, px: float) -> void:
	var type := String(l.get("type", ""))
	var blend := String(l.get("blend", "mix"))
	var col := Color.html(String(l.get("color", "000000")))
	var opacity := float(l.get("opacity", 1.0))
	match type:
		"adjust":
			var bb := BackBufferCopy.new()
			bb.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			add_child(bb)
			var cr := ColorRect.new()
			cr.size = Vector2(px, px)
			var m := ShaderMaterial.new()
			m.shader = _shader("adjust", "mix")
			for k in ["hue", "sat", "bright", "contrast"]:
				m.set_shader_parameter(k, float(l.get(k, 0.0)))
			m.set_shader_parameter("opacity", opacity)
			cr.material = m
			add_child(cr)
		"fill", "stripe", "rect", "ellipse":
			var cr := ColorRect.new()
			cr.size = Vector2(px, px)
			var m := ShaderMaterial.new()
			m.shader = _shader("shape", blend)
			var horizontal := type == "stripe" and String(l.get("dir", "vertical")) == "horizontal"
			m.set_shader_parameter("shape", 2 if horizontal else SHAPES[type])
			m.set_shader_parameter("col", col)
			m.set_shader_parameter("opacity", opacity)
			m.set_shader_parameter("angle", deg_to_rad(float(l.get("angle", 0.0))))
			m.set_shader_parameter("soft", float(l.get("soft", 0.0)))
			if type == "stripe":
				var p := float(l.get("pos", 0.5))
				var w := float(l.get("width", 0.04)) * 0.5
				m.set_shader_parameter("center", Vector2(0.5, p) if horizontal else Vector2(p, 0.5))
				m.set_shader_parameter("extent", Vector2(w, w))
			else:
				m.set_shader_parameter("center", Vector2(float(l.get("x", 0.5)), float(l.get("y", 0.5))))
				m.set_shader_parameter("extent", Vector2(float(l.get("w", 0.3)), float(l.get("h", 0.3))) * 0.5)
			cr.material = m
			add_child(cr)
		"text":
			var lb := Label.new()
			lb.text = String(l.get("text", ""))
			lb.add_theme_font_size_override("font_size", maxi(int(float(l.get("size", 0.12)) * px), 4))
			lb.add_theme_color_override("font_color", Color.WHITE)
			lb.self_modulate = col
			lb.material = _tex_material(blend, opacity)
			add_child(lb)
			lb.size = lb.get_combined_minimum_size()
			lb.pivot_offset = lb.size * 0.5
			lb.position = Vector2(float(l.get("x", 0.5)), float(l.get("y", 0.5))) * px - lb.size * 0.5
			lb.rotation = deg_to_rad(float(l.get("angle", 0.0)))
		"image", "paint":
			var f := String(l.get("file", ""))
			if not images.has(f):
				return
			if not _textures.has(f):
				_textures[f] = ImageTexture.create_from_image(images[f])
			var tr := TextureRect.new()
			tr.texture = _textures[f]
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.self_modulate = col
			tr.material = _tex_material(blend, opacity)
			if type == "paint":
				tr.size = Vector2(px, px)
			else:
				tr.size = Vector2(float(l.get("w", 0.5)), float(l.get("h", 0.5))) * px
				tr.pivot_offset = tr.size * 0.5
				tr.position = Vector2(float(l.get("x", 0.5)), float(l.get("y", 0.5))) * px - tr.size * 0.5
				tr.rotation = deg_to_rad(float(l.get("angle", 0.0)))
			add_child(tr)


## After painting into images[file]: show it (no rebuild).
func image_changed(file: String) -> void:
	if _textures.has(file) and images.has(file):
		(_textures[file] as ImageTexture).update(images[file])
	else:
		_textures.erase(file)
		rebuild()


func _tex_material(blend: String, opacity: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("tex", blend)
	m.set_shader_parameter("opacity", opacity)
	return m


## The picture as it is now (wait a frame or two for it).
func capture() -> Image:
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img


static func _shader(kind: String, blend: String) -> Shader:
	var key := kind + "|" + blend
	if _shaders.has(key):
		return _shaders[key]
	var mode: String = {"mix": "blend_mix", "add": "blend_add", "multiply": "blend_mul", "subtract": "blend_sub"}.get(blend, "blend_mix")
	var code := ""
	match kind:
		"shape":
			code = """shader_type canvas_item;
render_mode %s;
uniform int shape = 0;
uniform vec4 col : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float opacity = 1.0;
uniform vec2 center = vec2(0.5);
uniform vec2 extent = vec2(0.1);
uniform float angle = 0.0;
uniform float soft = 0.0;
void fragment() {
	vec2 p = fract(UV - center + 0.5) - 0.5;   // (wraps at the edges: the texture still tiles)
	float c = cos(angle);
	float s = sin(angle);
	p = vec2(c * p.x + s * p.y, -s * p.x + c * p.y);
	float d = -1.0;
	if (shape == 1) { d = abs(p.x) - extent.x; }
	else if (shape == 2) { d = abs(p.y) - extent.y; }
	else if (shape == 3) { vec2 q = abs(p) - extent; d = max(q.x, q.y); }
	else if (shape == 4) { d = (length(p / max(extent, vec2(0.0001))) - 1.0) * min(extent.x, extent.y); }
	float a = soft > 0.0 ? 1.0 - smoothstep(-soft * 0.5, soft * 0.5, d) : step(d, 0.0);
	a *= col.a * opacity;
	%s
}
""" % [mode, "COLOR = vec4(mix(vec3(1.0), col.rgb, a), 1.0);" if blend == "multiply" else "COLOR = vec4(col.rgb, a);"]
		"tex":
			code = """shader_type canvas_item;
render_mode %s;
uniform float opacity = 1.0;
void fragment() {
	vec4 t = texture(TEXTURE, UV) * COLOR;
	%s
}
""" % [mode, "COLOR = vec4(mix(vec3(1.0), t.rgb, t.a * opacity), 1.0);" if blend == "multiply" else "COLOR = vec4(t.rgb, t.a * opacity);"]
		"adjust":
			code = """shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float hue = 0.0;
uniform float sat = 1.0;
uniform float bright = 0.0;
uniform float contrast = 1.0;
uniform float opacity = 1.0;
vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}
void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 h = rgb2hsv(c);
	h.x = fract(h.x + hue);
	h.y = clamp(h.y * sat, 0.0, 1.0);
	vec3 o = hsv2rgb(h);
	o = clamp((o - 0.5) * contrast + 0.5 + bright, 0.0, 1.0);
	COLOR = vec4(mix(c, o, opacity), 1.0);
}
"""
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh


# ------------------------------------------------------------------------------------------------------- painting
## Paint (or erase) one round brush dab at uv (0..1) into a paint layer's image. Wraps at the edges like the
## texture does.
static func dab(img: Image, uv: Vector2, radius_px: float, color: Color, hardness: float, erase := false) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var c := Vector2(uv.x * w, uv.y * h)
	var r := maxf(radius_px, 0.5)
	var soft := clampf(1.0 - hardness, 0.0, 1.0)
	for oy in range(int(floor(c.y - r)), int(ceil(c.y + r)) + 1):
		for ox in range(int(floor(c.x - r)), int(ceil(c.x + r)) + 1):
			var d := Vector2(ox + 0.5, oy + 0.5).distance_to(c) / r
			if d > 1.0:
				continue
			var a := 1.0 if soft <= 0.0 or d < 1.0 - soft else (1.0 - d) / soft
			a *= color.a
			var x := posmod(ox, w)
			var y := posmod(oy, h)
			var old := img.get_pixel(x, y)
			if erase:
				old.a = maxf(old.a - a, 0.0)
				img.set_pixel(x, y, old)
			else:
				var out_a := a + old.a * (1.0 - a)
				var rgb := (Color(color.r, color.g, color.b) * a + Color(old.r, old.g, old.b) * old.a * (1.0 - a)) / maxf(out_a, 0.0001)
				img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, out_a))


# --------------------------------------------------------------------------------------------------------- saving
## Save a material: `color` is the finished picture (SIZE x SIZE), `layer_images` the paint / image layers' images.
## `id` = one of your made materials to save over, or "" for a new one. Returns its id.
static func save(r: Dictionary, color: Image, layer_images: Dictionary, id := "") -> String:
	if not (id.begins_with("made_") and MaterialLibrary.has(id)):
		var slug := String(r.get("name", "material")).to_lower().validate_filename().replace(" ", "_").left(40)
		if slug == "":
			slug = "material"
		id = "made_" + slug
		var n := 2
		while MaterialLibrary.has(id):
			id = "made_%s_%d" % [slug, n]
			n += 1
	var dir := MaterialLibrary.USER_DIR + id + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for old in DirAccess.get_files_at(dir):                # (layers taken out since: their files go too)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + old))
	var img: Image = color.duplicate()
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(dir + "color.jpg", 0.92)
	var prev: Image = img.duplicate()
	prev.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	prev.save_jpg(dir + "preview.jpg", 0.88)
	var maps := {"color": "color.jpg"}
	var base := String(r.get("base", ""))
	var surface := "concrete"
	if base != "" and MaterialLibrary.has(base):
		surface = String(MaterialLibrary.entry(base).get("surface", "concrete"))
		for m in ["normal", "roughness", "metal", "glow"]:      # (the starting material's surface detail)
			var mi := MaterialLibrary.image(base, m)
			if mi:
				mi.save_jpg(dir + m + ".jpg", 0.92)
				maps[m] = m + ".jpg"
	var rec: Dictionary = r.duplicate(true)
	for l in rec.get("layers", []):
		var f := String(l.get("file", ""))
		if f != "" and layer_images.has(f):
			(layer_images[f] as Image).save_png(dir + f)
	MaterialLibrary.put_user_entry({"id": id, "name": String(r.get("name", id)), "category": CATEGORY,
		"size": float(r.get("size", 2.0)), "surface": surface, "maps": maps, "recipe": rec,
		"ramp_fit": bool(r.get("ramp_fit", false)), "stamp": Time.get_unix_time_from_system()})
	return id
