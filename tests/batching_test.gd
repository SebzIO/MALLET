extends SceneTree
## Draw batching and light shadows (0.24.4). A cube object's small chunk meshes are drawn as one mesh per material for
## each 64 m region once it settles (the same triangles, a fraction of the draws); an edit shows the small meshes there
## again at once and the region merges again afterwards, with the edit in it. Shadowed lights only draw shadows near the
## camera, and the flat views draw none.
## Run: godot --path . --resolution 1280x720 -s res://tests/batching_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func tris_of(meshes: Array) -> int:
	var n := 0
	for m in meshes:
		for s in (m as ArrayMesh).get_surface_count():
			n += (m as ArrayMesh).surface_get_array_len(s) / 3
	return n


func fine_meshes(cm: CubeModelNode) -> Array:
	var out := []
	for ck in cm._chunks:
		if (cm._chunks[ck][0] as MeshInstance3D).mesh:
			out.append((cm._chunks[ck][0] as MeshInstance3D).mesh)
	return out


func merged_meshes(cm: CubeModelNode) -> Array:
	var out := []
	for rk in cm._regions:
		var r: Dictionary = cm._regions[rk]
		if r["merged"] and r["mi"] != null and (r["mi"] as MeshInstance3D).visible:
			out.append((r["mi"] as MeshInstance3D).mesh)
		elif not r["merged"] or r["mi"] == null or not (r["mi"] as MeshInstance3D).visible:
			for ck in r["chunks"]:
				if cm._chunks.has(ck) and (cm._chunks[ck][0] as MeshInstance3D).visible:
					out.append((cm._chunks[ck][0] as MeshInstance3D).mesh)
	return out


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	# a 40 x 40 m floor of 1 m cubes in two materials, and a few towers: many chunks
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	cm.world.begin()
	for x in 40:
		for z in 40:
			cm.world.set_cell(Vector3i(x * 8, 0, z * 8), 0, CubeWorld.FULL, CubeWorld.blank_tex("Bricks104" if (x + z) % 7 else "Concrete034"))
	for t in 6:
		for y in 12:
			cm.world.set_cell(Vector3i(t * 48, 8 + y * 8, 16), 0, CubeWorld.FULL, CubeWorld.blank_tex("Metal032"))
	cm.world.commit()
	cm.rebuild_all()
	cm.finish_background()
	await process_frame
	var draws_fine := cm.draw_count()
	var tris_fine := tris_of(fine_meshes(cm))
	cm.merge_all()
	var draws_merged := cm.draw_count()
	check("merging draws the object in far fewer pieces", draws_merged * 4 < draws_fine, "(%d -> %d draws)" % [draws_fine, draws_merged])
	check("...with exactly the same triangles", tris_of(merged_meshes(cm)) == tris_fine, "(%d vs %d)" % [tris_of(merged_meshes(cm)), tris_fine])
	# an edit
	cm.world.begin()
	cm.world.set_cell(Vector3i(0, 8, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex("Metal032"))
	cm.world.commit()
	cm.rebuild_dirty()
	var shown_fine := false
	for k in cm._regions:
		var r: Dictionary = cm._regions[k]
		if not r["merged"]:
			shown_fine = true
	check("an edit shows that region's small meshes again at once", shown_fine)
	var tris_now := tris_of(fine_meshes(cm))
	check("...with the edit in them", tris_now > tris_fine, "(%d -> %d)" % [tris_fine, tris_now])
	await create_timer(float(CubeModelNode.MERGE_AFTER_MS) / 1000.0 + 0.3).timeout
	for i in 5:
		await process_frame
	var all_merged := true
	for k in cm._regions:
		if not cm._regions[k]["merged"]:
			all_merged = false
	check("...and merges again once it settles, edit included", all_merged and tris_of(merged_meshes(cm)) == tris_now,
		"(%d vs %d)" % [tris_of(merged_meshes(cm)), tris_now])
	var hit: Dictionary = ed.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10.5, 50, 10.5), Vector3(10.5, -50, 10.5)))
	check("picking and collision still work (the small chunks' shapes)", not hit.is_empty() and hit.collider.get_meta("cube_model", null) == cm
		and absf((hit["position"] as Vector3).y - 1.0) < 0.01, str(hit.get("position")))
	# the SurfsUp export draws it the same way (a few region meshes), its collision unchanged
	var scene := SurfsUpExporter.build_scene(ed._map_dict(), "surf_batch")
	var obj := scene.find_child("CubeObject0", true, false)
	var meshes := []
	var shapes := 0
	if obj:
		for n in obj.find_children("*", "MeshInstance3D", true, false):
			meshes.append((n as MeshInstance3D).mesh)
		shapes = obj.find_children("*", "CollisionShape3D", true, false).size()
	check("the SurfsUp export draws it in a few region meshes, every triangle there", obj != null and meshes.size() <= 4
		and tris_of(meshes) >= tris_now, "(%d meshes, %d of %d triangles)" % [meshes.size(), tris_of(meshes), tris_now])
	check("...and keeps its collision", shapes >= 1600, "(%d shapes)" % shapes)
	scene.free()
	# lights
	var l := LightNode.make_light({"kind": "point", "color": "ffffff", "energy": 2.0, "range": 2000.0, "shadows": true})
	check("a shadowed light draws shadows only near the camera", l.distance_fade_enabled and is_equal_approx(l.distance_fade_shadow, LightNode.SHADOW_NEAR)
		and l.distance_fade_begin > 10000.0)
	l.free()
	var flat_ok := true
	for p in ed.panes:
		if p.is_ortho() and p.viewport.positional_shadow_atlas_size != 0:
			flat_ok = false
	check("the flat views draw no light shadows", flat_ok)
	print("batching_test: ", "PASS" if ok else "FAIL")
	quit()
