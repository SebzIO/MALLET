extends SceneTree
## Lights and particles (0.12): light presets, strips and effects (an AnimationPlayer, no script), particle effects in
## the editor (add, edit, save, load, copy), the SurfsUp export (owned nodes, no scripts), the CS:S export (light
## styles, a light per strip point, stock particle entities), and the map weight readout. Saves a picture.
## Run: godot --path D:/SurfForge --resolution 1280x720 -s res://tests/fx_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func has_script(n: Node) -> bool:
	if n.get_script() != null:
		return true
	for c in n.get_children():
		if has_script(c):
			return true
	return false


func all_owned(root3: Node, n: Node) -> bool:
	for c in n.get_children():
		if c.owner != root3 or not all_owned(root3, c):
			return false
	return true


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]

	# lights
	var made := 0
	for k in LightNode.PRESET_ORDER:
		var s := LightNode.spec(LightNode.PRESETS[k])
		var rig := LightNode.make_rig(s)
		made += 1 if rig.get_child(0) is Light3D else 0
		rig.free()
	check("every light preset builds", made == LightNode.PRESET_ORDER.size())
	var strip := LightNode.spec({"kind": "strip", "length": 8.0, "effect": "fluorescent"})
	var rig := LightNode.make_rig(strip)
	var n_lights := 0
	var player: AnimationPlayer = null
	for c in rig.get_children():
		n_lights += 1 if c is OmniLight3D else 0
		if c is AnimationPlayer:
			player = c
	check("an 8 m strip: 4 lights along it and a tube", n_lights == 4 and rig.get_node_or_null("Tube") != null)
	check("...its effect is an autoplaying AnimationPlayer driving every light", player != null and player.autoplay == "fx"
		and player.get_animation("fx").get_track_count() == 4)
	rig.free()

	# the editor
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._load_dict({})
	ed._add_light("point")
	var ln: LightNode = ed.selected
	ed._edit_prop("light_preset", "torch")
	check("picking the Torch preset: warm, candle effect", ln.data["effect"] == "candle" and ln.data["color"] == "ff9a40")
	ed._add_particles("fire")
	var pn: ParticleNode = ed.selected
	check("adding particles selects a fire effect", pn != null and pn.data["preset"] == "fire" and ed._particle_props.visible)
	var fire_area: Array = (pn.data["area"] as Array).duplicate()
	ed._edit_prop("fx_preset", "snow")
	check("...switching it to snow keeps the area (only the effect changes)", pn.data["preset"] == "snow" and pn.data["area"] == fire_area)
	ed._edit_prop("fx_amount", 2.0)
	ed._edit_prop("fx_own_color", true)
	ed._edit_prop("fx_color", Color(1, 0, 0))
	check("...amount and own color stick", pn.data["amount"] == 2.0 and pn.data["color"] == "ff0000")
	var md: Dictionary = ed._map_dict()
	check("the map saves its particles", md["particles"].size() == 1 and md["particles"][0]["preset"] == "snow")
	ed._load_dict(md)
	await process_frame
	check("...and loads them back", ed.particles_root.get_child_count() == 1
		and (ed.particles_root.get_child(0) as ParticleNode).data["amount"] == 2.0)
	ed._select(ed.particles_root.get_child(0))
	ed._duplicate_clicked()
	await process_frame
	check("duplicating a particle effect makes a second one", ed.particles_root.get_child_count() == 2)
	ed._select(null)
	ed._refresh_info()
	check("the info panel shows the map's weight", ed._info.text.contains("Map weight:") and ed._info.text.contains("particle"))
	var heavy := {"lights": [], "particles": []}
	for i in 12:
		heavy["lights"].append({"kind": "point", "shadows": true})
	for i in 8:
		heavy["particles"].append({"preset": "rain", "amount": 1.0})
	var w: Dictionary = ed.map_weight(heavy)
	check("a heavy map warns about shadows and particles", w["shadowed"] == 12 and w["particles"] == 7200 and w["warnings"].size() == 2)

	# SurfsUp export
	var map := {"format": "mallet-map", "version": 2, "environment": Look.default_environment(), "ramps": [], "props": [],
		"texts": [], "blocks": [{"position": [0, 0, 0], "size": [20, 2, 20]}],
		"entities": [{"kind": "start", "position": [0, 10, 0], "size": [20, 2, 26], "yaw": 0.0},
			{"kind": "finish", "position": [0, 10, 200], "size": [40, 2, 40], "yaw": 0.0}],
		"lights": [{"kind": "strip", "position": [0, 5, 0], "length": 6.0, "effect": "pulse"},
			{"kind": "point", "position": [10, 5, 0], "effect": "strobe"},
			{"kind": "spot", "position": [20, 5, 0]}],
		"particles": [{"preset": "fire", "position": [0, 1, 0]}, {"preset": "smoke", "position": [5, 1, 0]},
			{"preset": "sparks", "position": [10, 1, 0]}, {"preset": "snow", "position": [0, 30, 0]},
			{"preset": "mist", "position": [0, 2, 20]}, {"preset": "magic", "position": [0, 2, 30]}]}
	var scene := SurfsUpExporter.build_scene(map, "fx_test")
	var fxs := scene.get_node_or_null("Particles")
	check("SurfsUp: every particle effect is in the map", fxs != null and fxs.get_child_count() == 6
		and fxs.get_child(0) is GPUParticles3D)
	check("SurfsUp: lights and particles are saved with the map (all owned)", all_owned(scene, scene.get_node("Lights")) and all_owned(scene, fxs))
	check("SurfsUp: no scripts anywhere", not has_script(scene))
	var ps := PackedScene.new()
	check("SurfsUp: the scene packs", ps.pack(scene) == OK)
	scene.free()

	# CS:S
	var vx := VmfExporter.new()
	var text := vx.build(map)
	if text == "":
		print("VMF warnings: ", vx.warnings)
	check("CS:S: the pulsing strip is 3 lights with Source's pulse style", text.count("\"style\" \"2\"") == 3)
	check("CS:S: the strobe is light style 4", text.contains("\"style\" \"4\""))
	check("CS:S: fire, smoke, sparks, steam and snow become stock entities", text.contains("env_fire") and text.contains("env_smokestack")
		and text.contains("env_spark") and text.contains("env_steam") and text.contains("func_precipitation"))
	check("CS:S: snow is precipitation type 3", text.contains("\"preciptype\" \"3\""))
	var warned := false
	for wtxt in vx.warnings:
		warned = warned or String(wtxt).contains("no CS:S match")
	check("CS:S: magic sparkles are left out with a warning", warned)

	# a picture: fire, smoke and a neon strip at night
	ed.queue_free()
	await process_frame
	var root3 := Node3D.new()
	root.add_child(root3)
	var we := WorldEnvironment.new()
	we.environment = Look.build_environment(Look.preset_environment("night"))
	root3.add_child(we)
	var floor := BlockNode.new()
	root3.add_child(floor)
	floor.from_dict({"position": [0, -1, 0], "size": [30, 1, 30], "material": "Tiles107"})
	floor.rebuild()
	for d in [{"preset": "fire", "position": [-3, 0, 0]}, {"preset": "smoke", "position": [-3, 1.5, 0]},
			{"preset": "sparks", "position": [3, 0.5, 0]}, {"preset": "magic", "position": [0, 2, -3]}]:
		var p := ParticleNode.new()
		root3.add_child(p)
		p.from_dict(d)
	var l := LightNode.new()
	root3.add_child(l)
	l.from_dict(LightNode.PRESETS["neon_pink"].merged({"position": [0, 3, -5]}))
	var l2 := LightNode.new()
	root3.add_child(l2)
	l2.from_dict(LightNode.PRESETS["campfire"].merged({"position": [-3, 1, 0]}))
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4, 10), Vector3(0, 1, -2))
	cam.make_current()
	for i in 40:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + "/fx.png")
	var c0 := img.get_pixel(int(img.get_width() * 0.38), int(img.get_height() * 0.55))
	check("the picture isn't blank", c0.r + c0.g + c0.b > 0.05, "(%s)" % c0)
	print("FX: ", "PASS" if ok else "FAIL")
	quit()
