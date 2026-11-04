extends SceneTree
## Regression: editor view cameras must never be physics-interpolated. When they were, the 3D image trailed the
## true camera (most visibly after zooming) while outlines/handles/arcs were drawn with the true camera.
func _init():
	call_deferred("_run")
func _run():
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	await process_frame
	var bad := 0
	for p in ed.panes:
		if p.camera.is_physics_interpolated_and_enabled():
			bad += 1
			print("  interpolated camera in ", ViewPane.NAMES[p.kind])
	for e in ed.entities_root.get_children() + ed.ramps_root.get_children():
		if e.is_physics_interpolated_and_enabled():
			bad += 1
	print("interpolated editor cameras/objects: ", bad, " (must be 0)")
	ed._play_clicked()
	await physics_frame
	print("play-mode player interpolated (should be true, like SurfsUp): ", ed.play.player.is_physics_interpolated_and_enabled())
	ed.play.stop()
	quit()
