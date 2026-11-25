class_name PlayerStats
extends Node
## Health and stamina (GDD §4). Stamina drains while sprinting and refills after a short
## delay; running dry locks sprinting until it recovers. Health regenerates slowly, but only
## up to a cap (50 % by default).

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)

@export var tuning: PlayerTuning

var health: float = 0.0
var stamina: float = 0.0
var _exhausted: bool = false
var _stamina_delay_left: float = 0.0
var _health_delay_left: float = 0.0


func _ready() -> void:
	health = tuning.max_health
	stamina = tuning.max_stamina


func can_sprint() -> bool:
	return not _exhausted and stamina > 0.0


func is_exhausted() -> bool:
	return _exhausted


func tick(delta: float, sprinting: bool) -> void:
	_tick_stamina(delta, sprinting)
	_tick_health(delta)


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_health_delay_left = tuning.health_regen_delay
	health_changed.emit(health, tuning.max_health)


## Restores up to `amount` health (food); returns how much was actually restored.
func heal(amount: float) -> float:
	var before: float = health
	health = clampf(health + maxf(amount, 0.0), 0.0, tuning.max_health)
	health_changed.emit(health, tuning.max_health)
	return health - before


func get_max_health() -> float:
	return tuning.max_health


## Sets health directly (loading a save).
func set_health(value: float) -> void:
	health = clampf(value, 0.0, tuning.max_health)
	health_changed.emit(health, tuning.max_health)


func _tick_stamina(delta: float, sprinting: bool) -> void:
	var before: float = stamina
	if sprinting:
		stamina = maxf(0.0, stamina - tuning.sprint_drain_per_second * delta)
		_stamina_delay_left = tuning.stamina_regen_delay
		if stamina <= 0.0:
			_exhausted = true
	elif _stamina_delay_left > 0.0:
		_stamina_delay_left -= delta
	else:
		stamina = minf(tuning.max_stamina, stamina + tuning.stamina_regen_per_second * delta)
	if _exhausted and stamina >= tuning.min_stamina_to_sprint:
		_exhausted = false
	if stamina != before:
		stamina_changed.emit(stamina, tuning.max_stamina)


func _tick_health(delta: float) -> void:
	if _health_delay_left > 0.0:
		_health_delay_left -= delta
		return
	var cap: float = tuning.max_health * tuning.health_regen_cap
	if health > 0.0 and health < cap:
		health = minf(cap, health + tuning.health_regen_per_second * delta)
		health_changed.emit(health, tuning.max_health)
