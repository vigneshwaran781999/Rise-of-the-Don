class_name PlayerController
extends CharacterBody3D
## On-foot player (GDD §4, M1 subset): camera-relative walk / run / sprint, jump with coyote
## time and input buffering, gravity, slope handling, and a small state machine.
## The capsule is placeholder art; the Model node turns smoothly to face the movement.

signal state_changed(previous: State, current: State)
signal jumped
signal landed(impact_speed: float)

enum State { IDLE, WALK, RUN, SPRINT, JUMP, FALL, LAND }

@export var tuning: PlayerTuning

var state: State = State.IDLE

@onready var model: Node3D = $Model
@onready var stats: PlayerStats = $Stats
@onready var camera_rig: ThirdPersonCamera = $CameraRig

var _gravity: float = 9.8
var _coyote_left: float = 0.0
var _jump_buffer_left: float = 0.0
var _jump_was_held: bool = false
var _land_left: float = 0.0
var _was_on_floor: bool = true


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


func _physics_process(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	_update_timers(delta, on_floor)

	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var strength: float = minf(input.length(), 1.0)
	var gait: State = _choose_gait(strength)
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
	_update_state(now_on_floor, gait)


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
