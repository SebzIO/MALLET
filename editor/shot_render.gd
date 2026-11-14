class_name ShotRender
extends Node
## The render side of Render video (0.30.0). MALLET starts a second copy of itself with Godot's Movie Maker
## (`--write-movie <folder>/f.png --fixed-fps <fps> -- --mallet-render <job.json>`), so every frame is drawn at an
## exact time step however slow the machine is. This node runs in that copy: it loads the map from the job, hides
## the editor's own drawing, warms the shaders up, shows two all-magenta marker frames and then the shot, one frame
## per time step, and quits. Its window is the live preview. It reports each stage in the job's progress file, which
## the MALLET that started it reads (RenderJob); that MALLET then keeps the frames after the marker.

const FLAG := "--mallet-render"
const MARKER := Color(1, 0, 1)
const MARKER_FRAMES := 2
const WARM_STOPS := 24                       ## places along the shot the camera visits first (shaders, distant chunks)

var ed: Node
var job := {}
var _progress := ""


func run(editor: Node, job_path: String) -> void:
	ed = editor
	var data = JSON.parse_string(FileAccess.get_file_as_string(job_path)) if FileAccess.file_exists(job_path) else null
	if not data is Dictionary:
		printerr("MALLET render: no job at ", job_path)
		get_tree().quit(2)
		return
	job = data
	_progress = String(job.get("progress", ""))
	_go()


func _report(stage: String, extra := {}) -> void:
	if _progress == "":
		return
	var d := {"stage": stage, "frames_drawn": Engine.get_frames_drawn()}
	d.merge(extra, true)
	var f := FileAccess.open(_progress, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


func _fail(msg: String) -> void:
	printerr("MALLET render: ", msg)
	_report("error", {"message": msg})
	get_tree().quit(3)


func _go() -> void:
	var w := int(job.get("width", 1920))
	var h := int(job.get("height", 1080))
	var fps := int(job.get("fps", 60))
	var shot: Dictionary = job.get("shot", {})
	# the picture is drawn at the video's size whatever the window's (a window bigger than the screen gets cut)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = Vector2i(w, h)
	var room := Vector2(DisplayServer.screen_get_usable_rect(win.current_screen).size) * 0.8
	var k := minf(1.0, minf(room.x / w, room.y / h))
	win.size = Vector2i(roundi(w * k), roundi(h * k))
	win.move_to_center()
	win.title = "MALLET render: %s  (%d x %d, %d fps)" % [String(shot.get("name", "shot")), w, h, fps]
	_report("loading")
	ed.welcome.hide()
	var map = JSON.parse_string(FileAccess.get_file_as_string(String(job.get("map", ""))))
	if not map is Dictionary:
		_fail("could not read the map")
		return
	ed._load_dict(map)
	await get_tree().process_frame
	for cm in ed.cube_models_root.get_children():
		cm.finish_background()                           # (everything drawn in before the first frame)
		cm.merge_all()
	_presentation()
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 8000.0
	var vp: SubViewport = ed.panes[0].viewport
	vp.add_child(cam)
	cam.make_current()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var t = job.get("look_target")
	var path := CameraPath.new(shot, Vector3(float(t[0]), float(t[1]), float(t[2])) if t is Array else null)
	var total := maxi(roundi(path.duration() * fps), 1)
	for i in 5:
		await get_tree().process_frame
	# warm up: visit the shot (every material and shader it will see gets compiled now, not mid-video)
	for i in WARM_STOPS + 1:
		_pose(cam, path.sample(path.duration() * i / WARM_STOPS))
		_report("warmup", {"step": i, "steps": WARM_STOPS})
		for j in 3:
			await get_tree().process_frame
	_pose(cam, path.sample(0.0))
	for i in 20:
		await get_tree().process_frame
	# the marker: whole frames of pure magenta, so the frames before the shot can be told apart and dropped
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = MARKER
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var mask := cam.cull_mask
	var aa := vp.screen_space_aa
	cam.environment = env
	cam.cull_mask = 0
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	for i in MARKER_FRAMES:
		await get_tree().process_frame
	cam.environment = null
	cam.cull_mask = mask
	vp.screen_space_aa = aa
	for f in total:
		_pose(cam, path.sample(float(f) / fps))
		_report("frames", {"frame": f + 1, "frames": total})
		await get_tree().process_frame
	_report("done", {"frames": total})
	await get_tree().process_frame
	get_tree().quit()


func _pose(cam: Camera3D, s: Dictionary) -> void:
	cam.global_transform = s["xf"]
	cam.fov = float(s["fov"])


## Only the map, as players see it: no handles, zones, arrows, paths, bulbs or grid.
func _presentation() -> void:
	ed.set_presentation(true)
	ed.show_all_arcs = false
	ed.show_direction = false
	ed.show_ghost_path = false
	ed.show_tester_paths = false
	ed.show_co_editors = false
	ed._select(null)
	for p in ed.panes:
		p.overlay.visible = false
	if ed._ground_grid:
		ed._ground_grid.visible = false
	for cm in ed.cube_models_root.get_children():
		cm.set_show_mats(false)                          # (clip, noclip, death...: invisible, as in play mode and SurfsUp)
	for e in ed.entities_root.get_children():
		if e.is_volume():
			e.visible = false                            # (teleports, destinations, boosters, kill zones)
		else:
			e._zone_mesh.visible = false                 # (platforms stay; their zone outlines and arrows go)
			e._flat_arrow.visible = false
	LightNode.show_bulbs(ed.lights_root, false)
