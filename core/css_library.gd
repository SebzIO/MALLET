class_name CssLibrary
extends RefCounted
## Counter-Strike: Source's own world materials, read from the CS:S install on this computer (never shipped with
## MALLET): Valve's VPK archives -> VMT materials -> VTF textures. They show in the material picker as "CS:S · <folder>"
## with ids "css:<path>" (e.g. css:concrete/concretefloor005a). CS:S exports use them as they are (every CS:S player
## has them); SurfsUp exports copy them in only when the map maker turns that on (see SurfsUpExporter).

const ARCHIVES := ["cstrike/cstrike_pak_dir.vpk", "hl2/hl2_textures_dir.vpk", "hl2/hl2_misc_dir.vpk"]
const INDEX_PATH := "user://css_index.json"
const INDEX_VERSION := 1
const U := 39.37                        ## Source units per meter
## Folders that hold no world textures (models, effects, interface...).
const SKIP := ["models/", "sprites/", "effects/", "particle/", "particles/", "vgui/", "console/", "hud/", "debug/",
	"editor/", "tools/", "overlays/", "decals/", "skybox/", "cable/", "engine/", "shadertest/", "dev/dev_", "voice/",
	"perftest/", "detail/", "lights/", "water/", "liquids/", "nature/blendrock", "correction/", "cs_italy/flags",
	"vehicle/", "hlmv/", "maps/", "matsys_regressiontest/", "pl_hydro/", "test/", "vr/"]
const SHADERS := ["lightmappedgeneric", "worldvertextransition"]

static var _root := ""
static var _files := {}                  ## lower-case path -> [archive dir file, archive index, offset, length, preload]
static var _entries: Array = []
static var _by_id := {}
static var _loaded := false
static var _previews := {}
static var _images := {}


## The CS:S install's folder ("" when CS:S isn't installed).
static func root() -> String:
	if _root == "":
		_root = VmfExporter.find_css()
	return _root


static func available() -> bool:
	return root() != "" and FileAccess.file_exists(root().path_join(ARCHIVES[0]))


static func is_css(id: String) -> bool:
	return id.begins_with("css:")


## Every CS:S world material: [{"id", "name", "category", "size", "surface", "px", "maps", "basetexture", "css"}].
## Built once (a few seconds) and kept in user://css_index.json until the game updates its archives.
static func entries() -> Array:
	if _loaded:
		return _entries
	_loaded = true
	if not available():
		return _entries
	var sig := _signature()
	if FileAccess.file_exists(INDEX_PATH):
		var data = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if data is Dictionary and data.get("version", 0) == INDEX_VERSION and data.get("signature", "") == sig:
			_set_entries(data["materials"])
			return _entries
	_set_entries(_build_index())
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": INDEX_VERSION, "signature": sig, "materials": _entries}))
		f.close()
	return _entries


static func _set_entries(list: Array) -> void:
	_entries = list
	_by_id.clear()
	for e in _entries:
		e["dir"] = ""
		_by_id[e["id"]] = e


static func entry(id: String) -> Dictionary:
	entries()
	return _by_id.get(id, {})


static func _signature() -> String:
	var s := ""
	for a in ARCHIVES:
		var p := root().path_join(a)
		if FileAccess.file_exists(p):
			s += "%s:%d;" % [a, FileAccess.get_modified_time(p)]
	return s


# ------------------------------------------------------------------------------------------------ VPK archives
static func _mount() -> void:
	if not _files.is_empty() or not available():
		return
	for a in ARCHIVES:
		var p := root().path_join(a)
		if FileAccess.file_exists(p):
			_read_vpk_dir(p)


## A VPK directory file (v1 or v2): extension -> path -> name trees of entries.
static func _read_vpk_dir(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != 0x55AA1234:
		return
	var version := f.get_32()
	var tree_size := f.get_32()
	var header := 12
	if version == 2:
		f.get_32()
		f.get_32()
		f.get_32()
		f.get_32()
		header = 28
	var data_start := header + tree_size
	while true:
		var ext := _cstr(f)
		if ext == "":
			break
		while true:
			var dir := _cstr(f)
			if dir == "":
				break
			while true:
				var name := _cstr(f)
				if name == "":
					break
				f.get_32()                                   # CRC
				var preload_n := f.get_16()
				var archive := f.get_16()
				var offset := f.get_32()
				var length := f.get_32()
				f.get_16()                                   # terminator 0xFFFF
				var pre := f.get_buffer(preload_n) if preload_n > 0 else PackedByteArray()
				var full := ((dir + "/") if dir != " " else "") + name + "." + ext
				if archive == 0x7FFF:
					offset += data_start
				_files[full.to_lower()] = [path, archive, offset, length, pre]


static func _cstr(f: FileAccess) -> String:
	var b := PackedByteArray()
	while true:
		var c := f.get_8()
		if c == 0 or f.eof_reached():
			break
		b.append(c)
	return b.get_string_from_utf8()


static func has_file(path: String) -> bool:
	_mount()
	return _files.has(path.to_lower())


## A file from the archives ([] when it isn't there). `max_bytes` > 0 reads only that much (headers).
static func read(path: String, max_bytes := 0) -> PackedByteArray:
	_mount()
	var e = _files.get(path.to_lower())
	if e == null:
		return PackedByteArray()
	var out: PackedByteArray = (e[4] as PackedByteArray).duplicate()
	var length: int = e[3]
	if length > 0 and (max_bytes <= 0 or out.size() < max_bytes):
		var file: String = e[0]
		if e[1] != 0x7FFF:
			file = (e[0] as String).replace("_dir.vpk", "_%03d.vpk" % e[1])
		var f := FileAccess.open(file, FileAccess.READ)
		if f:
			f.seek(e[2])
			out.append_array(f.get_buffer(length if max_bytes <= 0 else mini(length, max_bytes - out.size())))
	return out


# ------------------------------------------------------------------------------------------------ VMT materials
## A VMT as {"shader": lower-case name, "$key": value, ...} (patch materials follow their include).
static func parse_vmt(text: String, depth := 0) -> Dictionary:
	var out := {}
	var toks := _tokens(text)
	if toks.is_empty():
		return out
	out["shader"] = (toks[0] as String).to_lower()
	var i := 1
	var level := 0
	while i < toks.size():
		var t: String = toks[i]
		if t == "{":
			level += 1
		elif t == "}":
			level -= 1
		elif i + 1 < toks.size() and toks[i + 1] != "{" and toks[i + 1] != "}":
			var key := t.to_lower()
			if level >= 1 and not out.has(key):
				out[key] = toks[i + 1]
			i += 1
		i += 1
	if out["shader"] == "patch" and out.has("include") and depth < 4:
		var base := parse_vmt(read(String(out["include"])).get_string_from_utf8(), depth + 1)
		for k in out:
			if k != "shader" and k != "include":
				base[k] = out[k]
		return base
	return out


static func _tokens(text: String) -> Array:
	var out := []
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if c == "/" and i + 1 < n and text[i + 1] == "/":
			while i < n and text[i] != "\n":
				i += 1
		elif c == "\"":
			var j := text.find("\"", i + 1)
			if j < 0:
				j = n
			out.append(text.substr(i + 1, j - i - 1))
			i = j + 1
			continue
		elif c == "{" or c == "}":
			out.append(c)
		elif c.strip_edges() != "":
			var j := i
			while j < n and text[j].strip_edges() != "" and not text[j] in ["{", "}", "\""]:
				j += 1
			out.append(text.substr(i, j - i))
			i = j
			continue
		i += 1
	return out


static func _build_index() -> Array:
	_mount()
	var list := []
	var seen := {}
	var keys := _files.keys()
	keys.sort()
	for path in keys:
		if not (path as String).begins_with("materials/") or not (path as String).ends_with(".vmt"):
			continue
		var rel: String = (path as String).substr(10, (path as String).length() - 14)
		if SKIP.any(func(s): return rel.begins_with(s)) or seen.has(rel):
			continue
		var vmt := parse_vmt(read(path).get_string_from_utf8())
		if not vmt.get("shader", "") in SHADERS:
			continue
		if vmt.has("$translucent") and vmt["$translucent"] != "0" or vmt.has("$alphatest") and vmt["$alphatest"] != "0":
			continue
		var bt := String(vmt.get("$basetexture", "")).to_lower().replace("\\", "/").trim_suffix(".vtf")
		if bt == "" or not has_file("materials/" + bt + ".vtf"):
			continue
		var head := read("materials/" + bt + ".vtf", 80)
		if head.size() < 64 or head.decode_u32(0) != 0x00465456:
			continue
		var w := head.decode_u16(16)
		seen[rel] = true
		var maps := {"color": bt}
		var bump := String(vmt.get("$bumpmap", "")).to_lower().replace("\\", "/").trim_suffix(".vtf")
		if bump != "" and vmt.get("$ssbump", "0") == "0" and has_file("materials/" + bump + ".vtf"):
			maps["normal"] = bump
		var folder := rel.get_slice("/", 0) if rel.contains("/") else "misc"
		list.append({"id": "css:" + rel, "name": rel.get_file(), "category": "CS:S · " + folder, "css": true,
			"size": snappedf(w * 0.25 / U, 0.001), "px": w, "surface": String(vmt.get("$surfaceprop", "concrete")).to_lower(),
			"maps": maps, "basetexture": bt})
	return list


# ------------------------------------------------------------------------------------------------ VTF textures
## The texture's largest mipmap no wider than `max_w`, as an RGB(A)8 image (null if it can't be read).
static func vtf_image(path: String, max_w := 1024) -> Image:
	var b := read(path)
	if b.size() < 64 or b.decode_u32(0) != 0x00465456:
		return null
	var minor := b.decode_u32(8)
	var header := b.decode_u32(12)
	var w := b.decode_u16(16)
	var h := b.decode_u16(18)
	var flags := b.decode_u32(20)
	var frames := maxi(b.decode_u16(24), 1)
	var fmt := b.decode_s32(52)
	var mips := b[56]
	var low_fmt := b.decode_s32(57)
	var low_w := b[61]
	var low_h := b[62]
	var depth := b.decode_u16(63) if minor >= 2 else 1
	var faces := 6 if flags & 0x4000 else 1
	var start := header + _size(low_fmt, low_w, low_h) if low_fmt >= 0 else header
	if minor >= 3:
		var n := b.decode_u32(68)
		for r in n:
			var at := 80 + r * 8
			if b[at] == 0x30 and b[at + 1] == 0 and b[at + 2] == 0:
				start = b.decode_u32(at + 4)
	var level := 0                                       # largest mip no wider than max_w (and at least 4 px for DXT)
	while level < mips - 1 and (w >> level) > max_w:
		level += 1
	var at := start
	for l in range(mips - 1, level, -1):                 # stored smallest first
		at += _size(fmt, maxi(w >> l, 1), maxi(h >> l, 1)) * frames * faces * maxi(depth >> l, 1)
	var mw := maxi(w >> level, 1)
	var mh := maxi(h >> level, 1)
	var data := b.slice(at, at + _size(fmt, mw, mh))
	return _decode(fmt, mw, mh, data)


static func _size(fmt: int, w: int, h: int) -> int:
	match fmt:
		13, 20: return maxi((w + 3) / 4, 1) * maxi((h + 3) / 4, 1) * 8
		14, 15: return maxi((w + 3) / 4, 1) * maxi((h + 3) / 4, 1) * 16
		0, 1, 11, 12, 16: return w * h * 4
		2, 3: return w * h * 3
		4, 6, 17, 22: return w * h * 2
		5, 8: return w * h
	return w * h * 4


static func _decode(fmt: int, w: int, h: int, data: PackedByteArray) -> Image:
	var img: Image = null
	match fmt:
		13, 20, 14, 15:                                  # DXT1 / DXT3 / DXT5: Godot decompresses them
			var pw := maxi((w + 3) / 4 * 4, 4)
			var ph := maxi((h + 3) / 4 * 4, 4)
			var gf := Image.FORMAT_DXT1 if fmt in [13, 20] else (Image.FORMAT_DXT3 if fmt == 14 else Image.FORMAT_DXT5)
			img = Image.create_from_data(pw, ph, false, gf, data)
			img.decompress()
			if pw != w or ph != h:
				img.crop(w, h)
		0:                                               # RGBA8888
			img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		2:                                               # RGB888
			img = Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
		3, 12, 16, 1, 11:                                # BGR888, BGRA8888, BGRX8888, ABGR8888, ARGB8888
			var bpp := 3 if fmt == 3 else 4
			var out := PackedByteArray()
			out.resize(w * h * bpp)
			for i in w * h:
				var p := i * bpp
				match fmt:
					3, 12, 16:
						out[p] = data[p + 2]; out[p + 1] = data[p + 1]; out[p + 2] = data[p]
						if bpp == 4: out[p + 3] = 255 if fmt == 16 else data[p + 3]
					1:
						out[p] = data[p + 3]; out[p + 1] = data[p + 2]; out[p + 2] = data[p + 1]; out[p + 3] = data[p]
					11:
						out[p] = data[p + 1]; out[p + 1] = data[p + 2]; out[p + 2] = data[p + 3]; out[p + 3] = data[p]
			img = Image.create_from_data(w, h, false, Image.FORMAT_RGB8 if bpp == 3 else Image.FORMAT_RGBA8, out)
		5:                                               # I8
			img = Image.create_from_data(w, h, false, Image.FORMAT_L8, data)
	if img:
		img.convert(Image.FORMAT_RGB8)
	return img


# ------------------------------------------------------------------------------------------------ for the library
## One of a CS:S material's maps ("color" / "normal") as an RGB image, at most 1024 px.
static func image(id: String, map: String) -> Image:
	var key := id + "/" + map
	if _images.has(key):
		return (_images[key] as Image).duplicate()
	var e := entry(id)
	var path = (e.get("maps", {}) as Dictionary).get(map)
	if path == null:
		return null
	var img := vtf_image("materials/" + String(path) + ".vtf", 1024)
	if img and map == "normal":                          # Source's normal maps point green down: Godot's point up
		var d := img.get_data()
		for i in range(1, d.size(), 3):
			d[i] = 255 - d[i]
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, d)
	if img:
		_images[key] = img
		return img.duplicate()
	return null


static func preview(id: String) -> Texture2D:
	if _previews.has(id):
		return _previews[id]
	var e := entry(id)
	var tex: Texture2D = null
	if not e.is_empty():
		var img := vtf_image("materials/" + String(e["maps"]["color"]) + ".vtf", 128)
		if img:
			if img.get_width() != 128:
				img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
			tex = ImageTexture.create_from_image(img)
	_previews[id] = tex
	return tex
