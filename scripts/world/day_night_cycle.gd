class_name DayNightCycle
extends Node
## Shows GameState's clock in the world (GDD §12): blends the sun, sky, fog and post-processing
## between the DayNightSettings looks, turns the city lights on at dusk (the city_lights shader
## global that lights streetlight lenses and windows, the pool of real streetlights near the
## camera) and tells everyone when it gets dark (car headlights).

## Darkness passed one half (true = night: headlights on).
signal darkness_changed(dark: bool)

@export var settings: DayNightSettings
## Seconds between lighting updates (a game minute passes every real second by default).
@export var update_interval: float = 0.5

var street_lights: StreetLightPool

var _lighting: WorldLighting
var _timer: float = 0.0
var _dark: bool = false
var _last_hour: float = -100.0


func setup(lighting: WorldLighting, streamer: WorldStreamer) -> void:
	_lighting = lighting
	street_lights = StreetLightPool.new()
	street_lights.name = "StreetLights"
	street_lights.light_range = settings.street_light_range
	street_lights.light_energy = settings.street_light_energy
	add_child(street_lights)
	street_lights.setup(streamer, settings.real_street_lights)
	refresh()


func is_dark() -> bool:
	return _dark


## Applies the current time at once (after loading, sleeping or a test setting the clock).
func refresh() -> void:
	_timer = update_interval
	_apply()


func _process(delta: float) -> void:
	if _lighting == null:
		return
	_timer -= delta
	if _timer <= 0.0 or absf(GameState.hour - _last_hour) > 0.25:
		_timer = update_interval
		_apply()


func _apply() -> void:
	_last_hour = GameState.hour
	_lighting.apply(settings.preset_at(GameState.hour))
	var darkness: float = settings.city_lights_at(GameState.hour)
	RenderingServer.global_shader_parameter_set(&"city_lights", darkness)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		street_lights.update(camera.global_position, darkness)
	var dark: bool = darkness > 0.5
	if dark != _dark:
		_dark = dark
		darkness_changed.emit(dark)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"city_lights", 0.0)
