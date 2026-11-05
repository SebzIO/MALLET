extends SceneTree
## Convex pieces and carving: volumes add up exactly, hollowing leaves the right walls, every piece is convex and
## solid, and meshes face outwards.
## Run: godot --headless --path D:/SurfForge -s res://tests/convex_test.gd

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-58s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


## Volume of a convex piece: split each face into triangles and sum tetrahedra from the centre.
func volume(piece: Array) -> float:
	var pts := Convex.points(piece)
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var v := 0.0
	for f in Convex.faces(piece):
		var poly: Array = f[1]
		for i in range(1, poly.size() - 1):
			v += absf((poly[0] - c).dot((poly[i] - c).cross(poly[i + 1] - c))) / 6.0
	return v


func total(pieces: Array) -> float:
	var v := 0.0
	for p in pieces:
		v += volume(p)
	return v


func _init() -> void:
	var wall := BlockShape.spec({"shape": "box", "size": [20, 10, 2]})
	var door := BlockShape.spec({"shape": "box", "size": [4, 6, 6], "position": [0, -1, 0], "cutter": true})
	var cut := BlockShape.world_pieces(wall, [door])
	var expect := 20.0 * 10.0 * 2.0 - 4.0 * 5.0 * 2.0          # the door goes from the floor (it starts below) to 5 m
	check("doorway carved out of a wall", absf(total(cut) - expect) < 0.01, "(%d pieces, %.2f m3, expected %.2f)" % [cut.size(), total(cut), expect])
	var all_solid := true
	for p in cut:
		all_solid = all_solid and Convex.solid(p)
	check("every piece is a real convex solid", all_solid)
	var hollow := BlockShape.local_pieces(BlockShape.spec({"shape": "box", "size": [10, 10, 10], "hollow": true, "wall": 1.0}))
	check("hollow box leaves 1 m walls", absf(total(hollow) - (1000.0 - 512.0)) < 0.01, "(%.2f m3)" % total(hollow))
	var stairs := BlockShape.local_pieces(BlockShape.spec({"shape": "stairs", "size": [4, 4, 8], "steps": 4}))
	check("stairs: 4 steps, 4 + 3 + 2 + 1 parts of volume", stairs.size() == 4 and absf(total(stairs) - 4.0 * 2.0 * (1 + 2 + 3 + 4)) < 0.01,
		"(%.2f m3)" % total(stairs))
	var cyl := BlockShape.local_pieces(BlockShape.spec({"shape": "cylinder", "size": [10, 4, 10], "sides": 32}))
	check("cylinder close to pi r^2 h", absf(total(cyl) - PI * 25.0 * 4.0) < PI * 25.0 * 4.0 * 0.01, "(%.1f m3)" % total(cyl))
	var w := BlockShape.local_pieces(BlockShape.spec({"shape": "wedge", "size": [4, 3, 6]}))
	check("wedge is half a box", absf(total(w) - 36.0) < 0.01)
	# mesh faces point outwards: each triangle's winding normal agrees with the face normal it came from
	var m := BlockShape.mesh(BlockShape.world_pieces(wall, [door]), Transform3D.IDENTITY)
	var arr := m.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var agree := true
	for i in range(0, verts.size(), 3):
		var g := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i])     # clockwise front faces
		agree = agree and g.dot(norms[i]) > 0.0
	check("mesh triangles wound to face outwards", agree)
	print("CONVEX: ", "PASS" if ok else "FAIL")
	quit()
