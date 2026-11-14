class_name RenderJob
extends RefCounted
## One Render video run (0.30.0): for each shot, start a second MALLET under Godot's Movie Maker (ShotRender does
## the drawing there), watch its progress file, and when it has finished keep the shot's own frames (those after its
## magenta marker) as an .avi (MJPEG, written by AviWriter), a numbered PNG sequence, or an .mp4 made by the user's own
## ffmpeg. Call tick() often (the Render video window does, every frame); read stage / fraction / done / failed.

const TMP := "user://render_tmp"

var map := {}                               ## the map as it is now (unsaved changes too)
var shots: Array = []                       ## [{"shot": shot dict, "look_target": [x, y, z] or null}]
var out_dir := ""
var base_name := "video"
var width := 1920
var height := 1080
var fps := 60
var format := "avi"                         ## avi, png or mp4
var ffmpeg := ""

var stage := ""                             ## what is happening, in words
var fraction := 0.0                         ## 0..1 over every shot
var done := false
var failed := ""
var canceled := false
var outputs := PackedStringArray()          ## the files (or folders, for PNG) made

var _i := -1
var _pid := -1
var _tmp := ""
var _progress := ""
var _last := {}
var _task := -1
var _shared := {}                           ## the writer thread's progress and result (under _mutex)
var _mutex := Mutex.new()
var _exe := ""
var _launched_at := 0
var _first_at := 0                          ## when this shot's first frame was reported (msec), for the time estimate
var _first_n := 0
const MEASURE_MIN_FRAMES := 30              ## shorter renders don't update the estimate (too noisy)


func start() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK and not DirAccess.dir_exists_absolute(out_dir):
		failed = "Could not make the folder %s" % out_dir
		return
	var f := FileAccess.open(TMP.path_join("map.mallet"), FileAccess.WRITE)
	if f == null:
		failed = "Could not write the render's copy of the map"
		return
	f.store_string(JSON.stringify(map))
	f.close()
	_exe = OS.get_executable_path()
	_next()


func _next() -> void:
	_i += 1
	if _i >= shots.size():
		done = true
		fraction = 1.0
		stage = "Finished: %d %s in %s" % [outputs.size(), "file" if outputs.size() == 1 else "files", out_dir]
		_clean(ProjectSettings.globalize_path(TMP), true)
		return
	_launch()


func shot_name(i: int) -> String:
	return String((shots[i]["shot"] as Dictionary).get("name", "Shot %d" % (i + 1)))


## A file name made of the map's and the shot's names (characters Windows refuses become _).
func output_name(i: int) -> String:
	var n := "%s - %s" % [base_name, shot_name(i)]
	for c in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		n = n.replace(c, "_")
	return n.strip_edges()


func _launch() -> void:
	_tmp = ProjectSettings.globalize_path(TMP).path_join("shot_%d" % _i)
	_clean(_tmp, false)
	DirAccess.make_dir_recursive_absolute(_tmp)
	_progress = _tmp.path_join("progress.json")
	_last = {}
	var job := {"map": ProjectSettings.globalize_path(TMP.path_join("map.mallet")), "shot": shots[_i]["shot"],
		"look_target": shots[_i].get("look_target"), "fps": fps, "width": width, "height": height, "progress": _progress}
	var job_path := _tmp.path_join("job.json")
	var f := FileAccess.open(job_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(job))
	f.close()
	var room := Vector2(DisplayServer.screen_get_usable_rect().size) * 0.8
	var k := minf(1.0, minf(room.x / width, room.y / height))
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])   # (the development copy)
	args.append_array(["--write-movie", _tmp.path_join("f.png" if format == "png" else "f.avi"), "--fixed-fps", str(fps),
		"--resolution", "%dx%d" % [roundi(width * k), roundi(height * k)], "--", ShotRender.FLAG, job_path])
	_pid = OS.create_process(_exe, args)
	_launched_at = Time.get_ticks_msec()
	_first_at = 0
	stage = "%s: starting MALLET for the render" % _shot_label()
	if _pid <= 0:
		failed = "Could not start %s for the render" % _exe.get_file()


func _shot_label() -> String:
	return "Shot %d of %d (%s)" % [_i + 1, shots.size(), shot_name(_i)] if shots.size() > 1 else shot_name(_i)


func _set_fraction(part: float) -> void:
	fraction = clampf((_i + clampf(part, 0.0, 1.0)) / maxf(shots.size(), 1), 0.0, 1.0)


## What this render took, kept for the next estimate: seconds per frame at this size, and the start-up (MALLET
## starting, the map loading, shaders warming up) per shot.
func _measure(total: int) -> void:
	var n := total - _first_n
	if _first_at == 0 or total < MEASURE_MIN_FRAMES or n <= 0:
		return
	var per_frame := (Time.get_ticks_msec() - _first_at) / 1000.0 / n
	Settings.set_value("render_measured", {"per_frame": per_frame, "pixels": width * height,
		"startup": (_first_at - _launched_at) / 1000.0, "size": "%dx%d" % [width, height], "fps": fps})


## A rough time for rendering `frames` frames at w x h in `shot_count` shots, from the last measured render
## (-1 = nothing measured yet). Drawing time grows with the pixels per frame, so a bigger size takes longer.
static func estimate(frames: int, w: int, h: int, shot_count: int) -> float:
	var m = Settings.value("render_measured")
	if not m is Dictionary or float(m.get("per_frame", 0.0)) <= 0.0:
		return -1.0
	var px := float(w * h) / maxf(float(m.get("pixels", 1)), 1.0)
	return frames * float(m["per_frame"]) * maxf(px, 0.25) + shot_count * float(m.get("startup", 15.0))


## Call often: follows the render and moves on to the next shot.
func tick() -> void:
	if done or failed != "" or canceled:
		return
	if _task >= 0:
		_mutex.lock()
		var written := int(_shared.get("written", 0))
		var total := int(_shared.get("total", 1))
		var what := String(_shared.get("what", "writing the file"))
		_mutex.unlock()
		stage = "%s: %s (%d of %d)" % [_shot_label(), what, written, total]
		_set_fraction(0.85 + 0.15 * written / maxf(total, 1))
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			var err := String(_shared.get("error", ""))
			if err != "":
				failed = err
				return
			outputs.append(String(_shared.get("output", "")))
			_next()
		return
	if _pid <= 0:
		return
	var txt := FileAccess.get_file_as_string(_progress) if FileAccess.file_exists(_progress) else ""
	var js := JSON.new()                                 # (quietly: the file may be caught half written)
	if txt != "" and js.parse(txt) == OK and js.data is Dictionary:
		_last = js.data
	match String(_last.get("stage", "")):
		"loading":
			stage = "%s: loading the map" % _shot_label()
			_set_fraction(0.02)
		"warmup":
			stage = "%s: warming up shaders" % _shot_label()
			_set_fraction(0.02 + 0.1 * float(_last.get("step", 0)) / maxf(float(_last.get("steps", 1)), 1.0))
		"frames":
			if _first_at == 0:
				_first_at = Time.get_ticks_msec()
				_first_n = int(_last.get("frame", 1))
			stage = "%s: frame %d of %d" % [_shot_label(), int(_last.get("frame", 0)), int(_last.get("frames", 1))]
			_set_fraction(0.12 + 0.73 * float(_last.get("frame", 0)) / maxf(float(_last.get("frames", 1)), 1.0))
		"done":
			stage = "%s: finishing" % _shot_label()
		"error":
			stage = "%s: %s" % [_shot_label(), String(_last.get("message", "error"))]
	if OS.is_process_running(_pid):
		return
	_pid = -1
	if String(_last.get("stage", "")) == "done":
		_measure(int(_last.get("frames", 1)))
	if String(_last.get("stage", "")) != "done":
		failed = "The render of %s stopped before the end%s." % [shot_name(_i),
			(": " + String(_last.get("message", ""))) if _last.has("message") else (" (it closed while %s)" % String(_last.get("stage", "starting")))]
		return
	_shared = {"dir": _tmp, "total": int(_last.get("frames", 1)), "written": 0, "format": format,
		"fps": fps, "width": width, "height": height, "out_dir": out_dir, "name": output_name(_i), "ffmpeg": ffmpeg}
	_task = WorkerThreadPool.add_task(_assemble)


## (On a worker thread.) The shot's frames -> the output.
func _assemble() -> void:
	_mutex.lock()
	var s := _shared.duplicate()
	_mutex.unlock()
	var dir: String = s["dir"]
	var out := ""
	if String(s["format"]) == "png":
		out = _assemble_png(s)
	else:
		out = String(s["out_dir"]).path_join(String(s["name"]) + ".avi")
		if String(s["format"]) == "mp4":
			out = dir.path_join("shot.avi")                 # (packed into an MP4 below, then removed)
		if not _assemble_avi(s, out):
			return
		if String(s["format"]) == "mp4":
			var mp4 := String(s["out_dir"]).path_join(String(s["name"]) + ".mp4")
			_put({"what": "making the MP4 with ffmpeg", "written": 0})
			var lines := []
			var code := OS.execute(String(s["ffmpeg"]), ["-y", "-loglevel", "error", "-i", out, "-c:v", "libx264",
				"-pix_fmt", "yuv420p", "-crf", "17", "-movflags", "+faststart", "-an", mp4], lines, true)
			if code != 0 or not FileAccess.file_exists(mp4):
				_put({"error": "ffmpeg could not make the MP4: %s" % ("".join(lines)).strip_edges().left(300)})
				return
			_put({"written": int(s["total"])})
			out = mp4
	if out == "":
		return
	_clean(dir, false)
	_put({"output": out})


## PNG pictures: the shot's frames (after the marker) move into a folder of their own, numbered from 0.
func _assemble_png(s: Dictionary) -> String:
	var dir: String = s["dir"]
	var total: int = s["total"]
	var frames := PackedStringArray()
	for n in DirAccess.get_files_at(dir):
		if n.begins_with("f") and n.ends_with(".png"):
			frames.append(n)
	frames.sort()
	var marker := _find_marker(frames.size(), total, func(j: int) -> bool: return _is_marker(Image.load_from_file(dir.path_join(frames[j]))))
	if marker < 0:
		_put({"error": "The render's frames are incomplete (%d frames, %d wanted)." % [frames.size(), total]})
		return ""
	var out := String(s["out_dir"]).path_join(String(s["name"]))
	DirAccess.make_dir_recursive_absolute(out)
	for old in DirAccess.get_files_at(out):
		if old.ends_with(".png"):
			DirAccess.remove_absolute(out.path_join(old))
	for i in total:
		var from := dir.path_join(frames[marker + 1 + i])
		var to := out.path_join("%s_%05d.png" % [String(s["name"]), i])
		if DirAccess.rename_absolute(from, to) != OK:
			DirAccess.copy_absolute(from, to)
		_put({"written": i + 1, "what": "saving the frames"})
	return out


## AVI: Movie Maker's own Motion-JPEG file holds everything from the start (loading, warm-up, marker); the shot's
## JPEG frames are copied as they are (no second compression) into a new file with the true size in its header.
func _assemble_avi(s: Dictionary, out: String) -> bool:
	var src: String = String(s["dir"]).path_join("f.avi")
	var total: int = s["total"]
	var chunks := AviWriter.video_chunks(src)
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null or chunks.is_empty():
		_put({"error": "The render's video file is missing or empty."})
		return false
	var read := func(j: int) -> PackedByteArray:
		f.seek(int(chunks[j][0]))
		return f.get_buffer(int(chunks[j][1]))
	var marker := _find_marker(chunks.size(), total, func(j: int) -> bool:
		var img := Image.new()
		return img.load_jpg_from_buffer(read.call(j)) == OK and _is_marker(img))
	if marker < 0:
		_put({"error": "The render's frames are incomplete (%d frames, %d wanted)." % [chunks.size(), total]})
		return false
	var avi := AviWriter.new()
	if not avi.open(out, int(s["width"]), int(s["height"]), int(s["fps"])):
		_put({"error": "Could not write %s (is it open in another program?)" % out})
		return false
	for i in total:
		if _canceled():
			avi.close()
			return false
		avi.add_jpeg(read.call(marker + 1 + i))
		_put({"written": i + 1, "what": "writing the video file"})
	avi.close()
	f.close()
	return true


## The last marker frame with the whole shot after it (frames 0..count-1), or -1.
static func _find_marker(count: int, total: int, is_marker: Callable) -> int:
	var hi := count - total - 1
	for j in range(hi, maxi(hi - 12, -1), -1):           # (where it should be: just before the shot's frames)
		if is_marker.call(j):
			return j
	for j in range(maxi(hi - 12, -1), -1, -1):           # (else anywhere earlier)
		if is_marker.call(j):
			return j
	return -1


func _canceled() -> bool:
	_mutex.lock()
	var c := bool(_shared.get("cancel", false))
	_mutex.unlock()
	return c


func _put(d: Dictionary) -> void:
	_mutex.lock()
	_shared.merge(d, true)
	_mutex.unlock()


static func _is_marker(img: Image) -> bool:
	if img == null or img.is_empty():
		return false
	var sz := img.get_size()
	for at in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
		var c := img.get_pixel(int(sz.x * at.x), int(sz.y * at.y))
		if c.r < 0.95 or c.g > 0.05 or c.b < 0.95:
			return false
	return true


func cancel() -> void:
	canceled = true
	stage = "Canceled"
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if _task >= 0:
		_put({"cancel": true})
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		for ext in [".avi", ".mp4"]:
			var partial := String(_shared.get("out_dir", "")).path_join(String(_shared.get("name", "")) + ext)
			if FileAccess.file_exists(partial):
				DirAccess.remove_absolute(partial)
	_clean(ProjectSettings.globalize_path(TMP), true)


## Remove a folder's files (and the folder itself with `whole`), recursing into folders.
static func _clean(dir: String, whole: bool) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(n))
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d), true)
	if whole:
		DirAccess.remove_absolute(dir)


## The user's own ffmpeg (on the PATH, or ffmpeg.exe next to MALLET), or "" (MALLET never ships one).
static func find_ffmpeg() -> String:
	var beside := OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg")
	if FileAccess.file_exists(beside):
		return beside
	var out := []
	var code := OS.execute("where" if OS.get_name() == "Windows" else "which", ["ffmpeg"], out, true)
	if code == 0 and not out.is_empty():
		var first := String(out[0]).strip_edges().split("\n")[0].strip_edges()
		if first != "" and FileAccess.file_exists(first):
			return first
	return ""
