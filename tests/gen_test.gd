extends SceneTree
## Ramp generators: each shape, generated off the starter ramp, must be landed on by that ramp's jump (full and 85%
## speed). Then a showcase course start -> spiral -> S-curve -> rollers -> corkscrew -> finish is chained with
## "continue from the selected ramp", every jump checked, and exported as sf_generators.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/gen_test.gd -- <out> [maps_dir]

var ed
var out := ""
var ok := true


func _init() -> void:
	call_deferred("_run")


func shot(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")


func settle() -> void:
	for i in 3:
		await physics_frame
	ed._update_arcs()


func arc_of(r: RampNode) -> Dictionary:
	for a in ed._arcs:
		if a["ramp"] == r:
			return a
	return {}


## The source ramp's jump must land on `target` for both the full-speed and the 85% rider.
func check_jump(what: String, src: RampNode, target) -> bool:
	var a := arc_of(src)
	if a.is_empty():
		print("  %s: no arc" % what)
		return false
	var good := true
	var labels := []
	for run in a["runs"]:
		labels.append(run["label"])
		good = good and JumpCheck.good(run["outcome"]) and run["target"] == target
	print("  %s: exit %d u/s | full: %s | 85%%: %s%s" % [what, roundi(a["speed"] * JumpCheck.U), labels[0], labels[1], "" if good else "   <-- FAIL"])
	return good


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var src: RampNode = ed.ramps_root.get_child(0)
	for e in ed.entities_root.get_children():
		if e.kind == "finish":
			e.position = Vector3(2000, -100, 0)          # out of the way: the jump should land on the new ramp

	# --- each shape off the starter ramp, then cancel
	for shape in RampGenerator.SHAPE_ORDER:
		ed._select(src)
		var undo_before: int = ed._undo.size()
		ed._generate_clicked()
		ed._gen_set_shape(shape)
		await settle()
		var g: RampNode = ed._gen_ramp
		ok = check_jump(shape, src, g) and ok
		ok = ok and ed._gen_props.visible and g.points.size() >= 4
		if shape == "corkscrew":
			ok = ok and g.freeform and absf(g.twist - 35.0) < 0.01
		await shot("gen_" + shape)
		ed._gen_cancel()
		var clean: bool = ed.ramps_root.get_child_count() == 1 and ed._undo.size() == undo_before and ed.selected == src
		print("  cancel leaves the map and undo history as they were: ", clean)
		ok = ok and clean

	# --- showcase course
	ed._load_dict({})
	var start := EntityNode.create("start")
	start.position = Vector3(0, 520, 0)
	ed.entities_root.add_child(start)
	var first: RampNode = ed._make_ramp(Vector3(0, 510, -20), Vector3(0, 470, -150))
	first.look = "ceramic"
	first.color = Color("2b4ea3")
	first.rebuild()
	var plan := [["spiral", {"radius": 70.0, "turns": 0.6, "drop": 70.0, "hand": 1.0}, 1.0],
		["s_curve", {"length": 240.0, "bends": 2.0, "sway": 25.0, "drop": 70.0}, -1.0],
		["rollers", {"length": 260.0, "waves": 3.0, "wave_height": 6.0, "drop": 80.0}, 1.0],
		["corkscrew", {"length": 220.0, "twist": 35.0, "turn": 30.0, "drop": 60.0}, 1.0]]
	var prev := first
	var created := [first]
	for step in plan:
		ed._select(prev)
		ed._generate_clicked()
		ed._gen_values[step[0]] = step[1]
		ed._gen_side = step[2]
		ed._gen_set_shape(step[0])
		var g: RampNode = ed._gen_ramp
		ed._gen_create()
		ok = ok and ed._gen_ramp == null and ed.selected == g and not ed._gen_props.visible
		created.append(g)
		prev = g
	# finish where the last jump comes down
	var ex := JumpCheck.exit_of(prev.ridge)
	var ref: Array = ed._speed_reference(prev)
	var v: Vector3 = ex[1] * JumpCheck.speed_at(ref[0], ref[1], ex[0].y)
	var t := 2.4
	var fin := EntityNode.create("finish")
	fin.size = Vector3(60, 2, 60)
	fin.position = ex[0] + v * t * 0.85 + Vector3.DOWN * 0.5 * JumpCheck.G * t * t
	ed.entities_root.add_child(fin)
	ed._select(null)
	await settle()
	ed.show_all_arcs = true
	await settle()
	for i in created.size():
		var target = created[i + 1] if i + 1 < created.size() else fin
		ok = check_jump("course ramp %d (%s)" % [i, "first" if i == 0 else plan[i - 1][0]], created[i], target) and ok
	var problems: PackedStringArray = SurfsUpExporter.check(ed._map_dict())
	print("export check: ", problems)
	ok = ok and problems.is_empty()
	# saved twist survives a round trip
	var d: Dictionary = ed._map_dict()
	ok = ok and absf(float(d["ramps"][4]["twist"]) - 35.0) < 0.01
	ed.show_all_arcs = false
	ed._toggle_views()
	var cam := ed.panes[0].camera as OrbitCamera
	ed.frame_course(cam, 16.0 / 9.0)
	await shot("gen_course")
	ed._toggle_views()
	if args.size() > 1:
		var f := FileAccess.open(out + "/sf_generators.sfmap", FileAccess.WRITE)
		f.store_string(JSON.stringify(d, "  "))
		f.close()
		print("export: '", SurfsUpExporter.export_pack(d, "sf_generators", args[1]), "'")
	print("GENERATORS: ", "PASS" if ok else "FAIL")
	quit()
