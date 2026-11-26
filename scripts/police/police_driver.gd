class_name PoliceDriver
extends RoadDriver
## Drives a police car (GDD §7) with the same controls as the player.
## - CHASE: along the roads (RoadRouter) towards the target, then straight at it once close,
##   leading a moving target, fast and ignoring signals; stops a few metres short of someone
##   on foot so officers can get out.
## - SEARCH: drives to random spots inside the search circle.
## - LEAVE: drives off to somewhere far away (the police manager removes it out of sight).
## Backs out when stuck (RoadDriver). Child of its car and its driver.

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

var _goal := Vector3.ZERO
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
	_reroute()
	if mode == Mode.LEAVE:
		var away: Vector3 = _car.global_position - target
		away.y = 0.0
		_goal = _car.global_position + (away.normalized() if away.length() > 1.0 else Vector3.FORWARD) * 220.0
	elif mode == Mode.SEARCH:
		_goal = _search_point()


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
		_reroute()
	var distance: float = _flat(here).distance_to(_flat(goal))
	var aim: Vector3
	var direct: bool = mode == Mode.CHASE and distance < DIRECT_RANGE
	if direct:
		aim = goal + target_velocity * clampf(distance / 20.0, 0.0, 0.8)
	else:
		aim = _follow_route(here, goal, delta)
	var steering: Vector2 = _steer_towards(here, aim)
	var speed: float = _car.get_forward_speed()
	var top: float = tuning.chase_speed_kmh / 3.6 if mode != Mode.SEARCH else 12.0
	var wanted: float = maxf(5.0, top * (1.0 - clampf(absf(steering.y) / 1.3, 0.0, 0.8)))
	if direct and target_on_foot:
		wanted = minf(wanted, sqrt(2.0 * 6.0 * maxf(distance - STOP_SHORT, 0.0)))
	_drive(speed, wanted, steering.x, delta)


func _search_point() -> Vector3:
	var centre: Vector3 = WantedSystem.last_known
	var radius: float = maxf(WantedSystem.zone_radius, 20.0)
	var angle: float = _rng.randf() * TAU
	var node: int = _router.nearest_node(centre + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.2, 1.0) * radius)
	return _router.graph.get_position(node) if node >= 0 else centre
