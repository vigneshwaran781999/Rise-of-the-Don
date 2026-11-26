class_name SettingsPanel
extends MenuPanel
## Master / music / effects volume, mouse sensitivity, invert-Y, pedestrian and traffic density,
## and graphics (M8: the quality preset, ambient occlusion, glow, shadows and lights, render scale,
## VSync, fullscreen; Settings applies them)
## (subset of GDD §10). The rows scroll (keyboard and gamepad focus brings each into view).
## Changes apply instantly; they are written to user://settings.cfg when the panel closes.

const PREVIEW_INTERVAL_MS: int = 120

var _volume_sliders: Dictionary = {}  # StringName -> HSlider
var _volume_labels: Dictionary = {}   # StringName -> Label
var _sensitivity: HSlider
var _sensitivity_label: Label
var _invert: Button
var _density_buttons: Dictionary = {}  # StringName -> Button
var _last_preview_ms: int = 0
var _graphics_rows: Array = []        # [Button, Callable that gives its text]


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
	for key: StringName in _density_buttons:
		(_density_buttons[key] as Button).text = "◀  %s  ▶" % Settings.DENSITY_NAMES[Settings.get_density(key)].to_upper()
	_refresh_graphics()


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

	var scroll := ScrollContainer.new()
	scroll.name = "Rows"
	scroll.custom_minimum_size = Vector2(0.0, 600.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 24)
	scroll.add_child(grid)
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

	_add_density_row(grid, "Pedestrians", &"pedestrian_density", "PedestrianDensityButton")
	_add_density_row(grid, "Traffic", &"traffic_density", "TrafficDensityButton")

	var heading := _row_label("GRAPHICS")
	heading.add_theme_color_override("font_color", UIStyle.MAGENTA)
	grid.add_child(heading)
	grid.add_child(Control.new())
	grid.add_child(Control.new())
	_add_option_row(grid, "Graphics quality", "QualityButton",
		func() -> String: return _cycle_text(Settings.QUALITY_NAMES[Settings.quality]),
		func() -> void: Settings.set_quality((Settings.quality + 1) % Settings.QUALITY_NAMES.size()))
	_add_option_row(grid, "Ambient occlusion", "AmbientOcclusionToggle",
		func() -> String: return _on_off(Settings.ambient_occlusion),
		func() -> void: Settings.set_ambient_occlusion(not Settings.ambient_occlusion))
	_add_option_row(grid, "Glow", "GlowToggle",
		func() -> String: return _on_off(Settings.glow),
		func() -> void: Settings.set_glow(not Settings.glow))
	_add_option_row(grid, "Shadows and lights", "ShadowButton",
		func() -> String: return _cycle_text(Settings.SHADOW_NAMES[Settings.shadow_quality]),
		func() -> void: Settings.set_shadow_quality((Settings.shadow_quality + 1) % Settings.SHADOW_NAMES.size()))
	_add_option_row(grid, "Render scale", "RenderScaleButton",
		func() -> String: return _cycle_text("%d%%" % roundi(Settings.render_scale * 100.0)),
		func() -> void: Settings.set_render_scale(_next_scale()))
	_add_option_row(grid, "VSync", "VSyncToggle",
		func() -> String: return _on_off(Settings.vsync),
		func() -> void: Settings.set_vsync(not Settings.vsync))
	_add_option_row(grid, "Fullscreen", "FullscreenToggle",
		func() -> String: return _on_off(Settings.fullscreen),
		func() -> void: Settings.set_fullscreen(not Settings.fullscreen))

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


## A button that cycles Low -> Medium -> High (how many people / cars are on the streets).
func _add_density_row(grid: GridContainer, text: String, key: StringName, node_name: String) -> void:
	grid.add_child(_row_label(text))
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(200.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(_on_density_pressed.bind(key, button))
	grid.add_child(button)
	grid.add_child(Control.new())
	_density_buttons[key] = button


## A graphics option: a button showing `show`'s text that does `press` (and refreshes every
## graphics row: the quality preset changes the others).
func _add_option_row(grid: GridContainer, text: String, node_name: String, show: Callable, press: Callable) -> void:
	grid.add_child(_row_label(text))
	var button := Button.new()
	button.name = node_name
	button.custom_minimum_size = Vector2(200.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(func() -> void:
		press.call()
		_refresh_graphics()
		AudioManager.play_ui(&"ui_move"))
	grid.add_child(button)
	grid.add_child(Control.new())
	_graphics_rows.append([button, show])


func _refresh_graphics() -> void:
	for row: Array in _graphics_rows:
		(row[0] as Button).text = (row[1] as Callable).call()


static func _cycle_text(value: String) -> String:
	return "◀  %s  ▶" % value.to_upper()


static func _on_off(enabled: bool) -> String:
	return "ON" if enabled else "OFF"


## The render scale after the current one (wrapping round).
static func _next_scale() -> float:
	var scales: PackedFloat32Array = Settings.RENDER_SCALES
	for i: int in scales.size():
		if absf(scales[i] - Settings.render_scale) < 0.01:
			return scales[(i + 1) % scales.size()]
	return scales[scales.size() - 1]


func _on_density_pressed(key: StringName, button: Button) -> void:
	Settings.set_density(key, (Settings.get_density(key) + 1) % Settings.DENSITY_NAMES.size())
	button.text = "◀  %s  ▶" % Settings.DENSITY_NAMES[Settings.get_density(key)].to_upper()
	AudioManager.play_ui(&"ui_move")


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
