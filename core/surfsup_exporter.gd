class_name SurfsUpExporter
extends RefCounted
## Turns a SurfForge map (the plain .sfmap dictionary) into a SurfsUp map pack: <Maps>/<name>.pck containing
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
	if map.get("ramps", []).is_empty():
		out.append("The map has no ramps.")
	return out


## Builds the scene tree. Every node is owned by the returned root so it can be packed.
static func build_scene(map: Dictionary, map_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = map_name
	var lowest := INF

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.46, 0.68)
	sky_mat.sky_horizon_color = Color(0.68, 0.74, 0.82)
	sky_mat.ground_bottom_color = Color(0.18, 0.19, 0.22)
	sky_mat.ground_horizon_color = Color(0.5, 0.53, 0.58)
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	_add(root, root, env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
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
		var w: float = rd.get("width", 13.0)
		var h: float = rd.get("height", 8.125)
		var detail: float = rd.get("detail", 1.0)
		var ridge := RampShape.sample_path(pts, 1.0 / max(detail, 0.05))
		var mesh := RampShape.build_mesh(ridge, w, h, rd.get("roll", 0.0), rd.get("solid", false), rd.get("base_depth", 0.0))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.html(rd.get("color", "edebe3"))
		mat.roughness = 0.25
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
			lowest = min(lowest, p.y - h - rd.get("base_depth", 0.0))
		i += 1

	# platforms + their zones
	var spawn: Transform3D
	for ed in map.get("entities", []):
		var kind: String = ed.get("kind", "")
		var pa: Array = ed.get("position", [0, 0, 0])
		var sa: Array = ed.get("size", [20, 2, 26])
		var pos := Vector3(pa[0], pa[1], pa[2])
		var size := Vector3(sa[0], sa[1], sa[2])
		var basis := Basis(Vector3.UP, deg_to_rad(ed.get("yaw", 0.0)))
		lowest = min(lowest, pos.y - size.y)
		if kind in ["start", "finish"]:
			var plat := StaticBody3D.new()
			plat.name = "StartPlatform" if kind == "start" else "FinishPlatform"
			plat.transform = Transform3D(basis, pos)
			_add(root, root, plat)
			var box := BoxMesh.new()
			box.size = size
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.25, 0.75, 0.4) if kind == "start" else Color(0.9, 0.3, 0.25)
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
			var zone := _zone(root, "StartZone" if kind == "start" else "FinishZone", "start" if kind == "start" else "finish",
				Transform3D(basis, pos + Vector3(0, ZONE_HEIGHT / 2, 0)), Vector3(size.x, ZONE_HEIGHT, size.z))
			zone.set_meta("course_id", 0)
			if kind == "start":
				zone.set_meta("play_sfx", true)
				zone.set_meta("run_direction", Vector3.ZERO)
				spawn = Transform3D(basis, pos + basis * Vector3(0, 0.1, size.z * 0.25))

	var sp := Marker3D.new()
	sp.name = "SpawnPoint"
	sp.transform = spawn
	_add(root, root, sp)

	# kill floor: an infinite plane well below everything
	if lowest == INF:
		lowest = 0.0
	var kill := Area3D.new()
	kill.name = "KillFloor"
	kill.collision_layer = 0
	kill.collision_mask = 2
	kill.set_meta("sdk_zone", "kill")
	kill.set_meta("kill_kind", "killbox")
	kill.position = Vector3(0, lowest - KILL_MARGIN, 0)
	_add(root, root, kill)
	var plane := CollisionShape3D.new()
	plane.name = "Plane"
	plane.shape = WorldBoundaryShape3D.new()
	_add(root, kill, plane)
	return root


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
