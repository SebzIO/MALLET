class_name PlaytestPanel
extends PanelContainer
## The playtest panel (its own toolbar button; Export > Playtest session starts one): who is on the relay session
## right now, where they are in the run, and what their runs look like. It sits in the top right corner of the window
## and never takes a click meant for the views unless you are clicking its buttons. The - in its title row collapses
## it to that row, and it stays collapsed next time.

signal leave_requested
signal copy_requested
signal remove_requested(id: String)

const WIDTH := 430

var _title: Label
var _status: Label
var _tree: Tree
var _summary: Label
var _remove: OptionButton
var _invite: LineEdit
var _body: VBoxContainer
var _min: Button
var minimized := false


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()                        # the title row: it stays when the panel is collapsed
	box.add_child(head)
	_title = Label.new()
	_title.text = "Playtest"
	_title.add_theme_font_size_override("font_size", 16)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_min = Button.new()
	_min.text = "-"
	_min.focus_mode = Control.FOCUS_NONE
	_min.custom_minimum_size = Vector2(34, 0)
	_min.pressed.connect(func(): set_minimized(not minimized))
	head.add_child(_min)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_status.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	_body.add_child(_status)
	_invite = LineEdit.new()                               # what the owner sends: address, code and secret
	_invite.editable = false
	_invite.tooltip_text = "Send this to the other person: they tick \"Join as a co-editor\" and type the code and secret."
	_invite.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_invite.visible = false
	_body.add_child(_invite)
	var row := HBoxContainer.new()
	_body.add_child(row)
	var copy := Button.new()
	copy.text = "Copy invite"
	copy.focus_mode = Control.FOCUS_NONE
	copy.tooltip_text = "Put the relay address, session code and secret on the clipboard, as one line to paste into a chat."
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
	_remove = OptionButton.new()                            # the map's owner's list of who to put out
	_remove.focus_mode = Control.FOCUS_NONE
	_remove.tooltip_text = "Remove someone from this session. The code still works: they can rejoin with it."
	_remove.item_selected.connect(_on_remove_chosen)
	_remove.visible = false
	_body.add_child(_remove)
	_tree = Tree.new()
	_tree.columns = 5
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.custom_minimum_size = Vector2(WIDTH - 20, 190)
	for i in 5:
		_tree.set_column_title(i, ["Who", "Where", "Runs", "Best", "Finish"][i])
		_tree.set_column_expand(i, true)
	_body.add_child(_tree)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(WIDTH - 20, 0)
	_summary.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_body.add_child(_summary)
	set_minimized(bool(Settings.value("playtest_minimized")))


## Collapse the panel to its title row (the session stays open). Remembered for next time.
func set_minimized(on: bool) -> void:
	minimized = on
	if _body != null:
		_body.visible = not on
	if _min != null:
		_min.text = "▸" if on else "-"
		_min.tooltip_text = "Show who is on the session and their runs." if on else "Collapse the panel to its title."
	if bool(Settings.value("playtest_minimized")) != on:
		Settings.set_value("playtest_minimized", on)
	reset_size()


## Keep it in the top right corner of the window (controls under a CanvasLayer don't follow anchors).
func _process(_delta: float) -> void:
	if not visible:
		return
	var vp := get_viewport().get_visible_rect().size
	position = Vector2(vp.x - size.x - 18, 62)


## `peers` is Relay.peers (id -> {id, name, role, map_version}), `live` is tester id -> their last live message,
## `runs` is the map's tester sessions (the same shape Tester.read_runs / import_runs make).
func refresh(session: String, status: String, peers: Dictionary, live: Dictionary, runs: Array, owner := false, invite := "") -> void:
	_title.text = "Playtest — session %s" % session if session != "" else "Playtest"
	_status.text = status
	_invite.text = invite
	_invite.visible = invite != ""
	_fill_remove(peers, owner)
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


## The owner's "remove someone" list: the co-editors in the session, by name.
func _fill_remove(peers: Dictionary, owner: bool) -> void:
	_remove.clear()
	_remove.add_item("Remove someone…")
	var names: Array = []
	for id in peers:
		var p: Dictionary = peers[id]
		if String(p.get("role", "")) != "editor":
			continue
		names.append([String(p.get("name", "?")), String(id)])
	names.sort()
	for pair in names:
		var i := _remove.item_count
		_remove.add_item(pair[0], i)
		_remove.set_item_metadata(i, pair[1])
	_remove.visible = owner and not names.is_empty()


func _on_remove_chosen(i: int) -> void:
	var id := String(_remove.get_item_metadata(i)) if i > 0 else ""
	_remove.select(0)
	if id != "":
		remove_requested.emit(id)


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
