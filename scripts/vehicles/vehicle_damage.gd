class_name VehicleDamage
extends Node
## Collision damage (GDD §5): a crash is a sudden change of speed while the body is touching
## something. Health drops with the size of the impact above a threshold, smoke pours from the
## engine bay when health is low, and at zero the engine dies (the car is wrecked).
## Must be a direct child of a VehicleController that has a SmokePoint marker.

signal health_changed(current: float, maximum: float)
## impact_kmh is the change of speed in the crash; damage is the health it cost.
signal impacted(impact_kmh: float, damage: float)
signal wrecked

## A crash spreads over a few physics ticks; this many ticks are summed into one impact.
const IMPACT_WINDOW_TICKS: int = 5
## A change of speed in a single tick above this (km/h) starts an impact. Hard braking is
## about 0.6 km/h per tick, so this only catches collisions.
const JOLT_KMH_PER_TICK: float = 3.0

var health: float = 0.0

var _vehicle: VehicleController
var _smoke: GPUParticles3D
var _smoke_material: ParticleProcessMaterial
var _previous_velocity: Vector3 = Vector3.ZERO
var _impact_start_velocity: Vector3 = Vector3.ZERO
var _impact_ticks_left: int = 0
var _touching_ticks: int = 0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	health = _vehicle.stats.max_health
	_smoke = _make_smoke()
	(_vehicle.get_node("SmokePoint") as Node3D).add_child(_smoke)
	_update_smoke()
	_vehicle.teleported.connect(_on_teleported)


func get_health_fraction() -> float:
	return health / _vehicle.stats.max_health


func is_wrecked() -> bool:
	return health <= 0.0


func is_smoking() -> bool:
	return _smoke.emitting


## Back to full health (a respray garage): the smoke stops and a wrecked engine runs again.
func repair() -> void:
	var was_wrecked: bool = is_wrecked()
	health = _vehicle.stats.max_health
	health_changed.emit(health, _vehicle.stats.max_health)
	_update_smoke()
	if was_wrecked:
		_vehicle.set_engine_disabled(false)


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or is_wrecked():
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, _vehicle.stats.max_health)
	_update_smoke()
	if is_wrecked():
		_vehicle.set_engine_disabled(true)
		wrecked.emit()


func _physics_process(_delta: float) -> void:
	var velocity: Vector3 = _vehicle.linear_velocity
	var flat_change := Vector2(velocity.x - _previous_velocity.x, velocity.z - _previous_velocity.z)
	_touching_ticks = 3 if _vehicle.get_contact_count() > 0 else maxi(_touching_ticks - 1, 0)
	if _impact_ticks_left > 0:
		_impact_ticks_left -= 1
		if _impact_ticks_left == 0:
			_resolve_impact(velocity)
	elif flat_change.length() * 3.6 > JOLT_KMH_PER_TICK and _touching_ticks > 0:
		_impact_start_velocity = _previous_velocity
		_impact_ticks_left = IMPACT_WINDOW_TICKS
	_previous_velocity = velocity


func _on_teleported() -> void:
	_previous_velocity = Vector3.ZERO
	_impact_ticks_left = 0


func _resolve_impact(velocity: Vector3) -> void:
	var change := Vector2(velocity.x - _impact_start_velocity.x, velocity.z - _impact_start_velocity.z)
	var impact_kmh: float = change.length() * 3.6
	var stats: VehicleStats = _vehicle.stats
	var damage: float = maxf(0.0, impact_kmh - stats.impact_threshold_kmh) * stats.damage_per_kmh
	impacted.emit(impact_kmh, damage)
	apply_damage(damage)


func _update_smoke() -> void:
	var share: float = get_health_fraction()
	var stats: VehicleStats = _vehicle.stats
	_smoke.emitting = share < stats.smoke_below
	if is_wrecked():
		_smoke.amount_ratio = 1.0
		_smoke_material.color = Color(0.08, 0.08, 0.09, 0.85)
	elif share < stats.heavy_smoke_below:
		_smoke.amount_ratio = 1.0
		_smoke_material.color = Color(0.24, 0.24, 0.26, 0.7)
	else:
		_smoke.amount_ratio = 0.45
		_smoke_material.color = Color(0.62, 0.62, 0.63, 0.38)


func _make_smoke() -> GPUParticles3D:
	_smoke_material = ParticleProcessMaterial.new()
	_smoke_material.direction = Vector3.UP
	_smoke_material.spread = 18.0
	_smoke_material.initial_velocity_min = 0.8
	_smoke_material.initial_velocity_max = 1.6
	_smoke_material.gravity = Vector3(0.0, 0.9, 0.0)
	_smoke_material.damping_min = 0.6
	_smoke_material.damping_max = 1.0
	_smoke_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_smoke_material.emission_box_extents = Vector3(0.35, 0.05, 0.25)
	_smoke_material.angle_min = -180.0
	_smoke_material.angle_max = 180.0
	_smoke_material.scale_min = 0.6
	_smoke_material.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.4))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	_smoke_material.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.12, Color(1.0, 1.0, 1.0, 1.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	_smoke_material.color_ramp = fade_texture

	var puff := Gradient.new()
	puff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	puff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var puff_texture := GradientTexture2D.new()
	puff_texture.gradient = puff
	puff_texture.fill = GradientTexture2D.FILL_RADIAL
	puff_texture.fill_from = Vector2(0.5, 0.5)
	puff_texture.fill_to = Vector2(1.0, 0.5)
	puff_texture.width = 64
	puff_texture.height = 64
	var draw := StandardMaterial3D.new()
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = puff_texture
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = draw

	var particles := GPUParticles3D.new()
	particles.name = "Smoke"
	particles.amount = 36
	particles.lifetime = 1.8
	particles.process_material = _smoke_material
	particles.draw_pass_1 = quad
	particles.visibility_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 8.0, 6.0))
	particles.local_coords = false
	particles.emitting = false
	return particles
