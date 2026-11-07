class_name Migrate
extends RefCounted
## MALLET used to be called SurfForge. Godot keeps each program's own data (user://) in a folder named after it, so
## on the first start MALLET copies your SurfForge settings, export folders, own materials and prefabs across. Once:
## a marker file says it's done, and nothing already in MALLET's folder is ever overwritten.

const OLD_NAME := "SurfForge"
const MARKER := ".copied_from_surfforge"
const CARRY := ["preferences.cfg", "settings.cfg", "materials", "prefabs"]


## Returns how many files were copied (0 when there was nothing to do).
static func from_surfforge(user_dir := "", old_dir := "") -> int:
	if user_dir == "":
		user_dir = OS.get_user_data_dir()
	if old_dir == "":
		old_dir = user_dir.get_base_dir().path_join(OLD_NAME)
	var marker := user_dir.path_join(MARKER)
	if FileAccess.file_exists(marker) or user_dir == old_dir or not DirAccess.dir_exists_absolute(old_dir):
		return 0
	DirAccess.make_dir_recursive_absolute(user_dir)
	var n := 0
	for item in CARRY:
		var src := old_dir.path_join(item)
		if DirAccess.dir_exists_absolute(src):
			n += _copy_dir(src, user_dir.path_join(item))
		elif FileAccess.file_exists(src):
			n += _copy_file(src, user_dir.path_join(item))
	var f := FileAccess.open(marker, FileAccess.WRITE)
	if f:
		f.store_string("Copied %d file(s) from %s\n" % [n, old_dir])
		f.close()
	if n > 0:
		Settings.reload()
	return n


static func _copy_file(src: String, dst: String) -> int:
	if FileAccess.file_exists(dst):
		return 0                                         # (never overwrite what's already in MALLET's folder)
	return 1 if DirAccess.copy_absolute(src, dst) == OK else 0


static func _copy_dir(src: String, dst: String) -> int:
	DirAccess.make_dir_recursive_absolute(dst)
	var n := 0
	for f in DirAccess.get_files_at(src):
		n += _copy_file(src.path_join(f), dst.path_join(f))
	for d in DirAccess.get_directories_at(src):
		n += _copy_dir(src.path_join(d), dst.path_join(d))
	return n
