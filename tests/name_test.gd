extends SceneTree
## The name: MALLET in the version, the project, the window title; .mallet templates and .malletprefab prefabs.
## Run: godot --path . --resolution 1600x900 -s res://tests/name_test.gd -- <out folder>

var ed
var ok := true


func _init() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()

	# ---- the name
	check("the version says MALLET", MalletVersion.full().begins_with("MALLET 0."), "(%s)" % MalletVersion.full())
	check("the project is called MALLET", ProjectSettings.get_setting("application/config/name") == "MALLET")
	ed._set_title("x.mallet")
	check("the window title says MALLET", get_root().title.begins_with("MALLET"), "(%s)" % get_root().title)
	check("the welcome screen finds the five .mallet templates", WelcomeScreen.template_paths().size() == 5)
	check("the starter prefabs are .malletprefab files", Prefabs.list().filter(func(p): return p["builtin"] and String(p["path"]).ends_with(".malletprefab")).size() == 7)

	print("NAME: ", "PASS" if ok else "FAIL")
	quit()
