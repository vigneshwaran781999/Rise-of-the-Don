class_name StoryClock
extends Node
## Puts the time of day and the weather where the story needs them (after 1.0). A mission started
## from the top, and each cutscene as it starts, can name a window of hours and a weather
## (MissionData / CutsceneData hour_from, hour_to, weather). Outside the window the clock skips
## forward to its start, never back, so days and rent tick over as usual; the play that follows
## happens at that time too. A mission's skip happens behind a quick fade, with a line saying the
## time; a cutscene's is hidden by its first cut. A weather named changes at once.

## A line for the HUD (the time after a skip).
signal message(text: String)

const FADE_IN_SECONDS: float = 0.8

var _day_night: DayNightCycle
var _weather: WeatherCycle
var _fade: ScreenFade


func _ready() -> void:
	_fade = ScreenFade.new()
	_fade.name = "Fade"
	add_child(_fade)


func _exit_tree() -> void:
	if MissionManager.mission_started.is_connected(_on_mission_started):
		MissionManager.mission_started.disconnect(_on_mission_started)


func setup(day_night: DayNightCycle, weather: WeatherCycle, cutscenes: CutscenePlayer) -> void:
	_day_night = day_night
	_weather = weather
	MissionManager.mission_started.connect(_on_mission_started)
	cutscenes.started.connect(_on_cutscene_started)


## Skips the clock forward into the window and sets the weather (&"" leaves it). The hours skipped.
func apply(hour_from: float, hour_to: float, weather_id: StringName) -> float:
	var hours: float = GameState.hours_until(hour_from, hour_to)
	if hours > 0.0:
		GameState.advance_hours(hours)
		_day_night.refresh()
	if weather_id != &"" and weather_id != GameState.weather:
		_weather.set_weather(weather_id, true)
	return hours


func _on_mission_started(mission: MissionData, checkpoint: int) -> void:
	if checkpoint != 0:
		return              # a retry or a resumed save carries on at the time it is
	if GameState.hours_until(mission.hour_from, mission.hour_to) > 0.0:
		_fade.set_alpha(1.0)
		apply(mission.hour_from, mission.hour_to, mission.weather)
		_fade.fade_to(0.0, FADE_IN_SECONDS)
		message.emit("Time passes. It's %s." % GameState.get_clock_text())
	else:
		apply(mission.hour_from, mission.hour_to, mission.weather)


func _on_cutscene_started(data: CutsceneData) -> void:
	apply(data.hour_from, data.hour_to, data.weather)
