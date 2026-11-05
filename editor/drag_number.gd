class_name DragNumber
extends LineEdit
## A number you drag: press and drag left / right to change it (the mouse is held in place, so it never runs out of
## room - drag as far as you like; Shift = fine, Ctrl = fast). A click without dragging lets you type a value.

signal drag_started
signal changed_by(amount: float)                   ## while dragging
signal typed(value: float)                         ## a value was typed and confirmed

var per_pixel := 0.05                              ## change per pixel of mouse movement
var _pressed := false
var _dragging := false
var _travel := 0.0
var _press_at := Vector2.ZERO
var _value := 0.0


func _ready() -> void:
	editable = false
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_mode = Control.FOCUS_CLICK
	tooltip_text = "Drag left / right to move (Shift: fine, Ctrl: fast). Click to type a value."
	text_submitted.connect(func(_t): _commit())
	focus_exited.connect(_commit)


## Show a value (ignored while the user is dragging or typing in it).
func show_value(v: float) -> void:
	_value = v
	if not _dragging and not editable:
		text = "%.2f" % v


func _gui_input(event: InputEvent) -> void:
	if editable:
		return                                     # typing: behave like a normal text box
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed = true
		_dragging = false
		_travel = 0.0
		_press_at = get_global_mouse_position()
		accept_event()


func _input(event: InputEvent) -> void:
	if not _pressed:
		return
	if event is InputEventMouseMotion:
		var dx: float = event.relative.x
		_travel += absf(dx)
		if not _dragging and _travel > 3.0:
			_dragging = true
			drag_started.emit()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _dragging:
			var k := per_pixel * (0.1 if event.shift_pressed else 1.0) * (10.0 if event.ctrl_pressed else 1.0)
			_value += dx * k
			text = "%.2f" % _value
			changed_by.emit(dx * k)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_pressed = false
		if _dragging:
			_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Input.warp_mouse(_press_at)
		else:
			editable = true                        # a plain click: type a value
			grab_focus()
			select_all()
		get_viewport().set_input_as_handled()


func _commit() -> void:
	if not editable:
		return
	editable = false
	var t := text.strip_edges()
	release_focus()
	if t.is_valid_float():
		typed.emit(float(t))
	text = "%.2f" % _value
