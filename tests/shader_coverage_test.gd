extends SceneTree
## Every setting of every shader is editable or accounted for (0.25.1). MALLET's own shaders: each uniform has a
## control of its own (Look.BUILTIN_COVERED says where), is internal (says why), or gets a control automatically
## (Look.param_uniforms) - a uniform added later without a control fails here. Your own shaders: every kind of
## setting MALLET can edit gets a control (ivec too), and the rest are listed as not shown, with why. And the aurora:
## both sky colors and the ramp look's second color, applied.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/shader_coverage_test.gd -- <out folder>

var ok := true
var ed


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	# every shipped shader, every uniform
	var missing := []
	var counted := 0
	for f in DirAccess.get_files_at("res://core/shaders/"):
		if not f.ends_with(".gdshader"):
			continue
		var file := f.get_basename()
		if Look.BUILTIN_INTERNAL.has(file):
			continue
		var s := Look.shader(file)
		var offered := Look.param_uniforms(file).map(func(u): return u["name"])
		var covered: Dictionary = Look.BUILTIN_COVERED.get(file, {})
		for u in s.get_shader_uniform_list():
			var n := String(u["name"])
			counted += 1
			if not (n in offered or covered.has(n)):
				missing.append("%s.%s" % [file, n])
	check("every setting of every shader MALLET ships has a control or a reason", missing.is_empty() and counted > 30,
		"(%d settings; without: %s)" % [counted, ", ".join(missing)])
	var sky := Look.param_uniforms("sky").map(func(u): return u["label"])
	check("the sky's aurora colors get controls", "Aurora color 1" in sky and "Aurora color 2" in sky, str(sky))
	check("the Aurora ramp look's second color does", Look.param_uniforms("ramp_aurora").any(func(u): return u["label"] == "Second color"))
	check("water / lava / glass show their other settings", Look.param_uniforms("water").size() >= 5 and Look.param_uniforms("lava").size() >= 6
		and Look.param_uniforms("glass").size() >= 4)
	# applied: the sky
	var env := Look.default_environment()
	env["aurora"] = 1.0
	env["sky_look"] = {"aurora_a": "ff0000", "aurora_b": "0000ff"}
	var sm: ShaderMaterial = Look.sky_material(env)[0]
	var a = sm.get_shader_parameter("aurora_a")
	check("the sky's aurora takes your colors", a is Color and (a as Color).r > 0.9 and (a as Color).g < 0.1, str(a))
	# applied: a ramp's aurora look
	ed._load_dict({"ramps": [{"points": [[0, 50, 0], [0, 40, -60]], "look": "aurora", "color": "00ff88"}]})
	await process_frame
	var r: RampNode = ed.ramps_root.get_child(0)
	ed._select(r)
	await process_frame
	check("selecting an Aurora ramp shows its settings (no shader picker)", ed._fields["shader_box"].visible
		and not ed._fields["shader_row"].visible and ed._fields["shader_params"].get_child_count() > 0)
	ed._edit_prop("shader_param", ["tint_b", "ffcc00"])
	var rm := r._mesh_instance.material_override as ShaderMaterial
	var tb = rm.get_shader_parameter("tint_b") if rm else null
	check("...and its second color takes", tb is Color and (tb as Color).is_equal_approx(Color.html("ffcc00")), str(tb))
	var d: Dictionary = ed._map_dict()
	check("...and saves with the ramp", (d["ramps"][0]["shader_params"] as Dictionary).get("tint_b") == "ffcc00")
	ed._edit_prop("look", "neon")
	check("another look starts its settings fresh", r.shader_params.is_empty())
	# applied: a water block, and build mode's lava
	var wm := BlockShape.water_material({"liquid": "water", "liquid_params": {"waves": 1.8, "foam": 0.1}})
	check("a water block takes its waves and foam", is_equal_approx(float(wm.get_shader_parameter("waves")), 1.8)
		and is_equal_approx(float(wm.get_shader_parameter("foam")), 0.1))
	var env2 := Look.default_environment()
	env2["lava_params"] = {"crust": 0.9}
	CubeWorld.set_mat_looks(env2)
	var lm := CubeWorld.material_look("lava") as ShaderMaterial
	check("build mode lava takes the map's crust setting", is_equal_approx(float(lm.get_shader_parameter("crust")), 0.9))
	CubeWorld.set_mat_looks(Look.default_environment())
	# your own shaders: every kind
	var code := """shader_type spatial;
uniform ivec2 tiles = ivec2(4, 2);
uniform mat4 warp;
uniform samplerCube env_map;
uniform float amount : hint_range(0.0, 2.0) = 1.0;
void fragment() { ALBEDO = vec3(amount); }
"""
	UserShaders.add_embedded({"coverage_probe": code})
	var e := UserShaders.entry("coverage_probe")
	var names: Array = (e.get("uniforms", []) as Array).map(func(u): return u["name"])
	var skipped: Array = (e.get("skipped", []) as Array).map(func(u): return u["name"])
	check("your shader: an ivec2 gets a control", "tiles" in names, str(names))
	check("...a matrix and a cubemap are listed as not shown, with why", "warp" in skipped and "env_map" in skipped, str(e.get("skipped")))
	print("shader_coverage_test: ", "PASS" if ok else "FAIL")
	quit()
