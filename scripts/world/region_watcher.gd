class_name RegionWatcher
extends Node
## Knows which district of the city the player is in (M7) and says when that changes: the HUD
## shows the district's name on arrival, and later the ambience follows it.

signal region_changed(index: int)

## Seconds between checks.
const INTERVAL: float = 0.5

var _player: Node3D
var _city: CityData
var _current: int = -1
var _timer: float = 0.0


func setup(player: Node3D, city: CityData) -> void:
	_player = player
	_city = city
	_current = city.region_at(player.global_position)


## Index of the district the player is in (CityData.region_*), or -1 outside every district.
func get_current() -> int:
	return _current


func get_current_name() -> String:
	return _city.get_region_name(_current) if _city != null else ""


func get_current_id() -> StringName:
	return _city.get_region_id(_current) if _city != null else &""


func _process(delta: float) -> void:
	if _player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	var now: int = _city.region_at(_player.global_position)
	if now == _current or now < 0:
		return
	# A district can span several cells (the Countryside): only a new name counts as arriving.
	var same_name: bool = _current >= 0 and _city.get_region_name(now) == _city.get_region_name(_current)
	_current = now
	if not same_name:
		region_changed.emit(now)
