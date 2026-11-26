extends Node
## Campaign test (per-feature test scene, M7 story). Runs the real game scene (traffic and
## pedestrians off) and plays story missions 6-15 through, from walking into each start marker
## to the reward, both endings of the last. On the way it checks what a player would trip over:
## - givers, contacts, fighters and lent vehicles stand clear of buildings, on the ground;
## - every cutscene shot's camera can see what it looks at (nothing solid in between), and its
##   people and the player stand clear of buildings;
## - fights, tails, escapes and the final choice play out; each mission pays its reward.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/campaign_test.tscn
## Add "-- --from=<mission id>" to start at that mission.
## Prints "CAMPAIGN TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const CAMPAIGN: Array[StringName] = [&"thorns", &"night_van", &"inspector", &"ledger", &"old_friends",
	&"detective", &"fire", &"mansion", &"harbour", &"rise_of_the_don"]
## How far behind a tailed car the player keeps (well inside "lost", outside "spotted").
const TAIL_GAP: float = 30.0

var _catcher: ErrorCatcher
var _game: GameSession
var _player: PlayerController
var _director: MissionDirector
var _cutscene: CutscenePlayer
var _world: CityWorld
var _router: RoadRouter
var _query := PhysicsShapeQueryParameters3D.new()
var _report: PackedStringArray = []
var _shots_checked: int = 0


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
	_cutscene = _director.get_cutscene()
	_world = _game.world
	_router = RoadRouter.for_graph(_world.get_lane_graph())
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	_query.shape = sphere
	_query.collision_mask = 1
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).clear()
	MissionManager.quit_mission()
	var failure: String = await _wait_for_navmesh()
	# "-- --from=<mission id>" starts there (debugging one mission without playing the ones before).
	var first: int = 0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--from="):
			first = maxi(CAMPAIGN.find(StringName(arg.get_slice("=", 1))), 0)
	if failure == "":
		for id: StringName in CAMPAIGN.slice(first):
			failure = await _play(id, 0)
			if failure != "":
				failure = "%s: %s" % [id, failure]
				break
	if failure == "":
		failure = await _play(&"rise_of_the_don", 1)          # the other ending
		if failure != "":
			failure = "rise_of_the_don (second ending): %s" % failure
	if failure == "":
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "engine/script error: %s" % errors[0]
	get_tree().paused = false
	print("CAMPAIGN REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("CAMPAIGN TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _wait_for_navmesh() -> String:
	await _teleport(Vector3(-72.0, 0.3, -60.0))
	var map: RID = _player.get_world_3d().navigation_map
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000 and NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
	return "" if NavigationServer3D.map_get_iteration_id(map) != 0 else "the navmesh never synchronised"


## Plays mission `id` from its start marker to its reward, answering any choice `answer`.
func _play(id: StringName, answer: int) -> String:
	var mission: MissionData = MissionManager.get_mission(id)
	if mission == null:
		return "not in the story"
	MissionManager.quit_mission()
	WantedSystem.clear()
	(_game.get_node("Police") as PoliceManager).clear_all()
	var done: Array[String] = []
	for m: MissionData in MissionManager.story.missions:
		if m.id == id:
			break
		done.append(String(m.id))
	MissionManager.from_save({"completed": done})
	_player.stats.set_health(_player.stats.get_max_health())
	await _ticks(5)
	if not MissionManager.get_available().has(mission) or not _director.has_offer(mission):
		return "should be on offer once the missions before it are passed"
	var giver: MissionContactNPC = _director.get_offer_giver(mission)
	if mission.giver != null:
		if giver == null:
			return "%s should stand by the start marker" % mission.giver.display_name
		var where: String = _clear_of_buildings(giver.global_position, [giver.get_rid()])
		if where != "":
			return "%s (the giver) stands inside %s" % [mission.giver.display_name, where]
	var cash: int = EconomyManager.cash
	await _walk_into(mission.start_position)
	if not MissionManager.is_active() or MissionManager.get_active() != mission:
		return "walking into the start marker should start it"
	var kinds: PackedStringArray = []
	for step: int in 40:
		if not MissionManager.is_active():
			break
		if MissionManager.is_failed():
			return "failed at objective %d: '%s'" % [MissionManager.get_objective_index(),
				(_game.get_node("MissionFailed") as MissionFailedScreen).get_reason_shown()]
		var index: int = MissionManager.get_objective_index()
		var objective: MissionObjective = MissionManager.get_objective()
		kinds.append(MissionObjective.Type.keys()[objective.type])
		var error: String = await _do(objective, answer)
		if error != "":
			return "objective %d ('%s'): %s" % [index, objective.text, error]
		for i: int in 300:
			if not MissionManager.is_active() or MissionManager.is_failed() or MissionManager.get_objective_index() != index:
				break
			await get_tree().physics_frame
		if MissionManager.is_failed():
			return "failed at objective %d ('%s'): '%s'" % [index, objective.text,
				(_game.get_node("MissionFailed") as MissionFailedScreen).get_reason_shown()]
		if MissionManager.is_active() and MissionManager.get_objective_index() == index:
			return "objective %d ('%s') didn't complete" % [index, objective.text]
	if MissionManager.is_active() or not MissionManager.is_completed(id):
		return "should be passed after its objectives"
	if EconomyManager.cash != cash + mission.reward_cash:
		return "should pay %s (cash %d -> %d)" % [EconomyManager.format(mission.reward_cash), cash, EconomyManager.cash]
	var ending: String = ""
	if GameState.get_choice(&"ending") >= 0 and id == &"rise_of_the_don":
		ending = ", ending: %s" % ["The Honest Road", "The Don of Velanagar"][GameState.get_choice(&"ending")]
	_note("%s '%s': %s; +%s%s" % [id, mission.title, " > ".join(kinds), EconomyManager.format(mission.reward_cash), ending])
	return ""


func _do(objective: MissionObjective, answer: int) -> String:
	match objective.type:
		MissionObjective.Type.TALK_TO:
			return await _talk_to(objective)
		MissionObjective.Type.CUTSCENE:
			return await _watch(objective)
		MissionObjective.Type.ENTER_VEHICLE:
			return await _get_in(objective)
		MissionObjective.Type.GO_TO:
			await _arrive(_director.get_goal_position())
		MissionObjective.Type.FIGHT:
			return await _win_fight()
		MissionObjective.Type.FOLLOW:
			return await _tail(objective)
		MissionObjective.Type.ESCAPE:
			return await _escape(objective)
		MissionObjective.Type.CHOICE:
			return await _choose(answer)
	return ""


func _talk_to(objective: MissionObjective) -> String:
	var npc: MissionContactNPC = _director.get_contact(objective.contact)
	if npc == null:
		return "contact %s isn't there" % objective.contact
	var inside: String = _clear_of_buildings(npc.global_position, [npc.get_rid()])
	if inside != "":
		return "%s stands inside %s" % [npc.data.display_name, inside]
	var spot: Vector3 = _free_spot_near(npc.global_position, 1.6, [npc.get_rid()])
	await _teleport(spot + Vector3.UP * 0.1)
	await _ticks(5)
	var index: int = MissionManager.get_objective_index()
	_tap(KEY_E)
	for press: int in 24:
		await _ticks(4)
		if MissionManager.get_objective_index() != index or not MissionManager.is_active():
			return ""
		_tap(KEY_E)
	return "talking to %s didn't finish (prompt '%s')" % [npc.data.display_name, _game.hud.get_prompt_text()]


## Plays the cutscene shot by shot (skipping on), checking each shot's camera can see its subject
## and that nobody in it stands inside a building.
func _watch(objective: MissionObjective) -> String:
	for i: int in 60:
		if _cutscene.is_playing():
			break
		await get_tree().process_frame
	if not _cutscene.is_playing():
		return "the cutscene didn't start"
	var exclude: Array[RID] = _contact_rids()
	var data: CutsceneData = objective.cutscene
	for shot: int in data.shots.size():
		while _cutscene.is_playing() and _cutscene.get_shot() < shot:
			await get_tree().process_frame
		await _frames(4)
		if not _cutscene.is_playing():
			return "the cutscene ended early, at shot %d" % shot
		var camera: Vector3 = _cutscene.get_camera().global_position
		var target: Vector3 = (_cutscene.get_node("Target") as Node3D).global_position
		var ray := PhysicsRayQueryParameters3D.create(target, camera, 1, exclude)
		var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(camera) > 0.3:
			return "%s shot %d: the camera can't see what it looks at (%s in the way at %s)" % [
				data.id, shot, (hit["collider"] as Node).name, (hit["position"] as Vector3).snapped(Vector3(0.1, 0.1, 0.1))]
		if shot == 0:
			for figure: CutsceneFigure in _cutscene.get_figures():
				var inside: String = _clear_of_buildings(figure.global_position, exclude)
				if inside != "":
					return "%s: %s stands inside %s" % [data.id, figure.speaker if figure.speaker != "" else figure.name, inside]
			var player_inside: String = _clear_of_buildings(_player.global_position, exclude)
			if player_inside != "":
				return "%s: the player is put inside %s" % [data.id, player_inside]
		_shots_checked += 1
		_press(&"interact")
	await _frames(5)
	return "" if not _cutscene.is_playing() else "the cutscene didn't end after its last shot"


func _get_in(objective: MissionObjective) -> String:
	var car: VehicleController = _director.get_vehicle(objective.vehicle)
	if car == null:
		return "vehicle %s isn't there" % objective.vehicle
	await _ticks(20)
	if car.freeze or car.global_position.y < 0.1 or car.global_position.y > 1.6:
		return "%s should stand on the road (at %s, frozen %s)" % [objective.vehicle, car.global_position, car.freeze]
	var inside: String = _clear_of_buildings(car.global_position, [car.get_rid()])
	if inside != "":
		return "%s is parked inside %s" % [objective.vehicle, inside]
	await _teleport(car.get_exit_points()[0] + Vector3.UP * 0.1)
	await _ticks(10)
	_tap(KEY_F)
	for i: int in 120:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			return ""
	return "couldn't get into %s (player at %s, car at %s, target %s, state %s, locked %s, prompt '%s')" % [objective.vehicle, _player.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
		car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), (_player.get_node("VehicleInteractor") as VehicleInteractor).get_target(), _player.get_state_name(), _player.input_locked, _game.hud.get_prompt_text()]


## On foot, or driving whatever the player is in.
func _arrive(point: Vector3) -> void:
	if _player.is_in_vehicle() and _player.vehicle != null:
		var car: VehicleController = _player.vehicle
		_world.streamer.load_around_now(point)
		# Pull up on the road beside the goal if that is within its reach, else drive onto it.
		var node: int = _router.nearest_node(point)
		var road: Vector3 = _world.get_lane_graph().get_position(node) if node >= 0 else point
		var reach: float = MissionManager.get_objective().radius if MissionManager.get_objective() != null else 4.0
		var at: Vector3 = road if _flat(road).distance_to(_flat(point)) < reach - 0.5 else point
		car.teleport(Transform3D(car.global_basis, Vector3(at.x, 0.6, at.z)))
		await _ticks(30)
	else:
		await _teleport(point + Vector3.UP * 0.1)
		await _ticks(10)


func _win_fight() -> String:
	await _ticks(30)
	var fighters: Array[Fighter] = _director.get_fighters()
	if fighters.is_empty():
		return "no fighters appeared"
	var exclude: Array[RID] = _contact_rids()
	for fighter: Fighter in fighters:
		var inside: String = _clear_of_buildings(fighter.global_position, exclude)
		if inside != "":
			return "a fighter stands inside %s at %s" % [inside, fighter.global_position.snapped(Vector3(0.1, 0.1, 0.1))]
		if not fighter.is_on_floor():
			return "a fighter at %s isn't standing on the ground" % fighter.global_position.snapped(Vector3(0.1, 0.1, 0.1))
	for fighter: Fighter in fighters:
		fighter.take_hit(1000.0, fighter.global_position + Vector3(1.0, 0.0, 0.0), _player)
		await _ticks(2)
	return ""


## Keeps TAIL_GAP metres behind the tailed car until it arrives.
func _tail(objective: MissionObjective) -> String:
	var index: int = MissionManager.get_objective_index()
	for f: int in 60 * 150:
		if MissionManager.get_objective_index() != index or MissionManager.is_failed() or not MissionManager.is_active():
			return ""
		var target: VehicleController = _director.get_vehicle(objective.vehicle)
		if target == null:
			return "the car to follow isn't there"
		if f % 15 == 0:
			var behind: Vector3 = target.global_position - target.global_basis.z * TAIL_GAP
			if _player.is_in_vehicle() and _player.vehicle != null:
				_player.vehicle.teleport(Transform3D(target.global_basis, Vector3(behind.x, target.global_position.y + 0.1, behind.z)))
				_player.vehicle.linear_velocity = target.linear_velocity
			else:
				_player.global_position = Vector3(behind.x, 0.4, behind.z)
		await get_tree().physics_frame
	var driver: RouteDriver = _director.get_follow_driver()
	var tailed: VehicleController = _director.get_vehicle(objective.vehicle)
	return "the tailed car didn't arrive within 150 s (next stop %d, at %s, frozen %s, sleeping %s, speed %.1f, driver %s, route %d, paused %s, player in %s at %s, process %s)" % [
		driver.get_next_stop() if driver != null else -1, tailed.global_position, tailed.freeze, tailed.sleeping, tailed.get_forward_speed(),
		tailed.get_driver(), driver.get_route().size() if driver != null else -1, get_tree().paused, _player.vehicle, _player.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
		"shop %s pause %s busted %s hospital %s failed %s choice %s map %s" % [_game.shop_menu.is_open(), _game.pause_menu.is_open(), _game.busted_screen.is_showing(),
			_game.hospital_screen.is_showing(), (_game.get_node("MissionFailed") as MissionFailedScreen).is_open(), _game.choice_card.is_open(), _game.map_screen.is_open()]]


## Out of the circle, to the nearest road beyond it.
func _escape(objective: MissionObjective) -> String:
	var from: Vector3 = objective.position
	for attempt: int in 8:
		var angle: float = TAU * attempt / 8.0
		var want: Vector3 = from + Vector3(cos(angle), 0.0, sin(angle)) * (objective.radius + 30.0)
		var node: int = _router.nearest_node(want)
		if node < 0:
			continue
		var road: Vector3 = _world.get_lane_graph().get_position(node)
		if _flat(road).distance_to(_flat(from)) < objective.radius + 5.0:
			continue
		await _arrive(road)
		if MissionManager.get_objective_index() < 0 or MissionManager.get_objective() != objective:
			return ""
	return "couldn't get out of the %d m circle" % int(objective.radius)


func _choose(answer: int) -> String:
	var card: ChoiceCard = _game.choice_card
	for i: int in 60:
		if card.is_open():
			break
		await get_tree().process_frame
	if not card.is_open():
		return "the choice card didn't open"
	var buttons: Array[Button] = card.get_buttons()
	if answer >= buttons.size():
		return "only %d answers" % buttons.size()
	buttons[answer].pressed.emit()
	await _frames(5)
	return ""


# --------------------------------------------------------------------------- helpers

## What solid world geometry overlaps a person standing at `at` (chest height), or "".
func _clear_of_buildings(at: Vector3, exclude: Array[RID]) -> String:
	for height: float in [0.6, 1.3]:
		_query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * height)
		_query.exclude = exclude
		var hits: Array[Dictionary] = _player.get_world_3d().direct_space_state.intersect_shape(_query, 1)
		if not hits.is_empty():
			return str((hits[0]["collider"] as Node).name)
	return ""


## A spot `distance` from `at` that is clear of buildings (for walking up to someone).
func _free_spot_near(at: Vector3, distance: float, exclude: Array[RID]) -> Vector3:
	for k: int in 8:
		var angle: float = TAU * k / 8.0
		var spot: Vector3 = at + Vector3(cos(angle), 0.0, sin(angle)) * distance
		if _clear_of_buildings(spot, exclude) == "":
			return spot
	return at + Vector3(distance, 0.0, 0.0)


func _contact_rids() -> Array[RID]:
	var rids: Array[RID] = [_player.get_rid()]
	var mission: MissionData = MissionManager.get_active()
	if mission == null:
		return rids
	var people: Array[MissionContact] = mission.contacts.duplicate()
	if mission.giver != null:
		people.append(mission.giver)
	for contact: MissionContact in people:
		var npc: MissionContactNPC = _director.get_contact(contact.id)
		if npc != null:
			rids.append(npc.get_rid())
	return rids


## Walks into a start marker from a few metres off (markers re-arm once you've stepped away).
func _walk_into(pos: Vector3) -> void:
	_world.streamer.load_around_now(pos)
	await _teleport(_free_spot_near(pos, 9.0, [_player.get_rid()]) + Vector3.UP * 0.1)
	await _ticks(5)
	await _teleport(pos + Vector3(0.3, 0.1, 0.0))
	for i: int in 60:
		if MissionManager.is_active():
			break
		await get_tree().physics_frame


func _teleport(pos: Vector3) -> void:
	if _player.is_in_vehicle():
		_player.exit_vehicle(pos)
		await _ticks(30)
	_world.streamer.load_around_now(pos)
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(3)


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


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
