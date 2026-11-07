class_name MaterialLibrary
extends RefCounted
## The starter material library (res://materials, CC0 textures from ambientCG): real materials with colour, surface
## detail (normal map), roughness and, for metals, metalness. Everything is built as embedded compressed textures so
## a SurfsUp export carries it inside the map; CS:S exports convert it to Valve's format (see VmfExporter).

const DIR := "res://materials/"
const USER_DIR := "user://materials/"     ## your own images, added from the picker
const MAX_SIZE := 1024
const GLOW_ENERGY := 1.6                  ## how bright a material's glow map shines

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


## Metres one repeat of the texture covers on a surface (at texture scale 1).
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
		m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # (ADD would light the whole face: colour + map)
		m.emission_energy_multiplier = GLOW_ENERGY
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = m
	return m


## Remove one of your own image materials again.
static func remove_user(id: String) -> void:
	if not id.begins_with("user_") or not FileAccess.file_exists(USER_DIR + "library.json"):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(USER_DIR + "library.json"))
	if not data is Dictionary:
		return
	var list: Array = data.get("materials", []).filter(func(e): return e["id"] != id)
	var f := FileAccess.open(USER_DIR + "library.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"materials": list}, "  "))
	f.close()
	for file in ["color.jpg", "preview.jpg"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + id + "/" + file))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_DIR + id))
	_entries.clear()
	_by_id.clear()
	_previews.erase(id)
