class_name RenderDialog
extends ConfirmationDialog
## File > Render video... (0.30.0): which shots, the folder, size, frame rate and file type, then Render. Each shot
## is drawn by a second MALLET window (its live preview) under Godot's Movie Maker, so the video's timing is exact
## however fast the computer is. The progress bar shows each stage; Cancel stops it.

const SIZES := [["1280 x 720 (HD)", 1280, 720], ["1920 x 1080 (Full HD)", 1920, 1080], ["2560 x 1440 (QHD)", 2560, 1440],
	["3840 x 2160 (4K)", 3840, 2160], ["1080 x 1920 (vertical, for phones)", 1080, 1920], ["1080 x 1080 (square)", 1080, 1080],
	["Your own size", 0, 0]]
const RATES := [24, 25, 30, 50, 60, 120]

var ed: Node
var job: RenderJob = null
var ffmpeg := ""
var _shots: OptionButton
var _shot_ids: Array = []                    ## index in the editor's shots per item (-1 = all)
var _format: OptionButton
var _format_ids: Array = []
var _format_note: Label
var _size: OptionButton
var _w: SpinBox
var _h: SpinBox
var _custom_row: Control
var _rate: OptionButton
var _dir: LineEdit
var _dir_dialog: FileDialog
var _bar: ProgressBar
var _stage: Label
var _cancel: Button
var _open_folder: Button
var _summary: Label


func setup(editor: Node) -> void:
	ed = editor


func _ready() -> void:
	title = "Render video"
	ok_button_text = "Render"
	cancel_button_text = "Close"
	dialog_hide_on_ok = false
	min_size = Vector2i(560, 0)
	confirmed.connect(_render)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_shots = OptionButton.new()
	_shots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shots.item_selected.connect(func(_i: int): _update_summary())
	_row(grid, "Shots", _shots)
	var drow := HBoxContainer.new()
	_dir = LineEdit.new()
	_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dir.tooltip_text = "The folder the videos go to (made if it isn't there)"
	drow.add_child(_dir)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(func(): _dir_dialog.current_dir = _dir.text; _dir_dialog.popup_centered_ratio(0.6))
	drow.add_child(browse)
	_row(grid, "Folder", drow)
	_size = OptionButton.new()
	for s in SIZES:
		_size.add_item(s[0])
	_size.item_selected.connect(func(_i: int): _size_changed())
	_row(grid, "Size", _size)
	_custom_row = HBoxContainer.new()
	_w = _spin(320, 7680, 1920)
	_h = _spin(240, 4320, 1080)
	_custom_row.add_child(_w)
	var x := Label.new()
	x.text = " x "
	_custom_row.add_child(x)
	_custom_row.add_child(_h)
	_w.value_changed.connect(func(_v: float): _update_summary())
	_h.value_changed.connect(func(_v: float): _update_summary())
	_row(grid, "", _custom_row)
	_rate = OptionButton.new()
	for r in RATES:
		_rate.add_item("%d frames a second" % r)
	_rate.item_selected.connect(func(_i: int): _update_summary())
	_row(grid, "Frame rate", _rate)
	_format = OptionButton.new()
	_format.item_selected.connect(func(_i: int): _format_changed())
	_row(grid, "File type", _format)
	_format_note = Label.new()
	_format_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_format_note.custom_minimum_size = Vector2(520, 0)
	_format_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(_format_note)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(520, 0)
	box.add_child(_summary)
	box.add_child(HSeparator.new())
	_stage = Label.new()
	_stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stage.custom_minimum_size = Vector2(520, 0)
	_stage.text = "Ready."
	box.add_child(_stage)
	var prow := HBoxContainer.new()
	box.add_child(prow)
	_bar = ProgressBar.new()
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.custom_minimum_size = Vector2(0, 22)
	prow.add_child(_bar)
	_cancel = Button.new()
	_cancel.text = "Cancel"
	_cancel.disabled = true
	_cancel.tooltip_text = "Stop the render (the unfinished video is deleted)"
	_cancel.pressed.connect(cancel)
	prow.add_child(_cancel)
	_open_folder = Button.new()
	_open_folder.text = "Open folder"
	_open_folder.pressed.connect(func(): OS.shell_open(_dir.text))
	prow.add_child(_open_folder)
	_dir_dialog = FileDialog.new()
	_dir_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dir_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dir_dialog.use_native_dialog = true
	_dir_dialog.dir_selected.connect(func(d: String): _dir.text = d)
	add_child(_dir_dialog)


func _row(grid: GridContainer, label: String, c: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(c)


func _spin(lo: float, hi: float, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = v
	return s


## Fill it from the map's shots and the last settings, then show it.
func open() -> void:
	if ffmpeg == "":
		ffmpeg = RenderJob.find_ffmpeg()
	_shots.clear()
	_shot_ids.clear()
	var usable := []
	for i in ed.shots.size():
		if ((ed.shots[i] as Dictionary).get("keys", []) as Array).size() >= 2:
			usable.append(i)
	if usable.size() > 1:
		_shots.add_item("All shots (%d videos)" % usable.size())
		_shot_ids.append(-1)
	for i in usable:
		_shots.add_item(String((ed.shots[i] as Dictionary).get("name", "Shot")))
		_shot_ids.append(i)
	var cur: int = ed.shot_panel.cur
	var at := _shot_ids.find(cur)                         # (the shot being edited; else all of them)
	_shots.select(at if at >= 0 else 0)
	_format.clear()
	_format_ids = ["avi", "png"]
	_format.add_item("AVI video (Motion JPEG)")
	_format.add_item("PNG pictures (one file per frame)")
	if ffmpeg != "":
		_format_ids.append("mp4")
		_format.add_item("MP4 video (H.264, made by your ffmpeg)")
	var fmt := String(Settings.value("render_format"))
	_format.select(maxi(_format_ids.find(fmt), 0))
	var dir := String(Settings.value("render_dir"))
	if dir == "":
		dir = OS.get_system_dir(OS.SYSTEM_DIR_MOVIES).path_join("MALLET")
	if not job_running():
		_dir.text = dir
	var sz := String(Settings.value("render_size")).split("x")
	var w := int(sz[0]) if sz.size() == 2 else 1920
	var h := int(sz[1]) if sz.size() == 2 else 1080
	var pick := SIZES.size() - 1
	for i in SIZES.size():
		if SIZES[i][1] == w and SIZES[i][2] == h:
			pick = i
	_size.select(pick)
	_w.value = w
	_h.value = h
	_rate.select(maxi(RATES.find(int(Settings.value("render_fps"))), 0))
	_size_changed()
	_format_changed()
	_set_running(job_running())
	reset_size()
	popup_centered()


func _size_changed() -> void:
	var s: Array = SIZES[_size.selected]
	_custom_row.visible = s[1] == 0
	(_custom_row.get_parent().get_child(_custom_row.get_index() - 1) as Control).visible = s[1] == 0   # (its label too)
	if s[1] != 0:
		_w.value = s[1]
		_h.value = s[2]
	_update_summary()


func _format_changed() -> void:
	var f: String = _format_ids[_format.selected] if _format.selected >= 0 else "avi"
	match f:
		"png":
			_format_note.text = "One PNG picture per frame, in a folder per shot: the sharpest, and the biggest. Video editors import them as an image sequence."
		"mp4":
			_format_note.text = "MP4 is made with your own ffmpeg (%s): MALLET renders an AVI, then ffmpeg turns it into an MP4." % ffmpeg
		_:
			_format_note.text = "AVI with Motion JPEG (95% quality) plays in VLC and goes straight into DaVinci Resolve, Premiere and Shotcut."
	if ffmpeg == "":
		_format_note.text += "\nNo ffmpeg was found, so videos are AVI (or PNG pictures). MP4 is offered only when ffmpeg is found: install it from ffmpeg.org on your PATH, or put ffmpeg.exe next to MALLET.exe."
	_update_summary()


func _chosen_shots() -> Array:
	var id: int = _shot_ids[_shots.selected] if _shots.selected >= 0 and _shots.selected < _shot_ids.size() else -1
	var out := []
	for i in ed.shots.size():
		if (id == -1 or id == i) and ((ed.shots[i] as Dictionary).get("keys", []) as Array).size() >= 2:
			out.append(i)
	return out


func _update_summary() -> void:
	if _summary == null:
		return
	if _h.value > 0:
		ed.shot_panel.aspect = _w.value / _h.value       # (the 3D view's frame shows this video's shape)
		ed._redraw_overlays()
	var fps: int = RATES[maxi(_rate.selected, 0)]
	var frames := 0
	var secs := 0.0
	for i in _chosen_shots():
		var d := ShotPanel.path_of(ed.shots[i], ed).duration()
		secs += d
		frames += maxi(roundi(d * fps), 1)
	var w := int(_w.value)
	var h := int(_h.value)
	_summary.text = "%.1f seconds of video, %d frames, every one exactly %d x %d whatever your screen. A bigger size and a higher frame rate take longer to render (each frame is drawn in full)." % [
		secs, frames, w - w % 2, h - h % 2]
	var est := RenderJob.estimate(frames, w, h, _chosen_shots().size())
	var m = Settings.value("render_measured")
	if est >= 0.0 and m is Dictionary:
		_summary.text += "\nAbout %s, judging by your last render (%s, %.2f s a frame)." % [_duration_text(est), String(m.get("size", "")), float(m.get("per_frame", 0.0))]
	else:
		_summary.text += "\nHow long it takes is shown here after your first render of %d frames or more." % RenderJob.MEASURE_MIN_FRAMES
	_summary.text += " The render opens its own MALLET window (the preview); keep working here while it runs."


static func _duration_text(s: float) -> String:
	if s < 90.0:
		return "%d seconds" % maxi(roundi(s / 5.0) * 5, 5)
	if s < 5400.0:
		return "%d minutes" % roundi(s / 60.0)
	return "%.1f hours" % (s / 3600.0)


func job_running() -> bool:
	return job != null and not job.done and job.failed == "" and not job.canceled


func _set_running(on: bool) -> void:
	get_ok_button().disabled = on
	_cancel.disabled = not on


func _render() -> void:
	if job_running():
		return
	var ids := _chosen_shots()
	if ids.is_empty():
		_stage.text = "No shot with two keys or more to render."
		return
	var fmt: String = _format_ids[_format.selected]
	Settings.set_value("render_format", fmt)
	Settings.set_value("render_dir", _dir.text.strip_edges())
	Settings.set_value("render_size", "%dx%d" % [int(_w.value), int(_h.value)])
	Settings.set_value("render_fps", RATES[_rate.selected])
	job = make_job(ed, ids, _dir.text.strip_edges(), int(_w.value), int(_h.value), RATES[_rate.selected], fmt, ffmpeg)
	job.start()
	_set_running(true)


## A render of the editor's shots `ids` (also used by the tests).
static func make_job(editor: Node, ids: Array, dir: String, w: int, h: int, fps: int, fmt: String, ff := "") -> RenderJob:
	var j := RenderJob.new()
	j.map = editor._map_dict()
	var own: Dictionary = editor._own_materials(j.map)
	if not own.is_empty():
		j.map["own_materials"] = own
	for i in ids:
		var s: Dictionary = editor.shots[i]
		var t = ShotPanel.look_target(s, editor)
		j.shots.append({"shot": s.duplicate(true), "look_target": [t.x, t.y, t.z] if t is Vector3 else null})
	j.out_dir = dir
	var cp: String = editor.current_path
	j.base_name = cp.get_file().get_basename() if cp != "" else "MALLET"
	j.width = w - w % 2                                    # (even sizes: video players and ffmpeg want them)
	j.height = h - h % 2
	j.fps = fps
	j.format = fmt
	j.ffmpeg = ff
	return j


func cancel() -> void:
	if job_running():
		job.cancel()
		_stage.text = "Canceled. The unfinished video was deleted."
	_set_running(false)


func _process(_delta: float) -> void:
	if job == null:
		return
	if job_running():
		job.tick()
		_bar.value = job.fraction
		_stage.text = job.stage
		if not job_running():
			_set_running(false)
			if job.failed != "":
				_stage.text = "The render failed: " + job.failed
			else:
				_stage.text = job.stage
				ed._set_status("Render finished: %s" % ", ".join(Array(job.outputs).map(func(o: String) -> String: return o.get_file())))
