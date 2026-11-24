class_name VehicleCamera
extends Node3D
## Camera for the vehicle the player drives (GDD §4 "vehicle camera mode", §5 "chase and hood
## cameras"). Chase: orbits behind the car on a collision-aware spring arm, drops back and
## widens the view with speed, and swings back behind the car a moment after you stop looking
## around. Hood: fixed over the bonnet, looking ahead, with a limited free look.
## vehicle_camera toggles between them. Mouse and right stick look work in both.
##   VehicleCamera (this, top_level) -> Yaw -> Pitch -> SpringArm3D -> Camera3D

signal mode_changed(mode: Mode)

enum Mode { CHASE, HOOD }

@export var settings: VehicleCameraTuning

var mode: Mode = Mode.CHASE
var vehicle: VehicleController

@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D
@onready var _yaw_node: Node3D = $Yaw
@onready var _pitch_node: Node3D = $Yaw/Pitch
@onready var _arm: SpringArm3D = $Yaw/Pitch/SpringArm3D

## Chase: world yaw and pitch of the view. Hood: offsets from straight ahead.
var _yaw: float = 0.0
var _pitch: float = 0.0
var _since_look: float = 0.0
var _recenter_now: bool = false


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sphere := SphereShape3D.new()
	sphere.radius = settings.collision_radius
	_arm.shape = sphere
	camera.fov = settings.base_fov
	_set_active(false)


## Starts following `target`, continuing from the given view angles (radians, chase yaw is
## world yaw) so the hand-over from the on-foot camera keeps looking the same way.
func activate(target: VehicleController, yaw: float, pitch: float) -> void:
	vehicle = target
	_arm.clear_excluded_objects()
	_arm.add_excluded_object(target.get_rid())
	_yaw = yaw if mode == Mode.CHASE else 0.0
	_pitch = pitch if mode == Mode.CHASE else 0.0
	_recenter_now = true
	_since_look = 0.0
	_set_active(true)
	_update_view(0.0, true)


func deactivate() -> void:
	vehicle = null
	_set_active(false)


func is_active() -> bool:
	return is_processing()


func set_mode(next: Mode) -> void:
	if next == mode:
		return
	mode = next
	_yaw = _heading_yaw() if mode == Mode.CHASE else 0.0
	_pitch = deg_to_rad(settings.default_pitch_degrees) if mode == Mode.CHASE else 0.0
	_since_look = 0.0
	_update_view(0.0, true)
	mode_changed.emit(mode)


## World yaw the camera is looking along (for handing the view back to the on-foot camera).
func get_view_yaw() -> float:
	var forward: Vector3 = -camera.global_basis.z
	return atan2(-forward.x, -forward.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var per_pixel: float = settings.mouse_radians_per_pixel * Settings.mouse_sensitivity
		_look(-motion.relative.x * per_pixel, -motion.relative.y * per_pixel * _invert_sign())
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("vehicle_camera"):
		set_mode(Mode.HOOD if mode == Mode.CHASE else Mode.CHASE)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if vehicle == null:
		return
	var stick: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		var speed: float = deg_to_rad(settings.stick_degrees_per_second) * Settings.mouse_sensitivity * delta
		_look(-stick.x * speed, -stick.y * speed * _invert_sign())
	_since_look += delta
	_update_view(delta, false)


func _look(yaw_delta: float, pitch_delta: float) -> void:
	_yaw += yaw_delta
	_pitch += pitch_delta
	_since_look = 0.0
	_recenter_now = false


func _update_view(delta: float, snap: bool) -> void:
	var car_xf: Transform3D = vehicle.get_global_transform_interpolated()
	var speed_share: float = clampf(vehicle.get_speed_kmh() / vehicle.stats.top_speed_kmh, 0.0, 1.0)
	var fov_goal: float
	if mode == Mode.CHASE:
		_recenter(delta)
		_pitch = clampf(_pitch, deg_to_rad(settings.min_pitch_degrees), deg_to_rad(settings.max_pitch_degrees))
		_yaw = wrapf(_yaw, -PI, PI)
		global_basis = Basis.IDENTITY
		var goal: Vector3 = car_xf.origin + Vector3.UP * settings.pivot_height
		if snap:
			global_position = goal
		else:
			var pos: Vector3 = global_position
			var k_h: float = 1.0 - exp(-settings.follow_sharpness * delta)
			var k_v: float = 1.0 - exp(-settings.vertical_follow_sharpness * delta)
			pos.x = lerpf(pos.x, goal.x, k_h)
			pos.z = lerpf(pos.z, goal.z, k_h)
			pos.y = lerpf(pos.y, goal.y, k_v)
			global_position = pos
		_arm.spring_length = settings.distance + settings.distance_speed_bonus * speed_share
		fov_goal = settings.base_fov + settings.speed_fov_bonus * speed_share
	else:
		var limit: float = deg_to_rad(settings.hood_look_limit_degrees)
		if _since_look > settings.recenter_delay:
			var k: float = 1.0 - exp(-settings.recenter_sharpness * delta)
			_yaw = lerpf(_yaw, 0.0, k)
			_pitch = lerpf(_pitch, 0.0, k)
		_yaw = clampf(_yaw, -limit, limit)
		_pitch = clampf(_pitch, deg_to_rad(-40.0), deg_to_rad(30.0))
		var hood_local: Transform3D = (vehicle.get_node("HoodCamera") as Node3D).transform
		global_transform = car_xf * hood_local
		_arm.spring_length = 0.0
		fov_goal = settings.hood_fov
	_yaw_node.rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)
	camera.fov = fov_goal if snap else lerpf(camera.fov, fov_goal, 1.0 - exp(-settings.fov_sharpness * delta))


## Swings the chase camera back behind the car once the player stops looking around (and
## right after getting in, starting from wherever the on-foot camera was looking).
func _recenter(delta: float) -> void:
	var moving: bool = vehicle.get_speed_kmh() >= settings.recenter_min_speed_kmh
	if not (_recenter_now or (moving and _since_look > settings.recenter_delay)):
		return
	var k: float = 1.0 - exp(-settings.recenter_sharpness * delta)
	_yaw = lerp_angle(_yaw, _heading_yaw(), k)
	_pitch = lerpf(_pitch, deg_to_rad(settings.default_pitch_degrees), k)
	if absf(angle_difference(_yaw, _heading_yaw())) < 0.02:
		_recenter_now = false


## The chase yaw that looks along the car's nose.
func _heading_yaw() -> float:
	var forward: Vector3 = vehicle.global_basis.z
	return atan2(-forward.x, -forward.z)


func _set_active(active: bool) -> void:
	set_process(active)
	set_process_unhandled_input(active)


func _invert_sign() -> float:
	return -1.0 if Settings.invert_y else 1.0
