class_name VehicleInteractor
extends Node
## Getting in and out of vehicles with the vehicle_enter_exit action (GDD §5).
## On foot it tracks the nearest free vehicle within reach (announced through target_changed,
## which the HUD turns into a prompt) and gets in through the nearer front door. In a vehicle
## it asks to get out; once the car is slow enough it finds a clear spot to stand: the
## driver's door first, then the passenger door, behind, in front, and finally the roof.
## Must be a direct child of the PlayerController.

## The vehicle the player could get into right now, or null.
signal target_changed(vehicle: VehicleController)

## Collision layer 1: the static world (ground, kerbs, buildings).
const WORLD_MASK: int = 1
const CAPSULE_LIFT: float = 0.05

var _player: PlayerController
var _target: VehicleController
var _pressed: bool = false
var _query := PhysicsShapeQueryParameters3D.new()
var _capsule_half_height: float = 0.9


func _ready() -> void:
	_player = get_parent() as PlayerController
	var body_shape := _player.get_node("CollisionShape3D") as CollisionShape3D
	_query.shape = body_shape.shape
	_capsule_half_height = (body_shape.shape as CapsuleShape3D).height * 0.5
	_query.collision_mask = _player.collision_mask


func get_target() -> VehicleController:
	return _target


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("vehicle_enter_exit") and not _player.input_locked:
		_pressed = true


func _physics_process(_delta: float) -> void:
	var pressed: bool = _pressed
	_pressed = false
	if _player.is_in_vehicle():
		_set_target(null)
		if pressed:
			_player.request_vehicle_exit()
		if _player.is_exit_requested():
			var car: VehicleController = _player.vehicle
			if car.linear_velocity.length() <= _player.tuning.vehicle_exit_max_speed \
					or _player.get_exit_wait() >= _player.tuning.vehicle_exit_timeout:
				_player.exit_vehicle(find_exit_position(car))
		return
	if not _player.can_enter_vehicle():
		_set_target(null)
		return
	_set_target(_nearest_vehicle())
	if pressed and _target != null:
		var car: VehicleController = _target
		_set_target(null)
		_player.enter_vehicle(car, _nearest_door(car))


## Where the player can stand after getting out of `car` (world position of the feet).
func find_exit_position(car: VehicleController) -> Vector3:
	for point: Vector3 in car.get_exit_points():
		var feet: Variant = _clear_spot(point, car)
		if feet != null:
			return feet
	return car.global_position + car.global_basis.y * 1.2   # boxed in: climb out onto the roof


## The feet position at `point` if the ground is there and a capsule fits, otherwise null.
func _clear_spot(point: Vector3, car: VehicleController) -> Variant:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.2, point + Vector3.DOWN * 1.5, WORLD_MASK)
	var hit: Dictionary = space.intersect_ray(ray)
	if hit.is_empty():
		return null
	var feet: Vector3 = (hit["position"] as Vector3) + Vector3.UP * CAPSULE_LIFT
	_query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * _capsule_half_height)
	_query.exclude = [_player.get_rid(), car.get_rid()]
	return feet if space.intersect_shape(_query, 1).is_empty() else null


func _nearest_vehicle() -> VehicleController:
	var best: VehicleController = null
	var best_distance: float = _player.tuning.vehicle_enter_radius
	var here := Vector2(_player.global_position.x, _player.global_position.z)
	for node: Node in get_tree().get_nodes_in_group(VehicleController.GROUP):
		var car := node as VehicleController
		if car == null or car.is_occupied():
			continue
		var distance: float = here.distance_to(Vector2(car.global_position.x, car.global_position.z))
		if distance <= best_distance:
			best = car
			best_distance = distance
	return best


## The nearer of the two front doors (the first two exit points).
func _nearest_door(car: VehicleController) -> Vector3:
	var doors: Array[Vector3] = car.get_exit_points()
	if doors.size() < 2:
		return doors[0] if not doors.is_empty() else car.global_position
	var here: Vector3 = _player.global_position
	return doors[0] if here.distance_to(doors[0]) <= here.distance_to(doors[1]) else doors[1]


func _set_target(car: VehicleController) -> void:
	if car != _target:
		_target = car
		target_changed.emit(car)
