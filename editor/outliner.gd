class_name Outliner
extends VBoxContainer
## The Outliner: every object in the map in one list - ramps, platforms, zones, blocks, text, lights, props and cube
## objects - with names you choose, in folders you make (folders can hold folders). Click an object to select it;
## click a folder to select everything in it (then drag it in any view to move the lot). Drag items onto a folder to
## file them, double-click to rename, the eye hides things in the editor views, the padlock locks them (0.24.0: a
## locked object can't be moved, edited or deleted, or picked in the views; a locked folder locks everything in it).
## Names, folders and locks save with the map (and come along in copy / paste and prefabs).

const KIND_COLORS := {"RampNode": Color(0.35, 0.6, 1.0), "EntityNode": Color(0.35, 0.85, 0.45), "BlockNode": Color(0.65, 0.68, 0.72),
	"TextNode": Color(0.95, 0.95, 0.95), "LightNode": Color(1.0, 0.85, 0.3), "ParticleNode": Color(1.0, 0.5, 0.8), "PropNode": Color(1.0, 0.55, 0.25),
	"CubeModelNode": Color(0.3, 0.85, 0.8), "folder": Color(0.95, 0.75, 0.35)}

var editor: Node
var folders: Array = []                  ## [{"id", "name", "parent" ("" = top level), "open"}]
var tree := Tree.new()
var filter := LineEdit.new()
var _menu := PopupMenu.new()
var _right_at := Vector2(-1, -1)
var _signature := ""
var _syncing := false
var _icons := {}
var _eye: Texture2D
var _eye_off: Texture2D
var _lock_on: Texture2D
var _lock_off: Texture2D
var _lock_folder: Texture2D              ## locked because its folder is
var _menu_item: TreeItem
var _anchor: TreeItem                    ## where a Shift-click range starts (the last plain or Ctrl click)
var _pending_single: TreeItem            ## pressed on an already-selected item: becomes the only one on release (no drag)


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
	tree.columns = 3
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 28)
	tree.set_column_expand(2, false)
	tree.set_column_custom_minimum_width(2, 28)
	tree.allow_rmb_select = true
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
	tree.multi_selected.connect(func(_i, _c, _s): _tree_selection_changed.call_deferred())
	tree.gui_input.connect(_tree_input)
	tree.item_edited.connect(_item_edited)
	tree.button_clicked.connect(_button_clicked)
	tree.item_collapsed.connect(_item_collapsed)
	tree.item_mouse_selected.connect(func(_p, b): if b == MOUSE_BUTTON_RIGHT: _open_menu(_right_at))
	tree.set_drag_forwarding(_get_drag, _can_drop, _drop)
	add_child(tree)
	var tip := Label.new()
	tip.text = "Click: select  ·  folder: select all in it  ·  drag onto a folder to file  ·  double-click: rename  ·  padlock: lock  ·  right-click: more"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", Color(0.6, 0.64, 0.7))
	add_child(tip)
	_menu.id_pressed.connect(_menu_pressed)
	add_child(_menu)
	_eye = _make_eye(true)
	_eye_off = _make_eye(false)
	_lock_on = _make_lock(true, Color(1.0, 0.72, 0.25))
	_lock_off = _make_lock(false, Color(0.45, 0.47, 0.52))
	_lock_folder = _make_lock(true, Color(0.7, 0.55, 0.3))


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
	editor._co_send_folders()
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
		editor._co_touch(o)
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
			editor._co_touch(o)
	for g in folders:
		if g["parent"] == id:
			g["parent"] = f["parent"]
	folders.erase(f)
	editor._co_send_folders()
	refresh(true)


# ------------------------------------------------------------------------------------------------ locks
## Locked: by its own padlock, or because a folder it is in (at any depth) is locked.
func is_locked(o: Node) -> bool:
	return bool(o.get_meta("locked", false)) or folder_locked(String(o.get_meta("folder", "")))


## A folder is locked by its own padlock or by a folder above it.
func folder_locked(id: String) -> bool:
	var guard := 0
	while id != "" and guard < 64:
		guard += 1
		var f := folder(id)
		if f.is_empty():
			return false
		if bool(f.get("locked", false)):
			return true
		id = String(f.get("parent", ""))
	return false


func set_locked(objs: Array, on: bool) -> void:
	for o in objs:
		if on:
			o.set_meta("locked", true)
		elif o.has_meta("locked"):
			o.remove_meta("locked")
		editor._co_touch(o)
	editor._lock_changed()
	refresh(true)


func set_folder_locked(id: String, on: bool) -> void:
	var f := folder(id)
	if f.is_empty():
		return
	if on:
		f["locked"] = true
	else:
		f.erase("locked")
	editor._co_send_folders()
	editor._lock_changed()
	refresh(true)


static func _make_lock(closed: bool, c: Color) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(3, 8, 10, 7), c)                # the body
	img.fill_rect(Rect2i(7, 10, 2, 3), Color(0.1, 0.1, 0.12, 1.0))   # the keyhole
	var lift := 0 if closed else 2                       # (open: the shackle lifted, its left leg out)
	img.fill_rect(Rect2i(5, 2 - lift + 2, 6, 2), c)      # the shackle's top
	img.fill_rect(Rect2i(10, 4 - lift + 2, 2, 4 + lift - 2), c)   # its right leg
	if closed:
		img.fill_rect(Rect2i(4, 4, 2, 4), c)             # its left leg, into the body
	return ImageTexture.create_from_image(img)


func set_hidden(objs: Array, hidden: bool) -> void:
	for o in objs:
		o.visible = not hidden
		if hidden:
			o.set_meta("hidden", true)
		elif o.has_meta("hidden"):
			o.remove_meta("hidden")
		editor._co_touch(o)
	refresh(true)


# ------------------------------------------------------------------------------------------------ the tree
## Rebuild the list if anything in it changed (cheap check every frame; `force` rebuilds now).
func refresh(force := false) -> void:
	if editor == null or (is_renaming() and not force):
		return                                           # (rebuilding would close a name being typed)
	var objs: Array = editor._all_objects()
	var sig := PackedStringArray([filter.text, str(folders)])
	for o in objs:
		sig.append("%d|%s|%s|%s|%s" % [o.get_instance_id(), name_of(o), o.get_meta("folder", ""), o.visible, o.get_meta("locked", false)])
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
			var own_lock := bool(f.get("locked", false))
			var above := folder_locked(String(f.get("parent", "")))
			it.add_button(2, _lock_on if own_lock else (_lock_folder if above else _lock_off), 1, false,
				"Unlock this folder" if own_lock else ("Locked by a folder it is in" if above else "Lock everything in this folder"))
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
		var own := bool(o.get_meta("locked", false))
		var by_folder := folder_locked(fid)
		it.add_button(2, _lock_on if own else (_lock_folder if by_folder else _lock_off), 1, false,
			"Unlock it" if own else ("Locked by its folder (unlock the folder)" if by_folder else "Lock it: it can't be moved, edited or deleted"))
		if not o.visible:
			it.set_custom_color(0, Color(0.55, 0.57, 0.62))
		elif own or by_folder:
			it.set_custom_color(0, Color(1.0, 0.82, 0.55))
	_syncing = false
	sync_selection()


## Highlight what's selected in the views.
func sync_selection() -> void:
	if editor == null or is_renaming():
		return                                           # never while a name is being typed (it would close the box)
	_syncing = true
	var sel: Array = editor.selection()
	var it := tree.get_root()
	var first: TreeItem = null
	while it:
		var meta = it.get_metadata(0)
		if meta is Dictionary and meta.has("object"):
			if meta["object"] in sel:
				if not it.is_selected(0):
					it.select(0)
				if first == null:
					first = it
			elif it.is_selected(0):
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


## Clicks work like Windows lists: click = just this one, Ctrl+click = add / remove it, Shift+click = everything from
## the last clicked row to this one (Ctrl+Shift adds that range), double-click = rename. Pressing on a row that's
## already selected keeps the selection (so several can be dragged) until the button comes up without a drag.
func _tree_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_F and not (ev.ctrl_pressed or ev.alt_pressed or ev.meta_pressed):
		editor._frame_clicked()                          # F: focus the selection, as in the views
		tree.accept_event()
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		_right_at = tree.get_global_transform_with_canvas() * ev.position     # (where the menu opens)
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var item := tree.get_item_at_position(ev.position)
	if ev.pressed:
		if item == null:
			_select_items([])
			_anchor = null
			tree.accept_event()
			return
		if tree.get_column_at_position(ev.position) in [1, 2] or _on_arrow(item, ev.position.x):
			return                                       # the eye / the padlock / the fold arrow: the tree's own
		if ev.double_click:
			_select_items([item])
			_anchor = item
			_rename_selected(item)
			tree.accept_event()
			return
		var rows := _visible_rows()
		if ev.shift_pressed and _anchor != null and rows.has(_anchor):
			var a := rows.find(_anchor)
			var b := rows.find(item)
			var range_rows := rows.slice(mini(a, b), maxi(a, b) + 1)
			if ev.ctrl_pressed:
				for r in _selected_rows():
					if not r in range_rows:
						range_rows.append(r)
			_select_items(range_rows)
		elif ev.ctrl_pressed or ev.meta_pressed:
			var now := _selected_rows()
			if item in now:
				now.erase(item)
			else:
				now.append(item)
			_select_items(now)
			_anchor = item
		elif item.is_selected(0) and _selected_rows().size() > 1:
			_pending_single = item                       # maybe the start of dragging them all
		else:
			_select_items([item])
			_anchor = item
		tree.accept_event()
	else:
		if _pending_single != null and not get_viewport().gui_is_dragging():
			_select_items([_pending_single])
			_anchor = _pending_single
		_pending_single = null


## Is x (in the tree) on this row's fold arrow?
func _on_arrow(item: TreeItem, x: float) -> bool:
	if item.get_child_count() == 0:
		return false
	var depth := 0
	var p := item.get_parent()
	while p != null and p != tree.get_root():
		depth += 1
		p = p.get_parent()
	var margin := float(tree.get_theme_constant("item_margin"))
	var left := tree.get_item_area_rect(item, 0).position.x
	return x >= left + depth * margin - 2.0 and x <= left + (depth + 1) * margin + 2.0


func _visible_rows() -> Array:
	var out := []
	var it := tree.get_root().get_next_visible() if tree.get_root() else null
	while it:
		out.append(it)
		it = it.get_next_visible()
	return out


func _selected_rows() -> Array:
	var out := []
	var it := tree.get_next_selected(null)
	while it:
		out.append(it)
		it = tree.get_next_selected(it)
	return out


func _select_items(rows: Array) -> void:
	_syncing = true
	tree.deselect_all()
	for r in rows:
		(r as TreeItem).select(0)
	_syncing = false
	if rows.is_empty():
		editor._set_selection([])
	else:
		_tree_selection_changed()


## Rename a row: the one you double-clicked, else the last row you clicked, else the first selected one.
func _rename_selected(it: TreeItem = null) -> void:
	if it == null:
		it = _anchor if _anchor != null and _anchor.is_selected(0) else tree.get_next_selected(null)
	if it == null:
		return
	rename_row(it)


## Is a name being typed? (The tree's own name box is open.)
func is_renaming() -> bool:
	for c in tree.get_children(true):
		if c is Window and (c as Window).visible:
			return true
	return false


## Start typing a new name into this row. (The tree edits the row its cursor is on, which isn't always the one
## that's highlighted - so put the cursor on it first.)
func rename_row(it: TreeItem) -> void:
	tree.set_selected(it, 0)
	it.set_editable(0, true)
	tree.edit_selected(true)


func _edit_folder_name(id: String) -> void:
	var it := tree.get_root()
	while it:
		var meta = it.get_metadata(0)
		if meta is Dictionary and meta.get("folder", "") == id:
			_rename_folder_later.call_deferred(id)
			return
		it = it.get_next_in_tree()


func _rename_folder_later(id: String) -> void:
	var it := tree.get_root()
	while it:                                            # (the list may have been rebuilt since: find the row again)
		var meta = it.get_metadata(0)
		if meta is Dictionary and meta.get("folder", "") == id:
			rename_row(it)
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
			editor._co_send_folders()
	elif meta.has("object"):
		var o: Node3D = meta["object"]
		if text == "":
			o.remove_meta("name") if o.has_meta("name") else null
		else:
			o.set_meta("name", text)
		editor._co_touch(o)                             # (a name is part of the object: the others rename theirs too)
		editor._refresh_props()
	refresh.call_deferred(true)


func _button_clicked(item: TreeItem, col: int, _id: int, _mb: int) -> void:
	var meta = item.get_metadata(0)
	editor._checkpoint()
	if col == 2:                                         # the padlock
		if meta.has("object"):
			var o: Node3D = meta["object"]
			if not bool(o.get_meta("locked", false)) and folder_locked(String(o.get_meta("folder", ""))):
				editor._set_status("It's locked by its folder: unlock the folder (its padlock) to change it.")
				return
			set_locked([o], not bool(o.get_meta("locked", false)))
		elif meta.has("folder"):
			var fid: String = meta["folder"]
			if not bool(folder(fid).get("locked", false)) and folder_locked(String(folder(fid).get("parent", ""))):
				editor._set_status("A folder it is in is locked: unlock that one.")
				return
			set_folder_locked(fid, not bool(folder(fid).get("locked", false)))
		return
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
	# Godot resets the drop mode after every drop: set it again so the tree can tell "onto a folder" from "between
	# two rows" - and draws the box / line that shows which it'll be
	tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM | Tree.DROP_MODE_INBETWEEN
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
	var folders_moved := false
	for m in data["outliner"]:
		if m.has("object"):
			if dest == "":
				if m["object"].has_meta("folder"):
					m["object"].remove_meta("folder")
			else:
				m["object"].set_meta("folder", dest)
			editor._co_touch(m["object"])
		elif m.has("folder") and m["folder"] != dest and not _is_inside(dest, m["folder"]):
			folder(m["folder"])["parent"] = dest
			folders_moved = true
	refresh(true)
	if folders_moved:
		editor._co_send_folders()


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
func _open_menu(at_mouse := Vector2(-1, -1)) -> void:
	_menu.clear()
	_menu.add_item("Rename (double-click)", 1)
	_menu.add_item("New folder with the selection", 2)
	_menu.add_item("Move the selection out of its folder", 3)
	_menu.add_separator()
	_menu.add_item("Hide", 4)
	_menu.add_item("Show", 5)
	_menu.add_item("Show everything", 6)
	_menu.add_separator()
	_menu.add_item("Lock", 10)
	_menu.add_item("Unlock", 11)
	if not editor.selection().is_empty():
		_menu.add_separator()
		_menu.add_item("Duplicate (Ctrl+D)", 8)
		_menu.add_item("Delete (Del)", 9)
	var it := tree.get_selected()
	if it and (it.get_metadata(0) as Dictionary).has("folder"):
		_menu.add_separator()
		_menu.add_item("Delete this folder (keeps what's in it)", 7)
	_menu.reset_size()
	var at := menu_position(get_viewport(), at_mouse if at_mouse.x >= 0.0 else get_viewport().get_mouse_position())
	if get_viewport().gui_embed_subwindows:              # (kept inside the window near its edges)
		var room := Vector2i(get_viewport().get_visible_rect().size) - _menu.size
		at = at.clamp(Vector2i.ZERO, room.max(Vector2i.ZERO))
	_menu.position = at
	_menu.popup()


## Where a popup opens at the mouse: inside the window (where MALLET draws its menus), or on the screen when menus
## are separate windows.
static func menu_position(vp: Viewport, mouse: Vector2) -> Vector2i:
	var at := Vector2i(mouse)
	if not vp.gui_embed_subwindows:
		at += vp.get_window().position
	return at


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
		8: editor._duplicate_clicked()
		9: editor._delete_clicked()
		10, 11:
			editor._checkpoint()
			var it := tree.get_selected()
			var meta = it.get_metadata(0) if it else null
			if meta is Dictionary and meta.has("folder") and objs.is_empty():
				set_folder_locked(meta["folder"], id == 10)
			else:
				set_locked(objs, id == 10)


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
