class_name VmfExporter
extends RefCounted
## Counter-Strike: Source export: writes a Hammer .vmf (and can compile it to a .bsp with the vbsp / vvis / vrad
## that ship with CS:S).
##
## Ramps become brushes: every stretch between two cross-sections, cut into convex pieces, is the convex hull of
## its corner points (the classic way surf ramps are built in Hammer). Platforms are box brushes. Zones use the
## surf-timer naming convention: map_start, map_end, s2_start, s3_start... with info_teleport_destinations named
## spawn_<zone>. Teleports and kill zones are trigger_teleports, boosters trigger_pushes, the kill floor a field of
## trigger_teleports sending you to the nearest stage. A skybox shell seals the map so it compiles without a leak.
##
## Source is Z-up and 1 unit = 1 inch: (x, y, z)_source = (x, -z, y)_godot * 39.37, the same 39.37 units per meter
## SurfsUp uses, so speeds and gravity match.

const U := 39.37
const LIMIT := 16384.0                   ## Source maps must fit inside +-16384 units on every axis
const SKY_MARGIN := 256.0                ## room between the map and the skybox walls (6.5 m)
const SKY_THICK := 64.0
const WELD := 0.5                        ## units: a cut cube's corners closer than this become one (about 1 cm)
const SIDE_SPREAD := 256.0               ## units between the three points that define a cut cube's brush side
const MIN_THICK := 1.0                   ## units: a cut piece thinner than this is left out (about 2.5 cm)
const MIN_SEGMENT := 2.0                 ## meters: ramp cross-sections closer than this are merged (brush budget)
const MAX_BRUSHES := 8192                ## Source's brush limit
const RAMP_MATERIAL := "DEV/DEV_MEASUREGENERIC01B"
const PLATFORM_MATERIAL := "DEV/DEV_MEASUREWALL01C"
const SKY_MATERIAL := "TOOLS/TOOLSSKYBOX"
const WATER_MATERIAL := "LIQUIDS/AZTECWATER"
const NODRAW := "TOOLS/TOOLSNODRAW"
## The closest stock CS:S texture for each block look (custom textures come with the material library).
const BLOCK_MATERIALS := {"grid": "DEV/DEV_MEASUREGENERIC01B", "color": "DEV/DEV_MEASUREWALL01C", "steel": "DEV/DEV_MEASUREWALL01D",
	"ceramic": "DEV/DEV_MEASUREWALL01A"}
const TRIGGER_MATERIAL := "TOOLS/TOOLSTRIGGER"
## Closest stock CS:S sky for each sky preset (all of these ship with CS:S).
const SKIES := {"day": "sky_day01_01", "sunset": "sky_day02_09", "overcast": "sky_day03_01", "night": "sky_borealis01",
	"aurora": "sky_borealis01", "space": "sky_borealis01"}
const SKY_CHOICES := ["sky_day01_01", "sky_day01_05", "sky_day01_08", "sky_day02_01", "sky_day02_05", "sky_day02_09",
	"sky_day03_01", "sky_day03_04", "sky_day03_06", "sky_borealis01", "sky_dust", "sky_wasteland02", "sky_c17_05",
	"italy", "assault", "office", "jungle", "tides", "train"]

var _id := 0
var _off := Vector3.ZERO
var _out := PackedStringArray()
var warnings := PackedStringArray()
var brushes := 0
var used_materials := {}                 ## library material ids the map uses (become VTF / VMT files)
var glowing_materials := {}              ## ...of which these also get a self-lit version
const VTF_SIZE := 512                    ## custom textures are converted at this size for CS:S


## Writes the map as a .vmf. Returns {"error": "" or why not, "warnings": [...], "brushes": n, "path": path}.
static func export_vmf(map: Dictionary, path: String, opts := {}) -> Dictionary:
	var ex := VmfExporter.new()
	var text := ex.build(map, opts)
	if text == "":
		return {"error": ex.warnings[0] if not ex.warnings.is_empty() else "Nothing to export", "warnings": [], "brushes": 0, "path": path}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"error": "Can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())], "warnings": [], "brushes": 0, "path": path}
	f.store_string(text)
	f.close()
	return {"error": "", "warnings": ex.warnings, "brushes": ex.brushes, "path": path, "materials": ex.used_materials.keys() + ex.variant_materials.values(),
		"glowing": ex.glowing_materials.keys()}


## Source coordinates of a Godot point (centered on the map).
func src(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y) * U - _off


## The whole .vmf as text ("" on failure, with the reason in warnings[0]).
func build(map: Dictionary, opts := {}) -> String:
	var problems := SurfsUpExporter.check(map)
	if not problems.is_empty():
		warnings = PackedStringArray([problems[0]])
		return ""
	# ---- gather geometry (Godot space) and the map's bounds
	var ramps := []
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for rd in map.get("ramps", []):
		var pts := PackedVector3Array()
		for p in rd.get("points", []):
			pts.append(Vector3(p[0], p[1], p[2]))
		if pts.size() < 2:
			continue
		var geo := RampShape.build(pts, RampShape.spec(rd))
		ramps.append(geo)
		for ring in geo["rings"]:
			for q in ring:
				lo = lo.min(q)
				hi = hi.max(q)
	var ents: Array = map.get("entities", [])
	# blocks: every convex piece is one brush
	var block_pieces := []
	var cutters := []
	for bd in map.get("blocks", []):
		if BlockShape.spec(bd)["cutter"]:
			cutters.append(bd)
	for bd in map.get("blocks", []):
		var bs := BlockShape.spec(bd)
		if bs["cutter"]:
			continue
		for piece in BlockShape.world_pieces(bs, cutters):
			block_pieces.append([piece, bs])
			for q in Convex.points(piece):
				lo = lo.min(q)
				hi = hi.max(q)
	var cube_items := CubeWorld.models_of(map)
	for item in cube_items:
		var cw: CubeWorld = item[0]
		if cw.count() == 0 and cw.mats.is_empty():
			continue
		var cb := cw.bounds()
		for i in 8:
			var c: Vector3 = (item[1] as Transform3D) * (cb.position + cb.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
			lo = lo.min(c)
			hi = hi.max(c)
	for e in ents:
		for c in _box_corners(e, true):
			lo = lo.min(c)
			hi = hi.max(c)
	var kill_y := SurfsUpExporter.kill_floor_y(map)
	lo.y = minf(lo.y, kill_y - 2.0)
	# ---- center the map in Source space and check it fits
	var s_lo := Vector3(lo.x, -hi.z, lo.y) * U
	var s_hi := Vector3(hi.x, -lo.z, hi.y) * U
	_off = ((s_lo + s_hi) * 0.5).round()
	var half := (s_hi - s_lo) * 0.5 + Vector3.ONE * (SKY_MARGIN + SKY_THICK)
	if half.x > LIMIT or half.y > LIMIT or half.z > LIMIT:
		var size_m := (hi - lo)
		warnings = PackedStringArray(["The map is %.0f x %.0f m and %.0f m tall: a CS:S map must fit in about %.0f m on every side. Move things closer together (or split it into stages placed side by side)." % [
			size_m.x, size_m.z, size_m.y, (LIMIT - SKY_MARGIN - SKY_THICK) * 2.0 / U]])
		return ""
	if not map.get("props", []).is_empty():
		warnings.append("Props aren't exported to CS:S yet (Source needs compiled .mdl models), so they're left out.")

	# ---- world brushes
	var world := PackedStringArray()
	var details := PackedStringArray()
	var ri := 0
	for geo in ramps:                                    # ramps are func_detail: they don't cut up visibility
		var rd: Dictionary = map["ramps"][ri]
		ri += 1
		var rmat := RAMP_MATERIAL
		var fit := Vector2.ZERO                          # (a "fit across a ramp" material: texture px, meters along)
		if rd.get("look", "") == "material" and MaterialLibrary.has(rd.get("material", "")):
			rmat = _mat_name(rd["material"])
			used_materials[rd["material"]] = true
			if MaterialLibrary.ramp_fit(rd["material"]):
				fit = Vector2(MaterialLibrary.texture_px(rd["material"]),
					MaterialLibrary.world_size(rd["material"]) * maxf(float(rd.get("tex_scale", 20.0)) / 20.0, 0.05))
		elif rd.get("look", "") == "shader":
			rmat = _shader_material(rd.get("shader", ""), rd.get("shader_params", {}), RAMP_MATERIAL)
		var rb := _ramp_brushes(geo, rmat, fit)
		if not rb.is_empty():
			details.append("entity
{
	\"id\" \"%d\"
	\"classname\" \"func_detail\"
%s}
" % [_next(), "".join(rb)])
	for e in ents:
		if e.get("kind", "") in ["start", "finish", "stage"] and not e.get("zone_only", false):
			world.append(_solid(_hull(_box_corners(e, false).map(func(c): return src(c))), PLATFORM_MATERIAL))
	# liquids: water as CS:S water (the preset's own CS:S water material); lava a glowing surface you pass through
	var env: Dictionary = map.get("environment", {})
	var noclip := PackedStringArray()
	var glassy := PackedStringArray()
	for bp in block_pieces:
		if bp[1].get("water", false):
			var lp: Dictionary = Look.LIQUIDS.get(bp[1].get("liquid", "water"), Look.LIQUIDS["water"])
			if lp["style"] == "lava":
				noclip.append(_solid(_hull(Array(Convex.points(bp[0])).map(func(q): return src(q))), _lava_material(bp[1].get("liquid", "lava"))))
			else:
				world.append(_water_solid(bp[0], lp.get("css", WATER_MATERIAL)))
		else:
			world.append(_block_solid(bp[0], bp[1]))
	# cube objects (build mode): a brush per cube; noclip cubes walk-through (func_illusionary); materials
	var cube_water: String = Look.LIQUIDS.get(env.get("water_look", "water"), Look.LIQUIDS["water"]).get("css", WATER_MATERIAL)
	var gl: Dictionary = Look.GLASS.get(env.get("glass_look", "clear"), Look.GLASS["clear"])
	for item in cube_items:
		var cw: CubeWorld = item[0]
		var cxf: Transform3D = item[1]
		for k in cw.leaves:
			var b := _cube_solid(cw, k, cxf)
			if b == "":
				continue
			if cw.cube_in_mat(k, "noclip"):
				noclip.append(b)
			else:
				world.append(b)
		var boxes := cw.material_boxes()
		for bx in boxes.get("water", []):
			world.append(_water_solid(Convex.transformed(_box_piece(bx), cxf), cube_water))
		for bx in boxes.get("glass", []):
			glassy.append(_solid(_hull(_box_src(bx, cxf)), _special_material("sf_glass", Color.html(gl["color"]),
				"\t\"$translucent\" \"1\"\n\t\"$alpha\" \"%.2f\"\n" % clampf(1.0 - float(gl["clarity"]) * 0.8, 0.15, 0.9))))
		for m in ["clip", "gameclip"]:
			for bx in boxes.get(m, []):
				world.append(_solid(_hull(_box_src(bx, cxf)), "TOOLS/TOOLSPLAYERCLIP"))
		for bx in boxes.get("lava", []):
			noclip.append(_solid(_hull(_box_src(bx, cxf)), _lava_material(env.get("lava_look", "lava"))))
	if not noclip.is_empty():
		details.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"func_illusionary\"\n%s}\n" % [_next(), "".join(noclip)])
	if not glassy.is_empty():
		details.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"func_detail\"\n%s}\n" % [_next(), "".join(glassy)])
	# text: solid 3D letters are func_detail, signs and see-through text func_illusionary
	for td in map.get("texts", []):
		var ts := TextShape.spec(td)
		if String(ts["text"]).strip_edges() == "":
			continue
		var tmat := BLOCK_MATERIALS["color"]
		if ts["material"] != "" and MaterialLibrary.has(ts["material"]):
			tmat = _mat_name(ts["material"])
			used_materials[ts["material"]] = true
		var depth := maxf(TextShape.depth_of(ts), 2.0 / U)       # at least two units thick: thinner brushes break Source's compiler
		var tb := PackedStringArray()
		for piece in TextShape.pieces(ts, 0.0, depth):
			var tp := []
			for q in Convex.points(piece):
				tp.append(src(q))
			tb.append(_solid(_hull(tp), tmat))
		if tb.is_empty():
			continue
		var cls := "func_detail" if ts["mode"] == "3d" and bool(ts["solid"]) else "func_illusionary"
		details.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"%s\"\n%s}\n" % [_next(), cls, "".join(tb)])

	var b_lo := -half + Vector3.ONE * SKY_THICK
	var b_hi := half - Vector3.ONE * SKY_THICK
	for i in 3:                                          # six walls of skybox around everything
		for sgn in [-1.0, 1.0]:
			var a := -half
			var b := half
			if sgn < 0:
				b[i] = b_lo[i]
			else:
				a[i] = b_hi[i]
			world.append(_solid(_hull(_aabb_corners(a, b)), SKY_MATERIAL))
	if brushes > MAX_BRUSHES:
		warnings = PackedStringArray(["That's %d brushes; Source allows %d. Lower the ramps' Smoothness and try again." % [brushes, MAX_BRUSHES]])
		return ""

	# ---- point and brush entities
	var sky: String = opts.get("skyname", SKIES.get(env.get("preset", "day"), "sky_day01_01"))
	if opts.get("sky_faces", {}) is Dictionary and not opts.get("sky_faces", {}).is_empty():
		variant_materials["skybox " + sky] = {"skybox": sky, "faces": opts["sky_faces"]}   # (the map's own sky, baked)
	var entities := PackedStringArray()
	var plates := []                                     # [godot spawn position, destination name]
	var spawned := {}                                    # zone name -> its spawn is made (several boxes, one zone)
	for e in SurfsUpExporter._plates_first(ents):
		var kind: String = e.get("kind", "")
		if not kind in ["start", "finish", "stage"]:
			continue
		var zone_name: String = {"start": "map_start", "finish": "map_end"}.get(kind, "s%d_start" % int(e.get("number", 2)))
		entities.append(_brush_entity({"classname": "trigger_multiple", "targetname": zone_name, "spawnflags": "1", "wait": "0"},
			_hull(_zone_corners(e).map(func(c): return src(c)))))
		if kind == "finish" or spawned.has(zone_name):
			continue
		spawned[zone_name] = true
		var spawn := _spawn(e)
		var yaw_src := float(e.get("yaw", 0.0)) + 90.0
		entities.append(_point_entity({"classname": "info_teleport_destination", "targetname": "spawn_" + zone_name,
			"angles": "0 %s 0" % _n(yaw_src)}, src(spawn)))
		plates.append([spawn, "spawn_" + zone_name, e])
		if kind == "start":
			for p in _spawn_grid(e):
				for team in ["info_player_terrorist", "info_player_counterterrorist"]:
					entities.append(_point_entity({"classname": team, "angles": "0 %s 0" % _n(yaw_src)}, src(p)))
	var kept_speed := 0
	var boosters := 0
	for e in ents:
		var kind: String = e.get("kind", "")
		var hull := _hull(_box_corners(e, false).map(func(c): return src(c)))
		match kind:
			"destination":                               # (0.19.9: a teleport's own target, no stage)
				var dpos := Vector3(e["position"][0], float(e["position"][1]) - float(e["size"][1]) * 0.5, e["position"][2])
				entities.append(_point_entity({"classname": "info_teleport_destination", "targetname": "dest_%d" % int(e.get("number", 1)),
					"angles": "0 %s 0" % _n(float(e.get("yaw", 0.0)) + 90.0)}, src(dpos)))
			"teleport":
				var tgt := ("dest_%d" if String(e.get("to", "stage")) == "destination" else "spawn_s%d_start") % int(e.get("number", 2))
				entities.append(_brush_entity({"classname": "trigger_teleport", "spawnflags": "1", "target": tgt}, hull))
				if e.get("keep_speed", true):
					kept_speed += 1
			"kill":
				var top := Vector3(e["position"][0], e["position"][1] + e["size"][1] * 0.5, e["position"][2])
				entities.append(_brush_entity({"classname": "trigger_teleport", "spawnflags": "1", "target": _nearest_plate(plates, top, true)}, hull))
			"booster":
				var d := _boost_dir(e)
				var sd := Vector3(d.x, -d.z, d.y)
				var pitch := -rad_to_deg(asin(clampf(sd.z, -1.0, 1.0)))
				var yaw := rad_to_deg(atan2(sd.y, sd.x))
				entities.append(_brush_entity({"classname": "trigger_push", "spawnflags": "1", "pushdir": "%s %s 0" % [_n(pitch), _n(yaw)],
					"speed": _n(float(e.get("strength", 1000.0)))}, hull))
				boosters += 1
	for bd in map.get("blocks", []):
		var wb := BlockShape.spec(bd)
		if wb.get("water", false) and wb.get("deadly", false):
			var wxf := BlockShape.transform_of(wb)
			var wsz := Vector3(wb["size"][0], wb["size"][1], wb["size"][2])
			var corners := []
			for i in 8:
				corners.append(src(wxf * Vector3(wsz.x * (0.5 if i & 1 else -0.5), wsz.y if i & 2 else 0.0, wsz.z * (0.5 if i & 4 else -0.5))))
			var wtop := wxf * Vector3(0, wsz.y, 0)
			entities.append(_brush_entity({"classname": "trigger_teleport", "spawnflags": "1", "target": _nearest_plate(plates, wtop, true)}, _hull(corners)))
	for item in CubeWorld.models_of(map):            # cube lava / death: send players back
		var cw: CubeWorld = item[0]
		var boxes := cw.material_boxes()
		for m in ["lava", "death"]:
			for bx in boxes.get(m, []):
				var top: Vector3 = (item[1] as Transform3D) * ((bx as AABB).get_center() + Vector3(0, (bx as AABB).size.y * 0.5, 0))
				entities.append(_brush_entity({"classname": "trigger_teleport", "spawnflags": "1", "target": _nearest_plate(plates, top, true)},
					_hull(_box_src(bx, item[1]))))
	for ld in map.get("lights", []):
		var ls := LightNode.spec(ld)
		var lc := Color.html(ls["color"])
		var lp: Array = ls["position"]
		var lkv := {"classname": "light_spot" if ls["kind"] == "spot" else "light",
			"_light": "%d %d %d %d" % [lc.r8, lc.g8, lc.b8, int(float(ls["energy"]) * 120.0)],
			"_zero_percent_distance": _n(float(ls["range"]) * U), "_fifty_percent_distance": _n(float(ls["range"]) * U * 0.35)}
		if ls["kind"] == "spot":
			var dir := LightNode.basis_of(ls) * Vector3.FORWARD
			var sd := Vector3(dir.x, -dir.z, dir.y)
			lkv["pitch"] = _n(-rad_to_deg(asin(clampf(sd.z, -1.0, 1.0))))
			lkv["angles"] = "0 %s 0" % _n(rad_to_deg(atan2(sd.y, sd.x)))
			lkv["_cone"] = _n(float(ls["angle"]) * 0.5)
			lkv["_inner_cone"] = _n(float(ls["angle"]) * 0.35)
		var style: int = LightNode.CSS_STYLES.get(ls["effect"], 0)
		if style != 0:
			lkv["style"] = str(style)                    # Source's own flicker / pulse / strobe
		if ls["kind"] == "strip":                        # a strip: a light along its length, like the editor's
			var n := LightNode.strip_count(ls)
			var e := float(ls["energy"]) / sqrt(float(n))
			lkv["_light"] = "%d %d %d %d" % [lc.r8, lc.g8, lc.b8, int(e * 120.0)]
			var lxf := Transform3D(LightNode.basis_of(ls), Vector3(lp[0], lp[1], lp[2]))
			for q in LightNode.strip_points(ls):
				entities.append(_point_entity(lkv.duplicate(), src(lxf * (q as Vector3))))
			continue
		entities.append(_point_entity(lkv, src(Vector3(lp[0], lp[1], lp[2]))))
	var no_fx := 0
	for pd in map.get("particles", []):
		var ps := ParticleNode.spec(pd)
		var css: String = ParticleNode.PRESETS[ps["preset"]]["css"]
		if css == "":
			no_fx += 1
			continue
		for e in _particle_entities(ps, css, kill_y):
			entities.append(e)
	if no_fx > 0:
		warnings.append("%d particle effect(s) (floating dust, magic sparkles) have no CS:S match, so they're left out." % no_fx)
	if kept_speed > 0:
		warnings.append("%d teleport(s) keep the player's speed in SurfsUp; CS:S teleports stop the player instead." % kept_speed)
	if boosters > 0:
		warnings.append("Boosters become trigger_push: CS:S pushes for as long as you're inside, so test their strength in game.")
	# kill floor: tiles of trigger_teleport, each to the nearest start / stage plate
	var floor_z := (kill_y * U) - _off.z
	var cell := 2048.0
	var x0 := -half.x + SKY_THICK + 1.0
	var y0 := -half.y + SKY_THICK + 1.0
	var nx := int(ceil((half.x - SKY_THICK) * 2.0 / cell))
	var ny := int(ceil((half.y - SKY_THICK) * 2.0 / cell))
	for j in ny:
		var run_start := 0
		var run_owner := ""
		for i in nx + 1:
			var owner := ""
			if i < nx:
				var cx := x0 + (i + 0.5) * cell
				var cy := y0 + (j + 0.5) * cell
				var g := Vector3((cx + _off.x) / U, kill_y, -(cy + _off.y) / U)      # the cell's center, back in Godot space
				owner = _nearest_plate(plates, g, false)
			if i == nx or owner != run_owner:
				if i > 0 and run_owner != "":
					var a := Vector3(x0 + run_start * cell, y0 + j * cell, floor_z - 64.0)
					var b := Vector3(minf(x0 + i * cell, half.x - SKY_THICK - 1.0), minf(y0 + (j + 1) * cell, half.y - SKY_THICK - 1.0), floor_z)
					a.z = maxf(a.z, -half.z + SKY_THICK + 1.0)
					entities.append(_brush_entity({"classname": "trigger_teleport", "spawnflags": "1", "target": run_owner}, _hull(_aabb_corners(a, b))))
				run_start = i
				run_owner = owner
	# sun, surf settings
	var sun_yaw := float(env.get("sun_yaw", -35.0)) + 90.0
	var sc := Color.html(env.get("sun_color", "fff2e0"))
	var ac := Color.html(env.get("ambient_color", "c8d4e6"))
	entities.append(_point_entity({"classname": "light_environment", "pitch": _n(-float(env.get("sun_pitch", 55.0))),
		"angles": "0 %s 0" % _n(sun_yaw),
		"_light": "%d %d %d %d" % [sc.r8, sc.g8, sc.b8, int(260.0 * float(env.get("sun_energy", 1.0)))],
		"_ambient": "%d %d %d %d" % [ac.r8, ac.g8, ac.b8, int(90.0 * float(env.get("ambient_energy", 0.6)))],
		"_lightHDR": "-1 -1 -1 1", "_ambientHDR": "-1 -1 -1 1", "SunSpreadAngle": "0"}, Vector3(0, 0, b_hi.z - 64.0)))
	for p in plates:                                     # (what reflective materials reflect: run buildcubemaps once)
		entities.append(_point_entity({"classname": "env_cubemap"}, src(p[0]) + Vector3(0, 0, 64)))
	var aa: int = int(opts.get("airaccelerate", 150))
	entities.append(_point_entity({"classname": "point_servercommand", "targetname": "sf_servercommand"}, Vector3(0, 0, b_hi.z - 96.0)))
	entities.append(_point_entity({"classname": "logic_auto", "spawnflags": "1"}, Vector3(0, 0, b_hi.z - 128.0),
		["\"OnMapSpawn\" \"sf_servercommand,Command,sv_airaccelerate %d,0,-1\"" % aa,
		 "\"OnMapSpawn\" \"sf_servercommand,Command,sv_gravity 800,0,-1\""]))

	# ---- assemble
	_out = PackedStringArray()
	_out.append("versioninfo\n{\n\t\"editorversion\" \"400\"\n\t\"editorbuild\" \"8864\"\n\t\"mapversion\" \"1\"\n\t\"formatversion\" \"100\"\n\t\"prefab\" \"0\"\n}\n")
	_out.append("visgroups\n{\n}\nviewsettings\n{\n\t\"bSnapToGrid\" \"1\"\n\t\"bShowGrid\" \"1\"\n\t\"bShowLogicalGrid\" \"0\"\n\t\"nGridSpacing\" \"64\"\n\t\"bShow3DGrid\" \"0\"\n}\n")
	_out.append("world\n{\n\t\"id\" \"%d\"\n\t\"mapversion\" \"1\"\n\t\"classname\" \"worldspawn\"\n\t\"skyname\" \"%s\"\n\t\"maxpropscreenwidth\" \"-1\"\n\t\"detailvbsp\" \"detail.vbsp\"\n\t\"detailmaterial\" \"detail/detailsprites\"\n\t\"comment\" \"Made with %s\"\n" % [_next(), sky, MalletVersion.full()])
	_out.append("".join(world))
	_out.append("}\n")
	_out.append("".join(details))
	_out.append("".join(entities))
	_out.append("cameras\n{\n\t\"activecamera\" \"-1\"\n}\ncordon\n{\n\t\"mins\" \"(-1024 -1024 -1024)\"\n\t\"maxs\" \"(1024 1024 1024)\"\n\t\"active\" \"0\"\n}\n")
	return "".join(_out)


# ------------------------------------------------------------------------------------------------ ramps
## Brushes for one ramp: between consecutive cross-sections (at least MIN_SEGMENT apart, seams kept), one convex
## hull per convex piece of the profile.
## `fit` (texture px, meters along; zero = off): the riding faces' textures span the riding surface once across,
## as in the editor (MaterialLibrary.ramp_fit), instead of Hammer's world-aligned default.
func _ramp_brushes(geo: Dictionary, material := RAMP_MATERIAL, fit := Vector2.ZERO) -> PackedStringArray:
	var out := PackedStringArray()
	var rings: Array = geo["rings"]
	var ridge: PackedVector3Array = geo["ridge"]
	if rings.size() < 2:
		return out
	var keep := [0]
	var seams: PackedInt32Array = geo.get("seams", PackedInt32Array())
	var since := 0.0
	for i in range(1, ridge.size()):
		since += ridge[i].distance_to(ridge[i - 1])
		if since >= MIN_SEGMENT or i == ridge.size() - 1 or i in seams:
			keep.append(i)
			since = 0.0
	var pp: PackedVector2Array = (geo["profile"] as Dictionary)["pts"]
	var pieces := []
	for poly in Geometry2D.decompose_polygon_in_convex(pp):
		var idx := []
		for v in poly:
			var best := 0
			for k in pp.size():
				if pp[k].distance_squared_to(v) < pp[best].distance_squared_to(v):
					best = k
			idx.append(best)
		pieces.append(idx)
	for s in range(1, keep.size()):
		var a: PackedVector3Array = rings[keep[s - 1]]
		var b: PackedVector3Array = rings[keep[s]]
		for idx in pieces:
			var pts := []
			for k in idx:
				pts.append(src(a[k]))
				pts.append(src(b[k]))
			var sides := _hull(pts)
			if sides.size() >= 4:
				out.append(_solid(sides, material, _fit_axes(sides, a, b, geo["profile"], fit) if fit.x > 0.0 else []))
	for poly in geo.get("closures", []):                 # closed ends: a slab 0.3 m thick across the end
		var pv: PackedVector3Array = poly
		if pv.size() < 3:
			continue
		var nrm := (pv[1] - pv[0]).cross(pv[pv.size() - 1] - pv[0]).normalized()
		var pts := []
		for q in pv:
			pts.append(src(q + nrm * 0.15))
			pts.append(src(q - nrm * 0.15))
		var sides := _hull(pts)
		if sides.size() >= 4:
			out.append(_solid(sides, material))
	return out


## Texture axes for the sides of one ramp piece that lie on a riding face: u across from 0 (one edge) to 1 (the
## other), ridge in between, exactly like RampShape's UVs; v one repeat every fit.y meters along. Other sides keep
## the default.
func _fit_axes(sides: Array, a: PackedVector3Array, b: PackedVector3Array, prof: Dictionary, fit: Vector2) -> Array:
	var pp: PackedVector2Array = prof["pts"]
	var pc := pp.size()
	var perim := PackedFloat32Array([0.0])
	for k in pc:
		perim.append(perim[k] + pp[k].distance_to(pp[(k + 1) % pc]))
	var r0: int = prof["ride"][0]
	var r1: int = prof["ride"][1]
	var ride_len := maxf(perim[r1] - perim[r0], 0.01)
	var px := fit.x
	var out := []
	for sd in sides:
		var nrm: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var ax: Array = _axes(nrm)
		for k in range(r0, r1):
			var a0 := src(a[k])
			var a1 := src(a[k + 1])
			var b0 := src(b[k])
			var en := (a1 - a0).cross(b0 - a0).normalized()
			if absf(en.dot(nrm)) < 0.999 or absf(nrm.dot(sd[0] - a0)) > 1.0:
				continue
			var len_e := a0.distance_to(a1)
			var du := (perim[k + 1] - perim[k]) / ride_len
			if len_e < 0.01 or du <= 0.0:
				break
			var dir := (a1 - a0) / len_e
			var su := len_e / (px * du)
			var shift := px * (perim[k] - perim[r0]) / ride_len - a0.dot(dir) / su
			var along := (b0 - a0) - dir * (b0 - a0).dot(dir)
			along = along.normalized() if along.length() > 0.001 else nrm.cross(dir).normalized()
			var sv := fit.y * U / px
			ax = ["[%f %f %f %f] %f" % [dir.x, dir.y, dir.z, shift, su], "[%f %f %f 0] %f" % [along.x, along.y, along.z, sv]]
			break
		out.append(ax)
	return out


# ------------------------------------------------------------------------------------------------ geometry
## The faces of the convex hull of a handful of points (Source space), each as three points wound so that
## (p3 - p1) x (p2 - p1) points out of the solid - Hammer's rule (clockwise seen from outside).
static func _hull(points: Array) -> Array:
	var pts: Array = []
	for p in points:                                     # drop duplicates
		var dup := false
		for q in pts:
			if (q as Vector3).distance_to(p) < 0.01:
				dup = true
				break
		if not dup:
			pts.append(p)
	var n := pts.size()
	var planes := []
	var eps := 0.02
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nrm: Vector3 = (pts[j] - pts[i]).cross(pts[k] - pts[i])
				if nrm.length() < 1e-3:
					continue
				nrm = nrm.normalized()
				var d: float = nrm.dot(pts[i])
				var front := false
				var back := false
				for p in pts:
					var sd: float = nrm.dot(p) - d
					if sd > eps:
						front = true
					elif sd < -eps:
						back = true
				if front and back:
					continue
				if front:
					nrm = -nrm
					d = -d
				var seen := false
				for pl in planes:
					if pl[0].dot(nrm) > 0.9999 and absf(pl[1] - d) < 0.1:
						seen = true
						break
				if not seen:
					planes.append([nrm, d])
	var sides := []
	for pl in planes:
		var on := []
		for p in pts:
			if absf(pl[0].dot(p) - pl[1]) <= eps:
				on.append(p)
		# the three points spanning the largest triangle: the most precise plane
		var best := []
		var best_area := 0.0
		for i in on.size():
			for j in range(i + 1, on.size()):
				for k in range(j + 1, on.size()):
					var area: float = (on[j] - on[i]).cross(on[k] - on[i]).length()
					if area > best_area:
						best_area = area
						best = [on[i], on[j], on[k]]
		if best.is_empty() or best_area < 1e-4:
			return []                                    # a face we can't describe would leave the brush open: drop it
		if (best[2] - best[0]).cross(best[1] - best[0]).dot(pl[0]) < 0.0:
			best = [best[0], best[2], best[1]]
		# nearly coplanar facets (a quad split in two) can pick the same three points: one face is enough
		var fn: Vector3 = (best[2] - best[0]).cross(best[1] - best[0]).normalized()
		var fd: float = fn.dot(best[0])
		var repeat := false
		for other in sides:
			var on2: Vector3 = (other[2] - other[0]).cross(other[1] - other[0]).normalized()
			var d2: float = on2.dot(other[0])
			# the same face if its three points already lie on another side (a thin triangle of nearly-in-line
			# points can come out a hair tilted; Source would round the two together)
			if on2.dot(fn) > 0.999 and absf(on2.dot(best[0]) - d2) < 0.05 and absf(on2.dot(best[1]) - d2) < 0.05 					and absf(on2.dot(best[2]) - d2) < 0.05:
				repeat = true
				break
		if not repeat:
			sides.append(best)
	if sides.size() < 4:
		return []
	# a sliver (a carve can leave one a hair thick) comes out of Source's rounding open or inside out: drop it
	for sd in sides:
		var sn: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var deepest := 0.0
		for p in pts:
			deepest = maxf(deepest, sn.dot(sd[0]) - sn.dot(p))
		if deepest < 0.5:
			return []
	return sides


static func _aabb_corners(a: Vector3, b: Vector3) -> Array:
	var out := []
	for i in 8:
		out.append(Vector3(b.x if i & 1 else a.x, b.y if i & 2 else a.y, b.z if i & 4 else a.z))
	return out


## Corners (Godot space) of a platform's slab or a volume's box; with `with_zone`, a platform's zone too.
static func _box_corners(e: Dictionary, with_zone: bool) -> Array:
	var p := Vector3(e["position"][0], e["position"][1], e["position"][2])
	var sz := Vector3(e["size"][0], e["size"][1], e["size"][2])
	var b := Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0))))
	var volume: bool = EntityNode.KINDS.get(e.get("kind", ""), {}).get("volume", false)
	var y0 := -sz.y * 0.5 if volume else -sz.y
	var y1 := sz.y * 0.5 if volume else 0.0
	if with_zone and not volume:
		y1 = float(EntityNode.KINDS[e["kind"]].get("zone", 10.0))
	var out := []
	for i in 8:
		var l := Vector3(sz.x * (0.5 if i & 1 else -0.5), y1 if i & 2 else y0, sz.z * (0.5 if i & 4 else -0.5))
		out.append(p + b * l)
	return out


## A platform's timer zone: its footprint, from its top surface up (Godot space).
static func _zone_corners(e: Dictionary) -> Array:
	var p := Vector3(e["position"][0], e["position"][1], e["position"][2])
	var sz := Vector3(e["size"][0], e["size"][1], e["size"][2])
	var b := Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0))))
	var zh: float = sz.y if e.get("zone_only", false) else EntityNode.KINDS[e["kind"]].get("zone", 10.0)
	var out := []
	for i in 8:
		out.append(p + b * Vector3(sz.x * (0.5 if i & 1 else -0.5), (zh if i & 2 else 0.0) + 0.05, sz.z * (0.5 if i & 4 else -0.5)))
	return out


static func _spawn(e: Dictionary) -> Vector3:
	var p := Vector3(e["position"][0], e["position"][1], e["position"][2])
	return p + Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0)))) * Vector3(0, 0.15, float(e["size"][2]) * 0.25)


## Up to 16 spawn spots in a grid on the back half of the start platform (players need one each).
static func _spawn_grid(e: Dictionary) -> Array:
	var p := Vector3(e["position"][0], e["position"][1], e["position"][2])
	var sz := Vector3(e["size"][0], e["size"][1], e["size"][2])
	var b := Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0))))
	var out := []
	var cols := clampi(int(sz.x / 1.3), 1, 4)
	var rows := clampi(int(sz.z * 0.45 / 1.3), 1, 4)
	for r in rows:
		for c in cols:
			var x := (c - (cols - 1) * 0.5) * minf(1.3, sz.x / cols)
			var z := sz.z * 0.25 + (r - (rows - 1) * 0.5) * minf(1.3, sz.z * 0.45 / rows)
			out.append(p + b * Vector3(x, 0.15, z))
	return out


static func _boost_dir(e: Dictionary) -> Vector3:
	var local := Basis(Vector3.RIGHT, deg_to_rad(float(e.get("pitch", 20.0)))) * Vector3.FORWARD
	return (Basis(Vector3.UP, deg_to_rad(float(e.get("yaw", 0.0)))) * local).normalized()


## The destination to send a falling player to: the nearest start / stage plate (with `above`, one higher than `p`).
static func _nearest_plate(plates: Array, p: Vector3, above: bool) -> String:
	var best := "spawn_map_start"
	var best_d := INF
	for pl in plates:
		var at: Vector3 = pl[0]
		if above and at.y < p.y:
			continue
		var d := Vector2(at.x - p.x, at.z - p.z).length() + (absf(at.y - p.y) * 0.25 if above else 0.0)
		if d < best_d:
			best_d = d
			best = pl[1]
	return best


# ------------------------------------------------------------------------------------------------ materials
static func _mat_name(id: String) -> String:
	if CssLibrary.is_css(id):
		return id.substr(4)                              # CS:S's own material: every CS:S player has it
	return "mallet/" + id.to_lower()


## One block piece as a brush, each side with its block side's material and texture placement.
func _block_solid(piece: Array, bs: Dictionary) -> String:
	var pts := []
	for q in Convex.points(piece):
		pts.append(src(q))
	var sides := _hull(pts)
	if sides.size() < 4:
		return ""
	var inv := BlockShape.basis_of(bs).inverse()
	var mats := []
	var axes := []
	for sd in sides:
		var nrm_src: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var nrm := Vector3(nrm_src.x, nrm_src.z, -nrm_src.y)            # back to Godot space
		var fs := BlockShape.face_settings(bs, BlockShape.slot_of((inv * nrm).normalized()))
		if fs["material"] != "" and MaterialLibrary.has(fs["material"]):
			used_materials[fs["material"]] = true
			if float(bs.get("glow", 0.0)) > 0.0 and CssLibrary.is_css(fs["material"]):
				mats.append(_css_variant(fs["material"], "\t\"$selfillum\" \"1\"\n"))   # (a self-lit copy of the game's own)
			elif float(bs.get("glow", 0.0)) > 0.0:
				glowing_materials[fs["material"]] = true
				mats.append(_mat_name(fs["material"]) + "_glow")
			else:
				mats.append(_mat_name(fs["material"]))
			axes.append(_material_axes(nrm, fs))
		elif bs["look"] == "shader":
			mats.append(_shader_material(bs.get("shader", ""), bs.get("shader_params", {}), PLATFORM_MATERIAL))
			axes.append(_axes(nrm_src))
		else:
			mats.append(BLOCK_MATERIALS.get(bs["look"], PLATFORM_MATERIAL))
			axes.append(_axes(nrm_src))
	return _solid(sides, mats, axes)


## Your own surface shader in CS:S (which can't run shaders): its first image, else its first color.
func _shader_material(id: String, params: Dictionary, fallback: String) -> String:
	var base := UserShaders.css_base(id, params)
	if base.has("image"):
		var name := "shader_%s_%x" % [id.to_lower().validate_filename().replace(" ", "_"), hash(base["image"]) & 0xffffff]
		variant_materials[name] = {"name": name, "image": base["image"], "params": "", "surface": "concrete"}
		return "MALLET/" + name.to_upper()
	if base.has("color"):
		var c: Color = base["color"]
		return _special_material("shader_%s" % c.to_html(false), c, "")
	return fallback


## A cut cube's brush sides straight from its exact planes. A side is written as three points far apart on its plane:
## three corners of a tiny face would barely pin the plane down once rounded to the file's decimals, which crashes vbsp.
func _cut_sides(w: CubeWorld, k: Vector4i, xf: Transform3D) -> Array:
	var origin := Vector3(k.x, k.y, k.z) * CubeWorld.TICK
	var unit := CubeWorld.metres(k.w) / 8.0
	var out := []
	for f in CubeWorld.cut_faces(w.leaves[k][3]):
		var poly: PackedVector3Array = f[2]
		var cen := Vector3.ZERO
		var size := 0.0
		for q in poly:
			cen += q
		cen /= poly.size()
		for q in poly:
			size = maxf(size, q.distance_to(cen))
		if size * unit * U < WELD:
			continue                                     # (a speck of a face: its neighbors close the brush)
		var g: Vector3 = xf.basis * (f[3] as Vector3)
		var n := Vector3(g.x, -g.z, g.y).normalized()
		var c := src(xf * (origin + cen * unit))
		var t := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var b := n.cross(t)
		out.append([c, c + b * SIDE_SPREAD, c + t * SIDE_SPREAD])   # ((p3 - p1) x (p2 - p1) points out: Hammer's rule)
	return out


## Is a convex brush thinner than MIN_THICK anywhere (measured from each of its sides, across the solid)?
static func _too_thin(sides: Array, pts: Array) -> bool:
	for sd in sides:
		var n: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var far := 0.0
		for p in pts:
			far = maxf(far, absf((p - sd[0]).dot(n)))
		if far < MIN_THICK:
			return true
	return false


## One cube from build mode as a brush, each side with its own texture and texture settings.
func _cube_solid(w: CubeWorld, k: Vector4i, xf := Transform3D.IDENTITY) -> String:
	var pts := []
	var is_cut: bool = (w.leaves[k] as Array).size() > 3 and not (w.leaves[k][3] as Array).is_empty()
	for q in w.cube_points(k):
		var sp := src(xf * q)
		if is_cut and pts.any(func(o): return (o as Vector3).distance_to(sp) < WELD):
			continue                                     # (corners a few mm apart: Source can't hold such a tiny edge)
		pts.append(sp)
	var sides := _hull(pts)
	if sides.size() < 4:
		return ""
	if is_cut and _too_thin(sides, pts):
		return ""                                        # (a plane just nicking a corner: vbsp crashes on such slivers)
	if is_cut:
		sides = _cut_sides(w, k, xf)
		if sides.size() < 4:
			return ""
	var tex: PackedStringArray = w.leaves[k][1]
	var alpha := w.cube_in_mat(k, "alpha")
	var inv := xf.basis.inverse()
	var mats := []
	var axes := []
	for sd in sides:
		var nrm_src: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var nrm := Vector3(nrm_src.x, nrm_src.z, -nrm_src.y)            # back to Godot space
		var sl := CubeWorld.parse_slot(tex[CubeWorld.orient_of((inv * nrm).normalized())])
		var id: String = sl["id"]
		if id != "" and MaterialLibrary.has(id):
			used_materials[id] = true
			mats.append(_slot_material(sl, alpha))
			axes.append(_material_axes(nrm, {"material": id, "uv_scale": float(sl["s"]), "uv_rot": float(int(sl["r"]) % 4) * 90.0,
				"uv_offset": [float(sl["u"]), float(sl["v"])], "origin": xf.origin}))   # (cube textures follow their object)
		else:
			mats.append(BLOCK_MATERIALS.get("grid", PLATFORM_MATERIAL))
			axes.append(_axes(nrm_src))
	return _solid(sides, mats, axes)


var variant_materials := {}              ## extra VMTs: name -> {"name", "base" or "color", "params"}


## A texture with Sauerbraten-style settings Source can do in the material itself (color, see-through, scrolling).
func _slot_material(sl: Dictionary, alpha_mat: bool) -> String:
	var params := ""
	var tint := Color.html(sl["c"])
	if tint != Color.WHITE:
		params += "\t\"$color\" \"[%.3f %.3f %.3f]\"\n" % [tint.r, tint.g, tint.b]
	var a := float(sl["a"]) * (0.5 if alpha_mat and float(sl["a"]) >= 1.0 else 1.0)
	if a < 1.0:
		params += "\t\"$translucent\" \"1\"\n\t\"$alpha\" \"%.2f\"\n" % a
	if float(sl["sp"]) != 0.0:                       # spin: Source turns the texture around each repeat's middle
		params += "\t\"$angle\" \"0\"\n\t\"Proxies\"\n\t{\n\t\t\"LinearRamp\"\n\t\t{\n\t\t\t\"rate\" \"%.2f\"\n" % float(sl["sp"]) \
			+ "\t\t\t\"initialValue\" \"0\"\n\t\t\t\"resultVar\" \"$angle\"\n\t\t}\n\t\t\"TextureTransform\"\n\t\t{\n" \
			+ "\t\t\t\"rotateVar\" \"$angle\"\n\t\t\t\"resultVar\" \"$basetexturetransform\"\n\t\t}\n\t}\n"
	elif float(sl["su"]) != 0.0 or float(sl["sv"]) != 0.0:
		var su := float(sl["su"])
		var sv := float(sl["sv"])
		params += "\t\"Proxies\"\n\t{\n\t\t\"TextureScroll\"\n\t\t{\n\t\t\t\"texturescrollvar\" \"$basetexturetransform\"\n" \
			+ "\t\t\t\"texturescrollrate\" \"%.3f\"\n\t\t\t\"texturescrollangle\" \"%.1f\"\n\t\t}\n\t}\n" % [
				Vector2(su, sv).length(), rad_to_deg(atan2(sv, su))]
	if params == "":
		return _mat_name(sl["id"])
	if not CssLibrary.is_css(sl["id"]):
		params += finish_vmt(MaterialLibrary.finish(sl["id"]))   # (the variant keeps the material's finish)
	if CssLibrary.is_css(sl["id"]):
		return _css_variant(sl["id"], params)
	var name := "%s_v%x" % [String(sl["id"]).to_lower(), hash(params) & 0xffffff]
	variant_materials[name] = {"name": name, "base": String(sl["id"]).to_lower(), "params": params,
		"surface": MaterialLibrary.entry(sl["id"]).get("surface", "concrete")}
	return "MALLET/" + name.to_upper()


## A CS:S material with extra settings: a VMT of our own over the game's texture (only the small .vmt is packed).
func _css_variant(id: String, params: String) -> String:
	var e := MaterialLibrary.entry(id)
	var name := "css_%s_v%x" % [String(id).substr(4).get_file(), hash(id + params) & 0xffffff]
	variant_materials[name] = {"name": name, "basetexture": e.get("basetexture", id.substr(4)), "params": params,
		"surface": e.get("surface", "concrete")}
	return "MALLET/" + name.to_upper()


## A material made just for the map (glass, lava): a plain color.
func _special_material(name: String, c: Color, params: String) -> String:
	variant_materials[name] = {"name": name, "color": c.to_html(false), "params": params, "surface": "glass" if name == "sf_glass" else "concrete"}
	return "MALLET/" + name.to_upper()


static func _box_piece(bx: AABB) -> Array:
	var pts := []
	for i in 8:
		pts.append(bx.position + bx.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
	return Convex.from_points(pts)


## A particle effect as Source's nearest stock entity: fire, smoke stack, sparks, steam, or a rain / snow brush.
func _particle_entities(ps: Dictionary, css: String, kill_y: float) -> Array:
	var pp: Array = ps["position"]
	var at := Vector3(pp[0], pp[1], pp[2])
	var area: Array = ps["area"]
	var size := float(ps["size"])
	var col := Color.html(ps["color"]) if ps["color"] != "" else Color.html(ParticleNode.PRESETS[ps["preset"]]["colors"][1])
	var rgb := "%d %d %d" % [col.r8, col.g8, col.b8]
	match css:
		"env_fire":
			return [_point_entity({"classname": "env_fire", "spawnflags": "13", "firesize": _n(maxf(float(area[0]), float(area[2])) * U * size * 1.5),
				"fireattack": "1", "firetype": "0", "damagescale": "0", "health": "30"}, src(at))]
		"env_smokestack":
			var embers: bool = ps["preset"] == "embers"
			return [_point_entity({"classname": "env_smokestack", "InitialState": "1", "BaseSpread": _n(float(area[0]) * U * 0.5),
				"SpreadSpeed": "15", "Speed": _n(40.0 * float(ps["speed"])), "StartSize": _n((4.0 if embers else 30.0) * size),
				"EndSize": _n((2.0 if embers else 90.0) * size), "Rate": _n((20.0 if embers else 12.0) * float(ps["amount"])),
				"JetLength": _n(120.0 if embers else 180.0), "rendercolor": rgb, "renderamt": "255" if embers else "160",
				"SmokeMaterial": "sprites/glow01.vmt" if embers else "particle/SmokeStack.vmt", "twist": "0", "WindAngle": "0", "WindSpeed": "0"}, src(at))]
		"env_spark":
			return [_point_entity({"classname": "env_spark", "spawnflags": "64", "MaxDelay": "1", "Magnitude": "2", "TrailLength": "1",
				"angles": "-90 0 0"}, src(at))]
		"env_steam":
			return [_point_entity({"classname": "env_steam", "InitialState": "1", "type": "0", "SpreadSpeed": "20",
				"Speed": _n(30.0 * float(ps["speed"])), "StartSize": _n(60.0 * size), "EndSize": _n(160.0 * size),
				"Rate": _n(10.0 * float(ps["amount"])), "JetLength": "120", "rendercolor": rgb, "renderamt": "60", "angles": "-90 0 0"}, src(at))]
		"func_precipitation":                          # a brush from the area down to the kill floor: it rains / snows inside it
			var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(ps["yaw"]))), at)
			var top := float(area[1]) * 0.5
			var bottom := kill_y - at.y
			var corners := []
			for i in 8:
				corners.append(src(xf * Vector3(float(area[0]) * (0.5 if i & 1 else -0.5), top if i & 2 else bottom,
					float(area[2]) * (0.5 if i & 4 else -0.5))))
			return [_brush_entity({"classname": "func_precipitation", "preciptype": "3" if ps["preset"] == "snow" else "0",
				"renderamt": "100", "rendercolor": "100 100 100"}, _hull(corners))]
	return []


func _box_src(bx: AABB, xf: Transform3D) -> Array:
	var out := []
	for i in 8:
		out.append(src(xf * (bx.position + bx.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))))
	return out


## A lava preset in CS:S: a self-lit plain color (Source has no lava shader).
func _lava_material(id: String) -> String:
	var lp: Dictionary = Look.LIQUIDS.get(id, Look.LIQUIDS["lava"])
	return _special_material("sf_lava_" + id, Color.html(lp["color"]), "\t\"$selfillum\" \"1\"\n")


## A water brush: the water surface on top, nothing drawn on the other sides (Source draws the volume itself).
func _water_solid(piece: Array, material := WATER_MATERIAL) -> String:
	var pts := []
	for q in Convex.points(piece):
		pts.append(src(q))
	var sides := _hull(pts)
	var mats := []
	for sd in sides:
		var nrm: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		mats.append(material if nrm.z > 0.7 else NODRAW)
	return _solid(sides, mats)


## Texture axes matching the editor: the same world-aligned projection, size, turn and shift, in Source units
## ("[ax ay az shift] scale", scale = world units per texel).
func _material_axes(nrm: Vector3, fs: Dictionary) -> Array:
	var a := nrm.abs()
	var u: Vector3
	var v: Vector3
	if a.y >= a.x and a.y >= a.z:
		u = Vector3(1, 0, 0)
		v = Vector3(0, -1, 0)
	elif a.x >= a.z:
		u = Vector3(0, -1, 0)
		v = Vector3(0, 0, -1)
	else:
		u = Vector3(1, 0, 0)
		v = Vector3(0, 0, -1)
	var th := deg_to_rad(float(fs["uv_rot"]))
	var u2 := u * cos(th) - v * sin(th)
	var v2 := u * sin(th) + v * cos(th)
	var size: float = MaterialLibrary.world_size(fs["material"]) * maxf(float(fs["uv_scale"]), 0.01)
	var px := MaterialLibrary.texture_px(fs["material"])   # (the game's own size for CS:S materials)
	var scale := size * U / px
	# the map is centered in Source space; shift textures back so they line up exactly as in the editor
	var su: float = _off.dot(u2) / scale + float(fs["uv_offset"][0]) * px
	var sv: float = _off.dot(v2) / scale + float(fs["uv_offset"][1]) * px
	if fs.has("origin"):                                 # a cube object's textures are laid out from its own origin
		var og: Vector3 = fs["origin"]
		var os := Vector3(og.x, -og.z, og.y) * U
		su -= os.dot(u2) / scale
		sv -= os.dot(v2) / scale
	return ["[%s %s %s %s] %s" % [_n(u2.x), _n(u2.y), _n(u2.z), _n(fmod(su, px)), _n6(scale)],
		"[%s %s %s %s] %s" % [_n(v2.x), _n(v2.y), _n(v2.z), _n(fmod(sv, px)), _n6(scale)]]


## Write the library materials a map uses as Source files under `root` (materials/mallet/<id>.vtf + .vmt).
## Returns the written files as [path inside the game, file on disk].
static func write_materials(ids: Array, root: String) -> Array:
	var out := []
	var dir := root.path_join("materials/mallet")
	DirAccess.make_dir_recursive_absolute(dir)
	for id in ids:
		if id is Dictionary and id.has("skybox"):
			out.append_array(_write_skybox(id["skybox"], id["faces"], root))
			continue
		if id is Dictionary:
			out.append_array(_write_variant(id, dir))
			continue
		if CssLibrary.is_css(id):
			continue                                     # (the game's own: nothing to write)
		var img := MaterialLibrary.image(id, "color")
		if img == null:
			continue
		var name: String = String(id).to_lower()
		var vtf := dir.path_join(name + ".vtf")
		var vmt := dir.path_join(name + ".vmt")
		var glow := MaterialLibrary.image(id, "glow")       # glowing parts: the texture's alpha, lit by $selfillum
		var fin := MaterialLibrary.finish(id)
		if glow == null and float(fin["glow"]) > 0.0:     # (light of its own, all over: a white mask)
			glow = Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
			glow.fill(Color.WHITE)
		_write_vtf(img, vtf, glow)
		var f := FileAccess.open(vmt, FileAccess.WRITE)
		f.store_string("\"LightmappedGeneric\"\n{\n\t\"$basetexture\" \"mallet/%s\"\n\t\"$surfaceprop\" \"%s\"\n%s%s}\n" % [name,
			MaterialLibrary.entry(id).get("surface", "concrete"), "\t\"$selfillum\" \"1\"\n" if glow else "", finish_vmt(fin)])
		f.close()
		# a self-lit version for glowing blocks (the same texture, shining)
		var gvmt := dir.path_join(name + "_glow.vmt")
		var g := FileAccess.open(gvmt, FileAccess.WRITE)
		g.store_string("\"LightmappedGeneric\"\n{\n\t\"$basetexture\" \"mallet/%s\"\n\t\"$selfillum\" \"1\"\n\t\"$surfaceprop\" \"%s\"\n}\n" % [name,
			MaterialLibrary.entry(id).get("surface", "concrete")])
		g.close()
		out.append(["materials/mallet/%s_glow.vmt" % name, gvmt])
		out.append(["materials/mallet/%s.vtf" % name, vtf])
		out.append(["materials/mallet/%s.vmt" % name, vmt])
	return out


## A material's finish in Source's words: brightness as $color, reflections as the map's cubemap (stronger the
## glossier), so a reflective material shines in CS:S too. ("" for the plain finish.)
static func finish_vmt(fin: Dictionary) -> String:
	var t := ""
	var b := float(fin.get("bright", 1.0))
	if not is_equal_approx(b, 1.0):
		t += "\t\"$color\" \"[%.3f %.3f %.3f]\"\n" % [b, b, b]
	var r := float(fin.get("reflect", 0.0))
	if r > 0.0:
		var k := r * (0.35 + 0.65 * float(fin.get("gloss", 0.0)))
		t += "\t\"$envmap\" \"env_cubemap\"\n\t\"$envmaptint\" \"[%.3f %.3f %.3f]\"\n" % [k, k, k]
	return t


## A material variant (a library texture with extra settings) or a plain-color material made for the map.
static func _write_variant(d: Dictionary, dir: String) -> Array:
	var out := []
	var name: String = d["name"]
	var base: String = d.get("base", name)
	if d.has("color") or d.has("image"):
		var img: Image = null
		if d.has("image"):
			img = Image.load_from_file(d["image"])
		if img == null or img.is_empty():
			img = Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color.html(d.get("color", "9aa3ad")))
		var vtf := dir.path_join(name + ".vtf")
		_write_vtf(img, vtf)
		out.append(["materials/mallet/%s.vtf" % name, vtf])
	var vmt := dir.path_join(name + ".vmt")
	var f := FileAccess.open(vmt, FileAccess.WRITE)
	f.store_string("\"LightmappedGeneric\"\n{\n\t\"$basetexture\" \"%s\"\n\t\"$surfaceprop\" \"%s\"\n%s}\n" % [
		d.get("basetexture", "mallet/" + base), d.get("surface", "concrete"), d.get("params", "")])   # (CS:S variants: the game's texture)
	f.close()
	out.append(["materials/mallet/%s.vmt" % name, vmt])
	return out


## A baked skybox (Look.bake_skybox): materials/skybox/<name><rt / bk / lf / ft / up / dn>, unlit and unfogged,
## stored uncompressed (smooth sky gradients band badly in DXT1).
static func _write_skybox(name: String, faces: Dictionary, root: String) -> Array:
	var out := []
	var dir := root.path_join("materials/skybox")
	DirAccess.make_dir_recursive_absolute(dir)
	for sfx in faces:
		var img: Image = (faces[sfx] as Image).duplicate()
		img.convert(Image.FORMAT_RGB8)
		var w := img.get_width()
		var h := img.get_height()
		var px := img.get_data()
		for i in w * h:                                  # RGB -> BGR (Source's BGR888)
			var r := px[i * 3]
			px[i * 3] = px[i * 3 + 2]
			px[i * 3 + 2] = r
		var hd := StreamPeerBuffer.new()
		hd.big_endian = false
		hd.put_data("VTF".to_ascii_buffer())
		hd.put_u8(0)
		hd.put_u32(7)
		hd.put_u32(2)
		hd.put_u32(80)
		hd.put_u16(w)
		hd.put_u16(h)
		hd.put_u32(0x4 | 0x8 | 0x100 | 0x200)            # clamp s / t, no mipmaps, no lower detail levels
		hd.put_u16(1)
		hd.put_u16(0)
		hd.put_u32(0)
		for k in 3:
			hd.put_float(0.5)
		hd.put_u32(0)
		hd.put_float(1.0)
		hd.put_u32(3)                                    # BGR888
		hd.put_u8(1)                                     # one mip level
		hd.put_u32(0xFFFFFFFF)
		hd.put_u8(0)
		hd.put_u8(0)
		hd.put_u16(1)
		while hd.get_size() < 80:
			hd.put_u8(0)
		var vtf := dir.path_join(name + sfx + ".vtf")
		var f := FileAccess.open(vtf, FileAccess.WRITE)
		f.store_buffer(hd.data_array)
		f.store_buffer(px)
		f.close()
		var vmt := dir.path_join(name + sfx + ".vmt")
		var g := FileAccess.open(vmt, FileAccess.WRITE)
		g.store_string("\"UnlitGeneric\"\n{\n\t\"$basetexture\" \"skybox/%s%s\"\n\t\"$nofog\" \"1\"\n\t\"$ignorez\" \"1\"\n}\n" % [name, sfx])
		g.close()
		out.append(["materials/skybox/%s%s.vtf" % [name, sfx], vtf])
		out.append(["materials/skybox/%s%s.vmt" % [name, sfx], vmt])
	return out


## A Valve texture file (VTF 7.2): DXT1-compressed with a full mipmap chain, smallest mip first.
## With `glow`: DXT5, the glow map's brightness in the alpha channel (Source's $selfillum lights those parts).
static func _write_vtf(src_img: Image, path: String, glow: Image = null) -> void:
	var img: Image = src_img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.resize(VTF_SIZE, VTF_SIZE, Image.INTERPOLATE_LANCZOS)
	var dxt5 := glow != null
	if dxt5:
		var mask: Image = glow.duplicate()
		if mask.is_compressed():
			mask.decompress()
		mask.convert(Image.FORMAT_RGB8)
		mask.resize(VTF_SIZE, VTF_SIZE, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGBA8)
		var px := img.get_data()
		var mk := mask.get_data()
		for i in VTF_SIZE * VTF_SIZE:
			px[i * 4 + 3] = maxi(mk[i * 3], maxi(mk[i * 3 + 1], mk[i * 3 + 2]))
		img = Image.create_from_data(VTF_SIZE, VTF_SIZE, false, Image.FORMAT_RGBA8, px)
	img.generate_mipmaps()
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
	dxt5 = img.get_format() == Image.FORMAT_DXT5          # (a mask with no dark parts compresses to DXT1)
	var data := img.get_data()
	var levels := img.get_mipmap_count() + 1
	var chunks := []
	var at := 0
	for l in levels:
		var w := maxi(VTF_SIZE >> l, 1)
		var size := maxi((w + 3) / 4, 1) * maxi((w + 3) / 4, 1) * (16 if dxt5 else 8)
		chunks.append(data.slice(at, at + size))
		at += size
	var h := StreamPeerBuffer.new()
	h.big_endian = false
	h.put_data("VTF".to_ascii_buffer())
	h.put_u8(0)
	h.put_u32(7)
	h.put_u32(2)
	h.put_u32(80)                         # header size
	h.put_u16(VTF_SIZE)
	h.put_u16(VTF_SIZE)
	h.put_u32(0x2000 if dxt5 else 0)      # flags (EIGHTBITALPHA when the alpha holds the glow mask)
	h.put_u16(1)                          # frames
	h.put_u16(0)                          # first frame
	h.put_u32(0)                          # padding
	for k in 3:
		h.put_float(0.5)                  # reflectivity
	h.put_u32(0)                          # padding
	h.put_float(1.0)                      # bumpmap scale
	h.put_u32(15 if dxt5 else 13)         # high-res format: DXT5 / DXT1
	h.put_u8(levels)
	h.put_u32(0xFFFFFFFF)                 # no low-res thumbnail
	h.put_u8(0)
	h.put_u8(0)
	h.put_u16(1)                          # depth
	while h.get_size() < 80:
		h.put_u8(0)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(h.data_array)
	for l in range(levels - 1, -1, -1):  # smallest first
		f.store_buffer(chunks[l])
	f.close()


# ------------------------------------------------------------------------------------------------ text
func _next() -> int:
	_id += 1
	return _id


## A texture scale: small ones (textures fitted to a small face) need more than 3 decimals, or the rounding slides
## the texture across faces far from the map's middle.
static func _n6(v: float) -> String:
	var s := "%.6f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


static func _n(v: float) -> String:
	var s := "%.3f" % v
	s = s.rstrip("0").rstrip(".")
	return "0" if s == "-0" or s == "" else s


func _vec(v: Vector3) -> String:
	return "%s %s %s" % [_n(v.x), _n(v.y), _n(v.z)]


## Texture axes for a face: projected along its dominant axis, like Hammer's world alignment.
static func _axes(nrm: Vector3) -> Array:
	var a := nrm.abs()
	if a.z >= a.x and a.z >= a.y:
		return ["[1 0 0 0] 0.25", "[0 -1 0 0] 0.25"]
	if a.x >= a.y:
		return ["[0 1 0 0] 0.25", "[0 0 -1 0] 0.25"]
	return ["[1 0 0 0] 0.25", "[0 0 -1 0] 0.25"]


## A brush. `material` is one name for every side, or an Array of one per side; `side_axes` optionally gives each
## side's texture axes.
func _solid(sides: Array, material, side_axes: Array = []) -> String:
	if sides.size() < 4:
		return ""
	brushes += 1
	var t := PackedStringArray(["\tsolid\n\t{\n\t\t\"id\" \"%d\"\n" % _next()])
	for si in sides.size():
		var sd: Array = sides[si]
		var nrm: Vector3 = (sd[2] - sd[0]).cross(sd[1] - sd[0]).normalized()
		var ax: Array = side_axes[si] if si < side_axes.size() else _axes(nrm)
		var mat_name: String = material[si] if material is Array else material
		t.append("\t\tside\n\t\t{\n\t\t\t\"id\" \"%d\"\n\t\t\t\"plane\" \"(%s) (%s) (%s)\"\n\t\t\t\"material\" \"%s\"\n\t\t\t\"uaxis\" \"%s\"\n\t\t\t\"vaxis\" \"%s\"\n\t\t\t\"rotation\" \"0\"\n\t\t\t\"lightmapscale\" \"16\"\n\t\t\t\"smoothing_groups\" \"0\"\n\t\t}\n"
			% [_next(), _vec(sd[0]), _vec(sd[1]), _vec(sd[2]), mat_name, ax[0], ax[1]])
	t.append("\t\teditor\n\t\t{\n\t\t\t\"color\" \"0 180 255\"\n\t\t\t\"visgroupshown\" \"1\"\n\t\t\t\"visgroupautoshown\" \"1\"\n\t\t}\n\t}\n")
	return "".join(t)


func _keys(kv: Dictionary) -> String:
	var t := PackedStringArray()
	for k in kv:
		t.append("\t\"%s\" \"%s\"\n" % [k, kv[k]])
	return "".join(t)


func _brush_entity(kv: Dictionary, sides: Array) -> String:
	var body := _solid(sides, TRIGGER_MATERIAL).replace("\n\t", "\n\t")
	return "entity\n{\n\t\"id\" \"%d\"\n%s%s}\n" % [_next(), _keys(kv), body]


func _point_entity(kv: Dictionary, origin: Vector3, connections: Array = []) -> String:
	var c := ""
	if not connections.is_empty():
		c = "\tconnections\n\t{\n\t\t" + "\n\t\t".join(PackedStringArray(connections)) + "\n\t}\n"
	return "entity\n{\n\t\"id\" \"%d\"\n%s\t\"origin\" \"%s\"\n%s}\n" % [_next(), _keys(kv), _vec(origin), c]


# ------------------------------------------------------------------------------------------------ compile
## Where CS:S is installed ("" if it can't be found). Looks in the usual Steam library folders.
static func find_css() -> String:
	var roots := ["D:/SteamLibrary/steamapps/common", "C:/Program Files (x86)/Steam/steamapps/common", "E:/SteamLibrary/steamapps/common",
		"C:/SteamLibrary/steamapps/common", "F:/SteamLibrary/steamapps/common"]
	for r in roots:
		var p: String = r + "/Counter-Strike Source"
		if FileAccess.file_exists(p + "/bin/x64/vbsp.exe") or FileAccess.file_exists(p + "/bin/vbsp.exe"):
			return p
	return ""


## Compile a .vmf with CS:S's own tools and copy the .bsp into cstrike/maps. Blocking: run it on a thread.
## `quality` "fast" (quick lighting) or "final". Returns {"error": "", "bsp": path, "log": text}.
static func compile(vmf: String, css: String, quality := "fast", materials: Array = []) -> Dictionary:
	var bin := css + "/bin/x64/" if FileAccess.file_exists(css + "/bin/x64/vbsp.exe") else css + "/bin/"
	var game := css + "/cstrike"
	var log := PackedStringArray()
	# custom textures: into cstrike/materials/mallet so vbsp / vrad find them, and packed into the map below
	var packed := write_materials(materials, game) if not materials.is_empty() else []
	var steps := [["vbsp.exe", ["-game", game, vmf]], ["vvis.exe", (["-fast"] if quality == "fast" else []) + ["-game", game, vmf]],
		["vrad.exe", (["-fast"] if quality == "fast" else ["-final"]) + ["-game", game, vmf]]]
	for st in steps:
		var out := []
		var code := OS.execute(bin + st[0], PackedStringArray(st[1]), out, true)
		var text: String = "".join(out)
		log.append("==== %s (exit %d)\n%s" % [st[0], code, text])
		if text.contains("LEAKED") or text.contains("**** leaked ****"):
			return {"error": "The map leaked (something reached outside the sky box).", "bsp": "", "log": "\n".join(log)}
		if code != 0:
			return {"error": "%s failed (exit code %d). See the compile log." % [st[0], code], "bsp": "", "log": "\n".join(log)}
	var bsp := vmf.get_basename() + ".bsp"
	if not FileAccess.file_exists(bsp):
		return {"error": "The compile finished but no .bsp was made. See the compile log.", "bsp": "", "log": "\n".join(log)}
	if not packed.is_empty():
		# pack the textures into the map so anyone who downloads it sees them
		var list := vmf.get_basename() + "_pack.txt"
		var lf := FileAccess.open(list, FileAccess.WRITE)
		for pair in packed:
			lf.store_string("%s\n%s\n" % [pair[0], ProjectSettings.globalize_path(pair[1])])
		lf.close()
		var pout := []
		var packed_bsp := bsp.get_basename() + "_packed.bsp"
		var code := OS.execute(bin + "bspzip.exe", PackedStringArray(["-game", game, "-addlist", bsp, list, packed_bsp]), pout, true)
		log.append("==== bspzip (exit %d)\n%s" % [code, "".join(pout)])
		if code == 0 and FileAccess.file_exists(packed_bsp):
			DirAccess.remove_absolute(bsp)
			DirAccess.rename_absolute(packed_bsp, bsp)
		else:
			return {"error": "Couldn't pack the textures into the map (bspzip exit %d)." % code, "bsp": "", "log": "\n".join(log)}
	var dest := game + "/maps/" + bsp.get_file()
	var err := DirAccess.copy_absolute(bsp, dest)
	if err != OK:
		return {"error": "Built %s but couldn't copy it into cstrike/maps (%s)." % [bsp.get_file(), error_string(err)], "bsp": bsp, "log": "\n".join(log)}
	return {"error": "", "bsp": dest, "log": "\n".join(log)}
