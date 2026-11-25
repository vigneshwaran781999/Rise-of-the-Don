class_name TrafficManager
extends Node3D
## Keeps the streets around the player busy with AI cars (GDD §6). Cars appear on lanes in a
## ring around the player, out of sight, and are removed once far behind (or hopelessly stuck,
## out of view); the number follows the traffic density setting. Every car is a full physics
## sedan driven by a TrafficDriver, so it can be bumped, rammed and crashed like the player's.
## The streets only exist near the player (chunk streaming), so all traffic is near the player;
## GDD §16's "kinematic distant traffic" isn't needed while the ring is this small.

const MONITOR: StringName = &"npc/traffic"

@export var tuning: PopulationTuning
@export var driver_tuning: DriverTuning
@export var car_scene: PackedScene
## Seconds between ring updates (each may add or remove one car).
@export var update_interval: float = 0.35

## Spawning and removing on or off (tests switch it off to set up situations by hand).
var enabled: bool = true
## Traffic drives with its headlights on (at night).
var headlights_on: bool = false

var _graph: LaneGraph
var _router: RoadRouter
var _focus: Node3D
var _streamer: WorldStreamer
var _cars: Array[VehicleController] = []
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _serial: int = 0
var _clear_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	_rng.seed = 90210
	var sphere := SphereShape3D.new()
	sphere.radius = 6.0
	_clear_query.shape = sphere
	_clear_query.collision_mask = 2 | 4 | 8
	if not Performance.has_custom_monitor(MONITOR):
		Performance.add_custom_monitor(MONITOR, get_count)


func _exit_tree() -> void:
	if Performance.has_custom_monitor(MONITOR):
		Performance.remove_custom_monitor(MONITOR)


func setup(graph: LaneGraph, focus: Node3D, streamer: WorldStreamer) -> void:
	_graph = graph
	_router = RoadRouter.for_graph(graph)
	_focus = focus
	_streamer = streamer


func get_cars() -> Array[VehicleController]:
	_prune()
	return _cars


func get_count() -> int:
	return get_cars().size()


func target_count() -> int:
	return tuning.traffic_counts[clampi(Settings.traffic_density, 0, tuning.traffic_counts.size() - 1)]


## Puts a traffic car on lane node `node`, already moving at `speed` m/s along the lane.
func spawn_at(node: int, speed: float = 0.0, paint: Color = Color(0, 0, 0, 0)) -> VehicleController:
	var start: Vector3 = _graph.get_position(node)
	var direction: Vector3 = _graph.get_position(_graph.get_next(node)[0]) - start
	direction.y = 0.0
	direction = direction.normalized()
	var car := _pick_model().instantiate() as VehicleController
	car.name = "Traffic%d" % _serial
	_serial += 1
	add_child(car)
	car.teleport(Transform3D(Basis.looking_at(-direction, Vector3.UP), start + Vector3.UP * 0.6))
	car.linear_velocity = direction * speed
	var colour: Color = paint if paint.a > 0.0 else tuning.paint_colours[_rng.randi() % tuning.paint_colours.size()]
	(car.get_node("Model") as VehicleModel).set_paint(colour)
	(car.get_node("Lights") as VehicleLights).beams_allowed = false
	car.set_headlights(headlights_on)
	var driver := TrafficDriver.new()
	driver.name = "Driver"
	driver.tuning = driver_tuning
	car.add_child(driver)
	driver.start(car, _graph, node, _rng.randi())
	_cars.append(car)
	return car


## Headlights on or off for every traffic car, now and for cars that appear later.
func set_headlights(on: bool) -> void:
	headlights_on = on
	for car: VehicleController in get_cars():
		car.set_headlights(on)


func clear() -> void:
	for car: VehicleController in _cars:
		if is_instance_valid(car):
			car.queue_free()
	_cars.clear()


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not enabled or _graph == null or _focus == null:
		return
	_timer = update_interval
	_prune()
	_remove_far()
	var count: int = _cars.size()
	var target: int = target_count()
	if count < target:
		_try_spawn()
	elif count > target:
		_remove_one_extra()


func _try_spawn() -> void:
	var here: Vector3 = _focus.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for attempt: int in 16:
		# A node near the player (sampling the whole city's graph would mostly miss the ring).
		var node: int = _router.random_node_near(here, tuning.traffic_spawn_min, tuning.traffic_spawn_max, _rng)
		if node < 0 or _graph.flags[node] != 0 or _graph.get_next(node).is_empty():
			continue    # only plain lane nodes, not stop lines, junctions or U-turns
		var pos: Vector3 = _graph.get_position(node)
		var distance: float = Vector2(pos.x - here.x, pos.z - here.z).length()
		if distance < tuning.traffic_spawn_min or distance > tuning.traffic_spawn_max:
			continue
		if not _streamer.is_position_loaded(pos):
			continue
		if camera != null and distance < tuning.traffic_visible_spawn_min and camera.is_position_in_frustum(pos + Vector3.UP):
			continue
		_clear_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP)
		if not space.intersect_shape(_clear_query, 1).is_empty():
			continue
		spawn_at(node, _graph.speed_kmh[node] / 3.6 * driver_tuning.cruise_factor * 0.8)
		return


func _remove_far() -> void:
	var here: Vector3 = _focus.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	for car: VehicleController in _cars.duplicate():
		var distance: float = Vector2(car.global_position.x - here.x, car.global_position.z - here.z).length()
		var seen: bool = camera != null and camera.is_position_in_frustum(car.global_position)
		var driver := car.get_node_or_null("Driver") as TrafficDriver
		var given_up: bool = driver != null and driver.held_for > driver_tuning.give_up_after
		var fell: bool = car.global_position.y < -2.0
		if fell or distance > tuning.traffic_despawn + 40.0 or (not seen and (distance > tuning.traffic_despawn or given_up)):
			_cars.erase(car)
			car.queue_free()


func _remove_one_extra() -> void:
	var here: Vector3 = _focus.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	var farthest: VehicleController = null
	var best: float = 0.0
	for car: VehicleController in _cars:
		if camera != null and camera.is_position_in_frustum(car.global_position):
			continue
		var d: float = car.global_position.distance_to(here)
		if d > best:
			best = d
			farthest = car
	if farthest != null:
		_cars.erase(farthest)
		farthest.queue_free()


func _prune() -> void:
	for i: int in range(_cars.size() - 1, -1, -1):
		if not is_instance_valid(_cars[i]) or _cars[i].is_queued_for_deletion():
			_cars.remove_at(i)


## The car for a new spawn: one of the tuning's traffic models by its share, otherwise car_scene.
func _pick_model() -> PackedScene:
	var roll: float = _rng.randf()
	for i: int in mini(tuning.traffic_models.size(), tuning.traffic_model_shares.size()):
		roll -= tuning.traffic_model_shares[i]
		if roll < 0.0 and tuning.traffic_models[i] != null:
			return tuning.traffic_models[i]
	return car_scene
