class_name Hud
extends CanvasLayer
## On-foot HUD (M1 subset of GDD §10): health and stamina bars, and an FPS counter
## toggled with F3.

const EXHAUSTED_COLOUR := Color(0.25, 0.42, 0.48)

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _stamina_fill: StyleBoxFlat
var _fps_label: Label
var _stats: PlayerStats


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


func is_fps_visible() -> bool:
	return _fps_label.visible


func get_health_shown() -> float:
	return _health_bar.value


func get_stamina_shown() -> float:
	return _stamina_bar.value


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fps"):
		_fps_label.visible = not _fps_label.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _fps_label.visible:
		var fps: float = Engine.get_frames_per_second()
		_fps_label.text = "%d FPS   %.1f ms" % [roundi(fps), 1000.0 / maxf(fps, 1.0)]


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current
	_stamina_fill.bg_color = EXHAUSTED_COLOUR if _stats != null and _stats.is_exhausted() else UIStyle.CYAN


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

	var panel := PanelContainer.new()
	panel.name = "VitalsPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = (UIStyle.get_theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate()
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	style.shadow_size = 12
	style.bg_color = Color(UIStyle.PANEL_BG, 0.7)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	panel.add_child(rows)
	_health_bar = _add_bar(rows, "HEALTH", "HealthBar", UIStyle.make_bar_fill(UIStyle.HEALTH))
	_stamina_fill = UIStyle.make_bar_fill(UIStyle.CYAN)
	_stamina_bar = _add_bar(rows, "STAMINA", "StaminaBar", _stamina_fill)

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


func _add_bar(parent: Control, caption: String, node_name: String, fill: StyleBoxFlat) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(104.0, 0.0)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300.0, 12.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar
