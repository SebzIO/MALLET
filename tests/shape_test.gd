extends SceneTree
## Geometry menu test: every shape makes valid, aligned, convex octree cells; nothing is lost (every point inside
## the shape lands in a cube); a ramp's top follows its slope; and a shape placed from the menu becomes one cube
## object you can undo. Run headless:
##   godot --path . --headless -s res://tests/shape_test.gd -- <existing out folder>

var ed
var out := ""


func _init() -> void:
	call_deferred("_run")


func _covered(w: CubeWorld, pt: Vector3) -> bool:
	return w.leaf_at((pt - Vector3.ONE * 0.002) / CubeWorld.TICK) != null   # (2 mm inside: samples on a face are not holes)


func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	var ok := true
	var ids: Array = []
	for def in ShapeGen.defs():
		ids.append(String(def["id"]))
	print("shapes: ", ", ".join(ids))

	for def in ShapeGen.defs():
		var id := String(def["id"])
		var res: Dictionary = ShapeGen.generate(id, ShapeGen.defaults(id), 0, 2)
		var cells: Array = res["cells"]
		var err := String(res.get("error", ""))
		var size: Vector3 = res.get("size", Vector3.ZERO)
		var aligned := true
		var convex := true
		var in_bounds := true
		for c in cells:
			var o: Vector3i = c[0]
			var q: int = c[1]
			var s := CubeWorld.size_of(q)
			if o.x % s != 0 or o.y % s != 0 or o.z % s != 0:
				aligned = false
			if not CubeWorld.is_valid_shape(c[2] as PackedByteArray):
				convex = false
			var lo := Vector3(o) * CubeWorld.TICK
			var hi := lo + Vector3.ONE * CubeWorld.metres(q)
			if lo.x < -0.001 or lo.y < -0.001 or lo.z < -0.001 or hi.x > size.x + 0.001 \
					or hi.y > size.y + 0.001 or hi.z > size.z + 0.001:
				in_bounds = false
		# place it and check a grid of points inside the shape all land in a cube (no holes)
		var w := CubeWorld.new()
		ShapeGen.place(w, cells, Vector3i.ZERO, "")
		var holes := 0
		var samples := 0
		var spec: Dictionary = ShapeGen._spec(id, ShapeGen.defaults(id), 1.0)
		for ix in 15:
			for iy in 15:
				for iz in 15:
					var pt := Vector3((ix + 0.5) / 15.0 * size.x, (iy + 0.5) / 15.0 * size.y, (iz + 0.5) / 15.0 * size.z)
					if not ShapeGen._inside(spec, pt):
						continue
					samples += 1
					if not _covered(w, pt):
						holes += 1
		var good := err == "" and not cells.is_empty() and aligned and convex and in_bounds and holes <= maxi(0, samples / 40) and samples > 0
		ok = ok and good
		print("%-9s cells %5d  aligned %s  convex %s  in bounds %s  inside points %4d  holes %d  %s" % [
			id, cells.size(), str(aligned), str(convex), str(in_bounds), samples, holes, err])

	# a ramp is one plane, carried by the cells themselves, so its face must be truly flat
	var rres: Dictionary = ShapeGen.generate("ramp", ShapeGen.defaults("ramp"), 0, 1)
	var rh := float(ShapeGen.defaults("ramp")["h"])
	var rl := float(ShapeGen.defaults("ramp")["l"])
	var flat := true
	var cut_cells := 0
	for c in rres["cells"]:
		if c.size() < 4:
			continue
		var cut: Array = c[3]
		if cut.size() != 1:
			flat = false
			continue
		var o: Vector3i = c[0]
		var q: int = c[1]
		var size := CubeWorld.metres(q)
		var nrm: Vector3i = (cut[0] as Array)[0]
		var off: int = (cut[0] as Array)[1]
		var uz := 4.0
		var uy := (float(off) - float(nrm.z) * uz) / float(nrm.y)
		var wy := float(o.y) * CubeWorld.TICK + uy / 8.0 * size
		var wz := float(o.z) * CubeWorld.TICK + uz / 8.0 * size
		if absf(wy - rh * wz / rl) > 0.01:
			flat = false
		cut_cells += 1
	print("ramp: one plane on every surface cell %s  cut cells %d of %d" % [str(flat), cut_cells, rres["cells"].size()])
	ok = ok and flat and cut_cells > 0



	# the preview mesh the menu draws (and the placing ghost uses): it has to wind exactly like the real cube meshes, or
	# its faces are culled from the outside, and it may not be made of slivers
	var bw := CubeWorld.new()
	ShapeGen.place(bw, ShapeGen.generate("box", {"w": 1.0, "h": 1.0, "d": 1.0}, 0, 0)["cells"], Vector3i.ZERO, "")
	var core_sign := 0.0
	for ck in bw.render_chunks():
		var cm: ArrayMesh = bw.chunk_mesh(ck)[0]
		for si in cm.get_surface_count():
			var ca: Array = cm.surface_get_arrays(si)
			var cv: PackedVector3Array = ca[Mesh.ARRAY_VERTEX]
			var cn: PackedVector3Array = ca[Mesh.ARRAY_NORMAL]
			for i in range(0, cv.size(), 3):
				var cf: Vector3 = (cv[i + 1] - cv[i]).cross(cv[i + 2] - cv[i])
				if core_sign == 0.0 and cf.length() > 1e-9:
					core_sign = signf(cf.dot(cn[i]))
	var pv_tris := 0
	var pv_wind := 0
	var pv_degen := 0
	var pv_bad := 0
	for id in ["box", "cone", "cylinder", "pyramid", "prism", "rhomboid", "sphere", "ramp", "stairs"]:
		var cres: Dictionary = ShapeGen.generate(id, ShapeGen.defaults(id), 0, 2)
		var got: Array = ShapeGen.preview_mesh(cres["cells"])
		var m: ArrayMesh = got[0]
		if m.get_surface_count() != 1:
			pv_bad += 1
			continue
		var arr: Array = m.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in range(0, vs.size(), 3):
			pv_tris += 1
			var fn: Vector3 = (vs[i + 1] - vs[i]).cross(vs[i + 2] - vs[i])
			if fn.length() < 1e-9:
				pv_degen += 1
			elif core_sign == 0.0 or signf(fn.dot(ns[i])) != core_sign:
				pv_wind += 1
	print("preview mesh: %d triangles, %d wound unlike the cube mesh, %d degenerate (cube mesh winds %s)" % [
		pv_tris, pv_wind, pv_degen, str(core_sign)])
	ok = ok and pv_wind == 0 and pv_degen == 0 and pv_bad == 0 and pv_tris > 0

	# the menu itself: generate, place, one object, undoable
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	await process_frame
	var before: int = ed.cube_models_root.get_child_count()
	ed.build.shapes.open_panel()

	# a typed number is taken on Enter, and the field shows the value it actually took
	ed.build.shapes._on_shape_selected(0)                       # box
	var wnum: DragNumber = ed.build.shapes._rows["w"]["number"]
	wnum.editable = true
	wnum.text = "6.5"
	wnum.text_submitted.emit("6.5")
	ed.build.shapes.tick(0.2)                                   # (flush the pending rebuild, as a frame would)
	var took := float(ed.build.shapes._values["w"])
	var shown: String = wnum.text
	var shown_preview: bool = ed.build.shapes._mesh_inst != null and ed.build.shapes._mesh_inst.mesh != null
	print("typed width 6.5: took %.3f  field shows '%s'  slider %.3f  preview %s" % [
		took, shown, float(ed.build.shapes._rows["w"]["slider"].value), str(shown_preview)])
	ok = ok and absf(took - 6.5) < 0.001 and shown == "6.50" and shown_preview
	ok = ok and absf(float(ed.build.shapes._rows["w"]["slider"].value) - 6.5) < 0.001

	# a slow shape rebuilds on a worker thread: the value can keep moving and the exact shape still lands
	ed.build.shapes._on_shape_selected(3)                       # cone
	ed.build.shapes._values = {"r": 2.5, "h": 4.0, "sides": 24.0}
	ed.build.shapes._build_params()
	ed.build.shapes._on_detail(2.0)
	ed.build.shapes._cost_ms = 500.0                            # (pretend the last exact build was slow)
	ed.build.shapes._set_value("r", 3.0, "slider")
	var frames_waited := 0
	for i in 500:
		ed.build.shapes.tick(0.02)
		frames_waited += 1
		if ed.build.shapes._task < 0 and not ed.build.shapes._dirty:
			break
		await process_frame
	var threaded_ok: bool = ed.build.shapes._task < 0 and not ed.build.shapes._cheap \
		and not ed.build.shapes._cells.is_empty() and ed.build.shapes._mesh_inst.mesh != null
	print("worker-thread rebuild: %s  frames %d  cubes %d  quick preview left over: %s" % [
		str(threaded_ok), frames_waited, ed.build.shapes._cubes, str(ed.build.shapes._cheap)])
	ok = ok and threaded_ok

	ed.build.shapes._on_shape_selected(7)                       # stairs
	ed.build.shapes._values = {"w": 4.0, "run": 1.0, "rise": 0.5, "steps": 5.0}
	ed.build.shapes._build_params()
	ed.build.shapes._regen()
	var plan: int = ed.build.shapes._cubes
	ed.build.shapes.start_placing()
	var placed_at: Vector3 = ed.build.shapes._anchor()
	ed.build.shapes.confirm_place()
	await process_frame
	var made: CubeModelNode = ed.cube_models_root.get_child(ed.cube_models_root.get_child_count() - 1) if \
		ed.cube_models_root.get_child_count() > before else null
	var cells_in := made.world.count() if made != null else -1
	print("menu placed stairs: %s object at %s  plan %d cubes  placed %d cells  undone in one step: %s" % [
		str(made != null), str(placed_at), plan, cells_in, str(ed.build._history.size() >= 2)])
	ok = ok and made != null and cells_in > 0 and placed_at.y > -0.001

	print("SHAPE TEST ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
