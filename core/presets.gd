class_name Presets
extends RefCounted
## Named presets the user saves for light settings and texture settings (0.19.3), kept in the user folder so they
## work in every map: user://presets.cfg, a section per kind ("light", "texture"), a key per name.

static var PATH := "user://presets.cfg"      ## (tests use a file of their own)


static func _cfg() -> ConfigFile:
	var c := ConfigFile.new()
	c.load(PATH)
	return c


## Every preset of this kind: {name: settings}, sorted by name.
static func all(kind: String) -> Dictionary:
	var c := _cfg()
	var out := {}
	if not c.has_section(kind):
		return out
	var names := Array(c.get_section_keys(kind))
	names.sort()
	for n in names:
		var v = c.get_value(kind, n, {})
		if v is Dictionary:
			out[n] = v
	return out


static func save(kind: String, name: String, settings: Dictionary) -> void:
	var c := _cfg()
	c.set_value(kind, name, settings.duplicate(true))
	c.save(PATH)


static func remove(kind: String, name: String) -> void:
	var c := _cfg()
	if c.has_section_key(kind, name):
		c.erase_section_key(kind, name)
		c.save(PATH)
