class_name DayNightSettings
extends Resource
## The day/night cycle (GDD §12): how long a day lasts, the looks it blends between through the
## day, and when the city's lights come on. Edit res://resources/world/day_night.tres.

## Real minutes for one in-game day (GDD default: 24, so an in-game hour is a real minute).
@export var day_length_minutes: float = 24.0
## Clock on New Game, in hours.
@export_range(0.0, 24.0) var start_hour: float = 16.5
## Looks through the day, each at its LightingPreset.hour; blended in between (wrapping at
## midnight). Order doesn't matter.
@export var keys: Array[LightingPreset] = []

@export_group("City lights")
## Streetlights, lit windows and car headlights come on at this hour...
@export_range(0.0, 24.0) var lights_on_hour: float = 18.25
## ...and go off at this one,
@export_range(0.0, 24.0) var lights_off_hour: float = 6.5
## fading over this many hours.
@export var lights_fade_hours: float = 0.5
## How many streetlights near the camera cast real light (the rest only glow).
@export var real_street_lights: int = 10


## The look at `hour`, blended from the two keys either side of it.
func preset_at(hour: float) -> LightingPreset:
	var sorted: Array[LightingPreset] = keys.duplicate()
	sorted.sort_custom(func(a: LightingPreset, b: LightingPreset) -> bool: return a.hour < b.hour)
	if sorted.is_empty():
		return LightingPreset.new()
	if sorted.size() == 1:
		return sorted[0]
	var h: float = fposmod(hour, 24.0)
	for i: int in sorted.size():
		var a: LightingPreset = sorted[i]
		var b: LightingPreset = sorted[(i + 1) % sorted.size()]
		var start: float = a.hour
		var end: float = b.hour if b.hour > a.hour else b.hour + 24.0
		var t_hour: float = h if h >= start else h + 24.0
		if t_hour >= start and t_hour <= end:
			var p: LightingPreset = LightingPreset.blend(a, b, (t_hour - start) / maxf(end - start, 0.001))
			p.hour = h
			return p
	return sorted[0]


## How far the city lights are on at `hour`: 0 by day, 1 at night, fading in between.
func city_lights_at(hour: float) -> float:
	var h: float = fposmod(hour, 24.0)
	var on: float = clampf((h - lights_on_hour) / lights_fade_hours, 0.0, 1.0)
	var off: float = 1.0 - clampf((h - lights_off_hour) / lights_fade_hours, 0.0, 1.0)
	return on if h >= 12.0 else off
