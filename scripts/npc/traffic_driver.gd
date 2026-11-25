class_name TrafficDriver
extends Node3D
## AI driver for one traffic car (GDD §6): follows the lane graph and drives with the same
## controls as the player (VehicleController.set_controls).
## - Steering: pure pursuit towards a point a little way along its route.
## - Speed: the lane's limit, slowing early for tighter turns ahead, stopping at stop lines
##   for red (and catchable amber) lights, at give-way lines until the junction is clear, and
##   before turning right across oncoming traffic until it is clear.
## - Keeps its distance with forward sensor rays (cars, the player, pedestrians, anything solid).
## - Swerves into the other lane (roads with two lanes each way) to pass a parked or wrecked car.
## - Honks when held up, pauses after a crash. Lives as a child of its car and is its driver.

signal stuck_changed(stuck: bool)

const SENSOR_MASK: int = 1 | 2 | 4 | 8   # world, player, vehicles, pedestrians
const FRONT_OFFSET: float = 2.35        # car centre to front bumper
const ROUTE_AHEAD: int = 14

@export var tuning: DriverTuning

var graph: LaneGraph
## Seconds the car has been held up by something other than a red light (traffic manager reads it).
var held_for: float = 0.0

var _car: VehicleController
var _route := PackedInt32Array()
var _cursor: int = 0
var _rng := RandomNumberGenerator.new()
var _wheelbase: float = 2.65
var _passed_stop: int = -1
var _right_turn_at: Dictionary = {}    # stop-line node -> true when the chosen exit turns right
var _stopped_at_line: float = 0.0
var _released_at: int = -1           # give-way line we have waited at and may now cross
var _crash_pause: float = 0.0
var _honk_timer: float = 0.0
var _query := PhysicsRayQueryParameters3D.new()
var _shape_query := PhysicsShapeQueryParameters3D.new()
var _lane_query := PhysicsShapeQueryParameters3D.new()
var _reason: String = ""
var _ahead: Node3D                     # what the sensor rays hit nearest this frame
var _passing: Node3D                   # the parked car being passed (the rays ignore it meanwhile)


## Takes the wheel of `car` on lane node `node` (the car must already sit on that lane).
func start(car: VehicleController, lane_graph: LaneGraph, node: int, seed_value: int) -> void:
	_car = car
	graph = lane_graph
	_rng.seed = seed_value
	_route = PackedInt32Array([node])
	_cursor = 0
	var front: float = -INF
	var rear: float = INF
	for wheel: VehicleWheel3D in car.get_wheels():
		front = maxf(front, wheel.position.z)
		rear = minf(rear, wheel.position.z)
	_wheelbase = front - rear
	_query.collision_mask = SENSOR_MASK
	_query.exclude = [car.get_rid()]
	var sphere := SphereShape3D.new()
	sphere.radius = tuning.junction_clear_radius
	_shape_query.shape = sphere
	_shape_query.collision_mask = 2 | 4   # the player and other vehicles
	_shape_query.exclude = [car.get_rid()]
	var near := SphereShape3D.new()
	near.radius = tuning.pass_clear_behind + tuning.pass_distance
	_lane_query.shape = near
	_lane_query.collision_mask = 2 | 4
	_lane_query.exclude = [car.get_rid()]
	(car.get_node("Damage") as VehicleDamage).impacted.connect(_on_impacted)
	car.set_driver(self)
	_extend_route()


func get_route() -> PackedInt32Array:
	return _route.slice(_cursor)


## Why the car is slowing or stopped right now ("red light", "give way", "something ahead"...),
## for tests and the debug view. Empty while cruising.
func get_reason() -> String:
	return _reason


## True while swerving round a parked car.
func is_passing() -> bool:
	return _passing != null


func _physics_process(delta: float) -> void:
	if _car == null or graph == null:
		return
	if _car.is_engine_disabled():
		_car.set_controls(0.1, 1.0, 0.0, false)
		return
	_extend_route()
	_advance()
	_update_passing()
	var speed: float = _car.get_forward_speed()
	# Follow the path more tightly while swerving round a parked car.
	var per_speed: float = tuning.look_ahead_per_speed * (0.5 if _passing != null else 1.0)
	var look_ahead: float = clampf(tuning.look_ahead_min + maxf(speed, 0.0) * per_speed,
		tuning.look_ahead_min, tuning.look_ahead_max)
	var target: Vector3 = _point_ahead(look_ahead)
	var steer: float = _steer_towards(target, look_ahead)
	var wanted: float = _target_speed(speed, target, delta)
	_crash_pause = maxf(0.0, _crash_pause - delta)
	if _crash_pause > 0.0:
		wanted = 0.0
		_reason = "crash"
	_drive(speed, wanted, steer)
	_update_horn(delta, speed, wanted)


# --------------------------------------------------------------------------- route

func _extend_route() -> void:
	if _cursor > 6:
		_route = _route.slice(_cursor - 2)
		_cursor = 2
	while _route.size() - _cursor < ROUTE_AHEAD:
		var last: int = _route[_route.size() - 1]
		var options: PackedInt32Array = graph.get_next(last)
		if options.is_empty():
			return
		var pick: int = options[0]
		if options.size() > 1:
			pick = _choose_exit(last, options)
		_route.append(pick)


## Weighted choice at a junction: straight, left or right (U-turns only if nothing else).
func _choose_exit(from: int, options: PackedInt32Array) -> int:
	var incoming: Vector3 = _incoming_direction(from)
	var weights: Array[float] = []
	var total: float = 0.0
	var turns: Array[int] = []
	for option: int in options:
		var direction: Vector3 = graph.get_position(option) - graph.get_position(from)
		direction.y = 0.0
		var turn: int = 0
		if incoming.dot(direction.normalized()) < 0.85:
			turn = 1 if Vector3.UP.cross(incoming).dot(direction) > 0.0 else -1
		var w: float = [tuning.turn_weights.x, tuning.turn_weights.y, tuning.turn_weights.z][[0, 1, -1].find(turn)]
		if graph.has_flag(option, LaneGraph.Flag.U_TURN):
			w = 0.001
		weights.append(w)
		turns.append(turn)
		total += w
	var roll: float = _rng.randf() * total
	for i: int in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			if turns[i] == -1:
				_right_turn_at[from] = true
			return options[i]
	return options[options.size() - 1]


func _incoming_direction(node: int) -> Vector3:
	var i: int = _route.rfind(node)
	var direction: Vector3
	if i > 0:
		direction = graph.get_position(node) - graph.get_position(_route[i - 1])
	else:
		direction = _car.global_basis.z
	direction.y = 0.0
	return direction.normalized()


## Moves the cursor past route nodes the car has already driven by.
func _advance() -> void:
	var pos: Vector3 = _car.global_position
	while _cursor + 1 < _route.size():
		var a: Vector3 = graph.get_position(_route[_cursor])
		var b: Vector3 = graph.get_position(_route[_cursor + 1])
		var segment: Vector3 = b - a
		segment.y = 0.0
		var past: bool = segment.length_squared() < 0.0001 or (pos - b).dot(segment) > 0.0
		if not past:
			break
		_cursor += 1
		var reached: int = _route[_cursor]
		if graph.has_flag(reached, LaneGraph.Flag.STOP_LINE):
			_passed_stop = reached
			_stopped_at_line = 0.0
			_released_at = -1


## The point `distance` metres along the route from where the car is.
func _point_ahead(distance: float) -> Vector3:
	var pos: Vector3 = _car.global_position
	var a: Vector3 = graph.get_position(_route[_cursor])
	if _cursor + 1 >= _route.size():
		return a
	var b: Vector3 = graph.get_position(_route[_cursor + 1])
	var segment: Vector3 = b - a
	var t: float = clampf((pos - a).dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
	var here: Vector3 = a + segment * t
	var left: float = distance
	var k: int = _cursor + 1
	var from: Vector3 = here
	while k < _route.size():
		var to: Vector3 = graph.get_position(_route[k])
		var step: float = from.distance_to(to)
		if step >= left:
			return from + (to - from) * (left / maxf(step, 0.0001))
		left -= step
		from = to
		k += 1
	return from


## Distance along the route from the car to route[index] (route[index] ahead of the cursor).
func _distance_to(index: int) -> float:
	var pos: Vector3 = _car.global_position
	var total: float = Vector2(pos.x, pos.z).distance_to(_flat(graph.get_position(_route[_cursor + 1])))
	for k: int in range(_cursor + 1, index):
		total += _flat(graph.get_position(_route[k])).distance_to(_flat(graph.get_position(_route[k + 1])))
	return total


# --------------------------------------------------------------------------- driving

func _steer_towards(target: Vector3, look_ahead: float) -> float:
	var local: Vector3 = _car.global_transform.affine_inverse() * target
	var alpha: float = atan2(local.x, maxf(local.z, 0.1))
	var angle: float = atan2(2.0 * _wheelbase * sin(alpha), look_ahead)
	return clampf(angle / maxf(_car.get_steer_lock(), 0.01), -1.0, 1.0)


func _target_speed(speed: float, target: Vector3, delta: float) -> float:
	_reason = ""
	var a: float = tuning.comfort_brake
	var next: int = _route[mini(_cursor + 1, _route.size() - 1)]
	var wanted: float = graph.speed_kmh[next] / 3.6 * tuning.cruise_factor
	var horizon: float = speed * speed / (2.0 * a) + 25.0
	var k: int = _cursor + 1
	while k < _route.size():
		var d: float = _distance_to(k)
		if d > horizon:
			break
		var node: int = _route[k]
		var limit: float = graph.speed_kmh[node] / 3.6 * tuning.cruise_factor
		wanted = minf(wanted, sqrt(limit * limit + 2.0 * a * maxf(d - 3.0, 0.0)))
		if graph.has_flag(node, LaneGraph.Flag.STOP_LINE) and node != _passed_stop:
			var front_gap: float = d - FRONT_OFFSET - tuning.stop_line_margin
			var why: String = _must_stop(node, front_gap, speed, delta)
			if why != "":
				var allowed: float = sqrt(2.0 * a * maxf(front_gap, 0.0))
				if allowed < wanted:
					wanted = allowed
					_reason = why
			break   # only the next stop line matters
		k += 1
	var gap: float = _sense(target)
	if gap < tuning.pass_distance and _passing == null and _is_parked(_ahead) and _change_lane(_ahead, gap):
		return wanted     # the route now leads round it, and the rays ignore it until it is behind
	if gap < INF:
		var room: float = maxf(gap - tuning.stop_gap, 0.0)
		var allowed: float = minf(room / tuning.headway, sqrt(2.0 * tuning.hard_brake * room))
		if allowed < wanted:
			wanted = allowed
			_reason = "something ahead"
	return wanted


## Why the car must stop at this stop line ("" = it may go).
func _must_stop(node: int, front_gap: float, speed: float, delta: float) -> String:
	var junction: int = graph.junction[node]
	var waiting: bool = front_gap < 1.5 and speed < 0.5
	if graph.has_flag(node, LaneGraph.Flag.SIGNALIZED):
		var sig: TrafficSignal = TrafficSignal.find(junction)
		if sig != null:
			var light: int = sig.get_light(graph.signal_axis[node])
			if light == TrafficSignal.Light.RED:
				return "red light"
			if light == TrafficSignal.Light.AMBER and front_gap > speed * speed / (2.0 * tuning.hard_brake):
				return "amber light"
		if _right_turn_at.has(node) and not _junction_clear(junction):
			return "turning right across traffic"
		return ""
	var must_yield: bool = graph.has_flag(node, LaneGraph.Flag.GIVE_WAY)
	var lane_road: bool = graph.speed_kmh[node] <= 35.0
	if must_yield:
		if _released_at == node:
			# Already waited here; only hold back again if the junction fills up.
			return "" if _junction_clear(junction) else "give way"
		_stopped_at_line = _stopped_at_line + delta if waiting else 0.0
		if _stopped_at_line < tuning.give_way_wait or not _junction_clear(junction):
			return "give way"
		_released_at = node
		return ""
	if (lane_road or _right_turn_at.has(node)) and not _junction_clear(junction):
		return "junction busy"
	return ""


## Nobody in the junction box and no moving car about to arrive in it. Cars waiting at the other
## stop lines don't count (otherwise two give-way lines would wait for each other forever).
func _junction_clear(junction: int) -> bool:
	if junction < 0 or junction >= graph.junction_positions.size():
		return true
	var centre: Vector3 = graph.junction_positions[junction]
	_shape_query.transform = Transform3D(Basis.IDENTITY, centre + Vector3.UP)
	for hit: Dictionary in _car.get_world_3d().direct_space_state.intersect_shape(_shape_query, 16):
		var body := hit["collider"] as Node3D
		if body == null:
			continue
		var offset: Vector3 = centre - body.global_position
		offset.y = 0.0
		if offset.length() < tuning.junction_box_radius:
			return false
		var other := body as VehicleController
		if other != null:
			var velocity: Vector3 = other.linear_velocity
			velocity.y = 0.0
			var closing: float = velocity.dot(offset.normalized())
			if closing > 2.0 and offset.length() / closing < tuning.junction_arrival_time:
				return false
	return true


## Distance from the front bumper to the nearest thing in the way, or INF. Three rays: centre
## line and both front corners, aimed along the route.
func _sense(target: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _car.get_world_3d().direct_space_state
	var origin: Vector3 = _car.to_global(Vector3(0.0, -0.05, FRONT_OFFSET))
	var direction: Vector3 = target - origin
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = _car.global_basis.z
	direction = direction.normalized()
	var side: Vector3 = Vector3.UP.cross(direction) * 0.85
	var length: float = tuning.sensor_length + maxf(_car.get_forward_speed(), 0.0) * tuning.sensor_per_speed
	var best: float = INF
	_ahead = null
	for offset: Vector3 in [Vector3.ZERO, side, -side]:
		_query.from = origin + offset
		_query.to = origin + offset + direction * length
		var hit: Dictionary = space.intersect_ray(_query)
		if not hit.is_empty():
			var collider := hit["collider"] as Node3D
			# The road surface and kerbs are world geometry too; only count what stands up.
			if collider is StaticBody3D and (hit["normal"] as Vector3).y > 0.5:
				continue
			var d: float = origin.distance_to(hit["position"])
			if d < best:
				best = d
				_ahead = collider
	return best


# --------------------------------------------------------------------------- passing

## A car nobody is driving (parked, abandoned or wrecked) standing still.
func _is_parked(body: Node3D) -> bool:
	var other := body as VehicleController
	if other == null or other.linear_velocity.length() > 0.5:
		return false
	return other.get_driver() == null or other.is_engine_disabled()


## Moves the route into the other lane going the same way, to get round `blocker` `gap` metres
## ahead, if this road has one and nobody is in it from a little behind to beyond the blocker.
func _change_lane(blocker: Node3D, gap: float) -> bool:
	if graph.side_lane.size() != graph.size():
		return false
	# Pull out gradually, but be fully in the other lane by the time the car is alongside.
	var pull_out: float = clampf(gap * 0.6, 5.0, 12.0)
	for j: int in range(_cursor + 1, _route.size()):
		var node: int = _route[j]
		var side: int = graph.side_lane[node]
		if side < 0:
			return false     # the road ends (or narrows) before there is room to pull out
		if _distance_to(j) < pull_out:
			continue
		if not _lane_free(graph.get_position(side), gap):
			return false
		_route = _route.slice(0, _cursor + 1)
		_route.append(side)
		_extend_route()
		_passing = blocker
		_query.exclude = [_car.get_rid(), blocker.get_rid()]
		return true
	return false


## Nobody in the lane through `lane_point` (parallel to the car) from pass_clear_behind metres
## behind the car to a little beyond the obstacle `gap` metres ahead.
func _lane_free(lane_point: Vector3, gap: float) -> bool:
	var forward: Vector3 = _car.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	_lane_query.transform = Transform3D(Basis.IDENTITY, _car.global_position)
	for hit: Dictionary in _car.get_world_3d().direct_space_state.intersect_shape(_lane_query, 32):
		var body := hit["collider"] as Node3D
		if body == null:
			continue
		var along: float = (body.global_position - _car.global_position).dot(forward)
		var off_lane: Vector3 = body.global_position - lane_point
		off_lane -= forward * off_lane.dot(forward)
		off_lane.y = 0.0
		if off_lane.length() < 2.2 and along > -tuning.pass_clear_behind and along < gap + FRONT_OFFSET + 8.0:
			return false
	return true


## Stops ignoring the passed car once it is behind.
func _update_passing() -> void:
	if _passing == null:
		return
	if not is_instance_valid(_passing) or (_passing.global_position - _car.global_position).dot(_car.global_basis.z) < -5.0:
		_passing = null
		_query.exclude = [_car.get_rid()]


func _drive(speed: float, wanted: float, steer: float) -> void:
	var error: float = wanted - speed
	if wanted < 0.3 and speed < 1.0:
		_car.set_controls(0.1, 1.0, steer, false)          # both pedals: hold still, never reverse
	elif error < -0.6:
		_car.set_controls(0.1, clampf(-error * 0.3, 0.15, 1.0), steer, false)
	elif error > 0.2:
		_car.set_controls(clampf(error * tuning.speed_gain, 0.0, 1.0), 0.0, steer, false)
	else:
		_car.set_controls(0.0, 0.0, steer, false)


func _update_horn(delta: float, speed: float, wanted: float) -> void:
	var held: bool = speed < 0.5 and wanted < 0.5 and _reason != "red light" and _reason != "amber light"
	var was_stuck: bool = held_for >= tuning.honk_after
	held_for = held_for + delta if held else 0.0
	var stuck: bool = held_for >= tuning.honk_after
	if stuck != was_stuck:
		stuck_changed.emit(stuck)
	_honk_timer = maxf(0.0, _honk_timer - delta)
	if stuck and _honk_timer <= 0.0:
		_honk_timer = 4.0
	_car.set_horn(stuck and _honk_timer > 3.4)


func _on_impacted(impact_kmh: float, _damage: float) -> void:
	if impact_kmh > 8.0:
		_crash_pause = tuning.crash_pause
		_honk_timer = 0.0


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
