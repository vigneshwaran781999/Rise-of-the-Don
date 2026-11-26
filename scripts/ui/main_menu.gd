extends Control
## Title screen (GDD §10): New Game, Continue (the latest save), Load Game, Settings,
## Controls, Credits, Exit. Keyboard, mouse and gamepad navigable.

const GAME_SCENE: String = "res://scenes/main/game.tscn"
const BACKGROUND_SHADER: Shader = preload("res://shaders/menu_background.gdshader")

var _new_game: Button
var _menu_buttons: Array[Button] = []
var _panels: Array[MenuPanel] = []
var _settings: SettingsPanel
var _controls: ControlsPanel
var _credits: CreditsPanel
var _load: SavePanel
var _return_focus: Button
var _starting: bool = false


func _ready() -> void:
	theme = UIStyle.get_theme()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	AudioManager.play_music(&"menu_pad")
	_new_game.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	for panel: MenuPanel in _panels:
		if panel.visible:
			panel.close()
			get_viewport().set_input_as_handled()
			return


func _build() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	var background_material := ShaderMaterial.new()
	background_material.shader = BACKGROUND_SHADER
	background.material = background_material
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 150)
	margin.add_theme_constant_override("margin_top", 110)
	margin.add_theme_constant_override("margin_right", 110)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 90)
	margin.add_child(row)

	var column := VBoxContainer.new()
	column.name = "MenuColumn"
	column.add_theme_constant_override("separation", 0)
	row.add_child(column)
	_build_title(column)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 56.0)
	column.add_child(gap)

	var buttons := VBoxContainer.new()
	buttons.name = "Buttons"
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	_new_game = _add_button(buttons, "New Game", "NewGameButton")
	_new_game.pressed.connect(_start_new_game)
	var has_save: bool = SaveManager.has_any_save()
	var continue_button: Button = _add_button(buttons, "Continue", "ContinueButton")
	continue_button.pressed.connect(_continue_game)
	var load_button: Button = _add_button(buttons, "Load Game", "LoadGameButton")
	for button: Button in [continue_button, load_button]:
		button.disabled = not has_save
		button.focus_mode = Control.FOCUS_ALL if has_save else Control.FOCUS_NONE
		button.tooltip_text = "" if has_save else "No saved game yet."
	var settings_button: Button = _add_button(buttons, "Settings", "SettingsButton")
	var controls_button: Button = _add_button(buttons, "Controls", "ControlsButton")
	var credits_button: Button = _add_button(buttons, "Credits", "CreditsButton")
	var exit_button: Button = _add_button(buttons, "Exit", "ExitButton")
	exit_button.pressed.connect(func() -> void: AudioManager.quit_game())

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var footer := Label.new()
	footer.name = "Footer"
	footer.text = "v%s      Enter / A select   ·   Esc / B back" % \
			str(ProjectSettings.get_setting("application/config/version", "1.0.3"))
	footer.add_theme_font_size_override("font_size", 18)
	footer.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	column.add_child(footer)

	var panel_area := CenterContainer.new()
	panel_area.name = "PanelArea"
	panel_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel_area)
	_settings = SettingsPanel.new()
	_controls = ControlsPanel.new()
	_credits = CreditsPanel.new()
	_load = SavePanel.new()
	_load.mode = SavePanel.Mode.LOAD
	for panel: MenuPanel in [_settings, _controls, _credits, _load]:
		panel_area.add_child(panel)
		panel.closed.connect(_on_panel_closed)
		_panels.append(panel)
	load_button.pressed.connect(_open_panel.bind(_load, load_button))
	settings_button.pressed.connect(_open_panel.bind(_settings, settings_button))
	controls_button.pressed.connect(_open_panel.bind(_controls, controls_button))
	credits_button.pressed.connect(_open_panel.bind(_credits, credits_button))


func _build_title(column: VBoxContainer) -> void:
	var spaced := FontVariation.new()
	spaced.base_font = UIStyle.get_font()
	spaced.spacing_glyph = 10
	var top := Label.new()
	top.name = "TitleTop"
	top.text = "RISE OF THE"
	var top_settings: LabelSettings = UIStyle.glow_label(46, UIStyle.CYAN, UIStyle.CYAN, 10)
	top_settings.font = spaced
	top.label_settings = top_settings
	column.add_child(top)

	var don := Label.new()
	don.name = "TitleDon"
	don.text = "DON"
	don.label_settings = UIStyle.glow_label(176, UIStyle.TEXT, UIStyle.MAGENTA, 28)
	column.add_child(don)

	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.text = "THE CITY NEVER FORGIVES."
	var tag_settings: LabelSettings = UIStyle.glow_label(24, UIStyle.TEXT_DIM, UIStyle.MAGENTA, 6)
	var tag_font := FontVariation.new()
	tag_font.base_font = UIStyle.get_font()
	tag_font.spacing_glyph = 5
	tag_settings.font = tag_font
	tagline.label_settings = tag_settings
	column.add_child(tagline)


func _add_button(parent: Control, text: String, node_name: String) -> Button:
	var button: Button = UIStyle.make_button(text, node_name)
	parent.add_child(button)
	_menu_buttons.append(button)
	return button


func _open_panel(panel: MenuPanel, from: Button) -> void:
	for other: MenuPanel in _panels:
		if other != panel and other.visible:
			other.hide()
	_return_focus = from
	panel.open()


func _on_panel_closed() -> void:
	if _return_focus != null:
		_return_focus.grab_focus()


func _start_new_game() -> void:
	if _starting:
		return
	_starting = true
	for button: Button in _menu_buttons:
		button.disabled = true
	AudioManager.stop_music(0.6)
	LoadingCard.change_to(get_tree(), GAME_SCENE)


## Loads the most recent save (manual or autosave).
func _continue_game() -> void:
	var slot: int = SaveManager.latest_slot()
	if _starting or slot < 0:
		return
	_starting = true
	for button: Button in _menu_buttons:
		button.disabled = true
	AudioManager.stop_music(0.6)
	if SaveManager.load_game(slot) != OK:
		_starting = false
		for button: Button in _menu_buttons:
			button.disabled = false
