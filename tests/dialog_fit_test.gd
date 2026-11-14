extends SceneTree
## Every dialog fits the screen with its buttons showing (0.18.16: the Export dialog grew past a 900-pixel screen,
## its wrapped text measured before it had a width, so the Export button was off the bottom).
## Run: godot --path . --resolution 1600x900 -s res://tests/dialog_fit_test.gd -- <out folder>

var ok := true


func check(label: String, good: bool, detail := "") -> void:
	print("%-72s %s %s" % [label, "OK  " if good else "FAIL", detail])
	ok = ok and good


func _init() -> void:
	call_deferred("_run")


func fits(d: Window) -> bool:
	var screen := Rect2i(Vector2i.ZERO, root.size)
	if not screen.encloses(Rect2i(d.position, d.size)):
		return false
	if d is AcceptDialog:
		var b: Button = (d as AcceptDialog).get_ok_button()
		var r := Rect2i(b.get_global_rect())
		return b.is_visible_in_tree() and Rect2i(Vector2i.ZERO, d.size).encloses(r)
	return true


func _run() -> void:
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	ed.welcome.hide()
	ed._export_clicked()
	for i in 5: await process_frame
	check("the Export dialog fits the screen, Export button showing", fits(ed._export_dialog), "(%s at %s)" % [ed._export_dialog.size, ed._export_dialog.position])
	ed._export_dialog.hide()
	ed._export_clicked()                                  # (opened a second time: still the same size)
	for i in 5: await process_frame
	check("...and the same the second time", fits(ed._export_dialog) and ed._export_dialog.size.y < 400, "(%s)" % ed._export_dialog.size)
	ed._export_dialog.hide()
	# every other dialog, as built
	var found := 0
	var bad := []
	for w in ed.find_children("*", "AcceptDialog", true, false):
		if w == ed._export_dialog or w is FileDialog:
			continue
		found += 1
		w.popup_centered()
		for i in 3: await process_frame
		if not fits(w):
			bad.append("%s %s (%s)" % [w.title, w.size, w.get_class()])
		w.hide()
		await process_frame
	check("the other %d dialogs fit the screen with their buttons showing" % found, bad.is_empty(), str(bad))
	print("dialog_fit_test: ", "PASS" if ok else "FAIL")
	quit()
