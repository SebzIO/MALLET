extends SceneTree
## Compiles a CS:S map (sf_ramp_prefabs) with one ramp of every starter ramp prefab, so vbsp checks the brushes of
## cuts, tapers, lips and closed ends. Needs CS:S. (Not part of the regression: it writes into cstrike/maps.)
## Run: godot --path . --headless -s res://tests/css_ramps_compile.gd -- <out folder>


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var map := {"format": "mallet-map", "version": 2, "environment": Look.default_environment(), "props": [], "texts": [], "blocks": [],
		"entities": [{"kind": "start", "position": [0, 60, -150], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 150], "size": [40, 2, 40], "yaw": 0.0}], "ramps": []}
	var z := -110.0
	for it in RampPrefabs.list():
		for solid in [false, true]:
			var rd: Dictionary = it["design"].duplicate(true)
			rd["solid"] = solid
			rd["points"] = [[-60 if solid else 10, 40, z], [-35 if solid else 35, 34, z + 4], [-10 if solid else 60, 28, z]]
			map["ramps"].append(rd)
		z += 22.0
	var vmf := out.path_join("sf_ramp_prefabs.vmf")
	var res := VmfExporter.export_vmf(map, vmf)
	print("export: ", res["error"] if res["error"] != "" else "ok (%d brushes)" % res["brushes"])
	var c := VmfExporter.compile(vmf, VmfExporter.find_css(), "fast")
	var log: String = c.get("log", "")
	var bad := 0
	for line in log.split("\n"):
		if line.contains("Brush") and (line.contains("error") or line.contains("invalid") or line.contains("mixed face")):
			bad += 1
			print("  ", line)
	print("compile: ", c["error"] if c["error"] != "" else c["bsp"], " | brush problems in the log: ", bad)
	print("css_ramps_compile: ", "PASS" if c["error"] == "" and bad == 0 else "FAIL")
	quit()
