extends Node
## Mission test (per-feature test scene, M5). Starts a new game in the real game scene and plays
## the opening missions through, moving the player (and the borrowed car) by teleport but
## talking, getting in and out with real key presses:
## - Mission 1 "Welcome to Velanagar": starts by itself at the bus stand, three places to reach,
##   passed banner, ₹300 reward, autosave, the fixer's mission then on offer.
## - Mission 2 "First Opportunity": started by walking into its marker; talk to the fixer (parcel
##   handed over), deliver to the tailor, the car is wrecked (failure screen, retry from the
##   checkpoint), the clock runs out (failure, quit the mission), started again, driven to the
##   market, parcel handed over, ₹1,000 reward.
## Saves go to a scratch folder (user://test_saves), never the player's real saves.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/mission_test.tscn
## Prints "MISSION TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const TEST_SAVES: String = "user://test_saves"

var _catcher: ErrorCatcher
var _game: GameSession
var _director: MissionDirector
var _hud: Hud
var _mhud: MissionHud
var _player: PlayerController
var _failed_screen: MissionFailedScreen
var _report: PackedStringArray = []


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
	_hud = _game.get_node("HUD") as Hud
	_mhud = _hud.get_mission_hud()
	_player = _game.get_node("Player") as PlayerController
	_failed_screen = _game.get_node("MissionFailed") as MissionFailedScreen
	var traffic := _game.get_node("Traffic") as TrafficManager
	var people := _game.get_node("Pedestrians") as PedestrianManager
	traffic.enabled = false     # keep the streets empty so nothing wanders into the test
	people.enabled = false
	traffic.clear()
	people.clear()
	var steps: Array[Callable] = [
		_check_new_game, _check_mission_one, _check_offer, _check_talk_to_fixer, _check_delivery_on_foot,
		_check_wreck_and_retry, _check_time_out_and_quit, _check_restart_and_finish, _check_side_jobs,
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
	for code: Key in [KEY_E, KEY_F, KEY_W]:
		_key(code, false)
	print("MISSION REPORT")
	for line: String in _report:
		print("  " + line)
	_wipe_saves()
	OS.remove_logger(_catcher)
	get_tree().paused = false
	if failure == "":
		print("MISSION TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


# --------------------------------------------------------------------------- mission 1

func _check_new_game() -> String:
	await _ticks(30)
	var active: MissionData = MissionManager.get_active()
	if active == null or active.id != &"welcome":
		return "New Game should start 'welcome' by itself (active: %s)" % [active.id if active else "none"]
	if EconomyManager.cash != MissionManager.story.starting_cash or _hud.get_cash_shown() != EconomyManager.format(EconomyManager.cash):
		return "starting cash: %d, HUD shows '%s'" % [EconomyManager.cash, _hud.get_cash_shown()]
	if _mhud.get_objective_shown() != "Walk to the temple's east gate." or _mhud.get_title_shown() != "WELCOME TO VELANAGAR":
		return "HUD shows '%s' / '%s'" % [_mhud.get_title_shown(), _mhud.get_objective_shown()]
	if not _mhud.get_subtitle_shown().begins_with("CONDUCTOR"):
		return "the arrival line isn't shown (subtitle '%s')" % _mhud.get_subtitle_shown()
	if not _mhud.get_hint_shown().contains("W A S D"):
		return "the first hint should name the movement keys (got '%s')" % _mhud.get_hint_shown()
	if _mhud.waypoint.target == null or _mhud.waypoint.target.global_position.distance_to(active.objectives[0].position) > 0.5:
		return "the waypoint doesn't point at the first goal"
	var spawn: Vector3 = (_game.get_node("World") as District).get_spawn_transform().origin
	if _player.global_position.distance_to(spawn) > 1.0 or spawn.distance_to(active.start_position) > 1.0:
		return "the player should start at the bus stand (%s; mission start %s)" % [_player.global_position, active.start_position]
	if _director.has_offer(MissionManager.get_mission(&"first_opportunity")):
		return "mission 2 is on offer before mission 1 is passed"
	_note("New Game: '%s' started at the bus stand with %s, objective, hint, arrival line and waypoint on the HUD" % [active.title, _hud.get_cash_shown()])
	return ""


func _check_mission_one() -> String:
	var mission: MissionData = MissionManager.get_active()
	var texts: PackedStringArray = []
	for index: int in mission.objectives.size():
		if MissionManager.get_objective_index() != index:
			return "expected objective %d, at %d" % [index, MissionManager.get_objective_index()]
		texts.append(_mhud.get_objective_shown())
		await _teleport(mission.objectives[index].position + Vector3(0.6, 0.1, 0.0))
		await _ticks(10)
	if MissionManager.is_active():
		return "the mission didn't finish after reaching all three places"
	if not MissionManager.is_completed(&"welcome"):
		return "'welcome' isn't marked as passed"
	if not _mhud.get_banner_shown().contains("MISSION PASSED") or not _mhud.get_banner_shown().contains("₹300"):
		return "no passed banner with the reward (got '%s')" % _mhud.get_banner_shown()
	if EconomyManager.cash != 500:
		return "cash should be ₹500 after the ₹300 reward, it is %d" % EconomyManager.cash
	await _ticks(90)
	if _hud.get_cash_shown() != "₹500":
		return "the HUD cash should count up to ₹500 (shows '%s')" % _hud.get_cash_shown()
	var autosave: Dictionary = SaveManager.read_slot(SaveManager.AUTOSAVE_SLOT)
	if autosave.is_empty() or not (autosave["state"]["missions"]["completed"] as Array).has("welcome"):
		return "no autosave with 'welcome' passed"
	if not _mhud.get_subtitle_shown().begins_with("FIXER"):
		return "the fixer should call out after the mission (subtitle '%s')" % _mhud.get_subtitle_shown()
	_note("mission 1: %s -> passed, +₹300 (₹500), autosaved, the fixer calls out" % " / ".join(texts))
	return ""


func _check_offer() -> String:
	var second: MissionData = MissionManager.get_mission(&"first_opportunity")
	if not _director.has_offer(second):
		return "mission 2 isn't on offer after mission 1"
	var giver: MissionContactNPC = _director.get_offer_giver(second)
	if giver == null or giver.global_position.distance_to(second.giver.position) > 0.5:
		return "the fixer isn't standing by the start marker"
	await _teleport(second.start_position + Vector3(-5.0, 0.1, 0.0))
	await _ticks(10)
	if MissionManager.is_active():
		return "the mission started from 5 m away"
	await _teleport(second.start_position + Vector3(0.3, 0.1, 0.0))
	await _ticks(5)
	if MissionManager.get_active() != second:
		return "walking into the start marker didn't start mission 2"
	var car: VehicleController = _director.get_vehicle(&"tailor_car")
	if car == null or car.global_position.distance_to(second.vehicles[0].position) > 1.5:
		return "the tailor's car isn't parked at its spot"
	for id: StringName in [&"fixer", &"tailor", &"buyer"]:
		if _director.get_contact(id) == null:
			return "contact '%s' is missing" % id
	_note("mission 2 on offer with the fixer by the magenta marker; walking in starts it; the tailor's car and the three contacts are in place")
	return ""


func _check_talk_to_fixer() -> String:
	var fixer: MissionContactNPC = _director.get_contact(&"fixer")
	if _hud.get_prompt_text() != "":
		await _teleport(fixer.global_position + Vector3(-6.0, 0.1, 0.0))
	if _hud.get_prompt_text().contains("TALK"):
		return "the talk prompt shows from 6 m away"
	await _teleport(fixer.global_position + Vector3(-1.6, 0.1, 0.0))
	await _ticks(5)
	if not _hud.get_prompt_text().ends_with("TALK TO FIXER"):
		return "no talk prompt next to the fixer (prompt '%s')" % _hud.get_prompt_text()
	var lines: int = await _talk()
	if MissionManager.get_objective_index() != 1:
		return "after talking the objective should move on (at %d)" % MissionManager.get_objective_index()
	if not _director.get_items().has(&"parcel") or _player.model.get_node_or_null("CarriedItem") == null:
		return "the fixer didn't hand over the parcel"
	_note("talking to the fixer: prompt 'E  TALK TO FIXER', %d lines (E skips), parcel handed over and carried" % lines)
	return ""


func _check_delivery_on_foot() -> String:
	var tailor: MissionContactNPC = _director.get_contact(&"tailor")
	await _teleport(tailor.global_position + Vector3(0.0, 0.1, 1.6))
	await _ticks(5)
	if not _hud.get_prompt_text().ends_with("GIVE TAILOR THE PARCEL"):
		return "no hand-over prompt by the tailor (prompt '%s')" % _hud.get_prompt_text()
	await _talk()
	if MissionManager.get_objective_index() != 2 or MissionManager.get_checkpoint() != 2:
		return "after the delivery: objective %d, checkpoint %d (expected 2 and 2)" % [MissionManager.get_objective_index(), MissionManager.get_checkpoint()]
	if _mhud.get_objective_shown() != "Get in the tailor's car.":
		return "objective shows '%s'" % _mhud.get_objective_shown()
	_note("delivered to the tailor on foot (he hands over a new parcel); checkpoint reached at 'Get in the tailor's car.'")
	return ""


# --------------------------------------------------------------------------- failure

func _check_wreck_and_retry() -> String:
	var car: VehicleController = _director.get_vehicle(&"tailor_car")
	(car.get_node("Damage") as VehicleDamage).apply_damage(100000.0)
	await _ticks(2)
	if not MissionManager.is_failed():
		return "wrecking the tailor's car didn't fail the mission"
	await _wait_for_failed_screen()
	if not _failed_screen.is_open() or not get_tree().paused:
		return "the failure screen didn't come up (paused %s)" % get_tree().paused
	if _failed_screen.get_reason_shown() != "The tailor's car is wrecked.":
		return "failure reason '%s'" % _failed_screen.get_reason_shown()
	(_failed_screen.find_child("RetryButton", true, false) as Button).pressed.emit()
	await _ticks(5)
	var fresh: VehicleController = _director.get_vehicle(&"tailor_car")
	if get_tree().paused or MissionManager.is_failed() or MissionManager.get_objective_index() != 2:
		return "Retry should resume at the checkpoint (objective %d, paused %s)" % [MissionManager.get_objective_index(), get_tree().paused]
	if fresh == null or fresh == car or (fresh.get_node("Damage") as VehicleDamage).is_wrecked():
		return "Retry didn't bring a fresh car"
	var spot: Vector3 = MissionManager.get_active().objectives[2].checkpoint_position
	if _flat(_player.global_position).distance_to(_flat(spot)) > 0.6:
		return "Retry should put the player at the checkpoint %s (at %s)" % [spot, _player.global_position]
	if not _director.get_items().has(&"parcel"):
		return "the player should still carry the parcel after the retry"
	_note("wrecking the car fails the mission: 'MISSION FAILED - The tailor's car is wrecked.' (game paused); Retry: back at the checkpoint with a fresh car and the parcel")
	return ""


func _check_time_out_and_quit() -> String:
	var mission: MissionData = MissionManager.get_active()
	var drive: MissionObjective = mission.objectives[3]
	var real_limit: float = drive.time_limit
	drive.time_limit = 3.0      # this run only: no need to wait two minutes
	var got_in: bool = await _get_in(_director.get_vehicle(&"tailor_car"))
	if not got_in or MissionManager.get_objective_index() != 3:
		drive.time_limit = real_limit
		return "couldn't get into the tailor's car (objective %d)" % MissionManager.get_objective_index()
	var shown: String = _mhud.get_timer_shown()
	await _ticks(60 * 3 + 20)
	drive.time_limit = real_limit
	if not MissionManager.is_failed():
		return "the mission didn't fail when the clock ran out"
	await _wait_for_failed_screen()
	if _failed_screen.get_reason_shown() != "You ran out of time.":
		return "failure reason '%s'" % _failed_screen.get_reason_shown()
	(_failed_screen.find_child("QuitMissionButton", true, false) as Button).pressed.emit()
	await _ticks(5)
	if MissionManager.is_active() or get_tree().paused:
		return "Quit Mission should end the mission and unpause"
	if _player.is_in_vehicle() or _director.get_vehicle(&"tailor_car") != null:
		return "quitting should take the borrowed car back (player in a car: %s)" % _player.is_in_vehicle()
	if not _director.has_offer(mission):
		return "after quitting, the mission should be on offer again"
	if EconomyManager.cash != 500:
		return "cash changed on failure (%d)" % EconomyManager.cash
	_note("getting in starts a %s clock; running out fails it ('You ran out of time.'); Quit Mission puts it back on offer, car returned" % shown)
	return ""


# --------------------------------------------------------------------------- the full run

func _check_restart_and_finish() -> String:
	var mission: MissionData = MissionManager.get_mission(&"first_opportunity")
	await _ticks(60)     # quitting put the player out of the car: let them finish stepping out
	await _teleport(mission.start_position + Vector3(0.3, 0.1, 0.0))
	await _ticks(5)
	if MissionManager.get_active() != mission or MissionManager.get_objective_index() != 0:
		return "walking back into the marker should restart the mission from the top"
	await _teleport(_director.get_contact(&"fixer").global_position + Vector3(-1.6, 0.1, 0.0))
	await _talk()
	if MissionManager.get_objective_index() != 1:
		return "second run: talking to the fixer didn't move on (objective %d, prompt '%s')" % [MissionManager.get_objective_index(), _hud.get_prompt_text()]
	await _teleport(_director.get_contact(&"tailor").global_position + Vector3(0.0, 0.1, 1.6))
	await _ticks(5)
	var prompt: String = _hud.get_prompt_text()
	await _talk()
	if MissionManager.get_objective_index() != 2:
		return "second run: the delivery to the tailor didn't move on (objective %d, prompt was '%s', player %s, state %s, tailor %s)" % [
			MissionManager.get_objective_index(), prompt, _player.global_position, _player.get_state_name(), _director.get_contact(&"tailor").global_position]
	var car: VehicleController = _director.get_vehicle(&"tailor_car")
	if not await _get_in(car) or MissionManager.get_objective_index() != 3:
		return "couldn't get into the car on the second run (objective %d)" % MissionManager.get_objective_index()
	var timer_text: String = _mhud.get_timer_shown()
	if timer_text != "2:00" and timer_text != "1:59":
		return "the clock should start at 2:00 (shows '%s')" % timer_text
	# Drive: put the car (with the player in it) in the market marker, stopped.
	var goal: Vector3 = mission.objectives[3].position
	var world := _game.get_node("World") as District
	world.streamer.load_around_now(goal)
	car.teleport(Transform3D(Basis(Vector3.UP, -PI * 0.5), goal + Vector3(1.0, 0.6, 0.0)))
	await _ticks(10)
	if MissionManager.get_objective_index() != 4:
		return "stopping in the market marker should complete the drive (objective %d, '%s')" % [MissionManager.get_objective_index(), _mhud.get_objective_shown()]
	if _mhud.get_timer_shown() != "":
		return "the clock should go once the car is delivered"
	_tap(KEY_F)
	for i: int in 60:
		await get_tree().physics_frame
		if not _player.is_in_vehicle():
			break
	await _ticks(30)
	if _player.is_in_vehicle():
		return "couldn't get out of the car"
	await _teleport(_director.get_contact(&"buyer").global_position + Vector3(0.0, 0.1, 1.6))
	await _ticks(5)
	if not _hud.get_prompt_text().ends_with("GIVE BUYER THE PARCEL"):
		return "no hand-over prompt by the buyer (prompt '%s')" % _hud.get_prompt_text()
	await _talk()
	if MissionManager.is_active() or not MissionManager.is_completed(&"first_opportunity"):
		return "handing the parcel to the buyer should pass the mission"
	if EconomyManager.cash != 1500 or GameState.get_stat(&"missions_passed") != 2 or GameState.get_stat(&"missions_failed") != 2:
		return "after both missions: cash %d (expected 1500), passed %d (2), failed %d (2)" % [
			EconomyManager.cash, GameState.get_stat(&"missions_passed"), GameState.get_stat(&"missions_failed")]
	if _director.get_items().size() > 0 or _player.model.get_node_or_null("CarriedItem") != null:
		return "the parcel is still carried after the hand-over"
	if not is_instance_valid(car) or car.is_queued_for_deletion():
		return "the borrowed car should stay where it was left"
	await _ticks(5)
	var autosave: Dictionary = SaveManager.read_slot(SaveManager.AUTOSAVE_SLOT)
	if int(autosave["state"]["economy"]["cash"]) != 1500:
		return "the autosave after mission 2 has cash %s" % autosave["state"]["economy"]["cash"]
	var offered: Array[StringName] = []
	for available: MissionData in MissionManager.get_available():
		offered.append(available.id)
	if offered != [&"job_tiffin", &"job_garage"] or _director.get_offer_giver(mission) != null:
		return "after the two missions only the side jobs should be on offer (got %s)" % [offered]
	_note("second run from the top: talk, deliver, get in (clock %s), stop in the market marker, get out, hand over -> passed, +₹1,000 (₹1,500), autosaved; stats: 2 passed, 2 failed; the two side jobs now on offer" % timer_text)
	return ""


# --------------------------------------------------------------------------- helpers

## Talks through the current conversation with E (skipping each line). Returns the line count.
## Side jobs (M6): Tiffin Delivery twice (repeatable, the customer one of its addresses), then a
## Garage Run by car; each pays and stays on offer.
func _check_side_jobs() -> String:
	var tiffin: MissionData = MissionManager.get_mission(&"job_tiffin")
	var garage: MissionData = MissionManager.get_mission(&"job_garage")
	var world := _game.get_node("World") as District
	var cash: int = EconomyManager.cash
	var addresses: Array[String] = []
	for run: int in 2:
		world.streamer.load_around_now(tiffin.start_position)
		await _teleport(tiffin.start_position + Vector3(0.3, 0.1, 0.0))
		await _ticks(5)
		if MissionManager.get_active() != tiffin:
			return "run %d: walking into Selvi's marker should start Tiffin Delivery" % (run + 1)
		await _teleport(_director.get_contact(&"selvi").global_position + Vector3(0.0, 0.1, 1.6))
		await _talk()
		if MissionManager.get_objective_index() != 1 or not _director.get_items().has(&"tiffin"):
			return "run %d: talking to Selvi should hand over the tiffin carrier (objective %d)" % [run + 1, MissionManager.get_objective_index()]
		var goal: Vector3 = _director.get_goal_position()
		if not tiffin.objectives[1].alternatives.has(goal):
			return "run %d: the customer should be one of the job's addresses (got %s)" % [run + 1, goal]
		addresses.append("(%.0f, %.0f)" % [goal.x, goal.z])
		world.streamer.load_around_now(goal)
		await _teleport(goal + Vector3(0.0, 0.1, 0.0))
		await _ticks(10)
		if MissionManager.is_active() or EconomyManager.cash != cash + 250 * (run + 1):
			return "run %d: reaching the customer should pass the job for ₹250 (active %s, cash %d)" % [run + 1, MissionManager.is_active(), EconomyManager.cash]
		await _ticks(30)
		if not MissionManager.get_available().has(tiffin):
			return "Tiffin Delivery should be offered again after it's passed"
	cash = EconomyManager.cash
	world.streamer.load_around_now(garage.start_position)
	await _teleport(garage.start_position + Vector3(0.3, 0.1, 0.0))
	await _ticks(5)
	if MissionManager.get_active() != garage:
		return "walking into Murugan's marker should start Garage Run"
	await _teleport(_director.get_contact(&"murugan").global_position + Vector3(0.0, 0.1, 1.6))
	await _talk()
	var car: VehicleController = _director.get_vehicle(&"customer_car")
	if MissionManager.get_objective_index() != 1 or car == null:
		return "talking to Murugan should point you at the customer's car"
	if not await _get_in(car) or MissionManager.get_objective_index() != 2:
		return "couldn't get into the customer's car (objective %d)" % MissionManager.get_objective_index()
	var drop: Vector3 = _director.get_goal_position()
	if not garage.objectives[2].alternatives.has(drop):
		return "the owner should be one of the job's addresses (got %s)" % drop
	world.streamer.load_around_now(drop)
	car.teleport(Transform3D(car.global_basis, drop + Vector3(0.0, 0.6, 0.0)))
	await _ticks(15)
	if MissionManager.is_active() or EconomyManager.cash != cash + 600:
		return "stopping at the owner's should pass Garage Run for ₹600 (active %s, cash %d, objective '%s')" % [MissionManager.is_active(), EconomyManager.cash, _mhud.get_objective_shown()]
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if not _player.is_in_vehicle():
			break
	await _ticks(30)
	_note("side jobs: Tiffin Delivery twice (Selvi hands over the carrier; customers at %s; ₹250 each, offered again), Garage Run by car to (%.0f, %.0f) for ₹600" % [", ".join(addresses), drop.x, drop.z])
	return ""


func _talk() -> int:
	_tap(KEY_E)
	await _ticks(3)
	var lines: int = 0
	while _director.dialogue.is_playing() and lines < 12:
		lines += 1
		_tap(KEY_E)
		await _ticks(3)
	return lines


## Walks up to the driver's door and presses F; true once the player is in.
func _get_in(car: VehicleController) -> bool:
	if car == null:
		return false
	await _teleport(car.get_exit_points()[0] + Vector3.UP * 0.1)
	await _ticks(10)
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			return true
	return false


func _wait_for_failed_screen() -> void:
	for i: int in 180:
		if _failed_screen.is_open():
			return
		await get_tree().process_frame


func _teleport(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(3)


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


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
