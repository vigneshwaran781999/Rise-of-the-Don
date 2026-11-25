extends Node
## The wanted level (GDD §7), 0-5. Crimes add heat; the level is the highest whose heat threshold
## is reached, and it rises further the longer the police keep you in sight. Out of sight, the
## police search a circle around where they last saw you that shrinks over time; staying outside
## it long enough drops one level, until you are clear. Being arrested ("busted") clears it too.
## The game scene's PoliceManager reports what the police see through tick(); this node only
## keeps the state. Not saved (loading a game starts with a clean record). Autoload: WantedSystem.

signal level_changed(level: int)
## The police lost sight of you (searching) or found you again.
signal searching_changed(searching: bool)
signal busted

var tuning: WantedTuning = preload("res://resources/police/wanted.tres")

var level: int = 0
var heat: float = 0.0
## True while the police are searching (they can't see you).
var searching: bool = false
## Where the police last saw you (the centre of the search circle).
var last_known := Vector3.ZERO
## Radius of the search circle, metres.
var zone_radius: float = 0.0

var _seen_time: float = 0.0
var _outside: float = 0.0
var _dispatch: float = 0.0     # seconds the police still know where you are after a crime


## Adds a crime's heat at `where` (knockdown, hit_police, assault_officer).
func report_crime(crime: StringName, where: Vector3) -> void:
	var added: float = 0.0
	match crime:
		&"knockdown":
			added = tuning.knockdown_heat
		&"hit_police":
			added = tuning.hit_police_heat
		&"assault_officer":
			added = tuning.assault_officer_heat
		_:
			push_warning("WantedSystem: unknown crime '%s'" % crime)
			return
	if level == 0:
		last_known = where
	heat += added
	_dispatch = tuning.dispatch_seconds
	_update_level()


## Sets the level directly (missions, tests).
func set_level(new_level: int, where: Vector3) -> void:
	heat = tuning.level_heat[clampi(new_level, 0, 5)]
	last_known = where
	_dispatch = tuning.dispatch_seconds
	_update_level()
	if level > 0:
		_set_searching(false)


func clear() -> void:
	heat = 0.0
	_dispatch = 0.0
	_seen_time = 0.0
	_outside = 0.0
	_set_searching(false)
	_update_level()


## Arrested: the game scene takes it from here (screen, fine, police station); the record is clean.
func bust() -> void:
	if level == 0:
		return
	clear()
	busted.emit()


## A respray garage: clears a level up to tuning.respray_max_level. False if it can't.
func respray() -> bool:
	if level == 0 or level > tuning.respray_max_level:
		return false
	clear()
	return true


## Called every physics frame by the police while wanted: whether any unit sees the player now.
func tick(delta: float, player_position: Vector3, seen: bool) -> void:
	if level == 0:
		return
	_dispatch = maxf(0.0, _dispatch - delta)
	if seen or _dispatch > 0.0:
		last_known = player_position
		_outside = 0.0
		_set_searching(false)
		_seen_time += delta
		var rise: float = tuning.escalate_seconds[level]
		if rise > 0.0 and _seen_time >= rise and level < 5:
			heat = maxf(heat, tuning.level_heat[level + 1])
			_update_level()
		return
	if not searching:
		_set_searching(true)
		zone_radius = tuning.search_radius_base + tuning.search_radius_per_level * level
	zone_radius = maxf(tuning.search_radius_min, zone_radius - tuning.search_shrink * delta)
	var away: float = Vector2(player_position.x - last_known.x, player_position.z - last_known.z).length()
	_outside = _outside + delta if away > zone_radius else 0.0
	if _outside >= tuning.clear_seconds:
		_outside = 0.0
		heat = tuning.level_heat[level - 1]
		_update_level()
		if level > 0:
			zone_radius = tuning.search_radius_base + tuning.search_radius_per_level * level
			last_known = player_position     # they spread out from where they think you are
		else:
			clear()


func is_wanted() -> bool:
	return level > 0


func _update_level() -> void:
	var new_level: int = 0
	for i: int in range(5, -1, -1):
		if heat >= tuning.level_heat[i] - 0.001:
			new_level = i
			break
	if new_level != level:
		if new_level > level:
			_seen_time = 0.0
		level = new_level
		level_changed.emit(level)


func _set_searching(value: bool) -> void:
	if value != searching:
		searching = value
		searching_changed.emit(value)
