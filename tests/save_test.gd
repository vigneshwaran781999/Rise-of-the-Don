extends Node
## Save / load test (per-feature test scene, M5). Drives the real menus and game scenes:
## - With no saves, Continue and Load Game are disabled.
## - New Game, pass mission 1 (autosave), start mission 2 and talk to the fixer, then save to
##   slot 2 from the pause menu (and see slot 1 asked to confirm an overwrite).
## - Change things (cash, position), load slot 2 through Main Menu -> Load Game: cash, missions,
##   stats, play time, health and position come back, and mission 2 resumes at its checkpoint.
## - Saving while driving stores a spot beside the car; damaged and other-version files are
##   refused without harm; Continue loads the most recent save.
## Saves go to user://test_saves, never the player's real saves.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/save_test.tscn
## Prints "SAVE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const GAME: String = "res://scenes/main/game.tscn"
const TEST_SAVES: String = "user://test_saves"

var _catcher: ErrorCatcher
var _report: PackedStringArray = []
var _saved_state: Dictionary = {}


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	SaveManager.save_dir = TEST_SAVES
	_wipe_saves()
	_run.call_deferred()


func _run() -> void:
	var stand_in := Node.new()
	stand_in.name = "SceneStandIn"
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	var steps: Array[Callable] = [
		_check_menu_without_saves, _check_play_and_save, _check_load_restores, _check_save_in_vehicle,
		_check_bad_files, _check_continue_latest,
	]
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
	for code: Key in [KEY_E, KEY_F, KEY_ESCAPE]:
		_key(code, false)
	print("SAVE REPORT")
	for line: String in _report:
		print("  " + line)
	_wipe_saves()
	OS.remove_logger(_catcher)
	get_tree().paused = false
	if failure == "":
		print("SAVE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_menu_without_saves() -> String:
	var menu: Node = await _open_scene(MAIN_MENU)
	for button_name: String in ["ContinueButton", "LoadGameButton"]:
		var button := menu.find_child(button_name, true, false) as Button
		if button == null or not button.disabled:
			return "%s should exist and be disabled without saves" % button_name
	_note("no saves: Continue and Load Game are disabled")
	return ""


func _check_play_and_save() -> String:
	var menu: Node = get_tree().current_scene
	(menu.find_child("NewGameButton", true, false) as Button).pressed.emit()
	var game := await _wait_for_scene(GAME) as GameSession
	if game == null:
		return "New Game did not load the game"
	_quiet_streets(game)
	await _ticks(20)
	var player: PlayerController = game.player
	# Pass mission 1 by visiting its three places (autosave), then start mission 2 and talk.
	var welcome: MissionData = MissionManager.get_active()
	for objective: MissionObjective in welcome.objectives:
		await _teleport(player, objective.position + Vector3(0.6, 0.1, 0.0))
		await _ticks(8)
	if not MissionManager.is_completed(&"welcome"):
		return "couldn't pass mission 1"
	await _ticks(5)
	var autosave: Dictionary = SaveManager.read_slot(SaveManager.AUTOSAVE_SLOT)
	if autosave.is_empty() or autosave["summary"]["missions_passed"] != 1.0:
		return "no autosave after mission 1 (%s)" % autosave.get("summary", {})
	var second: MissionData = MissionManager.get_mission(&"first_opportunity")
	await _teleport(player, second.start_position + Vector3(0.3, 0.1, 0.0))
	await _ticks(5)
	await _teleport(player, second.giver.position + Vector3(-1.6, 0.1, 0.0))
	await _ticks(5)
	_tap(KEY_E)
	for i: int in 10:
		await _ticks(3)
		_tap(KEY_E)
	await _ticks(5)
	if MissionManager.get_objective_index() != 1:
		return "couldn't get mission 2 to its second objective (at %d)" % MissionManager.get_objective_index()
	player.stats.set_health(61.0)
	GameState.set_hour(21.25)
	# Owned things and clothes (M6): a house and an outfit bought, the outfit worn.
	EconomyManager.buy(&"verandah_house", 0, &"test")
	EconomyManager.buy(&"outfit_kurta", 0, &"test")
	GameState.set_outfit(&"kurta")
	GameState.day = 3
	await _ticks(2)
	# Save to slot 2 from the pause menu; slot 1 gets a game first to see the overwrite question.
	if SaveManager.save_game(1) != OK:
		return "saving to slot 1 failed"
	_tap(KEY_ESCAPE)
	await _frames(3)
	var pause := game.get_node("PauseMenu") as PauseMenu
	if not pause.is_open():
		return "Esc didn't pause"
	(pause.find_child("SaveGameButton", true, false) as Button).pressed.emit()
	await _frames(2)
	var panel := pause.find_child("SavePanel", true, false) as SavePanel
	if panel == null or not panel.visible:
		return "Save Game didn't open the save panel"
	if not panel.get_row(SaveManager.AUTOSAVE_SLOT).disabled:
		return "the autosave slot should not be selectable for saving"
	panel.get_row(1).pressed.emit()
	if not panel.get_status_text().contains("overwrite"):
		return "picking an occupied slot should ask before overwriting (status '%s')" % panel.get_status_text()
	panel.get_row(2).pressed.emit()
	if panel.get_status_text() != "Saved to slot 2.":
		return "saving to slot 2 said '%s'" % panel.get_status_text()
	var slot2: Dictionary = SaveManager.read_slot(2)
	if slot2.is_empty() or slot2["summary"]["mission"] != "First Opportunity" or int(slot2["summary"]["cash"]) != 500:
		return "slot 2 summary is wrong: %s" % slot2.get("summary", {})
	if not panel.get_row(2).text.contains("FIRST OPPORTUNITY") or not panel.get_row(2).text.contains("₹500"):
		return "slot 2's row should describe the save (got '%s')" % panel.get_row(2).text.replace("\n", " | ")
	_saved_state = {"position": player.global_position, "play_time": GameState.play_time}
	panel.close()
	pause.resume()
	await _ticks(2)
	_note("pause -> Save Game: autosave row read-only, an occupied slot asks before overwriting, slot 2 saved and described as '%s'" % panel.get_row(2).text.get_slice("\n", 1))
	return ""


func _check_load_restores() -> String:
	var game := get_tree().current_scene as GameSession
	# Change things after saving.
	EconomyManager.add(777, &"test")
	GameState.set_outfit(&"arrival")
	await _teleport(game.player, Vector3(20.0, 0.6, -60.0))
	# Main Menu -> Load Game -> slot 2.
	_tap(KEY_ESCAPE)
	await _frames(3)
	var pause := game.get_node("PauseMenu") as PauseMenu
	(pause.find_child("MainMenuButton", true, false) as Button).pressed.emit()
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	if menu == null:
		return "Main Menu didn't return to the title screen"
	var continue_button := menu.find_child("ContinueButton", true, false) as Button
	var load_button := menu.find_child("LoadGameButton", true, false) as Button
	if continue_button.disabled or load_button.disabled:
		return "with saves, Continue and Load Game should be enabled"
	load_button.pressed.emit()
	await _frames(2)
	var panel := menu.find_child("SavePanel", true, false) as SavePanel
	if panel == null or not panel.visible or panel.get_row(3).disabled == false:
		return "Load Game should list the slots, empty slot 3 disabled"
	panel.get_row(2).pressed.emit()
	var loaded := await _wait_for_scene(GAME) as GameSession
	if loaded == null:
		return "loading slot 2 didn't start the game"
	_quiet_streets(loaded)
	await _ticks(20)
	var player: PlayerController = loaded.player
	if EconomyManager.cash != 500:
		return "cash after loading is %d, expected 500" % EconomyManager.cash
	if not MissionManager.is_completed(&"welcome") or MissionManager.get_active() == null or MissionManager.get_active().id != &"first_opportunity":
		return "mission state after loading: completed %s, active %s" % [MissionManager.get_completed(), MissionManager.get_active()]
	if MissionManager.get_objective_index() != 0:
		return "mission 2 should resume at its checkpoint (the top), it's at objective %d" % MissionManager.get_objective_index()
	if absf(player.stats.health - 61.0) > 0.5:
		return "health after loading is %.1f, expected 61" % player.stats.health
	var saved_at: Vector3 = _saved_state["position"]
	if Vector2(player.global_position.x - saved_at.x, player.global_position.z - saved_at.z).length() > 1.0:
		return "the player should be where they saved (%s), is at %s" % [saved_at, player.global_position]
	if GameState.day != 3 or absf(GameState.hour - 21.25) > 0.2:
		return "the clock after loading reads day %d %.2f h, saved day 3 21.25 h" % [GameState.day, GameState.hour]
	var figure := loaded.get_node("Player/Model/Figure") as PlayerFigure
	if not EconomyManager.owns(&"verandah_house") or not EconomyManager.owns(&"outfit_kurta") or GameState.outfit != &"kurta" or figure.get_outfit().id != &"kurta":
		return "loading should bring back the house, the kurta and wearing it (owned %s, wearing %s)" % [EconomyManager.get_owned(), GameState.outfit]
	if GameState.play_time < float(_saved_state["play_time"]) - 0.01 or GameState.get_stat(&"missions_passed") != 1:
		return "play time %.1f (saved %.1f) or stats %s not restored" % [GameState.play_time, _saved_state["play_time"], GameState.stats]
	var hud := loaded.get_node("HUD") as Hud
	if hud.get_cash_shown() != "₹500" or hud.get_mission_hud().get_objective_shown() != "Talk to the fixer.":
		return "HUD after loading: cash '%s', objective '%s'" % [hud.get_cash_shown(), hud.get_mission_hud().get_objective_shown()]
	_note("Main Menu -> Load Game -> slot 2: cash ₹500 (the ₹777 earned after saving is gone), health 61, position, day 3 21:15, the house and the kurta (worn), play time, stats and mission 2 (resumed at its checkpoint) restored")
	return ""


func _check_save_in_vehicle() -> String:
	var game := get_tree().current_scene as GameSession
	var player: PlayerController = game.player
	var car := game.get_node("World/Vehicles/Sedan") as VehicleController
	await _teleport(player, car.get_exit_points()[0] + Vector3.UP * 0.1)
	await _ticks(10)
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if player.is_in_vehicle():
			break
	if not player.is_in_vehicle():
		return "couldn't get into the parked sedan"
	if SaveManager.save_game(3) != OK:
		return "saving in a car failed"
	var p: Array = SaveManager.read_slot(3)["state"]["player"]["position"]
	var spot := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var from_car: float = Vector2(spot.x - car.global_position.x, spot.z - car.global_position.z).length()
	if from_car < 0.8 or from_car > 4.0:
		return "a save made in a car should store a spot beside it (%.1f m from the car)" % from_car
	_note("saving while driving stores a spot %.1f m beside the car" % from_car)
	return ""


func _check_bad_files() -> String:
	_write(SaveManager.slot_path(1), "{ this is not json")
	_write(SaveManager.slot_path(3), JSON.stringify({"version": 99, "state": {}, "summary": {}}))
	if SaveManager.read_slot(1).get("error", "") != "damaged" or SaveManager.read_slot(3).get("error", "") != "version":
		return "damaged / other-version files should be recognised (%s, %s)" % [SaveManager.read_slot(1), SaveManager.read_slot(3)]
	if SaveManager.load_game(1) == OK or SaveManager.load_game(3) == OK:
		return "loading a damaged or other-version file should be refused"
	if SavePanel.describe(SaveManager.read_slot(1)) != "Damaged save":
		return "a damaged slot should read 'Damaged save'"
	await _ticks(5)
	if not (get_tree().current_scene is GameSession):
		return "a refused load must leave the game running"
	_note("a damaged file and a file from another save version are refused (the game carries on) and listed as such")
	return ""


func _check_continue_latest() -> String:
	# A fresh autosave (with more cash) is now the newest save.
	var game := get_tree().current_scene as GameSession
	EconomyManager.add(5000, &"test")
	if SaveManager.save_game(SaveManager.AUTOSAVE_SLOT) != OK:
		return "autosave failed"
	if SaveManager.latest_slot() != SaveManager.AUTOSAVE_SLOT:
		return "the newest save should be the autosave (latest %d)" % SaveManager.latest_slot()
	var pause := game.get_node("PauseMenu") as PauseMenu
	pause.open()
	(pause.find_child("MainMenuButton", true, false) as Button).pressed.emit()
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	(menu.find_child("ContinueButton", true, false) as Button).pressed.emit()
	var loaded := await _wait_for_scene(GAME) as GameSession
	if loaded == null:
		return "Continue didn't load the game"
	await _ticks(10)
	if EconomyManager.cash != 5500:
		return "Continue should load the newest save (cash %d, expected 5500)" % EconomyManager.cash
	_note("Continue loads the newest save (the autosave here)")
	return ""


# --------------------------------------------------------------------------- helpers

func _quiet_streets(game: Node) -> void:
	var traffic := game.get_node("Traffic") as TrafficManager
	var people := game.get_node("Pedestrians") as PedestrianManager
	traffic.enabled = false
	people.enabled = false
	traffic.clear()
	people.clear()


func _open_scene(path: String) -> Node:
	get_tree().change_scene_to_file(path)
	return await _wait_for_scene(path)


func _wait_for_scene(path: String, max_frames: int = 900) -> Node:
	for i: int in max_frames:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == path and scene.is_node_ready():
			return scene
		await get_tree().process_frame
	return null


func _teleport(player: PlayerController, pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await _ticks(3)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _wipe_saves() -> void:
	for slot: int in SaveManager.ALL_SLOTS:
		SaveManager.delete_slot(slot)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
