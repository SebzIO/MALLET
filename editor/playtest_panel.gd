class_name PlaytestPanel
extends PanelContainer
## The playtest panel (Export > Playtest panel): who is on the relay session right now, where they are in the run,
## and what their runs look like. It sits in the top right corner of the window and never takes a click meant for
## the views unless you are clicking its buttons.

signal leave_requested
signal copy_requested

const WIDTH := 430

var _title: Label
var _status: Label
var _tree: Tree
var _summary: Label


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13, 0.96)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	sb.border_color = Color(0.25, 0.28, 0.35)
	sb.set_border_width_all(1)
	add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_title = Label.new()
	_title.text = "Playtest"
	_title.add_theme_font_size_override("font_size", 16)
	box.add_child(_title)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_status.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	box.add_child(_status)
	var row := HBoxContainer.new()
	box.add_child(row)
	var copy := Button.new()
	copy.text = "Copy code"
	copy.focus_mode = Control.FOCUS_NONE
	copy.tooltip_text = "Put the session code on the clipboard, to paste into a chat."
	copy.pressed.connect(func(): copy_requested.emit())
	row.add_child(copy)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var leave := Button.new()
	leave.text = "Leave"
	leave.focus_mode = Control.FOCUS_NONE
	leave.tooltip_text = "Close the connection. Runs already received stay in the map."
	leave.pressed.connect(func(): leave_requested.emit())
	row.add_child(leave)
	_tree = Tree.new()
	_tree.columns = 5
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.custom_minimum_size = Vector2(WIDTH - 20, 190)
	for i in 5:
		_tree.set_column_title(i, ["Who", "Where", "Runs", "Best", "Finish"][i])
		_tree.set_column_expand(i, true)
	box.add_child(_tree)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_summary.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	box.add_child(_summary)


## Keep it in the top right corner of the window (controls under a CanvasLayer don't follow anchors).
func _process(_delta: float) -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - size.x - 18, 62)


## `peers` is Relay.peers (id -> {id, name, role, map_version}), `live` is tester id -> their last live message,
## `runs` is the map's tester sessions (the same shape Tester.read_runs / import_runs make).
func refresh(session: String, status: String, peers: Dictionary, live: Dictionary, runs: Array) -> void:
	_title.text = "Playtest — session %s" % session if session != "" else "Playtest"
	_status.text = status
	_tree.clear()
	var root := _tree.create_item()
	var people := {}
	for id in peers:
		var p: Dictionary = peers[id]
		people[String(p.get("name", "?"))] = {"role": String(p.get("role", "")), "live": live.get(id, {})}
	for s in runs:
		if s is Dictionary:
			var n := String(s.get("tester", "?"))
			if not people.has(n):
				people[n] = {"role": "tester", "live": {}}
	var names: Array = people.keys()
	names.sort()
	for n in names:
		var info: Dictionary = people[n]
		var item := _tree.create_item(root)
		item.set_text(0, String(n))
		item.set_text(1, _where(info["live"]))
		item.set_text(2, str(_count(runs, n)))
		item.set_text(3, _best(runs, n))
		item.set_text(4, _finish(runs, n))
		item.set_tooltip_text(0, "%s · %s" % [n, info["role"]] if info["role"] != "" else n)
	_summary.text = Tester.summary(runs) if not runs.is_empty() else "No runs yet: testers show up here as they play."


static func _where(live: Dictionary) -> String:
	if live.is_empty():
		return "-"
	match String(live.get("state", "")):
		"wait":
			return "at the start"
		"finish":
			return "finished"
	var stage := int(live.get("stage", 0))
	return ("stage %d · " % stage if stage > 0 else "") + "%d u/s" % int(live.get("speed", 0))


static func _sessions(runs: Array, who: String) -> Array:
	return runs.filter(func(s): return s is Dictionary and String(s.get("tester", "")) == who)


static func _count(runs: Array, who: String) -> int:
	var n := 0
	for s in _sessions(runs, who):
		n += (s.get("attempts", []) as Array).size()
	return n


static func _best(runs: Array, who: String) -> String:
	var best := 0.0
	for s in _sessions(runs, who):
		for a in (s.get("attempts", []) as Array):
			if a is Dictionary and String(a.get("outcome", "")) == "finish":
				var t := float(a.get("time", 0.0))
				if best <= 0.0 or (t > 0.0 and t < best):
					best = t
	return PlayMode.format_time(best) if best > 0.0 else "-"


static func _finish(runs: Array, who: String) -> String:
	var last := 0.0
	for s in _sessions(runs, who):
		for a in (s.get("attempts", []) as Array):
			if a is Dictionary and String(a.get("outcome", "")) == "finish":
				last = float(a.get("finish_speed", 0.0))
	return "%d u/s" % roundi(last) if last > 0.0 else "-"
