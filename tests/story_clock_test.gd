extends Node
## Story clock test (after 1.0): missions and cutscenes that name a time of day.
## - The window maths: inside a window (also past midnight) nothing moves; outside, the clock
##   skips forward to the window's start, never back.
## - The Night Van started at noon: the clock skips to 18:30 behind a fade, with "Time passes."
##   Started at 20:30 (inside its window): the clock stays. Retried from its checkpoint: it stays.
## - A mission with no window (The Ledger) leaves the clock alone.
## - Harbour Lights at noon: night at once (the lighting refreshed) and rain.
## - The lighthouse cutscene at noon skips to 19:30. The Honest Road ending at 22:00 skips to
##   06:00 the next day: a new day, the house's rent paid, clear skies.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/story_clock_test.tscn
## Prints "STORY CLOCK TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const TEST_SAVES: String = "user://test_saves"
const BEFORE_NIGHT_VAN: Array[String] = ["welcome", "first_opportunity", "new_connection", "city_chase", "building_empire", "thorns"]

var _catcher: ErrorCatcher
var _game: GameSession
var _director: MissionDirector
var _mhud: MissionHud
var _clock: StoryClock
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	SaveManager.save_dir = TEST_SAVES
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_director = _game.get_node("Missions") as MissionDirector
	_mhud = (_game.get_node("HUD") as Hud).get_mission_hud()
	_clock = _game.get_node("StoryClock") as StoryClock
	for manager: Node in [_game.get_node("Traffic"), _game.get_node("Pedestrians")]:
		manager.set(&"enabled", false)
		manager.call(&"clear")
	var steps: Array[Callable] = [_check_maths, _check_mission_skip, _check_inside_and_retry, _check_no_window,
		_check_night_and_rain, _check_cutscenes]
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
	print("STORY CLOCK REPORT")
	for line: String in _report:
		print("  " + line)
	for slot: int in SaveManager.ALL_SLOTS:
		SaveManager.delete_slot(slot)
	OS.remove_logger(_catcher)
	if failure == "":
		print("STORY CLOCK TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_maths() -> String:
	await _ticks(30)
	MissionManager.quit_mission()             # the opening mission starts by itself on New Game
	# [clock, from, to, expected hours]
	var cases: Array = [[12.0, 20.0, 4.5, 8.0], [12.0, 8.0, 12.0, 0.0], [12.0, 6.0, 8.5, 18.0], [22.0, 20.0, 4.5, 0.0],
		[3.0, 19.5, 4.5, 0.0], [5.0, 20.0, 4.5, 15.0], [22.0, 6.0, 8.0, 8.0], [7.0, 7.5, 13.0, 0.5], [9.0, -1.0, -1.0, 0.0]]
	for c: Array in cases:
		GameState.set_hour(float(c[0]))
		var got: float = GameState.hours_until(float(c[1]), float(c[2]))
		if absf(got - float(c[3])) > 0.001:
			return "at %.1f h, window %.1f-%.1f: %.2f hours to skip (expected %.2f)" % [c[0], c[1], c[2], got, c[3]]
	_note("window maths: %d cases (inside, past midnight, the next day, no window)" % cases.size())
	return ""


func _check_mission_skip() -> String:
	MissionManager.from_save({"completed": BEFORE_NIGHT_VAN})
	await _ticks(5)
	_set_clock(12.0)
	var day: int = GameState.day
	if not MissionManager.start(&"night_van"):
		return "couldn't start The Night Van"
	await get_tree().process_frame
	if absf(GameState.hour - 18.5) > 0.02 or GameState.day != day:
		return "the clock should skip to 18:30 the same day (at %s, day %d -> %d)" % [GameState.get_clock_text(), day, GameState.day]
	var fade := _clock.get_node("Fade") as ScreenFade
	if fade.get_alpha() < 0.5:
		return "the skip should happen behind black (alpha %.2f)" % fade.get_alpha()
	if not _mhud.get_hint_shown().contains("Time passes. It's 18:30."):
		return "no 'Time passes' line ('%s')" % _mhud.get_hint_shown()
	await _ticks(70)
	if fade.get_alpha() > 0.05:
		return "the fade should clear (alpha %.2f)" % fade.get_alpha()
	MissionManager.quit_mission()
	_note("The Night Van started at 12:00: the clock skips to 18:30 behind a fade, 'Time passes. It's 18:30.'")
	return ""


func _check_inside_and_retry() -> String:
	_set_clock(20.5)
	MissionManager.start(&"night_van")
	await _ticks(2)
	if absf(GameState.hour - 20.5) > 0.05 or (_clock.get_node("Fade") as ScreenFade).get_alpha() > 0.05:
		return "inside its window the clock shouldn't move (at %s)" % GameState.get_clock_text()
	MissionManager.quit_mission()
	var mission: MissionData = MissionManager.get_mission(&"night_van")
	var checkpoint: int = -1
	for i: int in mission.objectives.size():
		if mission.objectives[i].checkpoint:
			checkpoint = i
			break
	_set_clock(12.0)
	MissionManager.start(&"night_van", checkpoint)
	await _ticks(2)
	var at_checkpoint: String = GameState.get_clock_text()
	MissionManager.quit_mission()
	if checkpoint < 0 or absf(GameState.hour - 12.0) > 0.05:
		return "carrying on from checkpoint %d shouldn't move the clock (at %s)" % [checkpoint, at_checkpoint]
	_note("started at 20:30, inside its window: the clock stays; from its checkpoint (objective %d) at 12:00: it stays" % checkpoint)
	return ""


func _check_no_window() -> String:
	var done: Array[String] = BEFORE_NIGHT_VAN.duplicate()
	done.append_array(["night_van", "inspector"])
	MissionManager.from_save({"completed": done})
	await _ticks(5)
	_set_clock(12.0)
	if not MissionManager.start(&"ledger"):
		return "couldn't start The Ledger"
	await _ticks(2)
	MissionManager.quit_mission()
	if absf(GameState.hour - 12.0) > 0.05:
		return "a mission with no window moved the clock (to %s)" % GameState.get_clock_text()
	_note("The Ledger (no window) at 12:00: the clock stays")
	return ""


func _check_night_and_rain() -> String:
	var done: Array[String] = []
	for mission: MissionData in MissionManager.story.missions:
		if mission.id == &"harbour":
			break
		done.append(String(mission.id))
	MissionManager.from_save({"completed": done})
	await _ticks(5)
	_set_clock(12.0)
	var day_night := _game.get_node("DayNight") as DayNightCycle
	var weather := _game.get_node("Weather") as WeatherCycle
	if day_night.is_dark():
		return "noon shouldn't be dark"
	if not MissionManager.start(&"harbour"):
		return "couldn't start Harbour Lights"
	await get_tree().process_frame
	var dark: bool = day_night.is_dark()
	var rain: float = weather.get_rain()
	MissionManager.quit_mission()
	if absf(GameState.hour - 20.0) > 0.05 or not dark:
		return "Harbour Lights should start at night (at %s, dark %s)" % [GameState.get_clock_text(), dark]
	if GameState.weather != &"rain" or weather.get_weather() != &"rain" or rain < 0.5:
		return "Harbour Lights should start in rain (weather %s, rain %.2f)" % [GameState.weather, rain]
	_note("Harbour Lights at 12:00: 20:00, the city dark at once, raining (%.2f)" % rain)
	return ""


func _check_cutscenes() -> String:
	var player := _game.get_node("Player") as PlayerController
	var cutscenes: CutscenePlayer = _director.get_cutscene()
	var lighthouse: CutsceneData = _cutscene(&"detective", &"c11_lighthouse")
	_set_clock(12.0)
	cutscenes.play(lighthouse, player)
	await get_tree().process_frame
	var at: String = GameState.get_clock_text()
	cutscenes.stop()
	await _ticks(5)
	if at != "19:30":
		return "the lighthouse cutscene at 12:00 should skip to 19:30 (at %s)" % at
	EconomyManager.add(10000, &"test")
	if not EconomyManager.buy(&"verandah_house", 6000, &"property"):
		return "couldn't buy the house for the rent check"
	_set_clock(22.0)
	var day: int = GameState.day
	var cash: int = EconomyManager.cash
	cutscenes.play(_cutscene(&"rise_of_the_don", &"c15_honest"), player)
	await get_tree().process_frame
	at = GameState.get_clock_text()
	var weather_now: StringName = GameState.weather
	cutscenes.stop()
	await _ticks(5)
	if at != "06:00" or GameState.day != day + 1:
		return "The Honest Road at 22:00 should skip to 06:00 the next day (at %s, day %d -> %d)" % [at, day, GameState.day]
	if EconomyManager.cash != cash + 400:
		return "the new day should pay the house's ₹400 rent (cash %d -> %d)" % [cash, EconomyManager.cash]
	if weather_now != &"clear":
		return "the ending should have clear skies (weather %s)" % weather_now
	_note("the lighthouse cutscene at 12:00: 19:30; The Honest Road at 22:00: 06:00 next day, rent +₹400, clear skies")
	return ""


func _cutscene(mission_id: StringName, cutscene_id: StringName) -> CutsceneData:
	for objective: MissionObjective in MissionManager.get_mission(mission_id).objectives:
		if objective.cutscene != null and objective.cutscene.id == cutscene_id:
			return objective.cutscene
	return null


func _set_clock(hour: float) -> void:
	GameState.set_hour(hour)
	(_game.get_node("DayNight") as DayNightCycle).refresh()


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
