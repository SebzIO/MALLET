class_name Tester
extends RefCounted
## Test builds (docs/PLAYTEST.md parts 1-2). A test build is MALLET itself, renamed, next to the map and a tester.cfg:
## started that way it skips the editor, asks the tester's name and consent once, and goes straight into play mode.
## Every attempt (outcome, time, splits, deaths, speeds, route) is written to a runs file next to it, which the map
## maker brings back with Playtest > Import tester runs. Nothing is sent anywhere.

const CONFIG := "tester.cfg"
const MAP_FILE := "map.mallet"
const RUNS_DIR := "tester runs"
const RUNS_FORMAT := "mallet-runs"


## The folder a test build runs from ("" = this is the normal MALLET). `--tester <folder>` after `--` also works
## (development and tests).
static func folder() -> String:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--tester")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	var here := OS.get_executable_path().get_base_dir()
	return here if FileAccess.file_exists(here.path_join(CONFIG)) else ""


## The build's settings: {"map_name", "version", "made", "maker"} ({} if it can't be read).
static func config(dir: String) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(dir.path_join(CONFIG)) != OK:
		return {}
	return {"map_name": String(cf.get_value("test", "map_name", "map")), "version": int(cf.get_value("test", "version", 1)),
		"made": String(cf.get_value("test", "made", "")), "maker": String(cf.get_value("test", "made_with", "")),
		"relay": String(cf.get_value("relay", "url", "")), "session": String(cf.get_value("relay", "session", "")),
		"secret": String(cf.get_value("relay", "secret", ""))}


## The tester's name and consent, kept next to the build ("" = not asked yet).
static func tester_name(dir: String) -> String:
	var cf := ConfigFile.new()
	if cf.load(dir.path_join("tester_profile.cfg")) != OK or not bool(cf.get_value("tester", "consent", false)):
		return ""
	return String(cf.get_value("tester", "name", ""))


static func save_tester(dir: String, name: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("tester", "name", name)
	cf.set_value("tester", "consent", true)
	cf.set_value("tester", "when", Time.get_datetime_string_from_system())
	cf.save(dir.path_join("tester_profile.cfg"))


## This session's runs file (one per launch), rewritten after every attempt so nothing is lost on a crash.
static func session_file(dir: String, cfg: Dictionary, name: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	DirAccess.make_dir_recursive_absolute(dir.path_join(RUNS_DIR))
	return dir.path_join(RUNS_DIR).path_join("%s v%d - %s - %s.json" % [cfg.get("map_name", "map"), int(cfg.get("version", 1)),
		name.validate_filename(), stamp])


static func write_session(path: String, cfg: Dictionary, name: String, attempts: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"format": RUNS_FORMAT, "version": 1, "map": cfg.get("map_name", ""),
		"map_version": int(cfg.get("version", 1)), "tester": name, "made_with": MalletVersion.full(), "attempts": attempts}))
	f.close()


## Read a runs file ({} if it isn't one). Values are checked, never trusted.
static func read_runs(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or d.get("format", "") != RUNS_FORMAT or not d.get("attempts") is Array:
		return {}
	var out := []
	for a in d["attempts"]:
		if not a is Dictionary or not String(a.get("outcome", "")) in ["finish", "restart", "quit"]:
			continue
		var route := []
		for q in (a.get("route", []) as Array if a.get("route") is Array else []):
			if q is Array and q.size() == 4:
				route.append([float(q[0]), float(q[1]), float(q[2]), float(q[3])])
		var deaths := []
		for q in (a.get("deaths", []) as Array if a.get("deaths") is Array else []):
			if q is Array and q.size() == 3:
				deaths.append([float(q[0]), float(q[1]), float(q[2])])
		out.append({"outcome": String(a["outcome"]), "time": float(a.get("time", 0.0)), "top_speed": float(a.get("top_speed", 0.0)),
			"finish_speed": float(a.get("finish_speed", 0.0)), "splits": a.get("splits", []) if a.get("splits") is Array else [],
			"deaths": deaths, "route": route, "started": float(a.get("started", 0.0))})
	return {"tester": String(d.get("tester", "?")).left(40), "map": String(d.get("map", "")), "map_version": int(d.get("map_version", 0)),
		"attempts": out}


## A plain-language summary of imported runs ([{tester, map_version, attempts}, ...]).
static func summary(sessions: Array) -> String:
	var testers := {}
	var n := 0
	var fins := []
	var deaths := 0
	var quits := 0
	for s in sessions:
		testers[s["tester"]] = true
		for a in s["attempts"]:
			n += 1
			deaths += (a["deaths"] as Array).size()
			if a["outcome"] == "finish":
				fins.append([a["time"], s["tester"]])
			elif a["outcome"] == "quit":
				quits += 1
	fins.sort_custom(func(x, y): return x[0] < y[0])
	var t := "%d tester(s), %d attempt(s), %d finished, %d fall(s) / death(s), %d quit mid-run." % [testers.size(), n, fins.size(), deaths, quits]
	if not fins.is_empty():
		t += "\nFastest: %s by %s." % [PlayMode.format_time(fins[0][0]), fins[0][1]]
	var stages := stage_report(sessions)
	if stages != "":
		t += "\n" + stages
	return t


## Per stage: how many attempts reached it and the best split (by whom); then where the runs that didn't finish
## ended (the last stage they reached: where people give up or keep falling). "" for a map without stages.
static func stage_report(sessions: Array) -> String:
	var reached := {}                                    # stage -> attempts that reached it
	var best := {}                                       # stage -> [time, tester]
	var ended := {}                                      # last stage reached (1 = still before stage 2) -> count
	var n := 0
	for s in sessions:
		for a in s.get("attempts", []):
			n += 1
			var last := 1
			for sp in a.get("splits", []):
				if not sp is Array or (sp as Array).size() < 2:
					continue
				var st := int(sp[0])
				var tm := float(sp[1])
				reached[st] = int(reached.get(st, 0)) + 1
				if not best.has(st) or tm < float(best[st][0]):
					best[st] = [tm, String(s.get("tester", "?"))]
				last = maxi(last, st)
			if String(a.get("outcome", "")) != "finish":
				ended[last] = int(ended.get(last, 0)) + 1
	if reached.is_empty():
		return ""
	var keys: Array = reached.keys()
	keys.sort()
	var lines := PackedStringArray()
	for st in keys:
		lines.append("Stage %d: reached in %d of %d attempt(s), best split %s by %s." % [st, reached[st], n,
			PlayMode.format_time(best[st][0]), best[st][1]])
	if not ended.is_empty():
		var ek: Array = ended.keys()
		ek.sort()
		var parts := PackedStringArray()
		for st in ek:
			parts.append("%d before stage 2" % ended[st] if st == 1 else "%d on stage %d" % [ended[st], st])
		lines.append("Runs that didn't finish ended: " + ", ".join(parts) + ".")
	return "\n".join(lines)


## Make a test build: the MALLET program (`exe`, with its .pck), renamed, plus the map, tester.cfg, the materials
## the map uses and a READ ME, zipped. Returns {"error", "zip"}.
static func make_build(map: Dictionary, map_name: String, version: int, exe: String, out_dir: String,
		relay: Dictionary = {}) -> Dictionary:
	var pck := exe.get_basename() + ".pck"
	if not FileAccess.file_exists(exe) or not FileAccess.file_exists(pck):
		return {"error": "Test builds are made from the MALLET program itself (MALLET.exe with MALLET.pck), not the development version.", "zip": ""}
	var base := "%s test v%d" % [map_name, version]
	var zip_path := out_dir.path_join(base.replace(" ", "_") + ".zip")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var z := ZIPPacker.new()
	if z.open(zip_path) != OK:
		return {"error": "Can't write " + zip_path, "zip": ""}
	var top := base + "/"
	var prog := "Play %s" % map_name
	_zip_file(z, top + prog + ".exe", FileAccess.get_file_as_bytes(exe))
	_zip_file(z, top + prog + ".pck", FileAccess.get_file_as_bytes(pck))
	_zip_file(z, top + MAP_FILE, JSON.stringify(map).to_utf8_buffer())
	var cf := ConfigFile.new()
	cf.set_value("test", "map_name", map_name)
	cf.set_value("test", "version", version)
	cf.set_value("test", "made", Time.get_datetime_string_from_system())
	cf.set_value("test", "made_with", MalletVersion.full())
	if not relay.is_empty():
		cf.set_value("relay", "url", String(relay.get("url", "")))       # live runs go to this session while it can reach it
		cf.set_value("relay", "session", String(relay.get("session", "")))
		cf.set_value("relay", "secret", String(relay.get("secret", "")))
	_zip_file(z, top + CONFIG, cf.encode_to_text().to_utf8_buffer())
	var privacy := "Nothing is sent anywhere." if relay.is_empty() else ("While it can reach the map maker's playtest session, it also sends your runs there as you play;\n"
		+ "the folder is still saved, so a lost connection loses nothing.")
	_zip_file(z, top + "READ ME FIRST.txt", (("Test build of %s (version %d), made with %s.\n\n" % [map_name, version, MalletVersion.full()])
		+ "Start \"%s.exe\". The first time it asks for a name to show on your runs and whether that's OK.\n" % prog
		+ "Windows may warn that it doesn't know the program: click More info > Run anyway (it isn't signed).\n\n"
		+ "Play: WASD + mouse, Space jumps, R restarts, Backspace back to the last stage, Esc for the menu.\n"
		+ "Every attempt is saved in the \"%s\" folder next to the program: your name, times, speeds, where you fell\n" % RUNS_DIR
		+ "and the path you took. " + privacy + " Send that folder back to the map maker when you're done.\n").to_utf8_buffer())
	# only the materials this map uses (a full library is a few hundred MB)
	var text := JSON.stringify(map)
	var used := []
	for e in MaterialLibrary.entries():
		if text.contains("\"%s\"" % e["id"]) or text.contains("\"%s|" % e["id"]):
			used.append(e)
	var lib := []
	for e in used:
		var dir: String = e["dir"]
		for f in DirAccess.get_files_at(dir):
			_zip_file(z, top + "materials/" + String(e["id"]) + "/" + f, FileAccess.get_file_as_bytes(dir + f))
		var copy: Dictionary = e.duplicate()
		copy.erase("dir")
		lib.append(copy)
	_zip_file(z, top + "materials/library.json", JSON.stringify({"materials": lib}).to_utf8_buffer())
	z.close()
	return {"error": "", "zip": zip_path, "materials": used.size()}


static func _zip_file(z: ZIPPacker, path: String, data: PackedByteArray) -> void:
	z.start_file(path)
	z.write_file(data)
	z.close_file()
