class_name VehicleEngine
extends Node
## Simulated engine speed and automatic gearbox for the engine sound and the speedometer.
## It does not change how the car drives (VehicleController's power curve does that); it only
## turns speed and throttle into believable rpm, gear changes and a gear letter.
## Must be a direct child of a VehicleController.

signal gear_changed(gear: int)

const NEUTRAL: int = 0
const REVERSE: int = -1
## Time the revs dip for during an up-shift, seconds.
const SHIFT_TIME: float = 0.28

## Engine speed in revolutions per minute (0 while the engine is off).
var rpm: float = 0.0
## REVERSE, NEUTRAL or the forward gear, 1..n.
var gear: int = NEUTRAL

var _vehicle: VehicleController
var _shift_left: float = 0.0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController


func get_gear_text() -> String:
	if gear == REVERSE:
		return "R"
	if gear == NEUTRAL:
		return "N"
	return str(gear)


## rpm as a share of the redline, 0..1.
func get_rpm_fraction() -> float:
	return clampf(rpm / _vehicle.stats.redline_rpm, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var stats: VehicleStats = _vehicle.stats
	_shift_left = maxf(0.0, _shift_left - delta)
	var target: float = 0.0
	if not _vehicle.is_engine_running():
		_set_gear(NEUTRAL)
	elif _vehicle.is_reversing():
		_set_gear(REVERSE)
		var reverse_share: float = _vehicle.get_speed_kmh() / stats.reverse_top_speed_kmh
		target = lerpf(stats.idle_rpm, stats.redline_rpm * 0.75, clampf(reverse_share, 0.0, 1.0))
	else:
		target = _forward_rpm(stats)
	# Revving against the clutch from a standstill.
	if _vehicle.is_engine_running() and gear <= 1:
		target = maxf(target, lerpf(stats.idle_rpm, 3400.0, _vehicle.get_engine_load()))
	if _shift_left > 0.0:
		target *= 0.82
	var sharpness: float = 9.0 if target > rpm else 6.0
	rpm = lerpf(rpm, target, 1.0 - exp(-sharpness * delta))


func _forward_rpm(stats: VehicleStats) -> float:
	var tops: PackedFloat32Array = stats.gear_top_speeds_kmh
	var speed_kmh: float = maxf(_vehicle.get_forward_speed() * 3.6, 0.0)
	if gear < 1:
		_set_gear(1)
	if gear < tops.size() and _rpm_in_gear(gear, speed_kmh) > stats.shift_up_rpm and _vehicle.get_engine_load() > 0.05:
		_set_gear(gear + 1)
		_shift_left = SHIFT_TIME
	elif gear > 1 and _rpm_in_gear(gear, speed_kmh) < stats.shift_down_rpm \
			and _rpm_in_gear(gear - 1, speed_kmh) < stats.shift_up_rpm - 500.0:
		_set_gear(gear - 1)
	return _rpm_in_gear(gear, speed_kmh)


func _rpm_in_gear(g: int, speed_kmh: float) -> float:
	var stats: VehicleStats = _vehicle.stats
	var top: float = stats.gear_top_speeds_kmh[clampi(g, 1, stats.gear_top_speeds_kmh.size()) - 1]
	return lerpf(stats.idle_rpm, stats.redline_rpm, clampf(speed_kmh / top, 0.0, 1.05))


func _set_gear(next: int) -> void:
	if next != gear:
		gear = next
		gear_changed.emit(gear)
