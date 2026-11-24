class_name PlayerDrivingInput
extends Node
## Drives the vehicle the player sits in, from the input map: throttle, brake (reverses when
## stopped), steering, handbrake, horn and headlights. While the player waits to get out it
## holds the brakes. Must be a direct child of the PlayerController.

var _player: PlayerController


func _ready() -> void:
	_player = get_parent() as PlayerController


func _physics_process(_delta: float) -> void:
	var car: VehicleController = _player.vehicle
	if car == null or not _player.is_in_vehicle():
		return
	if _player.is_exit_requested():
		# Both pedals together always mean "brake", whichever way the car is rolling.
		car.set_controls(1.0, 1.0, 0.0, false)
		car.set_horn(false)
		return
	car.set_controls(
		Input.get_action_strength("vehicle_accelerate"),
		Input.get_action_strength("vehicle_brake"),
		Input.get_axis("vehicle_steer_right", "vehicle_steer_left"),
		Input.is_action_pressed("vehicle_handbrake"))
	car.set_horn(Input.is_action_pressed("vehicle_horn"))


func _unhandled_input(event: InputEvent) -> void:
	if _player.is_in_vehicle() and event.is_action_pressed("vehicle_headlights"):
		_player.vehicle.toggle_headlights()
		get_viewport().set_input_as_handled()
