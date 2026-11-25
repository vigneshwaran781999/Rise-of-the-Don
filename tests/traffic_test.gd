extends Node
## Traffic test (per-feature test scene, M4). Loads the real game in Old Town and lets the
## traffic manager fill the streets (density, cars moving, far cars removed), then switches
## spawning off and sets up situations by hand: a red light then green, a give-way line, a
## queue behind a parked car on a one-lane road (keeps its distance, honks), passing a parked
## car on a two-lane road, and the pause after a crash. Run from the project root:
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/traffic_test.tscn
## Prints "TRAFFIC TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const FRONT: float = 2.35            # sedan centre to front bumper (TrafficDriver.FRONT_OFFSET)
const REAR: float = 2.3              # sedan centre to rear bumper
## On the south sidewalk of the gopuram road, out of the traffic's way.
const PLAYER_SPOT := Vector3(70.0, 0.3, 8.5)
## The M3 sedan parked in the outer westbound lane of the gopuram road, and a lane node behind it.
const PARKED_SEDAN: String = "World/Vehicles/Sedan"
const BEHIND_PARKED := Vector3(76.0, 0.0, 4.5)

var _catcher: ErrorCatcher
var _game: Node
var _traffic: TrafficManager
var _graph: LaneGraph
var _player: PlayerController
var _prev: Array[PackedInt32Array] = []   # predecessors of every lane node
var _extra: Array[Node] = []              # parked cars made by the test
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	_game = GAME.instantiate()
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_traffic = _game.get_node("Traffic") as TrafficManager
	_player = _game.get_node("Player") as PlayerController
	_graph = (_game.get_node("World") as CityWorld).get_lane_graph()
	var people := _game.get_node("Pedestrians") as PedestrianManager
	people.enabled = false     # cars only: people stepping into the road would make it random
	people.clear()
	_player.global_position = PLAYER_SPOT
	_player.reset_physics_interpolation()
	_build_predecessors()
	var steps: Array[Callable] = [
		_check_population, _check_density, _check_far_cars_removed, _check_red_light,
		_check_give_way, _check_queue_and_horn, _check_pass_parked, _check_crash_pause,
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
	print("TRAFFIC REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("TRAFFIC TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


# --------------------------------------------------------------------------- the manager

func _check_population() -> String:
	Settings.set_density(&"traffic_density", 1)
	var target: int = _traffic.target_count()
	var frames: int = 0
	while _traffic.get_count() < target and frames < 60 * 30:
		await get_tree().physics_frame
		frames += 1
	if _traffic.get_count() < target:
		return "only %d of %d cars after 30 s at medium density" % [_traffic.get_count(), target]
	for car: VehicleController in _traffic.get_cars():
		var nearest: int = _graph.nearest(car.global_position)
		var off: float = _flat(_graph.get_position(nearest)).distance_to(_flat(car.global_position))
		if off > 7.0:
			return "%s appeared %.1f m away from any lane" % [car.name, off]
	var crashes: Array[int] = [0]
	for car: VehicleController in _traffic.get_cars():
		(car.get_node("Damage") as VehicleDamage).impacted.connect(func(kmh: float, _damage: float) -> void:
			if kmh > 15.0:
				crashes[0] += 1)
	var samples: int = 0
	var moving: int = 0
	var fastest: float = 0.0
	for second: int in 20:
		await _ticks(60)
		for car: VehicleController in _traffic.get_cars():
			if car.global_position.y < -1.0:
				return "%s fell through the world at %s" % [car.name, car.global_position]
			samples += 1
			moving += 1 if car.get_speed_kmh() > 5.0 else 0
			fastest = maxf(fastest, car.get_speed_kmh())
	var share: float = float(moving) / maxf(samples, 1.0)
	_note("medium density: %d cars within %.1f s, all on lanes; over 20 s %.0f%% of samples moving, fastest %.0f km/h, %d crashes over 15 km/h" % [
		target, frames / 60.0, share * 100.0, fastest, crashes[0]])
	if share < 0.5:
		return "only %.0f%% of car samples were moving: traffic is jammed" % (share * 100.0)
	if fastest > 60.0:
		return "a car reached %.0f km/h; Old Town limits are 50 km/h at most" % fastest
	if crashes[0] > 3:
		return "%d crashes over 15 km/h in 20 s of normal traffic" % crashes[0]
	return ""


func _check_density() -> String:
	var counts: Array[int] = []
	for level: int in [0, 2, 1]:
		Settings.set_density(&"traffic_density", level)
		var target: int = _traffic.target_count()
		var frames: int = 0
		while _traffic.get_count() != target and frames < 60 * 40:
			await get_tree().physics_frame
			frames += 1
		if _traffic.get_count() != target:
			return "at %s density there are %d cars, expected %d" % [Settings.DENSITY_NAMES[level], _traffic.get_count(), target]
		counts.append(target)
	_note("density low %d -> high %d -> medium %d cars, each reached by adding or removing cars out of view" % counts)
	return ""


func _check_far_cars_removed() -> String:
	var here: Vector3 = _player.global_position
	var far_node: int = -1
	for i: int in _graph.size():
		var d: float = _flat(_graph.get_position(i)).distance_to(_flat(here))
		if _graph.flags[i] == 0 and d > 175.0 and d < 190.0:
			far_node = i
			break
	if far_node < 0:
		return "no lane node 175-190 m from the player"
	var car: VehicleController = _traffic.spawn_at(far_node, 0.0)
	await _ticks(60)
	if is_instance_valid(car) and not car.is_queued_for_deletion():
		return "a car %.0f m from the player was not removed" % _flat(car.global_position).distance_to(_flat(here))
	_note("a car beyond the despawn ring (%.0f m) was removed within 1 s" % _traffic.tuning.traffic_despawn)
	_traffic.enabled = false
	_traffic.clear()
	await _ticks(5)
	return ""


# --------------------------------------------------------------------------- junctions

func _check_red_light() -> String:
	var stop: int = _find_stop(LaneGraph.Flag.SIGNALIZED, 4)
	if stop < 0:
		return "no signalized stop line near the player with 4 plain lane nodes before it"
	var sig: TrafficSignal = TrafficSignal.find(_graph.junction[stop])
	if sig == null:
		return "the signal of junction %d is not loaded" % _graph.junction[stop]
	var axis: int = _graph.signal_axis[stop]
	sig.set_time(_phase_start(sig, axis, TrafficSignal.Light.RED) + 0.1)
	var car: VehicleController = _traffic.spawn_at(_upstream(stop, 4), 8.0)
	var driver := car.get_node("Driver") as TrafficDriver
	var still: int = await _wait_stopped(car, 60 * 20)
	if still < 0:
		return "the car never stopped for the red light (reason '%s')" % driver.get_reason()
	var gap: float = _front_gap(car, stop)
	if driver.get_reason() != "red light":
		return "the car stopped for '%s', expected 'red light'" % driver.get_reason()
	if gap < -0.5 or gap > 6.0:
		return "the car stopped %.1f m before the stop line, expected 0-6 m" % gap
	if sig.get_light(axis) != TrafficSignal.Light.RED:
		return "the light changed before the car stopped (test timing)"
	sig.set_time(_phase_start(sig, axis, TrafficSignal.Light.GREEN) + 0.1)
	var frames: int = 0
	while _front_gap(car, stop) > -(FRONT + 3.0) and frames < 60 * 8:
		await get_tree().physics_frame
		frames += 1
	if frames >= 60 * 8:
		return "the car did not drive on within 8 s of the light turning green"
	_note("red light at junction %d: stopped %.1f m before the line; drove off %.1f s after green" % [
		_graph.junction[stop], gap, frames / 60.0])
	await _clear()
	return ""


func _check_give_way() -> String:
	var stop: int = _find_stop(LaneGraph.Flag.GIVE_WAY, 3)
	if stop < 0:
		return "no give-way line near the player with 3 plain lane nodes before it"
	var car: VehicleController = _traffic.spawn_at(_upstream(stop, 3), 6.0)
	var driver := car.get_node("Driver") as TrafficDriver
	var stopped_gap: float = INF
	var stopped_for: float = 0.0
	var frames: int = 0
	while _front_gap(car, stop) > -(FRONT + 3.0) and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
		if car.get_speed_kmh() < 2.0 and driver.get_reason() == "give way":
			stopped_for += 1.0 / 60.0
			stopped_gap = minf(stopped_gap, _front_gap(car, stop))
	if frames >= 60 * 20:
		return "the car never pulled out of the give-way line (reason '%s')" % driver.get_reason()
	if stopped_for < 0.5:
		return "the car didn't wait at the give-way line (held %.2f s)" % stopped_for
	if stopped_gap < -1.0 or stopped_gap > 5.0:
		return "the car waited %.1f m before the give-way line, expected 0-5 m" % stopped_gap
	_note("give way at junction %d: waited %.1f s, %.1f m before the line, then pulled out into the empty junction" % [
		_graph.junction[stop], stopped_for, stopped_gap])
	await _clear()
	return ""


# --------------------------------------------------------------------------- obstacles

func _check_queue_and_horn() -> String:
	# A one-lane road (no lane to pass in): a parked car mid-block, a traffic car behind it.
	var block: int = -1
	var here: Vector3 = _player.global_position
	for i: int in _graph.size():
		var d: float = _flat(_graph.get_position(i)).distance_to(_flat(here))
		if d < 30.0 or d > 140.0 or _graph.flags[i] != 0 or _graph.side_lane[i] >= 0 or _graph.speed_kmh[i] > 35.0:
			continue
		if _upstream(i, 2) >= 0:
			block = i
			break
	if block < 0:
		return "no straight one-lane stretch near the player"
	var parked: VehicleController = _park_at(block)
	await _ticks(30)
	var parked_at: Vector3 = parked.global_position
	var car: VehicleController = _traffic.spawn_at(_upstream(block, 2), 6.0)
	var driver := car.get_node("Driver") as TrafficDriver
	var still: int = await _wait_stopped(car, 60 * 15)
	if still < 0:
		return "the car never stopped behind the parked car"
	var gap: float = (parked.global_position - car.global_position).length() - FRONT - REAR
	if gap < 0.8 or gap > 5.0:
		return "the car stopped %.1f m behind the parked car, expected about %.1f m" % [gap, driver.tuning.stop_gap]
	var honked: bool = false
	for i: int in 60 * int(driver.tuning.honk_after + 3.0):
		await get_tree().physics_frame
		honked = honked or car.is_horn_on()
	var pushed: float = parked.global_position.distance_to(parked_at)
	if not honked:
		return "the car waited behind the parked car without honking"
	if pushed > 0.3:
		return "the car pushed the parked car %.2f m" % pushed
	if driver.is_passing():
		return "the car tried to pass on a one-lane road"
	_note("one-lane road: stopped %.1f m behind a parked car (reason '%s'), honked after %.0f s, never touched it" % [
		gap, driver.get_reason(), driver.tuning.honk_after])
	await _clear()
	return ""


func _check_pass_parked() -> String:
	var sedan := _game.get_node(PARKED_SEDAN) as VehicleController
	var sedan_at: Vector3 = sedan.global_position
	var start: int = _graph.nearest(BEHIND_PARKED)
	if _graph.side_lane[start] < 0:
		return "lane node %d behind the parked sedan has no neighbouring lane" % start
	var car: VehicleController = _traffic.spawn_at(start, 8.0)
	var driver := car.get_node("Driver") as TrafficDriver
	var passing_seen: bool = false
	var beside_offset: float = INF
	var frames: int = 0
	var along: Vector3 = (_graph.get_position(_graph.get_next(start)[0]) - _graph.get_position(start)).normalized()
	while (car.global_position - sedan_at).dot(along) < 8.0 and frames < 60 * 12:
		await get_tree().physics_frame
		frames += 1
		passing_seen = passing_seen or driver.is_passing()
		if absf((car.global_position - sedan_at).dot(along)) < 1.5:
			var side: Vector3 = car.global_position - sedan_at
			side -= along * side.dot(along)
			beside_offset = minf(beside_offset, Vector2(side.x, side.z).length())
	if frames >= 60 * 12:
		return "the car did not get past the parked sedan within 12 s (reason '%s', passing %s)" % [driver.get_reason(), driver.is_passing()]
	if not passing_seen:
		return "the car got past without changing lanes"
	if beside_offset < 2.5:
		return "the car went past only %.1f m to the side of the parked sedan" % beside_offset
	var pushed: float = sedan.global_position.distance_to(sedan_at)
	if pushed > 0.3:
		return "the passing car moved the parked sedan %.2f m" % pushed
	_note("two-lane road: changed lanes round the parked sedan, %.1f m to its side, past it in %.1f s" % [beside_offset, frames / 60.0])
	await _clear()
	return ""


func _check_crash_pause() -> String:
	var stop: int = _find_stop(LaneGraph.Flag.STOP_LINE, 4)
	var car: VehicleController = _traffic.spawn_at(_upstream(stop, 4), 7.0)
	var driver := car.get_node("Driver") as TrafficDriver
	await _ticks(30)
	(car.get_node("Damage") as VehicleDamage).impacted.emit(30.0, 5.0)
	await _ticks(2)
	if driver.get_reason() != "crash":
		return "after a 30 km/h impact the driver's reason is '%s', expected 'crash'" % driver.get_reason()
	var paused: int = 0
	while driver.get_reason() == "crash" and paused < 60 * 10:
		await get_tree().physics_frame
		paused += 1
	if paused / 60.0 < driver.tuning.crash_pause - 0.2:
		return "the crash pause lasted only %.1f s" % (paused / 60.0)
	_note("after a crash the driver stopped for %.1f s, then drove on" % (paused / 60.0))
	await _clear()
	return ""


# --------------------------------------------------------------------------- helpers

func _build_predecessors() -> void:
	_prev.resize(_graph.size())
	for i: int in _graph.size():
		_prev[i] = PackedInt32Array()
	for i: int in _graph.size():
		for n: int in _graph.get_next(i):
			_prev[n].append(i)


## The node `steps` nodes before `node` along a plain lane with no branches, or -1.
func _upstream(node: int, steps: int) -> int:
	var at: int = node
	for k: int in steps:
		if _prev[at].size() != 1:
			return -1
		at = _prev[at][0]
		if _graph.flags[at] != 0:
			return -1
	return at


## A stop line with `flag`, 30-130 m from the player, with `steps` plain lane nodes before it.
func _find_stop(flag: int, steps: int) -> int:
	var here: Vector3 = _player.global_position
	for i: int in _graph.size():
		if not _graph.has_flag(i, flag) or not _graph.has_flag(i, LaneGraph.Flag.STOP_LINE):
			continue
		var d: float = _flat(_graph.get_position(i)).distance_to(_flat(here))
		if d > 30.0 and d < 130.0 and _upstream(i, steps) >= 0:
			return i
	return -1


## Metres from the car's front bumper to the stop line at `stop` (negative once over it).
func _front_gap(car: VehicleController, stop: int) -> float:
	var line: Vector3 = _graph.get_position(stop)
	var direction: Vector3 = (line - _graph.get_position(_prev[stop][0]))
	direction.y = 0.0
	direction = direction.normalized()
	var front: Vector3 = car.global_position + car.global_basis.z * FRONT
	return (line - front).dot(direction)


## Seconds into the signal's cycle when `light` starts for `axis`.
func _phase_start(sig: TrafficSignal, axis: int, light: TrafficSignal.Light) -> float:
	var t: float = 0.25
	while t < sig.timing.cycle_seconds() * 2.0:
		if sig.light_at(t, axis) == light and sig.light_at(t - 0.25, axis) != light:
			return t
		t += 0.25
	return 0.0


## Frames until the car has stood still for a second, or -1 after `limit` frames.
func _wait_stopped(car: VehicleController, limit: int) -> int:
	var still: int = 0
	for f: int in limit:
		await get_tree().physics_frame
		still = still + 1 if car.get_speed_kmh() < 1.0 else 0
		if still >= 60:
			return f
	return -1


## A sedan parked on lane node `node`, facing along the lane, nobody driving it.
func _park_at(node: int) -> VehicleController:
	var car := _traffic.car_scene.instantiate() as VehicleController
	car.name = "TestParked%d" % _extra.size()
	_game.add_child(car)
	var direction: Vector3 = _graph.get_position(_graph.get_next(node)[0]) - _graph.get_position(node)
	direction.y = 0.0
	car.teleport(Transform3D(Basis.looking_at(-direction.normalized(), Vector3.UP), _graph.get_position(node) + Vector3.UP * 0.6))
	_extra.append(car)
	return car


func _clear() -> void:
	_traffic.clear()
	for node: Node in _extra:
		if is_instance_valid(node):
			node.queue_free()
	_extra.clear()
	await _ticks(10)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
