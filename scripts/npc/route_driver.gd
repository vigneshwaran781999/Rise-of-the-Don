class_name RouteDriver
extends RoadDriver
## Drives a car through `stops` in order along the roads, keeping to its own side, at an
## unhurried `speed_kmh` (slower round corners), and pulls up at the last stop (`arrived`). The
## car a mission has the player tail (FOLLOW). It doesn't wait at traffic lights. Child of its car.

signal arrived

const STOP_REACH: float = 9.0
## Braking towards the last stop, m/s².
const STOP_DECELERATION: float = 3.0

var stops := PackedVector3Array()
var speed_kmh: float = 40.0

var _next: int = 0
var _arrived: bool = false
var _halted: bool = false


func start(car: VehicleController, router: RoadRouter, route_stops: PackedVector3Array, kmh: float) -> void:
	_car = car
	_router = router
	_any_way = false
	stops = route_stops
	speed_kmh = kmh
	_next = 0
	_arrived = stops.is_empty()
	car.set_driver(self)


func has_arrived() -> bool:
	return _arrived


## Pulls up where it is and stays there (the mission failed).
func halt() -> void:
	_halted = true


## The stop it is heading for (stops.size() once arrived).
func get_next_stop() -> int:
	return _next


func _physics_process(delta: float) -> void:
	if _car == null:
		return
	if _arrived or _halted or _car.is_engine_disabled():
		_car.set_controls(0.0, 1.0, 0.0, false)
		return
	var here: Vector3 = _car.global_position
	var goal: Vector3 = stops[_next]
	var distance: float = _flat(here).distance_to(_flat(goal))
	if distance < STOP_REACH:
		_next += 1
		_reroute()
		if _next >= stops.size():
			_arrived = true
			_car.set_controls(0.0, 1.0, 0.0, false)
			arrived.emit()
			return
		goal = stops[_next]
		distance = _flat(here).distance_to(_flat(goal))
	var steering: Vector2 = _steer_towards(here, _follow_route(here, goal, delta))
	var top: float = speed_kmh / 3.6
	var wanted: float = maxf(3.0, top * (1.0 - clampf(absf(steering.y) / 1.3, 0.0, 0.7)))
	if _next == stops.size() - 1:
		wanted = minf(wanted, sqrt(2.0 * STOP_DECELERATION * maxf(distance - STOP_REACH * 0.5, 0.0)) + 1.0)
	_drive(_car.get_forward_speed(), wanted, steering.x, delta)
