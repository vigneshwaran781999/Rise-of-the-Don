class_name PedestrianManager
extends Node3D
## Keeps the sidewalks around the player busy (GDD §6): people appear on the pedestrian navmesh
## in a ring around the player, out of sight (some as two people chatting), and are removed once
## far behind; the number follows the pedestrian density setting. It also coordinates them:
## free bench seats, who chats with whom, and alarms that make people run (crashes, horns,
## someone knocked down).

## The player's vehicle knocked someone down (a crime the police hear about).
signal player_hit_pedestrian(position: Vector3)
## The player punched someone (an assault, M7).
signal player_punched_pedestrian(position: Vector3)

const MONITOR: StringName = &"npc/pedestrians"
const SIT_SPOTS: StringName = &"sit_spots"

@export var tuning: PopulationTuning
@export var pedestrian_scene: PackedScene
## Models to pick from: man, woman, elder (tools/blender/characters.py).
@export var looks: Array[PackedScene] = []
@export var update_interval: float = 0.25

## Spawning and removing on or off (tests switch it off to set up situations by hand).
var enabled: bool = true
## People react when the player walks into them.
var player: PlayerController

var _streamer: WorldStreamer
var _people: Array[Pedestrian] = []
var _seats: Dictionary = {}       # sit-spot node -> Pedestrian using it
var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _serial: int = 0


func _ready() -> void:
	_rng.seed = 4711
	if not Performance.has_custom_monitor(MONITOR):
		Performance.add_custom_monitor(MONITOR, get_count)
	# People react to every car's crashes and horn, including cars that appear later.
	get_tree().node_added.connect(_on_node_added)
	for node: Node in get_tree().get_nodes_in_group(VehicleController.GROUP):
		_watch_vehicle(node as VehicleController)


func _exit_tree() -> void:
	if Performance.has_custom_monitor(MONITOR):
		Performance.remove_custom_monitor(MONITOR)


func setup(the_player: PlayerController, streamer: WorldStreamer) -> void:
	player = the_player
	_streamer = streamer


func get_pedestrians() -> Array[Pedestrian]:
	_prune()
	return _people


func get_count() -> int:
	return get_pedestrians().size()


func target_count() -> int:
	return tuning.pedestrian_counts[clampi(Settings.pedestrian_density, 0, tuning.pedestrian_counts.size() - 1)]


## A new person standing at `pos` (a point on the navmesh), who starts wandering.
func spawn_at(pos: Vector3) -> Pedestrian:
	var person := pedestrian_scene.instantiate() as Pedestrian
	person.name = "Pedestrian%d" % _serial
	_serial += 1
	person.manager = self
	add_child(person)
	person.global_position = pos + Vector3.UP * 0.05
	person.rotation.y = _rng.randf() * TAU
	person.reset_physics_interpolation()
	var look: int = _rng.randi() % looks.size()
	person.setup(looks[look], _colours(look), _rng.randi())
	person.wander()
	_people.append(person)
	return person


## Two people chatting face to face around `pos` (a point on the navmesh). Both spots must be on
## the navmesh too (not in a wall or a bench); if no way round fits, just one person appears.
func spawn_pair(pos: Vector3) -> Array[Pedestrian]:
	var map: RID = get_world_3d().navigation_map
	for attempt: int in 6:
		var angle: float = _rng.randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.6
		if not _on_navmesh(map, pos + offset) or not _on_navmesh(map, pos - offset):
			continue
		var a: Pedestrian = spawn_at(pos + offset)
		var b: Pedestrian = spawn_at(pos - offset)
		a.rotation.y = atan2(-offset.x, -offset.z)
		b.rotation.y = atan2(offset.x, offset.z)
		a.start_talk(b)
		b.start_talk(a)
		return [a, b]
	return [spawn_at(pos)]


func clear() -> void:
	for person: Pedestrian in _people:
		if is_instance_valid(person):
			person.queue_free()
	_people.clear()
	_seats.clear()


## Makes everyone within `radius` of `point` run (or, if not `run`, step) away from it.
func alert(point: Vector3, radius: float, run: bool, except: Pedestrian = null) -> void:
	for person: Pedestrian in get_pedestrians():
		if person == except or person.state == Pedestrian.State.KNOCKED:
			continue
		var d: Vector3 = person.global_position - point
		if Vector2(d.x, d.z).length() <= radius:
			person.flee_from(point, run)


## The nearest free bench seat within reach of `person`, now reserved for them, or null.
func claim_seat(person: Pedestrian) -> Node3D:
	var best: Node3D = null
	var best_d: float = person.tuning.sit_search_radius
	for node: Node in get_tree().get_nodes_in_group(SIT_SPOTS):
		var seat := node as Node3D
		if is_seat_taken(seat):
			continue
		var d: float = seat.global_position.distance_to(person.global_position)
		if d < best_d:
			best_d = d
			best = seat
	if best != null:
		_seats[best] = person
	return best


func release_seat(seat: Node3D) -> void:
	_seats.erase(seat)


func is_seat_taken(seat: Node3D) -> bool:
	return _seats.has(seat) and is_instance_valid(_seats[seat])


## Pairs `person` up with someone standing about nearby, if anyone is free to chat.
func try_start_talk(person: Pedestrian) -> void:
	for other: Pedestrian in get_pedestrians():
		if other == person or other.is_busy() or other.state != Pedestrian.State.IDLE:
			continue
		if other.global_position.distance_to(person.global_position) <= person.tuning.talk_radius:
			person.start_talk(other)
			other.start_talk(person)
			return


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not enabled or player == null or _streamer == null:
		return
	_timer = update_interval
	_prune()
	_remove_far()
	var count: int = _people.size()
	var target: int = target_count()
	if count < target:
		_try_spawn(target - count)
	elif count > target:
		_remove_one_extra()


func _try_spawn(missing: int) -> void:
	var here: Vector3 = player.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return   # the navigation map has not synced yet (first frames after loading)
	for attempt: int in 8:
		var angle: float = _rng.randf() * TAU
		var distance: float = _rng.randf_range(tuning.pedestrian_spawn_min, tuning.pedestrian_spawn_max)
		var wanted: Vector3 = here + Vector3(cos(angle), 0.0, sin(angle)) * distance
		var point: Vector3 = NavigationServer3D.map_get_closest_point(map, wanted)
		if point == Vector3.ZERO or Vector2(point.x - wanted.x, point.z - wanted.z).length() > 6.0:
			continue
		var from_player: float = Vector2(point.x - here.x, point.z - here.z).length()
		if from_player < tuning.pedestrian_spawn_min or not _streamer.is_position_loaded(point):
			continue
		if camera != null and from_player < tuning.pedestrian_visible_spawn_min and camera.is_position_in_frustum(point + Vector3.UP):
			continue
		if missing >= 2 and _rng.randf() < tuning.pair_chance:
			spawn_pair(point)
		else:
			spawn_at(point)
		return


func _remove_far() -> void:
	var here: Vector3 = player.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	for person: Pedestrian in _people.duplicate():
		var d: Vector3 = person.global_position - here
		var distance: float = Vector2(d.x, d.z).length()
		var seen: bool = camera != null and camera.is_position_in_frustum(person.global_position + Vector3.UP)
		if person.global_position.y < -3.0 or distance > tuning.pedestrian_despawn + 30.0 or (distance > tuning.pedestrian_despawn and not seen):
			_remove(person)


func _remove_one_extra() -> void:
	var here: Vector3 = player.global_position
	var camera: Camera3D = get_viewport().get_camera_3d()
	var farthest: Pedestrian = null
	var best: float = 0.0
	for person: Pedestrian in _people:
		if camera != null and camera.is_position_in_frustum(person.global_position + Vector3.UP):
			continue
		var d: float = person.global_position.distance_to(here)
		if d > best:
			best = d
			farthest = person
	if farthest != null:
		_remove(farthest)


func _remove(person: Pedestrian) -> void:
	if person.get_seat() != null:
		release_seat(person.get_seat())
	_people.erase(person)
	person.queue_free()


static func _on_navmesh(map: RID, point: Vector3) -> bool:
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length() < 0.1


func _colours(look: int) -> Dictionary:
	var t: PopulationTuning = tuning
	var bottom: PackedColorArray = [t.bottom_colours, t.skirt_colours, t.veshti_colours][mini(look, 2)]
	var hair: PackedColorArray = t.grey_hair_colours if look == 2 else t.hair_colours
	return {
		&"top_color": t.top_colours[_rng.randi() % t.top_colours.size()],
		&"bottom_color": bottom[_rng.randi() % bottom.size()],
		&"skin_color": t.skin_tones[_rng.randi() % t.skin_tones.size()],
		&"hair_color": hair[_rng.randi() % hair.size()],
	}


func _on_node_added(node: Node) -> void:
	if node is VehicleController:
		_watch_vehicle.call_deferred(node as VehicleController)


func _watch_vehicle(vehicle: VehicleController) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.has_meta(&"watched_by_pedestrians"):
		return
	vehicle.set_meta(&"watched_by_pedestrians", true)
	var damage := vehicle.get_node_or_null("Damage") as VehicleDamage
	if damage != null:
		damage.impacted.connect(func(impact_kmh: float, _damage: float) -> void:
			if impact_kmh > 10.0:
				alert(vehicle.global_position, 18.0, true))
	vehicle.horn_changed.connect(func(on: bool) -> void:
		if on:
			alert(vehicle.global_position + vehicle.global_basis.z * 5.0, 8.0, false))


func _prune() -> void:
	for i: int in range(_people.size() - 1, -1, -1):
		if not is_instance_valid(_people[i]) or _people[i].is_queued_for_deletion():
			_people.remove_at(i)


## A person was knocked down by `vehicle` (Pedestrian calls this); if the player was driving it,
## the police are told.
func report_knockdown(person: Pedestrian, vehicle: VehicleController) -> void:
	if player != null and player.vehicle == vehicle:
		player_hit_pedestrian.emit(person.global_position)


## Someone was punched by `attacker` (Pedestrian calls this); if it was the player, the police
## are told.
func report_assault(person: Pedestrian, attacker: Node3D) -> void:
	if player != null and attacker == player:
		player_punched_pedestrian.emit(person.global_position)
