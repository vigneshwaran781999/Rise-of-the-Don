class_name MissionHud
extends Control
## The mission parts of the HUD (GDD §8, §10): the mission title and current objective (with the
## time left when there is a clock), tutorial hints, dialogue subtitles, the waypoint arrow, and
## the big banners for a mission starting and being passed. The failure screen is separate
## (MissionFailedScreen).

const HINT_SECONDS: float = 7.0
const BANNER_SECONDS: float = 3.2
const SPEAKER_COLOUR := "ff2bd6"

var waypoint: WaypointIndicator

var _panel: PanelContainer
var _title: Label
var _objective: Label
var _timer: Label
var _hint: Label
var _hint_tween: Tween
var _subtitle_box: PanelContainer
var _subtitle: RichTextLabel
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_tween: Tween
var _director: MissionDirector
var _hold_until_ms: int = 0


func _ready() -> void:
	name = "MissionHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.mission_passed.connect(_on_mission_passed)
	MissionManager.mission_failed.connect(_on_mission_failed)
	MissionManager.mission_ended.connect(_on_mission_ended)


func _exit_tree() -> void:
	for pair: Array in [[MissionManager.mission_started, _on_mission_started], [MissionManager.mission_passed, _on_mission_passed],
			[MissionManager.mission_failed, _on_mission_failed], [MissionManager.mission_ended, _on_mission_ended]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func bind(director: MissionDirector, player: Node3D) -> void:
	_director = director
	waypoint.origin = player
	director.objective_text_changed.connect(_on_objective_text)
	director.hint_requested.connect(show_hint)
	director.waypoint_changed.connect(func(target: Node3D) -> void: waypoint.target = target)
	director.timer_changed.connect(_on_timer)
	director.dialogue.line_started.connect(_on_line)
	var active: MissionData = MissionManager.get_active()
	if active != null:
		_title.text = active.title.to_upper()


# --------------------------------------------------------------------------- read-outs for tests

func get_objective_shown() -> String:
	return _objective.text if _panel.visible else ""


func get_title_shown() -> String:
	return _title.text if _panel.visible else ""


func get_timer_shown() -> String:
	return _timer.text if _timer.visible and _panel.visible else ""


func get_subtitle_shown() -> String:
	return _subtitle.get_parsed_text() if _subtitle_box.visible else ""


func get_hint_shown() -> String:
	return _hint.text if _hint.visible else ""


func get_banner_shown() -> String:
	return "%s %s" % [_banner_title.text, _banner_sub.text] if _banner.visible else ""


# --------------------------------------------------------------------------- updates

## Keeps banners back for `seconds` (while the district title card is up).
func hold_banners(seconds: float) -> void:
	_hold_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	_hint.show()
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(HINT_SECONDS)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 1.0)
	_hint_tween.tween_callback(_hint.hide)


func _on_mission_started(mission: MissionData, checkpoint: int) -> void:
	_title.text = mission.title.to_upper()
	if checkpoint == 0:
		_show_banner(mission.title.to_upper(), mission.description)
	else:
		_show_banner(mission.title.to_upper(), "Back at the last checkpoint")
	AudioManager.play_ui(&"mission_start")


func _on_mission_passed(mission: MissionData) -> void:
	var reward: String = ("+" + EconomyManager.format(mission.reward_cash)) if mission.reward_cash > 0 else ""
	_show_banner("MISSION PASSED", reward)
	AudioManager.play_ui(&"mission_passed")


func _on_mission_failed(_mission: MissionData, _reason: String) -> void:
	_panel.hide()
	_hint.hide()


func _on_mission_ended(_mission: MissionData) -> void:
	_panel.hide()
	_timer.hide()


func _on_objective_text(text: String) -> void:
	_objective.text = text
	_panel.visible = text != "" and MissionManager.is_active()
	if _panel.visible:
		_objective.modulate.a = 0.0
		create_tween().tween_property(_objective, "modulate:a", 1.0, 0.35)


func _on_timer(seconds_left: float) -> void:
	_timer.visible = seconds_left >= 0.0
	if seconds_left >= 0.0:
		var whole: int = ceili(seconds_left)
		_timer.text = "%d:%02d" % [whole / 60, whole % 60]
		_timer.add_theme_color_override("font_color", Color("ff5d7a") if seconds_left < 15.0 else UIStyle.CYAN)


func _on_line(speaker: String, text: String) -> void:
	if text == "":
		_subtitle_box.hide()
		return
	var who: String = "[color=#%s]%s[/color]   " % [SPEAKER_COLOUR, speaker.to_upper()] if speaker != "" else ""
	_subtitle.text = who + text.replace("[", "[lb]")
	_subtitle_box.show()


func _show_banner(title: String, subtitle: String) -> void:
	_banner_title.text = title
	_banner_sub.text = subtitle
	_banner.modulate.a = 0.0
	_banner.show()
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	var wait_ms: int = _hold_until_ms - Time.get_ticks_msec()
	if wait_ms > 0:
		_banner_tween.tween_interval(wait_ms / 1000.0)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.5)
	_banner_tween.tween_interval(BANNER_SECONDS)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.9)
	_banner_tween.tween_callback(_banner.hide)


# --------------------------------------------------------------------------- layout

func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MissionPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = (UIStyle.get_theme().get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate()
	style.bg_color = Color(UIStyle.PANEL_BG, 0.7)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_panel.position = Vector2(30.0, 150.0)
	_panel.custom_minimum_size = Vector2(420.0, 0.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	_title = Label.new()
	_title.name = "MissionTitle"
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", UIStyle.MAGENTA)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	_timer = Label.new()
	_timer.name = "MissionTimer"
	_timer.add_theme_font_size_override("font_size", 26)
	_timer.add_theme_color_override("font_color", UIStyle.CYAN)
	_timer.hide()
	top.add_child(_timer)
	_objective = Label.new()
	_objective.name = "ObjectiveText"
	_objective.add_theme_font_size_override("font_size", 23)
	_objective.add_theme_color_override("font_color", UIStyle.TEXT)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(420.0, 0.0)
	column.add_child(_objective)
	_panel.hide()

	_hint = Label.new()
	_hint.name = "MissionHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 21)
	_hint.add_theme_color_override("font_color", UIStyle.CYAN)
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -700.0
	_hint.offset_right = 700.0
	_hint.offset_top = -300.0
	_hint.offset_bottom = -266.0
	_hint.hide()

	_subtitle_box = PanelContainer.new()
	_subtitle_box.name = "Subtitle"
	_subtitle_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_style := StyleBoxFlat.new()
	sub_style.bg_color = Color(0.0, 0.0, 0.02, 0.62)
	sub_style.set_corner_radius_all(6)
	sub_style.content_margin_left = 22.0
	sub_style.content_margin_right = 22.0
	sub_style.content_margin_top = 10.0
	sub_style.content_margin_bottom = 10.0
	_subtitle_box.add_theme_stylebox_override("panel", sub_style)
	add_child(_subtitle_box)
	_subtitle_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_box.offset_left = -560.0
	_subtitle_box.offset_right = 560.0
	_subtitle_box.offset_top = -250.0
	_subtitle_box.offset_bottom = -190.0
	_subtitle = RichTextLabel.new()
	_subtitle.name = "SubtitleText"
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.add_theme_font_size_override("normal_font_size", 25)
	_subtitle.add_theme_color_override("default_color", UIStyle.TEXT)
	_subtitle_box.add_child(_subtitle)
	_subtitle_box.hide()

	_banner = VBoxContainer.new()
	_banner.name = "MissionBanner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", 2)
	add_child(_banner)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -700.0
	_banner.offset_right = 700.0
	_banner.offset_top = -190.0
	_banner.offset_bottom = -60.0
	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.label_settings = UIStyle.glow_label(66, UIStyle.TEXT, UIStyle.MAGENTA, 16)
	_banner.add_child(_banner_title)
	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner_sub.label_settings = UIStyle.glow_label(26, UIStyle.CYAN, UIStyle.CYAN, 6)
	_banner.add_child(_banner_sub)
	_banner.hide()

	waypoint = WaypointIndicator.new()
	add_child(waypoint)
	waypoint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
