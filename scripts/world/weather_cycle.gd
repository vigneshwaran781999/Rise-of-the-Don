class_name WeatherCycle
extends Node
## The weather (GDD §12): spells of clear, cloudy, foggy and rainy weather in turn (WeatherSettings),
## each blending into the next over a minute or so. It changes the day/night look before it is
## applied (modify(), called by DayNightCycle): less sun, a greyer sky, more fog, clouds. In rain
## it falls near the camera (RainEffect), the ground gets wet and shiny (the `wetness` shader
## global, which dries off slowly afterwards) and the rain is heard (AudioManager). The current
## weather lives in GameState, so saves keep it.

signal weather_changed(weather_id: StringName)

@export var settings: WeatherSettings

var _from: WeatherLook
var _to: WeatherLook
var _blend: float = 1.0          # 0 = all _from, 1 = all _to
var _spell: float = 0.0          # seconds left of the current weather
var _wetness: float = 0.0
var _lighting: WorldLighting
var _rain: RainEffect
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_rain = RainEffect.new()
	_rain.name = "Rain"
	add_child(_rain)
	var look: WeatherLook = settings.get_look(GameState.weather)
	_from = look
	_to = look
	_spell = _new_spell()
	_wetness = look.wetness


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"wetness", 0.0)
	AudioManager.set_ambience(&"rain", 0.0)


## Hooks the weather up to the world's sky (for the clouds).
func setup(lighting: WorldLighting) -> void:
	_lighting = lighting
	_apply_now()


## Changes the weather to `weather_id`: over the transition time, or at once (loading a save, tests).
func set_weather(weather_id: StringName, instant: bool = false) -> void:
	var look: WeatherLook = settings.get_look(weather_id)
	if look == null:
		return
	if instant:
		_from = look
		_wetness = look.wetness
		_blend = 1.0
	else:
		_from = _blended_snapshot()
		_blend = 0.0
	_to = look
	_spell = _new_spell()
	GameState.weather = look.id
	weather_changed.emit(look.id)
	_apply_now()


func get_weather() -> StringName:
	return _to.id


func get_weather_name() -> String:
	return _to.display_name


## How hard it is raining now (0-1).
func get_rain() -> float:
	return lerpf(_from.rain, _to.rain, _blend)


## How wet the ground is now (0-1).
func get_wetness() -> float:
	return _wetness


func get_rain_effect() -> RainEffect:
	return _rain


## The day/night look `preset` as this weather changes it.
func modify(preset: LightingPreset) -> LightingPreset:
	var p := preset.duplicate() as LightingPreset
	var overcast: float = lerpf(_from.overcast, _to.overcast, _blend)
	var tint: Color = _from.overcast_tint.lerp(_to.overcast_tint, _blend)
	# The overcast grey is as bright as the time of day's horizon, so night stays dark.
	var level: float = preset.sky_horizon_color.get_luminance()
	var grey := Color(tint.r * level, tint.g * level, tint.b * level)
	p.sun_energy = preset.sun_energy * lerpf(_from.sun_energy_scale, _to.sun_energy_scale, _blend)
	p.ambient_energy = preset.ambient_energy * lerpf(_from.ambient_scale, _to.ambient_scale, _blend)
	p.sky_top_color = preset.sky_top_color.lerp(grey * 0.85, overcast)
	p.sky_horizon_color = preset.sky_horizon_color.lerp(grey, overcast)
	p.ground_horizon_color = preset.ground_horizon_color.lerp(grey * 0.8, overcast)
	p.fog_color = preset.fog_color.lerp(grey, overcast)
	p.fog_density = preset.fog_density + lerpf(_from.fog_density_add, _to.fog_density_add, _blend)
	p.fog_sun_scatter = preset.fog_sun_scatter * (1.0 - overcast)
	p.saturation = preset.saturation * lerpf(_from.saturation_scale, _to.saturation_scale, _blend)
	p.exposure = preset.exposure * lerpf(_from.exposure_scale, _to.exposure_scale, _blend)
	return p


func _process(delta: float) -> void:
	if _to == null:
		return
	if GameState.playing:
		_spell -= delta
		if _spell <= 0.0:
			set_weather(settings.pick_next(_to.id, _rng).id)
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / maxf(settings.transition_seconds, 0.01))
	var target: float = lerpf(_from.wetness, _to.wetness, _blend)
	var rate: float = 1.0 / (settings.wet_seconds if target > _wetness else settings.dry_seconds)
	_wetness = move_toward(_wetness, target, rate * delta)
	_apply_now()


func _apply_now() -> void:
	var rain: float = get_rain()
	RenderingServer.global_shader_parameter_set(&"wetness", _wetness)
	_rain.set_intensity(rain)
	_rain.set_brightness(lerpf(1.0, 0.3, GameState.get_darkness()))
	AudioManager.set_ambience(&"rain", rain)
	if _lighting != null:
		_lighting.set_cloud_cover(lerpf(_from.cloud_cover, _to.cloud_cover, _blend))


func _new_spell() -> float:
	return _rng.randf_range(settings.min_minutes, settings.max_minutes) * 60.0


## The weather as it is right now, mid-blend, as a look to blend away from.
func _blended_snapshot() -> WeatherLook:
	var w := WeatherLook.new()
	w.id = _to.id
	w.display_name = _to.display_name
	w.sun_energy_scale = lerpf(_from.sun_energy_scale, _to.sun_energy_scale, _blend)
	w.ambient_scale = lerpf(_from.ambient_scale, _to.ambient_scale, _blend)
	w.overcast = lerpf(_from.overcast, _to.overcast, _blend)
	w.overcast_tint = _from.overcast_tint.lerp(_to.overcast_tint, _blend)
	w.fog_density_add = lerpf(_from.fog_density_add, _to.fog_density_add, _blend)
	w.saturation_scale = lerpf(_from.saturation_scale, _to.saturation_scale, _blend)
	w.exposure_scale = lerpf(_from.exposure_scale, _to.exposure_scale, _blend)
	w.cloud_cover = lerpf(_from.cloud_cover, _to.cloud_cover, _blend)
	w.rain = lerpf(_from.rain, _to.rain, _blend)
	w.wetness = lerpf(_from.wetness, _to.wetness, _blend)
	return w
