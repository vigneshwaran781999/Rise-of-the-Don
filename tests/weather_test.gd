extends Node
## Weather test (per-feature test scene, M7). Runs the real game scene and checks the weather
## (GDD §12): a new game starts clear; rain dims the sun, greys the sky, falls near the camera, is
## heard and wets the ground; fog thickens the fog; clouds cover the sky; changes blend over time
## and the ground dries slowly afterwards; the cycle moves on from one weather to the next by
## itself; the weather is saved and loaded.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/weather_test.tscn
## Prints "WEATHER TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")

var _catcher: ErrorCatcher
var _game: GameSession
var _weather: WeatherCycle
var _cycle: DayNightCycle
var _lighting: WorldLighting
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	SaveManager.save_dir = "user://test_saves"
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_weather = _game.get_node("Weather") as WeatherCycle
	_cycle = _game.get_node("DayNight") as DayNightCycle
	_lighting = _game.world.get_node("Lighting") as WorldLighting
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	var steps: Array[Callable] = [_check_new_game, _check_rain, _check_fog_and_clouds, _check_blend_and_drying, _check_cycle, _check_save]
	var failure: String = ""
	for step: Callable in steps:
		failure = await step.call()
		if failure != "":
			failure = "%s: %s" % [step.get_method(), failure]
			break
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "%s: engine/script error: %s" % [step.get_method(), errors[0]]
			break
	print("WEATHER REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("WEATHER TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


## The look at noon in `weather_id` (set at once): [sun energy, fog density, cloud cover, sky top].
func _look_in(weather_id: StringName) -> Array:
	_weather.set_weather(weather_id, true)
	GameState.set_hour(12.0)
	_cycle.refresh()
	await _ticks(3)
	var env: Environment = _lighting.world_environment.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	return [_lighting.sun.light_energy, env.fog_density, _lighting.get_cloud_cover(), sky.sky_top_color]


func _check_new_game() -> String:
	if GameState.weather != &"clear" or _weather.get_weather() != &"clear":
		return "New Game should start in clear weather (%s)" % GameState.weather
	if _weather.get_rain() > 0.0 or _weather.get_rain_effect().get_intensity() > 0.0 or AudioManager.get_ambience(&"rain") > 0.0:
		return "no rain should fall or be heard in clear weather"
	if _weather.get_wetness() > 0.01:
		return "the ground should be dry at the start (wetness %.2f)" % _weather.get_wetness()
	_note("New Game: clear weather, no rain, dry ground")
	return ""


func _check_rain() -> String:
	var clear: Array = await _look_in(&"clear")
	var rain: Array = await _look_in(&"rain")
	var drops: RainEffect = _weather.get_rain_effect()
	if float(rain[0]) > float(clear[0]) * 0.5:
		return "rain should dim the sun (%.2f against %.2f clear)" % [rain[0], clear[0]]
	var clear_sky: Color = clear[3]
	var rain_sky: Color = rain[3]
	if rain_sky.s > clear_sky.s * 0.7:
		return "rain should grey the sky (saturation %.2f against %.2f clear)" % [rain_sky.s, clear_sky.s]
	if not drops.emitting or drops.get_intensity() < 0.9:
		return "rain should fall near the camera (intensity %.2f)" % drops.get_intensity()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and Vector2(drops.global_position.x - camera.global_position.x, drops.global_position.z - camera.global_position.z).length() > 1.0:
		return "the rain should follow the camera"
	if AudioManager.get_ambience(&"rain") < 0.5:
		return "rain should be heard (level %.2f)" % AudioManager.get_ambience(&"rain")
	if _weather.get_wetness() < 0.99:
		return "set at once, rain should leave the ground wet (wetness %.2f)" % _weather.get_wetness()
	_note("rain: sun %.2f (clear %.2f), sky saturation %.2f (clear %.2f), drops falling round the camera, rain heard at %.2f, ground wet" % [
		rain[0], clear[0], rain_sky.s, clear_sky.s, AudioManager.get_ambience(&"rain")])
	return ""


func _check_fog_and_clouds() -> String:
	var clear: Array = await _look_in(&"clear")
	var fog: Array = await _look_in(&"fog")
	var cloudy: Array = await _look_in(&"cloudy")
	if float(fog[1]) < float(clear[1]) + 0.01:
		return "fog should thicken the fog (density %.4f against %.4f clear)" % [fog[1], clear[1]]
	if float(cloudy[2]) < 0.6 or float(clear[2]) > 0.3:
		return "cloudy weather should cover the sky with clouds (%.2f; clear %.2f)" % [cloudy[2], clear[2]]
	if float(cloudy[0]) >= float(clear[0]):
		return "cloud should dim the sun"
	if _weather.get_rain_effect().get_intensity() > 0.0:
		return "no rain should fall when it is cloudy"
	_note("fog: density %.4f (clear %.4f); cloudy: cloud cover %.2f (clear %.2f), sun %.2f" % [fog[1], clear[1], cloudy[2], clear[2], cloudy[0]])
	return ""


func _check_blend_and_drying() -> String:
	var settings: WeatherSettings = _weather.settings
	var transition: float = settings.transition_seconds
	settings.transition_seconds = 4.0
	_weather.set_weather(&"rain", true)
	await _ticks(10)
	_weather.set_weather(&"clear")
	await _ticks(120)                      # half-way through the change
	var halfway_rain: float = _weather.get_rain()
	await _ticks(180)
	var after_rain: float = _weather.get_rain()
	var wet_after: float = _weather.get_wetness()
	settings.transition_seconds = transition
	if halfway_rain < 0.3 or halfway_rain > 0.7:
		return "half-way from rain to clear it should rain about half as hard (%.2f)" % halfway_rain
	if after_rain > 0.0:
		return "once clear, it should stop raining (%.2f)" % after_rain
	if wet_after < 0.9:
		return "the ground should dry off slowly after rain (wetness %.2f 5 s later)" % wet_after
	_note("rain to clear blends over the transition (half-way %.2f), the ground dries slowly (still %.2f wet after 5 s)" % [halfway_rain, wet_after])
	return ""


func _check_cycle() -> String:
	var settings: WeatherSettings = _weather.settings
	var spell: Vector2 = Vector2(settings.min_minutes, settings.max_minutes)
	settings.min_minutes = 0.02
	settings.max_minutes = 0.02
	_weather.set_weather(&"clear", true)    # a new, short spell
	var seen: Dictionary = {}
	for i: int in 60 * 8:
		await get_tree().physics_frame
		seen[_weather.get_weather()] = true
	settings.min_minutes = spell.x
	settings.max_minutes = spell.y
	if seen.size() < 3:
		return "with 1.2 s spells, 8 s of play should go through several kinds of weather (%s)" % seen.keys()
	if GameState.weather != _weather.get_weather():
		return "GameState should hold the current weather"
	_note("the weather moves on by itself: %s in 8 s of 1.2 s spells" % [seen.keys()])
	return ""


func _check_save() -> String:
	_weather.set_weather(&"rain", true)
	var saved: Dictionary = GameState.to_save()
	_weather.set_weather(&"clear", true)
	GameState.from_save(saved)
	if GameState.weather != &"rain":
		return "the weather should be saved and loaded (%s)" % GameState.weather
	GameState.start_new_game()
	if GameState.weather != &"clear":
		return "a new game should start clear"
	_note("saved in rain, loaded: rain; a new game: clear")
	return ""


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
