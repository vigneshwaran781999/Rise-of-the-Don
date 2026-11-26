extends Node
## Controls test (after 1.0): rebinding in the pause menu's Controls screen, with real input
## events through the viewport.
## - Pause → Controls lists every action with its key, alternative and gamepad input; Esc is fixed.
## - Jump to J, then to E: Talk had E, so it gets J (they swap). Horn to Ctrl: Walk keeps Ctrl too
##   (walking and driving never happen at once). Prompts show the new keys.
## - Esc cancels, Backspace clears, a gamepad press is ignored for a key slot, and doing nothing
##   for a few seconds gives up.
## - Punch to the right mouse button; Jump's gamepad input to X (Talk gets A); Horn's to RT
##   (Accelerate gets the left stick click).
## - Saved to the settings file and loaded back after a restart of the controls; Reset to Defaults
##   puts everything back; tests (Settings.persist off) always get the defaults.
## The settings go to a scratch file (user://test_settings.cfg), never the player's real one.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/controls_test.tscn
## Prints "CONTROLS TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const PAUSE_MENU: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const TEST_SETTINGS: String = "user://test_settings.cfg"
const KEY := InputBindings.Slot.KEY
const ALT := InputBindings.Slot.ALT_KEY
const PAD := InputBindings.Slot.PAD

var _catcher: ErrorCatcher
var _pause: PauseMenu
var _panel: ControlsPanel
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.save_path = TEST_SETTINGS
	Settings.persist = false
	_pause = PAUSE_MENU.instantiate() as PauseMenu
	add_child(_pause)
	_run.call_deferred()


func _run() -> void:
	var steps: Array[Callable] = [_check_screen, _check_keys, _check_cancel_clear, _check_mouse_and_pad, _check_timeout,
		_check_saved, _check_reset]
	var failure: String = ""
	for step: Callable in steps:
		failure = await step.call()
		if failure != "":
			failure = "%s: %s" % [step.get_method(), failure]
			break
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "%s: engine/script error: %s" % [step.get_method(), errors[0]]
			break
	print("CONTROLS REPORT")
	for line: String in _report:
		print("  " + line)
	Settings.persist = false
	Settings.save_path = Settings.SAVE_PATH
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	OS.remove_logger(_catcher)
	get_tree().paused = false
	if failure == "":
		print("CONTROLS TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_screen() -> String:
	_pause.open()
	await _frames(2)
	(_pause.find_child("ControlsButton", true, false) as Button).pressed.emit()
	await _frames(2)
	_panel = _pause.find_child("ControlsPanel", true, false) as ControlsPanel
	if _panel == null or not _panel.visible:
		return "Pause → Controls didn't open the controls screen"
	var expect: Dictionary = {&"jump": ["Space", "—", "A"], &"vehicle_accelerate": ["W", "Up", "RT"],
		&"move_forward": ["W", "—", "Left stick up"], &"attack": ["Left Mouse Button", "—", "B"]}
	for action: StringName in expect:
		for slot: int in 3:
			var shown: String = _panel.get_cell(action, slot).text
			if shown != expect[action][slot]:
				return "%s slot %d shows '%s' (expected '%s')" % [action, slot, shown, expect[action][slot]]
	var pause_key: Button = _panel.get_cell(&"pause", KEY)
	if not pause_key.disabled or pause_key.text != "Esc":
		return "Pause's key should be a fixed Esc"
	_note("Pause → Controls: every action with key / alternative / gamepad (Jump: Space, —, A; Accelerate: W, Up, RT); Esc fixed")
	return ""


func _check_keys() -> String:
	await _pick(&"jump", KEY, _key_event(KEY_J))
	if not _has(&"jump", KEY, KEY_J) or _panel.get_cell(&"jump", KEY).text != "J" or ControlsPanel.key_text("jump") != "J":
		return "Jump should be on J (cell '%s', prompt '%s')" % [_panel.get_cell(&"jump", KEY).text, ControlsPanel.key_text("jump")]
	await _pick(&"jump", KEY, _key_event(KEY_E))
	if not _has(&"jump", KEY, KEY_E) or not _has(&"interact", KEY, KEY_J):
		return "Jump to E should swap with Talk (jump %s, talk %s)" % [_shown(&"jump", KEY), _shown(&"interact", KEY)]
	if not _panel.get_status_text().contains("had it, so it gets J instead") or ControlsPanel.key_text("interact") != "J":
		return "the swap should be explained and prompts follow ('%s')" % _panel.get_status_text()
	await _pick(&"vehicle_horn", KEY, _key_event(KEY_CTRL))
	if not _has(&"vehicle_horn", KEY, KEY_CTRL) or not _has(&"walk", KEY, KEY_CTRL):
		return "Horn on Ctrl shouldn't take it from Walk (horn %s, walk %s)" % [_shown(&"vehicle_horn", KEY), _shown(&"walk", KEY)]
	_note("Jump to J, then E: Talk had E and gets J (prompts follow); Horn to Ctrl: Walk keeps Ctrl (never live together)")
	return ""


func _check_cancel_clear() -> String:
	_panel.get_cell(&"jump", KEY).pressed.emit()
	await _frames(12)
	_send(_pad_button(JOY_BUTTON_Y))
	await _frames(2)
	if not _panel.is_capturing():
		return "a gamepad press shouldn't end picking a key"
	_send(_key_event(KEY_ESCAPE))
	await _frames(2)
	if _panel.is_capturing() or not _has(&"jump", KEY, KEY_E):
		return "Esc should cancel and leave Jump on E (now %s)" % _shown(&"jump", KEY)
	await _pick(&"vehicle_accelerate", ALT, _key_event(KEY_BACKSPACE))
	if InputBindings.get_event(&"vehicle_accelerate", ALT) != null or not _has(&"vehicle_accelerate", KEY, KEY_W):
		return "Backspace should clear Accelerate's alternative (Up) and keep W"
	_note("picking a key ignores gamepad presses; Esc cancels; Backspace clears Accelerate's Up arrow (W stays)")
	return ""


func _check_mouse_and_pad() -> String:
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	await _pick(&"attack", KEY, right)
	var punch: InputEvent = InputBindings.get_event(&"attack", KEY)
	if not (punch is InputEventMouseButton) or (punch as InputEventMouseButton).button_index != MOUSE_BUTTON_RIGHT:
		return "Punch should be on the right mouse button (%s)" % _shown(&"attack", KEY)
	await _pick(&"jump", PAD, _pad_button(JOY_BUTTON_X))
	var jump_pad := InputBindings.get_event(&"jump", PAD) as InputEventJoypadButton
	var talk_pad := InputBindings.get_event(&"interact", PAD) as InputEventJoypadButton
	if jump_pad == null or jump_pad.button_index != JOY_BUTTON_X or talk_pad == null or talk_pad.button_index != JOY_BUTTON_A:
		return "Jump's gamepad input to X should swap with Talk (jump %s, talk %s)" % [_shown(&"jump", PAD), _shown(&"interact", PAD)]
	var trigger := InputEventJoypadMotion.new()
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 0.9
	await _pick(&"vehicle_horn", PAD, trigger)
	if _shown(&"vehicle_horn", PAD) != "RT" or _shown(&"vehicle_accelerate", PAD) != "Left stick click":
		return "Horn to RT should swap with Accelerate (horn %s, accelerate %s)" % [_shown(&"vehicle_horn", PAD), _shown(&"vehicle_accelerate", PAD)]
	_note("Punch to the right mouse button; Jump's pad input to X (Talk gets A); Horn's to RT (Accelerate gets the left stick click)")
	return ""


func _check_timeout() -> String:
	_panel.get_cell(&"map", KEY).pressed.emit()
	await _frames(int(ControlsPanel.CAPTURE_SECONDS * 60.0) + 20)
	if _panel.is_capturing() or not _has(&"map", KEY, KEY_M):
		return "doing nothing should give up picking and leave Map on M"
	_note("doing nothing for %d s gives up (gamepad players have no Esc)" % int(ControlsPanel.CAPTURE_SECONDS))
	return ""


func _check_saved() -> String:
	Settings.persist = true                     # writes to the scratch file only
	Settings.bind(&"sprint", KEY, _key_event(KEY_Q))
	var cfg := ConfigFile.new()
	if cfg.load(TEST_SETTINGS) != OK or not cfg.has_section_key("bindings", "sprint"):
		return "the change wasn't saved to the settings file"
	InputMap.load_from_project_settings()       # as on a fresh start
	Settings.load_settings()
	if not _has(&"sprint", KEY, KEY_Q) or not _has(&"jump", KEY, KEY_E) or not _has(&"interact", KEY, KEY_J):
		return "loading the settings didn't bring the controls back (sprint %s, jump %s)" % [_shown(&"sprint", KEY), _shown(&"jump", KEY)]
	_note("saved under [bindings] and loaded back on a fresh start (Sprint Q, Jump E, Talk J)")
	return ""


func _check_reset() -> String:
	var reset := _panel.find_child("ResetControlsButton", true, false) as Button
	reset.pressed.emit()
	await _frames(2)
	if not _has(&"jump", KEY, KEY_E):
		return "Reset should ask again before resetting"
	reset.pressed.emit()
	await _frames(2)
	for check: Array in [[&"jump", KEY_SPACE], [&"interact", KEY_E], [&"vehicle_horn", KEY_H], [&"sprint", KEY_SHIFT]]:
		if not _has(check[0], KEY, check[1]):
			return "after Reset, %s is %s" % [check[0], _shown(check[0], KEY)]
	if _shown(&"vehicle_accelerate", ALT) != "Up" or _shown(&"attack", KEY) != "Left Mouse Button" or _shown(&"jump", PAD) != "A":
		return "Reset should bring back the alternatives, the mouse and the gamepad inputs"
	Settings.bind(&"jump", KEY, _key_event(KEY_K))
	Settings.persist = false
	if not _has(&"jump", KEY, KEY_SPACE):
		return "with Settings.persist off (tests) the controls should be the defaults"
	_pause.resume()
	_note("Reset to Defaults (asked twice) puts every key, alternative and gamepad input back; tests get the defaults")
	return ""


# --------------------------------------------------------------------------- helpers

## Selects the slot's button, waits out the settling frames, then sends `event`.
func _pick(action: StringName, slot: int, event: InputEvent) -> void:
	_panel.get_cell(action, slot).pressed.emit()
	await _frames(ControlsPanel.ARM_FRAMES + 2)
	_send(event)
	await _frames(2)


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		var release: InputEvent = event.duplicate()
		release.set(&"pressed", false)
		Input.parse_input_event(release)


func _has(action: StringName, slot: int, code: Key) -> bool:
	var event := InputBindings.get_event(action, slot) as InputEventKey
	return event != null and event.physical_keycode == code


func _shown(action: StringName, slot: int) -> String:
	return InputBindings.describe(InputBindings.get_event(action, slot))


func _key_event(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
