extends SceneTree
## Welcome screen: lists the templates with thumbnails, loading one gives a complete map, Esc closes, undo restores.
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/welcome_test.gd -- <out>

func _init() -> void:
	call_deferred("_run")


func shot(path: String) -> void:
	for i in 8:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var ok := true
	var paths := WelcomeScreen.template_paths()
	print("templates: ", paths.size())
	ok = ok and paths.size() == 4
	ok = ok and not ed.welcome.visible                 # tests don't get greeted
	ed._new_map_clicked()
	ok = ok and ed.welcome.visible
	var thumbs := 0
	for c in ed.welcome._grid.get_children():
		var tr: TextureRect = c.get_child(0).get_child(0)
		thumbs += 1 if tr.texture is CompressedTexture2D else 0   # (the imported texture: raw PNGs are not in an exported build)
	print("cards with thumbnails: ", thumbs)
	ok = ok and thumbs == 4
	await shot(out + "/welcome.png")
	var before: int = ed.ramps_root.get_child_count()
	ed.welcome.template_chosen.emit("res://templates/4_aurora_night.mallet")
	await process_frame
	var n: int = ed.ramps_root.get_child_count()
	var problems: PackedStringArray = SurfsUpExporter.check(ed._map_dict())
	print("loaded aurora: ramps=%d preset=%s welcome=%s problems=%s" % [n, ed.environment.get("preset"), ed.welcome.visible, problems])
	ok = ok and n > 3 and not ed.welcome.visible and problems.is_empty() and not ed._map_dict().has("template")
	await shot(out + "/welcome_loaded.png")
	ed.undo()
	print("after undo: ramps=%d (was %d)" % [ed.ramps_root.get_child_count(), before])
	ok = ok and ed.ramps_root.get_child_count() == before
	# Esc closes the screen
	ed._new_map_clicked()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	print("esc closes: ", not ed.welcome.visible)
	ok = ok and not ed.welcome.visible
	print("WELCOME: ", "PASS" if ok else "FAIL")
	quit()
