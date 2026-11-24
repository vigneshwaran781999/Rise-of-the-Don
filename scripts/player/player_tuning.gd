class_name PlayerTuning
extends Resource
## On-foot movement, jump, stamina and health tunables (GDD §4).
## Edit res://resources/characters/player_tuning.tres rather than the defaults here.

@export_group("Speeds (m/s)")
@export var walk_speed: float = 2.0
@export var run_speed: float = 5.0
@export var sprint_speed: float = 8.0
## Gamepad: left-stick tilt below this walks instead of running.
@export_range(0.0, 1.0) var stick_walk_threshold: float = 0.55

@export_group("Acceleration")
## m/s² while speeding up toward the target speed.
@export var ground_acceleration: float = 32.0
## m/s² while slowing down with no input.
@export var ground_deceleration: float = 40.0
## Fraction of ground acceleration available in the air.
@export_range(0.0, 1.0) var air_control: float = 0.3
## How quickly the body turns to face its movement (higher = snappier).
@export var turn_speed: float = 12.0

@export_group("Jump and gravity")
@export var jump_velocity: float = 5.2
@export var gravity_scale: float = 1.3
## Extra gravity while falling, for a less floaty arc.
@export var fall_gravity_multiplier: float = 1.6
@export var max_fall_speed: float = 40.0
## Seconds after walking off a ledge during which a jump still works.
@export var coyote_time: float = 0.12
## Seconds a jump press is remembered before landing.
@export var jump_buffer_time: float = 0.12
@export var land_recovery_time: float = 0.12

@export_group("Floor")
@export_range(0.0, 89.0) var max_slope_degrees: float = 46.0
@export var floor_snap_length: float = 0.35

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var sprint_drain_per_second: float = 20.0
@export var stamina_regen_per_second: float = 25.0
@export var stamina_regen_delay: float = 0.8
## After running dry, sprinting unlocks again at this much stamina.
@export var min_stamina_to_sprint: float = 20.0

@export_group("Health")
@export var max_health: float = 100.0
@export var health_regen_per_second: float = 2.0
## Health regenerates on its own only up to this fraction of max (GDD: 50 %).
@export_range(0.0, 1.0) var health_regen_cap: float = 0.5
@export var health_regen_delay: float = 5.0

@export_group("Vehicles")
## The nearest vehicle whose centre is within this distance can be entered (GDD: 3 m).
@export var vehicle_enter_radius: float = 3.0
## Time to step to the door and get in, seconds.
@export var enter_vehicle_time: float = 0.45
## Time after getting out before the player can move.
@export var exit_vehicle_time: float = 0.3
## Asking to get out above this speed (m/s) brakes the car first.
@export var vehicle_exit_max_speed: float = 2.5
## Give up waiting for the car to slow down and get out anyway after this long.
@export var vehicle_exit_timeout: float = 4.0
