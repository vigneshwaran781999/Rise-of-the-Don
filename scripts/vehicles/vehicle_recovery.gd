class_name VehicleRecovery
extends Node
## Puts an upturned car back on its wheels: if the car someone is driving lies on its side or
## roof, nearly still, for VehicleStats.flip_recovery_seconds, it is lifted and set upright
## facing the same way. Parked cars are left alone.
## Must be a direct child of a VehicleController.

signal recovered

## The car counts as upturned when its up axis points less than this far up (0.4 = about 66°).
const UPRIGHT_LIMIT: float = 0.4
const STILL_SPEED: float = 2.0
const LIFT: float = 1.0

var _vehicle: VehicleController
var _upturned_for: float = 0.0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController


func _physics_process(delta: float) -> void:
	var upturned: bool = _vehicle.global_basis.y.y < UPRIGHT_LIMIT
	if not _vehicle.is_occupied() or not upturned or _vehicle.linear_velocity.length() > STILL_SPEED:
		_upturned_for = 0.0
		return
	_upturned_for += delta
	if _upturned_for >= _vehicle.stats.flip_recovery_seconds:
		_upturned_for = 0.0
		_set_upright()


func _set_upright() -> void:
	var forward: Vector3 = _vehicle.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = _vehicle.global_basis.y   # nose straight down or up: use the roof direction
		forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var basis := Basis(Vector3.UP.cross(forward), Vector3.UP, forward)
	_vehicle.teleport(Transform3D(basis, _vehicle.global_position + Vector3.UP * LIFT))
	recovered.emit()
