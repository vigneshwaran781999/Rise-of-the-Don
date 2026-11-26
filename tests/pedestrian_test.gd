extends Node
## Pedestrian test (per-feature test scene, M4). Loads the real game in Old Town and lets the
## pedestrian manager fill the sidewalks (density, looks, everyone on the navmesh and nobody
## inside a building), then switches spawning off and sets up situations by hand: walking,
## two people chatting, sitting on a bench, running from an alarm, reacting to a crash and a
## horn, being knocked down by a car (which keeps going) and the player bumping into someone.
## Run from the project root:
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/pedestrian_test.tscn
## Prints "PEDESTRIAN TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
## South sidewalk of the gopuram road, next to the parked sedan (62, 4.75), facing west.
const WALK_SPOT := Vector3(60.0, 0.15, 8.0)
const SEDAN_PATH: String = "World/Vehicles/Sedan"
## Open stretch of Ring B (z = 112) used for the knock-down run, as in the smoke test.
const TEST_ROAD := Vector3(-20.0, 0.6, 109.0)

var _catcher: ErrorCatcher
var _game: Node
var _people: PedestrianManager
var _player: PlayerController
var _map: RID
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	_game = GAME.instantiate()
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_people = _game.get_node("Pedestrians") as PedestrianManager
	_player = _game.get_node("Player") as PlayerController
	_map = _player.get_world_3d().navigation_map
	var traffic := _game.get_node("Traffic") as TrafficManager
	traffic.enabled = false     # people only: cars would knock people down at random
	traffic.clear()
	var steps: Array[Callable] = [
		_check_population, _check_density, _check_walk, _check_talk, _check_sit, _check_flee,
		_check_crash_and_horn, _check_knockdown, _check_player_bump,
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
	_key(KEY_W, false)
	print("PEDESTRIAN REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("PEDESTRIAN TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


# --------------------------------------------------------------------------- the manager

func _check_population() -> String:
	Settings.set_density(&"pedestrian_density", 1)
	var target: int = _people.target_count()
	var frames: int = 0
	while _people.get_count() < target and frames < 60 * 30:
		await get_tree().physics_frame
		frames += 1
	if _people.get_count() < target:
		return "only %d of %d people after 30 s at medium density" % [_people.get_count(), target]
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var inside := PhysicsPointQueryParameters3D.new()
	inside.collision_mask = 1
	var states: Dictionary = {}
	var looks: Dictionary = {}
	var tops: Dictionary = {}
	for second: int in 10:
		await _ticks(60)
		for person: Pedestrian in _people.get_pedestrians():
			states[person.get_state_name()] = true
			if person.global_position.y < -0.5:
				return "%s sank to y=%.2f at %s" % [person.name, person.global_position.y, person.global_position]
			if person.state == Pedestrian.State.SIT:
				continue      # on a bench, off the navmesh
			inside.position = person.global_position + Vector3.UP
			if not space.intersect_point(inside, 1).is_empty():
				return "%s is inside solid geometry at %s" % [person.name, person.global_position]
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(_map, person.global_position)
			if _flat(closest).distance_to(_flat(person.global_position)) > 0.8:
				return "%s is %.1f m off the navmesh at %s" % [person.name, _flat(closest).distance_to(_flat(person.global_position)), person.global_position]
	for person: Pedestrian in _people.get_pedestrians():
		looks[person.model.look] = true
		tops[person.model.get_colour(&"top_color")] = true
	if looks.size() < 2 or tops.size() < 3:
		return "everyone looks alike (%d models, %d shirt colours)" % [looks.size(), tops.size()]
	if not states.has("WALK"):
		return "nobody walked (states seen: %s)" % states.keys()
	_note("medium density: %d people within %.1f s, all on the sidewalk navmesh and none inside buildings over 10 s; %d models, %d shirt colours; states seen %s" % [
		target, frames / 60.0, looks.size(), tops.size(), states.keys()])
	return ""


func _check_density() -> String:
	var counts: Array[int] = []
	for level: int in [0, 2, 1]:
		Settings.set_density(&"pedestrian_density", level)
		var target: int = _people.target_count()
		var frames: int = 0
		while _people.get_count() != target and frames < 60 * 40:
			await get_tree().physics_frame
			frames += 1
		if _people.get_count() != target:
			return "at %s density there are %d people, expected %d" % [Settings.DENSITY_NAMES[level], _people.get_count(), target]
		counts.append(target)
	_note("density low %d -> high %d -> medium %d people" % counts)
	_people.enabled = false
	_people.clear()
	await _ticks(5)
	return ""


# --------------------------------------------------------------------------- behaviours

func _check_walk() -> String:
	var person: Pedestrian = _people.spawn_at(_nav(WALK_SPOT))
	var start: Vector3 = person.global_position
	await _ticks(60 * 6)
	var moved: float = _flat(person.global_position).distance_to(_flat(start))
	if moved < 4.0:
		return "a wandering person moved only %.1f m in 6 s (state %s)" % [moved, person.get_state_name()]
	if absf(person.global_position.y - 0.15) > 0.25:
		return "the walker left the sidewalk surface (y=%.2f)" % person.global_position.y
	_note("a wandering person walked %.1f m along the sidewalk in 6 s" % moved)
	await _clear()
	return ""


func _check_talk() -> String:
	var pair: Array[Pedestrian] = []
	for x: float in [60.0, 52.0, 44.0, 76.0]:
		pair = _people.spawn_pair(_nav(Vector3(x, 0.15, 8.0)))
		if pair.size() == 2:
			break
		await _clear()
	if pair.size() != 2:
		return "no room on the sidewalk for two people to chat"
	await _ticks(60)
	for k: int in 2:
		var me: Pedestrian = pair[k]
		var other: Pedestrian = pair[1 - k]
		if me.state != Pedestrian.State.TALK or me.get_partner() != other:
			return "%s is %s with partner %s, expected talking to %s" % [me.name, me.get_state_name(), me.get_partner(), other.name]
		var facing: float = me.global_basis.z.dot((other.global_position - me.global_position).normalized())
		if facing < 0.8:
			return "%s doesn't face their partner (dot %.2f)" % [me.name, facing]
		if me.global_position.y < 0.0:
			return "%s sank into the ground while talking (y=%.2f)" % [me.name, me.global_position.y]
	_note("two people chat face to face %.1f m apart" % pair[0].global_position.distance_to(pair[1].global_position))
	await _clear()
	return ""


func _check_sit() -> String:
	var seat: Node3D = null
	var here: Vector3 = _player.global_position
	for node: Node in get_tree().get_nodes_in_group(PedestrianManager.SIT_SPOTS):
		var s := node as Node3D
		if s.global_position.distance_to(here) < 120.0 and (seat == null or s.global_position.distance_to(here) < seat.global_position.distance_to(here)):
			seat = s
	if seat == null:
		return "no bench seat within 120 m of the player"
	var stand_point: Vector3 = seat.global_position + seat.global_basis.z * 0.65 + Vector3.UP * Pedestrian.SEAT_DROP
	var person: Pedestrian = _people.spawn_at(_nav(stand_point + seat.global_basis.z * 4.0))
	var claimed: Node3D = _people.claim_seat(person)
	if claimed == null:
		return "no seat could be claimed near the bench at %s" % seat.global_position
	person.go_sit(claimed)
	var frames: int = 0
	while person.state != Pedestrian.State.SIT and frames < 60 * 15:
		await get_tree().physics_frame
		frames += 1
	if person.state != Pedestrian.State.SIT:
		return "the person never sat down (state %s, %.1f m from the seat)" % [person.get_state_name(), person.global_position.distance_to(claimed.global_position)]
	await _ticks(30)
	if person.global_position.distance_to(claimed.global_position) > 0.2:
		return "the person sits %.2f m from the seat" % person.global_position.distance_to(claimed.global_position)
	if not _people.is_seat_taken(claimed):
		return "the seat is not marked as taken"
	var sit_pose: StringName = person.model.get_state()
	if sit_pose != &"sit":
		return "the person is on the seat but not in the sitting pose (%s)" % sit_pose
	_people.alert(claimed.global_position + Vector3(3.0, 0.0, 0.0), 10.0, true)
	await _ticks(30)
	if person.state != Pedestrian.State.FLEE or _people.is_seat_taken(claimed):
		return "an alarm should make the sitter get up and run, freeing the seat (state %s)" % person.get_state_name()
	if person.global_position.y < 0.0:
		return "the person got up into the ground (y=%.2f)" % person.global_position.y
	_note("walked to a bench and sat down in %.1f s (on the seat, sitting pose); an alarm made them get up and run, freeing the seat" % (frames / 60.0))
	await _clear()
	return ""


func _check_flee() -> String:
	var danger := _nav(WALK_SPOT)
	var crowd: Array[Pedestrian] = []
	for offset: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(6, 0, 0)]:
		var person: Pedestrian = _people.spawn_at(_nav(WALK_SPOT + offset))
		person.stand(30.0)
		crowd.append(person)
	var far: Pedestrian = _people.spawn_at(_nav(WALK_SPOT + Vector3(40, 0, 0)))
	far.stand(30.0)
	await _ticks(10)
	var before: Array[float] = []
	for person: Pedestrian in crowd:
		before.append(_flat(person.global_position).distance_to(_flat(danger)))
	_people.alert(danger, 15.0, true)
	await _ticks(60 * 3)
	for k: int in crowd.size():
		var person: Pedestrian = crowd[k]
		var now: float = _flat(person.global_position).distance_to(_flat(danger))
		if person.state != Pedestrian.State.FLEE:
			return "%s didn't run from the alarm (state %s)" % [person.name, person.get_state_name()]
		if now < before[k] + 5.0:
			return "%s got only %.1f m further away in 3 s" % [person.name, now - before[k]]
	if far.state != Pedestrian.State.IDLE:
		return "someone 40 m away reacted to an alarm with a 15 m radius (state %s)" % far.get_state_name()
	_note("an alarm made the three people within 15 m run off (5+ m further away within 3 s); someone 40 m away carried on")
	await _clear()
	return ""


func _check_crash_and_horn() -> String:
	var sedan := _game.get_node(SEDAN_PATH) as VehicleController
	# A crash: everyone within 18 m runs.
	var near: Pedestrian = _people.spawn_at(_nav(sedan.global_position + Vector3(4.0, 0.0, 4.0)))
	near.stand(30.0)
	await _ticks(10)
	(sedan.get_node("Damage") as VehicleDamage).impacted.emit(35.0, 4.0)
	await _ticks(2)
	if near.state != Pedestrian.State.FLEE:
		return "a 35 km/h crash 6 m away didn't make someone run (state %s)" % near.get_state_name()
	await _clear()
	# A horn: people in front of the car step aside (not a panic).
	var ahead: Vector3 = sedan.global_position + sedan.global_basis.z * 5.0
	var front: Pedestrian = _people.spawn_at(_nav(ahead + Vector3(0.0, 0.0, 4.0)))
	front.stand(30.0)
	await _ticks(10)
	sedan.set_horn(true)
	await _ticks(2)
	sedan.set_horn(false)
	if front.state != Pedestrian.State.STEP_ASIDE:
		return "a horn right in front didn't make someone step aside (state %s)" % front.get_state_name()
	_note("a crash nearby makes people run; a horn makes people in front of the car step aside")
	await _clear()
	return ""


func _check_knockdown() -> String:
	var car := _game.get_node(SEDAN_PATH) as VehicleController
	var driver := Node3D.new()
	driver.name = "TestDriver"
	add_child(driver)
	var start := Transform3D(Basis(Vector3.UP, -PI * 0.5), TEST_ROAD + Vector3(14.0, 0.0, 0.0))   # facing -X
	car.teleport(start)
	car.set_driver(driver)
	await _ticks(20)
	var victim: Pedestrian = _people.spawn_at(Vector3(TEST_ROAD.x - 14.0, 0.05, TEST_ROAD.z))
	victim.stand(30.0)
	car.set_controls(1.0, 0.0, 0.0, false)
	var hit_speed: float = -1.0
	for f: int in 60 * 8:
		await get_tree().physics_frame
		if car.get_speed_kmh() > 32.0:
			car.set_controls(0.0, 0.0, 0.0, false)
		if victim.state == Pedestrian.State.KNOCKED:
			hit_speed = car.get_speed_kmh()
			break
	if hit_speed < 0.0:
		return "the car never knocked the person down (state %s, car at %s)" % [victim.get_state_name(), car.global_position]
	await _ticks(20)
	var after: float = car.get_speed_kmh()
	car.set_controls(0.1, 1.0, 0.0, false)      # both pedals: brake to a stop without reversing
	if after < hit_speed * 0.6:
		return "the car stopped dead on the person (%.0f -> %.0f km/h)" % [hit_speed, after]
	await _ticks(int(60 * (victim.tuning.knocked_time + 0.5)))
	if victim.state not in [Pedestrian.State.FLEE, Pedestrian.State.STEP_ASIDE] or victim.model.rotation.length() > 0.01:
		return "the person didn't get up and run after %.1f s (state %s)" % [victim.tuning.knocked_time, victim.get_state_name()]
	car.set_driver(null)
	driver.queue_free()
	_note("a car at %.0f km/h knocked a person down and rolled on at %.0f km/h; they got up after %.0f s and ran" % [
		hit_speed, after, victim.tuning.knocked_time])
	await _clear()
	return ""


func _check_player_bump() -> String:
	var spot: Vector3 = _nav(WALK_SPOT + Vector3(-10.0, 0.0, 0.0))
	var person: Pedestrian = _people.spawn_at(spot)
	person.stand(30.0)
	var start: Vector3 = _nav(spot + Vector3(4.0, 0.0, 0.0))
	_player.global_position = start + Vector3.UP * 0.1
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(20)
	var towards: Vector3 = person.global_position - _player.global_position
	_player.camera_rig.set_view_degrees(rad_to_deg(atan2(-towards.x, -towards.z)), -10.0)
	_player.camera_rig.snap_to_target()
	_key(KEY_W, true)
	var frames: int = 0
	while person.state == Pedestrian.State.IDLE and frames < 60 * 4:
		await get_tree().physics_frame
		frames += 1
	_key(KEY_W, false)
	if person.state != Pedestrian.State.STEP_ASIDE:
		return "walking into someone didn't make them step aside (state %s, %.1f m apart)" % [
			person.get_state_name(), _flat(person.global_position).distance_to(_flat(_player.global_position))]
	_note("the player walking into someone makes them step out of the way")
	await _clear()
	return ""


# --------------------------------------------------------------------------- helpers

## The closest navmesh point to `point` (after the map has synced).
func _nav(point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(_map, point)


func _clear() -> void:
	_people.clear()
	await _ticks(5)


func _key(code: Key, pressed: bool) -> void:
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
