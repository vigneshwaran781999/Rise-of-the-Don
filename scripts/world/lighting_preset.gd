class_name LightingPreset
extends Resource
## Sun, sky, fog and post-processing for one time of day (GDD §12). The day/night cycle
## (DayNightCycle) blends between presets like this one by their `hour`.

## Time of day this look belongs to, in hours (0-24), when used in a day/night cycle.
@export_range(0.0, 24.0) var hour: float = 16.5

@export_group("Sun")
@export_range(-10.0, 90.0) var sun_elevation_degrees: float = 22.0
## Compass bearing of the sun: 0 = north (-Z), 90 = east (+X), 180 = south, 270 = west.
@export_range(0.0, 360.0) var sun_azimuth_degrees: float = 250.0
@export var sun_color: Color = Color(1.0, 0.8, 0.6)
@export var sun_energy: float = 1.5
@export var shadow_max_distance: float = 140.0

@export_group("Sky")
@export var sky_top_color: Color = Color(0.22, 0.42, 0.72)
@export var sky_horizon_color: Color = Color(0.95, 0.74, 0.56)
@export var ground_horizon_color: Color = Color(0.78, 0.62, 0.5)
@export var ground_bottom_color: Color = Color(0.2, 0.17, 0.15)

@export_group("Ambient and fog")
@export var ambient_energy: float = 0.65
@export var fog_color: Color = Color(0.9, 0.74, 0.6)
@export var fog_density: float = 0.0035
@export_range(0.0, 1.0) var fog_sun_scatter: float = 0.3
@export_range(0.0, 1.0) var fog_aerial_perspective: float = 0.5
@export_range(0.0, 1.0) var fog_sky_affect: float = 0.35

@export_group("Post-processing")
@export var exposure: float = 1.0
@export var saturation: float = 1.12
@export var contrast: float = 1.06
@export var glow_intensity: float = 0.55
@export var ssao_enabled: bool = true


## A preset part-way from `a` to `b` (t = 0..1); the sun takes the short way round the compass.
static func blend(a: LightingPreset, b: LightingPreset, t: float) -> LightingPreset:
	var p := LightingPreset.new()
	p.hour = lerpf(a.hour, b.hour, t)
	p.sun_elevation_degrees = lerpf(a.sun_elevation_degrees, b.sun_elevation_degrees, t)
	p.sun_azimuth_degrees = fposmod(rad_to_deg(lerp_angle(deg_to_rad(a.sun_azimuth_degrees), deg_to_rad(b.sun_azimuth_degrees), t)), 360.0)
	p.sun_color = a.sun_color.lerp(b.sun_color, t)
	p.sun_energy = lerpf(a.sun_energy, b.sun_energy, t)
	p.shadow_max_distance = lerpf(a.shadow_max_distance, b.shadow_max_distance, t)
	p.sky_top_color = a.sky_top_color.lerp(b.sky_top_color, t)
	p.sky_horizon_color = a.sky_horizon_color.lerp(b.sky_horizon_color, t)
	p.ground_horizon_color = a.ground_horizon_color.lerp(b.ground_horizon_color, t)
	p.ground_bottom_color = a.ground_bottom_color.lerp(b.ground_bottom_color, t)
	p.ambient_energy = lerpf(a.ambient_energy, b.ambient_energy, t)
	p.fog_color = a.fog_color.lerp(b.fog_color, t)
	p.fog_density = lerpf(a.fog_density, b.fog_density, t)
	p.fog_sun_scatter = lerpf(a.fog_sun_scatter, b.fog_sun_scatter, t)
	p.fog_aerial_perspective = lerpf(a.fog_aerial_perspective, b.fog_aerial_perspective, t)
	p.fog_sky_affect = lerpf(a.fog_sky_affect, b.fog_sky_affect, t)
	p.exposure = lerpf(a.exposure, b.exposure, t)
	p.saturation = lerpf(a.saturation, b.saturation, t)
	p.contrast = lerpf(a.contrast, b.contrast, t)
	p.glow_intensity = lerpf(a.glow_intensity, b.glow_intensity, t)
	p.ssao_enabled = a.ssao_enabled if t < 0.5 else b.ssao_enabled
	return p
