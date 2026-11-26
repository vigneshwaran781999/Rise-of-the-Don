class_name ControlsPanel
extends MenuPanel
## The controls, and changing them (after 1.0). Every action has a key, an alternative key and a
## gamepad input; select one and press the new key, mouse button or gamepad button (or push a
## stick or trigger). Backspace clears it, Esc cancels, and doing nothing for a few seconds
## cancels too (for gamepads). If another action that is live at the same time had that input,
## the two swap (Settings.bind). Esc always pauses. Reset puts every control back to its default.
## Opened from the main menu and the pause menu. Prompts and hints elsewhere read the input map,
## so they show the new keys.

## [label, action] rows; a one-element row is a section heading.
const ROWS: Array = [
	["ON FOOT"],
	["Move forward", &"move_forward"], ["Move back", &"move_back"], ["Move left", &"move_left"], ["Move right", &"move_right"],
	["Look left", &"look_left"], ["Look right", &"look_right"], ["Look up", &"look_up"], ["Look down", &"look_down"],
	["Walk (hold)", &"walk"], ["Sprint (hold)", &"sprint"], ["Jump", &"jump"], ["Punch", &"attack"],
	["Get in / out of a vehicle", &"vehicle_enter_exit"], ["Talk, hand over, skip a line", &"interact"],
	["DRIVING"],
	["Accelerate", &"vehicle_accelerate"], ["Brake / reverse", &"vehicle_brake"], ["Steer left", &"vehicle_steer_left"],
	["Steer right", &"vehicle_steer_right"], ["Handbrake", &"vehicle_handbrake"], ["Horn (hold)", &"vehicle_horn"],
	["Headlights", &"vehicle_headlights"], ["Chase / hood camera", &"vehicle_camera"],
	["GENERAL"],
	["Pause", &"pause"], ["Map", &"map"], ["Zoom the map in", &"map_zoom_in"], ["Zoom the map out", &"map_zoom_out"],
	["FPS counter", &"toggle_fps"], ["Lane and navmesh debug view", &"toggle_lane_debug"],
]
const SLOT_NAMES: PackedStringArray = ["key", "alternative key", "gamepad input"]
## Seconds to press something before picking is given up.
const CAPTURE_SECONDS: float = 6.0
## Frames ignored after picking starts (the press that selected the slot is still settling).
const ARM_FRAMES: int = 8
const JOY_BUTTON_NAMES: Dictionary = {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start",
	7: "Left stick click", 8: "Right stick click", 9: "LB", 10: "RB",
	11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right",
}
## Short labels for keys whose names read badly in a prompt ("Equal" is the =/+ key).
const KEY_SYMBOLS: Dictionary = {"Equal": "+", "Minus": "-", "Kp Add": "+", "Kp Subtract": "-"}
const JOY_AXIS_NAMES: Dictionary = {0: "Left stick", 1: "Left stick", 2: "Right stick", 3: "Right stick", 4: "LT", 5: "RT"}

var _back: Button
var _reset: Button
var _status: Label
var _cells: Dictionary = {}          # action -> [Button, Button, Button]
var _labels: Dictionary = {}         # action -> its row label
var _capture_action: StringName = &""
var _capture_slot: int = -1
var _capture_left: float = 0.0
var _arm: int = 0
var _confirm_reset: bool = false


func _ready() -> void:
	name = "ControlsPanel"
	custom_minimum_size = Vector2(1000.0, 0.0)
	_build()
	hide()


## The button for `slot` (InputBindings.Slot) of `action`.
func get_cell(action: StringName, slot: int) -> Button:
	return (_cells[action] as Array)[slot] if _cells.has(action) else null


func get_status_text() -> String:
	return _status.text


func is_capturing() -> bool:
	return _capture_slot >= 0


## Starts picking a new input for `slot` of `action` (what selecting its button does).
func start_capture(action: StringName, slot: int) -> void:
	_capture_action = action
	_capture_slot = slot
	_capture_left = CAPTURE_SECONDS
	_arm = ARM_FRAMES
	_confirm_reset = false
	var what: String = "gamepad button, stick or trigger" if slot == InputBindings.Slot.PAD else "key or mouse button"
	_status.text = "Press a %s for %s. Backspace clears it, Esc cancels." % [what, _labels[action]]
	get_cell(action, slot).text = "..."


func _on_opening() -> void:
	_end_capture()
	_confirm_reset = false
	_status.text = "Select a control to change it."
	_refresh()


func _on_closing() -> void:
	_end_capture()


func _focus_target() -> Control:
	return get_cell(&"move_forward", InputBindings.Slot.KEY)


func _process(delta: float) -> void:
	if not is_capturing():
		return
	_arm = maxi(0, _arm - 1)
	_capture_left -= delta
	if _capture_left <= 0.0:
		_end_capture()
		_status.text = "Nothing pressed: left as it was."
		_refresh()


func _input(event: InputEvent) -> void:
	if not is_capturing() or not visible or event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key != null and key.pressed and (key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE):
		_end_capture()
		_status.text = "Left as it was."
		_refresh()
		return
	if _arm > 0:
		return
	if key != null and key.pressed and (key.physical_keycode in [KEY_BACKSPACE, KEY_DELETE] or key.keycode in [KEY_BACKSPACE, KEY_DELETE]):
		_apply_pick(null)
		return
	var picked: InputEvent = InputBindings.from_pressed(event)
	if picked == null or InputBindings.is_keyboard(picked) != (_capture_slot != InputBindings.Slot.PAD):
		return
	_apply_pick(picked)


func _apply_pick(event: InputEvent) -> void:
	var action: StringName = _capture_action
	var slot: int = _capture_slot
	_end_capture()
	var old: InputEvent = InputBindings.get_event(action, slot)
	var swapped: StringName = Settings.bind(action, slot, event)
	if event == null:
		_status.text = "%s: %s cleared." % [_labels[action], SLOT_NAMES[slot]]
	else:
		_status.text = "%s: %s." % [_labels[action], InputBindings.describe(event)]
		if swapped != &"":
			_status.text += " %s had it, so it gets %s instead." % [_labels.get(swapped, String(swapped)),
				InputBindings.describe(old) if old != null else "nothing"]
	AudioManager.play_ui(&"ui_accept")
	_refresh()
	get_cell(action, slot).grab_focus()


func _end_capture() -> void:
	_capture_action = &""
	_capture_slot = -1


func _on_reset_pressed() -> void:
	_end_capture()
	if not _confirm_reset:
		_confirm_reset = true
		_status.text = "Select Reset again to put every control back to its default."
		return
	_confirm_reset = false
	Settings.reset_controls()
	_status.text = "Every control is back to its default."
	AudioManager.play_ui(&"ui_accept")
	_refresh()


func _refresh() -> void:
	for action: StringName in _cells:
		var slots: Array = InputBindings.get_slots(action)
		for slot: int in 3:
			var cell: Button = (_cells[action] as Array)[slot]
			cell.text = InputBindings.describe(slots[slot] as InputEvent)
	var pause_key: Button = get_cell(&"pause", InputBindings.Slot.KEY)
	pause_key.text = "Esc"
	pause_key.disabled = true
	pause_key.tooltip_text = "Esc always pauses (and cancels picking a key)."


static func describe_keyboard(actions: Array) -> String:
	var names := PackedStringArray()
	for action: String in actions:
		for event: InputEvent in InputMap.action_get_events(action):
			var text: String = ""
			if event is InputEventKey:
				var key := event as InputEventKey
				text = key.as_text_physical_keycode() if key.physical_keycode != KEY_NONE else key.as_text_keycode()
			elif event is InputEventMouseButton:
				text = (event as InputEventMouseButton).as_text()
			if text != "" and not names.has(text):
				names.append(text)
	return " ".join(names)


## The key to show in prompts and hints for `action`: its first keyboard key, plus the gamepad
## button when a gamepad is connected ("E", or "E / X").
static func key_text(action: String) -> String:
	var keys: String = describe_keyboard([action]).get_slice(" ", 0)
	keys = KEY_SYMBOLS.get(keys, keys)
	if Input.get_connected_joypads().is_empty():
		return keys
	var pad: String = describe_gamepad([action]).get_slice(",", 0)
	return "%s / %s" % [keys, pad] if pad != "" else keys


## `text` with every {action_name} replaced by that action's key, e.g. "Press {interact} to talk".
static func fill_keys(text: String) -> String:
	var result: String = text
	for action: StringName in InputMap.get_actions():
		var tag: String = "{%s}" % action
		if result.contains(tag):
			result = result.replace(tag, key_text(action))
	return result


static func describe_gamepad(actions: Array) -> String:
	var names := PackedStringArray()
	for action: String in actions:
		for event: InputEvent in InputMap.action_get_events(action):
			var text: String = ""
			if event is InputEventJoypadButton:
				var index: int = (event as InputEventJoypadButton).button_index
				text = JOY_BUTTON_NAMES.get(index, "Button %d" % index)
			elif event is InputEventJoypadMotion:
				text = JOY_AXIS_NAMES.get((event as InputEventJoypadMotion).axis, "Stick")
			if text != "" and not names.has(text):
				names.append(text)
	return ", ".join(names)


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(UIStyle.make_heading("CONTROLS"))
	var note := Label.new()
	note.text = "Select a control, then press the new key, mouse button or gamepad input. The mouse always looks around, and its wheel zooms the map."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 19)
	note.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(note)
	_status = Label.new()
	_status.name = "ControlsStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", UIStyle.CYAN)
	box.add_child(_status)
	box.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "Rows"
	scroll.custom_minimum_size = Vector2(0.0, 500.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "BindingsGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for header: String in ["ACTION", "KEY", "ALTERNATIVE", "GAMEPAD"]:
		grid.add_child(_small(header, UIStyle.TEXT_DIM))
	for row: Array in ROWS:
		if row.size() == 1:
			grid.add_child(_small(str(row[0]), UIStyle.MAGENTA.lightened(0.3), 12.0))
			for i: int in 3:
				grid.add_child(Control.new())
			continue
		var action: StringName = row[1]
		_labels[action] = str(row[0])
		var label := Label.new()
		label.text = str(row[0])
		label.custom_minimum_size = Vector2(320.0, 0.0)
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", UIStyle.TEXT)
		grid.add_child(label)
		var cells: Array = []
		for slot: int in 3:
			var cell: Button = UIStyle.make_button("", "Bind_%s_%d" % [action, slot])
			cell.custom_minimum_size = Vector2(190.0, 40.0)
			cell.add_theme_font_size_override("font_size", 18)
			cell.clip_text = true
			cell.pressed.connect(start_capture.bind(action, slot))
			grid.add_child(cell)
			cells.append(cell)
		_cells[action] = cells

	box.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_back = _make_back_button()
	buttons.add_child(_back)
	_reset = UIStyle.make_button("Reset to Defaults", "ResetControlsButton")
	_reset.custom_minimum_size = Vector2(300.0, 56.0)
	_reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(_reset)


## Small caps-style label for column headers and section headings.
func _small(text: String, color: Color, top_gap: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.custom_minimum_size = Vector2(0.0, 20.0 + top_gap)
	return label
