extends Node
## Facts about the current playthrough that belong to no other system: time played and the
## running stats (GDD §14 saves them). Autoload: GameState.

## Counts play time while true (the game session sets it; pausing stops it, as this node pauses).
var playing: bool = false
var play_time: float = 0.0
var stats: Dictionary = {}


func _ready() -> void:
	MissionManager.mission_passed.connect(func(_mission: MissionData) -> void: add_stat(&"missions_passed"))
	MissionManager.mission_failed.connect(func(_mission: MissionData, _reason: String) -> void: add_stat(&"missions_failed"))
	EconomyManager.cash_changed.connect(_on_cash_changed)


func _process(delta: float) -> void:
	if playing:
		play_time += delta


func start_new_game() -> void:
	play_time = 0.0
	stats = {&"missions_passed": 0, &"missions_failed": 0, &"cash_earned": 0}


func add_stat(key: StringName, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount


func get_stat(key: StringName) -> int:
	return int(stats.get(key, 0))


func to_save() -> Dictionary:
	var saved: Dictionary = {}
	for key: StringName in stats:
		saved[String(key)] = stats[key]
	return {"play_time": play_time, "stats": saved}


func from_save(data: Dictionary) -> void:
	start_new_game()
	play_time = float(data.get("play_time", 0.0))
	var saved: Dictionary = data.get("stats", {})
	for key: Variant in saved:
		stats[StringName(str(key))] = int(saved[key])


## "1:05:09" or "12:34" for a play time in seconds.
static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]


func _on_cash_changed(_cash: int, delta: int, reason: StringName) -> void:
	if delta > 0 and reason != &"set":
		add_stat(&"cash_earned", delta)
