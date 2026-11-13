class_name MaterialLibrary
extends RefCounted
## The starter material library (res://materials, CC0 textures from ambientCG): real materials with color, surface
## detail (normal map), roughness and, for metals, metalness. Everything is built as embedded compressed textures so
## a SurfsUp export carries it inside the map; CS:S exports convert it to Valve's format (see VmfExporter).

const DIR := "res://materials/"
const USER_DIR := "user://materials/"     ## your own images, added from the picker
const MAX_SIZE := 1024
const GLOW_ENERGY := 1.6                  ## how bright a material's glow map shines
## A material's finish (0.23.0, set in the material maker): bright = how much light it gives back (x, no upper
## limit), glow = light of its own (its picture shining by itself, no upper limit), gloss = 0 as photographed to 1
## mirror-smooth, reflect = 0 not at all to 1 a perfect mirror (metal). Missing keys are these.
const FINISH_DEFAULTS := {"bright": 1.0, "glow": 0.0, "gloss": 0.0, "reflect": 0.0}

static var _entries: Array = []
static var _by_id := {}
static var _textures := {}
static var _materials := {}
static var _previews := {}


## Where the starter materials are: inside the project, or (in an exported MALLET, which can't pack this folder)
## the "materials" folder next to MALLET.exe.
static func starter_dir() -> String:
	if FileAccess.file_exists(DIR + "library.json"):
		return DIR
	return OS.get_executable_path().get_base_dir().path_join("materials") + "/"


static func entries() -> Array:
	if _entries.is_empty():
		for dir in [starter_dir(), USER_DIR]:
			var data = JSON.parse_string(FileAccess.get_file_as_string(dir + "library.json")) if FileAccess.file_exists(dir + "library.json") else null
			if data is Dictionary:
				for e in data.get("materials", []):
					e["dir"] = dir + e["id"] + "/"
					_entries.append(e)
					_by_id[e["id"]] = e
	return _entries


## Add your own image as a material (it lands in the "Your images" category). Returns its id, or "" if the image
## can't be read.
static func add_user_image(path: String) -> String:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return ""
	var base := path.get_file().get_basename().to_lower().validate_filename().replace(" ", "_")
	var id := "user_" + base
	var n := 2
	while has(id):
		id = "user_%s_%d" % [base, n]
		n += 1
	DirAccess.make_dir_recursive_absolute(USER_DIR + id)
	if maxi(img.get_width(), img.get_height()) > MAX_SIZE:
		var k := float(MAX_SIZE) / maxi(img.get_width(), img.get_height())
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(USER_DIR + id + "/color.jpg", 0.92)
	var prev: Image = img.duplicate()
	prev.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	prev.save_jpg(USER_DIR + id + "/preview.jpg", 0.88)
	var list := []
	if FileAccess.file_exists(USER_DIR + "library.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string(USER_DIR + "library.json"))
		if data is Dictionary:
			list = data.get("materials", [])
	list.append({"id": id, "name": path.get_file().get_basename(), "category": "Your images", "size": 2.0,
		"surface": "concrete", "maps": {"color": "color.jpg"}})
	var f := FileAccess.open(USER_DIR + "library.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"materials": list}, "  "))
	f.close()
	_entries.clear()                                    # reload with the new one
	_by_id.clear()
	return id


static func has(id: String) -> bool:
	if CssLibrary.is_css(id):
		return not CssLibrary.entry(id).is_empty()
	entries()
	return _by_id.has(id)


## A material's library entry (CS:S materials from the install come from CssLibrary, with ids "css:<path>").
static func entry(id: String) -> Dictionary:
	if CssLibrary.is_css(id):
		return CssLibrary.entry(id)
	entries()
	return _by_id.get(id, {})


## Pixels across the texture as exported to CS:S: the game's own size for CS:S materials, else the converted size.
static func texture_px(id: String) -> int:
	return int(entry(id).get("px", VmfExporter.VTF_SIZE)) if CssLibrary.is_css(id) else VmfExporter.VTF_SIZE


static func display_name(id: String) -> String:
	return entry(id).get("name", id) if id != "" else "None"


## Meters one repeat of the texture covers on a surface (at texture scale 1).
static func world_size(id: String) -> float:
	return float(entry(id).get("size", 2.0))


static func categories() -> Array:
	var out := []
	for e in entries():
		if not e["category"] in out:
			out.append(e["category"])
	return out


static func image(id: String, map: String) -> Image:
	if CssLibrary.is_css(id):
		return CssLibrary.image(id, map)
	var e := entry(id)
	if not e.get("maps", {}).has(map):
		return null
	var bytes := FileAccess.get_file_as_bytes(e["dir"] + e["maps"][map])
	var img := Image.new()
	if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
		return null
	return img


static func preview(id: String) -> Texture2D:
	if CssLibrary.is_css(id):
		return CssLibrary.preview(id)
	if _previews.has(id):
		return _previews[id]
	var bytes := FileAccess.get_file_as_bytes(entry(id).get("dir", starter_dir() + id + "/") + "preview.jpg")
	var img := Image.new()
	var tex: Texture2D = null
	if not bytes.is_empty() and img.load_jpg_from_buffer(bytes) == OK:
		tex = ImageTexture.create_from_image(img)
	_previews[id] = tex
	return tex


## One of a material's maps as an embedded, compressed texture.
static func texture(id: String, map: String) -> Texture2D:
	var key := id + "/" + map
	if _textures.has(key):
		return _textures[key]
	var img := image(id, map)
	var tex: Texture2D = null
	if img:
		if maxi(img.get_width(), img.get_height()) > MAX_SIZE:
			img.resize(MAX_SIZE, MAX_SIZE, Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		var c := PortableCompressedTexture2D.new()
		c.keep_compressed_buffer = true                    # so the image data is saved into exported maps
		c.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, map == "normal", 0.85)
		tex = c
	_textures[key] = tex
	return tex


## The material, tinted (white = as photographed). Shared, so a map stores each texture once.
static func material(id: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s" % [id, tint.to_html()]
	if _materials.has(key):
		return _materials[key]
	var fin := finish(id)
	var m := StandardMaterial3D.new()
	m.resource_name = id
	m.albedo_color = tint
	m.albedo_texture = texture(id, "color")
	var n := texture(id, "normal")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var r := texture(id, "roughness")
	m.roughness = 1.0
	if r:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var mt := texture(id, "metal")
	if mt:
		m.metallic = 1.0
		m.metallic_texture = mt
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var gl := texture(id, "glow")                        # lit parts (signs, lamps, screens) shine by themselves
	if gl:
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = gl
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # (ADD would light the whole face: color + map)
		m.emission_energy_multiplier = GLOW_ENERGY
	apply_finish(m, fin, mt != null, gl != null)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = m
	return m


## Put a finish on a material built from a library entry (`has_metal` / `has_glow`: it has those maps).
static func apply_finish(m: StandardMaterial3D, fin: Dictionary, has_metal: bool, has_glow: bool) -> void:
	var b := float(fin["bright"])
	m.albedo_color = Color(m.albedo_color.r * b, m.albedo_color.g * b, m.albedo_color.b * b, m.albedo_color.a)
	m.roughness = 1.0 - float(fin["gloss"])             # (it scales the roughness map: 0 = mirror-smooth)
	if float(fin["reflect"]) > 0.0:
		if not has_metal:                                # (with a metal map, that map still says which parts are metal)
			m.metallic = float(fin["reflect"])
		m.metallic_specular = 0.5 + 0.5 * float(fin["reflect"])
	if float(fin["glow"]) > 0.0 and not has_glow:       # (light of its own: the picture shines by itself)
		m.emission_enabled = true
		m.emission = Color.WHITE
		m.emission_texture = m.albedo_texture
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		m.emission_energy_multiplier = float(fin["glow"])
	elif float(fin["glow"]) > 0.0:
		m.emission_energy_multiplier = GLOW_ENERGY * (1.0 + float(fin["glow"]))


## A material's finish (FINISH_DEFAULTS filled in).
static func finish(id: String) -> Dictionary:
	var f := FINISH_DEFAULTS.duplicate()
	var e = entry(id).get("finish") if id != "" else null
	if e is Dictionary:
		for k in f:
			if (e as Dictionary).has(k):
				f[k] = maxf(float(e[k]), 0.0)
	f["gloss"] = minf(f["gloss"], 1.0)
	f["reflect"] = minf(f["reflect"], 1.0)
	return f


## The same finish on one of the surface shaders (cube faces, turned / scrolling ramp textures).
static func shader_finish(sm: ShaderMaterial, id: String) -> void:
	var f := finish(id)
	sm.set_shader_parameter("bright", f["bright"])
	sm.set_shader_parameter("self_glow", f["glow"])
	sm.set_shader_parameter("gloss", f["gloss"])
	sm.set_shader_parameter("reflect", f["reflect"])


## Remove one of your own materials again (an image you added, or one you made).
static func remove_user(id: String) -> void:
	if not is_own(id):
		return
	_write_user_list(_user_list().filter(func(e): return e["id"] != id))
	var dir := USER_DIR + id + "/"
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + id))
	forget(id)


## Yours: an image you added ("user_...") or a material you made in the material maker ("made_...").
static func is_own(id: String) -> bool:
	return id.begins_with("user_") or id.begins_with("made_")


## Made in the material maker (it has a recipe you can open again).
static func is_made(id: String) -> bool:
	return id.begins_with("made_") and entry(id).has("recipe")


## On a ramp, one repeat spans the whole riding surface across (left edge 0, ridge in the middle, right edge 1)
## instead of repeating every `size` meters, so a line drawn into the texture lands on the ridge.
static func ramp_fit(id: String) -> bool:
	return bool(entry(id).get("ramp_fit", false))


## Drop everything built from one material (after it was saved again), so it is read fresh.
static func forget(id: String) -> void:
	_entries.clear()
	_by_id.clear()
	_previews.erase(id)
	for cache in [_textures, _materials]:
		for k in cache.keys():
			if String(k).begins_with(id + "/") or String(k).begins_with(id + "|"):
				cache.erase(k)


static func _user_list() -> Array:
	if FileAccess.file_exists(USER_DIR + "library.json"):
		var data = JSON.parse_string(FileAccess.get_file_as_string(USER_DIR + "library.json"))
		if data is Dictionary and data.get("materials") is Array:
			return data["materials"]
	return []


static func _write_user_list(list: Array) -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var clean := []
	for e in list:
		var c: Dictionary = (e as Dictionary).duplicate(true)
		c.erase("dir")
		clean.append(c)
	var f := FileAccess.open(USER_DIR + "library.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"materials": clean}, "  "))
	f.close()


## Add or replace one entry of your own library (its files are already in USER_DIR/<id>/).
static func put_user_entry(e: Dictionary) -> void:
	var list := _user_list().filter(func(x): return x["id"] != e["id"])
	list.append(e)
	_write_user_list(list)
	forget(String(e["id"]))


## One of your materials with its files, to travel inside a map (or to a co-editor): {entry, files: {name: base64}}.
static func package(id: String) -> Dictionary:
	if not is_own(id) or not has(id):
		return {}
	var e: Dictionary = entry(id).duplicate(true)
	var dir := String(e["dir"])
	e.erase("dir")
	var files := {}
	for file in DirAccess.get_files_at(dir):
		files[file] = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(dir + file))
	return {"entry": e, "files": files}


## Put a packaged material into your library: when you don't have it, or theirs is newer (saved later). True if
## it was installed.
static func install(pkg: Dictionary) -> bool:
	var e = pkg.get("entry")
	var files = pkg.get("files")
	if not e is Dictionary or not files is Dictionary or not is_own(String(e.get("id", ""))):
		return false
	var id := String(e["id"])
	if id.validate_filename() != id:
		return false
	if has(id) and float(entry(id).get("stamp", 0.0)) >= float(e.get("stamp", 0.0)):
		return false
	var dir := USER_DIR + id + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for file in files:
		var name := String(file)
		if name.validate_filename() != name:
			continue
		var f := FileAccess.open(dir + name, FileAccess.WRITE)
		if f:
			f.store_buffer(Marshalls.base64_to_raw(String(files[file])))
			f.close()
	put_user_entry(e)
	return true


## Which of your own materials a map uses (by id, anywhere in its text).
static func own_used_in(map_text: String) -> Array:
	var out := []
	for e in entries():
		if is_own(String(e["id"])) and map_text.contains('"%s"' % e["id"]):
			out.append(String(e["id"]))
	return out
