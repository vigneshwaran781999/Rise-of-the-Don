class_name BikeLean
extends Node
## Leans a two-wheeler into its turns (M7): the motorcycle rides on two hidden stabiliser wheels
## besides its two real ones (GDD §5: "simplified physics"), so the physics body stays upright and
## this tilts its looks (the Model node, with the rider on it) instead: by the steering, more with
## speed, up to the vehicle's lean_degrees. A child of the vehicle.

## Speed (km/h) at which the full lean is reached.
const FULL_LEAN_KMH: float = 35.0
## How quickly the lean follows the steering (per second).
const SHARPNESS: float = 6.0

var _vehicle: VehicleController
var _model: Node3D


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	_model = _vehicle.get_node("Model") as Node3D


func _process(delta: float) -> void:
	var max_steer: float = deg_to_rad(maxf(_vehicle.stats.max_steer_degrees, 1.0))
	var steer: float = clampf(_vehicle.get_steer_angle() / max_steer, -1.0, 1.0)
	var speed: float = clampf(absf(_vehicle.get_speed_kmh()) / FULL_LEAN_KMH, 0.0, 1.0)
	# Steering left (positive) turns towards +X; leaning into it tips the top that way, which is a
	# negative roll about the forward (+Z) axis.
	var target: float = -steer * speed * deg_to_rad(_vehicle.stats.lean_degrees)
	_model.rotation.z = lerpf(_model.rotation.z, target, 1.0 - exp(-SHARPNESS * delta))


## The current lean (radians, positive = leaning right).
func get_lean() -> float:
	return _model.rotation.z
