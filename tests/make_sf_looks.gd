extends SceneTree
## In-game showcase sf_looks: aurora sky, all eight ramp looks side by side; the aurora ramp is the playable line.
func _init() -> void:
	var colors := {"color": "edebe3", "ceramic": "21408f", "steel": "ccd1db", "grid": "9ea8b8", "aurora": "26ff99",
		"nebula": "d933e6", "neon": "1ae6ff", "texture": "ffffff"}
	var ramps := []
	var i := 0
	for look in Look.LOOK_ORDER:
		var z := -105.0 + i * 30.0
		var r := {"points": [[-60, 120, z], [0, 105, z], [60, 90, z]], "width": 20.0, "height": 12.5, "detail": 1.0, "roll": 0.0,
			"color": colors[look], "look": look}
		if look == "texture":
			r["texture"] = ProjectSettings.globalize_path("res://icon.svg").replace("icon.svg", "tests/out/test_texture.png")
			r["tex_scale"] = 30.0
		ramps.append(r)
		i += 1
	var play_z := -105.0 + Look.LOOK_ORDER.find("aurora") * 30.0
	var env := Look.preset_environment("aurora")
	var map := {"format": "surfforge-map", "version": 2, "environment": env, "ramps": ramps,
		"entities": [{"kind": "start", "position": [-84, 128, play_z], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "finish", "position": [110, 60, play_z], "size": [40, 2, 40], "yaw": 0.0}]}
	print("export: '", SurfsUpExporter.export_pack(map, "sf_looks", SurfsUpExporter.guess_maps_dir()), "'")
	var f := FileAccess.open("res://maps/sf_looks.sfmap", FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "  "))
	quit()
