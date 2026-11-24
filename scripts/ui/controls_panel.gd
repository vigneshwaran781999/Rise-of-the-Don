class_name ControlsPanel
extends MenuPanel
## Lists the controls that work right now. Bindings are read from the input map, so this
## screen always matches project.godot. Rebinding comes with the full settings screen.

## label, actions, optional keyboard text override, optional gamepad text override.
## A one-element row is a section heading.
const ROWS: Array = [
	["ON FOOT"],
	["Move", ["move_forward", "move_left", "move_back", "move_right"], "", ""],
	["Look", ["look_left", "look_right", "look_up", "look_down"], "Mouse", ""],
	["Walk (hold)", ["walk"], "", "Tilt stick gently"],
	["Sprint (hold)", ["sprint"], "", ""],
	["Jump", ["jump"], "", ""],
	["Get in / out of a vehicle", ["vehicle_enter_exit"], "", ""],
	["DRIVING"],
	["Accelerate", ["vehicle_accelerate"], "", ""],
	["Brake / reverse", ["vehicle_brake"], "", ""],
	["Steer left", ["vehicle_steer_left"], "", ""],
	["Steer right", ["vehicle_steer_right"], "", ""],
	["Handbrake", ["vehicle_handbrake"], "", ""],
	["Horn (hold)", ["vehicle_horn"], "", ""],
	["Headlights", ["vehicle_headlights"], "", ""],
	["Chase / hood camera", ["vehicle_camera"], "", ""],
	["GENERAL"],
	["Pause", ["pause"], "", ""],
	["FPS counter", ["toggle_fps"], "", ""],
]
const JOY_BUTTON_NAMES: Dictionary = {
	0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start",
	7: "Left stick click", 8: "Right stick click", 9: "LB", 10: "RB",
	11: "D-pad up", 12: "D-pad down", 13: "D-pad left", 14: "D-pad right",
}
const JOY_AXIS_NAMES: Dictionary = {0: "Left stick", 1: "Left stick", 2: "Right stick", 3: "Right stick", 4: "LT", 5: "RT"}

var _back: Button


func _ready() -> void:
	name = "ControlsPanel"
	custom_minimum_size = Vector2(860.0, 0.0)
	_build()
	hide()


func _focus_target() -> Control:
	return _back


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
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	box.add_child(UIStyle.make_heading("CONTROLS"))
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.name = "BindingsGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 7)
	box.add_child(grid)
	for header: String in ["ACTION", "KEYBOARD / MOUSE", "GAMEPAD"]:
		grid.add_child(_small(header, UIStyle.TEXT_DIM))
	for row: Array in ROWS:
		if row.size() == 1:
			grid.add_child(_small(str(row[0]), UIStyle.MAGENTA.lightened(0.3), 12.0))
			grid.add_child(Control.new())
			grid.add_child(Control.new())
			continue
		var actions: Array = row[1]
		var keys: String = str(row[2]) if str(row[2]) != "" else describe_keyboard(actions)
		var pad: String = str(row[3]) if str(row[3]) != "" else describe_gamepad(actions)
		grid.add_child(_cell(str(row[0]), UIStyle.TEXT))
		grid.add_child(_cell(keys, UIStyle.CYAN))
		grid.add_child(_cell(pad if pad != "" else "—", UIStyle.MAGENTA.lightened(0.25)))

	box.add_child(HSeparator.new())
	_back = _make_back_button()
	box.add_child(_back)


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", color)
	return label


## Small caps-style label for column headers and section headings.
func _small(text: String, color: Color, top_gap: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.custom_minimum_size = Vector2(0.0, 20.0 + top_gap)
	return label
