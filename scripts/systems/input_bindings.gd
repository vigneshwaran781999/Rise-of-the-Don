class_name InputBindings
## The player's controls as rebindable slots (after 1.0): each action has a key (or mouse button),
## an alternative key, and a gamepad button or stick/trigger direction. Reads and writes them in
## the InputMap (whose defaults come from project.godot, written by tools/godot/setup_project.gd),
## turns them into plain data for the settings file, and knows which actions are live at the same
## time (on foot, driving, on the map) so two of them never share an input there.

enum Slot { KEY, ALT_KEY, PAD }

## Where each action is live: two actions clash only if they share one.
const CONTEXTS: Dictionary = {
	&"move_forward": [&"foot", &"map"], &"move_back": [&"foot", &"map"],
	&"move_left": [&"foot", &"map"], &"move_right": [&"foot", &"map"],
	&"sprint": [&"foot"], &"walk": [&"foot"], &"jump": [&"foot"], &"attack": [&"foot"],
	&"look_left": [&"foot", &"drive"], &"look_right": [&"foot", &"drive"],
	&"look_up": [&"foot", &"drive"], &"look_down": [&"foot", &"drive"],
	&"interact": [&"foot", &"drive"], &"vehicle_enter_exit": [&"foot", &"drive"],
	&"vehicle_accelerate": [&"drive"], &"vehicle_brake": [&"drive"],
	&"vehicle_steer_left": [&"drive"], &"vehicle_steer_right": [&"drive"],
	&"vehicle_handbrake": [&"drive"], &"vehicle_horn": [&"drive"],
	&"vehicle_headlights": [&"drive"], &"vehicle_camera": [&"drive"],
	&"pause": [&"foot", &"drive", &"map"], &"map": [&"foot", &"drive", &"map"],
	&"map_zoom_in": [&"map"], &"map_zoom_out": [&"map"],
	&"toggle_fps": [&"foot", &"drive"], &"toggle_lane_debug": [&"foot", &"drive"],
}
## Never bound to anything: it cancels picking a new input (and always pauses).
const RESERVED_KEY: Key = KEY_ESCAPE
## How far a stick or trigger must move to count when picking a gamepad input.
const AXIS_PICK: float = 0.6


static func get_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	for action: StringName in CONTEXTS:
		actions.append(action)
	return actions


## The input in `slot` of `action` (null if the slot is empty).
static func get_event(action: StringName, slot: Slot) -> InputEvent:
	var keys: Array[InputEvent] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if is_keyboard(event):
			keys.append(event)
		elif slot == Slot.PAD and is_gamepad(event):
			return event
	if slot == Slot.KEY and keys.size() > 0:
		return keys[0]
	if slot == Slot.ALT_KEY and keys.size() > 1:
		return keys[1]
	return null


## All three slots of `action`: [key, alt key, pad] (nulls for empty slots).
static func get_slots(action: StringName) -> Array:
	return [get_event(action, Slot.KEY), get_event(action, Slot.ALT_KEY), get_event(action, Slot.PAD)]


## Replaces the action's inputs with these three slots (nulls skipped). An empty key slot with a
## filled alternative moves the alternative up.
static func set_slots(action: StringName, slots: Array) -> void:
	InputMap.action_erase_events(action)
	for event: Variant in slots:
		if event != null:
			InputMap.action_add_event(action, event as InputEvent)


static func is_keyboard(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


static func is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## Whether the two inputs are the same key, button or stick direction.
static func same_input(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		return _key_code(a as InputEventKey) == _key_code(b as InputEventKey)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false


## Whether actions `a` and `b` are live at the same time somewhere.
static func clash(a: StringName, b: StringName) -> bool:
	for context: StringName in CONTEXTS.get(a, []):
		if (CONTEXTS.get(b, []) as Array).has(context):
			return true
	return false


## A clean copy of a pressed input to bind (any device), or null if it can't be bound: keys
## (not Esc), mouse buttons (not the wheel), gamepad buttons, sticks and triggers pushed past
## AXIS_PICK.
static func from_pressed(event: InputEvent) -> InputEvent:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var code: Key = _key_code(event as InputEventKey)
		if code == KEY_NONE or code == RESERVED_KEY:
			return null
		var key := InputEventKey.new()
		key.device = -1
		key.physical_keycode = code
		return key
	if event is InputEventMouseButton and event.is_pressed():
		var index: MouseButton = (event as InputEventMouseButton).button_index
		if index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return null
		var mouse := InputEventMouseButton.new()
		mouse.device = -1
		mouse.button_index = index
		return mouse
	if event is InputEventJoypadButton and event.is_pressed():
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = (event as InputEventJoypadButton).button_index
		return button
	if event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) >= AXIS_PICK:
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = (event as InputEventJoypadMotion).axis
		motion.axis_value = signf((event as InputEventJoypadMotion).axis_value)
		return motion
	return null


## Plain data for the settings file ({} for an empty slot).
static func to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"key": int(_key_code(event as InputEventKey))}
	if event is InputEventMouseButton:
		return {"mouse": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		return {"axis": int((event as InputEventJoypadMotion).axis), "value": signf((event as InputEventJoypadMotion).axis_value)}
	return {}


## The input from to_data()'s data (null for an empty or unreadable slot).
static func from_data(data: Dictionary) -> InputEvent:
	if data.has("key"):
		var key := InputEventKey.new()
		key.device = -1
		key.physical_keycode = int(data["key"]) as Key
		return key
	if data.has("mouse"):
		var mouse := InputEventMouseButton.new()
		mouse.device = -1
		mouse.button_index = int(data["mouse"]) as MouseButton
		return mouse
	if data.has("button"):
		var button := InputEventJoypadButton.new()
		button.device = -1
		button.button_index = int(data["button"]) as JoyButton
		return button
	if data.has("axis"):
		var motion := InputEventJoypadMotion.new()
		motion.device = -1
		motion.axis = int(data["axis"]) as JoyAxis
		motion.axis_value = 1.0 if float(data.get("value", 1.0)) >= 0.0 else -1.0
		return motion
	return null


## How an input reads on screen: "Space", "Left Mouse Button", "A", "Left stick up", "RT".
static func describe(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventKey:
		var key := event as InputEventKey
		var text: String = key.as_text_physical_keycode() if key.physical_keycode != KEY_NONE else key.as_text_keycode()
		return ControlsPanel.KEY_SYMBOLS.get(text, text)
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).as_text()
	if event is InputEventJoypadButton:
		var index: int = (event as InputEventJoypadButton).button_index
		return ControlsPanel.JOY_BUTTON_NAMES.get(index, "Button %d" % index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		match motion.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		var stick: String = "Left stick" if motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y] else "Right stick"
		var horizontal: bool = motion.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_RIGHT_X]
		var way: String = ("right" if motion.axis_value > 0.0 else "left") if horizontal else ("down" if motion.axis_value > 0.0 else "up")
		return "%s %s" % [stick, way]
	return "?"


static func _key_code(key: InputEventKey) -> Key:
	return key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
