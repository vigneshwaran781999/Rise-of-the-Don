class_name MissionFailedScreen
extends CanvasLayer
## Shown when a mission fails (GDD §8): after a short beat the game pauses and the reason comes
## up with Retry (from the last checkpoint) and Quit Mission. Keyboard, mouse and gamepad.

const DELAY_SECONDS: float = 1.4

var _root: Control
var _reason: Label
var _retry: Button
var _quit: Button
var _waiting: bool = false


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	MissionManager.mission_failed.connect(_on_mission_failed)


func _exit_tree() -> void:
	if MissionManager.mission_failed.is_connected(_on_mission_failed):
		MissionManager.mission_failed.disconnect(_on_mission_failed)


func is_open() -> bool:
	return _root.visible


## The failure reason on screen ("" when closed).
func get_reason_shown() -> String:
	return _reason.text if _root.visible else ""


## True from the failure until a choice is made (including the short delay before the screen).
func is_pending() -> bool:
	return _waiting or _root.visible


func _unhandled_input(event: InputEvent) -> void:
	# While the choice is up, Esc must not open the pause menu underneath.
	if _root.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()


func retry() -> void:
	_close()
	MissionManager.retry()


func quit_mission() -> void:
	_close()
	MissionManager.quit_mission()


func _on_mission_failed(_mission: MissionData, reason: String) -> void:
	_reason.text = reason
	_waiting = true
	AudioManager.play_ui(&"mission_failed")
	await get_tree().create_timer(DELAY_SECONDS, true, false, true).timeout
	_waiting = false
	if not MissionManager.is_failed():
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	_retry.grab_focus()


func _close() -> void:
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.0, 0.03, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "FailedPanel"
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "MISSION FAILED"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.label_settings = UIStyle.glow_label(56, UIStyle.TEXT, UIStyle.HEALTH, 14)
	box.add_child(heading)
	_reason = Label.new()
	_reason.name = "Reason"
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.add_theme_font_size_override("font_size", 26)
	_reason.add_theme_color_override("font_color", UIStyle.TEXT)
	box.add_child(_reason)
	box.add_child(HSeparator.new())
	_retry = UIStyle.make_button("Retry", "RetryButton")
	_retry.pressed.connect(retry)
	box.add_child(_retry)
	_quit = UIStyle.make_button("Quit Mission", "QuitMissionButton")
	_quit.pressed.connect(quit_mission)
	box.add_child(_quit)
