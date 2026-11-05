class_name Prefabs
extends RefCounted
## Prefabs: saved groups of objects to drop into any map. Same format as the clipboard (so anything you can copy
## you can save), plus a name and a description. The starter ones live in res://prefabs, yours in user://prefabs.

const BUILTIN_DIR := "res://prefabs/"
const USER_DIR := "user://prefabs/"
const EXT := "sfprefab"


## Every prefab: [{"name", "description", "path", "builtin"}], the starter ones first.
static func list() -> Array:
	var out := []
	for dir in [BUILTIN_DIR, USER_DIR]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files := DirAccess.get_files_at(dir)
		files.sort()
		for f in files:
			if f.get_extension() != EXT:
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
			if data is Dictionary:
				out.append({"name": data.get("name", f.get_basename()), "description": data.get("description", ""),
					"path": dir + f, "builtin": dir == BUILTIN_DIR})
	return out


static func read(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Save a clipboard-style selection as one of your prefabs. Returns the file it went to.
static func save(name: String, clip: Dictionary, description := "", dir := USER_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var file := name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	if file == "":
		file = "prefab"
	var path := dir + file + "." + EXT
	var d := clip.duplicate(true)
	d["name"] = name.strip_edges()
	d["description"] = description
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	return path


static func remove(path: String) -> void:
	if path.begins_with(USER_DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
