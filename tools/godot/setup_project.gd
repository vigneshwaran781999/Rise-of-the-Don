extends SceneTree
## Writes the project's input map into project.godot.
## Edit the action table below and re-run; it rebuilds every action it owns.
##
## Run from the project root (Git Bash):
##   "$GODOT" --headless --path . --script res://tools/godot/setup_project.gd

const MOVE_DEADZONE: float = 0.2
const LOOK_DEADZONE: float = 0.15


func _initialize() -> void:
	_setup_input_map()
	var err: Error = ProjectSettings.save()
	if err != OK:
		push_error("setup_project: ProjectSettings.save() failed with code %d" % err)
		quit(1)
		return
	print("setup_project: input map written to project.godot")
	quit(0)


func _setup_input_map() -> void:
	# On foot
	_action("move_forward", MOVE_DEADZONE, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_back", MOVE_DEADZONE, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("move_left", MOVE_DEADZONE, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", MOVE_DEADZONE, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("sprint", MOVE_DEADZONE, [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)])
	_action("jump", MOVE_DEADZONE, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])

	# Camera (mouse look is read from mouse motion by the camera rig; these are the stick equivalents)
	_action("look_left", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("look_right", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("look_up", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("look_down", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_Y, 1.0)])

	# Interaction
	_action("vehicle_enter_exit", MOVE_DEADZONE, [_key(KEY_F), _button(JOY_BUTTON_Y)])
	_action("interact", MOVE_DEADZONE, [_key(KEY_E), _button(JOY_BUTTON_X)])

	# Menus
	_action("pause", MOVE_DEADZONE, [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)])


func _action(action_name: String, deadzone: float, events: Array[InputEvent]) -> void:
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})


func _key(physical_keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = physical_keycode
	return ev


func _button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = -1
	ev.button_index = button
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = -1
	ev.axis = axis
	ev.axis_value = value
	return ev
