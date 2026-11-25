extends Node
## Story test (per-feature test scene, M6): missions 3 to 5 and the side jobs, played through the
## real game scene (traffic, pedestrians and new police units off; the wanted level itself runs):
## - 3 "The New Connection": Durai sends you to Kamalam; the meeting plays as a dialogue scene
##   (two-shot camera, letterbox, the player held still) and afterwards the clothes shop and the
##   side jobs open;
## - side jobs: Tiffin Delivery twice (repeatable, a customer from its list), Garage Run by car;
## - 4 "City Chase": into the watched car, two stars, five checkpoints in order, lose the police
##   (here with a garage respray), leave the car in the garage; the house goes on sale;
## - 5 "Building an Empire": not started without ₹6,000; then talk to Durai and buy the house.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/story_test.tscn
## Prints "STORY TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const TEST_SAVES: String = "user://test_saves"

var _catcher: ErrorCatcher
var _game: GameSession
var _director: MissionDirector
var _hud: Hud
var _mhud: MissionHud
var _player: PlayerController
var _world: District
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	SaveManager.save_dir = TEST_SAVES
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_director = _game.missions
	_hud = _game.hud
	_mhud = _hud.get_mission_hud()
	_player = _game.player
	_world = _game.world
	var traffic := _game.get_node("Traffic") as TrafficManager
	var people := _game.get_node("Pedestrians") as PedestrianManager
	traffic.enabled = false
	people.enabled = false
	traffic.clear()
	people.clear()
	(_game.get_node("Police") as PoliceManager).enabled = false
	await _ticks(10)
	# Start after mission 2 (the save format's way of saying what has been passed); mission 1,
	# which starts by itself, is quit first.
	MissionManager.quit_mission()
	MissionManager.from_save({"completed": ["welcome", "first_opportunity"]})
	EconomyManager.set_cash(1500)
	await _ticks(10)
	var steps: Array[Callable] = [_check_new_connection, _check_side_jobs, _check_city_chase, _check_building_an_empire]
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
	for code: Key in [KEY_E, KEY_F]:
		_key(code, false)
	WantedSystem.clear()
	get_tree().paused = false
	print("STORY REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("STORY TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_new_connection() -> String:
	var mission: MissionData = MissionManager.get_mission(&"new_connection")
	var textiles: ShopData = _game.places.get_shop(&"textiles")
	if textiles.is_open() or MissionManager.get_available().has(MissionManager.get_mission(&"job_tiffin")):
		return "before mission 3 the clothes shop and the side jobs should be closed"
	await _walk_into(mission.start_position)
	if MissionManager.get_active() != mission:
		return "walking into Durai's marker should start The New Connection"
	await _teleport(_director.get_contact(&"durai").global_position + Vector3(-1.6, 0.1, 0.0))
	await _talk()
	if MissionManager.get_objective_index() != 1:
		return "talking to Durai should move on to meeting Kamalam"
	var kamalam: MissionContactNPC = _director.get_contact(&"kamalam")
	await _teleport(kamalam.global_position + Vector3(0.0, 0.1, 1.6))
	await _ticks(5)
	if not _hud.get_prompt_text().ends_with("TALK TO KAMALAM"):
		return "next to Kamalam the prompt should be to talk to her (got '%s')" % _hud.get_prompt_text()
	var scene: DialogueScene = _director.get_scene()
	_tap(KEY_E)
	await _ticks(10)
	if not scene.is_playing() or get_viewport().get_camera_3d() != scene.get_camera() or not _player.input_locked:
		return "the meeting should play as a scene (playing %s, scene camera %s, player held %s)" % [
			scene.is_playing(), get_viewport().get_camera_3d() == scene.get_camera(), _player.input_locked]
	var cam: Vector3 = scene.get_camera().global_position
	var to_her: float = cam.distance_to(kamalam.global_position)
	var to_me: float = cam.distance_to(_player.global_position)
	if to_her > 7.0 or to_me > 7.0 or absf(to_her - to_me) > 3.0:
		return "the scene camera should frame both (%.1f m to Kamalam, %.1f m to Vetri)" % [to_her, to_me]
	var speakers: Array[String] = []
	for i: int in 20:
		var line: String = _mhud.get_subtitle_shown()
		var speaker: String = line.get_slice(" ", 0) if line != "" else ""
		if speaker != "" and not speakers.has(speaker):
			speakers.append(speaker)
		if not scene.is_playing():
			break
		_tap(KEY_E)
		await _ticks(4)
	await _ticks(10)
	if scene.is_playing() or _player.input_locked or get_viewport().get_camera_3d() == scene.get_camera():
		return "after the scene the game camera and control should come back"
	if MissionManager.is_active() or not MissionManager.is_completed(mission.id) or EconomyManager.cash != 1500 + mission.reward_cash:
		return "the meeting should pass the mission for %s (cash %d)" % [EconomyManager.format(mission.reward_cash), EconomyManager.cash]
	if not textiles.is_open() or not MissionManager.get_available().has(MissionManager.get_mission(&"job_tiffin")):
		return "after meeting Kamalam the clothes shop and the side jobs should open"
	if not _mhud.get_hint_shown().contains("Velanagar Textiles is open"):
		return "the opening of the clothes shop should be announced (hint '%s')" % _mhud.get_hint_shown()
	_note("3 The New Connection: Durai, then Kamalam's scene (camera %.1f / %.1f m from the two, letterbox, player held; subtitles from %s); passed +%s; Velanagar Textiles and the side jobs open" % [
		to_her, to_me, speakers, EconomyManager.format(mission.reward_cash)])
	return ""


## Side jobs: Tiffin Delivery twice (repeatable, the customer one of its addresses), then a
## Garage Run by car; each pays and stays on offer.
func _check_side_jobs() -> String:
	var tiffin: MissionData = MissionManager.get_mission(&"job_tiffin")
	var garage: MissionData = MissionManager.get_mission(&"job_garage")
	var cash: int = EconomyManager.cash
	var addresses: Array[String] = []
	for run: int in 2:
		await _walk_into(tiffin.start_position)
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
		await _teleport(goal + Vector3(0.0, 0.1, 0.0))
		await _ticks(10)
		if MissionManager.is_active() or EconomyManager.cash != cash + 250 * (run + 1):
			return "run %d: reaching the customer should pass the job for ₹250 (active %s, cash %d)" % [run + 1, MissionManager.is_active(), EconomyManager.cash]
		await _ticks(30)
		if not MissionManager.get_available().has(tiffin):
			return "Tiffin Delivery should be offered again after it's passed"
	cash = EconomyManager.cash
	await _walk_into(garage.start_position)
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
	await _drive_to(car, drop)
	await _ticks(5)
	if MissionManager.is_active() or EconomyManager.cash != cash + 600:
		return "stopping at the owner's should pass Garage Run for ₹600 (active %s, cash %d, objective '%s')" % [MissionManager.is_active(), EconomyManager.cash, _mhud.get_objective_shown()]
	await _get_out()
	_note("side jobs: Tiffin Delivery twice (Selvi hands over the carrier; customers at %s; ₹250 each, offered again), Garage Run by car to (%.0f, %.0f) for ₹600" % [", ".join(addresses), drop.x, drop.z])
	return ""


func _check_city_chase() -> String:
	var mission: MissionData = MissionManager.get_mission(&"city_chase")
	await _walk_into(mission.start_position)
	if MissionManager.get_active() != mission or WantedSystem.is_wanted():
		return "walking into Kamalam's marker should start City Chase with a clean record"
	await _teleport(_director.get_contact(&"kamalam").global_position + Vector3(0.0, 0.1, 1.6))
	await _talk()
	var car: VehicleController = _director.get_vehicle(&"watched_car")
	if MissionManager.get_objective_index() != 1 or car == null:
		return "Kamalam's briefing should lead to the watched car"
	if not await _get_in(car):
		return "couldn't get into the watched car"
	await _ticks(5)
	if MissionManager.get_objective_index() != 2 or WantedSystem.level < 2:
		return "getting in should start the checkpoints with two stars (objective %d, level %d)" % [MissionManager.get_objective_index(), WantedSystem.level]
	if not _mhud.get_objective_shown().ends_with("(1/5)") or _mhud.get_timer_shown() == "":
		return "the HUD should show checkpoint 1/5 and a clock ('%s', '%s')" % [_mhud.get_objective_shown(), _mhud.get_timer_shown()]
	var points: PackedVector3Array = mission.objectives[2].checkpoints
	# Out of order does nothing: the last checkpoint first.
	await _drive_to(car, points[4])
	if not _mhud.get_objective_shown().ends_with("(1/5)"):
		return "a checkpoint out of order shouldn't count ('%s')" % _mhud.get_objective_shown()
	for i: int in points.size():
		await _drive_to(car, points[i])
		var want: String = "(%d/5)" % (i + 2)
		if i < points.size() - 1 and not _mhud.get_objective_shown().ends_with(want):
			return "after checkpoint %d the HUD should say %s ('%s')" % [i + 1, want, _mhud.get_objective_shown()]
	if MissionManager.get_objective_index() != 3 or _mhud.get_objective_shown() != "Lose the police.":
		return "after the last checkpoint: lose the police (objective %d, '%s')" % [MissionManager.get_objective_index(), _mhud.get_objective_shown()]
	# Lose them with a respray; then the car is already in the garage.
	var garage: ShopData = _game.places.get_shop(&"garage")
	var paint: Color = (car.get_node("Model") as VehicleModel).get_paint()
	var cash: int = EconomyManager.cash
	await _drive_to(car, _game.places.get_spot(garage))
	await _ticks(30)
	if _hud.get_prompt_text() != "E  RESPRAY":
		return "stopped in the garage bay the respray should be offered (got '%s')" % _hud.get_prompt_text()
	_tap(KEY_E)
	await _frames(3)
	_game.shop_menu.choose(&"respray")
	for i: int in 240:
		await get_tree().process_frame
		if not get_tree().paused and not MissionManager.is_active():
			break
	await _ticks(10)
	if MissionManager.is_active() or not MissionManager.is_completed(mission.id):
		return "the respray should clear the stars with the car in the garage: mission passed (active %s, objective '%s', level %d)" % [
			MissionManager.is_active(), _mhud.get_objective_shown(), WantedSystem.level]
	if (car.get_node("Model") as VehicleModel).get_paint().is_equal_approx(paint) or EconomyManager.cash != cash - 500 + mission.reward_cash:
		return "the car should be resprayed for ₹500 and the mission pay %s (cash %d -> %d)" % [EconomyManager.format(mission.reward_cash), cash, EconomyManager.cash]
	var house: PropertyData = _game.places.get_property(&"verandah_house")
	if not house.is_on_sale() or not _game.places.has_sale_board(house):
		return "after City Chase the house should be for sale"
	await _get_out()
	_note("4 City Chase: briefing, into the watched car -> 2 stars, checkpoints counted only in order (1/5 .. 5/5), 'Lose the police.', a respray in the garage clears the stars with the car delivered: passed +%s; the house goes on sale" % EconomyManager.format(mission.reward_cash))
	return ""


func _check_building_an_empire() -> String:
	var mission: MissionData = MissionManager.get_mission(&"building_empire")
	if not MissionManager.get_available().has(mission):
		return "Building an Empire should be on offer after City Chase"
	EconomyManager.set_cash(4000)
	await _walk_into(mission.start_position)
	if MissionManager.is_active():
		return "with ₹4,000 the mission shouldn't start"
	if not _mhud.get_hint_shown().contains("needs ₹6,000"):
		return "walking in short of cash should say what it needs (hint '%s')" % _mhud.get_hint_shown()
	EconomyManager.set_cash(7000)
	await _teleport(mission.start_position + Vector3(0.0, 0.1, 8.0))
	await _ticks(10)
	await _walk_into(mission.start_position)
	if MissionManager.get_active() != mission:
		return "with ₹7,000 walking back in should start it"
	await _teleport(_director.get_contact(&"durai").global_position + Vector3(0.0, 0.1, 1.6))
	await _talk()
	if MissionManager.get_objective_index() != 1 or _mhud.get_objective_shown() != "Buy the verandah house.":
		return "after Durai: buy the house ('%s')" % _mhud.get_objective_shown()
	var door: Vector3 = _game.places.get_place(&"house").origin
	await _teleport(door + Vector3(0.0, 0.1, 0.0))
	await _ticks(10)
	if not _hud.get_prompt_text().begins_with("E  BUY VERANDAH HOUSE"):
		return "at the door the buy prompt should show during the mission (got '%s')" % _hud.get_prompt_text()
	_tap(KEY_E)
	await _frames(3)
	_game.shop_menu.choose(&"buy")
	await _ticks(10)
	if not EconomyManager.owns(&"verandah_house") or MissionManager.is_active() or not MissionManager.is_completed(mission.id):
		return "buying the house should pass Building an Empire"
	if EconomyManager.cash != 7000 - 6000 + mission.reward_cash:
		return "cash after buying and the reward should be %d (is %d)" % [7000 - 6000 + mission.reward_cash, EconomyManager.cash]
	_note("5 Building an Empire: refused with ₹4,000 ('needs ₹6,000'), started with ₹7,000; Durai, then the house bought at its door: passed +%s" % EconomyManager.format(mission.reward_cash))
	return ""


## Puts the car (with the player in it) at `point`, stopped, and lets the objective notice.
func _drive_to(car: VehicleController, point: Vector3) -> void:
	_world.streamer.load_around_now(point)
	var flat := Vector3(car.global_basis.z.x, 0.0, car.global_basis.z.z).normalized()
	car.teleport(Transform3D(Basis.looking_at(-flat, Vector3.UP), point + Vector3(0.0, 0.6, 0.0)))
	await _ticks(10)


## Walks into a start marker: from a few metres off first (markers re-arm once you've stepped
## away, so a mission ending beside the next one's marker doesn't start it at once).
func _walk_into(pos: Vector3) -> void:
	await _teleport(pos + Vector3(0.0, 0.1, 9.0))
	await _ticks(5)
	await _teleport(pos + Vector3(0.3, 0.1, 0.0))
	await _ticks(5)


func _talk() -> int:
	_tap(KEY_E)
	await _ticks(3)
	var lines: int = 0
	while _director.dialogue.is_playing() and lines < 14:
		lines += 1
		_tap(KEY_E)
		await _ticks(3)
	return lines


func _get_in(car: VehicleController) -> bool:
	await _teleport(car.get_exit_points()[0] + Vector3.UP * 0.1)
	await _ticks(10)
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			return true
	return false


func _get_out() -> void:
	_tap(KEY_F)
	for i: int in 90:
		await get_tree().physics_frame
		if not _player.is_in_vehicle():
			break
	await _ticks(30)


func _teleport(pos: Vector3) -> void:
	_world.streamer.load_around_now(pos)
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(3)


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
