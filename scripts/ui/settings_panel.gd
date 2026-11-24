class_name SettingsPanel
extends MenuPanel
## Master / music / effects volume, mouse sensitivity and invert-Y (M1 subset of GDD §10).
## Changes apply instantly; they are written to user://settings.cfg when the panel closes.

const PREVIEW_INTERVAL_MS: int = 120

var _volume_sliders: Dictionary = {}  # StringName -> HSlider
var _volume_labels: Dictionary = {}   # StringName -> Label
var _sensitivity: HSlider
var _sensitivity_label: Label
var _invert: Button
var _last_preview_ms: int = 0


func _ready() -> void:
	name = "SettingsPanel"
	custom_minimum_size = Vector2(860.0, 0.0)
	_build()
	hide()


func _on_opening() -> void:
	for key: StringName in _volume_sliders:
		var slider: HSlider = _volume_sliders[key]
		slider.set_value_no_signal(roundf(Settings.get_volume(key) * 100.0))
		_show_volume(key, slider.value)
	_sensitivity.set_value_no_signal(Settings.mouse_sensitivity)
	_show_sensitivity(Settings.mouse_sensitivity)
	_invert.set_pressed_no_signal(Settings.invert_y)
	_invert.text = "ON" if Settings.invert_y else "OFF"


func _on_closing() -> void:
	Settings.save_settings()


func _focus_target() -> Control:
	return _volume_sliders[&"master_volume"]


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	box.add_child(UIStyle.make_heading("SETTINGS"))
	box.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 24)
	box.add_child(grid)
	_add_volume_row(grid, "Master volume", &"master_volume", "MasterSlider")
	_add_volume_row(grid, "Music volume", &"music_volume", "MusicSlider")
	_add_volume_row(grid, "Effects volume", &"sfx_volume", "SfxSlider")

	grid.add_child(_row_label("Mouse sensitivity"))
	_sensitivity = _make_slider("SensitivitySlider", Settings.MOUSE_SENSITIVITY_MIN,
			Settings.MOUSE_SENSITIVITY_MAX, 0.05)
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	grid.add_child(_sensitivity)
	_sensitivity_label = _value_label()
	grid.add_child(_sensitivity_label)

	grid.add_child(_row_label("Invert look up / down"))
	_invert = Button.new()
	_invert.name = "InvertYToggle"
	_invert.toggle_mode = true
	_invert.custom_minimum_size = Vector2(150.0, 48.0)
	_invert.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_invert.toggled.connect(_on_invert_toggled)
	grid.add_child(_invert)
	grid.add_child(Control.new())

	box.add_child(HSeparator.new())
	box.add_child(_make_back_button())


func _add_volume_row(grid: GridContainer, text: String, key: StringName, node_name: String) -> void:
	grid.add_child(_row_label(text))
	var slider: HSlider = _make_slider(node_name, 0.0, 100.0, 1.0)
	slider.value_changed.connect(_on_volume_changed.bind(key))
	grid.add_child(slider)
	var label: Label = _value_label()
	grid.add_child(label)
	_volume_sliders[key] = slider
	_volume_labels[key] = label


func _on_volume_changed(value: float, key: StringName) -> void:
	Settings.set_volume(key, value / 100.0)
	_show_volume(key, value)
	var now: int = Time.get_ticks_msec()
	if now - _last_preview_ms < PREVIEW_INTERVAL_MS:
		return
	_last_preview_ms = now
	if key == &"sfx_volume":
		AudioManager.play_sfx(&"footstep")
	elif key == &"master_volume":
		AudioManager.play_ui(&"ui_move")


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_show_sensitivity(value)


func _on_invert_toggled(enabled: bool) -> void:
	Settings.set_invert_y(enabled)
	_invert.text = "ON" if enabled else "OFF"
	AudioManager.play_ui(&"ui_move")


func _show_volume(key: StringName, value: float) -> void:
	(_volume_labels[key] as Label).text = "%d%%" % roundi(value)


func _show_sensitivity(value: float) -> void:
	_sensitivity_label.text = "%.2f×" % value


func _make_slider(node_name: String, min_value: float, max_value: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(400.0, 36.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return slider


func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(250.0, 0.0)
	return label


func _value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(90.0, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", UIStyle.CYAN)
	return label
