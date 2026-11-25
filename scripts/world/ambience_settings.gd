class_name AmbienceSettings
extends Resource
## How each district sounds (GDD §13: "city ambience per district"): the level of each looping
## ambience layer there by day, and how night, the coast and being in a vehicle change it. Edit
## resources/world/ambience.tres.

## Region id (CityData.region_ids) -> {layer: level 0-1}, by day.
@export var district_layers: Dictionary = {}
## Layers that sing by day and go quiet at night (birds), and the layer that takes over then.
@export var day_layer: StringName = &"amb_birds"
@export var night_layer: StringName = &"amb_crickets"
## How loud the night layer gets where the day layer was at full level.
@export var night_layer_scale: float = 0.9
## The city's hum by night (a share of its daytime level).
@export var city_night_scale: float = 0.6
## Waves: loudest at the water's edge (CityLayout.COAST_X), gone this many metres inland.
@export var waves_reach: float = 150.0
@export var waves_level: float = 0.75
## Everything outside is muffled to this share inside a vehicle.
@export var vehicle_scale: float = 0.45
## How fast levels follow (level units per second): crossing into a district fades its sounds in.
@export var fade_per_second: float = 0.35
