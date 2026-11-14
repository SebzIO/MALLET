class_name Trail
extends RefCounted
## A short trail of what was just done (keys, clicks, cube edits, background redraws), written to
## user://logs/actions.log and flushed line by line, so after a crash it says what MALLET was doing. The session
## before is kept as actions_previous.log. Only the main thread writes here.

const PATH := "user://logs/actions.log"
const PREVIOUS := "user://logs/actions_previous.log"
const MAX_LINES := 5000                  ## a long session starts the file again (the trail before a crash is what matters)

static var _file: FileAccess
static var off := false                  ## (a video render started by MALLET: it leaves the user's trail alone)
static var _lines := 0
static var _t0 := 0


static func note(text: String) -> void:
	if off or OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return                                           # (a test script, not MALLET itself: leave the real trail alone)
	if _file == null or _lines >= MAX_LINES:
		_open()
		if _file == null:
			return
	_file.store_line("%9.3f  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])
	_file.flush()
	_lines += 1


static func _open() -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	if _file == null:                                    # (a new session: keep the last one's trail)
		if FileAccess.file_exists(PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS))
			DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PREVIOUS))
		_t0 = Time.get_ticks_msec()
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	_lines = 0
	if _file:
		_file.store_line("%s  %s  (seconds since start)" % [MalletVersion.full(), Time.get_datetime_string_from_system()])
