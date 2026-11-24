class_name CameraTuning
extends Resource
## Third-person camera tunables. Edit res://resources/characters/player_camera.tres.

@export_group("Framing")
## Height above the player's feet that the camera orbits around.
@export var pivot_height: float = 1.55
## Spring-arm length when nothing is in the way.
@export var distance: float = 4.2
@export var default_pitch_degrees: float = -12.0
@export var min_pitch_degrees: float = -65.0
@export var max_pitch_degrees: float = 35.0
## Radius of the sphere the spring arm sweeps (keeps the lens off walls).
@export var collision_radius: float = 0.2

@export_group("Look")
## Radians per mouse pixel at a Settings sensitivity of 1.0.
@export var mouse_radians_per_pixel: float = 0.0025
## Degrees per second at full right-stick tilt and sensitivity 1.0.
@export var stick_degrees_per_second: float = 150.0

@export_group("Smoothing")
## Higher = tighter horizontal follow.
@export var follow_sharpness: float = 16.0
## Higher = tighter vertical follow (lower softens jumps and kerbs).
@export var vertical_follow_sharpness: float = 9.0

@export_group("Field of view")
@export var base_fov: float = 70.0
@export var sprint_fov_bonus: float = 6.0
@export var fov_sharpness: float = 6.0
