extends SceneTree
## Ramp point alignment (0.27.3): the line between two neighboring points counts as aligned in a view when it runs
## at an exact 45° step in that view's plane (level, upright, diagonal - so also when the points share an X or a Z);
## aligned lines are drawn green and their points get a green ring, updated as points move.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/ramp_align_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func pane_of(ed_, kind: int) -> ViewPane:
	for p in ed_.panes:
		if p.kind == kind:
			return p
	return null


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	var E = ed.get_script()
	check("level, upright and diagonal lines are aligned", E.is_aligned(Vector2(0, 0), Vector2(50, 0)) and E.is_aligned(Vector2(0, 0), Vector2(0, -30))
		and E.is_aligned(Vector2(0, 0), Vector2(-40, 40)) and E.is_aligned(Vector2(0, 0), Vector2(25, -25)))
	check("...a line a little off isn't", not E.is_aligned(Vector2(0, 0), Vector2(100, 3)) and not E.is_aligned(Vector2(0, 0), Vector2(40, 41)))
	check("...nor two points on top of each other", not E.is_aligned(Vector2(5, 5), Vector2(5, 5)))
	var top := pane_of(ed, ViewPane.Kind.TOP)
	var front := pane_of(ed, ViewPane.Kind.FRONT)
	var side := pane_of(ed, ViewPane.Kind.SIDE)
	# the user's second screenshot: a 45° diagonal, then a run along the same Z
	var pts := PackedVector3Array([Vector3(100, 60, -100), Vector3(0, 50, 0), Vector3(-200, 40, 0)])
	check("top view: the diagonal and the run along Z are both aligned", E.aligned_pairs(pts, top) == [true, true], str(E.aligned_pairs(pts, top)))
	check("front view (Z / Y): only the pair sharing a Z (upright here)", E.aligned_pairs(pts, front) == [false, true], str(E.aligned_pairs(pts, front)))
	check("side view (X / Y): neither (the slopes aren't 45°)", E.aligned_pairs(pts, side) == [false, false], str(E.aligned_pairs(pts, side)))
	var off := PackedVector3Array([Vector3(100, 60, -200), Vector3(0, 50, -103), Vector3(-200, 40, -95)])
	check("the first screenshot's uneven points aren't", E.aligned_pairs(off, top) == [false, false], str(E.aligned_pairs(off, top)))
	# live: moving a point changes it
	ed._load_dict({"ramps": [{"points": [[100, 60, -100], [0, 50, 0], [-200, 40, 3]]}]})
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	check("a ramp's points as they are: the last line is off", E.aligned_pairs(r.points, top) == [true, false])
	var p := r.points
	p[2] = Vector3(-200, 40, 0)
	r.points = p
	check("...moved onto the line, it's aligned", E.aligned_pairs(r.points, top) == [true, true])
	print("ramp_align_test: ", "PASS" if ok else "FAIL")
	quit()
