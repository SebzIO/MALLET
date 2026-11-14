extends SceneTree
## Build mode's Sauerbraten-style selection moving (requested by a Sauerbraten player): right-drag inside the selection
## moves the box (a right click still extends / turns it), Shift + right-drag leaves a copy of its cubes where it's let
## go, a red box shows where V will paste (growing away from the face you aim at, whichever way it faces), and a copy
## pasted after making the grid smaller keeps its exact shape.
## Run: godot --path . --resolution 1600x900 -s res://tests/selmove_test.gd -- <out>

var ok := true
var ed
var bm: BuildMode


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-62s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func key(k: Key, pressed := true) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = pressed
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func tap(k: Key) -> void:
	key(k)
	key(k, false)
	await frames(1)


func wheel(dir: int, times := 1) -> void:
	for i in times:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		Input.parse_input_event(e)
		await frames(2)


func held_wheel(k: Key, dir: int, times := 1) -> void:
	key(k)
	await wheel(dir, times)
	key(k, false)


func click(button: MouseButton, pressed: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame
	await physics_frame


func look(from: Vector3, at: Vector3) -> void:
	bm.cam.global_position = from
	var f := (at - from).normalized()
	bm.yaw = atan2(-f.x, -f.z)
	bm.pitch = asin(clampf(f.y, -0.9999, 0.9999))
	bm._apply_cam()



## Every tick cell of a box: is it solid there? (the cube's real shape, sampled)
func shape(w: CubeWorld, lo: Vector3i, size: Vector3i) -> Array:
	var out := []
	for x in range(lo.x, lo.x + size.x):
		for y in range(lo.y, lo.y + size.y):
			for z in range(lo.z, lo.z + size.z):
				var k = w.leaf_at(Vector3(x, y, z) + Vector3.ONE * 0.5)
				var solid := false
				if k != null:
					var u: Vector3 = (Vector3(x, y, z) + Vector3.ONE * 0.5 - Vector3(k.x, k.y, k.z)) / CubeWorld.size_of(k.w) * 8.0
					solid = true
					for pl in CubeWorld.leaf_planes(w.leaves[k]):
						if (pl[0] as Vector3).dot(u) - float(pl[1]) > 1e-4:
							solid = false
				out.append(solid)
	return out


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	bm = ed.build
	await tap(KEY_E)
	# a 6 x 6 m floor of 1 m cubes (top at y 0), a 1 m bump at x 1 on it
	var cm := CubeModelNode.new()
	ed.cube_models_root.add_child(cm)
	var w: CubeWorld = cm.world
	for x in 6:
		for z in 6:
			w.set_cell(Vector3i(x * 8, -8, z * 8), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	w.set_cell(Vector3i(8, 0, 8), 0, CubeWorld.FULL, CubeWorld.blank_tex("Bricks104"))
	bm.model = cm
	bm.grid_p = 0
	await frames(2)

	# select the bump's top, then right-drag inside it to 3 m further along x
	bm.sel = CubeWorld.make_sel(Vector3i(8, 0, 8), 0, 3)
	bm.sel["model"] = cm
	look(Vector3(1.5, 6, 1.5), Vector3(1.5, 1, 1.5))
	await frames(3)
	click(MOUSE_BUTTON_RIGHT, true)
	await frames(1)
	check("right-drag inside the selection starts moving it", bm._drag == "selmove")
	look(Vector3(1.5, 6, 1.5), Vector3(4.5, 1, 1.5))
	await frames(3)
	click(MOUSE_BUTTON_RIGHT, false)
	await frames(1)
	check("...the box moves with the aim (3 m along x), the cubes stay", bm.sel["o"] == Vector3i(32, 0, 8)
		and w.leaf_at(Vector3(12, 4, 12)) != null and w.leaf_at(Vector3(36, 4, 12)) == null, "(o %s)" % bm.sel["o"])
	# a right click without dragging still acts as before (inside the selection: turns it to that face)
	bm.sel = CubeWorld.make_sel(Vector3i(32, -8, 8), 0, 3)                  # a floor cube's top, under the aim
	bm.sel["model"] = cm
	look(Vector3(4.5, 6, 1.5), Vector3(4.5, -0.5, 1.5))
	await frames(3)
	click(MOUSE_BUTTON_RIGHT, true)
	await frames(1)
	click(MOUSE_BUTTON_RIGHT, false)
	await frames(1)
	check("a right click that doesn't move still acts as a right click", bm._drag == "" and bm.sel["o"] == Vector3i(32, -8, 8)
		and bm.sel["s"] == Vector3i.ONE, "(%s)" % bm.sel)

	# Shift + right-drag: back over the bump, then drag with Shift to 2 m along z: a copy is left there
	bm.sel = CubeWorld.make_sel(Vector3i(8, 0, 8), 0, 3)
	bm.sel["model"] = cm
	look(Vector3(1.5, 6, 1.5), Vector3(1.5, 1, 1.5))
	await frames(3)
	click(MOUSE_BUTTON_RIGHT, true)
	await frames(1)
	look(Vector3(1.5, 6, 1.5), Vector3(1.5, 1, 3.5))
	await frames(3)
	key(KEY_SHIFT)
	click(MOUSE_BUTTON_RIGHT, false)
	key(KEY_SHIFT, false)
	await frames(2)
	var copied = w.leaf_at(Vector3(12, 4, 28))
	check("Shift + right-drag leaves a copy where it's let go (and keeps the original)", copied != null
		and w.leaf_at(Vector3(12, 4, 12)) != null and (w.leaves[copied][1] as PackedStringArray)[0] == "Bricks104")

	# the red paste box: after C, aiming at the floor with no selection, it sits on the floor in front of the face
	bm.sel = CubeWorld.make_sel(Vector3i(8, 0, 8), 0, 3)
	bm.sel["model"] = cm
	bm.copy()
	bm.sel = {}
	look(Vector3(4.5, 6, 4.5), Vector3(4.5, -0.5, 4.5))
	await frames(3)
	var pd: Dictionary = bm._paste_dest()
	check("the red paste box: on the floor you aim at", not pd.is_empty() and pd["o"] == Vector3i(32, 0, 32), "(%s)" % pd)
	# aiming at a wall facing -x: the copy grows back from it (not into it)
	w.set_cell(Vector3i(40, 0, 0), 0, CubeWorld.FULL, CubeWorld.blank_tex())
	var cl: Dictionary = bm.clip
	bm.clip = {"s": Vector3i(24, 8, 8), "p": 0, "cubes": cl["cubes"], "mats": []}    # a 3 m long copy
	look(Vector3(2.5, 0.5, 0.5), Vector3(6, 0.5, 0.5))
	await frames(3)
	pd = bm._paste_dest()
	check("facing -x, the paste box grows away from the wall", not pd.is_empty() and pd["orient"] == 0
		and pd["o"].x + 24 <= 40 and pd["o"].x + 24 >= 32, "(%s)" % pd)
	bm.clip = cl

	# copy a sloped cube at 1 m, make the grid 0.5 m, paste: exactly the same shape
	var slope := CubeWorld.FULL.duplicate()
	for n in [2, 6]:                                    # the top's -x corners down to 2 of 8: a slope
		slope[n * 3 + 1] = 2
	w.set_cell(Vector3i(40, 0, 32), 0, slope, CubeWorld.blank_tex("Concrete034"))
	bm.sel = CubeWorld.make_sel(Vector3i(40, 0, 32), 0, 3)
	bm.sel["model"] = cm
	bm.copy()
	bm.grid_p = -1
	bm.sel = CubeWorld.make_sel(Vector3i(16, 0, 32), -1, 3)
	bm.sel["model"] = cm
	bm.paste()
	await frames(1)
	var a := shape(w, Vector3i(40, 0, 32), Vector3i(8, 8, 8))
	var b := shape(w, Vector3i(16, 0, 32), Vector3i(8, 8, 8))
	check("a copy pasted at a smaller grid keeps its exact shape", a == b and a.count(true) > 0 and a.count(false) > 0,
		"(%d / %d solid)" % [a.count(true), b.count(true)])
	var pieces := w.leaves_in(Vector3i(16, 0, 32), Vector3i(8, 8, 8))
	check("...made of cubes at the new 0.5 m grid", not pieces.is_empty() and pieces.all(func(k): return k.w <= -1), "(%d pieces)" % pieces.size())
	print("SELMOVE: ", "PASS" if ok else "FAIL")
	quit()
