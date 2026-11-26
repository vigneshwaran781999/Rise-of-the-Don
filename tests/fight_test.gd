extends Node
## Fight test (per-feature test scene, M7 fists, death and the hospital). Runs the real game scene
## (traffic and pedestrians off) on an Old Town sidewalk and checks:
## - the punch: the Attack input throws one (the PUNCH state, the right arm thrown out), and the
##   player can't punch again until it is over;
## - pedestrians: a blow makes them reel back and is an assault (heat); a quick second blow floors
##   them; people nearby run; wanted level 1 after two;
## - police officers: punching one is assaulting an officer; three blows floor them;
## - a fighter: chases, winds up and punches (the player is hurt, the HUD flashes red); a punch
##   during the wind-up breaks it; four blows knock them out for good;
## - knocked out: the player goes down, the HOSPITALISED card and a bill, awake at the nearest
##   hospital (the Old Town clinic) at full health, the police gone, the running mission failed;
##   each district's nearest hospital.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/fight_test.tscn
## Prints "FIGHT TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const FIGHTER: PackedScene = preload("res://scenes/npc/fighter.tscn")
## The north sidewalk of the east gopuram road, the player facing east along it.
const SPOT := Vector3(70.0, 0.3, -8.0)
const EAST := Vector3(1.0, 0.0, 0.0)

var _catcher: ErrorCatcher
var _game: GameSession
var _player: PlayerController
var _fists: PlayerFists
var _people: PedestrianManager
var _police: PoliceManager
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
	_fists = _player.get_node("Fists") as PlayerFists
	_people = _game.get_node("Pedestrians") as PedestrianManager
	_police = _game.get_node("Police") as PoliceManager
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	_people.enabled = false
	_people.clear()
	MissionManager.quit_mission()
	var steps: Array[Callable] = [
		_check_navmesh, _check_punch, _check_pedestrian, _check_officer, _check_fighter, _check_hospital,
		_check_hospitals_by_district,
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
	print("FIGHT REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("FIGHT TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


## Waits for the sidewalk's navmesh (it syncs on a thread in real time).
func _check_navmesh() -> String:
	_stand_at_spot()
	var map: RID = _player.get_world_3d().navigation_map
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000 and NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return "the navmesh never synchronised"
	while Time.get_ticks_msec() - started < 20000 and _flat(NavigationServer3D.map_get_closest_point(map, SPOT)).distance_to(_flat(SPOT)) > 0.8:
		await get_tree().physics_frame
	if _flat(NavigationServer3D.map_get_closest_point(map, SPOT)).distance_to(_flat(SPOT)) > 0.8:
		return "no navmesh on the test sidewalk"
	return ""


func _check_punch() -> String:
	_stand_at_spot()
	await _ticks(20)
	var figure := _player.get_node("Model/Figure") as PlayerFigure
	_press(&"attack", true)
	await _ticks(2)
	_press(&"attack", false)
	if _player.state != PlayerController.State.PUNCH:
		return "the Attack input should throw a punch (state %s)" % _player.get_state_name()
	if _fists.punch():
		return "a second punch shouldn't start while the first is under way"
	# How far the right fist gets in front of the player (the skeleton, posed by the animation).
	var skeleton: Skeleton3D = figure.get_skeleton()
	var hand: int = skeleton.find_bone("RightHand")
	var rest_reach: float = _reach(skeleton, hand)
	var arm: float = 0.0
	var playing: bool = false
	for i: int in 40:
		arm = maxf(arm, _reach(skeleton, hand))
		playing = playing or figure.is_playing(&"punch")
		await get_tree().process_frame
	if _player.state == PlayerController.State.PUNCH:
		return "the punch should be over after 0.7 s"
	if not playing or arm < 0.45:
		return "the right fist should be thrown out in front in the punch animation (playing %s, reach %.2f m, at rest %.2f m)" % [playing, arm, rest_reach]
	var guard: float = figure.get_guard()
	if guard < 0.5:
		return "the fists should stay up for a moment after a punch (guard %.2f)" % guard
	_note("Attack throws a punch (PUNCH state, the punch animation: the fist reaches %.2f m in front, %.2f m at rest; fists up %.2f after); no second punch mid-swing" % [arm, rest_reach, guard])
	return ""


## How far in front of the player a bone is (along the way they face).
func _reach(skeleton: Skeleton3D, bone: int) -> float:
	var at: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	return (at - _player.global_position).dot(_player.get_facing())


func _check_pedestrian() -> String:
	WantedSystem.clear()
	_stand_at_spot()
	await _ticks(10)
	var victim: Pedestrian = _people.spawn_at(_nav(SPOT + EAST * 1.3))
	var bystander: Pedestrian = _people.spawn_at(_nav(SPOT - EAST * 6.0))
	victim.stand(30.0)
	bystander.stand(30.0)
	await _ticks(5)
	var states: Array[String] = []
	victim.state_changed.connect(func(_from: Pedestrian.State, to: Pedestrian.State) -> void: states.append(Pedestrian.State.keys()[to]))
	if not _fists.punch():
		return "couldn't throw a punch"
	await _ticks(20)
	if not "STAGGER" in states:
		return "a blow should make the pedestrian reel back (states %s)" % [states]
	var heat_one: float = WantedSystem.heat
	if absf(heat_one - WantedSystem.tuning.assault_heat) > 0.01 or WantedSystem.level != 0:
		return "one punch should be an assault (heat %.2f, level %d)" % [heat_one, WantedSystem.level]
	await _until_punch_over()
	if not _fists.punch():
		return "couldn't throw a second punch"
	await _ticks(20)
	if victim.state != Pedestrian.State.KNOCKED:
		return "a quick second punch should floor them (state %s, states %s, %.1f m away)" % [
			victim.get_state_name(), states, _flat(victim.global_position).distance_to(_flat(_player.global_position))]
	if bystander.state != Pedestrian.State.FLEE:
		return "someone 6 m away should run from the fight (state %s)" % bystander.get_state_name()
	if WantedSystem.level != 1:
		return "two punches should make you wanted (level %d, heat %.2f)" % [WantedSystem.level, WantedSystem.heat]
	await _ticks(60 * 4)
	if victim.state == Pedestrian.State.KNOCKED:
		return "the pedestrian should get up again"
	_note("pedestrian: one punch makes them reel (assault, heat %.1f); a second floors them, a bystander runs, wanted level 1; up again and running %s" % [
		heat_one, victim.get_state_name()])
	_people.clear()
	WantedSystem.clear()
	_police.clear_all()
	return ""


func _check_officer() -> String:
	WantedSystem.clear()
	_stand_at_spot()
	await _ticks(10)
	var bust_seconds: float = WantedSystem.tuning.bust_seconds
	WantedSystem.tuning.bust_seconds = 999.0          # no arrest mid-test
	# Officers are about when you're wanted (at level 0 they walk off): level 1, one coming for you.
	WantedSystem.set_level(1, _player.global_position)
	var officer: PoliceOfficer = _police.spawn_officer_at(_nav(SPOT + EAST * 1.3))
	officer.rotation.y = -PI * 0.5                     # facing the player
	await _ticks(3)
	var levels: Array[int] = []
	var down: bool = false
	for blow: int in 3:
		_aim_at(officer)
		if not _fists.punch():
			WantedSystem.tuning.bust_seconds = bust_seconds
			return "couldn't throw punch %d" % (blow + 1)
		await _until_punch_over()
		levels.append(WantedSystem.level)
		down = officer.is_down()
	WantedSystem.tuning.bust_seconds = bust_seconds
	_police.clear_all()
	WantedSystem.clear()
	if levels[0] < 2:
		return "punching an officer should be assaulting an officer (level %d after one blow)" % levels[0]
	if not down:
		return "three punches should floor an officer"
	_note("officer: one punch is assaulting an officer (level %d), three floor them (levels %s)" % [levels[0], levels])
	return ""


func _check_fighter() -> String:
	_stand_at_spot()
	_player.stats.set_health(_player.stats.get_max_health())
	await _ticks(10)
	var fighter := FIGHTER.instantiate() as Fighter
	_game.add_child(fighter)
	fighter.global_position = _nav(SPOT + EAST * 6.0) + Vector3.UP * 0.05
	fighter.attack(_player)
	var defeated: Array[bool] = [false]
	fighter.defeated.connect(func(_f: Fighter) -> void: defeated[0] = true)
	var health: float = _player.stats.health
	var wound_up: bool = false
	var flash: float = 0.0
	var hit_after: float = 0.0
	for f: int in 60 * 10:
		await get_tree().physics_frame
		wound_up = wound_up or fighter.state == Fighter.State.WINDUP
		if _player.stats.health < health:
			hit_after = f / 60.0
			await _frames(2)
			flash = _game.hud.get_hurt_flash()
			break
	if hit_after == 0.0:
		return "the fighter should land a punch within 10 s (state %s, %.1f m away)" % [
			fighter.get_state_name(), _flat(fighter.global_position).distance_to(_flat(_player.global_position))]
	if not wound_up:
		return "the fighter should wind up before the punch"
	var damage: float = health - _player.stats.health
	if flash < 0.1:
		return "the HUD should flash red when the player is hurt (%.2f)" % flash
	# Hit first: a punch during the wind-up breaks it.
	var broke: bool = false
	for attempt: int in 4:
		while fighter.state != Fighter.State.WINDUP:
			await get_tree().physics_frame
		_aim_at(fighter)
		var before: float = _player.stats.health
		_fists.punch()
		await _ticks(14)
		if fighter.state == Fighter.State.STAGGER:
			await _ticks(20)
			if _player.stats.health < before:
				return "a broken wind-up shouldn't still land a blow"
			broke = true
			break
	if not broke:
		return "punching a fighter mid-wind-up should stagger them"
	var blows: int = 1
	for i: int in 12:
		if fighter.is_down():
			break
		await _until_punch_over()
		_aim_at(fighter)
		if _flat(fighter.global_position).distance_to(_flat(_player.global_position)) > 1.8:
			await _ticks(20)            # let them come back in
			continue
		if _fists.punch():
			await _ticks(14)
			blows += 1
	if not fighter.is_down() or not defeated[0]:
		return "the fighter should be knocked out by repeated punches (health %.0f after %d blows)" % [fighter.get_health(), blows]
	var health_after: float = _player.stats.health
	await _ticks(60 * 3)
	if not fighter.is_down() or _player.stats.health < health_after:
		return "a knocked-out fighter should stay down and stop fighting"
	_note("fighter: closes in, winds up and lands a punch after %.1f s (-%.0f health, red flash %.2f); a punch mid-wind-up staggers them; knocked out after %d blows and stays down" % [
		hit_after, damage, flash, blows])
	fighter.queue_free()
	return ""


func _check_hospital() -> String:
	_stand_at_spot()
	await _ticks(10)
	EconomyManager.set_cash(5000)
	var cash: int = EconomyManager.cash
	var tuning: PlayerTuning = _player.tuning
	var expected_fee: int = maxi(tuning.hospital_fee_min, int(cash * tuning.hospital_fee_share))
	if not MissionManager.is_active():
		MissionManager.start(&"welcome")
	await _ticks(10)
	var mission_running: bool = MissionManager.is_active()
	_stand_at_spot()                  # the mission starts you at the bus stand: back to the test spot
	await _ticks(10)
	WantedSystem.set_level(1, _player.global_position)
	_player.stats.apply_damage(_player.stats.health - 8.0)     # hurt (so health doesn't regenerate yet)
	var fighter := FIGHTER.instantiate() as Fighter
	_game.add_child(fighter)
	fighter.global_position = _nav(SPOT + EAST * 2.5) + Vector3.UP * 0.05
	fighter.attack(_player)
	var died: Array[bool] = [false]
	_player.died.connect(func() -> void: died[0] = true, CONNECT_ONE_SHOT)
	for f: int in 60 * 10:
		await get_tree().physics_frame
		if died[0]:
			break
	if not died[0] or not _player.is_down():
		return "a blow at 8 health should knock the player out (health %.0f, state %s; player at %s, fighter %s at %s, mission %s)" % [
			_player.stats.health, _player.get_state_name(), _player.global_position, fighter.get_state_name(), fighter.global_position,
			MissionManager.get_active().id if MissionManager.is_active() else &"none"]
	var fell_at: Vector3 = _player.global_position
	var hospital: Transform3D = _game.world.data.nearest_hospital(fell_at)
	if hospital.origin == Vector3.ZERO:
		return "the city has no hospital"
	var screen := _game.get_node("Hospital") as HospitalScreen
	for i: int in 60 * 5:
		if screen.is_showing():
			break
		await get_tree().process_frame
	if not screen.is_showing() or not get_tree().paused:
		return "the HOSPITALISED card should show, the game held still"
	var bill: String = screen.get_amount_text()
	if not EconomyManager.format(expected_fee) in bill:
		return "the card should show the bill %s (shows '%s')" % [EconomyManager.format(expected_fee), bill]
	while screen.is_showing():
		await get_tree().process_frame
	await _ticks(10)
	if _flat(_player.global_position).distance_to(_flat(hospital.origin)) > 3.0:
		return "the player should wake at the nearest hospital %s (at %s)" % [hospital.origin, _player.global_position]
	if _player.is_down() or _player.stats.health < _player.stats.get_max_health() - 0.01:
		return "the player should be up at full health (state %s, health %.0f)" % [_player.get_state_name(), _player.stats.health]
	if EconomyManager.cash != cash - expected_fee:
		return "the bill should be %d (cash %d -> %d)" % [expected_fee, cash, EconomyManager.cash]
	if WantedSystem.is_wanted() or not _police.get_officers().is_empty():
		return "after hospital the record and the streets should be clear"
	if mission_running:
		var failed_screen := _game.get_node("MissionFailed") as MissionFailedScreen
		for i: int in 120:
			if failed_screen.is_open():
				break
			await get_tree().process_frame
		if failed_screen.get_reason_shown() != "You were hospitalised.":
			return "the running mission should fail with 'You were hospitalised.' (got '%s')" % failed_screen.get_reason_shown()
		failed_screen.quit_mission()
		await _frames(3)
	var region: String = _game.world.data.get_region_name(_game.world.data.region_at(hospital.origin))
	_note("knocked out at %d health: down, HOSPITALISED card with the bill %s, awake at the %s hospital door %.0f m away at full health, record clean%s" % [
		8, EconomyManager.format(expected_fee), region, _flat(fell_at).distance_to(_flat(hospital.origin)),
		", the mission fails" if mission_running else ""])
	fighter.queue_free()
	return ""


func _check_hospitals_by_district() -> String:
	var city: CityData = _game.world.data
	if city.hospitals.size() < 2:
		return "the city should have a clinic in Old Town and a hospital Downtown (%d)" % city.hospitals.size()
	var found: PackedStringArray = []
	for at: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -512.0), Vector3(512.0, 0.0, -512.0), Vector3(-512.0, 0.0, 512.0)]:
		var door: Transform3D = city.nearest_hospital(at)
		var region: String = city.get_region_name(city.region_at(door.origin))
		if city.surface_at(door.origin) != &"paved":
			return "the hospital door at %s should be on the sidewalk (%s)" % [door.origin, city.surface_at(door.origin)]
		found.append("%s -> %s" % [city.get_region_name(city.region_at(at)), region])
	if not found[0].ends_with("Old Town") or not found[1].ends_with("Downtown"):
		return "Old Town's nearest hospital should be its clinic and Downtown's its hospital (%s)" % ", ".join(found)
	_note("nearest hospital: %s" % ", ".join(found))
	return ""


# --------------------------------------------------------------------------- helpers

func _stand_at_spot() -> void:
	_game.place_player(Transform3D(Basis(Vector3.UP, -PI * 0.5), SPOT))


## Turns the player to face `node`.
func _aim_at(node: Node3D) -> void:
	var to: Vector3 = node.global_position - _player.global_position
	_player.model.rotation.y = atan2(-to.x, -to.z)


func _until_punch_over() -> void:
	while _player.state == PlayerController.State.PUNCH:
		await get_tree().physics_frame
	await get_tree().physics_frame


func _nav(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(_player.get_world_3d().navigation_map, point)


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


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
