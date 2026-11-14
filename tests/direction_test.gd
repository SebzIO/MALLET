extends SceneTree
## Direction of travel: Flip reverses the points but leaves the ramp exactly where it was (same surface, half ramps
## keep their face on the same side), undo restores the original order, and the
## arrows are an editor overlay only. Screenshots: direction_*.png
## Run: godot --path . --resolution 1600x900 -s res://tests/direction_test.gd -- <out>

var ok := true


func _init() -> void:
	call_deferred("_run")


func shot(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


## Largest distance from any point of `a` to the nearest point of `b` (the two surfaces must coincide).
func gap(a: Array, b: Array) -> float:
	var worst := 0.0
	for ra in a:
		for p in ra:
			var best := INF
			for rb in b:
				for q in rb:
					best = minf(best, p.distance_squared_to(q))
			worst = maxf(worst, sqrt(best))
	return worst


func every(rings: Array, step: int) -> Array:
	var out := []
	for i in range(0, rings.size(), step):
		out.append(rings[i])
	out.append(rings[rings.size() - 1])
	return out


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	r.points = PackedVector3Array([Vector3(-60, 120, 0), Vector3(-10, 110, -30), Vector3(40, 100, 10), Vector3(90, 90, -20)])
	ed._select(r)
	ed._edit_prop("style", "half_left")
	ed._edit_prop("solid", true)
	ed._toggle_views()
	await shot(out + "/direction_before.png")
	var before_rings: Array = r.geometry["rings"].duplicate()
	var before_pts := r.points.duplicate()
	var before_first := r.points[0]

	ed._flip_clicked()
	var after_rings: Array = r.geometry["rings"]
	var g := gap(every(before_rings, 10), after_rings)
	var g2 := gap(every(after_rings, 10), before_rings)
	var same_surface := g < 0.05 and g2 < 0.05
	var reversed: bool = r.points[0] == before_pts[before_pts.size() - 1] and r.points[r.points.size() - 1] == before_first
	print("flip: points reversed %s, style now %s, surface moved by at most %.3f m  %s" % [reversed, r.style, maxf(g, g2),
		"OK" if same_surface and reversed and r.style == "half_right" else "FAIL"])
	ok = ok and same_surface and reversed and r.style == "half_right"
	await shot(out + "/direction_after.png")

	ed.undo()
	r = ed.ramps_root.get_child(0)
	var undone: bool = r.points == before_pts and r.style == "half_left"
	print("undo restores the original direction: ", undone)
	ok = ok and undone

	# Freeform faces swap sides too
	ed._select(r)
	ed._edit_prop("style", "v")
	ed._edit_prop("freeform", true)
	ed._edit_prop("angle_right", 70.0)
	var rings_ff: Array = r.geometry["rings"].duplicate()
	ed._flip_clicked()
	var gff := maxf(gap(every(rings_ff, 10), r.geometry["rings"]), gap(every(r.geometry["rings"], 10), rings_ff))
	print("flip with uneven Freeform faces: left %.0f / right %.0f, surface moved by at most %.3f m  %s" % [r.angle, r.angle_right, gff,
		"OK" if gff < 0.05 and r.angle == 70.0 else "FAIL"])
	ok = ok and gff < 0.05 and r.angle == 70.0

	# arrows are overlay only: the exported scene has nothing new in it
	var scene: Node = SurfsUpExporter.build_scene(ed._map_dict(), "sf_dir_test")
	var names := []
	for c in scene.get_children():
		names.append(c.name)
	print("exported top-level nodes: ", names)
	ok = ok and not str(names).to_lower().contains("arrow")
	scene.free()
	print("DIRECTION: ", "PASS" if ok else "FAIL")
	quit()
