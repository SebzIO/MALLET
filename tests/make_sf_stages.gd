extends SceneTree
## Exports the in-game test map sf_stages to SurfsUp's Maps (and saves maps/sf_stages.sfmap).
func _init() -> void:
	var map := {
		"format": "surfforge-map", "version": 2,
		"ramps": [
			{"points": [[-60, 120, 0], [0, 105, 0], [60, 90, 0]], "width": 13.0, "height": 8.125, "detail": 1.0, "roll": 0.0, "color": "edebe3"},
			{"points": [[-60, 120, 200], [0, 105, 200], [60, 90, 200]], "width": 13.0, "height": 8.125, "detail": 1.0, "roll": 0.0, "color": "9fd3ff"},
		],
		"entities": [
			{"kind": "start", "position": [-84, 128, 0], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "teleport", "position": [84, 84, 0], "size": [30, 40, 10], "yaw": 90.0, "number": 2, "keep_speed": true},
			{"kind": "stage", "position": [-84, 128, 200], "size": [24, 2, 24], "yaw": -90.0, "number": 2},
			{"kind": "finish", "position": [110, 60, 200], "size": [40, 2, 40], "yaw": 0.0},
		],
	}
	print("check: ", SurfsUpExporter.check(map))
	print("export: '", SurfsUpExporter.export_pack(map, "sf_stages", SurfsUpExporter.guess_maps_dir()), "'")
	var f := FileAccess.open("res://maps/sf_stages.sfmap", FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "  "))
	quit()
