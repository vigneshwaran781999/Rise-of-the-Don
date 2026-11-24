class_name ThirdPersonCamera
extends Node3D
## Third-person camera rig (GDD §4): mouse and right-stick look with a pitch clamp, collision
## through a SpringArm3D, smoothed follow of the target's interpolated position, and a small
## FOV kick while sprinting. Lives under the player but is top_level, so it moves on its own.
##   CameraRig (this) -> Yaw -> Pitch -> SpringArm3D -> Camera3D

@export var settings: CameraTuning

## Set each physics frame by the player controller.
var sprinting: bool = false
var target: Node3D

@onready var camera: Camera3D = $Yaw/Pitch/SpringArm3D/Camera3D
@onready var _yaw_node: Node3D = $Yaw
@onready var _pitch_node: Node3D = $Yaw/Pitch
@onready var _arm: SpringArm3D = $Yaw/Pitch/SpringArm3D

var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	top_level = true
	# Moved by hand every rendered frame from the target's interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm.spring_length = settings.distance
	var sphere := SphereShape3D.new()
	sphere.radius = settings.collision_radius
	_arm.shape = sphere
	camera.fov = settings.base_fov
	_pitch = deg_to_rad(settings.default_pitch_degrees)
	_apply_rotation()


func set_target(node: CollisionObject3D) -> void:
	target = node
	_arm.add_excluded_object(node.get_rid())
	snap_to_target()


## Jump straight to the target (after spawning or teleporting) instead of gliding there.
func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position + Vector3.UP * settings.pivot_height


func get_yaw() -> float:
	return _yaw


func get_pitch() -> float:
	return _pitch


func set_view_degrees(yaw_degrees: float, pitch_degrees: float) -> void:
	_yaw = deg_to_rad(yaw_degrees)
	_pitch = deg_to_rad(pitch_degrees)
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var per_pixel: float = settings.mouse_radians_per_pixel * Settings.mouse_sensitivity
		_yaw -= motion.relative.x * per_pixel
		_pitch -= motion.relative.y * per_pixel * _invert_sign()
		_apply_rotation()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Clicking back into the window (e.g. after alt-tab) recaptures the mouse.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO:
		var speed: float = deg_to_rad(settings.stick_degrees_per_second) * Settings.mouse_sensitivity
		_yaw -= look.x * speed * delta
		_pitch -= look.y * speed * delta * _invert_sign()
		_apply_rotation()
	if target != null:
		var goal: Vector3 = target.get_global_transform_interpolated().origin + Vector3.UP * settings.pivot_height
		var pos: Vector3 = global_position
		var k_h: float = 1.0 - exp(-settings.follow_sharpness * delta)
		var k_v: float = 1.0 - exp(-settings.vertical_follow_sharpness * delta)
		pos.x = lerpf(pos.x, goal.x, k_h)
		pos.z = lerpf(pos.z, goal.z, k_h)
		pos.y = lerpf(pos.y, goal.y, k_v)
		global_position = pos
	var fov_goal: float = settings.base_fov + (settings.sprint_fov_bonus if sprinting else 0.0)
	camera.fov = lerpf(camera.fov, fov_goal, 1.0 - exp(-settings.fov_sharpness * delta))


func _apply_rotation() -> void:
	_pitch = clampf(_pitch, deg_to_rad(settings.min_pitch_degrees), deg_to_rad(settings.max_pitch_degrees))
	_yaw = wrapf(_yaw, -PI, PI)
	_yaw_node.rotation = Vector3(0.0, _yaw, 0.0)
	_pitch_node.rotation = Vector3(_pitch, 0.0, 0.0)


func _invert_sign() -> float:
	return -1.0 if Settings.invert_y else 1.0
