extends SceneTree
## SurfForge became MALLET (0.10.0): the new name everywhere, .mallet maps, and nothing from before is lost - old
## .sfmap maps open (and save as .mallet), old .sfprefab prefabs and copied SurfForge objects still work, and the
## first start copies SurfForge's settings, own materials and prefabs across (once, never overwriting).
## Run: godot --path D:/SurfForge --resolution 1600x900 -s res://tests/rename_test.gd -- <out folder>

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
	check("the welcome screen finds the four .mallet templates", WelcomeScreen.template_paths().size() == 4)
	check("the starter prefabs are .malletprefab files", Prefabs.list().filter(func(p): return p["builtin"] and String(p["path"]).ends_with(".malletprefab")).size() == 7)

	# ---- an old SurfForge map: opens, and Save turns it into a .mallet
	ed._load_dict({})
	ed._make_ramp(Vector3(-40, 60, 0), Vector3(40, 40, 0))
	var d: Dictionary = ed._map_dict()
	d["format"] = "surfforge-map"
	write(out + "/old_map.sfmap", JSON.stringify(d))
	ed._load_dict({})
	ed.load_map(out + "/old_map.sfmap")
	check("an old .sfmap map opens", ed.ramps_root.get_child_count() == 1)
	ed._file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	ed._on_file_chosen(out + "/old_map.sfmap")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out + "/old_map.mallet"))
	check("saving it writes old_map.mallet as a MALLET map", saved.get("format", "") == "mallet-map" and ed.current_path.ends_with(".mallet"),
		"(%s)" % ed.current_path)

	# ---- old clipboard contents and old prefabs
	var clip: Dictionary = ed._map_dict()
	var old_clip := {"surfforge_clipboard": 1, "ramps": clip["ramps"], "entities": [], "props": [], "blocks": [], "texts": [], "lights": [], "cube_models": []}
	DisplayServer.clipboard_set(JSON.stringify(old_clip))
	ed._paste_clicked()
	check("objects copied in SurfForge still paste", ed.ramps_root.get_child_count() == 2)
	var oldp := "user://prefabs/zz_old_rename_test.sfprefab"
	write(oldp, JSON.stringify(old_clip.merged({"name": "Old one", "description": ""})))
	check("an old .sfprefab prefab still shows up", Prefabs.list().any(func(p): return p["path"] == oldp))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(oldp))

	# ---- first start: SurfForge's own data copied across, once, never overwriting
	var base := out + "/userdata"
	var old_dir := base + "/SurfForge"
	var new_dir := base + "/MALLET"
	for p in [old_dir, new_dir]:
		if DirAccess.dir_exists_absolute(p):
			OS.move_to_trash(ProjectSettings.globalize_path(p))
	write(old_dir + "/preferences.cfg", "[settings]\nfly_speed=123.0\n")
	write(old_dir + "/settings.cfg", "[css]\ndir=\"old\"\n")
	write(old_dir + "/materials/user_brick/color.jpg", "jpg")
	write(old_dir + "/prefabs/mine.sfprefab", "{}")
	write(old_dir + "/shader_cache/junk.bin", "x")
	write(new_dir + "/settings.cfg", "[css]\ndir=\"new\"\n")             # already there: must stay
	var n := Migrate.from_surfforge(new_dir, old_dir)
	check("first start copies settings, own materials and prefabs", n == 3 and FileAccess.file_exists(new_dir + "/preferences.cfg")
		and FileAccess.file_exists(new_dir + "/materials/user_brick/color.jpg") and FileAccess.file_exists(new_dir + "/prefabs/mine.sfprefab"), "(%d files)" % n)
	check("...without overwriting MALLET's own, or copying caches", FileAccess.get_file_as_string(new_dir + "/settings.cfg").contains("new")
		and not DirAccess.dir_exists_absolute(new_dir + "/shader_cache"))
	check("...and only once", Migrate.from_surfforge(new_dir, old_dir) == 0)
	Settings.reload()

	print("RENAME: ", "PASS" if ok else "FAIL")
	quit()
