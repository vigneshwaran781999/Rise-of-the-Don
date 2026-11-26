class_name PauseMenu
extends CanvasLayer
## Esc / Start pauses the game: Resume, Map, Missions (replay a passed story mission, after 1.0),
## Save Game, Settings, Main Menu, Quit (subset of GDD §10).
## Pausing stops gameplay through SceneTree.paused and frees the mouse.

const MAIN_MENU_SCENE: String = "res://scenes/main/main_menu.tscn"

var _root: Control
var _menu: PanelContainer
var _settings: SettingsPanel
var _resume: Button
var _settings_button: Button
var _save: SavePanel
var _save_button: Button
var _map_button: Button
var _missions: MissionsPanel
var _missions_button: Button
var _save_only: bool = false     # opened straight on the save panel (at a property): closing it resumes
## The full map, opened from here (set by the game session).
var map_screen: MapScreen
## Mission replays, started from the Missions panel (set by the game session).
var replay: MissionReplay:
	set(value):
		replay = value
		if _missions != null:
			_missions.replay = value


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed: bool = event.is_action_pressed("pause")
	var back_pressed: bool = event.is_action_pressed("ui_cancel")
	if not (pause_pressed or back_pressed):
		return
	if not is_open():
		if pause_pressed and not MissionManager.is_failed():   # the failure screen takes over then
			open()
			get_viewport().set_input_as_handled()
		return
	if _settings.visible:
		_settings.close()
	elif _save.visible:
		_save.close()
	elif _missions.visible:
		_missions.close()
	else:
		resume()
	get_viewport().set_input_as_handled()


func open() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	_menu.show()
	_settings.hide()
	_save.hide()
	_missions.hide()
	_resume.grab_focus()
	AudioManager.play_ui(&"ui_accept")


func resume() -> void:
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_ui(&"ui_back")


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_menu = PanelContainer.new()
	_menu.name = "PausePanel"
	_menu.custom_minimum_size = Vector2(540.0, 0.0)
	center.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_menu.add_child(box)
	box.add_child(UIStyle.make_heading("PAUSED", 52))
	box.add_child(HSeparator.new())
	_resume = _add_button(box, "Resume", "ResumeButton")
	_resume.pressed.connect(resume)
	_map_button = _add_button(box, "Map", "MapButton")
	_map_button.pressed.connect(_open_map)
	_missions_button = _add_button(box, "Missions", "MissionsButton")
	_missions_button.pressed.connect(_open_missions)
	_save_button = _add_button(box, "Save Game", "SaveGameButton")
	_save_button.pressed.connect(_open_save)
	_settings_button = _add_button(box, "Settings", "SettingsButton")
	_settings_button.pressed.connect(_open_settings)
	var main_menu: Button = _add_button(box, "Main Menu", "MainMenuButton")
	main_menu.pressed.connect(_go_to_main_menu)
	var quit: Button = _add_button(box, "Quit to Desktop", "QuitButton")
	quit.pressed.connect(func() -> void: AudioManager.quit_game())

	_settings = SettingsPanel.new()
	center.add_child(_settings)
	_settings.closed.connect(_on_settings_closed)
	_save = SavePanel.new()
	center.add_child(_save)
	_save.closed.connect(_on_save_closed)
	_missions = MissionsPanel.new()
	_missions.replay = replay
	center.add_child(_missions)
	_missions.closed.connect(_on_missions_closed)
	_missions.replay_chosen.connect(_on_replay_chosen)
	_missions.end_chosen.connect(_on_end_replay)


func _add_button(parent: Control, text: String, node_name: String) -> Button:
	var button: Button = UIStyle.make_button(text, node_name)
	parent.add_child(button)
	return button


func _open_settings() -> void:
	_menu.hide()
	_settings.open()


func _on_settings_closed() -> void:
	_menu.show()
	_settings_button.grab_focus()


func _open_save() -> void:
	_menu.hide()
	_save.open_as(SavePanel.Mode.SAVE)


func _open_missions() -> void:
	_menu.hide()
	_missions.open()


func _on_missions_closed() -> void:
	if not _root.visible:
		return                 # closed by picking a replay: the game resumed
	_menu.show()
	_missions_button.grab_focus()


func _on_replay_chosen(id: StringName) -> void:
	if replay == null:
		return
	_close_for_play()
	replay.start(id)


func _on_end_replay() -> void:
	if replay == null:
		return
	_close_for_play()
	replay.end()


## Back to the game from the Missions panel (a replay starting or ending).
func _close_for_play() -> void:
	_root.hide()
	_missions.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_ui(&"ui_accept")


func _on_save_closed() -> void:
	if _save_only:
		_save_only = false
		resume()
		return
	_menu.show()
	_save_button.grab_focus()


## Pauses straight onto the save slots (a property's save point); closing them resumes the game.
func open_save() -> void:
	open()
	_save_only = true
	_open_save()


func is_saving() -> bool:
	return _root.visible and _save.visible


func _go_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _open_map() -> void:
	if map_screen == null:
		return
	_root.hide()
	if not map_screen.closed.is_connected(_on_map_closed):
		map_screen.closed.connect(_on_map_closed)
	map_screen.open(true)


func _on_map_closed() -> void:
	if not get_tree().paused:
		return
	_root.show()
	_map_button.grab_focus()
