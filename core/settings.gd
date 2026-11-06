class_name Settings
extends RefCounted
## Your own SurfForge settings (not part of any map), kept in user://preferences.cfg so they survive restarts:
## mouse sensitivity for the editor's 3D view, build mode and play mode, and inverted mouse up / down. (Its own file:
## settings.cfg is the editor's export folders, and two writers of one file would wipe out each other's entries.)

const PATH := "user://preferences.cfg"
const DEFAULTS := {
	"editor_mouse": 1.0,                 ## editor 3D view (orbit / fly): x the normal speed
	"build_mouse": 1.0,                  ## build mode's first-person look: x the normal speed
	"play_mouse": 3.0,                   ## play mode: Source-style sensitivity (0.022 deg per count, like SurfsUp / CS:S)
	"invert_y": false,                   ## mouse forward looks down (everywhere)
}

static var _cfg: ConfigFile = null


static func _load() -> void:
	if _cfg != null:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)                      # (missing file = defaults)


static func value(key: String):
	_load()
	return _cfg.get_value("settings", key, DEFAULTS[key])


static func set_value(key: String, v) -> void:
	_load()
	_cfg.set_value("settings", key, v)
	_cfg.save(PATH)


static func editor_mouse() -> float:
	return float(value("editor_mouse"))


static func build_mouse() -> float:
	return float(value("build_mouse"))


static func play_mouse() -> float:
	return float(value("play_mouse"))


static func invert_y() -> bool:
	return bool(value("invert_y"))


## Up / down mouse motion with the invert setting applied (+1 or -1).
static func y_sign() -> float:
	return -1.0 if invert_y() else 1.0
