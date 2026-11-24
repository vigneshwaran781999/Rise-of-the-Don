class_name Hud
extends CanvasLayer
## In-game HUD (GDD §10, M2 subset): health and stamina bars, an FPS counter (F3), the
## "get in" prompt near a vehicle, and while driving a speedometer with gear, revs and the
## car's health, plus a short reminder of the driving controls when you first get in.

const EXHAUSTED_COLOUR := Color(0.25, 0.42, 0.48)
const CAR_HEALTH_COLOUR := Color("ffb02e")
const HINT_SECONDS: float = 7.0
## [actions, label] for the driving reminder.
const DRIVING_HINTS: Array = [
	[["vehicle_accelerate"], "accelerate"], [["vehicle_brake"], "brake / reverse"],
	[["vehicle_steer_left", "vehicle_steer_right"], "steer"], [["vehicle_handbrake"], "handbrake"],
	[["vehicle_camera"], "camera"], [["vehicle_horn"], "horn"], [["vehicle_headlights"], "lights"],
	[["vehicle_enter_exit"], "get out"],
]

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _stamina_fill: StyleBoxFlat
var _fps_label: Label
var _stats: PlayerStats
var _prompt: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _vehicle_panel: PanelContainer
var _speedometer: Speedometer
var _car_health_bar: ProgressBar
var _hint: Label
var _hint_tween: Tween
var _vehicle: VehicleController
var _engine: VehicleEngine
var _damage: VehicleDamage
var _hint_shown: bool = false


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_fps_label.hide()


func bind_player(stats: PlayerStats) -> void:
	_stats = stats
	stats.health_changed.connect(_on_health_changed)
	stats.stamina_changed.connect(_on_stamina_changed)
	_on_health_changed(stats.health, stats.tuning.max_health)
	_on_stamina_changed(stats.stamina, stats.tuning.max_stamina)


## Shows the "get in" prompt whenever the interactor has a vehicle in reach.
func bind_interactor(interactor: VehicleInteractor) -> void:
	interactor.target_changed.connect(_on_vehicle_target_changed)
	_on_vehicle_target_changed(interactor.get_target())


func bind_vehicle(vehicle: VehicleController) -> void:
	unbind_vehicle()
	_vehicle = vehicle
	_engine = vehicle.get_node("Engine") as VehicleEngine
	_damage = vehicle.get_node("Damage") as VehicleDamage
	_damage.health_changed.connect(_on_car_health_changed)
	_on_car_health_changed(_damage.health, vehicle.stats.max_health)
	_speedometer.max_kmh = ceilf(vehicle.stats.top_speed_kmh / 20.0) * 20.0
	_vehicle_panel.show()
	_on_vehicle_target_changed(null)
	if not _hint_shown:
		_hint_shown = true
		_show_hint()


func unbind_vehicle() -> void:
	if _damage != null and _damage.health_changed.is_connected(_on_car_health_changed):
		_damage.health_changed.disconnect(_on_car_health_changed)
	_vehicle = null
	_engine = null
	_damage = null
	_vehicle_panel.hide()


func is_fps_visible() -> bool:
	return _fps_label.visible


func get_health_shown() -> float:
	return _health_bar.value


func get_stamina_shown() -> float:
	return _stamina_bar.value


func is_speedometer_visible() -> bool:
	return _vehicle_panel.visible


func get_speed_shown() -> int:
	return _speedometer.get_shown_kmh()


func get_gear_shown() -> String:
	return _speedometer.get_shown_gear()


func get_car_health_shown() -> float:
	return _car_health_bar.value


## The prompt as shown ("" when hidden), e.g. "F  GET IN".
func get_prompt_text() -> String:
	return "%s  %s" % [_prompt_key.text, _prompt_text.text] if _prompt.visible else ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fps"):
		_fps_label.visible = not _fps_label.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fps_label.visible:
		var fps: float = Engine.get_frames_per_second()
		_fps_label.text = "%d FPS   %.1f ms" % [roundi(fps), 1000.0 / maxf(fps, 1.0)]
	if _vehicle != null:
		_speedometer.set_reading(_vehicle.get_speed_kmh(), _engine.get_rpm_fraction(), _engine.get_gear_text())


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current
	_stamina_fill.bg_color = EXHAUSTED_COLOUR if _stats != null and _stats.is_exhausted() else UIStyle.CYAN


func _on_car_health_changed(current: float, maximum: float) -> void:
	_car_health_bar.max_value = maximum
	_car_health_bar.value = current


func _on_vehicle_target_changed(vehicle: VehicleController) -> void:
	if vehicle == null:
		_prompt.hide()
		return
	_prompt_key.text = _key_text("vehicle_enter_exit")
	_prompt_text.text = "GET IN"
	_prompt.show()


func _show_hint() -> void:
	var parts := PackedStringArray()
	for entry: Array in DRIVING_HINTS:
		var keys := PackedStringArray()
		for action: String in entry[0]:
			keys.append(_key_text(action))
		parts.append("%s %s" % ["/".join(keys), entry[1]])
	_hint.text = "     ".join(parts)
	_hint.modulate.a = 1.0
	_hint.show()
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_SECONDS)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 1.2)
	_hint_tween.tween_callback(_hint.hide)


## First keyboard key of an action, plus the gamepad button when a gamepad is connected.
func _key_text(action: String) -> String:
	var keys: String = ControlsPanel.describe_keyboard([action]).get_slice(" ", 0)
	if Input.get_connected_joypads().is_empty():
		return keys
	var pad: String = ControlsPanel.describe_gamepad([action]).get_slice(",", 0)
	return "%s / %s" % [keys, pad] if pad != "" else keys


# --------------------------------------------------------------------------- layout

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.theme = UIStyle.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_top"]:
		margin.add_theme_constant_override(side, 30)
	root.add_child(margin)

	var panel := _panel("VitalsPanel")
	margin.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	_health_bar = _add_bar(rows, "HEALTH", "HealthBar", UIStyle.make_bar_fill(UIStyle.HEALTH), 300.0)
	_stamina_fill = UIStyle.make_bar_fill(UIStyle.CYAN)
	_stamina_bar = _add_bar(rows, "STAMINA", "StaminaBar", _stamina_fill, 300.0)

	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.label_settings = UIStyle.glow_label(22, UIStyle.CYAN, UIStyle.CYAN, 6)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_fps_label)
	_fps_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -320.0
	_fps_label.offset_right = -30.0
	_fps_label.offset_top = 26.0
	_fps_label.offset_bottom = 60.0

	_build_prompt(root)
	_build_vehicle_panel(root)

	_hint = Label.new()
	_hint.name = "DrivingHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 19)
	_hint.add_theme_color_override("font_color", UIStyle.TEXT)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -760.0
	_hint.offset_right = 760.0
	_hint.offset_top = -64.0
	_hint.offset_bottom = -34.0
	_hint.hide()


func _build_prompt(root: Control) -> void:
	_prompt = _panel("InteractPrompt")
	root.add_child(_prompt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_prompt.add_child(row)
	var key_box := PanelContainer.new()
	var key_style := StyleBoxFlat.new()
	key_style.bg_color = Color(UIStyle.CYAN, 0.12)
	key_style.border_color = UIStyle.CYAN
	key_style.set_border_width_all(2)
	key_style.set_corner_radius_all(4)
	key_style.content_margin_left = 10.0
	key_style.content_margin_right = 10.0
	key_box.add_theme_stylebox_override("panel", key_style)
	row.add_child(key_box)
	_prompt_key = Label.new()
	_prompt_key.add_theme_font_size_override("font_size", 22)
	_prompt_key.add_theme_color_override("font_color", UIStyle.CYAN)
	key_box.add_child(_prompt_key)
	_prompt_text = Label.new()
	_prompt_text.add_theme_font_size_override("font_size", 22)
	_prompt_text.add_theme_color_override("font_color", UIStyle.TEXT)
	_prompt_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt_text)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -150.0
	_prompt.hide()


func _build_vehicle_panel(root: Control) -> void:
	_vehicle_panel = _panel("VehiclePanel")
	root.add_child(_vehicle_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_vehicle_panel.add_child(column)
	_speedometer = Speedometer.new()
	_speedometer.name = "Speedometer"
	column.add_child(_speedometer)
	_car_health_bar = _add_bar(column, "CAR", "CarHealthBar", UIStyle.make_bar_fill(CAR_HEALTH_COLOUR), 170.0)
	_vehicle_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_vehicle_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_vehicle_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vehicle_panel.offset_right = -30.0
	_vehicle_panel.offset_bottom = -30.0
	_vehicle_panel.hide()


func _panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = (UIStyle.get_theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate()
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	style.shadow_size = 12
	style.bg_color = Color(UIStyle.PANEL_BG, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _add_bar(parent: Control, caption: String, node_name: String, fill: StyleBoxFlat, width: float) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(104.0 if width > 200.0 else 50.0, 0.0)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 12.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar
