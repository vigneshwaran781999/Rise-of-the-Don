class_name WeatherLook
extends Resource
## One kind of weather (GDD §12: clear, cloudy, fog, rain): how it changes the time of day's light
## (WeatherCycle applies it on top of the day/night look) and what falls from the sky.

@export var id: StringName = &"clear"
@export var display_name: String = "Clear"
## How likely this weather is to come next (relative to the others).
@export var weight: float = 1.0

@export_group("Light")
## Multiplies the sun's (or moon's) light and the sky's ambient light.
@export var sun_energy_scale: float = 1.0
@export var ambient_scale: float = 1.0
## How far the sky and the fog turn towards an overcast grey (0-1). The grey follows the time of
## day's brightness, so an overcast night stays dark.
@export_range(0.0, 1.0) var overcast: float = 0.0
@export var overcast_tint: Color = Color(0.9, 0.93, 1.0)
## Added to the fog density.
@export var fog_density_add: float = 0.0
@export var saturation_scale: float = 1.0
## Multiplies the exposure (rain and heavy cloud look darker than the light alone would make them).
@export var exposure_scale: float = 1.0
## Clouds drawn over the sky (0 = none).
@export_range(0.0, 1.0) var cloud_cover: float = 0.15

@export_group("Rain")
## How hard it rains (0-1): the particles near the camera and the rain sound.
@export_range(0.0, 1.0) var rain: float = 0.0
## How wet the ground gets in this weather (it dries slowly afterwards).
@export_range(0.0, 1.0) var wetness: float = 0.0
