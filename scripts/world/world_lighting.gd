class_name WorldLighting
extends Node3D
## Creates the WorldEnvironment (procedural sky, ambient light, fog, ACES tonemapping, glow,
## SSAO, colour adjustment) and the sun DirectionalLight3D, and shows a LightingPreset with them.
## apply() can be called again at any time (the day/night cycle does, with blended presets): it
## updates the existing sky and environment rather than building new ones.

@export var preset: LightingPreset

var sun: DirectionalLight3D
var world_environment: WorldEnvironment
var _sky_material: ProceduralSkyMaterial
var _env: Environment


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = _sky_material
	# Spread sky lighting updates over several frames (the day/night cycle changes the sky often).
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = true
	_env.glow_bloom = 0.04
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	_env.ssao_radius = 1.2
	_env.ssao_intensity = 1.6
	_env.fog_enabled = true
	_env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	_env.adjustment_enabled = true
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = _env
	add_child(world_environment)
	apply(preset)


func apply(p: LightingPreset) -> void:
	var elevation: float = deg_to_rad(p.sun_elevation_degrees)
	var azimuth: float = deg_to_rad(p.sun_azimuth_degrees)
	var to_sun := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
	sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.directional_shadow_max_distance = p.shadow_max_distance
	_sky_material.sky_top_color = p.sky_top_color
	_sky_material.sky_horizon_color = p.sky_horizon_color
	_sky_material.ground_horizon_color = p.ground_horizon_color
	_sky_material.ground_bottom_color = p.ground_bottom_color
	_env.ambient_light_energy = p.ambient_energy
	_env.tonemap_exposure = p.exposure
	_env.glow_intensity = p.glow_intensity
	_env.ssao_enabled = p.ssao_enabled
	_env.fog_light_color = p.fog_color
	_env.fog_density = p.fog_density
	_env.fog_sun_scatter = p.fog_sun_scatter
	_env.fog_aerial_perspective = p.fog_aerial_perspective
	_env.fog_sky_affect = p.fog_sky_affect
	_env.adjustment_saturation = p.saturation
	_env.adjustment_contrast = p.contrast
