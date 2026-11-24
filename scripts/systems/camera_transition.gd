class_name CameraTransition
extends Camera3D
## Smoothly hands the view from the current camera to another one: it takes over at the old
## camera's position, eases towards the new camera's live position and field of view, then
## makes the new camera current. Used between the on-foot and vehicle cameras (and later
## cutscenes). Place it after the camera rigs in the scene so it reads their updated positions.

signal finished(target: Camera3D)

var _target: Camera3D
var _from: Transform3D = Transform3D.IDENTITY
var _from_fov: float = 70.0
var _elapsed: float = 0.0
var _duration: float = 0.5


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 100
	set_process(false)


## Blends to `target` over `seconds` (0 = cut).
func blend_to(target: Camera3D, seconds: float) -> void:
	var viewport_camera: Camera3D = get_viewport().get_camera_3d()
	var start: Camera3D = viewport_camera if viewport_camera != null else target
	if seconds <= 0.0 or start == target:
		_finish(target)
		return
	_from = start.global_transform
	_from_fov = start.fov
	_target = target
	_elapsed = 0.0
	_duration = seconds
	global_transform = _from
	fov = _from_fov
	near = target.near
	far = target.far
	make_current()
	set_process(true)


func is_blending() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = smoothstep(0.0, 1.0, clampf(_elapsed / _duration, 0.0, 1.0))
	var goal: Transform3D = _target.global_transform
	global_transform = Transform3D(_from.basis.slerp(goal.basis, t).orthonormalized(), _from.origin.lerp(goal.origin, t))
	fov = lerpf(_from_fov, _target.fov, t)
	if _elapsed >= _duration:
		_finish(_target)


func _finish(target: Camera3D) -> void:
	set_process(false)
	target.make_current()
	_target = null
	finished.emit(target)
