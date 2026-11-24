class_name WorldLighting
extends Node3D
## Creates the WorldEnvironment (procedural sky, ambient light, fog, ACES tonemapping, glow,
## SSAO, colour adjustment) and the sun DirectionalLight3D from a LightingPreset.

@export var preset: LightingPreset

var sun: DirectionalLight3D
var world_environment: WorldEnvironment


func _ready() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)
	world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
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

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = p.sky_top_color
	sky_material.sky_horizon_color = p.sky_horizon_color
	sky_material.ground_horizon_color = p.ground_horizon_color
	sky_material.ground_bottom_color = p.ground_bottom_color
	sky_material.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = p.exposure
	env.glow_enabled = true
	env.glow_intensity = p.glow_intensity
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = p.ssao_enabled
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = p.fog_color
	env.fog_density = p.fog_density
	env.fog_sun_scatter = p.fog_sun_scatter
	env.fog_aerial_perspective = p.fog_aerial_perspective
	env.fog_sky_affect = p.fog_sky_affect
	env.adjustment_enabled = true
	env.adjustment_saturation = p.saturation
	env.adjustment_contrast = p.contrast
	world_environment.environment = env
