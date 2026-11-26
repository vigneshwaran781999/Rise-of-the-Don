extends Node
## Facts about the current playthrough that belong to no other system: the in-game clock and
## day (GDD §12; one day lasts DayNightSettings.day_length_minutes of play) and the weather (the
## WeatherCycle sets it; a WeatherLook id), the outfit the player
## is wearing (GDD §9; Outfit ids, bought through EconomyManager), time played and the
## running stats. All of it is saved (GDD §14). Autoload: GameState.

## A new in-game day began (the clock passed midnight).
signal day_changed(day: int)
## The player changed clothes (or a save was loaded); &"" is the clothes they arrived in.
signal outfit_changed(outfit_id: StringName)

const DAY_NIGHT: DayNightSettings = preload("res://resources/world/day_night.tres")

## Counts play time and runs the clock while true (the game session sets it; pausing stops
## both, as this node pauses).
var playing: bool = false
var play_time: float = 0.0
var stats: Dictionary = {}
## In-game time of day in hours (0-24).
var hour: float = 16.5
## Outfit being worn (&"" = the clothes the player arrived in).
var outfit: StringName = &""
## In-game day, from 1.
var day: int = 1
## The weather (a WeatherLook id in resources/world/weather.tres; WeatherCycle changes it).
var weather: StringName = &"clear"
## The story's decisions (M7 CHOICE objectives): answer index by choice id.
var choices: Dictionary = {}


func _ready() -> void:
	MissionManager.mission_passed.connect(func(_mission: MissionData) -> void: add_stat(&"missions_passed"))
	MissionManager.mission_failed.connect(func(_mission: MissionData, _reason: String) -> void: add_stat(&"missions_failed"))
	EconomyManager.cash_changed.connect(_on_cash_changed)


func _process(delta: float) -> void:
	if not playing:
		return
	play_time += delta
	advance_hours(delta * 24.0 / (DAY_NIGHT.day_length_minutes * 60.0))


func start_new_game() -> void:
	play_time = 0.0
	stats = {&"missions_passed": 0, &"missions_failed": 0, &"cash_earned": 0}
	hour = DAY_NIGHT.start_hour
	day = 1
	weather = &"clear"
	set_outfit(&"")
	choices.clear()


## Moves the clock on (sleeping, tests); passing midnight starts a new day.
func advance_hours(hours: float) -> void:
	hour += hours
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_changed.emit(day)


## Sets the clock to `new_hour` today (no new day).
func set_hour(new_hour: float) -> void:
	hour = fposmod(new_hour, 24.0)


## "18:45"
func get_clock_text() -> String:
	var minutes: int = int(hour * 60.0) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


## How far the city lights are on now (0 by day, 1 at night).
func get_darkness() -> float:
	return DAY_NIGHT.city_lights_at(hour)


func add_stat(key: StringName, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func get_stat(key: StringName) -> int:
	return int(stats.get(key, 0))


func to_save() -> Dictionary:
	var saved: Dictionary = {}
	for key: StringName in stats:
		saved[String(key)] = stats[key]
	var answers: Dictionary = {}
	for key: StringName in choices:
		answers[String(key)] = choices[key]
	return {"play_time": play_time, "stats": saved, "hour": hour, "day": day, "outfit": String(outfit), "weather": String(weather),
		"choices": answers}


func from_save(data: Dictionary) -> void:
	start_new_game()
	play_time = float(data.get("play_time", 0.0))
	hour = fposmod(float(data.get("hour", DAY_NIGHT.start_hour)), 24.0)
	day = maxi(int(data.get("day", 1)), 1)
	weather = StringName(str(data.get("weather", "clear")))
	set_outfit(StringName(str(data.get("outfit", ""))))
	var saved: Dictionary = data.get("stats", {})
	for key: Variant in saved:
		stats[StringName(str(key))] = int(saved[key])
	var answers: Dictionary = data.get("choices", {})
	for key: Variant in answers:
		choices[StringName(str(key))] = int(answers[key])


## "1:05:09" or "12:34" for a play time in seconds.
static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func _on_cash_changed(_cash: int, delta: int, reason: StringName) -> void:
	if delta > 0 and reason != &"set":
		add_stat(&"cash_earned", delta)


func set_outfit(outfit_id: StringName) -> void:
	outfit = outfit_id
	outfit_changed.emit(outfit)


## Records the answer (an index) to story choice `id`.
func set_choice(id: StringName, answer: int) -> void:
	choices[id] = answer


## The answer given to story choice `id`, or -1 if it hasn't come up.
func get_choice(id: StringName) -> int:
	return int(choices.get(id, -1))
