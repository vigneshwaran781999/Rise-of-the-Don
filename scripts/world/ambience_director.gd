class_name AmbienceDirector
extends Node
## The background sound of the city (GDD §13: ambience per district): mixes the looping ambience
## layers (AudioManager.set_ambience) for where the player is (AmbienceSettings: the district's
## layers, birds by day and crickets at night, the city's hum quieter at night, waves near the
## coast) and muffles them while the player is in a vehicle. Levels fade as they change. Rain is
## the weather's own layer, not touched here.

const LAYERS: Array[StringName] = [&"amb_city", &"amb_waves", &"amb_industrial", &"amb_birds", &"amb_crickets"]
## Seconds between working out the targets.
const INTERVAL: float = 0.25

@export var settings: AmbienceSettings

var _player: PlayerController
var _regions: RegionWatcher
var _levels: Dictionary = {}       # layer -> level now
var _targets: Dictionary = {}      # layer -> level wanted
var _timer: float = 0.0


func setup(player: PlayerController, regions: RegionWatcher) -> void:
	_player = player
	_regions = regions
	for layer: StringName in LAYERS:
		_levels[layer] = 0.0
		_targets[layer] = 0.0
	_update_targets()
	for layer: StringName in LAYERS:       # arriving: start at the right mix
		_levels[layer] = _targets[layer]
		AudioManager.set_ambience(layer, _levels[layer])


func _exit_tree() -> void:
	for layer: StringName in LAYERS:
		AudioManager.set_ambience(layer, 0.0)


## The level a layer is playing at now (tests).
func get_level(layer: StringName) -> float:
	return float(_levels.get(layer, 0.0))


func _process(delta: float) -> void:
	if _player == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = INTERVAL
		_update_targets()
	for layer: StringName in LAYERS:
		var now: float = _levels[layer]
		var next: float = move_toward(now, _targets[layer], settings.fade_per_second * delta)
		if not is_equal_approx(next, now):
			_levels[layer] = next
			AudioManager.set_ambience(layer, next)


func _update_targets() -> void:
	var day: Dictionary = settings.district_layers.get(String(_regions.get_current_id()), {})
	var night: float = GameState.get_darkness()
	var inside: float = settings.vehicle_scale if _player.is_in_vehicle() else 1.0
	for layer: StringName in LAYERS:
		var level: float = float(day.get(String(layer), 0.0))
		if layer == settings.day_layer:
			level *= 1.0 - night
		elif layer == settings.night_layer:
			level = float(day.get(String(settings.day_layer), 0.0)) * settings.night_layer_scale * night
		elif layer == &"amb_city":
			level *= lerpf(1.0, settings.city_night_scale, night)
		elif layer == &"amb_waves":
			var inland: float = CityLayout.COAST_X - _player.global_position.x
			level = maxf(level, settings.waves_level * clampf(1.0 - inland / settings.waves_reach, 0.0, 1.0))
		_targets[layer] = clampf(level * inside, 0.0, 1.0)
