class_name RainEffect
extends GPUParticles3D
## Rain (GDD §12: "GPU particles near the camera"): streaks falling through a box that follows the
## active camera, as many as the rain's intensity asks for (0 = none at all).

## The box the rain falls through, around and above the camera (half extents, metres).
const EXTENTS := Vector3(22.0, 9.0, 22.0)
const MAX_DROPS: int = 5000
const FALL_SPEED: float = 24.0

var _intensity: float = 0.0
var _look: StandardMaterial3D


func _ready() -> void:
	amount = MAX_DROPS
	lifetime = (EXTENTS.y * 2.0 + 4.0) / FALL_SPEED
	local_coords = false
	preprocess = lifetime
	emitting = false
	visibility_aabb = AABB(-EXTENTS - Vector3(4.0, 30.0, 4.0), (EXTENTS + Vector3(4.0, 30.0, 4.0)) * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = EXTENTS
	mat.direction = Vector3(0.08, -1.0, 0.04)
	mat.spread = 2.0
	mat.initial_velocity_min = FALL_SPEED * 0.9
	mat.initial_velocity_max = FALL_SPEED * 1.1
	mat.gravity = Vector3.ZERO
	process_material = mat
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.55)
	var look := StandardMaterial3D.new()
	_look = look
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(0.78, 0.84, 0.95, 0.32)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	look.billboard_keep_scale = true
	streak.material = look
	draw_pass_1 = streak


## How hard it rains: 0 stops it, 1 is a downpour.
func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	amount_ratio = _intensity
	emitting = _intensity > 0.01


## How bright the streaks are (1 by day; lower at night, as they are only lit by the city).
func set_brightness(value: float) -> void:
	_look.albedo_color = Color(0.78 * value, 0.84 * value, 0.95 * value, 0.32)


func get_intensity() -> float:
	return _intensity if emitting else 0.0


func _process(_delta: float) -> void:
	if not emitting:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * (EXTENTS.y * 0.6)
