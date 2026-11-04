extends SceneTree
## Builds the starter templates in res://templates/ and proves every jump in them with the jump checker
## (full speed and 85% speed must both land somewhere good). Run:
##   godot --path D:/SurfForge --resolution 1280x720 -s res://tools/make_templates.gd
## Ramps are placed where SurfsUp physics says riders land: speed from the drop since the plate (from 400 u/s),
## gravity 20.32, the same model the jump checker uses (matched the real controller within 1 m).

const ANGLE := 56.0                 ## face angle of every template ramp (the editor default)
const FACE := 10.5                  ## face length
const AIM := 0.85                    ## the speed (fraction of ideal) each jump is aimed for
var ed
var failures := 0


func _init() -> void:
	call_deferred("_run")


## Horizontal unit vector for a yaw in degrees (yaw 0 = -Z, the way a start platform's arrow points).
func dir(yaw: float) -> Vector3:
	var r := deg_to_rad(yaw)
	return Vector3(-sin(r), 0.0, -cos(r))


## Control points for a ramp starting at s heading `yaw`, `length` m long, dropping `drop`, turning `turn` degrees.
func ramp_points(s: Vector3, yaw: float, length: float, drop: float, turn: float) -> Array:
	var pts := [s]
	var p := s
	var n := 3
	for i in n:
		var y := yaw + turn * (float(i) + 0.5) / n
		p = p + dir(y) * (length / n) - Vector3(0, drop / n, 0)
		pts.append(p)
	return pts


func ramp(pts: Array, color: String, look := "ceramic") -> Dictionary:
	var out := []
	for p in pts:
		out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
	return {"points": out, "angle": ANGLE, "face_length": FACE, "detail": 1.0, "color": color, "look": look}


## Where the rider leaves a ramp: [point, unit direction]. Mirrors JumpCheck.exit_of on the sampled ridge.
func exit_of(pts: Array) -> Array:
	var ridge := RampShape.sample_path(PackedVector3Array(pts), 1.0)
	return JumpCheck.exit_of(ridge)


## Ballistic point `t` seconds after leaving `p0` at velocity `v0`.
func arc_at(p0: Vector3, v0: Vector3, t: float) -> Vector3:
	return p0 + v0 * t + Vector3.DOWN * 0.5 * JumpCheck.G * t * t


## The next ramp's ridge start, placed so the rider's arc meets the start of its face `gap` metres on.
func next_start(ex: Array, speed: float, gap: float, side: float) -> Vector3:
	return JumpCheck.next_ramp_start(ex[0], ex[1], speed, gap, side, tan(deg_to_rad(ANGLE)))


## A course of ramps from a plate. Returns [ramps, last exit, speed at the last exit].
func course(plate_pos: Vector3, plate_yaw: float, specs: Array, colors: Array, looks: Array) -> Array:
	var y0 := plate_pos.y
	var out := []
	# first ramp: just past the plate's front edge and a little lower, like the starter map
	var s := plate_pos + dir(plate_yaw) * 24.0 + Vector3(0, -8.0, 0)
	var yaw := plate_yaw
	var ex := []
	for i in specs.size():
		var sp: Array = specs[i]                    # [length, drop, turn, gap to the next ramp, side]
		var pts := ramp_points(s, yaw, sp[0], sp[1], sp[2])
		out.append(ramp(pts, colors[i % colors.size()], looks[i % looks.size()]))
		ex = exit_of(pts)
		if i + 1 < specs.size():
			# aim so a rider at 85% speed lands at the start of the next ramp; that ramp begins along the flight
			# path, so faster riders simply land further down it instead of missing it
			var speed := JumpCheck.speed_at(y0, JumpCheck.START_SPEED, ex[0].y)
			s = next_start(ex, speed * AIM, sp[3], sp[4])
			yaw = rad_to_deg(atan2(-ex[1].x, -ex[1].z))
	return [out, ex, JumpCheck.speed_at(y0, JumpCheck.START_SPEED, ex[0].y)]


## A platform the last arc drops into, `drop` metres below the exit (its zone catches the arc 5 m above the slab).
func landing(ex: Array, speed: float, drop: float) -> Vector3:
	var v: Vector3 = ex[1] * speed
	# time to fall `drop` from the exit along the arc
	var a := 0.5 * JumpCheck.G
	var t := (v.y + sqrt(v.y * v.y + 4.0 * a * drop)) / (2.0 * a)
	return arc_at(ex[0], v, t) - Vector3(0, 5.0, 0)


func template_first_surf() -> Dictionary:
	var start := Vector3(0, 400, 0)
	var c := course(start, 0.0, [[150, 40, 20, 40, 1], [140, 34, -30, 42, -1], [150, 34, 35, 44, 1], [140, 30, -25, 46, -1],
		[160, 34, 15, 0, 0]], ["2b4ea3", "a33b2b", "2b8a4e", "7a3ba3", "c48a1c"], ["ceramic"])
	var fin := landing(c[1], c[2], 28.0)
	return {"format": "surfforge-map", "version": 2,
		"template": {"title": "First Surf", "description": "A classic linear surf: five glazed-ceramic ramps with gentle turns on a clear day. Every jump is makeable at 85% speed."},
		"environment": Look.preset_environment("day"), "ramps": c[0],
		"entities": [{"kind": "start", "position": v3(start), "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": v3(fin), "size": [44, 2, 44], "yaw": 0.0}]}


func template_three_stages() -> Dictionary:
	var ramps := []
	var ents := []
	var plates := [Vector3(0, 380, 0), Vector3(320, 380, -40), Vector3(640, 380, 0)]
	var looks := [["steel"], ["grid"], ["neon"]]
	var cols := [["c9ced8"], ["9ea8b8"], ["ff7a1a"]]
	for k in 3:
		var c := course(plates[k], 0.0, [[150, 40, -20, 40, -1], [150, 36, 25, 0, 0]], cols[k], looks[k])
		ramps += c[0]
		if k == 0:
			ents.append({"kind": "start", "position": v3(plates[k]), "size": [20, 2, 26], "yaw": 0.0})
		else:
			ents.append({"kind": "stage", "position": v3(plates[k]), "size": [24, 2, 24], "yaw": 0.0, "number": k + 1})
		var drop_to := landing(c[1], c[2], 22.0) + Vector3(0, 5.0, 0)
		if k < 2:
			ents.append({"kind": "teleport", "position": v3(drop_to), "size": [40, 30, 40], "yaw": 0.0, "number": k + 2, "keep_speed": false})
		else:
			ents.append({"kind": "finish", "position": v3(drop_to - Vector3(0, 5, 0)), "size": [44, 2, 44], "yaw": 0.0})
	return {"format": "surfforge-map", "version": 2,
		"template": {"title": "Three Stages", "description": "Three short stages joined by teleports, at sunset: falling off sends you back to your stage's plate, and the finish needs every stage."},
		"environment": Look.preset_environment("sunset"), "ramps": ramps, "entities": ents}


func template_aurora() -> Dictionary:
	var start := Vector3(0, 420, 0)
	var c := course(start, 0.0, [[160, 44, 30, 42, 1], [150, 36, -40, 44, -1], [170, 40, 35, 0, 0]],
		["26ff99", "1ae6ff", "d933e6"], ["aurora", "neon", "nebula"])
	var ramps: Array = c[0]
	var ex: Array = c[1]
	var speed: float = c[2]
	# a booster right at the last ramp's exit launches riders across a gap they could not make on their own
	var boost_dir: Vector3 = (ex[1] + Vector3(0, 0.35, 0)).normalized()
	var v: Vector3 = ex[1] * speed + boost_dir * (600.0 / JumpCheck.U)
	var boost_pos: Vector3 = ex[0] + ex[1] * 6.0
	var yaw_b := rad_to_deg(atan2(-boost_dir.x, -boost_dir.z))
	var pitch_b := rad_to_deg(asin(boost_dir.y))
	# final ramp where the boosted arc comes down, then the finish
	var vh := Vector2(v.x, v.z).length()
	var t := 160.0 / vh
	var land := arc_at(ex[0], v, t)
	var s := land + Vector3.UP.cross(ex[1]).normalized() * 3.0 + Vector3(0, 3.0 * tan(deg_to_rad(ANGLE)) - 0.6, 0)
	var yaw_last := rad_to_deg(atan2(-ex[1].x, -ex[1].z))
	var pts := ramp_points(s, yaw_last + 12.0, 170, 40, -30)
	ramps.append(ramp(pts, "26ff99", "aurora"))
	var ex2 := exit_of(pts)
	# energy after the boost: the rider is faster than the drop alone explains
	var e_boost: float = v.length_squared() / (2.0 * JumpCheck.G) + ex[0].y
	var speed2 := sqrt(maxf(2.0 * JumpCheck.G * (e_boost - ex2[0].y), 0.0))
	var fin := landing(ex2, speed2, 30.0)
	return {"format": "surfforge-map", "version": 2,
		"template": {"title": "Aurora Night", "description": "Under the northern lights: aurora, neon and nebula ramps, with a booster that throws you across the big gap."},
		"environment": Look.preset_environment("aurora"), "ramps": ramps,
		"entities": [{"kind": "start", "position": v3(start), "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "booster", "position": v3(boost_pos), "size": [24, 18, 14], "yaw": yaw_b, "pitch": pitch_b, "strength": 600.0, "mode": 0},
			{"kind": "finish", "position": v3(fin), "size": [44, 2, 44], "yaw": 0.0}],
		"_boost_check": {"exit": v3(ex[0]), "velocity": v3(v)}}


func template_blank() -> Dictionary:
	return {"format": "surfforge-map", "version": 2,
		"template": {"title": "Blank", "description": "Just a start and a finish. Press N to add your first ramp."},
		"environment": Look.preset_environment("day"), "ramps": [],
		"entities": [{"kind": "start", "position": [0, 200, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 100, -260], "size": [40, 2, 40], "yaw": 0.0}]}


func v3(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


## Load the map into the editor and check every ramp's jump at full and 85% speed.
func verify(name: String, map: Dictionary) -> void:
	var boost: Dictionary = map.get("_boost_check", {})
	map.erase("_boost_check")
	ed._load_dict(map)
	for i in 4:
		await physics_frame
	ed.show_all_arcs = true
	ed._update_arcs()
	var bad := 0
	for a in ed._arcs:
		var r: RampNode = a["ramp"]
		var idx: int = r.get_index()
		var line := "  ramp %d: exit %d u/s | full: %s | 85%%: %s" % [idx, roundi(a["speed"] * JumpCheck.U), a["runs"][0]["label"], a["runs"][1]["label"]]
		if not (JumpCheck.good(a["runs"][0]["outcome"]) and JumpCheck.good(a["runs"][1]["outcome"])):
			bad += 1
			line += "   <-- FAIL"
		print(line)
	if not boost.is_empty():
		# the boosted jump: fly the boosted velocity from the exit
		var ex := Vector3(boost["exit"][0], boost["exit"][1], boost["exit"][2])
		var vel := Vector3(boost["velocity"][0], boost["velocity"][1], boost["velocity"][2])
		var volumes: Array = ed.entities_root.get_children().filter(func(x): return x.is_volume() and x.kind != "booster")
		var res: Dictionary = JumpCheck.fly(ed.get_world_3d().direct_space_state, ex, vel, volumes, -1000.0, [ed.ramps_root.get_child(2)._body.get_rid()])
		print("  boosted jump: ", res["label"], "" if JumpCheck.good(res["outcome"]) else "   <-- FAIL")
		if not JumpCheck.good(res["outcome"]):
			bad += 1
	failures += bad
	var problems := Array(SurfsUpExporter.check(map)).filter(func(x): return name != "1_blank" or x != "The map has no ramps.")
	if not problems.is_empty():
		print("  export check: ", problems)
		failures += 1
	# thumbnail for the welcome screen: the 3D view only (no handles, labels or arcs), framed on the whole map
	ed.show_all_arcs = false
	ed._select(null)
	var cam := ed.panes[0].camera as OrbitCamera
	cam.fov = 32.0                                       # long lens: near-orthographic, the course stays in proportion
	cam.cull_mask = 1                                    # no editor grid in the thumbnail
	ed.frame_course(cam, 16.0 / 9.0)
	for i in 12:
		await process_frame
	var img: Image = ed.panes[0].viewport.get_texture().get_image()
	var target := Vector2(img.get_width(), img.get_width() * 9.0 / 16.0)
	img = img.get_region(Rect2i(0, int((img.get_height() - target.y) / 2), int(target.x), int(target.y)))
	img.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path("res://templates/%s.png" % name))
	cam.cull_mask = 0xFFFFF
	cam.fov = 70.0
	var f := FileAccess.open("res://templates/%s.sfmap" % name, FileAccess.WRITE)
	f.store_string(JSON.stringify(map, "  "))
	f.close()
	print("%s: %s" % [name, "OK" if bad == 0 else "%d FAILED JUMPS" % bad])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://templates"))
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed._toggle_views()                                   # one big 3D view for the thumbnails
	await verify("1_blank", template_blank())
	await verify("2_first_surf", template_first_surf())
	await verify("3_three_stages", template_three_stages())
	await verify("4_aurora_night", template_aurora())
	print("TEMPLATES: ", "ALL JUMPS PROVEN" if failures == 0 else "%d problems" % failures)
	quit()
