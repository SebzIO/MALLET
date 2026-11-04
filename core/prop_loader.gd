class_name PropLoader
extends RefCounted
## Loads glTF models (.glb / .gltf) at runtime for props: their meshes (with materials and textures), the faces
## players collide with, and compact copies for export. Only meshes are kept - no scripts, cameras, lights or
## animation players - so an exported map stays a plain scene SurfsUp accepts. Shared by the editor and exporters.

const MAX_TEXTURE := 1024                ## exported textures are scaled down to this and compressed

static var _cache := {}                  ## path -> {"meshes": [[Mesh, Transform3D]], "aabb", "triangles", "error"}
static var _export_cache := {}           ## path -> [[Mesh with compressed textures, Transform3D]]


## The model's meshes and their transforms inside the model, its bounding box, triangle count, or an error.
static func load_model(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var res := {"meshes": [], "aabb": AABB(), "triangles": 0, "error": ""}
	if path == "" or not FileAccess.file_exists(path):
		res["error"] = "Model file not found: %s" % (path.get_file() if path != "" else "(none chosen)")
		return res                       # not cached: the file may appear later
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		res["error"] = "Could not read %s (%s)" % [path.get_file(), error_string(err)]
		_cache[path] = res
		return res
	var root := doc.generate_scene(state)
	if root == null:
		res["error"] = "%s has nothing in it to show" % path.get_file()
		_cache[path] = res
		return res
	_collect(root, Transform3D.IDENTITY, res)
	root.free()
	if res["meshes"].is_empty():
		res["error"] = "%s has no meshes" % path.get_file()
	_cache[path] = res
	return res


static func _collect(node: Node, parent_xf: Transform3D, res: Dictionary) -> void:
	var xf := parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mi.material_override:                         # bake an override into the surfaces
			mesh = mesh.duplicate()
			for s in mesh.get_surface_count():
				mesh.surface_set_material(s, mi.material_override)
		res["meshes"].append([mesh, xf])
		var box: AABB = xf * mesh.get_aabb()
		res["aabb"] = box if res["meshes"].size() == 1 else (res["aabb"] as AABB).merge(box)
		for s in mesh.get_surface_count():
			res["triangles"] += mesh.surface_get_array_len(s) / 3 if mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_INDEX == 0 \
				else mesh.surface_get_array_index_len(s) / 3
	for c in node.get_children():
		_collect(c, xf, res)


## Every collision triangle of the model, scaled, in the prop's own space.
static func collision_faces(path: String, scale: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var b := Basis().scaled(Vector3.ONE * scale)
	for m in load_model(path)["meshes"]:
		var xf: Transform3D = Transform3D(b, Vector3.ZERO) * (m[1] as Transform3D)
		for v in (m[0] as Mesh).get_faces():
			faces.append(xf * v)
	return faces


## The model's meshes for export: textures scaled down and compressed so the map pack stays small.
static func export_meshes(path: String) -> Array:
	if _export_cache.has(path):
		return _export_cache[path]
	var out := []
	var done := {}                                       # source material -> compressed copy (shared materials stay shared)
	for m in load_model(path)["meshes"]:
		var mesh: Mesh = (m[0] as Mesh).duplicate()
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D:
				if not done.has(mat):
					done[mat] = _compressed_material(mat)
				mesh.surface_set_material(s, done[mat])
		out.append([mesh, m[1]])
	_export_cache[path] = out
	return out


static func _compressed_material(mat: BaseMaterial3D) -> BaseMaterial3D:
	var copy: BaseMaterial3D = mat.duplicate()
	for p in ["albedo_texture", "normal_texture", "roughness_texture", "metallic_texture", "emission_texture",
			"ao_texture", "orm_texture"]:
		if not p in copy:
			continue
		var tex = copy.get(p)
		if tex is Texture2D and not tex is PortableCompressedTexture2D:
			var img: Image = (tex as Texture2D).get_image()
			if img == null or img.is_empty():
				continue
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			var longest: int = maxi(img.get_width(), img.get_height())
			if longest > MAX_TEXTURE:
				var k := float(MAX_TEXTURE) / longest
				img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			var c := PortableCompressedTexture2D.new()
			c.keep_compressed_buffer = true          # without this the image data is not saved into the map
			c.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY, p == "normal_texture", 0.85)
			copy.set(p, c)
	return copy


static func forget(path: String) -> void:
	_cache.erase(path)
	_export_cache.erase(path)
