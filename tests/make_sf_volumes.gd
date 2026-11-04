extends SceneTree
## Exports the in-game test map sf_volumes (starter course + booster after the ramp + kill zone) to SurfsUp's Maps.
func _init() -> void:
	var map := {
		"format": "surfforge-map", "version": 2,
		"ramps": [{"points": [[-60, 120, 0], [0, 105, 0], [60, 90, 0]], "width": 13.0, "height": 8.125, "detail": 1.0, "roll": 0.0, "color": "edebe3"}],
		"entities": [
			{"kind": "start", "position": [-84, 128, 0], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "finish", "position": [190, 60, 0], "size": [40, 2, 40], "yaw": 0.0},
			{"kind": "booster", "position": [76, 86, 0], "size": [16, 24, 30], "yaw": -90.0, "pitch": 25.0, "strength": 600.0, "mode": 0},
			{"kind": "kill", "position": [-30, 70, 0], "size": [60, 20, 60], "yaw": 0.0},
		],
	}
	print("export: '", SurfsUpExporter.export_pack(map, "sf_volumes", SurfsUpExporter.guess_maps_dir()), "'")
	var f := FileAccess.open("res://maps/sf_volumes.sfmap", FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "  "))
	quit()
