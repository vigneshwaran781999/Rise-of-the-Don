extends SceneTree
## Writes the project's input map, autoloads, main scene and a few core settings into
## project.godot, and the audio bus layout into default_bus_layout.tres.
## Edit the tables below and re-run; it rebuilds everything it owns.
##
## Run from the project root (Git Bash):
##   "$GODOT" --headless --path . --script res://tools/godot/setup_project.gd

const MOVE_DEADZONE: float = 0.2
const LOOK_DEADZONE: float = 0.15
const STEER_DEADZONE: float = 0.12
const TRIGGER_DEADZONE: float = 0.08
const MAIN_SCENE: String = "res://scenes/main/main_menu.tscn"
const BUS_LAYOUT_PATH: String = "res://default_bus_layout.tres"
## Autoloads in load order (GDD: only real global state).
const AUTOLOADS: Array = [
	["Settings", "res://scripts/systems/settings.gd"],
	["AudioManager", "res://scripts/systems/audio_manager.gd"],
	["MissionManager", "res://scripts/systems/mission_manager.gd"],
	["EconomyManager", "res://scripts/systems/economy_manager.gd"],
	["GameState", "res://scripts/systems/game_state.gd"],
	["SaveManager", "res://scripts/systems/save_manager.gd"],
	["WantedSystem", "res://scripts/systems/wanted_system.gd"],
]
## Buses under Master (GDD §13).
const BUSES: Array = ["Music", "SFX", "Ambience", "UI"]


func _initialize() -> void:
	_setup_input_map()
	_setup_core_settings()
	var bus_err: Error = _setup_audio_buses()
	var err: Error = ProjectSettings.save()
	if err != OK or bus_err != OK:
		push_error("setup_project: saving failed (project %d, buses %d)" % [err, bus_err])
		quit(1)
		return
	print("setup_project: project.godot and default_bus_layout.tres written")
	quit(0)


func _setup_core_settings() -> void:
	ProjectSettings.set_setting("application/run/main_scene", MAIN_SCENE)
	# The release (M8): its version, and the Windows icon of the window and the exported game
	# (written by tools/godot/make_icon.gd from icon.svg).
	ProjectSettings.set_setting("application/config/version", "1.0.3")
	ProjectSettings.set_setting("application/config/windows_native_icon", "res://icon.ico")
	# Smooth rendering between 60 Hz physics ticks on high-refresh screens.
	ProjectSettings.set_setting("physics/common/physics_interpolation", true)
	# Buildings in the streamed districts carry box occluders (dense streets hide most of the town).
	ProjectSettings.set_setting("rendering/occlusion_culling/use_occlusion_culling", true)
	# Finer vertical navmesh cells, so pedestrian paths sit on the 0.15 m sidewalks (must match
	# the cell height the district builder bakes with).
	ProjectSettings.set_setting("navigation/3d/default_cell_height", 0.1)
	# Shader global set by the day/night cycle: 0 by day, 1 at night (streetlights, lit windows).
	ProjectSettings.set_setting("shader_globals/city_lights", {"type": "float", "value": 0.0})
	# How wet the ground is after rain (M7, the weather; 0 = dry).
	ProjectSettings.set_setting("shader_globals/wetness", {"type": "float", "value": 0.0})
	for entry: Array in AUTOLOADS:
		ProjectSettings.set_setting("autoload/" + str(entry[0]), "*" + str(entry[1]))


func _setup_audio_buses() -> Error:
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	for bus_name: String in BUSES:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, &"Master")
	return ResourceSaver.save(AudioServer.generate_bus_layout(), BUS_LAYOUT_PATH)


func _setup_input_map() -> void:
	# On foot
	_action("move_forward", MOVE_DEADZONE, [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_action("move_back", MOVE_DEADZONE, [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_action("move_left", MOVE_DEADZONE, [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("move_right", MOVE_DEADZONE, [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("sprint", MOVE_DEADZONE, [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)])
	_action("walk", MOVE_DEADZONE, [_key(KEY_CTRL)])  # gamepad walks by tilting the stick gently
	_action("jump", MOVE_DEADZONE, [_key(KEY_SPACE), _button(JOY_BUTTON_A)])

	# Camera (mouse look is read from mouse motion by the camera rig; these are the stick equivalents)
	_action("look_left", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_X, -1.0)])
	_action("look_right", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_X, 1.0)])
	_action("look_up", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_action("look_down", LOOK_DEADZONE, [_axis(JOY_AXIS_RIGHT_Y, 1.0)])

	# Interaction
	_action("vehicle_enter_exit", MOVE_DEADZONE, [_key(KEY_F), _button(JOY_BUTTON_Y)])
	_action("interact", MOVE_DEADZONE, [_key(KEY_E), _button(JOY_BUTTON_X)])
	# Fists (M7): left mouse button, or B on a gamepad.
	_action("attack", MOVE_DEADZONE, [_mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_B)])

	# Driving (only read while the player is in a vehicle; arrow keys work as well as WASD)
	_action("vehicle_accelerate", TRIGGER_DEADZONE, [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("vehicle_brake", TRIGGER_DEADZONE, [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_action("vehicle_steer_left", STEER_DEADZONE, [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_action("vehicle_steer_right", STEER_DEADZONE, [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_action("vehicle_handbrake", MOVE_DEADZONE, [_key(KEY_SPACE), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_action("vehicle_horn", MOVE_DEADZONE, [_key(KEY_H), _button(JOY_BUTTON_LEFT_STICK)])
	_action("vehicle_headlights", MOVE_DEADZONE, [_key(KEY_L), _button(JOY_BUTTON_DPAD_UP)])
	_action("vehicle_camera", MOVE_DEADZONE, [_key(KEY_V), _button(JOY_BUTTON_BACK)])

	# Menus and debug
	_action("pause", MOVE_DEADZONE, [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)])
	_action("toggle_fps", MOVE_DEADZONE, [_key(KEY_F3)])
	_action("toggle_lane_debug", MOVE_DEADZONE, [_key(KEY_F4)])

	# Map (GDD §11): open the full map; zoom it
	_action("map", MOVE_DEADZONE, [_key(KEY_M), _button(JOY_BUTTON_DPAD_DOWN)])
	_action("map_zoom_in", TRIGGER_DEADZONE, [_key(KEY_EQUAL), _key(KEY_KP_ADD), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_action("map_zoom_out", TRIGGER_DEADZONE, [_key(KEY_MINUS), _key(KEY_KP_SUBTRACT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])


func _action(action_name: String, deadzone: float, events: Array[InputEvent]) -> void:
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})


func _key(physical_keycode: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.device = -1
	ev.physical_keycode = physical_keycode
	return ev


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.device = -1
	ev.button_index = button
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
