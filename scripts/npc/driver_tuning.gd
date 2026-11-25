class_name DriverTuning
extends Resource
## How AI traffic drives. Edit res://resources/vehicles/traffic_driver.tres.

@export_group("Speed")
## Share of each lane's speed limit the drivers aim for.
@export_range(0.3, 1.2) var cruise_factor: float = 0.85
## Comfortable braking for planned stops (red lights, slow corners), m/s².
@export var comfort_brake: float = 3.0
## Hardest braking used for sudden obstacles, m/s².
@export var hard_brake: float = 7.0
## How hard the throttle follows the speed error.
@export var speed_gain: float = 0.35

@export_group("Steering")
## Pure-pursuit look-ahead: this far ahead at a standstill, plus look_ahead_per_speed metres per m/s.
@export var look_ahead_min: float = 4.0
@export var look_ahead_per_speed: float = 0.55
@export var look_ahead_max: float = 12.0

@export_group("Keeping distance")
## Gap left to the car or obstacle in front when stopped, metres.
@export var stop_gap: float = 2.5
## Time gap kept to the car in front while moving, seconds.
@export var headway: float = 1.2
## Forward sensor length: this many metres plus sensor_per_speed metres per m/s.
@export var sensor_length: float = 9.0
@export var sensor_per_speed: float = 1.8

@export_group("Junctions")
## Stop this far (front bumper) before a stop line, metres.
@export var stop_line_margin: float = 1.0
## Time to wait at a give-way line before pulling out, seconds.
@export var give_way_wait: float = 1.0
## Cars are looked for this far around a junction's centre, metres...
@export var junction_clear_radius: float = 22.0
## ...the junction is busy while anyone is this close to its centre (inside the box)...
@export var junction_box_radius: float = 5.0
## ...or a moving car will reach it within this many seconds.
@export var junction_arrival_time: float = 3.0
## Relative chances of going straight, turning left, turning right at a junction.
@export var turn_weights: Vector3 = Vector3(0.55, 0.25, 0.2)

@export_group("Passing")
## On roads with two lanes each way, a parked or wrecked car closer than this (metres) is passed
## by moving into the other lane, if that lane is free...
@export var pass_distance: float = 25.0
## ...from this far behind the car to a little beyond the obstacle (metres).
@export var pass_clear_behind: float = 20.0

@export_group("Patience")
## Honk after being held up by an obstacle (not a red light) this long, seconds.
@export var honk_after: float = 5.0
## Pause after a crash, seconds.
@export var crash_pause: float = 3.0
## A car stuck this long, out of view, is removed by the traffic manager.
@export var give_up_after: float = 40.0
