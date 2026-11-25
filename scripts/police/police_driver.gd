class_name PoliceDriver
extends Node3D
## Drives a police car (GDD §7) with the same controls as the player.
## - CHASE: along the roads (RoadRouter) towards the target, then straight at it once close,
##   leading a moving target, fast and ignoring signals; stops a few metres short of someone
##   on foot so officers can get out.
## - SEARCH: drives to random spots inside the search circle.
## - LEAVE: drives off to somewhere far away (the police manager removes it out of sight).
## Backs out when stuck. Child of its car and its driver.

enum Mode { CHASE, SEARCH, LEAVE }

const FRONT_OFFSET: float = 2.35
const DIRECT_RANGE: float = 38.0
const STOP_SHORT: float = 7.0

var mode: Mode = Mode.CHASE
## Where the chase goes (the player, or where they were last seen) and how that is moving.
var target := Vector3.ZERO
var target_velocity := Vector3.ZERO
## The target is a person on foot (stop short of them).
var target_on_foot: bool = false
var tuning: WantedTuning

var _car: VehicleController
var _router: RoadRouter
var _route := PackedVector3Array()
var _index: int = 0
var _route_timer: float = 0.0
var _goal := Vector3.ZERO
var _wheelbase: float = 2.65
var _stuck: float = 0.0
var _reverse: float = 0.0
var _reverse_steer: float = 0.0
var _forward_time: float = 0.0
var _rng := RandomNumberGenerator.new()


func start(car: VehicleController, router: RoadRouter, wanted_tuning: WantedTuning, seed_value: int) -> void:
	_car = car
	_router = router
	tuning = wanted_tuning
	_rng.seed = seed_value
	car.set_driver(self)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	_route = PackedVector3Array()
	_route_timer = 0.0
	if mode == Mode.LEAVE:
		var away: Vector3 = _car.global_position - target
		away.y = 0.0
		_goal = _car.global_position + (away.normalized() if away.length() > 1.0 else Vector3.FORWARD) * 220.0
	elif mode == Mode.SEARCH:
		_goal = _search_point()


func get_route() -> PackedVector3Array:
	return _route


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	if _car.is_engine_disabled():
		_car.set_controls(0.1, 1.0, 0.0, false)
		return
	var here: Vector3 = _car.global_position
	var goal: Vector3 = target if mode == Mode.CHASE else _goal
	if mode == Mode.SEARCH and _flat(here).distance_to(_flat(_goal)) < 12.0:
		_goal = _search_point()
		_route = PackedVector3Array()
	var distance: float = _flat(here).distance_to(_flat(goal))
	var aim: Vector3
	var direct: bool = mode == Mode.CHASE and distance < DIRECT_RANGE
	if direct:
		aim = goal + target_velocity * clampf(distance / 20.0, 0.0, 0.8)
	else:
		aim = _follow_route(here, goal, delta)
	var local: Vector3 = _car.global_transform.affine_inverse() * aim
	var alpha: float = atan2(local.x, maxf(local.z, 0.1))
	var look: float = maxf(_flat(here).distance_to(_flat(aim)), 4.0)
	var steer: float = clampf(atan2(2.0 * _wheelbase * sin(alpha), look) / maxf(_car.get_steer_lock(), 0.01), -1.0, 1.0)
	if local.z < 0.0:
		steer = signf(local.x) if absf(local.x) > 0.1 else 1.0     # target behind: turn round
		# Too tight to turn round on the move: a three-point turn (back up steering the other way).
		if _reverse <= 0.0 and _forward_time > 1.2 and absf(_car.get_forward_speed()) < 3.0:
			_reverse = 1.5
			_reverse_steer = -steer
	var speed: float = _car.get_forward_speed()
	var top: float = tuning.chase_speed_kmh / 3.6 if mode != Mode.SEARCH else 12.0
	var wanted: float = maxf(5.0, top * (1.0 - clampf(absf(alpha) / 1.3, 0.0, 0.8)))
	if direct and target_on_foot:
		wanted = minf(wanted, sqrt(2.0 * 6.0 * maxf(distance - STOP_SHORT, 0.0)))
	_drive(speed, wanted, steer, delta)


## Follows a road route to `goal`, recalculated now and then; returns a point a little way along it.
func _follow_route(here: Vector3, goal: Vector3, delta: float) -> Vector3:
	_route_timer -= delta
	if _route.is_empty() or _route_timer <= 0.0:
		_route = _router.route_any_way(here, goal)
		_route.insert(0, here)
		_route.append(goal)
		_index = 1
		_route_timer = 1.5
		# Skip route points just behind the car (the nearest lane node may be one).
		var forward: Vector3 = _car.global_basis.z
		while _index < _route.size() - 1 and (_route[_index] - here).dot(forward) < 0.0 \
				and _flat(here).distance_to(_flat(_route[_index])) < 12.0:
			_index += 1
	if _route.size() < 2:
		return goal
	# Move on to the next segment once the car is past the end of the current one.
	_index = clampi(_index, 1, _route.size() - 1)
	while _index < _route.size() - 1:
		var seg: Vector3 = _route[_index] - _route[_index - 1]
		if (here - _route[_index]).dot(seg) <= 0.0 and _flat(here).distance_to(_flat(_route[_index])) > 4.0:
			break
		_index += 1
	# Look ahead along the road itself (not straight across a corner): from the car's spot on the
	# current segment, a distance that grows with speed.
	var a: Vector3 = _route[_index - 1]
	var b: Vector3 = _route[_index]
	var t: float = clampf((here - a).dot(b - a) / maxf((b - a).length_squared(), 0.01), 0.0, 1.0)
	var from: Vector3 = a.lerp(b, t)
	var left: float = clampf(5.0 + maxf(_car.get_forward_speed(), 0.0) * 0.45, 5.0, 14.0)
	for k: int in range(_index, _route.size()):
		var step: float = _flat(from).distance_to(_flat(_route[k]))
		if step >= left:
			return from.lerp(_route[k], left / maxf(step, 0.01))
		left -= step
		from = _route[k]
	return _route[_route.size() - 1]


func _drive(speed: float, wanted: float, steer: float, delta: float) -> void:
	if _reverse > 0.0:
		_reverse -= delta
		_forward_time = 0.0
		_car.set_controls(0.0, 1.0, _reverse_steer, false)   # brake pedal at a standstill reverses
		return
	_forward_time += delta
	var error: float = wanted - speed
	if wanted < 0.5 and speed < 1.0:
		_car.set_controls(0.1, 1.0, steer, false)
		_stuck = 0.0
		return
	if error > 0.3:
		_car.set_controls(clampf(error * 0.5, 0.3, 1.0), 0.0, steer, false)
	elif error < -1.5:
		_car.set_controls(0.1, clampf(-error * 0.25, 0.2, 1.0), steer, false)
	else:
		_car.set_controls(0.15, 0.0, steer, false)
	# Wedged against something: back out for a moment.
	_stuck = _stuck + delta if absf(speed) < 0.8 and wanted > 3.0 else 0.0
	if _stuck > 1.6:
		_stuck = 0.0
		_reverse = 1.3
		_reverse_steer = -steer


func _search_point() -> Vector3:
	var centre: Vector3 = WantedSystem.last_known
	var radius: float = maxf(WantedSystem.zone_radius, 20.0)
	var angle: float = _rng.randf() * TAU
	var node: int = _router.nearest_node(centre + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.2, 1.0) * radius)
	return _router.graph.get_position(node) if node >= 0 else centre


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
