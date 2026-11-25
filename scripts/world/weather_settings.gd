class_name WeatherSettings
extends Resource
## The city's weather (GDD §12): the kinds of weather, how long each spell lasts and how quickly
## one turns into the next. Edit resources/world/weather.tres.

@export var looks: Array[WeatherLook] = []
## A spell of weather lasts between these many real minutes.
@export var min_minutes: float = 4.0
@export var max_minutes: float = 9.0
## Seconds one weather takes to turn into the next.
@export var transition_seconds: float = 45.0
## Seconds the ground takes to get fully wet in rain, and to dry out again.
@export var wet_seconds: float = 40.0
@export var dry_seconds: float = 150.0


func get_look(look_id: StringName) -> WeatherLook:
	for look: WeatherLook in looks:
		if look.id == look_id:
			return look
	return looks[0] if not looks.is_empty() else null


## The next weather after `current`, by the looks' weights (never the same one twice running).
func pick_next(current: StringName, rng: RandomNumberGenerator) -> WeatherLook:
	var total: float = 0.0
	for look: WeatherLook in looks:
		total += look.weight if look.id != current else 0.0
	var roll: float = rng.randf() * total
	for look: WeatherLook in looks:
		if look.id == current:
			continue
		roll -= look.weight
		if roll <= 0.0:
			return look
	return looks[0]
