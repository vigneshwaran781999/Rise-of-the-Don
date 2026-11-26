class_name RoadDriver
extends Node3D
## What every AI that drives a car somewhere particular shares (police cars, a mission's car on
## its route): following a road route from RoadRouter to a goal with a look-ahead along the road,
## steering towards a point (pure pursuit; turning round when it's behind, with a three-point turn
## when too tight), holding a speed with the same pedals as the player, and backing out when
## wedged. Subclasses decide where to go and how fast. Child of its car and its driver.

var _car: VehicleController
var _router: RoadRouter
## Route along lanes either way (police) or only the right way (everyone else).
var _any_way: bool = true
var _route := PackedVector3Array()
var _index: int = 0
var _route_timer: float = 0.0
var _wheelbase: float = 2.65
var _stuck: float = 0.0
var _reverse: float = 0.0
var _reverse_steer: float = 0.0
var _forward_time: float = 0.0


func get_route() -> PackedVector3Array:
	return _route


## Forgets the route (the goal changed).
func _reroute() -> void:
	_route = PackedVector3Array()
	_route_timer = 0.0


## Follows a road route to `goal`, recalculated now and then; returns a point a little way along it.
func _follow_route(here: Vector3, goal: Vector3, delta: float) -> Vector3:
	_route_timer -= delta
	if _route.is_empty() or _route_timer <= 0.0:
		_route = _router.route_any_way(here, goal) if _any_way else _router.route(here, goal, _car.global_basis.z)
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


## Steering (-1..1) towards `aim` from `here`, and the angle to it (radians, for slowing down).
## A point behind the car turns it round; too tight on the move, a three-point turn starts.
func _steer_towards(here: Vector3, aim: Vector3) -> Vector2:
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
	return Vector2(steer, alpha)


## Pedals for `wanted` m/s at `speed` m/s, steering `steer`; reverses out when wedged.
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


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
