extends SceneTree
## Regression: zoom the front view right in on the selected ramp; nothing from it may be drawn in the perspective view.
func _init():
	call_deferred("_run")
func _run():
	var ed = load("res://editor/main.tscn").instantiate()
	root.add_child(ed)
	for i in 3: await process_frame
	ed._select(ed.ramps_root.get_child(0))
	var front: ViewPane = ed.panes[2]
	front.frame(Vector3(0, 78, 0), 20)              # zoomed in, ramp just above the view: its outline extends past the top edge
	ed.panes[0].frame(Vector3(0, -2000, 0), 30)     # point the perspective view at empty sky
	for i in 6: await process_frame
	var img := root.get_viewport().get_texture().get_image()
	print("outline pixels drawn inside the perspective view by other views: ", count(img, ed.panes[0].get_global_rect().grow(-4)))
	# and the overlays must still draw in their own view (the first version of the fix clipped everything away)
	var fr: Rect2 = ed.panes[2].get_global_rect().grow(-4)
	print("outline pixels inside the front view itself (must be > 0): ", count(img, fr))
	var grid := 0
	for x in range(int(fr.position.x), int(fr.end.x)):
		if img.get_pixel(x, int(fr.get_center().y)).r > 0.2:
			grid += 1
	print("grid/label pixels across the front view (must be > 0): ", grid)
	img.save_png("D:/SurfForge/tests/out/clip_test.png")
	quit()


func count(img: Image, rect: Rect2) -> int:
	var n := 0
	for y in range(int(rect.position.y), int(rect.end.y), 2):
		for x in range(int(rect.position.x), int(rect.end.x), 2):
			var c := img.get_pixel(x, y)
			if c.b > 0.85 and c.r < 0.45 and c.g > 0.6:  # the outline colour (0.3, 0.75, 1.0)
				n += 1
	return n
