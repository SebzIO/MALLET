class_name SurfsUpExporter
extends RefCounted
## Turns a MALLET map (the plain .mallet dictionary) into a SurfsUp map pack: <Maps>/<name>.pck containing
## one self-contained scene at res://Levels/<name>.tscn, loaded in game with `map <name>`.
##
## Rules learned from SurfsUp 2.1:
##  * no scripts anywhere in the pack (the game refuses "unsafe" packs), so everything is plain nodes + metadata
##  * the scene root needs a Marker3D called SpawnPoint
##  * gameplay zones are Area3Ds (collision layer 0, mask 2) tagged with metadata `sdk_zone`
##    (start / finish / kill / booster / ...) plus that zone's settings, the same format MapCraft writes
##  * after replacing a pack, SurfsUp must be restarted (it caches the pack's file table)

const KILL_MARGIN := 60.0            ## kill floor this far below the lowest part of the map
const ZONE_HEIGHT := 10.0


static func valid_name(n: String) -> bool:
	var re := RegEx.create_from_string("^[A-Za-z0-9_\\-]{1,64}$")
	return re.search(n) != null


## Problems that would make the map unplayable (empty = good to export).
static func check(map: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var kinds := []
	for e in map.get("entities", []):
		kinds.append(e.get("kind", ""))
	if not "start" in kinds:
		out.append("The map needs a start platform (press B).")
	if not "finish" in kinds:
		out.append("The map needs a finish platform (press M).")
	if map.get("ramps", []).is_empty() and map.get("blocks", []).is_empty() and map.get("cubes", {}).is_empty() \
			and map.get("cube_models", []).is_empty():
		out.append("The map has nothing to surf on yet (no ramps, blocks or cubes).")
	var stages := []
	var plates := []
	for e in map.get("entities", []):
		if e.get("kind", "") == "stage":
			var num := int(e.get("number", 2))
			if not e.get("zone_only", false):
				if num in plates:
					out.append("Two stage plates are both numbered %d." % num)
				plates.append(num)
			if not num in stages:                        # (several zone boxes can share a number: one zone)
				stages.append(num)
	stages.sort()
	for i in stages.size():
		if stages[i] != i + 2:
			out.append("Stage numbers must run 2, 3, 4... without gaps (stage %d is missing)." % (i + 2))
			break
	for pd in map.get("props", []):
		var err: String = PropLoader.load_model(pd.get("source", ""))["error"]
		if err != "":
			out.append("A prop can't be exported: %s" % err)
	for e in map.get("entities", []):
		if e.get("kind", "") == "teleport" and not int(e.get("number", 2)) in stages:
			out.append("A teleport goes to stage %d, but there is no stage %d plate." % [int(e.get("number", 2)), int(e.get("number", 2))])
	return out


## Builds the scene tree. Every node is owned by the returned root so it can be packed.
static func build_scene(map: Dictionary, map_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = map_name
	root.set_meta("made_with", MalletVersion.full())
	var lowest := INF

	var look_env: Dictionary = Look.default_environment()
	look_env.merge(map.get("environment", {}), true)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Look.build_environment(look_env)
	_add(root, root, env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	Look.apply_sun(sun, look_env)
	_add(root, root, sun)

	# ramps: mesh + trimesh collision, one StaticBody each
	var ramps := Node3D.new()
	ramps.name = "Ramps"
	_add(root, root, ramps)
	var i := 0
	for rd in map.get("ramps", []):
		var pts := PackedVector3Array()
		for p in rd.get("points", []):
			pts.append(Vector3(p[0], p[1], p[2]))
		if pts.size() < 2:
			continue
		var sp := RampShape.spec(rd)
		var geo := RampShape.build(pts, sp)
		var ridge: PackedVector3Array = geo["ridge"]
		var mesh: ArrayMesh = geo["mesh"]
		var mat := Look.ramp_material(rd.get("look", "color"), Color.html(rd.get("color", "edebe3")), rd.get("texture", ""),
			rd.get("tex_scale", 20.0), rd.get("material", ""), float(sp["face_length"]))
		mesh.surface_set_material(0, mat)
		var body := StaticBody3D.new()
		body.name = "Ramp%d" % i
		_add(root, ramps, body)
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		_add(root, body, mi)
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = mesh.create_trimesh_shape()
		_add(root, body, cs)
		for p in ridge:
			lowest = min(lowest, p.y - RampShape.depth_below_spine(sp))
		i += 1

	# platforms + their zones (a zone-only entity is just the zone, on a platform the mapper built; several boxes of
	# one kind / stage number make one zone)
	var spawn: Transform3D
	var have_spawn := false
	var markers := {}                                    # stage number -> its respawn marker is made
	var used_names := {}
	for ed in _plates_first(map.get("entities", [])):
		var kind: String = ed.get("kind", "")
		var pa: Array = ed.get("position", [0, 0, 0])
		var sa: Array = ed.get("size", [20, 2, 26])
		var pos := Vector3(pa[0], pa[1], pa[2])
		var size := Vector3(sa[0], sa[1], sa[2])
		var basis := Basis(Vector3.UP, deg_to_rad(ed.get("yaw", 0.0)))
		var zone_only: bool = ed.get("zone_only", false) and kind in ["start", "finish", "stage"]
		var zh := size.y if zone_only else ZONE_HEIGHT
		lowest = min(lowest, pos.y - size.y)
		if kind == "stage" and zone_only:
			var znum := int(ed.get("number", 2))
			if not markers.has(znum):
				markers[znum] = true
				var zm := Marker3D.new()
				zm.name = "Stage%d" % znum
				zm.transform = Transform3D(basis, pos + basis * Vector3(0, 0.1, size.z * 0.25))
				_add(root, root, zm)
			var zxf2 := Transform3D(basis, pos + Vector3(0, zh / 2, 0))
			var zsize2 := Vector3(size.x, zh, size.z)
			var resp2 := _zone(root, _unique(used_names, "Stage%dCheckpoint" % znum), "respawn", zxf2, zsize2)
			resp2.set_meta("respawn", "Stage%d" % znum)
			resp2.set_meta("is_alt_spawn", false)
			resp2.set_meta("bhop_area", false)
			var split2 := _zone(root, _unique(used_names, "Stage%dSplit" % znum), "split", zxf2, zsize2)
			split2.set_meta("split_index", znum - 2)
			split2.set_meta("course_id", 0)
			continue
		if kind in ["start", "finish"] and zone_only:
			var zz := _zone(root, _unique(used_names, "StartZone" if kind == "start" else "FinishZone"), kind,
				Transform3D(basis, pos + Vector3(0, zh / 2, 0)), Vector3(size.x, zh, size.z))
			zz.set_meta("course_id", 0)
			if kind == "start":
				zz.set_meta("play_sfx", true)
				zz.set_meta("run_direction", Vector3.ZERO)
				if not have_spawn:
					spawn = Transform3D(basis, pos + basis * Vector3(0, 0.1, size.z * 0.25))
					have_spawn = true
			continue
		if kind == "stage":
			var num := int(ed.get("number", 2))
			markers[num] = true
			var plat := StaticBody3D.new()
			plat.name = "Stage%dPlate" % num
			plat.transform = Transform3D(basis, pos)
			_add(root, root, plat)
			var box := BoxMesh.new()
			box.size = size
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.62, 0.38, 0.95)
			box.material = pm
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = box
			mi.position = Vector3(0, -size.y / 2, 0)
			_add(root, plat, mi)
			var shape := BoxShape3D.new()
			shape.size = size
			var cs := CollisionShape3D.new()
			cs.name = "Collision"
			cs.shape = shape
			cs.position = mi.position
			_add(root, plat, cs)
			# respawn point on the plate, named so teleports and the respawn zone can find it
			var marker := Marker3D.new()
			marker.name = "Stage%d" % num
			marker.transform = Transform3D(basis, pos + basis * Vector3(0, 0.1, size.z * 0.25))
			_add(root, root, marker)
			var zxf := Transform3D(basis, pos + Vector3(0, ZONE_HEIGHT / 2, 0))
			var zsize := Vector3(size.x, ZONE_HEIGHT, size.z)
			var resp := _zone(root, _unique(used_names, "Stage%dCheckpoint" % num), "respawn", zxf, zsize)
			resp.set_meta("respawn", "Stage%d" % num)
			resp.set_meta("is_alt_spawn", false)
			resp.set_meta("bhop_area", false)
			var split := _zone(root, _unique(used_names, "Stage%dSplit" % num), "split", zxf, zsize)
			split.set_meta("split_index", num - 2)
			split.set_meta("course_id", 0)
			continue
		if kind in ["start", "finish"]:
			var plat := StaticBody3D.new()
			plat.name = "StartPlatform" if kind == "start" else "FinishPlatform"
			plat.transform = Transform3D(basis, pos)
			_add(root, root, plat)
			var box := BoxMesh.new()
			box.size = size
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.25, 0.75, 0.4) if kind == "start" else Color(0.25, 0.5, 0.95)
			box.material = pm
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			mi.mesh = box
			mi.position = Vector3(0, -size.y / 2, 0)
			_add(root, plat, mi)
			var shape := BoxShape3D.new()
			shape.size = size
			var cs := CollisionShape3D.new()
			cs.name = "Collision"
			cs.shape = shape
			cs.position = mi.position
			_add(root, plat, cs)
			var zone := _zone(root, _unique(used_names, "StartZone" if kind == "start" else "FinishZone"), "start" if kind == "start" else "finish",
				Transform3D(basis, pos + Vector3(0, ZONE_HEIGHT / 2, 0)), Vector3(size.x, ZONE_HEIGHT, size.z))
			zone.set_meta("course_id", 0)
			if kind == "start":
				zone.set_meta("play_sfx", true)
				zone.set_meta("run_direction", Vector3.ZERO)
				if not have_spawn:
					spawn = Transform3D(basis, pos + basis * Vector3(0, 0.1, size.z * 0.25))
					have_spawn = true

	# kill zones and boosters: invisible trigger volumes, exactly as SurfsUp's own zone types
	var n_kill := 0
	var n_boost := 0
	var n_tp := 0
	for ed in map.get("entities", []):
		var kind: String = ed.get("kind", "")
		if not kind in ["kill", "booster", "teleport"]:
			continue
		var pa: Array = ed.get("position", [0, 0, 0])
		var sa: Array = ed.get("size", [20, 20, 20])
		var basis := Basis(Vector3.UP, deg_to_rad(ed.get("yaw", 0.0)))
		var xf := Transform3D(basis, Vector3(pa[0], pa[1], pa[2]))
		if kind == "teleport":
			var target := "Stage%d" % int(ed.get("number", 2))
			var dest_yaw := 0.0
			for other in map.get("entities", []):
				if other.get("kind", "") == "stage" and int(other.get("number", 2)) == int(ed.get("number", 2)):
					dest_yaw = other.get("yaw", 0.0)
			if ed.get("keep_speed", true):
				# SurfsUp's plain teleport always stops the player; the point teleport can keep their velocity
				var z := _zone(root, "TeleportTo%s_%d" % [target, n_tp], "point_tp", xf, Vector3(sa[0], sa[1], sa[2]))
				z.set_meta("target", target)
				z.set_meta("reset_velocity_on_teleport", false)
				z.set_meta("reset_view_on_teleport", true)
				z.set_meta("horizontal_view_override", float(dest_yaw))
				z.set_meta("cancel_run", false)
			else:
				var z := _zone(root, "TeleportTo%s_%d" % [target, n_tp], "teleport", xf, Vector3(sa[0], sa[1], sa[2]))
				z.set_meta("next_stage", target)
				z.set_meta("kill_velocity", true)
				z.set_meta("align_to_spawn", true)
				z.set_meta("do_not_set_spawn", false)
				z.set_meta("keep_offset", false)
				z.set_meta("cancel_run", false)
				z.set_meta("to_current_stage", false)
			n_tp += 1
			continue
		if kind == "kill":
			var z := _zone(root, "KillZone%d" % n_kill, "kill", xf, Vector3(sa[0], sa[1], sa[2]))
			z.set_meta("kill_kind", "killbox")
			z.set_meta("play_sfx", true)
			n_kill += 1
		else:
			var z := _zone(root, "Booster%d" % n_boost, "booster", xf, Vector3(sa[0], sa[1], sa[2]))
			var dir := (basis * (Basis(Vector3.RIGHT, deg_to_rad(ed.get("pitch", 20.0))) * Vector3.FORWARD)).normalized()
			z.set_meta("boost_velocity", float(ed.get("strength", 1000.0)))
			z.set_meta("boost_mode", int(ed.get("mode", 0)))
			z.set_meta("boost_direction", dir)
			z.set_meta("freeze_gravity", true)
			z.set_meta("boost_on_exit", false)
			n_boost += 1

	# blocks: a mesh and an exact convex collision shape per piece (cutters only cut, they aren't built)
	var blocks := Node3D.new()
	blocks.name = "Blocks"
	_add(root, root, blocks)
	var cutters := []
	for bd in map.get("blocks", []):
		if BlockShape.spec(bd)["cutter"]:
			cutters.append(bd)
	var bi := 0
	for bd in map.get("blocks", []):
		var bs := BlockShape.spec(bd)
		if bs["cutter"]:
			continue
		var bxf := BlockShape.transform_of(bs)
		var pieces := BlockShape.world_pieces(bs, cutters)
		if pieces.is_empty():
			continue
		var water: bool = bs.get("water", false)
		var body: Node3D = Node3D.new() if water else StaticBody3D.new()
		body.name = ("Water%d" if water else "Block%d") % bi
		body.transform = bxf
		_add(root, blocks, body)
		if water and bs.get("deadly", false):
			# lava / acid: a kill zone filling the volume
			var kz := _zone(root, "Deadly%d" % bi, "kill", bxf * Transform3D(Basis(), Vector3(0, float(bs["size"][1]) * 0.5, 0)),
				Vector3(bs["size"][0], bs["size"][1], bs["size"][2]))
			kz.set_meta("kill_kind", "killbox")
		var bm: ArrayMesh = BlockShape.mesh_faces(pieces, bxf, bs)[0]
		var bmi := MeshInstance3D.new()
		bmi.name = "Mesh"
		bmi.mesh = bm
		_add(root, body, bmi)
		var inv := bxf.affine_inverse()
		var pn := 0
		for piece in (pieces if not water else []):
			var shape := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for v in Convex.points(piece):
				pts.append(inv * v)
			shape.points = pts
			var cs := CollisionShape3D.new()
			cs.name = "Piece%d" % pn
			cs.shape = shape
			_add(root, body, cs)
			pn += 1
		bi += 1

	# cube objects (build mode): a mesh per 16 m chunk, an exact convex collision shape per cube (none inside noclip),
	# box walls for glass / clip / gameclip, kill zones for lava / death
	var cube_items := CubeWorld.models_of(map)
	if not cube_items.is_empty():
		var cube_root := Node3D.new()
		cube_root.name = "Cubes"
		_add(root, root, cube_root)
		var oi := 0
		for item in cube_items:
			var cw: CubeWorld = item[0]
			var cxf: Transform3D = item[1]
			cw.show_mats = false
			var obj := Node3D.new()
			obj.name = "CubeObject%d" % oi
			obj.transform = cxf
			_add(root, cube_root, obj)
			var ci := 0
			for ck in cw.render_chunks():
				var got := cw.chunk_mesh(ck)
				var body := StaticBody3D.new()
				body.name = "Chunk%d" % ci
				_add(root, obj, body)
				var cmi := MeshInstance3D.new()
				cmi.name = "Mesh"
				cmi.mesh = got[0]
				_add(root, body, cmi)
				var pn := 0
				for k in cw.chunk_cubes(ck):
					if cw.cube_in_mat(k, "noclip"):
						continue
					var shape := ConvexPolygonShape3D.new()
					shape.points = cw.cube_points(k)
					var ccs := CollisionShape3D.new()
					ccs.name = "Cube%d" % pn
					ccs.shape = shape
					_add(root, body, ccs)
					pn += 1
				ci += 1
			var boxes := cw.material_boxes()
			var walls := StaticBody3D.new()
			walls.name = "Walls"
			_add(root, obj, walls)
			var wn := 0
			for m in ["glass", "clip", "gameclip"]:
				for bx in boxes.get(m, []):
					var bs := BoxShape3D.new()
					bs.size = (bx as AABB).size
					var wcs := CollisionShape3D.new()
					wcs.name = "%s%d" % [m.capitalize(), wn]
					wcs.shape = bs
					wcs.position = (bx as AABB).get_center()
					_add(root, walls, wcs)
					wn += 1
			var dn := 0
			for m in ["lava", "death"]:
				for bx in boxes.get(m, []):
					var kz := _zone(root, "Deadly%d_%d" % [oi, dn], "kill", cxf * Transform3D(Basis(), (bx as AABB).get_center()), (bx as AABB).size)
					kz.set_meta("kill_kind", "killbox")
					dn += 1
			oi += 1

	# lights
	var lights := Node3D.new()
	lights.name = "Lights"
	_add(root, root, lights)
	var li := 0
	for ld in map.get("lights", []):
		var ls := LightNode.spec(ld)
		var l := LightNode.make_light(ls)
		l.name = "Light%d" % li
		var lp: Array = ls["position"]
		l.transform = Transform3D(LightNode.basis_of(ls), Vector3(lp[0], lp[1], lp[2]))
		_add(root, lights, l)
		li += 1

	# text: the letters' mesh, and for solid 3D text an exact convex collision shape per piece 
	var texts := Node3D.new()
	texts.name = "Texts"
	_add(root, root, texts)
	var ti := 0
	for td in map.get("texts", []):
		var ts := TextShape.spec(td)
		if String(ts["text"]).strip_edges() == "":
			continue
		var txf := TextShape.transform_of(ts)
		var solid: bool = ts["mode"] == "3d" and bool(ts["solid"])
		var holder: Node3D = StaticBody3D.new() if solid else Node3D.new()
		holder.name = "Text%d" % ti
		holder.transform = txf
		_add(root, texts, holder)
		var tmi := MeshInstance3D.new()
		tmi.name = "Mesh"
		tmi.mesh = TextShape.mesh(ts)
		tmi.material_override = TextShape.material(ts)
		_add(root, holder, tmi)
		if solid:
			var tinv := txf.affine_inverse()
			var tn := 0
			for piece in TextShape.solid_pieces(ts):
				var shape := ConvexPolygonShape3D.new()
				var pts := PackedVector3Array()
				for v in Convex.points(piece):
					pts.append(tinv * v)
				shape.points = pts
				var cs := CollisionShape3D.new()
				cs.name = "Piece%d" % tn
				cs.shape = shape
				_add(root, holder, cs)
				tn += 1
		ti += 1

	# props: the models' meshes (textures compressed) and, if solid, their collision
	var props := Node3D.new()
	props.name = "Props"
	_add(root, root, props)
	var pi := 0
	for pd in map.get("props", []):
		var src: String = pd.get("source", "")
		var meshes := PropLoader.export_meshes(src)
		if meshes.is_empty():
			continue
		var p: Array = pd.get("position", [0, 0, 0])
		var size: float = pd.get("size", 1.0)
		var holder: Node3D = StaticBody3D.new() if pd.get("solid", true) else Node3D.new()
		holder.name = "Prop%d" % pi
		holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(pd.get("yaw", 0.0))), Vector3(p[0], p[1], p[2]))
		_add(root, props, holder)
		var b := Basis().scaled(Vector3.ONE * size)
		var mi_n := 0
		for m in meshes:
			var mi := MeshInstance3D.new()
			mi.name = "Mesh%d" % mi_n
			mi.mesh = m[0]
			mi.transform = Transform3D(b, Vector3.ZERO) * (m[1] as Transform3D)
			_add(root, holder, mi)
			mi_n += 1
		if holder is StaticBody3D:
			var cs := CollisionShape3D.new()
			cs.name = "Collision"
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(PropLoader.collision_faces(src, size))
			shape.backface_collision = true
			cs.shape = shape
			_add(root, holder, cs)
		pi += 1

	var sp := Marker3D.new()
	sp.name = "SpawnPoint"
	sp.transform = spawn
	_add(root, root, sp)

	# kill floor: an infinite plane well below everything
	var kill := Area3D.new()
	kill.name = "KillFloor"
	kill.collision_layer = 0
	kill.collision_mask = 2
	kill.set_meta("sdk_zone", "kill")
	kill.set_meta("kill_kind", "killbox")
	kill.position = Vector3(0, kill_floor_y(map), 0)
	_add(root, root, kill)
	var plane := CollisionShape3D.new()
	plane.name = "Plane"
	plane.shape = WorldBoundaryShape3D.new()
	_add(root, kill, plane)
	return root


## Height of the automatic kill floor: KILL_MARGIN below the lowest ramp or platform.
## `models`: the cube objects as [CubeWorld, Transform3D] when the caller has them already (the editor's live ones);
## otherwise they're read from the map (slow for big ones: every cube is parsed).
static func kill_floor_y(map: Dictionary, models = null) -> float:
	var lowest := INF
	for rd in map.get("ramps", []):
		for p in rd.get("points", []):
			lowest = min(lowest, p[1] - RampShape.depth_below_spine(RampShape.spec(rd)) - 20.0)
	for ed in map.get("entities", []):
		if ed.get("kind", "") in ["start", "finish", "stage"]:
			lowest = min(lowest, ed["position"][1] - ed["size"][1])
	for bd in map.get("blocks", []):
		if not bd.get("cutter", false):
			lowest = min(lowest, float(bd.get("position", [0, 0, 0])[1]) - 20.0)
	for item in (models if models != null else CubeWorld.models_of(map)):
		var cw: CubeWorld = item[0]
		if cw.count() == 0 and cw.mats.is_empty():
			continue
		var bb := cw.bounds()
		for i in 8:
			var c: Vector3 = (item[1] as Transform3D) * (bb.position + bb.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
			lowest = min(lowest, c.y - 20.0)
	return (0.0 if lowest == INF else lowest) - KILL_MARGIN


## Entities with the plates (not zone-only boxes) first, so a plate is where the player spawns / respawns.
static func _plates_first(ents: Array) -> Array:
	return ents.filter(func(e): return not e.get("zone_only", false)) + ents.filter(func(e): return e.get("zone_only", false))


## `base`, or base2, base3... if it's been used (several boxes of one zone).
static func _unique(used: Dictionary, base: String) -> String:
	var n: int = used.get(base, 0) + 1
	used[base] = n
	return base if n == 1 else "%s%d" % [base, n]


static func _zone(root: Node, name: String, kind: String, xf: Transform3D, size: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = name
	a.transform = xf
	a.collision_layer = 0
	a.collision_mask = 2
	a.set_meta("sdk_zone", kind)
	_add(root, root, a)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = shape
	_add(root, a, cs)
	return a


static func _add(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


## Writes <maps_dir>/<map_name>.pck. Returns "" on success or an error message.
static func export_pack(map: Dictionary, map_name: String, maps_dir: String) -> String:
	if not valid_name(map_name):
		return "Map names can only use letters, numbers, _ and - (no spaces)."
	var problems := check(map)
	if not problems.is_empty():
		return "\n".join(problems)
	if not DirAccess.dir_exists_absolute(maps_dir):
		return "SurfsUp's Maps folder wasn't found:\n%s" % maps_dir
	var root := build_scene(map, map_name)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return "Could not build the map scene (error %d)." % err
	var tmp_dir := OS.get_user_data_dir().path_join("export")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tmp_scene := tmp_dir.path_join(map_name + ".tscn")
	err = ResourceSaver.save(packed, tmp_scene)
	if err != OK:
		return "Could not save the map scene (error %d)." % err
	var pck_path := maps_dir.path_join(map_name + ".pck")
	var packer := PCKPacker.new()
	err = packer.pck_start(pck_path)
	if err != OK:
		return "Could not write %s (error %d). Is the file in use?" % [pck_path, err]
	packer.add_file("res://Levels/%s.tscn" % map_name, tmp_scene)
	err = packer.flush()
	if err != OK:
		return "Could not finish writing %s (error %d)." % [pck_path, err]
	return ""


## Best guess at SurfsUp's Maps folder: Steam's default libraries, then any drive's SteamLibrary.
static func guess_maps_dir() -> String:
	var candidates := ["C:/Program Files (x86)/Steam/steamapps/common/SurfsUp/Maps"]
	for d in "CDEFGH":
		candidates.append("%s:/SteamLibrary/steamapps/common/SurfsUp/Maps" % d)
	for c in candidates:
		if DirAccess.dir_exists_absolute(c):
			return c
	return ""
