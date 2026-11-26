extends Node
## Objective test (per-feature test scene, M7 story objectives). Runs the real game scene (traffic
## and pedestrians off) with small missions built here:
## - FIGHT: the fighters appear (enemy blips, "n left"), wait until the player comes close, then
##   come for them; knocking them all out completes it and they stand down;
## - FOLLOW: the car waits for the player, then drives its route (left of the road, round a
##   corner) to its last stop; tailing it at a distance completes it, too close gets you spotted,
##   too far loses it;
## - ESCAPE: the circle on the map, chasers at once, the distance to go; out of it completes it;
## - CHOICE: the choice card holds the game, the answer is kept (and saved), and the mission runs
##   only the objectives of the branch chosen.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/objective_test.tscn
## Prints "OBJECTIVE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const SEDAN: PackedScene = preload("res://scenes/vehicles/sedan.tscn")
## The north sidewalk of the east gopuram road.
const SPOT := Vector3(70.0, 0.15, -8.0)
## The tailed car starts on the eastbound side of the east gopuram road (traffic keeps left),
## facing east (east of the temple's gateway), and turns left, north, at the Ring A junction (x = 112).
## Its stops sit in the kerb lanes (4.5 m off the centre line): left turns go from the left lane.
const VAN_START := Vector3(56.0, 0.0, -4.5)
const ROUTE: PackedVector3Array = [Vector3(96.0, 0.0, -4.5), Vector3(107.5, 0.0, -70.0)]

var _catcher: ErrorCatcher
var _game: GameSession
var _player: PlayerController
var _director: MissionDirector
var _added: Array[MissionData] = []
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	SaveManager.save_dir = "user://test_saves"
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_player = _game.player
	_director = _game.missions
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).clear()
	MissionManager.quit_mission()
	var steps: Array[Callable] = [_check_navmesh, _check_fight, _check_follow, _check_follow_spotted, _check_follow_lost,
		_check_escape, _check_choice]
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
	for mission: MissionData in _added:
		MissionManager.story.missions.erase(mission)
	get_tree().paused = false
	print("OBJECTIVE REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("OBJECTIVE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_navmesh() -> String:
	_game.place_player(Transform3D(Basis.IDENTITY, SPOT))
	var map: RID = _player.get_world_3d().navigation_map
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000 and NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
	while Time.get_ticks_msec() - started < 20000 and _flat(NavigationServer3D.map_get_closest_point(map, SPOT)).distance_to(_flat(SPOT)) > 0.8:
		await get_tree().physics_frame
	return "" if NavigationServer3D.map_get_iteration_id(map) != 0 else "the navmesh never synchronised"


## A mission of `objectives` starting at `start` (added to the story while the test runs).
func _mission(id: StringName, start: Vector3, objectives: Array[MissionObjective], vehicles: Array[MissionVehicle] = []) -> MissionData:
	var mission := MissionData.new()
	mission.id = id
	mission.title = "Objective Test"
	mission.start_position = start
	mission.objectives = objectives
	mission.vehicles = vehicles
	mission.repeatable = true
	MissionManager.story.missions.append(mission)
	_added.append(mission)
	return mission


static func _spec(at: Vector3) -> FighterSpec:
	var spec := FighterSpec.new()
	spec.position = at
	spec.yaw_degrees = 90.0
	return spec


static func _go_to(text: String, at: Vector3) -> MissionObjective:
	var objective := MissionObjective.new()
	objective.type = MissionObjective.Type.GO_TO
	objective.text = text
	objective.position = at
	return objective


func _check_fight() -> String:
	var fight := MissionObjective.new()
	fight.type = MissionObjective.Type.FIGHT
	fight.text = "Deal with them."
	fight.fighters = [_spec(SPOT + Vector3(10.0, 0.0, 0.0)), _spec(SPOT + Vector3(12.0, 0.0, 0.5))]
	fight.aggro_range = 15.0
	var far_spot: Vector3 = SPOT - Vector3(40.0, 0.0, 0.0)
	_mission(&"test_fight", far_spot, [fight, _go_to("Walk on.", SPOT - Vector3(20.0, 0.0, 0.0))])
	if not MissionManager.start(&"test_fight"):
		return "couldn't start the fight mission"
	await _ticks(60)
	var fighters: Array[Fighter] = _director.get_fighters()
	var enemies: int = 0
	for blip: Dictionary in _director.get_map_blips():
		enemies += 1 if blip["kind"] == &"enemy" else 0
	if fighters.size() != 2 or enemies != 2 or not _director.get_objective_text().ends_with("(2 left)"):
		return "two fighters should appear with enemy blips and '(2 left)' (%d fighters, %d blips, '%s')" % [
			fighters.size(), enemies, _director.get_objective_text()]
	if fighters[0].hostile or fighters[0].state != Fighter.State.IDLE:
		return "40 m away they should wait (state %s)" % fighters[0].get_state_name()
	_game.place_player(Transform3D(Basis.IDENTITY, SPOT))
	await _ticks(60)
	if not fighters[0].hostile or not fighters[1].hostile:
		return "within their range they should come for the player"
	fighters[0].take_hit(200.0, _player.global_position, _player)
	await _ticks(5)
	if not _director.get_objective_text().ends_with("(1 left)"):
		return "after knocking one out the objective should say '(1 left)' (got '%s')" % _director.get_objective_text()
	fighters[1].take_hit(200.0, _player.global_position, _player)
	await _ticks(5)
	if MissionManager.get_objective_index() != 1:
		return "knocking them all out should complete the objective"
	if not _director.get_fighters().is_empty() or fighters[1].target != null:
		return "the fighters should stand down once the fight is won"
	MissionManager.quit_mission()
	await _ticks(5)
	_note("FIGHT: two fighters (enemy blips, '2 left'), idle until the player is within 15 m, then coming; knocked out one by one, the objective completes and they stand down")
	return ""


## The tailing missions: get in (on foot is fine for the test), then FOLLOW the sedan.
func _follow_mission(id: StringName) -> MissionData:
	var van := MissionVehicle.new()
	van.id = &"van"
	van.label = "the van"
	van.scene = SEDAN
	van.position = VAN_START
	van.yaw_degrees = -90.0
	van.paint = Color("e8e2d2")
	van.must_survive = false
	var follow := MissionObjective.new()
	follow.type = MissionObjective.Type.FOLLOW
	follow.text = "Follow the van."
	follow.vehicle = &"van"
	follow.checkpoints = ROUTE
	follow.follow_near = 10.0
	follow.follow_far = 70.0
	follow.spotted_seconds = 3.0
	follow.route_speed_kmh = 35.0
	# The player starts out of sight of it, 87 m away on the lane north of the temple's east side.
	return _mission(id, Vector3(48.0, 0.0, -90.0), [follow, _go_to("Done.", SPOT)], [van])


## Keeps the player `gap` metres behind the van (on foot, teleported: the test can't drive) for up
## to `seconds`; stops early once the mission moves on or fails.
func _shadow(gap: float, seconds: float) -> void:
	for f: int in int(seconds * 60.0):
		var van: VehicleController = _director.get_vehicle(&"van")
		if van == null or MissionManager.is_failed() or MissionManager.get_objective_index() != 0:
			return
		if f % 20 == 0:
			var behind: Vector3 = van.global_position - van.global_basis.z * gap
			_player.global_position = Vector3(behind.x, 0.4, behind.z)
			_player.velocity = Vector3.ZERO
		await get_tree().physics_frame


func _check_follow() -> String:
	_follow_mission(&"test_follow")
	if not MissionManager.start(&"test_follow"):
		return "couldn't start the tailing mission"
	await _ticks(30)
	var van: VehicleController = _director.get_vehicle(&"van")
	if van == null or _director.get_follow_driver() != null:
		return "the van should wait for the player to come within sight (driver %s)" % _director.get_follow_driver()
	var started_at: Vector3 = van.global_position
	var lefts: int = 0
	var samples: int = 0
	for f: int in 60 * 90:
		van = _director.get_vehicle(&"van")
		if van == null or MissionManager.is_failed() or MissionManager.get_objective_index() != 0:
			break
		if f % 20 == 0:
			var behind: Vector3 = van.global_position - van.global_basis.z * 30.0
			_player.global_position = Vector3(behind.x, 0.4, behind.z)
			_player.velocity = Vector3.ZERO
			# On the east gopuram road, eastbound traffic keeps to the north half (z < 0).
			if van.global_position.x > 62.0 and van.global_position.x < 100.0:
				samples += 1
				lefts += 1 if van.global_position.z < 0.0 else 0
		await get_tree().physics_frame
	if MissionManager.is_failed():
		return "tailing at 30 m shouldn't fail (%s)" % (_game.get_node("MissionFailed") as MissionFailedScreen).get_reason_shown()
	if MissionManager.get_objective_index() != 1:
		var driver: RouteDriver = _director.get_follow_driver()
		return "the van should reach its last stop within 90 s (next stop %d, at %s, frozen %s, speed %.1f, route %d points, engine %s, player at %s)" % [
			driver.get_next_stop() if driver != null else -1, van.global_position if van != null else Vector3.INF,
			van.freeze, van.get_forward_speed(), driver.get_route().size() if driver != null else -1,
			van.is_engine_running(), _player.global_position]
	if samples == 0 or lefts < samples:
		return "the van should keep to the left on the gopuram road (%d of %d samples)" % [lefts, samples]
	var moved: float = _flat(started_at).distance_to(_flat(_director.get_vehicle(&"van").global_position))
	MissionManager.quit_mission()
	await _ticks(5)
	_note("FOLLOW: the van waits until the player is near, drives its route on the left of the road and round the corner (%.0f m from its start); tailing at 30 m completes the objective" % moved)
	return ""


func _check_follow_spotted() -> String:
	if not MissionManager.start(&"test_follow"):
		return "couldn't start the tailing mission again"
	await _ticks(10)
	await _shadow(5.0, 15.0)
	var reason: String = await _failure_reason()
	if reason != "They spotted you.":
		return "staying 5 m behind should get you spotted (got '%s')" % reason
	_note("FOLLOW: 5 m behind for 3 s: 'They spotted you.'")
	return ""


func _check_follow_lost() -> String:
	if not MissionManager.start(&"test_follow"):
		return "couldn't start the tailing mission a third time"
	await _ticks(10)
	await _shadow(40.0, 4.0)              # it sets off...
	await _shadow(110.0, 10.0)            # ...and the player falls far behind
	var reason: String = await _failure_reason()
	if reason != "You lost them.":
		return "falling 110 m behind should lose them (got '%s')" % reason
	_note("FOLLOW: 110 m behind: 'You lost them.'")
	return ""


func _check_escape() -> String:
	var escape := MissionObjective.new()
	escape.type = MissionObjective.Type.ESCAPE
	escape.text = "Get away."
	escape.position = SPOT
	escape.radius = 40.0
	escape.fighters = [_spec(SPOT + Vector3(8.0, 0.0, 0.0))]
	_mission(&"test_escape", SPOT, [escape, _go_to("Safe.", SPOT - Vector3(60.0, 0.0, 0.0))])
	if not MissionManager.start(&"test_escape"):
		return "couldn't start the escape mission"
	await _ticks(20)
	var chaser: Fighter = _director.get_fighters()[0] if not _director.get_fighters().is_empty() else null
	var zone: bool = false
	for blip: Dictionary in _director.get_map_blips():
		zone = zone or (blip["kind"] == &"zone" and is_equal_approx(float(blip["radius"]), 40.0))
	if chaser == null or not chaser.hostile:
		return "the chaser should come after the player at once"
	if not zone or not _director.get_objective_text().contains("m to go"):
		return "the circle should be on the map and the distance to go shown ('%s')" % _director.get_objective_text()
	_game.place_player(Transform3D(Basis.IDENTITY, SPOT - Vector3(50.0, 0.0, 0.0)))
	await _ticks(10)
	if MissionManager.get_objective_index() != 1 or (is_instance_valid(chaser) and chaser.hostile):
		return "out of the circle the objective should complete and the chaser give up"
	MissionManager.quit_mission()
	await _ticks(5)
	_note("ESCAPE: the 40 m circle on the map, a chaser at once, the distance to go; outside it, done and the chaser gives up (gone once 45 m off)")
	return ""


func _check_choice() -> String:
	var choice := MissionObjective.new()
	choice.type = MissionObjective.Type.CHOICE
	choice.text = "Which way?"
	choice.choices = PackedStringArray(["The left road", "The right road"])
	choice.choice_id = &"test_road"
	var left: MissionObjective = _go_to("Take the left road.", SPOT + Vector3(-30.0, 0.0, 0.0))
	left.if_choice = &"test_road"
	left.if_answer = 0
	var right: MissionObjective = _go_to("Take the right road.", SPOT + Vector3(30.0, 0.0, 0.0))
	right.if_choice = &"test_road"
	right.if_answer = 1
	_mission(&"test_choice", SPOT, [choice, left, right])
	if not MissionManager.start(&"test_choice"):
		return "couldn't start the choice mission"
	await _frames(5)
	var card: ChoiceCard = _game.choice_card
	if not card.is_open() or not get_tree().paused or card.get_question() != "Which way?" or card.get_buttons().size() != 2:
		return "the choice card should hold the game with the question and two answers (open %s, paused %s, %d buttons)" % [
			card.is_open(), get_tree().paused, card.get_buttons().size()]
	card.get_buttons()[1].pressed.emit()
	await _frames(5)
	if card.is_open() or get_tree().paused:
		return "answering should close the card and carry on"
	if GameState.get_choice(&"test_road") != 1:
		return "the answer should be kept (got %d)" % GameState.get_choice(&"test_road")
	if MissionManager.get_objective_index() != 2 or _director.get_objective_text() != "Take the right road.":
		return "the mission should skip the other branch (objective %d, '%s')" % [MissionManager.get_objective_index(), _director.get_objective_text()]
	var saved: Dictionary = GameState.to_save()
	GameState.from_save(saved)
	if GameState.get_choice(&"test_road") != 1:
		return "the answer should survive a save and load"
	MissionManager.quit_mission()
	await _frames(5)
	_note("CHOICE: the card holds the game with two answers; the answer is kept (and saved) and the mission skips to the right road's branch")
	return ""


## Waits for the failure screen; returns its reason and quits the mission.
func _failure_reason() -> String:
	var failed := _game.get_node("MissionFailed") as MissionFailedScreen
	for i: int in 240:
		if failed.is_open():
			break
		await get_tree().process_frame
	var reason: String = failed.get_reason_shown()
	if failed.is_open():
		failed.quit_mission()
	elif MissionManager.is_active():
		MissionManager.quit_mission()
	await _ticks(5)
	return reason


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
