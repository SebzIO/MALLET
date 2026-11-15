extends SceneTree
## CS:S textures (0.30.2): the .vtf files MALLET writes for its own materials hold the real picture. 0.30.1 and earlier
## compressed them with Godot's DXT compressor, which only exists in the editor: an exported MALLET wrote raw pixels
## under a DXT header, and CS:S showed rainbow static. This reads each file back (header, every mip level's size, the
## full-size picture's pixels) and compares it with the source. Run it with the exported MALLET.exe too:
##   godot --path . --headless -s res://tests/css_vtf_test.gd -- <out dir>
##   MALLET.exe --headless -s <path>/tests/css_vtf_test.gd -- <out dir>

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out)
	var src := Image.create(128, 128, false, Image.FORMAT_RGB8)       # bricks-ish: red blocks, gray lines
	for y in 128:
		for x in 128:
			var line := y % 32 < 3 or (x + (16 if (y / 32) % 2 == 1 else 0)) % 32 < 3
			src.set_pixel(x, y, Color(0.75, 0.75, 0.72) if line else Color(0.62, 0.22 + 0.001 * x, 0.15))
	var glow := Image.create(128, 128, false, Image.FORMAT_RGB8)
	glow.fill(Color.BLACK)
	glow.fill_rect(Rect2i(32, 32, 64, 64), Color.WHITE)
	for case in [["plain", null], ["glow", glow]]:
		var path := out.path_join("vtf_%s.vtf" % case[0])
		VmfExporter._write_vtf(src, path, case[1])
		var b := FileAccess.get_file_as_bytes(path)
		var n: int = VmfExporter.VTF_SIZE
		check(b.size() > 80 and b.slice(0, 3).get_string_from_ascii() == "VTF", "%s: a VTF file" % case[0])
		var fmt := b.decode_u32(52)
		var bpp := 4 if case[1] != null else 3
		check(fmt == (12 if bpp == 4 else 3), "%s: uncompressed %s (format %d)" % [case[0], "BGRA8888" if bpp == 4 else "BGR888", fmt])
		check(b.decode_u16(16) == n and b.decode_u16(18) == n, "%s: %d x %d" % [case[0], n, n])
		var levels := b[56]
		var want := 80
		for l in levels:
			var w := maxi(n >> l, 1)
			want += w * w * bpp
		check(b.size() == want, "%s: %d mip levels, the file is exactly their size (%d bytes, want %d)" % [case[0], levels, b.size(), want])
		# the full-size picture is last; compare it with the source scaled the same way
		var ref: Image = src.duplicate()
		ref.resize(n, n, Image.INTERPOLATE_LANCZOS)
		var top := b.slice(b.size() - n * n * bpp)
		var worst := 0.0
		for i in 400:
			var x := (i * 37) % n
			var y := (i * 91) % n
			var o := (y * n + x) * bpp
			var c := Color8(top[o + 2], top[o + 1], top[o])          # (stored blue, green, red)
			var r := ref.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(c.r - r.r), maxf(absf(c.g - r.g), absf(c.b - r.b))))
		check(worst < 0.03, "%s: the picture matches the source (worst channel off by %.3f)" % [case[0], worst])
		if bpp == 4:
			var a_in := top[((n / 2) * n + n / 2) * 4 + 3]
			var a_out := top[(4 * n + 4) * 4 + 3]
			check(a_in > 240 and a_out < 15, "glow: the glow mask is in alpha (inside %d, outside %d)" % [a_in, a_out])
	print("css_vtf_test (%s): %s" % ["editor" if OS.has_feature("editor") else "exported", "ALL PASS" if fails == 0 else "%d FAILED" % fails])
	quit(1 if fails > 0 else 0)
