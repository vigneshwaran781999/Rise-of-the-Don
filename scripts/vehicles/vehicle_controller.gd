class_name VehicleController
extends VehicleBody3D
## A drivable car (GDD §5) on Godot's VehicleBody3D with the Jolt physics engine.
## Whoever drives it (the player now, AI traffic later) only calls set_controls(); this script
## turns those inputs into engine force, brakes and steering on the wheels, all tuned by a
## VehicleStats resource. Forward is +Z, and positive steering turns left.
##
## Child components listen to its signals: Engine (rpm and gear), Damage, Lights, Audio and
## Recovery. Scene layout: Model, CollisionShape3D, Wheel* (VehicleWheel3D), Seat (Marker3D),
## ExitPoints/* (Marker3D, in order of preference), HoodCamera (Marker3D), SmokePoint (Marker3D).

signal driver_changed(driver: Node3D)
signal engine_state_changed(running: bool)
signal headlights_changed(on: bool)
signal horn_changed(on: bool)
## The car was moved by code (not by physics); trackers such as VehicleDamage reset.
signal teleported

const GROUP: StringName = &"vehicles"
## Below this speed (m/s) the brake pedal reverses and the throttle pulls away from reverse.
const DIRECTION_CHANGE_SPEED: float = 1.0
const INPUT_THRESHOLD: float = 0.05

@export var stats: VehicleStats
@export var display_name: String = "Sedan"

var _throttle: float = 0.0
var _brake: float = 0.0
var _steer_input: float = 0.0
var _handbrake: bool = false
var _steer_angle: float = 0.0
var _driver: Node3D
var _engine_running: bool = false
var _engine_disabled: bool = false
var _headlights: bool = false
var _horn: bool = false
var _braking: bool = false
var _reversing: bool = false
var _load: float = 0.0
var _wheels: Array[VehicleWheel3D] = []
var _driven: Array[VehicleWheel3D] = []
var _front: Array[VehicleWheel3D] = []
var _rear: Array[VehicleWheel3D] = []


func _ready() -> void:
	add_to_group(GROUP)
	contact_monitor = true
	max_contacts_reported = 6
	continuous_cd = true
	# Air drag and rolling resistance are modelled in _apply_resistance(); the project's default
	# linear damping (0.1/s) would act as a second, speed-proportional drag and cap top speed.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	_apply_stats()


## Applies the VehicleStats values to the body and wheels (also call after editing stats).
func _apply_stats() -> void:
	mass = stats.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, stats.center_of_mass_height, 0.0)
	_wheels.clear()
	_driven.clear()
	_front.clear()
	_rear.clear()
	for child: Node in get_children():
		var wheel := child as VehicleWheel3D
		if wheel == null:
			continue
		var is_front: bool = wheel.position.z > 0.0
		_wheels.append(wheel)
		(_front if is_front else _rear).append(wheel)
		wheel.use_as_steering = is_front
		wheel.use_as_traction = stats.drive == VehicleStats.Drive.ALL \
			or (stats.drive == VehicleStats.Drive.FRONT) == is_front
		if wheel.use_as_traction:
			_driven.append(wheel)
		wheel.suspension_stiffness = stats.suspension_stiffness
		wheel.wheel_rest_length = stats.suspension_rest_length
		wheel.suspension_travel = stats.suspension_travel
		wheel.damping_compression = stats.damping_compression
		wheel.damping_relaxation = stats.damping_relaxation
		wheel.suspension_max_force = stats.suspension_max_force
		wheel.wheel_roll_influence = stats.roll_influence
		wheel.wheel_friction_slip = stats.front_grip if is_front else stats.rear_grip


# --------------------------------------------------------------------------- driving API

## throttle and brake 0..1, steer -1..1 (positive = left), handbrake on/off.
func set_controls(throttle: float, brake: float, steer: float, handbrake: bool) -> void:
	_throttle = clampf(throttle, 0.0, 1.0)
	_brake = clampf(brake, 0.0, 1.0)
	_steer_input = clampf(steer, -1.0, 1.0)
	_handbrake = handbrake


func set_driver(driver: Node3D) -> void:
	if driver == _driver:
		return
	_driver = driver
	set_controls(0.0, 0.0, 0.0, false)
	set_horn(false)
	_set_engine_running(driver != null and not _engine_disabled)
	if driver != null:
		sleeping = false
	driver_changed.emit(driver)


func get_driver() -> Node3D:
	return _driver


## Moves the car and stops it dead without that counting as a crash.
func teleport(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
	teleported.emit()


func is_occupied() -> bool:
	return _driver != null


func is_engine_running() -> bool:
	return _engine_running


## A wrecked engine stops and won't restart (VehicleDamage calls this at zero health).
func set_engine_disabled(disabled: bool) -> void:
	_engine_disabled = disabled
	_set_engine_running(_driver != null and not disabled)


func is_engine_disabled() -> bool:
	return _engine_disabled


func set_headlights(on: bool) -> void:
	if on != _headlights:
		_headlights = on
		headlights_changed.emit(on)


func toggle_headlights() -> void:
	set_headlights(not _headlights)


func are_headlights_on() -> bool:
	return _headlights


func set_horn(on: bool) -> void:
	if on != _horn:
		_horn = on
		horn_changed.emit(on)


func is_horn_on() -> bool:
	return _horn


# --------------------------------------------------------------------------- queries

## Signed speed along the car's nose, m/s (negative when rolling backwards).
func get_forward_speed() -> float:
	return global_basis.z.dot(linear_velocity)


func get_speed_kmh() -> float:
	return absf(get_forward_speed()) * 3.6


## How hard the engine is working, 0..1 (throttle forwards, brake pedal in reverse).
func get_engine_load() -> float:
	return _load


func is_braking() -> bool:
	return _braking


func is_reversing() -> bool:
	return _reversing


func is_handbrake_on() -> bool:
	return _handbrake


## Current front-wheel angle in radians (positive = left).
func get_steer_angle() -> float:
	return _steer_angle


func get_wheels() -> Array[VehicleWheel3D]:
	return _wheels


func get_seat_transform() -> Transform3D:
	return ($Seat as Node3D).global_transform


## World positions (at road level) where someone can get out, best first: driver's door,
## passenger door, behind, in front. Callers check which one is free.
func get_exit_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for marker: Node in $ExitPoints.get_children():
		points.append((marker as Node3D).global_position)
	return points


func get_hood_camera_transform() -> Transform3D:
	return ($HoodCamera as Node3D).global_transform


# --------------------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	var forward_speed: float = get_forward_speed()
	var drive_force: float = 0.0
	var brake_force: float = 0.0
	var coasting: bool = false
	_braking = false
	_reversing = false

	if _driver == null:
		brake_force = stats.parking_brake_force
	elif _throttle > INPUT_THRESHOLD and _brake > INPUT_THRESHOLD:
		brake_force = stats.brake_force * _brake
		_braking = true
	elif _throttle > INPUT_THRESHOLD:
		if forward_speed < -DIRECTION_CHANGE_SPEED:
			brake_force = stats.brake_force * _throttle    # stop rolling back before pulling away
			_braking = true
		else:
			drive_force = _throttle * _forward_push(forward_speed)
	elif _brake > INPUT_THRESHOLD:
		if forward_speed > DIRECTION_CHANGE_SPEED:
			brake_force = stats.brake_force * _brake
			_braking = true
		else:
			drive_force = -_brake * _reverse_push(forward_speed)
			_reversing = true
	else:
		coasting = true

	if not _engine_running:
		drive_force = 0.0
	_load = 0.0 if not _engine_running else (_brake if _reversing else (_throttle if drive_force > 0.0 else 0.0))
	# Still "in reverse" while rolling backwards off the pedals (reverse lights, gear R).
	_reversing = _reversing or (_driver != null and forward_speed < -0.5 and _throttle <= INPUT_THRESHOLD)
	_apply_wheel_forces(drive_force, brake_force, coasting, delta)
	_apply_steering(delta)
	_apply_resistance()


## Push from the engine going forwards: full force from a standstill, then limited by power,
## fading to nothing at the top speed.
func _forward_push(forward_speed: float) -> float:
	var speed: float = maxf(forward_speed, 0.0)
	var push: float = minf(stats.engine_force, stats.engine_power / maxf(speed, 0.1))
	var top: float = stats.top_speed_kmh / 3.6
	return push * clampf((top - speed) / (top * 0.04), 0.0, 1.0)


func _reverse_push(forward_speed: float) -> float:
	var speed: float = maxf(-forward_speed, 0.0)
	var top: float = stats.reverse_top_speed_kmh / 3.6
	return stats.reverse_force * clampf((top - speed) / (top * 0.15), 0.0, 1.0)


## VehicleWheel3D.brake is an impulse per physics step, so forces are scaled by delta.
## A wheel ignores its brake while it has engine force, which is why the two never mix.
func _apply_wheel_forces(drive_force: float, brake_force: float, coasting: bool, delta: float) -> void:
	var per_driven: float = drive_force / maxf(_driven.size(), 1)
	var front_brake: float = brake_force * stats.brake_bias_front / maxf(_front.size(), 1)
	var rear_brake: float = brake_force * (1.0 - stats.brake_bias_front) / maxf(_rear.size(), 1)
	var engine_brake: float = stats.engine_braking / maxf(_driven.size(), 1) if coasting and _engine_running else 0.0
	var handbrake: bool = _handbrake and _driver != null
	for wheel: VehicleWheel3D in _wheels:
		var is_front: bool = _front.has(wheel)
		var force: float = per_driven if wheel.use_as_traction else 0.0
		var brake: float = front_brake if is_front else rear_brake
		if coasting and wheel.use_as_traction:
			brake += engine_brake
		if handbrake and not is_front:
			force = 0.0
			brake += stats.handbrake_force / maxf(_rear.size(), 1)
		wheel.engine_force = force
		wheel.brake = brake * delta
		var grip: float = stats.front_grip if is_front else stats.rear_grip
		wheel.wheel_friction_slip = grip * (stats.handbrake_rear_grip if handbrake and not is_front else 1.0)


## Largest front-wheel angle at the current speed, radians (steering input 1.0 gives this).
func get_steer_lock() -> float:
	var falloff: float = clampf(get_speed_kmh() / stats.steer_falloff_speed_kmh, 0.0, 1.0)
	return deg_to_rad(lerpf(stats.max_steer_degrees, stats.high_speed_steer_degrees, falloff))


func _apply_steering(delta: float) -> void:
	var lock: float = get_steer_lock()
	var target: float = _steer_input * lock if _driver != null else 0.0
	var returning: bool = absf(target) < absf(_steer_angle) or signf(target) != signf(_steer_angle)
	var rate: float = stats.steer_return_speed if returning else stats.steer_speed
	_steer_angle = move_toward(_steer_angle, target, rate * delta)
	for wheel: VehicleWheel3D in _front:
		wheel.steering = _steer_angle


## Air drag, rolling resistance and downforce, applied at the centre of mass.
func _apply_resistance() -> void:
	var velocity: Vector3 = linear_velocity
	var speed: float = velocity.length()
	if speed > 0.5:
		var resist: float = stats.drag_coefficient * speed * speed + stats.rolling_resistance
		apply_central_force(-velocity / speed * resist)
	if speed > 1.0:
		apply_central_force(-global_basis.y * stats.downforce * speed * speed)


func _set_engine_running(running: bool) -> void:
	if running != _engine_running:
		_engine_running = running
		engine_state_changed.emit(running)
