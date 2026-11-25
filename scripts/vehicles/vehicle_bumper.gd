class_name VehicleBumper
extends Area3D
## Sensor boxes just beyond a car's front and rear bumpers that notice pedestrians before the car
## touches them: above a walking pace the person is knocked down (and stops colliding, so the
## car doesn't stop dead against them); slower, they step out of the way.
## Child of a VehicleController; the person must have hit_by_vehicle(vehicle, speed).

const NPC_LAYER: int = 8

var _vehicle: VehicleController


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	collision_layer = 0
	collision_mask = NPC_LAYER
	monitorable = false
	for spec: Array in [[Vector3(0.0, -0.1, 2.75), Vector3(2.0, 1.4, 1.3)], [Vector3(0.0, -0.1, -2.7), Vector3(2.0, 1.4, 1.1)]]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		shape.position = spec[0]
		add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method(&"hit_by_vehicle"):
		body.call(&"hit_by_vehicle", _vehicle, _vehicle.linear_velocity.length())
