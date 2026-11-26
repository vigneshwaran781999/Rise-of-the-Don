class_name PlayerController
extends CharacterBody3D
## The player (GDD §4): camera-relative walk / run / sprint, jump with coyote time and input
## buffering, gravity, slope handling, and getting in and out of vehicles, driven by a small
## state machine. The capsule is placeholder art; the Model node turns to face the movement.
##
## Vehicles: VehicleInteractor decides when to get in or out and where to stand; this script
## carries it out (walk to the door, ride in the seat hidden, step out) and announces it with
## vehicle_entered / vehicle_exited. PlayerDrivingInput steers while the state is IN_VEHICLE.
##
## Fists (M7): PlayerFists starts a punch (PUNCH: slowed for a moment); blows taken push the
## player back and cost health (take_hit). At no health the player goes DOWN (died); the game
## session takes them to hospital and revive()s them.

signal state_changed(previous: State, current: State)
signal jumped
signal landed(impact_speed: float)
## Emitted as the player starts getting in (the camera hands over during the walk to the door).
signal vehicle_entered(vehicle: VehicleController)
signal vehicle_exited(vehicle: VehicleController)
## A blow landed on the player (take_hit).
signal hurt(damage: float)
## Health ran out: the player is down.
signal died

enum State { IDLE, WALK, RUN, SPRINT, JUMP, FALL, LAND, ENTER_VEHICLE, IN_VEHICLE, EXIT_VEHICLE, PUNCH, DOWN }

const ON_FOOT_STATES: Array[State] = [State.IDLE, State.WALK, State.RUN, State.SPRINT, State.LAND]

@export var tuning: PlayerTuning

var state: State = State.IDLE
## While true (a dialogue scene), movement, jumping and getting into vehicles are ignored.
var input_locked: bool = false
## The vehicle the player is getting into or sitting in (null on foot).
var vehicle: VehicleController

@onready var model: Node3D = $Model
@onready var stats: PlayerStats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _gravity: float = 9.8
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _jump_was_held: bool = false
var _land_left: float = 0.0
var _was_on_floor: bool = true
var _transition_left: float = 0.0
var _enter_from: Vector3 = Vector3.ZERO
var _enter_door_local: Vector3 = Vector3.ZERO
var _exit_requested: bool = false
var _exit_wait: float = 0.0
var _punch_left: float = 0.0
var _stagger_left: float = 0.0


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	floor_max_angle = deg_to_rad(tuning.max_slope_degrees)
	floor_snap_length = tuning.floor_snap_length
	floor_constant_speed = true
	floor_stop_on_slope = true
	camera_rig.set_target(self)


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func get_state_name() -> String:
	return State.keys()[state]


# --------------------------------------------------------------------------- vehicles

## True when standing (or walking) on the ground, free to get into a vehicle.
func can_enter_vehicle() -> bool:
	return state in ON_FOOT_STATES and is_on_floor()


func is_in_vehicle() -> bool:
	return state == State.IN_VEHICLE


## Starts getting into `target` through the door at world position `door`.
func enter_vehicle(target: VehicleController, door: Vector3) -> void:
	if not can_enter_vehicle() or target.is_occupied():
		return
	vehicle = target
	_enter_from = global_position
	_enter_door_local = target.to_local(door)
	_transition_left = tuning.enter_vehicle_time
	velocity = Vector3.ZERO
	_collision.set_deferred("disabled", true)
	_set_state(State.ENTER_VEHICLE)
	vehicle_entered.emit(target)


## Asks to get out. VehicleInteractor completes it with exit_vehicle() once the car is slow
## enough; until then PlayerDrivingInput brakes.
func request_vehicle_exit() -> void:
	if state == State.IN_VEHICLE and not _exit_requested:
		_exit_requested = true
		_exit_wait = 0.0


func is_exit_requested() -> bool:
	return _exit_requested


## Seconds since the exit was requested.
func get_exit_wait() -> float:
	return _exit_wait


## Steps out of the current vehicle onto the ground at world position `at`.
func exit_vehicle(at: Vector3) -> void:
	if vehicle == null:
		return
	var left: VehicleController = vehicle
	left.set_driver(null)
	vehicle = null
	_exit_requested = false
	global_position = at
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	var away: Vector3 = at - left.global_position
	away.y = 0.0
	if away.length() > 0.01:
		model.rotation.y = atan2(-away.x, -away.z)
	model.visible = true
	_collision.set_deferred("disabled", false)
	_transition_left = tuning.exit_vehicle_time
	_jump_buffer_left = 0.0
	_was_on_floor = true
	_set_state(State.EXIT_VEHICLE)
	vehicle_exited.emit(left)


# --------------------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	match state:
		State.ENTER_VEHICLE:
			_step_entering(delta)
			return
		State.IN_VEHICLE:
			_ride(delta)
			return
		State.DOWN:
			_lie(delta)
			return

	var on_floor: bool = is_on_floor()
	var stepping_out: bool = state == State.EXIT_VEHICLE
	_transition_left = maxf(0.0, _transition_left - delta)
	_update_timers(delta, on_floor)
	if stepping_out:
		_jump_buffer_left = 0.0

	if input_locked:
		_jump_buffer_left = 0.0
	var input: Vector2 = Vector2.ZERO if stepping_out or input_locked or _stagger_left > 0.0 else Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back")
	_punch_left = maxf(0.0, _punch_left - delta)
	_stagger_left = maxf(0.0, _stagger_left - delta)
	if state == State.PUNCH:
		input *= tuning.punch_move_scale
	var strength: float = minf(input.length(), 1.0)
	var gait: State = _choose_gait(strength)
	if _stagger_left <= 0.0:          # reeling from a blow: the knockback carries the player
		_apply_horizontal(_camera_relative(input) * _gait_speed(gait), on_floor, delta)
	_apply_gravity(on_floor, delta)
	_try_jump()

	var fall_speed: float = -velocity.y
	move_and_slide()
	var now_on_floor: bool = is_on_floor()
	if now_on_floor and not _was_on_floor:
		_land_left = tuning.land_recovery_time
		landed.emit(maxf(fall_speed, 0.0))
	_was_on_floor = now_on_floor

	var speed: float = get_horizontal_speed()
	stats.tick(delta, gait == State.SPRINT and speed > tuning.walk_speed)
	camera_rig.sprinting = gait == State.SPRINT and speed > tuning.run_speed
	_face_movement(delta)
	if stepping_out and _transition_left > 0.0:
		return
	if state == State.PUNCH and _punch_left > 0.0:
		return
	_update_state(now_on_floor, gait)


## Starts a punch (PlayerFists) when on foot and free to: true if it started.
func start_punch() -> bool:
	if input_locked or state not in ON_FOOT_STATES or not is_on_floor() or _punch_left > 0.0:
		return false
	_punch_left = tuning.punch_time
	_set_state(State.PUNCH)
	return true


## How far through the current punch (0-1), or -1 when not punching.
func get_punch_progress() -> float:
	return 1.0 - _punch_left / tuning.punch_time if state == State.PUNCH else -1.0


## Which way the player faces (on the ground plane).
func get_facing() -> Vector3:
	return -model.global_basis.z


## A blow from someone at `from`: costs health, pushes the player back for a moment, and at no
## health puts them down. Ignored in a vehicle or already down.
func take_hit(damage: float, from: Vector3, _attacker: Node3D = null) -> void:
	if state == State.DOWN or is_in_vehicle():
		return
	stats.apply_damage(damage)
	var push := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if push.length_squared() > 0.0001:
		push = push.normalized() * tuning.hit_knockback
		velocity.x = push.x
		velocity.z = push.z
	_stagger_left = tuning.hit_stagger_time
	hurt.emit(damage)
	if stats.health <= 0.0:
		_go_down()


func is_down() -> bool:
	return state == State.DOWN


## Back on their feet after being down (the hospital): full health, facing as they were.
func revive() -> void:
	model.rotation.x = 0.0
	model.position.y = 0.0
	stats.set_health(stats.get_max_health())
	_stagger_left = 0.0
	_punch_left = 0.0
	velocity = Vector3.ZERO
	_set_state(State.IDLE)


func _go_down() -> void:
	_punch_left = 0.0
	_set_state(State.DOWN)
	died.emit()


## Lying down: no control, just gravity and friction.
func _lie(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	_apply_horizontal(Vector3.ZERO, on_floor, delta)
	_apply_gravity(on_floor, delta)
	move_and_slide()


## Walks (glides) to the door, turning to face the car, then disappears into the seat.
func _step_entering(delta: float) -> void:
	_transition_left -= delta
	var progress: float = 1.0 - clampf(_transition_left / tuning.enter_vehicle_time, 0.0, 1.0)
	var door: Vector3 = vehicle.to_global(_enter_door_local)
	global_position = _enter_from.lerp(door, smoothstep(0.0, 1.0, progress))
	var to_car: Vector3 = vehicle.global_position - global_position
	if Vector2(to_car.x, to_car.z).length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_car.x, -to_car.z), 1.0 - exp(-tuning.turn_speed * delta))
	if _transition_left <= 0.0:
		model.visible = false
		vehicle.set_driver(self)
		_set_state(State.IN_VEHICLE)
		_ride(delta)


## Sits in the driver's seat: follows the car, hidden, with no collision of its own.
func _ride(delta: float) -> void:
	global_position = vehicle.get_seat_transform().origin
	velocity = Vector3.ZERO
	stats.tick(delta, false)
	camera_rig.sprinting = false
	if _exit_requested:
		_exit_wait += delta


func _update_timers(delta: float, on_floor: bool) -> void:
	_coyote_left = tuning.coyote_time if on_floor else maxf(0.0, _coyote_left - delta)
	_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)
	_land_left = maxf(0.0, _land_left - delta)
	# Edge-detect the press here so a jump is never missed between physics ticks.
	var held: bool = Input.is_action_pressed("jump")
	if held and not _jump_was_held:
		_jump_buffer_left = tuning.jump_buffer_time
	_jump_was_held = held


func _choose_gait(strength: float) -> State:
	if strength < 0.05:
		return State.IDLE
	if Input.is_action_pressed("sprint") and stats.can_sprint() and strength > 0.5:
		return State.SPRINT
	if Input.is_action_pressed("walk") or strength < tuning.stick_walk_threshold:
		return State.WALK
	return State.RUN


func _gait_speed(gait: State) -> float:
	match gait:
		State.WALK:
			return tuning.walk_speed
		State.RUN:
			return tuning.run_speed
		State.SPRINT:
			return tuning.sprint_speed
	return 0.0


## Converts stick / WASD input to a world direction on the ground plane, relative to the camera.
func _camera_relative(input: Vector2) -> Vector3:
	if input.length_squared() < 0.0001:
		return Vector3.ZERO
	var yaw: float = camera_rig.get_yaw()
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var right: Vector3 = Vector3.RIGHT.rotated(Vector3.UP, yaw)
	return (right * input.x - forward * input.y).normalized()


func _apply_horizontal(target: Vector3, on_floor: bool, delta: float) -> void:
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = tuning.ground_acceleration if target.length_squared() > 0.0001 else tuning.ground_deceleration
	if not on_floor:
		rate *= tuning.air_control
	current = current.move_toward(target, rate * delta)
	velocity.x = current.x
	velocity.z = current.z


func _apply_gravity(on_floor: bool, delta: float) -> void:
	if on_floor and velocity.y <= 0.0:
		return
	var g: float = _gravity * tuning.gravity_scale
	if velocity.y < 0.0:
		g *= tuning.fall_gravity_multiplier
	velocity.y = maxf(velocity.y - g * delta, -tuning.max_fall_speed)


func _try_jump() -> void:
	if _jump_buffer_left <= 0.0 or _coyote_left <= 0.0:
		return
	velocity.y = tuning.jump_velocity
	_jump_buffer_left = 0.0
	_coyote_left = 0.0
	_set_state(State.JUMP)
	jumped.emit()


func _face_movement(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < 0.3:
		return
	var target_yaw: float = atan2(-horizontal.x, -horizontal.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-tuning.turn_speed * delta))


func _update_state(on_floor: bool, gait: State) -> void:
	var next: State = gait
	if not on_floor:
		next = State.JUMP if state == State.JUMP and velocity.y > 0.0 else State.FALL
	elif _land_left > 0.0 and state in [State.JUMP, State.FALL, State.LAND]:
		next = State.LAND
	_set_state(next)


func _set_state(next: State) -> void:
	if next == state:
		return
	var previous: State = state
	state = next
	state_changed.emit(previous, next)
