class_name UserShaders
extends RefCounted
## Your own shaders: Godot .gdshader files dropped into the shaders folder (user://shaders, opened from the menu).
## A "shader_type sky;" file becomes a choice for the map's sky, a "shader_type spatial;" file a ramp / block look.
## Every uniform becomes a control in the panel (sliders, color pickers, checkboxes, image choosers), so a shader
## writer also makes something anyone can tweak. A shader that doesn't compile is never used: its error is shown and
## MALLET falls back to the built-in sky / a plain color (no white faces, no crash).
##
## Maps carry the code of the shaders they use ("shaders" in the .mallet file), so a map still looks right on another
## computer, and the SurfsUp export embeds them like the built-in looks (no scripts).

static var dir := "user://shaders/"          ## (tests point this at a folder of their own)
const TEMPLATES := "res://core/shaders/templates/"
const EXAMPLES := ["example_sky.gdshader", "example_surface.gdshader"]

## id -> {"id", "kind" ("sky" / "surface" / "other"), "code", "path" ("" = from a map file), "mtime", "error",
## "line", "shader" (null when it doesn't compile), "uniforms" (see _read_uniforms), "version"}
static var _lib := {}
static var _version := 0
static var _logger: _ErrorCatcher


## Collects shader compile errors while a shader is being compiled (Godot reports them to its loggers).
class _ErrorCatcher extends Logger:
	var on := false
	var got: Array = []
	var _lock := Mutex.new()

	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		if on:
			got.append({"shader": error_type == ERROR_TYPE_SHADER, "line": line, "text": code if error_type == ERROR_TYPE_SHADER else rationale})
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## The folder on disk (made on first use, with the commented example shaders copied in).
static func folder() -> String:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		for f in EXAMPLES:
			var code := FileAccess.get_file_as_string(TEMPLATES + f)
			if code != "":
				var out := FileAccess.open(dir + f, FileAccess.WRITE)
				if out:
					out.store_string(code)
					out.close()
	return ProjectSettings.globalize_path(dir)


## Look for new, changed and removed files in the folder. Returns the ids that changed (empty: nothing new).
static func scan() -> Array:
	folder()
	var changed := []
	var seen := {}
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.get_extension().to_lower() != "gdshader":
				continue
			var id := f.get_basename()
			var path := dir + f
			var mtime := FileAccess.get_modified_time(path)
			seen[id] = true
			var e: Dictionary = _lib.get(id, {})
			var code := FileAccess.get_file_as_string(path)   # (always read: a save within the same second keeps the mtime)
			if not e.is_empty() and e["code"] == code and e["path"] == path:
				e["mtime"] = mtime
				continue
			_lib[id] = _compile(id, code, path, mtime)
			changed.append(id)
	for id in _lib.keys():
		if _lib[id]["path"] != "" and not seen.has(id):
			_lib.erase(id)                               # removed from the folder (the open map puts back the ones it uses)
			changed.append(id)
	return changed


## Shaders that came inside a map file: used when your folder doesn't have one by that name.
static func add_embedded(shaders: Dictionary) -> void:
	for id in shaders:
		var code := String(shaders[id])
		var e: Dictionary = _lib.get(id, {})
		if e.is_empty() or (e["path"] == "" and e["code"] != code):
			_lib[id] = _compile(id, code, "", 0)


## Compile one shader and read its controls. Errors are caught, not crashed on.
static func _compile(id: String, code: String, path: String, mtime: int) -> Dictionary:
	if _logger == null:
		_logger = _ErrorCatcher.new()
		OS.add_logger(_logger)
	_version += 1
	var e := {"id": id, "code": code, "path": path, "mtime": mtime, "error": "", "line": 0, "shader": null,
		"uniforms": [], "kind": "other", "version": _version, "animated": false}
	var m := RegEx.create_from_string("(?m)^\\s*shader_type\\s+(\\w+)\\s*;").search(_strip_comments(code))
	var type := m.get_string(1) if m else ""
	match type:
		"sky": e["kind"] = "sky"
		"spatial": e["kind"] = "surface"
		"":
			e["error"] = "The file doesn't start with a shader type. Put  shader_type sky;  (for a sky) or  shader_type spatial;  (for a ramp / block surface) at the top."
			return e
		_:
			e["error"] = "\"shader_type %s\" isn't used by MALLET. Use  shader_type sky;  for a sky or  shader_type spatial;  for a surface." % type
			return e
	var s := Shader.new()
	_logger.got.clear()
	_logger.on = true
	s.code = code
	var uniforms := s.get_shader_uniform_list()
	_logger.on = false
	var errs: Array = _logger.got.duplicate()
	_logger.got.clear()
	for er in errs:
		if er["shader"]:
			e["error"] = "Line %d: %s" % [er["line"], er["text"]]
			e["line"] = er["line"]
			break
	if e["error"] == "" and not errs.is_empty():
		e["error"] = "The shader doesn't compile: " + String(errs[0]["text"])
	if e["error"] != "":
		return e
	e["shader"] = s
	e["uniforms"] = _read_uniforms(s, uniforms, code)
	e["skipped"] = skipped_uniforms(s, uniforms)
	e["animated"] = RegEx.create_from_string("\\bTIME\\b").search(_strip_comments(code)) != null
	return e


## Comments out (so "// shader_type spatial;" in an explanation isn't read as code).
static func _strip_comments(code: String) -> String:
	return RegEx.create_from_string("(?s)/\\*.*?\\*/|//[^\\n]*").sub(code, "", true)


## The shader's controls, in the order they're written: {"name", "label", "type" (float / int / bool / color /
## vec2 / vec3 / vec4 / image), "min", "max", "step", "default", "alpha" (colors), "tip" (the uniform's // comment)}.
## Uniforms whose name starts with "_" are left out (for values the shader writer doesn't want tweaked).
static func _read_uniforms(s: Shader, list: Array, code: String) -> Array:
	var tips := {}
	for m in RegEx.create_from_string("(?m)^\\s*uniform\\s+[^;]*?\\b(\\w+)\\s*(?::[^;=]*)?(?:=[^;]*)?;[ \\t]*//[ \\t]*(.+)$").search_all(code):
		tips[m.get_string(1)] = m.get_string(2).strip_edges()
	var out := []
	for u in list:
		var name := String(u["name"])
		if name.begins_with("_") or name.contains("/"):
			continue
		var def = RenderingServer.shader_get_parameter_default(s.get_rid(), name)
		var label := name.capitalize()                    # ("cloud_amount" -> "Cloud amount", like MALLET's own labels)
		var c := {"name": name, "label": label.substr(0, 1) + label.substr(1).to_lower(), "tip": tips.get(name, ""), "default": def,
			"min": 0.0, "max": 1.0, "step": 0.01, "alpha": false}
		var hint := int(u["hint"])
		match int(u["type"]):
			TYPE_FLOAT, TYPE_INT:
				c["type"] = "int" if int(u["type"]) == TYPE_INT else "float"
				var dv := float(def) if def != null else 0.0
				c["default"] = dv
				if hint == PROPERTY_HINT_RANGE:
					var parts := String(u["hint_string"]).split(",")
					c["min"] = float(parts[0])
					c["max"] = float(parts[1]) if parts.size() > 1 else float(parts[0]) + 1.0
					c["step"] = float(parts[2]) if parts.size() > 2 else (1.0 if c["type"] == "int" else 0.01)
				else:                                    # no hint_range: a sensible range around the default
					var top := maxf(absf(dv) * 4.0, 1.0)
					c["min"] = -top if dv < 0.0 else 0.0
					c["max"] = top
					c["step"] = 1.0 if c["type"] == "int" else 0.01
				c["free"] = hint != PROPERTY_HINT_RANGE  # (the number box may go past the slider's ends)
			TYPE_BOOL:
				c["type"] = "bool"
				c["default"] = bool(def) if def != null else false
			TYPE_COLOR:
				c["type"] = "color"
				c["alpha"] = hint != PROPERTY_HINT_COLOR_NO_ALPHA
				c["default"] = def if def is Color else Color.WHITE
			TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
				c["type"] = {TYPE_VECTOR2: "vec2", TYPE_VECTOR3: "vec3", TYPE_VECTOR4: "vec4"}[int(u["type"])]
				if def == null:
					def = {TYPE_VECTOR2: Vector2.ZERO, TYPE_VECTOR3: Vector3.ZERO, TYPE_VECTOR4: Vector4.ZERO}[int(u["type"])]
				c["default"] = def
			TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:      # (ivec2 / ivec3 / ivec4: whole numbers)
				c["type"] = {TYPE_VECTOR2I: "ivec2", TYPE_VECTOR3I: "ivec3", TYPE_VECTOR4I: "ivec4"}[int(u["type"])]
				if def == null:
					def = {TYPE_VECTOR2I: Vector2i.ZERO, TYPE_VECTOR3I: Vector3i.ZERO, TYPE_VECTOR4I: Vector4i.ZERO}[int(u["type"])]
				c["default"] = def
			TYPE_OBJECT:
				if String(u["hint_string"]) != "Texture2D":
					continue                             # (cubemaps, 3D textures: not offered)
				c["type"] = "image"
				c["default"] = ""
			_:
				continue                                 # (matrices, arrays: not offered)
		out.append(c)
	return out


static func has(id: String) -> bool:
	return _lib.has(id)


static func entry(id: String) -> Dictionary:
	return _lib.get(id, {})


## Working shaders' ids of one kind ("sky" / "surface"), sorted by name; broken ones too with `with_broken`.
static func ids(kind: String, with_broken := false) -> Array:
	var out := []
	for id in _lib:
		var e: Dictionary = _lib[id]
		if e["kind"] == kind and (with_broken or e["shader"] != null):
			out.append(id)
	out.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(b) < 0)
	return out


## Files in the folder that don't compile (or aren't a sky / spatial shader): [[id, error], ...].
static func broken() -> Array:
	var out := []
	for id in _lib:
		if _lib[id]["shader"] == null:
			out.append([id, _lib[id]["error"]])
	return out


## Why a shader can't be used ("" = it works). Unknown ids say so.
static func problem(id: String) -> String:
	if not _lib.has(id):
		return "\"%s\" isn't in your shaders folder (and this map doesn't carry a copy)." % id
	return _lib[id]["error"]


static func ok(id: String) -> bool:
	return _lib.has(id) and _lib[id]["shader"] != null


## A number that changes whenever any shader is recompiled (for material caches).
static func version(id: String) -> int:
	return int(_lib.get(id, {}).get("version", 0))


## The shader's code for saving into a map (only shaders that are known).
static func code(id: String) -> String:
	return String(_lib.get(id, {}).get("code", ""))


## A material for a working shader with the map's settings applied (null if the shader can't be used).
static func material(id: String, params: Dictionary) -> ShaderMaterial:
	if not ok(id):
		return null
	var m := ShaderMaterial.new()
	m.shader = _lib[id]["shader"]
	for u in _lib[id]["uniforms"]:
		if params.has(u["name"]):
			var v = decode(u, params[u["name"]])
			if v != null:
				m.set_shader_parameter(u["name"], v)
	return m


## Uniforms a shader has that get no control, each with why: [{"name", "why"}]. Shown under the controls, so
## nothing disappears without a word. (Names starting with "_" are the writer's own choice and aren't listed.)
static func skipped_uniforms(s: Shader, list: Array) -> Array:
	var out := []
	for u in list:
		var name := String(u["name"])
		if name.begins_with("_") or name.contains("/"):
			continue
		var why := ""
		match int(u["type"]):
			TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
				continue
			TYPE_OBJECT:
				if String(u["hint_string"]) == "Texture2D":
					continue
				var kinds := {"TextureLayered": "cubemap or texture array", "Cubemap": "cubemap", "Texture2DArray": "texture array",
					"Texture3D": "3D texture"}
				why = "a %s: only 2D images (sampler2D) can be chosen" % kinds.get(String(u["hint_string"]), "texture of another kind")
			TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_PROJECTION:
				why = "a matrix: no control for those"
			TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, \
					TYPE_PACKED_COLOR_ARRAY, TYPE_ARRAY:
				why = "an array: no control for those"
			_:
				why = "a kind of value MALLET has no control for"
		out.append({"name": name, "why": why})
	return out


## A control's value as it's stored in the map (JSON-friendly).
static func encode(u: Dictionary, v):
	match u["type"]:
		"color": return (v as Color).to_html(u["alpha"])
		"vec2": return [v.x, v.y]
		"vec3": return [v.x, v.y, v.z]
		"vec4": return [v.x, v.y, v.z, v.w]
		"ivec2": return [int(v.x), int(v.y)]
		"ivec3": return [int(v.x), int(v.y), int(v.z)]
		"ivec4": return [int(v.x), int(v.y), int(v.z), int(v.w)]
		"int": return int(v)
		"float": return float(v)
		"bool": return bool(v)
	return v


## A stored value back as the shader's type (null when it can't be used: the shader's own default stays).
static func decode(u: Dictionary, v):
	match u["type"]:
		"color": return Color.html(String(v)) if v is String and Color.html_is_valid(v) else null
		"vec2": return Vector2(v[0], v[1]) if v is Array and v.size() >= 2 else null
		"vec3": return Vector3(v[0], v[1], v[2]) if v is Array and v.size() >= 3 else null
		"vec4": return Vector4(v[0], v[1], v[2], v[3]) if v is Array and v.size() >= 4 else null
		"ivec2": return Vector2i(int(v[0]), int(v[1])) if v is Array and v.size() >= 2 else null
		"ivec3": return Vector3i(int(v[0]), int(v[1]), int(v[2])) if v is Array and v.size() >= 3 else null
		"ivec4": return Vector4i(int(v[0]), int(v[1]), int(v[2]), int(v[3])) if v is Array and v.size() >= 4 else null
		"int": return int(v)
		"float": return float(v)
		"bool": return bool(v)
		"image": return Look.image_texture(String(v)) if String(v) != "" else null
	return null


## The value a control shows: the map's setting, or the shader's default.
static func value_of(u: Dictionary, params: Dictionary):
	if params.has(u["name"]):
		var v = decode(u, params[u["name"]]) if u["type"] != "image" else String(params[u["name"]])
		if v != null:
			return v
	return u["default"]


## What a surface shader looks like in CS:S (which can't run shaders): its first image, else its first color.
## Returns {"image": path} / {"color": Color} / {} (nothing to go by).
static func css_base(id: String, params: Dictionary) -> Dictionary:
	if not ok(id):
		return {}
	var color = null
	for u in _lib[id]["uniforms"]:
		if u["type"] == "image" and String(params.get(u["name"], "")) != "" and FileAccess.file_exists(String(params[u["name"]])):
			return {"image": String(params[u["name"]])}
		if u["type"] == "color" and color == null:
			color = value_of(u, params)
	return {"color": color} if color != null else {}
