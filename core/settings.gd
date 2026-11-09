class_name Settings
extends RefCounted
## Your own MALLET settings (not part of any map), kept in user://preferences.cfg so they survive restarts:
## mouse sensitivity for the editor's 3D view, build mode and play mode, and inverted mouse up / down. (Its own file:
## settings.cfg is the editor's export folders, and two writers of one file would wipe out each other's entries.)

const PATH := "user://preferences.cfg"
const DEFAULTS := {
	"editor_mouse": 1.0,                 ## editor 3D view (orbit / fly): x the normal speed
	"build_mouse": 1.0,                  ## (unused since 0.17.8: build mode uses play_mouse, the Source number)
	"play_mouse": 3.0,                   ## play mode: Source-style sensitivity (0.022 deg per count, like SurfsUp / CS:S)
	"invert_y": false,                   ## mouse forward looks down (everywhere)
	"ground_grid": true,                 ## the editor's 3D view shows the ground grid plane
	"fly_speed": 60.0,                   ## editor 3D view: right mouse + WASD speed (m/s), set with right mouse + wheel
	"relay_url": "wss://relay.sebz.xyz/ws",  ## the playtest relay (Export > Playtest session; local: ws://127.0.0.1:8787/ws)
	"player_name": "Maker",              ## the name testers see on their runs and in the playtest panel
	"playtest_minimized": false,         ## the playtest panel is collapsed to its title row
}

static var _cfg: ConfigFile = null


## Read the file again (after Migrate copied the old SurfForge one in).
static func reload() -> void:
	_cfg = null


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


## Build mode and play mode turn at the same rate: one number in Source's own scale, used by both.
static func build_mouse() -> float:
	return play_mouse()


static func play_mouse() -> float:
	return float(value("play_mouse"))


static func invert_y() -> bool:
	return bool(value("invert_y"))


## Up / down mouse motion with the invert setting applied (+1 or -1).
static func y_sign() -> float:
	return -1.0 if invert_y() else 1.0
