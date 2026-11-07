extends SceneTree
## Compiles a small CS:S map (sf_shader_sky) whose sky is the example sky shader baked into a skybox, and checks the
## skybox files went into the .bsp. Needs CS:S installed. (Not part of the regression: it writes into cstrike/maps.)
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/css_sky_compile.gd -- <out folder>


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	UserShaders.dir = out.path_join("shaders") + "/"
	UserShaders.scan()
	var host := Node.new()
	root.add_child(host)
	var env := Look.default_environment()
	env["sky_shader"] = "example_sky"
	env["sun_pitch"] = 25.0
	var map := {"format": "mallet-map", "version": 2, "environment": env, "ramps": [], "props": [], "texts": [],
		"blocks": [{"position": [0, 0, 0], "size": [40, 2, 40]}],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 60], "size": [20, 2, 20], "yaw": 0.0}]}
	var faces: Dictionary = await Look.bake_skybox(env, host, 512)
	var vmf := out.path_join("sf_shader_sky.vmf")
	var res := VmfExporter.export_vmf(map, vmf, {"skyname": "mallet_sf_shader_sky", "sky_faces": faces})
	print("export: ", res["error"] if res["error"] != "" else "ok")
	var css := VmfExporter.find_css()
	var c := VmfExporter.compile(vmf, css, "fast", res.get("materials", []))
	print("compile: ", c["error"] if c["error"] != "" else c["bsp"])
	var bsp := FileAccess.get_file_as_bytes(c.get("bsp", ""))
	var packed := 0
	for sfx in ["rt", "bk", "lf", "ft", "up", "dn"]:
		var needle := "materials/skybox/mallet_sf_shader_sky%s.vtf" % sfx
		packed += 1 if bsp.size() > 0 and _find(bsp, needle.to_ascii_buffer()) else 0
	print("skybox faces packed into the bsp: %d / 6" % packed)
	print("css_sky_compile: ", "PASS" if c["error"] == "" and packed == 6 else "FAIL")
	quit()


func _find(hay: PackedByteArray, needle: PackedByteArray) -> bool:
	var s := hay.hex_encode()
	return s.find(needle.hex_encode()) >= 0 and s.find(needle.hex_encode()) % 2 == 0
