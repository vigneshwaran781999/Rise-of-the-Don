class_name VehicleCameraTuning
extends Resource
## Vehicle camera tunables (chase and hood views). Edit res://resources/vehicles/vehicle_camera.tres.

@export_group("Chase framing")
## Height above the car's centre that the chase camera orbits around.
@export var pivot_height: float = 1.3
## Spring-arm length when parked.
@export var distance: float = 5.6
## Extra distance at the car's top speed (the camera drops back as you speed up).
@export var distance_speed_bonus: float = 1.4
@export var default_pitch_degrees: float = -10.0
@export var min_pitch_degrees: float = -55.0
@export var max_pitch_degrees: float = 25.0
@export var collision_radius: float = 0.25

@export_group("Look")
## Radians per mouse pixel at a Settings sensitivity of 1.0.
@export var mouse_radians_per_pixel: float = 0.0025
## Degrees per second at full right-stick tilt and sensitivity 1.0.
@export var stick_degrees_per_second: float = 150.0
## After looking around, the chase camera swings back behind the car after this long.
@export var recenter_delay: float = 1.2
## How quickly it swings back behind the car (higher = faster).
@export var recenter_sharpness: float = 3.0
## Below this speed (km/h) it doesn't swing back on its own, so you can look at a parked car.
@export var recenter_min_speed_kmh: float = 8.0

@export_group("Smoothing")
@export var follow_sharpness: float = 14.0
## Lower values soak up suspension bounce.
@export var vertical_follow_sharpness: float = 7.0

@export_group("Field of view")
@export var base_fov: float = 72.0
## Extra field of view at the car's top speed.
@export var speed_fov_bonus: float = 10.0
@export var fov_sharpness: float = 4.0

@export_group("Hood view")
@export var hood_fov: float = 80.0
## How far the hood camera can be turned to either side, degrees.
@export var hood_look_limit_degrees: float = 100.0
