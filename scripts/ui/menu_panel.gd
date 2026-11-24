class_name MenuPanel
extends PanelContainer
## Base for sub-screens opened from a menu (settings, controls, credits).
## open() shows the panel and focuses its first control; close() hides it and emits `closed`.

signal closed


func open() -> void:
	_on_opening()
	show()
	var target: Control = _focus_target()
	if target != null:
		target.grab_focus()


func close() -> void:
	if not visible:
		return
	_on_closing()
	hide()
	AudioManager.play_ui(&"ui_back")
	closed.emit()


## Called just before the panel is shown (refresh displayed values here).
func _on_opening() -> void:
	pass


## Called just before the panel is hidden (persist changes here).
func _on_closing() -> void:
	pass


## The control that receives keyboard / gamepad focus when the panel opens.
func _focus_target() -> Control:
	return null


func _make_back_button() -> Button:
	var back: Button = UIStyle.make_button("Back", "BackButton")
	back.custom_minimum_size = Vector2(260.0, 56.0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(close)
	return back
