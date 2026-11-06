extends SceneTree
## Cube world (build mode's geometry): pull / push cubes, merging, face and corner pushes (slopes), splitting a sloped
## cube, validity, textures, rotate / flip, copy / paste, undo / redo, saving, hidden faces.
## Run: godot --headless --path D:/SurfForge -s res://tests/cube_test.gd

var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## Is a point (cube units 0..8, inside cube corners c) inside the solid?
func inside(c: PackedByteArray, p: Vector3) -> bool:
	for o in 6:
		for t in CubeWorld.face_triangles(c, o):
			var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0]).normalized()
			if n.dot(p - t[0]) > 1e-4:
				return false
	return true


func world_solid_at(w: CubeWorld, pt_ticks: Vector3) -> bool:
	var k = w.leaf_at(pt_ticks)
	if k == null:
		return false
	var s := float(CubeWorld.size_of(k.w))
	var local := (pt_ticks - Vector3(k.x, k.y, k.z)) / s * 8.0
	return inside(w.leaves[k][0], local)


func _run() -> void:
	var w := CubeWorld.new()
	var p := 0                                            # 1 m cubes (8 ticks)
	# pulling out of "air": a selection under the spot, facing up
	var sel := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3)
	w.begin()
	sel = w.pull(sel, "Bricks104")
	w.commit()
	check("pull: one 1 m cube appears", w.count() == 1 and w.leaves.has(Vector4i(0, 0, 0, 0)))
	check("...and the selection moved onto it", sel["o"] == Vector3i(0, 0, 0))
	w.begin()
	sel = w.pull(sel)
	w.commit()
	check("pull again: a second cube on top, same texture", w.leaves.has(Vector4i(0, 8, 0, 0))
		and w.leaves[Vector4i(0, 8, 0, 0)][1][3] == "Bricks104")
	w.begin()
	sel = w.push(sel)
	w.commit()
	check("push: the top cube is gone", w.count() == 1 and sel["o"] == Vector3i(0, 0, 0))

	# 8 cubes filling a 2 m cell merge into one 2 m cube
	w.clear()
	w.begin()
	var floor_sel := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 2))
	floor_sel = w.pull(floor_sel, "")
	floor_sel = w.pull(floor_sel, "")
	w.commit()
	check("a full 2 x 2 x 2 block of 1 m cubes merges into one 2 m cube", w.count() == 1 and w.leaves.has(Vector4i(0, 0, 0, 1)))
	# editing one 1 m cell of it splits it back
	w.begin()
	w.push(CubeWorld.make_sel(Vector3i(8, 8, 8), p, 3))
	w.commit()
	check("pushing one corner cell out of it splits it (7 left)", w.count() == 7)

	# face push: the top of a cube goes down in 1/8 steps; 8 steps and it's gone
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3))
	w.commit()
	var top := CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3)
	w.begin()
	w.push_face(top, 1)
	w.commit()
	var c: PackedByteArray = w.leaves[Vector4i(0, 0, 0, 0)][0]
	check("F + wheel: the top face drops 1/8", CubeWorld.corner(c, 7).y == 7 and CubeWorld.corner(c, 0).y == 0)
	for i in 7:
		w.begin()
		w.push_face(top, 1)
		w.commit()
	check("...and after 8 steps the cube is gone", w.count() == 0)
	w.undo()
	check("undo brings the 1/8-thick cube back", w.count() == 1 and CubeWorld.corner(w.leaves[Vector4i(0, 0, 0, 0)][0], 7).y == 1)
	for i in 7:
		w.undo()
	check("undo all the way: a full cube again", w.leaves[Vector4i(0, 0, 0, 0)][0] == CubeWorld.FULL)
	w.redo()
	check("redo", CubeWorld.corner(w.leaves[Vector4i(0, 0, 0, 0)][0], 7).y == 7)
	w.undo()

	# pulling a face that's already at its side starts a thin cube on top
	w.begin()
	var up := w.push_face(top, -1)
	w.commit()
	var thin = w.leaves.get(Vector4i(0, 8, 0, 0))
	check("F + wheel out at the side: a 1/8 cube starts on top", thin != null and CubeWorld.corner(thin[0], 7).y == 1
		and CubeWorld.corner(thin[0], 0).y == 0 and up["o"] == Vector3i(0, 8, 0))

	# corner push: a slope
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3))
	w.commit()
	for i in 8:
		w.begin()
		w.push_face(top, 1, 2)                             # corner 2 of the top face's quad
		w.commit()
	c = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var lowered := 0
	for n in 8:
		if (n >> 1) & 1 and CubeWorld.corner(c, n).y == 0:
			lowered += 1
	check("Q + wheel: one top corner pushed all the way down (a corner slope)", lowered == 1 and CubeWorld.is_valid_shape(c))
	# push both corners on one side: a wedge (a ramp)
	w.begin()
	for i in 8:
		w.push_face(top, 1, 1)
	w.commit()
	c = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var wedge := CubeWorld.is_valid_shape(c) and inside(c, Vector3(1, 6, 4)) == (CubeWorld.corner(c, 2).y == 8 or CubeWorld.corner(c, 3).y == 8)
	check("two top corners down: a wedge, still valid", CubeWorld.is_valid_shape(c), "(corners %s)" % [c])
	var bad := CubeWorld.FULL.duplicate()
	bad[7 * 3] = 4
	bad[7 * 3 + 1] = 4
	bad[7 * 3 + 2] = 4
	check("a dented (concave) cube is rejected", not CubeWorld.is_valid_shape(bad))

	# splitting a sloped 2 m cube keeps its shape (sample points agree)
	w.clear()
	var wc := CubeWorld.FULL.duplicate()
	for n in [3, 7]:                                      # +X top corners down to the bottom: a wedge
		wc[n * 3 + 1] = 0
	w.set_cell(Vector3i(0, 0, 0), 1, wc, CubeWorld.blank_tex())
	var before := []
	for x in 8:
		for y in 8:
			for z in 8:
				before.append(world_solid_at(w, Vector3(x * 2 + 1, y * 2 + 1, z * 2 + 1)))
	w._split(Vector4i(0, 0, 0, 1))
	var agree := 0
	var i2 := 0
	for x in 8:
		for y in 8:
			for z in 8:
				if world_solid_at(w, Vector3(x * 2 + 1, y * 2 + 1, z * 2 + 1)) == before[i2]:
					agree += 1
				i2 += 1
	check("splitting a wedge into 8 keeps its shape", agree >= 500, "(%d / 512 sample points agree)" % agree)

	# textures, rotate, flip
	w.clear()
	w.begin()
	var row := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 1))
	row = w.pull(row, "")
	w.set_texture(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3), "Grass004")
	w.commit()
	check("Y: the top of one cube textured", w.leaves[Vector4i(0, 0, 0, 0)][1][3] == "Grass004" and w.leaves[Vector4i(8, 0, 0, 0)][1][3] == "")
	w.begin()
	w.set_texture(CubeWorld.make_sel(Vector3i(8, 0, 0), p, 3), "Metal009", true)
	w.commit()
	check("...all faces of the other (all faces on)", w.leaves[Vector4i(8, 0, 0, 0)][1] == CubeWorld.blank_tex("Metal009"))
	# rotate the 2 x 1 row a quarter turn about Y: it becomes 1 x 2 along Z
	w.begin()
	var r := w.rotate(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(2, 1, 1)), 1)
	w.commit()
	check("R: a 2 x 1 row turns into 1 x 2", w.count() == 2 and r["s"] == Vector3i(1, 1, 2))
	var tops := []
	for k in w.leaves:
		tops.append(w.leaves[k][1][3])
	check("...tops keep their textures", tops.has("Grass004") and tops.has("Metal009"))
	w.begin()
	w.flip(r)
	w.commit()
	check("X: flipping keeps two cubes", w.count() == 2)

	# copy / paste
	var clip := w.copy(r)
	w.begin()
	var pasted := w.paste(CubeWorld.make_sel(Vector3i(40, 0, 0), p, 3), clip)
	w.commit()
	check("C / V: copy and paste somewhere else", w.count() == 4 and pasted["s"] == Vector3i(1, 1, 2))

	# saving
	var d := w.to_dict()
	var w2 := CubeWorld.from_dict(d)
	var same := w2.count() == w.count()
	for k in w.leaves:
		same = same and w2.leaves.has(k) and w2.leaves[k][0] == w.leaves[k][0] and w2.leaves[k][1] == w.leaves[k][1]
	check("save / load keeps every cube, corner and texture", same)

	# hidden faces: two cubes side by side draw 10 faces (20 triangles), not 12
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 1)))
	w.commit()
	var mesh_data := w.chunk_mesh(Vector3i(0, 0, 0), true)   # (outline mode: every face on its own)
	check("faces between touching cubes aren't drawn", (mesh_data[1] as PackedVector3Array).size() == 20 * 3,
		"(%d triangles)" % ((mesh_data[1] as PackedVector3Array).size() / 3))
	mesh_data = w.chunk_mesh(Vector3i(0, 0, 0))
	check("and the faces side by side are drawn as one (6 rectangles)", (mesh_data[1] as PackedVector3Array).size() == 12 * 3,
		"(%d triangles)" % ((mesh_data[1] as PackedVector3Array).size() / 3))

	# ---- texture settings (Sauerbraten's vslots)
	var slot := CubeWorld.make_slot({"id": "Bricks104", "s": 2.0, "r": 1, "u": 0.25, "su": 0.5, "c": "ff8080", "a": 0.5, "l": "Grass004"})
	var back := CubeWorld.parse_slot(slot)
	check("texture settings survive writing and reading", back["id"] == "Bricks104" and float(back["s"]) == 2.0 and int(back["r"]) == 1
		and float(back["u"]) == 0.25 and float(back["su"]) == 0.5 and back["c"] == "ff8080" and float(back["a"]) == 0.5 and back["l"] == "Grass004",
		"(%s)" % slot)
	check("a plain texture stays just its name", CubeWorld.make_slot({"id": "Metal009"}) == "Metal009")
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3), "Bricks104")
	w.set_slot_param(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3), false, func(d: Dictionary) -> Dictionary:
		d["u"] = 0.5
		return d)
	w.commit()
	var top_slot: String = w.leaves[Vector4i(0, 0, 0, 0)][1][3]
	check("O / P: shift a face's texture (only that face)", CubeWorld.parse_slot(top_slot)["u"] == 0.5
		and w.leaves[Vector4i(0, 0, 0, 0)][1][0] == "Bricks104", "(%s)" % top_slot)
	var mm: Array = w.chunk_mesh(Vector3i.ZERO)
	check("faces with different settings get their own surface", (mm[0] as ArrayMesh).get_surface_count() == 2)
	w.begin()
	var nrep := w.replace_texture("Bricks104", "Metal009")
	w.commit()
	check("replace: every Bricks face becomes Metal (keeping its settings)", nrep == 6
		and CubeWorld.parse_slot(w.leaves[Vector4i(0, 0, 0, 0)][1][3])["u"] == 0.5 and CubeWorld.slot_id(w.leaves[Vector4i(0, 0, 0, 0)][1][3]) == "Metal009")

	# ---- materials
	w.clear()
	w.begin()
	var flr := CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(4, 1, 4))
	w.pull(flr)
	w.set_material(CubeWorld.make_sel(Vector3i(0, 8, 0), p, 3, Vector3i(4, 2, 4)), "water")
	w.set_material(CubeWorld.make_sel(Vector3i(0, 24, 0), p, 3, Vector3i(1, 1, 1)), "clip")
	w.commit()
	check("water fills a 4 x 2 x 4 space", w.mat_at(Vector3(4, 12, 4)) == "water" and w.mat_at(Vector3(4, 20, 28)) == "water")
	var mb := w.material_boxes()
	check("material boxes for export", (mb.get("water", []) as Array).size() >= 1 and (mb.get("clip", []) as Array).size() == 1)
	var cm2: Array = w.chunk_mesh(Vector3i.ZERO)
	var col_n := (cm2[1] as PackedVector3Array).size() / 3
	var floor_n := 12                                     # (the 4 x 1 x 4 floor alone: 6 merged rectangles)
	w.undo()
	check("undo takes the materials away again", w.mats.is_empty())
	w.redo()
	check("clip adds invisible collision", col_n >= floor_n + 12, "(%d triangles)" % col_n)
	w.begin()
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(4, 1, 4)), "noclip")
	w.commit()
	var cm3: Array = w.chunk_mesh(Vector3i.ZERO)
	check("noclip: the floor cubes have no collision any more", (cm3[1] as PackedVector3Array).size() / 3 <= 12 + 2,
		"(%d triangles)" % ((cm3[1] as PackedVector3Array).size() / 3))
	var w3 := CubeWorld.from_dict(w.to_dict())
	check("materials are saved with the cubes", w3.mats.size() == w.mats.size() and w3.mat_at(Vector3(4, 12, 4)) == "water")

	# ---- corner selection: push just a strip of corners
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(3, 1, 1)))
	w.commit()
	var row3 := CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(3, 1, 1))
	w.begin()
	for i in 4:
		w.push_corner_quads(row3, [0, 1, 1, 4], 1)              # z 0..1 m, x 1..2 m: the corner lines at x = 1 m and 2 m (a top face's axes are z, x)
	w.commit()
	var c0: PackedByteArray = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var c1: PackedByteArray = w.leaves[Vector4i(8, 0, 0, 0)][0]
	var c2: PackedByteArray = w.leaves[Vector4i(16, 0, 0, 0)][0]
	check("corner selection: the middle cube's top sinks, its neighbours tilt into it",
		CubeWorld.corner(c1, 2).y == 4 and CubeWorld.corner(c1, 3).y == 4 and CubeWorld.corner(c0, 2).y == 8 and CubeWorld.corner(c0, 3).y == 4
		and CubeWorld.corner(c2, 2).y == 4 and CubeWorld.corner(c2, 3).y == 8)

	# ---- corner selection only shapes: no new cubes, only the selected ones, back up to the side and no further
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(3, 1, 1)))
	w.commit()
	var just_mid := CubeWorld.make_sel(Vector3i(8, 0, 0), p, 3)
	w.begin()
	for i in 4:
		w.push_corner_quads(just_mid, [0, 1, 0, 5], 1)           # a rectangle wider than the one cube selected
	w.commit()
	var m1: PackedByteArray = w.leaves[Vector4i(8, 0, 0, 0)][0]
	var n0: PackedByteArray = w.leaves[Vector4i(0, 0, 0, 0)][0]
	var n2: PackedByteArray = w.leaves[Vector4i(16, 0, 0, 0)][0]
	check("corner selection shapes only the selected cube (neighbours untouched)", CubeWorld.corner(m1, 2).y == 4 and CubeWorld.corner(m1, 3).y == 4
		and n0 == CubeWorld.FULL and n2 == CubeWorld.FULL)
	w.begin()
	for i in 6:
		w.push_corner_quads(just_mid, [0, 1, 0, 5], -1)          # pull: back up to the cube's top, then nothing
	w.commit()
	check("pulling corners back stops at the cube's own side, and adds nothing", w.leaves[Vector4i(8, 0, 0, 0)][0] == CubeWorld.FULL
		and w.count() == 3)
	var with_gap := CubeWorld.make_sel(Vector3i(16, 0, 0), p, 3, Vector3i(3, 1, 1))   # one cube, then two empty cells
	w.begin()
	for i in 5:
		w.push_corner_quads(with_gap, [0, 1, 4, 9], -1)
	w.commit()
	check("corner pulls never create cubes (empty cells stay empty)", w.count() == 3 and not w.leaves.has(Vector4i(24, 0, 0, 0))
		and not w.leaves.has(Vector4i(16, 8, 0, 0)))
	# two cubes at different heights in one selection: each column's top cube is shaped
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(2, 1, 1)))
	w.pull(CubeWorld.make_sel(Vector3i(8, 0, 0), p, 3))       # a second layer on the right one
	w.commit()
	var tall := CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(2, 2, 1))
	w.begin()
	for i in 2:
		w.push_corner_quads(tall, [0, 1, 0, 3], 1)
	w.commit()
	check("cubes at different heights: each column's top cube is shaped", CubeWorld.corner(w.leaves[Vector4i(0, 0, 0, 0)][0], 2).y == 6
		and CubeWorld.corner(w.leaves[Vector4i(8, 8, 0, 0)][0], 3).y == 6 and w.leaves[Vector4i(8, 0, 0, 0)][0] == CubeWorld.FULL)

	# ---- heightmap: raise a hill in a flat 9 x 9 floor, then smooth it
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(-32, -8, -32), p, 3, Vector3i(9, 1, 9)))
	w.commit()
	var round_brush: Array = CubeWorld.BRUSHES[2][1]
	w.begin()
	for i in 6:
		w.hmap_edit(Vector3i(8, 0, 8), 7, p, round_brush, -1)       # raise (wheel towards you)
	w.commit()
	var peak_k = w.leaf_at(Vector3(8, 20, 8) + Vector3(-1, 0, -1))
	var top_y := 0.0
	for k in w.leaves:
		for n in 8:
			top_y = maxf(top_y, k.y + CubeWorld.corner(w.leaves[k][0], n).y * CubeWorld.size_of(k.w) / 8.0)
	check("heightmap: the brush raises a hill (3 x 6 steps of 1/8 m at its top)", absf(top_y - (8.0 + 18.0)) < 0.5, "(top %.1f ticks)" % top_y)
	var all_valid := true
	for k in w.leaves:
		all_valid = all_valid and CubeWorld.is_valid_shape(w.leaves[k][0])
	check("...every cube of it still valid", all_valid)
	w.begin()
	for i in 4:
		w.hmap_edit(Vector3i(8, 0, 8), 20, p, [], 1)              # smooth
	w.commit()
	var top2 := 0.0
	for k in w.leaves:
		for n in 8:
			top2 = maxf(top2, k.y + CubeWorld.corner(w.leaves[k][0], n).y * CubeWorld.size_of(k.w) / 8.0)
	check("smooth brush flattens the peak", top2 < top_y - 1.0, "(%.1f -> %.1f ticks)" % [top_y, top2])
	w.begin()
	for i in 3:
		w.hmap_edit(Vector3i(-16, 0, -16), 7, p, CubeWorld.BRUSHES[0][1], 1)   # dig a point down
	w.commit()
	var dug = w.leaf_at(Vector3(-16.5, 4, -16.5))
	check("heightmap lowers too", dug != null and CubeWorld.corner(w.leaves[dug][0], 7).y < 8)

	# ---- the reported bug: a bevelled 4 m cube, then small edits on its top (no spikes, the shape kept)
	var bev := CubeWorld.FULL.duplicate()
	for n in [1, 3, 5, 7]:                                # the +X side's corners pushed in: a slope down that side
		bev[n * 3] = 5
	bev[3 * 3 + 1] = 6                                    # and two top corners dropped: a bevelled edge
	bev[7 * 3 + 1] = 6
	check("(the test cube is a valid bevelled shape)", CubeWorld.is_valid_shape(bev))
	for mode in ["push", "heightmap"]:
		w.clear()
		w.set_cell(Vector3i.ZERO, 2, bev, CubeWorld.blank_tex())        # 4 m = 32 ticks
		var ref := CubeWorld.new()
		ref.set_cell(Vector3i.ZERO, 2, bev, CubeWorld.blank_tex())
		w.begin()
		if mode == "push":
			w.push(CubeWorld.make_sel(Vector3i(8, 31, 8), -3, 3))     # one 0.125 m cube out of the top (like the report)
		else:
			for i in 2:
				w.hmap_edit(Vector3i(12, 0, 12), 31, -3, CubeWorld.BRUSHES[2][1], 1)
		w.commit()
		var all_ok := true
		var outside := 0.0
		for k in w.leaves:
			all_ok = all_ok and CubeWorld.is_valid_shape(w.leaves[k][0])
			for q in w.cube_points(k):
				var tq: Vector3 = q / CubeWorld.TICK
				# how far any corner pokes out of the original shape (ticks)
				var lp := tq / 32.0 * 8.0
				for pl in CubeWorld.solid_planes(bev):
					outside = maxf(outside, ((pl[0] as Vector3).dot(lp) - float(pl[1])) * 4.0)
		var kept := 0
		var n_total := 0
		for x in 16:
			for y in 16:
				for z in 16:
					var pt := Vector3(x * 2 + 1, y * 2 + 1, z * 2 + 1)
					if pt.y > 27 and pt.x > 4 and pt.x < 20 and pt.z > 4 and pt.z < 20:
						continue                                          # the edited spot itself
					n_total += 1
					if world_solid_at(w, pt) == world_solid_at(ref, pt):
						kept += 1
		check("bevelled cube, %s on top: every cube valid, nothing pokes out" % mode, all_ok and outside < 0.6,
			"(pokes out %.2f ticks)" % outside)
		check("...and the rest of its shape is kept", float(kept) / n_total > 0.97, "(%d / %d samples)" % [kept, n_total])

	# ---- blend painting
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3, Vector3i(4, 1, 4)), "Bricks104")
	w.set_slot_param(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(4, 1, 4)), false, func(d: Dictionary) -> Dictionary:
		d["l"] = "Grass004"
		return d)
	w.commit()
	w.begin()
	var painted := w.paint_blend(Vector3(16, 8, 16), 12.0, 2)
	w.commit()
	var mid_k = w.leaf_at(Vector3(15, 4, 15))
	var bl: PackedByteArray = CubeWorld._blend_of(w.leaves[mid_k]) if mid_k != null else PackedByteArray()
	check("blend paint: the layer is painted in around the brush", painted > 0 and not bl.is_empty() and Array(bl).max() > 200,
		"(%d cubes, %s)" % [painted, bl])
	var pm: Array = w.chunk_mesh(Vector3i.ZERO)
	var shader_surface := false
	for i in (pm[0] as ArrayMesh).get_surface_count():
		shader_surface = shader_surface or (pm[0] as ArrayMesh).surface_get_material(i) is ShaderMaterial
	check("...drawn with the blending shader", shader_surface)
	var w4 := CubeWorld.from_dict(w.to_dict())
	check("blend paint is saved", CubeWorld._blend_of(w4.leaves[mid_k]) == bl)

	# ---- moving cubes (editcut)
	w.clear()
	w.begin()
	w.pull(CubeWorld.make_sel(Vector3i(0, -8, 0), p, 3))
	w.set_material(CubeWorld.make_sel(Vector3i(0, 8, 0), p, 3), "water")
	w.commit()
	w.begin()
	var mv := w.move_cubes(CubeWorld.make_sel(Vector3i(0, 0, 0), p, 3, Vector3i(1, 2, 1)), Vector3i(24, 0, 0))
	w.commit()
	check("Shift-drag: cubes and their water move together", w.leaves.has(Vector4i(24, 0, 0, 0)) and not w.leaves.has(Vector4i(0, 0, 0, 0))
		and w.mat_at(Vector3(28, 12, 4)) == "water" and w.mat_at(Vector3(4, 12, 4)) == "" and mv["o"] == Vector3i(24, 0, 0))

	# ---- 0.6.0 save format still loads
	var old := {"v": 1, "palette": [""], "count": 1, "data": ""}
	var buf := StreamPeerBuffer.new()
	buf.put_32(0)
	buf.put_32(0)
	buf.put_32(0)
	buf.put_8(0)
	buf.put_data(CubeWorld.FULL)
	for j in 6:
		buf.put_u16(0)
	old["data"] = Marshalls.raw_to_base64(buf.data_array)
	var w5 := CubeWorld.from_dict(old)
	check("a 0.6.0 map's cubes still load", w5.count() == 1 and w5.leaves[Vector4i(0, 0, 0, 0)][0] == CubeWorld.FULL)

	print("CUBES: ", "PASS" if ok else "FAIL")
	quit()
