extends Node
## Police test (per-feature test scene, M6). Runs the real game scene (traffic and pedestrians off)
## and checks the wanted system and the police response:
## - crimes and heat: knockdowns raise the level step by step, the HUD stars follow; knocking a
##   real pedestrian down with a car makes you wanted;
## - escalation while seen; evading: out of sight, outside the search circle long enough, the
##   level drops to 0;
## - pursuit: police cars come for you, officers get out, sirens and lights, police blips;
## - busted: the BUSTED card, a fine, out at the police station, the running mission fails;
## - roadblocks with spike strips ahead of a fast car; burst tyres; the helicopter at level 5.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/police_test.tscn
## Prints "POLICE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
## Open stretch of Ring B (z = 112), as in the smoke test; and a lane-side spot for on-foot checks.
const TEST_ROAD := Vector3(-20.0, 0.6, 109.0)

var _catcher: ErrorCatcher
var _game: GameSession
var _police: PoliceManager
var _player: PlayerController
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
	_police = _game.get_node("Police") as PoliceManager
	_player = _game.player
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).clear()
	await _ticks(30)
	var steps: Array[Callable] = [
		_check_heat, _check_knockdown_crime, _check_escalation_and_evading, _check_pursuit_and_bust,
		_check_roadblock_and_spikes, _check_helicopter,
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
	WantedSystem.clear()
	get_tree().paused = false
	print("POLICE REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("POLICE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_heat() -> String:
	var hud := _game.get_node("HUD") as Hud
	var stars: WantedDisplay = hud.get_wanted_display()
	var levels: Array[int] = []
	_police.enabled = false
	for i: int in 3:
		WantedSystem.report_crime(&"knockdown", _player.global_position)
		levels.append(WantedSystem.level)
	await _frames(2)
	if levels != [1, 1, 2]:
		return "three knockdowns should give levels 1, 1, 2 (got %s)" % [levels]
	if not stars.visible or stars.get_lit_count() != 2:
		return "the HUD should show 2 stars"
	WantedSystem.report_crime(&"hit_police", _player.global_position)
	if WantedSystem.level != 3:
		return "ramming police on top of that should make it level 3 (got %d)" % WantedSystem.level
	WantedSystem.clear()
	await _frames(2)
	if stars.visible:
		return "the stars should hide at level 0"
	_police.enabled = true
	_note("heat: knockdowns give levels 1, 1, 2; ramming police then gives 3; the HUD stars follow and hide when clear")
	return ""


func _check_knockdown_crime() -> String:
	var car := _game.get_node("World/Vehicles/SedanRingB") as VehicleController
	var people := _game.get_node("Pedestrians") as PedestrianManager
	_police.enabled = false
	car.teleport(Transform3D(Basis(Vector3.UP, -PI * 0.5), TEST_ROAD + Vector3(14.0, 0.0, 0.0)))
	await _ticks(10)
	_player.global_position = car.get_exit_points()[0] + Vector3.UP * 0.2
	_player.reset_physics_interpolation()
	await _ticks(10)
	_player.enter_vehicle(car, car.get_exit_points()[0])
	for i: int in 60:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			break
	if not _player.is_in_vehicle():
		return "couldn't get into the test car"
	var victim: Pedestrian = people.spawn_at(Vector3(TEST_ROAD.x - 12.0, 0.05, TEST_ROAD.z))
	victim.stand(30.0)
	var driver: Node3D = car.get_driver()
	for f: int in 60 * 6:
		await get_tree().physics_frame
		car.set_controls(1.0 if car.get_speed_kmh() < 30.0 else 0.0, 0.0, 0.0, false)
		if victim.state == Pedestrian.State.KNOCKED:
			break
	car.set_controls(0.1, 1.0, 0.0, false)
	if victim.state != Pedestrian.State.KNOCKED:
		return "the car never knocked the pedestrian down"
	if WantedSystem.level != 1:
		return "knocking someone down with your car should make you wanted (level %d)" % WantedSystem.level
	await _ticks(60)
	WantedSystem.clear()
	people.clear()
	_player.exit_vehicle(car.get_exit_points()[0])
	await _ticks(60)
	assert(driver != null)
	_police.enabled = true
	_note("driving into a pedestrian makes you wanted (1 star)")
	return ""


func _check_escalation_and_evading() -> String:
	_police.enabled = false
	_police.clear_all()
	var tuning: WantedTuning = WantedSystem.tuning
	var real_rise: float = tuning.escalate_seconds[1]
	tuning.escalate_seconds[1] = 3.0
	WantedSystem.set_level(1, _player.global_position)
	await _ticks(60 * 5)     # the dispatch window counts as being seen
	tuning.escalate_seconds[1] = real_rise
	if WantedSystem.level != 2:
		return "being seen long enough at level 1 should raise it to 2 (level %d)" % WantedSystem.level
	# Out of sight: searching, the circle shrinks; outside it long enough, level by level to 0.
	await _ticks(60 * 2)
	if not WantedSystem.searching:
		return "with nobody seeing you, the police should be searching"
	var start_radius: float = WantedSystem.zone_radius
	await _ticks(60)
	if WantedSystem.zone_radius >= start_radius:
		return "the search circle should shrink (%.0f -> %.0f m)" % [start_radius, WantedSystem.zone_radius]
	var levels: Array[int] = [WantedSystem.level]
	var far := Vector3(150.0, 0.5, 8.5)
	for hop: int in 2:
		far.x -= 220.0 * hop
		_player.global_position = far
		_player.reset_physics_interpolation()
		_game.world.streamer.load_around_now(far)
		for i: int in 60 * 12:
			await get_tree().physics_frame
			if WantedSystem.level < levels[levels.size() - 1]:
				break
		levels.append(WantedSystem.level)
		if WantedSystem.level == 0:
			break
	if WantedSystem.level != 0:
		return "staying out of the search circle should clear the level step by step (levels %s)" % [levels]
	_player.global_position = Vector3(-20.0, 0.5, 116.0)
	_player.reset_physics_interpolation()
	_game.world.streamer.load_around_now(_player.global_position)
	await _ticks(30)
	_police.enabled = true
	_note("seen for long enough, level 1 rises to 2; out of sight the search circle shrinks (%.0f m at first) and staying outside it clears the level (%s)" % [start_radius, levels])
	return ""


func _check_pursuit_and_bust() -> String:
	var station: Transform3D = _game.world.data.nearest_police_station(_player.global_position)
	if station.origin == Vector3.ZERO:
		return "the city has no police station"
	EconomyManager.set_cash(1500)
	var cash: int = EconomyManager.cash
	var expected_fine: int = maxi(WantedSystem.tuning.fine_min, int(cash * WantedSystem.tuning.fine_share))
	if not MissionManager.is_active():
		MissionManager.start(&"welcome")
	await _ticks(10)
	var mission_running: bool = MissionManager.is_active()
	if not mission_running:
		return "couldn't start mission 1 to check that an arrest fails it"
	WantedSystem.set_level(2, _player.global_position)
	var closest: float = INF
	var first_seen: Dictionary = {}     # car -> its distance when it appeared
	var closed_in: float = 0.0          # the most any car closed the distance
	var sirens: bool = false
	var officers_seen: int = 0
	var blips: int = 0
	var busted: Array[bool] = [false]
	WantedSystem.busted.connect(func() -> void: busted[0] = true, CONNECT_ONE_SHOT)
	for f: int in 60 * 45:
		await get_tree().physics_frame
		for car: VehicleController in _police.get_cars():
			var d: float = car.global_position.distance_to(_player.global_position)
			closest = minf(closest, d)
			if not first_seen.has(car):
				first_seen[car] = d
			closed_in = maxf(closed_in, float(first_seen[car]) - d)
			sirens = sirens or (car.get_node("LightBar") as PoliceLightBar).is_siren_on()
		officers_seen = maxi(officers_seen, _police.get_officers().size())
		if f == 60 * 3:
			for blip: Dictionary in _police.get_map_blips():
				blips += 1 if blip["kind"] == &"police" else 0
		if busted[0]:
			break
	if not busted[0]:
		return "standing still at level 2 should get you arrested within 45 s (closest car %.0f m, %d officers)" % [closest, officers_seen]
	# Officers on foot (who appear closer) often make the arrest before the cars arrive: the cars
	# only have to be closing in.
	if closed_in < 25.0 or not sirens or officers_seen < 1 or blips < 2:
		return "pursuit: cars closed in by %.0f m (closest %.0f m), sirens %s, %d officers, %d police blips" % [closed_in, closest, sirens, officers_seen, blips]
	var screen := _game.get_node("Busted") as BustedScreen
	await _frames(3)
	if not screen.is_showing() or not get_tree().paused:
		return "BUSTED card not shown"
	while screen.is_showing():
		await get_tree().process_frame
	await _ticks(10)
	if _player.global_position.distance_to(station.origin) > 3.0:
		return "after the arrest the player should be at the police station %s (at %s)" % [station.origin, _player.global_position]
	if EconomyManager.cash != cash - expected_fine:
		return "the fine should be %d (cash %d -> %d)" % [expected_fine, cash, EconomyManager.cash]
	if WantedSystem.is_wanted() or not _police.get_cars().is_empty() or not _police.get_officers().is_empty():
		return "after the arrest the record and the streets should be clear"
	if mission_running:
		var failed_screen := _game.get_node("MissionFailed") as MissionFailedScreen
		for i: int in 120:
			if failed_screen.is_open():
				break
			await get_tree().process_frame
		if failed_screen.get_reason_shown() != "You were busted.":
			return "the running mission should fail with 'You were busted.' (got '%s')" % failed_screen.get_reason_shown()
		failed_screen.quit_mission()
		await _frames(3)
	_note("level 2 on foot: police cars close in (by %.0f m, to %.0f m, sirens on), %d officers chase you, police blips on the map; arrested: BUSTED card, fine %s, released at the police station, police gone%s" % [
		closed_in, closest, officers_seen, EconomyManager.format(expected_fine), ", the mission fails" if mission_running else ""])
	return ""


func _check_roadblock_and_spikes() -> String:
	_police.enabled = false
	var car := _game.get_node("World/Vehicles/SedanRingB") as VehicleController
	car.repair_tyres()
	car.teleport(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(60.0, 0.6, 109.0)))     # Ring B, heading west
	_game.world.streamer.load_around_now(car.global_position)
	await _ticks(10)
	_player.global_position = car.get_exit_points()[0] + Vector3.UP * 0.2
	_player.reset_physics_interpolation()
	await _ticks(10)
	_player.enter_vehicle(car, car.get_exit_points()[0])
	for i: int in 60:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			break
	WantedSystem.set_level(4, car.global_position)
	var block: Node3D = _police.place_roadblock_ahead(true)
	if block == null:
		return "no roadblock could be placed ahead on Ring B"
	var ahead: float = (block.global_position - car.global_position).dot(car.global_basis.z)
	var cars: int = block.find_children("*", "VehicleController", true, false).size()
	var strip := block.find_child("SpikeStrip", true, false) as SpikeStrip
	# Ring B has two lanes each way: the block should take three cars to cover it, centred on the
	# road (z = 112) whichever lane the car was in.
	if ahead < 60.0 or cars != 3 or strip == null or absf(block.global_position.z - 112.0) > 1.0:
		return "roadblock: %.0f m ahead, %d cars, spike strip %s, centre z %.1f" % [ahead, cars, strip != null, block.global_position.z]
	# Drive over the strip.
	car.teleport(Transform3D(car.global_basis, strip.global_position + car.global_basis.z * -8.0 + Vector3.UP * 0.6))
	for f: int in 60 * 3:
		await get_tree().physics_frame
		car.set_controls(1.0, 0.0, 0.0, false)
		if car.are_tyres_burst():
			break
	car.set_controls(0.1, 1.0, 0.0, false)
	if not car.are_tyres_burst():
		return "driving over the spike strip should burst the tyres"
	WantedSystem.clear()
	await _ticks(30)
	_player.exit_vehicle(car.get_exit_points()[0])
	await _ticks(30)
	_police.clear_all()
	car.repair_tyres()
	_police.enabled = true
	_note("level 4: a roadblock %.0f m ahead (%d police cars across all four lanes, from the wrong-way lane too) with a spike strip; driving over it bursts the tyres" % [ahead, cars])
	return ""


func _check_helicopter() -> String:
	WantedSystem.set_level(5, _player.global_position)
	await _ticks(60 * 12)
	var heli: PoliceHelicopter = _police.get_helicopter()
	if heli == null:
		return "no helicopter at level 5"
	var flat: float = Vector2(heli.global_position.x - _player.global_position.x, heli.global_position.z - _player.global_position.z).length()
	if flat > 70.0 or heli.global_position.y < 20.0:
		return "the helicopter should be overhead (%.0f m away, %.0f m up)" % [flat, heli.global_position.y]
	var light: SpotLight3D = heli.get_searchlight()
	var aim: Vector3 = -light.global_basis.z
	var to_player: Vector3 = (_player.global_position - light.global_position).normalized()
	if aim.dot(to_player) < 0.9:
		return "the searchlight should point at the player"
	WantedSystem.clear()
	_note("level 5: the helicopter flies in overhead (%.0f m away, %.0f m up) with its searchlight on the player" % [flat, heli.global_position.y])
	return ""


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
