class_name MalletVersion
extends RefCounted
## The one place MALLET's version lives. 0.x = previews: the middle number goes up with each batch of new
## features, the last with bug-fix releases. 1.0 is the first release we call complete (the MVP).

const VERSION := "0.30.3"
const CHANNEL := "preview"
## One line for the welcome screen: what this version brought.
const NEWS := "CS:S: ramps have no more cracks or black lines between their pieces, and fewer pieces overall."


## The guide (docs/GUIDE.html next to MALLET.exe; in the project, res://docs/GUIDE.html), or another page in docs.
static func doc_path(file := "GUIDE.html") -> String:
	var shipped := OS.get_executable_path().get_base_dir().path_join("docs").path_join(file)
	if FileAccess.file_exists(shipped):
		return shipped
	return ProjectSettings.globalize_path("res://docs/" + file)


## Open a page of the docs in the browser. False if it isn't there.
static func open_doc(file := "GUIDE.html") -> bool:
	var p := doc_path(file)
	if not FileAccess.file_exists(p):
		return false
	OS.shell_open("file:///" + p.replace("\\", "/"))
	return true


static func full() -> String:
	return "MALLET %s %s" % [VERSION, CHANNEL]
