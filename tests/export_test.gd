extends SceneTree
## Export test: build a map, export it to a scratch Maps folder, then load it back exactly like the game does
## (mount the .pck, load res://Levels/<name>.tscn) and inspect it.
## Run: godot --headless --path D:/SurfForge -s res://tests/export_test.gd -- <scratch_maps_dir>

func _init() -> void:
	var maps: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(maps)
	var map := {
		"format": "surfforge-map", "version": 2,
		"ramps": [
			{"points": [[-60, 120, 0], [0, 105, 20], [60, 90, 0]], "width": 13.0, "height": 8.125, "detail": 1.0, "roll": 0.0, "color": "e04f9a"},
			{"points": [[100, 80, 40], [180, 60, 60]], "width": 13.0, "height": 8.125, "detail": 1.0, "roll": 0.0, "solid": true, "base_depth": 10.0, "color": "4fa3e0"},
		],
		"entities": [
			{"kind": "start", "position": [-84, 128, 0], "size": [20, 2, 26], "yaw": -90.0},
			{"kind": "finish", "position": [220, 40, 60], "size": [40, 2, 40], "yaw": 0.0},
		],
	}
	print("check: ", SurfsUpExporter.check(map))
	print("bad name check: '", SurfsUpExporter.export_pack(map, "my map", maps), "'")
	var err := SurfsUpExporter.export_pack(map, "sf_export_test", maps)
	print("export result: '%s'" % err)
	var pck := maps.path_join("sf_export_test.pck")
	print("pck size: ", FileAccess.get_file_as_bytes(pck).size(), " bytes")
	print("mounted: ", ProjectSettings.load_resource_pack(pck))
	var scene: PackedScene = load("res://Levels/sf_export_test.tscn")
	var root := scene.instantiate()
	var scripts := 0
	var stack := [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n.get_script(): scripts += 1
		var line := "  " + str(root.get_path_to(n)) + " <" + n.get_class() + ">"
		if n is Node3D: line += " at " + str((n as Node3D).position.snapped(Vector3.ONE * 0.1))
		if n is CollisionObject3D: line += " layer %d mask %d" % [n.collision_layer, n.collision_mask]
		for k in n.get_meta_list(): line += " %s=%s" % [k, n.get_meta(k)]
		if n is CollisionShape3D and n.shape: line += " shape=" + n.shape.get_class()
		print(line)
	print("scripts in scene: ", scripts, "   root SpawnPoint: ", root.get_node_or_null("SpawnPoint") != null)
	quit()
