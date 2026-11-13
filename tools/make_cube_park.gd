extends SceneTree
## Builds templates/5_cube_park: a surf made of build mode cubes (two V ramps from the Geometry menu's prism, each
## half a cube object's worth of cut cubes), joined by a teleport to a destination that keeps your speed.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tools/make_cube_park.gd

const W := 8.0                     ## each half's width (m): with H, a 56 degree face
const H := 12.0
const L := 64.0                    ## length (m, the Geometry menu's limit at a 1 m grid)
const PITCH := 6.0                 ## the ramps drop this many degrees along their length
var ed


func _init() -> void:
	call_deferred("_run")


## One V ramp as a cube object: ridge along -Z from `at` (the ridge's top at its start), dropping PITCH degrees.
func v_ramp(at: Vector3, tex: String, pitch_sign_left: float) -> CubeModelNode:
	var m := CubeModelNode.new()
	ed.cube_models_root.add_child(m)
	var halves := [ShapeGen.generate("prism", {"w": W, "h": H, "l": L, "pitch": -PITCH}, 0, 0),
		ShapeGen.generate("prism", {"w": W, "h": H, "l": L, "yaw": 180.0, "pitch": PITCH * pitch_sign_left}, 0, 0)]
	m.world.begin()
	for k in 2:
		var g: Dictionary = halves[k]
		if String(g["error"]) != "":
			push_error(g["error"])
			continue
		var b := ShapeGen.cell_bounds(g["cells"])
		print("half %d: %d cells, bounds %s (ticks), size %s" % [k, g["cells"].size(), b, g.get("size")])
		# right half: ridge (its x = 0 side) on x = 0; left half: its high side (x max) on x = 0. Both run from z = 0 to -L.
		var off := Vector3i(-int(b.position.x) if k == 0 else -int(b.end.x), -int(b.position.y), -int(b.end.z))
		ShapeGen.place(m.world, g["cells"], off, tex)
	m.world.commit()
	m.position = at - Vector3(0, 0, 0)
	m.rebuild_all()
	if m.has_method("finish_background"):
		m.finish_background()
	return m


func ridge_y(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, z), Vector3(x, -50, z))
	var hit: Dictionary = ed.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if hit else -999.0


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._toggle_views()                                   # one big 3D view for the thumbnail
	ed._load_dict({"environment": Look.preset_environment("day"), "entities": [
		{"kind": "start", "position": [-5.0, 38.0, 18.0], "size": [16.0, 2.0, 16.0], "yaw": 0.0},
		{"kind": "teleport", "position": [0.0, 20.0, -82.0], "size": [44.0, 44.0, 6.0], "yaw": 0.0, "number": 1,
			"to": "destination", "keep_speed": true},
		{"kind": "destination", "position": [105.0, 36.0, 6.0], "size": [2.0, 3.5, 2.0], "yaw": 0.0, "number": 1},
		{"kind": "finish", "position": [110.0, 4.0, -100.0], "size": [60.0, 2.0, 60.0], "yaw": 0.0}]})
	await process_frame
	v_ramp(Vector3(0, 10, 0), "Concrete034", 1.0)
	v_ramp(Vector3(110, 10, 0), "Metal032", 1.0)
	for i in 4:
		await physics_frame
	for x in [-4.0, 0.3, 4.0, 106.0, 114.0]:
		print("x %5.1f: z -4 -> %.2f   z -60 -> %.2f" % [x, ridge_y(x, -4), ridge_y(x, -60)])
	var map: Dictionary = ed._map_dict()
	map["template"] = {"title": "Cube Park", "description": "Built in build mode (E): two V ramps from the Geometry menu (F6), joined by a teleport to a destination that keeps your speed."}
	var problems := SurfsUpExporter.check(map)
	print("export check: ", problems)
	ed._select(null)
	var cam := ed.panes[0].camera as OrbitCamera
	cam.fov = 32.0
	cam.cull_mask = 1
	ed.frame_course(cam, 16.0 / 9.0)
	for i in 12:
		await process_frame
	var img: Image = ed.panes[0].viewport.get_texture().get_image()
	var target := Vector2(img.get_width(), img.get_width() * 9.0 / 16.0)
	img = img.get_region(Rect2i(0, int((img.get_height() - target.y) / 2), int(target.x), int(target.y)))
	img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path("res://templates/5_cube_park.png"))
	var text := JSON.stringify(map, "  ")
	var f := FileAccess.open("res://templates/5_cube_park.mallet", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("5_cube_park: %d KB" % (text.length() / 1024))
	quit()
