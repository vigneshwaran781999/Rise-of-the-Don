class_name ShopMenu
extends CanvasLayer
## The counter of a shop, garage or property for sale (GDD §9): a title and the keeper's line,
## the player's cash, a list of choices (name on the left, price or state on the right, a line
## about the focused one underneath), a message line, and Leave. The game pauses while it's open.
## What a choice does is up to whoever opened it (PlaceDirector): it gets `chosen` and answers
## with set_rows() / set_message() / close(). Keyboard, mouse and gamepad.

signal chosen(choice_id: StringName)
signal closed

const LAYER: int = 20

var _root: Control
var _title: Label
var _greeting: Label
var _cash: Label
var _list: VBoxContainer
var _detail: Label
var _message: Label
var _leave: Button
var _rows: Array[Dictionary] = []
var _buttons: Dictionary = {}       # StringName -> Button
var _fade: ColorRect


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	EconomyManager.cash_changed.connect(func(cash: int, _delta: int, _reason: StringName) -> void:
		_cash.text = EconomyManager.format(cash))


func is_open() -> bool:
	return _root.visible


## Opens with `rows`: [{id, text, note (price or state, right-aligned), detail (one line shown
## when focused), dim (greyed: can't afford or nothing to gain; still choosable)}].
func open(title: String, greeting: String, rows: Array[Dictionary]) -> void:
	_title.text = title.to_upper()
	_greeting.text = greeting
	_greeting.visible = greeting != ""
	_cash.text = EconomyManager.format(EconomyManager.cash)
	_message.text = ""
	set_rows(rows)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	AudioManager.play_ui(&"ui_accept")
	var first: Button = _buttons.get(rows[0]["id"]) if not rows.is_empty() else _leave
	first.grab_focus()
	_show_detail(0)


## Replaces the choices (after a purchase), keeping the focus on the same row.
func set_rows(rows: Array[Dictionary]) -> void:
	var focused: StringName = &""
	for choice_id: StringName in _buttons:
		if (_buttons[choice_id] as Button).has_focus():
			focused = choice_id
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_rows = rows
	_buttons.clear()
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		var button := UIStyle.make_button(str(row["text"]), "Choice_" + str(row["id"]))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 54.0)
		var note := Label.new()
		note.name = "Note"
		note.text = str(row.get("note", ""))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.add_theme_font_size_override("font_size", 24)
		var dim: bool = bool(row.get("dim", false))
		note.add_theme_color_override("font_color", UIStyle.TEXT_DIM if dim else UIStyle.CYAN)
		if dim:
			button.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
		button.add_child(note)
		note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		note.offset_right = -22.0
		var choice_id: StringName = row["id"]
		button.pressed.connect(choose.bind(choice_id))
		button.focus_entered.connect(_show_detail.bind(i))
		button.mouse_entered.connect(_show_detail.bind(i))
		_list.add_child(button)
		_buttons[choice_id] = button
	if focused != &"":
		_focus_row.call_deferred(focused)


func set_message(text: String) -> void:
	_message.text = text


func get_message() -> String:
	return _message.text


func get_row_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Dictionary in _rows:
		ids.append(row["id"])
	return ids


## The right-hand note of a row as shown (its price, "OWNED"...), "" if there is no such row.
func get_note(choice_id: StringName) -> String:
	var button: Button = _buttons.get(choice_id)
	return (button.get_node("Note") as Label).text if button != null else ""


## Picks a row, as if pressed.
func choose(choice_id: StringName) -> void:
	AudioManager.play_ui(&"ui_accept")
	chosen.emit(choice_id)


func close() -> void:
	if not _root.visible:
		return
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_ui(&"ui_back")
	closed.emit()


## Fades the screen to black, calls `at_black` (a respray), and fades back; the game stays
## paused throughout.
func blackout(at_black: Callable, seconds: float = 0.6) -> void:
	var was_paused: bool = get_tree().paused
	get_tree().paused = true
	_fade.show()
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, seconds * 0.5)
	await tween.finished
	at_black.call()
	await get_tree().create_timer(0.25, true, false, true).timeout
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, seconds * 0.5)
	await tween.finished
	_fade.hide()
	get_tree().paused = was_paused


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _focus_row(choice_id: StringName) -> void:
	var button: Button = _buttons.get(choice_id)
	if button != null and button.is_inside_tree() and _root.visible:
		button.grab_focus()


func _show_detail(index: int) -> void:
	_detail.text = str(_rows[index].get("detail", "")) if index < _rows.size() else ""


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ShopPanel"
	panel.custom_minimum_size = Vector2(720.0, 0.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.name = "Title"
	_title.label_settings = UIStyle.glow_label(40, UIStyle.TEXT, UIStyle.MAGENTA, 12)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_cash = Label.new()
	_cash.name = "Cash"
	_cash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cash.add_theme_font_size_override("font_size", 28)
	_cash.add_theme_color_override("font_color", Color("7dffb0"))
	header.add_child(_cash)
	_greeting = Label.new()
	_greeting.name = "Greeting"
	_greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_greeting.add_theme_font_size_override("font_size", 22)
	_greeting.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(_greeting)
	box.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.name = "Choices"
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	_detail = Label.new()
	_detail.name = "Detail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0.0, 30.0)
	_detail.add_theme_font_size_override("font_size", 21)
	_detail.add_theme_color_override("font_color", UIStyle.TEXT)
	box.add_child(_detail)
	_message = Label.new()
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_color", UIStyle.CYAN)
	box.add_child(_message)
	box.add_child(HSeparator.new())
	_leave = UIStyle.make_button("Leave", "LeaveButton")
	_leave.pressed.connect(close)
	box.add_child(_leave)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.hide()
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
