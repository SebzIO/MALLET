class_name RampPrefabs
extends RefCounted
## Ramp prefabs: saved ramp designs from the ramp creator (cross-section, ends, style, angle, face length, body).
## A design has no path: applied to a ramp it keeps that ramp's points, so the ramp stays an ordinary ramp you can
## drag, stretch, bend and lock. The starter ones live in res://ramp_prefabs, yours in user://ramp_prefabs, each
## with a thumbnail (yours: next to the file; starters: rendered once into user://ramp_prefabs/.thumbs).
## Files are plain JSON (.malletramp), so they can be shared.

const BUILTIN_DIR := "res://ramp_prefabs/"
const EXT := "malletramp"
const FORMAT := "mallet-ramp"
## The ramp settings a design carries (everything about the shape, nothing about where it is or its look).
const DESIGN_KEYS := ["style", "solid", "base_depth", "angle", "face_length", "angle_right", "face_length_right",
	"freeform", "profile", "ends"]

static var user_dir := "user://ramp_prefabs/"          ## (tests point this at a folder of their own)


## A ramp's design (from a ramp dictionary or RampShape.spec), complete and with plain values.
static func design_of(d: Dictionary) -> Dictionary:
	var s := RampShape.spec(d)
	var out := {}
	for k in DESIGN_KEYS:
		out[k] = s[k].duplicate(true) if s[k] is Dictionary or s[k] is Array else s[k]
	if not RampShape.custom_profile(s) and s["profile"]["same"]:
		out["profile"] = {}                              # (a plain cross-section; "faces differ" is kept while editing)
	if not RampShape.custom_ends(s):
		out["ends"] = {}
	return out


## Every ramp prefab: [{"name", "description", "path", "builtin", "design"}], starters first.
static func list() -> Array:
	var out := []
	for dir in [BUILTIN_DIR, user_dir]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f in files:
			if String(f).get_extension() != EXT:
				continue
			var data := read(dir + f)
			if not data.is_empty():
				data["path"] = dir + f
				data["builtin"] = dir == BUILTIN_DIR
				out.append(data)
	return out


## {"name", "description", "design"} from a file ({} if it isn't a ramp prefab).
static func read(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("format", "") != FORMAT or not data.get("design") is Dictionary:
		return {}
	return {"name": String(data.get("name", path.get_file().get_basename())), "description": String(data.get("description", "")),
		"design": design_of(data["design"])}


static func _file_name(name: String) -> String:
	var f := name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	return f if f != "" else "ramp"


## Save a design as one of your prefabs (with its thumbnail). Returns the file.
static func save(name: String, design: Dictionary, description := "", thumb: Image = null) -> String:
	DirAccess.make_dir_recursive_absolute(user_dir)
	var path := user_dir + _file_name(name) + "." + EXT
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": FORMAT, "version": 1, "name": name.strip_edges(), "description": description,
		"made_with": MalletVersion.full(), "design": design_of(design)}, "  "))
	f.close()
	if thumb:
		thumb.save_png(path.get_basename() + ".png")
	return path


static func remove(path: String) -> void:
	if path.begins_with(user_dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.get_basename() + ".png"))


## Copy a ramp prefab file someone shared into your prefabs. Returns its new path ("" if it isn't one).
static func import_file(src: String) -> String:
	var data := read(src)
	if data.is_empty():
		return ""
	var name: String = data["name"]
	var base := _file_name(name)
	var path := user_dir + base + "." + EXT
	var k := 2
	while FileAccess.file_exists(path):
		path = user_dir + "%s_%d.%s" % [base, k, EXT]
		k += 1
	DirAccess.make_dir_recursive_absolute(user_dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src))
	f.close()
	return path


## Write a prefab out to a file of your choice (to share it).
static func export_file(path: String, dest: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null or text == "":
		return false
	f.store_string(text)
	f.close()
	return true


## Where a prefab's thumbnail lives (made by the ramp creator when it's missing).
static func thumb_path(path: String) -> String:
	if path.begins_with(user_dir):
		return path.get_basename() + ".png"
	return user_dir + ".thumbs/" + path.get_file().get_basename() + ".png"


static func thumbnail(path: String) -> Texture2D:
	var tp := thumb_path(path)
	if not FileAccess.file_exists(tp):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(tp))
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


## A few words about a design, for the panel ("Curved faces, tapered start, lip at the end").
static func describe(design: Dictionary) -> String:
	var s := RampShape.spec(design)
	var parts := []
	if RampShape.custom_profile(s):
		parts.append("custom cross-section" + (", %.1f m flat top" % s["profile"]["top"] if s["profile"]["top"] > 0.0 else ""))
	for which in ["start", "end"]:
		var e: Dictionary = s["ends"][which]
		var bits := []
		if e["shape"] != "square":
			bits.append({"taper": "tapered", "round": "rounded", "flare": "flared"}[e["shape"]])
		if e["cut"] != 0.0:
			bits.append("cut %d°" % int(e["cut"]))
		if e["lip"] != 0.0:
			bits.append("%.1f m lip" % e["lip"])
		if e["closed"]:
			bits.append("closed")
		if not bits.is_empty():
			parts.append("%s %s" % [", ".join(bits), which])
	return "; ".join(parts) if not parts.is_empty() else "plain ramp"
