class_name Outliner
extends VBoxContainer
## The Outliner: every object in the map in one list - ramps, platforms, zones, blocks, text, lights, props and cube
## objects - with names you choose, in folders you make (folders can hold folders). Click an object to select it;
## click a folder to select everything in it (then drag it in any view to move the lot). Drag items onto a folder to
## file them, double-click to rename, the eye hides things in the editor views. Names and folders save with the map
## (and come along in copy / paste and prefabs).

const KIND_COLORS := {"RampNode": Color(0.35, 0.6, 1.0), "EntityNode": Color(0.35, 0.85, 0.45), "BlockNode": Color(0.65, 0.68, 0.72),
	"TextNode": Color(0.95, 0.95, 0.95), "LightNode": Color(1.0, 0.85, 0.3), "PropNode": Color(1.0, 0.55, 0.25),
	"CubeModelNode": Color(0.3, 0.85, 0.8), "folder": Color(0.95, 0.75, 0.35)}

var editor: Node
var folders: Array = []                  ## [{"id", "name", "parent" ("" = top level), "open"}]
var tree := Tree.new()
var filter := LineEdit.new()
var _menu := PopupMenu.new()
var _signature := ""
var _syncing := false
var _icons := {}
var _eye: Texture2D
var _eye_off: Texture2D
var _menu_item: TreeItem


func setup(ed: Node) -> void:
	editor = ed


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	add_child(head)
	var title := Label.new()
	title.text = "Outliner"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var nf := Button.new()
	nf.text = "+ Folder"
	nf.focus_mode = Control.FOCUS_NONE
	nf.tooltip_text = "A new folder (what's selected goes into it)"
	nf.pressed.connect(func(): new_folder_from_selection())
	head.add_child(nf)
	filter.placeholder_text = "Find by name…"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(_t): refresh(true))
	add_child(filter)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.columns = 2
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 28)
	tree.allow_rmb_select = true
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	tree.multi_selected.connect(func(_i, _c, _s): _tree_selection_changed.call_deferred())
	tree.item_activated.connect(_rename_selected)
	tree.item_edited.connect(_item_edited)
	tree.button_clicked.connect(_button_clicked)
	tree.item_collapsed.connect(_item_collapsed)
	tree.item_mouse_selected.connect(func(_p, b): if b == MOUSE_BUTTON_RIGHT: _open_menu())
	tree.set_drag_forwarding(_get_drag, _can_drop, _drop)
	add_child(tree)
	var tip := Label.new()
	tip.text = "Click: select  ·  folder: select all in it  ·  drag onto a folder to file  ·  double-click: rename  ·  right-click: more"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	add_child(tip)
	_menu.id_pressed.connect(_menu_pressed)
	add_child(_menu)
	_eye = _make_eye(true)
	_eye_off = _make_eye(false)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


# ------------------------------------------------------------------------------------------------ names and folders
static func kind_name(o: Node) -> String:
	for k in KIND_COLORS:
		if o.get_script() != null and o.get_script().get_global_name() == k:
			return k
	return "Node"


## An object's name: the one you gave it, or "<kind> <n>".
func name_of(o: Node) -> String:
	if o.has_meta("name") and String(o.get_meta("name")) != "":
		return o.get_meta("name")
	var base: String = o.label() if o.has_method("label") else "Object"
	if o is RampNode:
		base = "Ramp"
	var n := 1
	for other in o.get_parent().get_children():
		if other == o:
			break
		if other.get_script() == o.get_script() and (not other.has_meta("name") or String(other.get_meta("name")) == ""):
			n += 1
	return "%s %d" % [base, n]


func folder(id: String) -> Dictionary:
	for f in folders:
		if f["id"] == id:
			return f
	return {}


func new_folder(name := "New folder", parent := "") -> String:
	var id := "f%d" % Time.get_ticks_usec()
	folders.append({"id": id, "name": name, "parent": parent, "open": true})
	refresh(true)
	return id


## + Folder: a new folder holding whatever is selected.
func new_folder_from_selection() -> String:
	editor._checkpoint()
	var objs: Array = editor.selection()
	var parent := ""
	if not objs.is_empty():
		parent = String(objs[0].get_meta("folder", ""))
	var id := new_folder("Folder %d" % (folders.size() + 1), parent)
	for o in objs:
		o.set_meta("folder", id)
	refresh(true)
	_edit_folder_name(id)
	return id


func move_to_folder(objs: Array, id: String) -> void:
	for o in objs:
		if id == "":
			o.remove_meta("folder") if o.has_meta("folder") else null
		else:
			o.set_meta("folder", id)
	refresh(true)


## Everything in a folder, and in the folders inside it.
func objects_in(id: String) -> Array:
	var ids := {id: true}
	var grew := true
	while grew:
		grew = false
		for f in folders:
			if not ids.has(f["id"]) and ids.has(f["parent"]):
				ids[f["id"]] = true
				grew = true
	return editor._all_objects().filter(func(o): return ids.has(String(o.get_meta("folder", ""))))


func delete_folder(id: String) -> void:
	var f := folder(id)
	if f.is_empty():
		return
	editor._checkpoint()
	for o in editor._all_objects():                       # what was in it moves up a level
		if String(o.get_meta("folder", "")) == id:
			if f["parent"] == "":
				o.remove_meta("folder")
			else:
				o.set_meta("folder", f["parent"])
	for g in folders:
		if g["parent"] == id:
			g["parent"] = f["parent"]
	folders.erase(f)
	refresh(true)


func set_hidden(objs: Array, hidden: bool) -> void:
	for o in objs:
		o.visible = not hidden
		if hidden:
			o.set_meta("hidden", true)
		elif o.has_meta("hidden"):
			o.remove_meta("hidden")
	refresh(true)


# ------------------------------------------------------------------------------------------------ the tree
## Rebuild the list if anything in it changed (cheap check every frame; `force` rebuilds now).
func refresh(force := false) -> void:
	if editor == null:
		return
	var objs: Array = editor._all_objects()
	var sig := PackedStringArray([filter.text, str(folders)])
	for o in objs:
		sig.append("%d|%s|%s|%s" % [o.get_instance_id(), name_of(o), o.get_meta("folder", ""), o.visible])
	var s := "\n".join(sig)
	if s == _signature and not force:
		return
	_signature = s
	_syncing = true
	tree.clear()
	var root := tree.create_item()
	var items := {"": root}
	var pending: Array = folders.duplicate()
	var guard := 0
	while not pending.is_empty() and guard < 64:            # parents before children
		guard += 1
		for f in pending.duplicate():
			var parent_id: String = f["parent"]
			if parent_id != "" and folder(parent_id).is_empty():
				parent_id = ""                           # its parent is gone: show it at the top
			if not items.has(parent_id):
				continue                                 # its parent isn't in the list yet: next pass
			var it := tree.create_item(items[parent_id])
			it.set_text(0, f["name"])
			it.set_icon(0, _icon("folder"))
			it.set_metadata(0, {"folder": f["id"]})
			it.collapsed = not f.get("open", true)
			var inside := objects_in(f["id"])
			var all_hidden := not inside.is_empty() and inside.all(func(o): return not o.visible)
			it.add_button(1, _eye_off if all_hidden else _eye, 0, false, "Show / hide everything in it")
			items[f["id"]] = it
			pending.erase(f)
	var q := filter.text.strip_edges().to_lower()
	for o in objs:
		var nm := name_of(o)
		if q != "" and not nm.to_lower().contains(q):
			continue
		var fid := String(o.get_meta("folder", ""))
		var parent: TreeItem = items.get(fid, root)
		var it := tree.create_item(parent)
		it.set_text(0, nm)
		it.set_icon(0, _icon(kind_name(o)))
		it.set_metadata(0, {"object": o})
		it.set_tooltip_text(0, "%s%s" % [o.label() if o.has_method("label") else "", " (in a group)" if o.has_meta("group") else ""])
		it.add_button(1, _eye if o.visible else _eye_off, 0, false, "Show / hide in the editor views")
		if not o.visible:
			it.set_custom_color(0, Color(0.55, 0.57, 0.62))
	_syncing = false
	sync_selection()


## Highlight what's selected in the views.
func sync_selection() -> void:
	if editor == null:
		return
	_syncing = true
	var sel: Array = editor.selection()
	var it := tree.get_root()
	var first: TreeItem = null
	while it:
		var meta = it.get_metadata(0)
		if meta is Dictionary and meta.has("object"):
			if meta["object"] in sel:
				it.select(0)
				if first == null:
					first = it
			else:
				it.deselect(0)
		it = it.get_next_in_tree()
	if first:
		tree.scroll_to_item(first)
	_syncing = false


func _tree_selection_changed() -> void:
	if _syncing:
		return
	var objs := []
	var it := tree.get_next_selected(null)
	while it:
		var meta = it.get_metadata(0)
		if meta is Dictionary:
			if meta.has("object") and not meta["object"] in objs:
				objs.append(meta["object"])
			elif meta.has("folder"):
				for o in objects_in(meta["folder"]):
					if not o in objs:
						objs.append(o)
		it = tree.get_next_selected(it)
	if objs.is_empty():
		return
	editor._set_selection(objs)
	editor._set_status("%s selected - drag in any view to move %s" % [
		name_of(objs[0]) if objs.size() == 1 else "%d objects" % objs.size(), "it" if objs.size() == 1 else "them together"])


func _rename_selected() -> void:
	var it := tree.get_selected()
	if it == null:
		return
	it.set_editable(0, true)
	tree.edit_selected(true)


func _edit_folder_name(id: String) -> void:
	var it := tree.get_root()
	while it:
		var meta = it.get_metadata(0)
		if meta is Dictionary and meta.get("folder", "") == id:
			it.select(0)
			it.set_editable(0, true)
			tree.edit_selected.call_deferred(true)
			return
		it = it.get_next_in_tree()


func _item_edited() -> void:
	var it := tree.get_edited()
	if it == null:
		return
	it.set_editable(0, false)
	rename(it.get_metadata(0), it.get_text(0))


## Give an object or folder (its tree metadata) a new name ("" = back to the automatic one for objects).
func rename(meta: Dictionary, new_name: String) -> void:
	var text := new_name.strip_edges()
	editor._checkpoint()
	if meta.has("folder"):
		var f := folder(meta["folder"])
		if not f.is_empty() and text != "":
			f["name"] = text
	elif meta.has("object"):
		var o: Node = meta["object"]
		if text == "":
			o.remove_meta("name") if o.has_meta("name") else null
		else:
			o.set_meta("name", text)
		editor._refresh_props()
	refresh.call_deferred(true)


func _button_clicked(item: TreeItem, _col: int, _id: int, _mb: int) -> void:
	var meta = item.get_metadata(0)
	editor._checkpoint()
	if meta.has("object"):
		var o: Node3D = meta["object"]
		set_hidden([o], o.visible)
	elif meta.has("folder"):
		var inside := objects_in(meta["folder"])
		var any_shown := inside.any(func(o): return o.visible)
		set_hidden(inside, any_shown)


func _item_collapsed(item: TreeItem) -> void:
	if _syncing:
		return
	var meta = item.get_metadata(0)
	if meta is Dictionary and meta.has("folder"):
		var f := folder(meta["folder"])
		if not f.is_empty():
			f["open"] = not item.collapsed


# ------------------------------------------------------------------------------------------------ drag and drop
func _get_drag(_at: Vector2):
	var dragged := []
	var it := tree.get_next_selected(null)
	while it:
		dragged.append(it.get_metadata(0))
		it = tree.get_next_selected(it)
	if dragged.is_empty():
		return null
	var l := Label.new()
	l.text = "%d item(s)" % dragged.size()
	set_drag_preview(l)
	return {"outliner": dragged}


func _can_drop(_at: Vector2, data) -> bool:
	return data is Dictionary and data.has("outliner")


func _drop(at: Vector2, data) -> void:
	var target := tree.get_item_at_position(at)
	var dest := ""
	if target:
		var meta = target.get_metadata(0)
		if meta.has("folder"):
			dest = meta["folder"]
			if tree.get_drop_section_at_position(at) != 0:      # dropped beside a folder: next to it, not in it
				dest = folder(dest).get("parent", "")
		elif meta.has("object"):
			dest = String(meta["object"].get_meta("folder", ""))
	editor._checkpoint()
	for m in data["outliner"]:
		if m.has("object"):
			if dest == "":
				if m["object"].has_meta("folder"):
					m["object"].remove_meta("folder")
			else:
				m["object"].set_meta("folder", dest)
		elif m.has("folder") and m["folder"] != dest and not _is_inside(dest, m["folder"]):
			folder(m["folder"])["parent"] = dest
	refresh(true)


## Is folder `id` inside folder `outer` (or the same)?
func _is_inside(id: String, outer: String) -> bool:
	var cur := id
	var guard := 0
	while cur != "" and guard < 64:
		if cur == outer:
			return true
		cur = folder(cur).get("parent", "")
		guard += 1
	return false


# ------------------------------------------------------------------------------------------------ right-click menu
func _open_menu() -> void:
	_menu.clear()
	_menu.add_item("Rename (double-click)", 1)
	_menu.add_item("New folder with the selection", 2)
	_menu.add_item("Move the selection out of its folder", 3)
	_menu.add_separator()
	_menu.add_item("Hide", 4)
	_menu.add_item("Show", 5)
	_menu.add_item("Show everything", 6)
	var it := tree.get_selected()
	if it and (it.get_metadata(0) as Dictionary).has("folder"):
		_menu.add_separator()
		_menu.add_item("Delete this folder (keeps what's in it)", 7)
	_menu.position = Vector2i(get_viewport().get_mouse_position()) + get_window().position
	_menu.reset_size()
	_menu.popup()


func _menu_pressed(id: int) -> void:
	var objs: Array = editor.selection()
	match id:
		1: _rename_selected()
		2: new_folder_from_selection()
		3:
			editor._checkpoint()
			move_to_folder(objs, "")
		4:
			editor._checkpoint()
			set_hidden(objs, true)
		5:
			editor._checkpoint()
			set_hidden(objs, false)
		6:
			editor._checkpoint()
			set_hidden(editor._all_objects(), false)
		7:
			var it := tree.get_selected()
			if it:
				delete_folder((it.get_metadata(0) as Dictionary)["folder"])


# ------------------------------------------------------------------------------------------------ icons
func _icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: Color = KIND_COLORS.get(kind, Color.GRAY)
	if kind == "folder":
		img.fill_rect(Rect2i(1, 4, 12, 9), c)
		img.fill_rect(Rect2i(1, 2, 5, 3), c)
	else:
		img.fill_rect(Rect2i(2, 2, 10, 10), c)
		img.fill_rect(Rect2i(3, 3, 8, 8), c.darkened(0.25))
	var t := ImageTexture.create_from_image(img)
	_icons[kind] = t
	return t


static func _make_eye(open: bool) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.85, 0.88, 0.92) if open else Color(0.45, 0.47, 0.52)
	for x in 16:
		for y in 16:
			var dx := (x - 7.5) / 7.0
			var dy := (y - 7.5) / 4.0
			if dx * dx + dy * dy <= 1.0 and dx * dx + dy * dy >= 0.55:
				img.set_pixel(x, y, c)
			if open and (x - 7.5) * (x - 7.5) + (y - 7.5) * (y - 7.5) <= 4.0:
				img.set_pixel(x, y, c)
	if not open:
		for i in 14:
			img.set_pixel(1 + i, 14 - i, c)
	return ImageTexture.create_from_image(img)
