class_name LightingPreset
extends Resource
## Sun, sky, fog and post-processing for one time of day (GDD §12).
## The M6 TimeOfDay system is meant to blend between presets like this one.

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
