extends SceneTree
## Fills (water, lava, glass...) are quick and one thing (0.19.0): a big fill takes no time and becomes a handful of
## big cells (it scanned every material cell for every cell filled: a 32,000-cell fill hung MALLET); what's drawn is
## exactly the outside of the filled shape, even where cells of different sizes meet; and no fill face is drawn
## against solid cubes, however small they are.
## Run: godot --path . --resolution 1280x720 -s res://tests/fill_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


## Area (m2) of everything drawn with this material's look, over the world's chunks.
func area_of(w: CubeWorld, mat: String) -> float:
	var look = CubeWorld.material_look(mat)
	var a := 0.0
	for ck in w.render_chunks():
		var m: ArrayMesh = w.chunk_mesh(ck)[0]
		for si in m.get_surface_count():
			if m.surface_get_material(si) != look:
				continue
			var v: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size(), 3):
				a += (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).length() * 0.5
	return a


func _run() -> void:
	# a big fill of small cells
	var w := CubeWorld.new()
	var t := Time.get_ticks_usec()
	w.begin()
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), -3, 3, Vector3i(32, 8, 32)), "glass")
	w.commit()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	print("  32 x 8 x 32 small glass cells: %.0f ms, %d cells after merging" % [ms, w.mats.size()])
	check("a 8,192-cell fill is quick", ms < 3000.0, "(%.0f ms)" % ms)
	check("...and becomes a handful of big cells", w.mats.size() <= 16, "(%d)" % w.mats.size())
	check("...that hold exactly the space filled", w.mat_at(Vector3(1, 1, 1)) == "glass" and w.mat_at(Vector3(31.5, 7.5, 31.5)) == "glass"
		and w.mat_at(Vector3(32.5, 1, 1)) == "" and w.mat_at(Vector3(1, 8.5, 1)) == "")
	check("its outside is all that's drawn (4 x 1 x 4 m: 48 m2)", absf(area_of(w, "glass") - 48.0) < 0.01, "(%.2f m2)" % area_of(w, "glass"))
	w.undo()
	check("undo takes the whole fill away", w.mats.is_empty())
	# an L shape: two fills, cells of different sizes meet
	w = CubeWorld.new()
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3, Vector3i(4, 2, 4)), "water")    # 4 x 2 x 4 m (merges)
	w.set_material(CubeWorld.make_sel(Vector3i(32, 0, 0), -1, 3, Vector3i(3, 4, 2)), "water")  # 1.5 x 2 x 1 m beside it
	# (the big box: top 16, four sides 2 x 8 + 2 x 8 minus the 2 x 1 patch the small one covers; the small box: top
	#  1.5, two long sides 2 x 3, the far end 2; water has no undersides)
	var expect := 16.0 + 2.0 * (4.0 * 2.0) + 2.0 * (4.0 * 2.0) - 2.0 * 1.0 + 1.5 * 1.0 + 2.0 * (1.5 * 2.0) + 1.0 * 2.0
	check("an L of water with cells of different sizes: just its outside", absf(area_of(w, "water") - expect) < 0.01,
		"(%.2f m2, expected %.2f)" % [area_of(w, "water"), expect])
	# glass beside a block made of small solid cubes: no face against them
	w = CubeWorld.new()
	for i in 8:
		w.set_cell(Vector3i(8 + (i & 1) * 4, ((i >> 1) & 1) * 4, ((i >> 2) & 1) * 4), -1, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3), "glass")
	check("glass beside a block of small cubes: no face against them (5 m2)", absf(area_of(w, "glass") - 5.0) < 0.01, "(%.2f m2)" % area_of(w, "glass"))
	# glass poured over blocks (0.19.3): nothing drawn on a full block's faces, only over a pushed-in one's dip
	w = CubeWorld.new()
	var dip := CubeWorld.FULL.duplicate()
	for n in 8:
		if (n >> 1) & 1:
			dip[n * 3 + 1] = 4                            # (its top pushed halfway down)
	w.set_cell(Vector3i(0, 0, 0), 0, CubeWorld.FULL.duplicate(), CubeWorld.blank_tex())
	w.set_cell(Vector3i(8, 0, 0), 0, dip, CubeWorld.blank_tex())
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3, Vector3i(2, 1, 1)), "glass")
	var ga := area_of(w, "glass")
	# (only the 1 x 1 top over the dip, and the dip's open sides: 3 half-meter strips of 1 x 0.5)
	check("glass over a full block draws nothing on it; over a dip, only the open part", absf(ga - (1.0 + 3.0 * 0.5)) < 0.01, "(%.2f m2)" % ga)
	# glass beside a pushed-in block: only the part of the shared side the block leaves open
	w = CubeWorld.new()
	w.set_cell(Vector3i(8, 0, 0), 0, dip, CubeWorld.blank_tex())
	w.set_material(CubeWorld.make_sel(Vector3i(0, 0, 0), 0, 3), "glass")
	ga = area_of(w, "glass")
	check("glass beside a pushed-in block: just the open half of the shared side", absf(ga - (5.0 + 0.5)) < 0.01, "(%.2f m2)" % ga)
	print("fill_test: ", "PASS" if ok else "FAIL")
	quit()
