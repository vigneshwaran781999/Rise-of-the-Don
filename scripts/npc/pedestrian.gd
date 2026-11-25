class_name Pedestrian
extends CharacterBody3D
## Someone on Old Town's sidewalks (GDD §6). Walks the pedestrian navmesh with a
## NavigationAgent3D (with avoidance, so people steer round each other) and:
##   wanders, stops to stand, chats with someone nearby, sits on a free bench,
##   flees from crashes, horns and people being hit, is knocked down by cars,
##   and steps aside when the player walks into them.
## Looks and the walk cycle come from shaders/character.gdshader (per-person colours, legs and
## arms swung in the vertex shader). PedestrianManager spawns, removes and coordinates them.

signal state_changed(previous: State, current: State)

enum State { WALK, IDLE, TALK, SIT, FLEE, STEP_ASIDE, KNOCKED }

const GROUP: StringName = &"pedestrians"
## A seated figure's feet sit this far below the bench's base (see OldTownLayout._bench).
const SEAT_DROP: float = 0.41

@export var tuning: PedestrianTuning

var state: State = State.IDLE
var manager: PedestrianManager

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var model: MeshInstance3D = $Model
@onready var _shape: CollisionShape3D = $CollisionShape3D

var _walk_speed: float = 1.3
var _speed: float = 1.3
var _timer: float = 0.0
var _phase: float = 0.0
var _swing: float = 0.0
var _sit: float = 0.0
var _safe_velocity: Vector3 = Vector3.ZERO
var _partner: Pedestrian
var _seat: Node3D
var _danger: Vector3 = Vector3.ZERO
var _hit_by: Node3D                    # the car that knocked them down (they run from where it is now)
var _bump_cooldown: float = 0.0
var _gravity: float = 9.8
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	agent.velocity_computed.connect(_on_velocity_computed)


## Gives the person their look (model and colours) and pace.
func setup(look: PackedScene, colours: Dictionary, seed_value: int) -> void:
	_rng.seed = seed_value
	model.mesh = CharacterBaker.get_mesh(look)
	for key: StringName in colours:
		model.set_instance_shader_parameter(key, colours[key])
	_walk_speed = _rng.randf_range(tuning.walk_speed_min, tuning.walk_speed_max)
	_phase = _rng.randf() * TAU


func get_state_name() -> String:
	return State.keys()[state]


func get_partner() -> Pedestrian:
	return _partner if is_instance_valid(_partner) else null


func get_seat() -> Node3D:
	return _seat


## Busy people don't start chatting or go to sit down.
func is_busy() -> bool:
	return state in [State.TALK, State.SIT, State.FLEE, State.STEP_ASIDE, State.KNOCKED] or _seat != null


# --------------------------------------------------------------------------- commands

func wander() -> void:
	for attempt: int in 6:
		var angle: float = _rng.randf() * TAU
		var candidate: Vector3 = global_position + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(tuning.wander_min, tuning.wander_max)
		var point: Variant = _navmesh_point(candidate)
		if point != null and _flat((point as Vector3) - global_position).length() > 5.0:
			_walk_to(point, _walk_speed, State.WALK)
			return
	_stand(1.5)


## Stands still where they are for `seconds`, then wanders on.
func stand(seconds: float) -> void:
	_leave_seat()
	_end_talk()
	_stand(seconds)


func start_talk(partner: Pedestrian) -> void:
	_partner = partner
	_timer = _rng.randf_range(tuning.talk_min, tuning.talk_max)
	_halt()
	_set_state(State.TALK)


## Walks to `seat` (a sit-spot marker) and sits there for a while.
func go_sit(seat: Node3D) -> void:
	_seat = seat
	var stand_point: Vector3 = _seat_stand_point()
	var point: Variant = _navmesh_point(stand_point)
	_walk_to(point if point != null else stand_point, _walk_speed, State.WALK)


## Runs (or, if not `run`, hurries) away from `point`.
func flee_from(point: Vector3, run: bool) -> void:
	if state == State.KNOCKED:
		return
	_leave_seat()
	_end_talk()
	_danger = point
	var away: Vector3 = _flat3(global_position - point)
	if away.length_squared() < 0.01:
		var angle: float = _rng.randf() * TAU
		away = Vector3(cos(angle), 0.0, sin(angle))
	var point_away: Variant = _navmesh_point(global_position + away.normalized() * (tuning.flee_distance if run else 6.0))
	if point_away == null:
		point_away = global_position
	_timer = tuning.flee_time if run else 2.0
	_walk_to(point_away, tuning.run_speed if run else _walk_speed * 1.7, State.FLEE if run else State.STEP_ASIDE)


## Called by a car's VehicleBumper when it reaches this person.
func hit_by_vehicle(vehicle: VehicleController, speed: float) -> void:
	if state == State.KNOCKED:
		return
	if speed < tuning.knock_speed:
		flee_from(vehicle.global_position, false)
		return
	_leave_seat()
	_end_talk()
	_danger = vehicle.global_position
	_hit_by = vehicle
	_shape.set_deferred(&"disabled", true)   # the car rolls on instead of stopping dead
	velocity = Vector3.ZERO
	_halt()
	# Fall backwards onto the road, lying along the way the car pushed.
	var push: Vector3 = _flat3(global_position - vehicle.global_position)
	if push.length_squared() > 0.01:
		rotation.y = atan2(-push.x, -push.z)
	model.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	model.position = Vector3(0.0, 0.12, 0.0)
	_timer = tuning.knocked_time
	_set_state(State.KNOCKED)
	if manager != null:
		manager.alert(global_position, 15.0, true, self)
		manager.report_knockdown(self, vehicle)


# --------------------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	match state:
		State.WALK, State.FLEE, State.STEP_ASIDE:
			_follow_path(delta)
		State.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				wander()
		State.TALK:
			_timer -= delta
			var partner: Pedestrian = get_partner()
			if partner != null:
				_face(partner.global_position - global_position, delta)
			if _timer <= 0.0 or partner == null or partner.state != State.TALK:
				_end_talk()
				wander()
		State.SIT:
			_timer -= delta
			if _timer <= 0.0:
				_stand_up()
		State.KNOCKED:
			_timer -= delta
			if _timer <= 0.0:
				_get_up()
	if state != State.SIT and state != State.KNOCKED:
		var moving: bool = state in [State.WALK, State.FLEE, State.STEP_ASIDE]
		var v: Vector3 = _safe_velocity if moving else Vector3.ZERO
		velocity.x = v.x
		velocity.z = v.z
		velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
		move_and_slide()
	_animate(delta)
	_check_bump()


func _follow_path(delta: float) -> void:
	if state != State.WALK:
		_timer -= delta
		if _timer <= 0.0:
			_arrived()
			return
	if agent.is_navigation_finished():
		_arrived()
		return
	var next: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = _flat3(next - global_position)
	var desired: Vector3 = direction.normalized() * _speed if direction.length() > 0.05 else Vector3.ZERO
	agent.velocity = desired
	if _safe_velocity.length_squared() > 0.04:
		_face(_safe_velocity, delta)


func _arrived() -> void:
	_halt()
	if _seat != null and state == State.WALK:
		_sit_down()
		return
	if state != State.WALK:
		wander()
		return
	if manager != null and _rng.randf() < tuning.sit_chance:
		var seat: Node3D = manager.claim_seat(self)
		if seat != null:
			go_sit(seat)
			return
	if _rng.randf() < tuning.idle_chance:
		_stand(_rng.randf_range(tuning.idle_min, tuning.idle_max))
		if manager != null:
			manager.try_start_talk(self)
		return
	wander()


func _animate(delta: float) -> void:
	var speed: float = _flat(velocity).length() if state != State.KNOCKED and state != State.SIT else 0.0
	var target_swing: float = clampf(speed / 1.4, 0.0, 1.0) * tuning.swing * (1.5 if speed > 2.5 else 1.0)
	if state == State.TALK:
		target_swing = 0.12          # small hand gestures
		_phase += delta * 2.5
	else:
		_phase += speed / tuning.stride * PI * delta
	_swing = lerpf(_swing, target_swing, 1.0 - exp(-8.0 * delta))
	_sit = move_toward(_sit, 1.0 if state == State.SIT else 0.0, delta * 3.0)
	model.set_instance_shader_parameter(&"walk_phase", _phase)
	model.set_instance_shader_parameter(&"swing", _swing)
	model.set_instance_shader_parameter(&"sit", _sit)


## The player walking into this person makes them step out of the way.
func _check_bump() -> void:
	if _bump_cooldown > 0.0 or manager == null or manager.player == null:
		return
	if state not in [State.WALK, State.IDLE, State.TALK]:
		return
	var player: PlayerController = manager.player
	if player.is_in_vehicle() or player.get_horizontal_speed() < 0.8:
		return
	if _flat(player.global_position - global_position).length() < tuning.bump_distance:
		_bump_cooldown = tuning.bump_cooldown
		_face(player.global_position - global_position, 1.0)
		flee_from(player.global_position, false)


# --------------------------------------------------------------------------- helpers

func _walk_to(point: Vector3, speed: float, next_state: State) -> void:
	agent.target_position = point
	_speed = speed
	agent.max_speed = maxf(speed, 0.5)
	_set_state(next_state)


func _halt() -> void:
	_safe_velocity = Vector3.ZERO
	agent.velocity = Vector3.ZERO


func _stand(seconds: float) -> void:
	_timer = seconds
	_halt()
	_set_state(State.IDLE)


func _sit_down() -> void:
	var seat_xform: Transform3D = _seat.global_transform
	_shape.set_deferred(&"disabled", true)
	velocity = Vector3.ZERO
	global_transform = Transform3D(seat_xform.basis, seat_xform.origin)
	reset_physics_interpolation()
	_timer = _rng.randf_range(tuning.sit_min, tuning.sit_max)
	_set_state(State.SIT)


func _stand_up() -> void:
	_leave_seat()
	wander()


func _get_up() -> void:
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	_shape.set_deferred(&"disabled", false)
	state = State.IDLE
	flee_from(_hit_by.global_position if is_instance_valid(_hit_by) else _danger, true)
	_hit_by = null


func _seat_stand_point() -> Vector3:
	var seat_xform: Transform3D = _seat.global_transform
	return seat_xform.origin + seat_xform.basis.z * 0.65 + Vector3.UP * SEAT_DROP


## Gives up the claimed bench seat; someone sitting on it first stands up in front of it.
func _leave_seat() -> void:
	if _seat == null:
		return
	if state == State.SIT:
		global_position = _seat_stand_point()
		rotation = Vector3(0.0, rotation.y, 0.0)
		reset_physics_interpolation()
		_shape.set_deferred(&"disabled", false)
		_set_state(State.IDLE)
	if manager != null:
		manager.release_seat(_seat)
	_seat = null


func _end_talk() -> void:
	_partner = null


func _face(direction: Vector3, delta: float) -> void:
	var flat: Vector3 = _flat3(direction)
	if flat.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), 1.0 - exp(-tuning.turn_speed * delta))


func _navmesh_point(near: Vector3) -> Variant:
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return null
	var point: Vector3 = NavigationServer3D.map_get_closest_point(map, near)
	if point == Vector3.ZERO or _flat(point - near).length() > 8.0:
		return null
	return point


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous: State = state
	state = next
	state_changed.emit(previous, next)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _flat3(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
