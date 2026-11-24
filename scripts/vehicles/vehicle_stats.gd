class_name VehicleStats
extends Resource
## Handling, durability and sound tunables for one vehicle model (GDD §5).
## Edit the .tres files in res://resources/vehicles/ (e.g. sedan_stats.tres) in the inspector.
## Forces are in newtons, speeds in km/h unless the name says otherwise.

enum Drive { FRONT, REAR, ALL }

@export_group("Body")
@export var mass: float = 1250.0
## Height of the centre of mass in the vehicle's local space (the origin is the chassis
## centre). Lower is more stable.
@export var center_of_mass_height: float = -0.3
@export var max_health: float = 1000.0

@export_group("Engine")
@export var drive: Drive = Drive.FRONT
## Total push at the driven wheels from a standstill.
@export var engine_force: float = 5200.0
## Above roughly engine_power / engine_force m/s the push falls off as power / speed.
@export var engine_power: float = 95000.0
@export var top_speed_kmh: float = 175.0
@export var reverse_force: float = 3400.0
@export var reverse_top_speed_kmh: float = 28.0
## Air resistance, newtons per (m/s)^2.
@export var drag_coefficient: float = 0.42
@export var rolling_resistance: float = 200.0
## Slowing force when coasting with no throttle or brake.
@export var engine_braking: float = 900.0
## Extra grip at speed, newtons per (m/s)^2 pushing the car down.
@export var downforce: float = 1.2

@export_group("Brakes")
@export var brake_force: float = 11000.0
## Share of the brake force on the front wheels.
@export_range(0.0, 1.0) var brake_bias_front: float = 0.62
@export var handbrake_force: float = 7000.0
## Holds the car still when nobody is driving it.
@export var parking_brake_force: float = 6000.0
## Rear tyre grip is multiplied by this while the handbrake is held (lower = easier slides).
@export_range(0.05, 1.0) var handbrake_rear_grip: float = 0.45

@export_group("Steering")
@export var max_steer_degrees: float = 32.0
## Steering lock left at and above steer_falloff_speed_kmh.
@export var high_speed_steer_degrees: float = 9.0
@export var steer_falloff_speed_kmh: float = 110.0
## How fast the wheels turn towards the steering input, radians per second.
@export var steer_speed: float = 2.6
## How fast they return to centre when the input is released, radians per second.
@export var steer_return_speed: float = 4.0

@export_group("Suspension")
## Spring strength (Godot's VehicleWheel3D units: scaled by the vehicle's mass).
@export var suspension_stiffness: float = 42.0
## Spring length at rest, metres.
@export var suspension_rest_length: float = 0.2
## How far the spring can compress, metres.
@export var suspension_travel: float = 0.2
@export var damping_compression: float = 2.4
@export var damping_relaxation: float = 3.2
@export var suspension_max_force: float = 15000.0
## How much cornering forces roll the body (0 = none, 1 = fully physical; low keeps it upright).
@export_range(0.0, 1.0) var roll_influence: float = 0.12

@export_group("Tyres")
## Tyre grip (VehicleWheel3D friction_slip). Roughly the cornering grip in g.
@export var front_grip: float = 1.4
@export var rear_grip: float = 1.55

@export_group("Gearbox (sound and speedometer only)")
## Speed at the redline in each forward gear.
@export var gear_top_speeds_kmh: PackedFloat32Array = PackedFloat32Array([38.0, 66.0, 98.0, 135.0, 180.0])
@export var idle_rpm: float = 850.0
@export var redline_rpm: float = 6400.0
@export var shift_up_rpm: float = 5800.0
@export var shift_down_rpm: float = 2500.0

@export_group("Damage")
## A sudden change of speed (a crash) smaller than this does no damage.
@export var impact_threshold_kmh: float = 12.0
## Health lost per km/h of impact above the threshold.
@export var damage_per_kmh: float = 9.0
## Light smoke from the engine below this share of health, heavy smoke below the next one.
@export_range(0.0, 1.0) var smoke_below: float = 0.35
@export_range(0.0, 1.0) var heavy_smoke_below: float = 0.15
## An occupied car stuck on its side or roof is put back on its wheels after this long.
@export var flip_recovery_seconds: float = 2.5
