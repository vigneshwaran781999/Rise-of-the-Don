extends Node
## Mission replay test (after 1.0). Starts a game in the real game scene with the whole story
## passed (ending: the ledger to the inspector), then works the pause menu's Missions panel:
## - the list: the fifteen story missions in order, no side jobs; End Replay hidden;
## - blocked: another mission running, the police after you, in a car (rows greyed, a reason);
## - mission 1 replayed through: started from its row (fade, the player at its start), no saving
##   meanwhile, passed with no cash, stats, story progress or autosave, then the player back where
##   they were with their health and the time of day;
## - mission 15 replayed to its ending choice and the other answer picked, then ended from the
##   pause menu: the saved story keeps the first answer;
## - a replay failed and given up from the failure screen: back where they were, no failure in the
##   stats.
## Saves go to a scratch folder (user://test_saves), never the player's real saves.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/replay_test.tscn
## Prints "REPLAY TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const TEST_SAVES: String = "user://test_saves"
const STORY: Array[StringName] = [&"welcome", &"first_opportunity", &"new_connection", &"city_chase", &"building_empire",
	&"thorns", &"night_van", &"inspector", &"ledger", &"old_friends", &"detective", &"fire", &"mansion", &"harbour", &"rise_of_the_don"]

var _catcher: ErrorCatcher
var _game: GameSession
var _director: MissionDirector
var _mhud: MissionHud
var _player: PlayerController
var _pause: PauseMenu
var _replay: MissionReplay
var _panel: MissionsPanel
var _failed_screen: MissionFailedScreen
var _report: PackedStringArray = []
## Where the player stands when choosing a replay (by the temple's east gate, mission 1's first goal: far
## from its start at the bus stand).
var _home := Vector3.ZERO


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	SaveManager.save_dir = TEST_SAVES
	_wipe_saves()
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_director = _game.get_node("Missions") as MissionDirector
	_mhud = (_game.get_node("HUD") as Hud).get_mission_hud()
	_player = _game.get_node("Player") as PlayerController
	_pause = _game.get_node("PauseMenu") as PauseMenu
	_replay = _game.get_node("Replay") as MissionReplay
	_failed_screen = _game.get_node("MissionFailed") as MissionFailedScreen
	var traffic := _game.get_node("Traffic") as TrafficManager
	var people := _game.get_node("Pedestrians") as PedestrianManager
	traffic.enabled = false
	people.enabled = false
	traffic.clear()
	people.clear()
	var steps: Array[Callable] = [_check_list, _check_blocked, _check_replay_passed, _check_replay_choice, _check_replay_failed]
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
	print("REPLAY REPORT")
	for line: String in _report:
		print("  " + line)
	_wipe_saves()
	OS.remove_logger(_catcher)
	get_tree().paused = false
	if failure == "":
		print("REPLAY TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


# --------------------------------------------------------------------------- the list

func _check_list() -> String:
	await _ticks(30)
	MissionManager.quit_mission()             # the opening mission starts by itself on New Game
	var completed: Array[String] = ["job_tiffin"]
	for id: StringName in STORY:
		completed.append(String(id))
	MissionManager.from_save({"completed": completed})
	GameState.set_choice(&"ending", 0)
	_home = MissionManager.get_mission(&"welcome").objectives[0].position + Vector3(1.5, 0.1, 0.0)
	await _teleport(_home)
	await _ticks(10)
	var replayable: Array[StringName] = []
	for mission: MissionData in MissionManager.get_replayable():
		replayable.append(mission.id)
	if replayable != STORY:
		return "replayable missions %s (expected the fifteen story missions in order)" % [replayable]
	await _open_panel()
	if not _panel.visible:
		return "Pause → Missions didn't open the panel"
	for i: int in STORY.size():
		var row: Button = _panel.get_row(STORY[i])
		if row == null or row.disabled:
			return "no enabled row for '%s'" % STORY[i]
		if not row.text.begins_with("%d.  %s" % [i + 1, MissionManager.get_mission(STORY[i]).title]):
			return "row %d reads '%s'" % [i + 1, row.text]
	if _panel.get_row(&"job_tiffin") != null:
		return "a side job is listed"
	if (_panel.find_child("EndReplayButton", true, false) as Button).visible or _panel.get_status_text() != "":
		return "End Replay or a status shows with no replay running ('%s')" % _panel.get_status_text()
	_note("Pause → Missions lists the 15 story missions in order (\"1.  Welcome to Velanagar\"…), no side jobs, all enabled")
	_close_pause()
	return ""


func _check_blocked() -> String:
	var reasons: PackedStringArray = []
	MissionManager.start(&"job_tiffin")
	var reason: String = await _blocked_reason()
	MissionManager.quit_mission()
	if reason != "Finish the mission you're on first.":
		return "with a side job running: '%s'" % reason
	reasons.append(reason)
	WantedSystem.set_level(1, _player.global_position)
	reason = await _blocked_reason()
	WantedSystem.clear()
	(_game.get_node("Police") as PoliceManager).clear_all()
	if reason != "Lose the police first.":
		return "with a star: '%s'" % reason
	reasons.append(reason)
	var car := (load("res://scenes/vehicles/sedan.tscn") as PackedScene).instantiate() as VehicleController
	_game.add_child(car)
	car.global_position = _home + Vector3(4.0, 0.6, 0.0)
	await _ticks(30)
	if not await _get_in(car):
		return "couldn't get into the test car"
	reason = await _blocked_reason()
	_player.exit_vehicle(_home)
	await _ticks(30)
	car.queue_free()
	await _teleport(_home)
	if reason != "Get out of the vehicle first.":
		return "in a car: '%s'" % reason
	reasons.append(reason)
	_note("blocked (rows greyed): %s" % " / ".join(reasons))
	return ""


## Opens the Missions panel; the rows must all be disabled. Returns the reason shown.
func _blocked_reason() -> String:
	await _open_panel()
	var reason: String = _panel.get_status_text()
	for id: StringName in STORY:
		if not _panel.get_row(id).disabled:
			reason = "row '%s' is enabled (status '%s')" % [id, reason]
			break
	_close_pause()
	await _ticks(3)
	return reason


# --------------------------------------------------------------------------- a replay passed

func _check_replay_passed() -> String:
	var mission: MissionData = MissionManager.get_mission(&"welcome")
	_player.stats.set_health(60.0)
	var cash: int = EconomyManager.cash
	var passed_stat: int = GameState.get_stat(&"missions_passed")
	var completed: Array[StringName] = MissionManager.get_completed()
	var yaw: float = _player.camera_rig.get_yaw()
	await _open_panel()
	_panel.get_row(&"welcome").pressed.emit()
	await _ticks(2)
	var hour: float = GameState.hour
	if get_tree().paused or _pause.is_open():
		return "the game should resume when a replay starts"
	if not MissionManager.is_replay() or MissionManager.get_active() != mission:
		return "picking the row didn't start a replay of '%s'" % mission.id
	if _flat(_player.global_position).distance_to(_flat(mission.start_position)) > 1.5:
		return "the player should be at the mission's start (at %s)" % _player.global_position
	var black: ColorRect = _replay.get_node("Fade/Black")
	if black.color.a < 0.5:
		return "the jump to the start should happen behind black (alpha %.2f)" % black.color.a
	if not _mhud.get_banner_shown().contains("Replay."):
		return "the start banner should say it's a replay ('%s')" % _mhud.get_banner_shown()
	if SaveManager.can_save() or SaveManager.save_game(1) == OK or not SaveManager.read_slot(1).is_empty():
		return "saving should wait until the replay ends"
	if String(MissionManager.to_save()["active"]) != "":
		return "a replay shouldn't be saved as the running mission"
	if _director.has_offer(MissionManager.get_mission(&"job_tiffin")):
		return "the side jobs' start markers should go during a replay"
	await _ticks(40)
	if black.color.a > 0.05:
		return "the fade should clear after the start (alpha %.2f)" % black.color.a
	for index: int in mission.objectives.size():
		await _teleport(mission.objectives[index].position + Vector3(0.6, 0.1, 0.0))
		await _ticks(10)
	if MissionManager.is_active():
		return "the replay didn't finish after reaching all three places"
	if not _mhud.get_banner_shown().contains("REPLAY PASSED") or _mhud.get_banner_shown().contains("₹"):
		return "banner '%s' (expected REPLAY PASSED, no reward)" % _mhud.get_banner_shown()
	if EconomyManager.cash != cash:
		return "cash changed: %d -> %d" % [cash, EconomyManager.cash]
	if GameState.get_stat(&"missions_passed") != passed_stat or MissionManager.get_completed() != completed:
		return "the replay counted as progress (passed %d -> %d)" % [passed_stat, GameState.get_stat(&"missions_passed")]
	await _ticks(30)
	if not SaveManager.read_slot(SaveManager.AUTOSAVE_SLOT).is_empty():
		return "a replay shouldn't autosave"
	var waited: float = await _wait_back(20.0)
	if waited < 0.0:
		return "the player wasn't taken back within 20 s"
	var back: String = _check_back(yaw, 60.0, hour)
	if back != "":
		return back
	if not _director.has_offer(MissionManager.get_mission(&"job_tiffin")):
		return "the side jobs should be on offer again"
	if not _mhud.get_hint_shown().contains("Back where you were"):
		return "no 'Back where you were.' hint ('%s')" % _mhud.get_hint_shown()
	_note("mission 1 replayed from its row: behind a fade at the bus stand, 'Replay.' banner, no saving; passed with no cash, stats or autosave; back by the gate %.1f s later with 60 health and the clock as it was" % waited)
	return ""


# --------------------------------------------------------------------------- the ending

func _check_replay_choice() -> String:
	var last: MissionData = MissionManager.get_mission(&"rise_of_the_don")
	await _open_panel()
	_panel.get_row(&"rise_of_the_don").pressed.emit()
	await _ticks(5)
	if MissionManager.get_active() != last:
		return "the row didn't replay the last mission"
	for i: int in last.objectives.size():
		var objective: MissionObjective = MissionManager.get_objective()
		if objective != null and objective.type == MissionObjective.Type.CHOICE:
			break
		MissionManager.complete_objective()
		await _ticks(5)
	var choice: MissionObjective = MissionManager.get_objective()
	if choice == null or choice.type != MissionObjective.Type.CHOICE:
		return "never reached the ending choice"
	_director.answer_choice(1)
	await _ticks(5)
	if GameState.get_choice(&"ending") != 1:
		return "in the replay the other answer should count (ending %d)" % GameState.get_choice(&"ending")
	var other: MissionObjective = MissionManager.get_objective()
	if other == null or other.if_answer != 1:
		return "the replay should go on down the other ending's branch"
	await _open_panel()
	var end_button := _panel.find_child("EndReplayButton", true, false) as Button
	if not end_button.visible or not end_button.text.contains(last.title):
		return "End Replay should show during a replay ('%s')" % end_button.text
	if not _panel.get_row(&"welcome").disabled or not _panel.get_status_text().is_empty():
		return "during a replay the rows should be greyed behind End Replay"
	end_button.pressed.emit()
	await _ticks(5)
	if MissionManager.is_active():
		return "End Replay didn't end it"
	if GameState.get_choice(&"ending") != 0:
		return "the saved story should keep the first answer (ending %d)" % GameState.get_choice(&"ending")
	if await _wait_back(10.0) < 0.0:
		return "End Replay didn't take the player back"
	var back: String = _check_back(-INF, -1.0, -1.0)
	if back != "":
		return back
	_note("mission 15 replayed to the ending choice; the other answer runs the other ending; End Replay: the story keeps the first answer, player back")
	return ""


# --------------------------------------------------------------------------- failed and quit

func _check_replay_failed() -> String:
	var failed_stat: int = GameState.get_stat(&"missions_failed")
	await _open_panel()
	_panel.get_row(&"city_chase").pressed.emit()
	await _ticks(10)
	MissionManager.fail("Test failure.")
	for i: int in 180:
		if _failed_screen.is_open():
			break
		await get_tree().process_frame
	if not _failed_screen.is_open():
		return "no failure screen"
	(_failed_screen.find_child("QuitMissionButton", true, false) as Button).pressed.emit()
	if await _wait_back(10.0) < 0.0:
		return "quitting the failed replay didn't take the player back"
	var back: String = _check_back(-INF, -1.0, -1.0)
	if back != "":
		return back
	if GameState.get_stat(&"missions_failed") != failed_stat:
		return "a failed replay counted in the stats"
	_note("a replay failed and quit from the failure screen: back where they were, no failure counted")
	return ""


# --------------------------------------------------------------------------- helpers

## Waits until the replay has put the player back; seconds of game time waited, or -1.
func _wait_back(max_seconds: float) -> float:
	var ticks: int = 0
	while ticks < int(max_seconds * 60.0):
		if _replay.get_mission() == null:
			await _ticks(40)          # the fade back in
			return ticks / 60.0
		await _ticks(1)
		ticks += 1
	return -1.0


## The player back at _home (facing `yaw`, with `health`, the clock near `hour`; negative: skip).
func _check_back(yaw: float, health: float, hour: float) -> String:
	if _flat(_player.global_position).distance_to(_flat(_home)) > 1.0:
		return "the player should be back at %s (at %s)" % [_home, _player.global_position]
	if _player.is_in_vehicle() or MissionManager.is_active():
		return "back, the player should be on foot with no mission running"
	if yaw > -INF and absf(angle_difference(_player.camera_rig.get_yaw(), yaw)) > 0.05:
		return "the camera should face as it did (yaw %.2f, was %.2f)" % [_player.camera_rig.get_yaw(), yaw]
	if health >= 0.0 and absf(_player.stats.health - health) > 0.01:
		return "health %.1f (was %.1f)" % [_player.stats.health, health]
	if hour >= 0.0 and absf(GameState.hour - hour) > 0.05:
		return "the clock reads %.2f h (was %.2f h)" % [GameState.hour, hour]
	if (_replay.get_node("Fade/Black") as ColorRect).color.a > 0.05 or WantedSystem.level != 0:
		return "the fade or the police are still there"
	return ""


func _open_panel() -> void:
	_pause.open()
	await get_tree().process_frame
	(_pause.find_child("MissionsButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	_panel = _pause.find_child("MissionsPanel", true, false) as MissionsPanel


func _close_pause() -> void:
	if _pause.is_open():
		_pause.resume()


func _get_in(car: VehicleController) -> bool:
	await _teleport(car.get_exit_points()[0] + Vector3.UP * 0.1)
	await _ticks(10)
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			return true
	return false


func _teleport(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(3)


func _wipe_saves() -> void:
	for slot: int in SaveManager.ALL_SLOTS:
		SaveManager.delete_slot(slot)


func _tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
