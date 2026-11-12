extends SceneTree
## The 2D editor (0.19.5): a selected object behind another one is still the one you grab (a click on anything else
## picks that); zones, kill zones, boosters and platforms stretch and shrink by squares on their sides, like blocks;
## a ramp's texture can be turned, shifted, scrolled and made see-through, as in build mode, in the editor and in
## the SurfsUp export.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/editor2d_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await frames(2)
	ed.welcome.hide()
	ed._load_dict({"blocks": [{"shape": "box", "position": [0.0, 0.0, 0.0], "size": [4.0, 4.0, 4.0]},
		{"shape": "box", "position": [0.0, 10.0, 0.0], "size": [4.0, 4.0, 4.0]}],
		"entities": [{"kind": "kill", "position": [40.0, 10.0, 0.0], "size": [10.0, 10.0, 10.0]}],
		"ramps": [{"points": [[-60, 60, 30], [-30, 50, 30], [0, 40, 30]], "look": "material", "material": "Bricks104"}]})
	await frames(3)
	var top: ViewPane = null
	for p in ed.panes:
		if p.is_ortho() and absf(p.camera.global_basis.z.y) > 0.9:
			top = p
	top.frame(Vector3(0, 0, 0), 30.0)
	await frames(3)
	var low: BlockNode = ed.blocks_root.get_child(0)
	var high: BlockNode = ed.blocks_root.get_child(1)
	var mouse: Vector2 = top.camera.unproject_position(Vector3(0, 6, 0))
	check("the top view sees the higher block first", ed._pick_object(top, mouse) == high)
	ed._select(low)
	check("...but with the lower one selected, it grabs the selected one through it", ed._pick_object(top, mouse, true) == low)
	ed._select(null)
	check("with nothing selected, the front one", ed._pick_object(top, mouse, true) == high)
	# a kill zone's side handle
	var kz: EntityNode = ed.entities_root.get_child(0)
	var hs: Array = kz.face_handles()
	check("a kill zone has six side handles at its faces", hs.size() == 6 and (hs[1][0] as Vector3).is_equal_approx(Vector3(45, 10, 0)), str(hs[1][0]))
	var d := kz.resized(kz.to_dict(), 0, 1.0, 4.0)
	kz.from_dict(d)
	check("stretching its +x side 4 m keeps the -x side where it was", kz.size.is_equal_approx(Vector3(14, 10, 10))
		and is_equal_approx(kz.position.x - kz.size.x * 0.5, 35.0), "(%s at %s)" % [kz.size, kz.position])
	var plat := EntityNode.create("start")
	ed.entities_root.add_child(plat)
	plat.position = Vector3(0, 20, 50)
	var top_y := plat.position.y
	plat.from_dict(plat.resized(plat.to_dict(), 1, -1.0, 2.0))
	check("a platform made thicker from below keeps its top", is_equal_approx(plat.position.y, top_y) and is_equal_approx(plat.size.y, 4.0))
	# ramp texture settings
	var r: RampNode = ed.ramps_root.get_child(0)
	var plain_uv: PackedVector2Array = (r._mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	ed._select(r)
	await frames(1)
	ed._edit_prop("tex_r", 1)
	ed._edit_prop("tex_u", 0.25)
	ed._edit_prop("tex_su", 0.5)
	await frames(1)
	var tm := r._mesh_instance.mesh as ArrayMesh
	var mat := tm.surface_get_material(0)
	check("a turned, shifted, scrolling ramp texture uses the cube surface shader", mat is ShaderMaterial
		and (mat as ShaderMaterial).get_shader_parameter("scroll") == Vector2(0.5, 0.0))
	var uv: PackedVector2Array = tm.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check("...with its texture coordinates turned and shifted", uv.size() == plain_uv.size() and not uv[3].is_equal_approx(plain_uv[3]))
	check("...kept in the map", float(r.to_dict()["tex"]["u"]) == 0.25 and int(r.to_dict()["tex"]["r"]) == 1)
	var scene := SurfsUpExporter.build_scene(ed._map_dict(), "surf_test")
	if scene != null:
		var found := false
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m is ArrayMesh and m.get_surface_count() > 0 and m.surface_get_material(0) is ShaderMaterial \
					and (m.surface_get_material(0) as ShaderMaterial).get_shader_parameter("scroll") == Vector2(0.5, 0.0):
				found = true
		check("...and in the SurfsUp export", found)
		scene.free()
	print("editor2d_test: ", "PASS" if ok else "FAIL")
	quit()
