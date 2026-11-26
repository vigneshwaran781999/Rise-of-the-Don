class_name PoliceManager
extends Node3D
## The police response to the wanted level (GDD §7).
## - Sight: every unit within range with a clear line to the player sees them; WantedSystem.tick()
##   gets the answer each frame (seen: pursuit; not seen: searching the shrinking circle).
## - Units per level (WantedTuning): officers on foot from level 1, police cars from level 2,
##   roadblocks across the road ahead from 3, spike strips in front of them from 4, the helicopter
##   at 5. New units appear out of sight; cars chase along the roads (PoliceDriver), officers run
##   after the player (PoliceOfficer) and police cars stopping near a player on foot let officers out.
## - Busted: an officer next to the player on foot, or police close around a stopped car, for a
##   moment -> WantedSystem.bust().
## - Crimes it sees: ramming a police car, knocking down an officer (and, via the pedestrian
##   manager, knocking down anyone).
## - When the level drops to 0 the units leave and are removed once out of sight.
## Offers map blips: police units, and the search circle while searching.

const CAR_GROUP: StringName = &"police_cars"
const SPAWN_CAR_MIN: float = 70.0
const SPAWN_CAR_MAX: float = 130.0
const SPAWN_OFFICER_MIN: float = 35.0
const SPAWN_OFFICER_MAX: float = 60.0
const REMOVE_DISTANCE: float = 230.0
const LEAVE_SECONDS: float = 25.0
## Roadblocks go this far ahead along the road; each car parked across it blocks about this much.
const ROADBLOCK_AHEAD: float = 90.0
const ROADBLOCK_CAR_SPAN: float = 4.2
const POLICE_PAINT := Color("eef0f3")

@export var car_scene: PackedScene
@export var officer_look: PackedScene
@export var skin_tones: PackedColorArray = PackedColorArray([Color("8d5a3b"), Color("6b4228"), Color("a3714d"), Color("5a3620")])

var tuning: WantedTuning = WantedSystem.tuning
## New units appear (tests switch it off to set situations up by hand).
var enabled: bool = true
## Whether any unit could see the player at the last check.
var seen: bool = false

var _player: PlayerController
var _streamer: WorldStreamer
var _router: RoadRouter
var _cars: Array[VehicleController] = []
var _officers: Array[PoliceOfficer] = []
var _roadblocks: Array[Node3D] = []
var _heli: PoliceHelicopter
var _deployed: Dictionary = {}       # car -> true once it has let officers out
var _rng := RandomNumberGenerator.new()
var _sight_timer: float = 0.0
var _spawn_timer: float = 0.0
var _roadblock_timer: float = 0.0
var _bust_timer: float = 0.0
var _leave_timer: float = 0.0
var _serial: int = 0
var _ray := PhysicsRayQueryParameters3D.new()
var _clear_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	add_to_group(GpsNavigator.BLIP_GROUP)
	_rng.seed = 5150
	_ray.collision_mask = 1
	var sphere := SphereShape3D.new()
	sphere.radius = 5.0
	_clear_query.shape = sphere
	_clear_query.collision_mask = 2 | 4 | 8


func setup(player: PlayerController, streamer: WorldStreamer, graph: LaneGraph, pedestrians: PedestrianManager) -> void:
	_player = player
	_streamer = streamer
	_router = RoadRouter.for_graph(graph)
	pedestrians.player_hit_pedestrian.connect(func(where: Vector3) -> void: WantedSystem.report_crime(&"knockdown", where))
	pedestrians.player_punched_pedestrian.connect(func(where: Vector3) -> void: WantedSystem.report_crime(&"assault", where))


func get_cars() -> Array[VehicleController]:
	_prune()
	return _cars


func get_officers() -> Array[PoliceOfficer]:
	_prune()
	return _officers


func get_roadblocks() -> Array[Node3D]:
	_prune()
	return _roadblocks


func get_helicopter() -> PoliceHelicopter:
	return _heli if _heli != null and is_instance_valid(_heli) else null


## Removes every police unit at once (after an arrest).
func clear_all() -> void:
	for node: Node in _units(true):
		if is_instance_valid(node):
			node.queue_free()
	if get_helicopter() != null:
		_heli.queue_free()
	_heli = null
	_cars.clear()
	_officers.clear()
	_roadblocks.clear()
	_deployed.clear()
	seen = false
	_bust_timer = 0.0


## An officer was knocked down (PoliceOfficer calls this): by the player's car, that's a crime.
func officer_hit(officer: PoliceOfficer, vehicle: VehicleController) -> void:
	if _player != null and _player.vehicle == vehicle:
		WantedSystem.report_crime(&"assault_officer", officer.global_position)


## An officer was punched (PoliceOfficer calls this): by the player, that's a crime: the first
## blow is assaulting an officer, more blows on them an assault each.
func officer_punched(officer: PoliceOfficer, attacker: Node3D, first: bool) -> void:
	if _player != null and attacker == _player:
		WantedSystem.report_crime(&"assault_officer" if first else &"assault", officer.global_position)


## Puts a police car on lane node `node` (tests and roadblocks use it too).
func spawn_car_at(node: int, speed: float = 0.0) -> VehicleController:
	var graph: LaneGraph = _router.graph
	var start: Vector3 = graph.get_position(node)
	var next: PackedInt32Array = graph.get_next(node)
	var direction: Vector3 = (graph.get_position(next[0]) - start) if not next.is_empty() else Vector3.FORWARD
	direction.y = 0.0
	var car: VehicleController = _make_car(Transform3D(Basis.looking_at(-direction.normalized(), Vector3.UP), start + Vector3.UP * 0.6))
	car.linear_velocity = direction.normalized() * speed
	var driver := PoliceDriver.new()
	driver.name = "Driver"
	car.add_child(driver)
	driver.start(car, _router, tuning, _rng.randi())
	_cars.append(car)
	return car


## Puts an officer on foot at `pos` (a navmesh point).
func spawn_officer_at(pos: Vector3) -> PoliceOfficer:
	var officer := PoliceOfficer.new()
	officer.setup(officer_look, skin_tones[_rng.randi() % skin_tones.size()])
	officer.name = "Officer%d" % _serial
	_serial += 1
	officer.manager = self
	officer.run_speed = tuning.officer_run_speed
	officer.max_health = tuning.officer_health
	add_child(officer)
	officer.global_position = pos + Vector3.UP * 0.05
	officer.reset_physics_interpolation()
	_officers.append(officer)
	return officer


func get_map_blips() -> Array[Dictionary]:
	var blips: Array[Dictionary] = []
	if WantedSystem.is_wanted() and WantedSystem.searching:
		blips.append({"position": WantedSystem.last_known, "kind": &"zone", "radius": WantedSystem.zone_radius})
	_prune()
	for node: Node3D in _units(false):
		blips.append({"position": node.global_position, "kind": &"police"})
	if get_helicopter() != null:
		blips.append({"position": _heli.global_position, "kind": &"police"})
	return blips


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_prune()
	var here: Vector3 = _focus_position()
	if not WantedSystem.is_wanted():
		_wind_down(delta, here)
		return
	_leave_timer = 0.0
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = 0.15
		seen = _anyone_sees(here)
	WantedSystem.tick(delta, here, seen)
	if not WantedSystem.is_wanted():
		return
	_direct_units(here)
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and enabled:
		_spawn_timer = 0.5
		_balance_units(here)
	_update_roadblocks(delta, here)
	_update_helicopter(here)
	_check_bust(delta)


# --------------------------------------------------------------------------- sight

func _anyone_sees(here: Vector3) -> bool:
	var eye: Vector3 = here + Vector3.UP * 1.0
	var exclude: Array[RID] = [_player.get_rid()]
	if _player.vehicle != null:
		exclude.append(_player.vehicle.get_rid())
	for car: VehicleController in _cars:
		if car.get_driver() != null and car.global_position.distance_to(here) < tuning.car_sight \
				and _clear_line(car.global_position + Vector3.UP * 1.0, eye, exclude, car.get_rid()):
			return true
	for officer: PoliceOfficer in _officers:
		if not officer.is_down() and officer.global_position.distance_to(here) < tuning.officer_sight \
				and _clear_line(officer.global_position + Vector3.UP * 1.6, eye, exclude):
			return true
	var heli: PoliceHelicopter = get_helicopter()
	if heli != null and heli.global_position.distance_to(here) < tuning.helicopter_sight \
			and _clear_line(heli.global_position - Vector3.UP * 1.0, eye, exclude):
		return true
	return false


func _clear_line(from: Vector3, to: Vector3, exclude: Array[RID], also: RID = RID()) -> bool:
	_ray.from = from
	_ray.to = to
	var skip: Array[RID] = exclude.duplicate()
	if also.is_valid():
		skip.append(also)
	_ray.exclude = skip
	return get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


# --------------------------------------------------------------------------- units

func _direct_units(here: Vector3) -> void:
	var target: Vector3 = here if seen else WantedSystem.last_known
	var velocity: Vector3 = Vector3.ZERO
	if seen:
		velocity = _player.vehicle.linear_velocity if _player.is_in_vehicle() and _player.vehicle != null else _player.velocity
	var on_foot: bool = not _player.is_in_vehicle()
	for car: VehicleController in _cars:
		var driver := car.get_node_or_null("Driver") as PoliceDriver
		(car.get_node("LightBar") as PoliceLightBar).active = true
		if driver == null:
			continue
		driver.target = target
		driver.target_velocity = velocity
		driver.target_on_foot = on_foot
		driver.set_mode(PoliceDriver.Mode.SEARCH if WantedSystem.searching else PoliceDriver.Mode.CHASE)
		# A car that has pulled up near a player on foot lets two officers out.
		if on_foot and not _deployed.has(car) and car.global_position.distance_to(here) < 16.0 and car.linear_velocity.length() < 2.0:
			_deployed[car] = true
			for door: Vector3 in car.get_exit_points().slice(0, 2):
				spawn_officer_at(door)
	for officer: PoliceOfficer in _officers:
		if officer.is_down():
			continue
		officer.state = PoliceOfficer.State.SEARCH if WantedSystem.searching else PoliceOfficer.State.CHASE
		officer.target = target


func _balance_units(here: Vector3) -> void:
	var level: int = WantedSystem.level
	var camera: Camera3D = get_viewport().get_camera_3d()
	if _cars.size() < tuning.cars[level]:
		_try_spawn_car(here, camera)
	var foot_officers: int = 0
	for officer: PoliceOfficer in _officers:
		foot_officers += 1
	if foot_officers < tuning.officers[level] and not _player.is_in_vehicle():
		_try_spawn_officer(here, camera)
	for node: Node3D in _units(false):
		var far: bool = _flat(node.global_position).distance_to(_flat(here)) > REMOVE_DISTANCE
		var fell: bool = node.global_position.y < -3.0
		if fell or (far and not _in_view(camera, node.global_position)):
			_remove(node)


func _try_spawn_car(here: Vector3, camera: Camera3D) -> void:
	var graph: LaneGraph = _router.graph
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for attempt: int in 16:
		var angle: float = _rng.randf() * TAU
		var wanted: Vector3 = here + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(SPAWN_CAR_MIN, SPAWN_CAR_MAX)
		var node: int = _router.nearest_node(wanted)
		if node < 0 or graph.flags[node] != 0 or graph.get_next(node).is_empty():
			continue
		var pos: Vector3 = graph.get_position(node)
		var distance: float = _flat(pos).distance_to(_flat(here))
		if distance < SPAWN_CAR_MIN * 0.8 or not _streamer.is_position_loaded(pos):
			continue
		if distance < 110.0 and _in_view(camera, pos + Vector3.UP):
			continue
		_clear_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP)
		if not space.intersect_shape(_clear_query, 1).is_empty():
			continue
		spawn_car_at(node, 8.0)
		return


func _try_spawn_officer(here: Vector3, camera: Camera3D) -> void:
	var map: RID = get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	for attempt: int in 8:
		var angle: float = _rng.randf() * TAU
		var wanted: Vector3 = here + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(SPAWN_OFFICER_MIN, SPAWN_OFFICER_MAX)
		var point: Vector3 = NavigationServer3D.map_get_closest_point(map, wanted)
		if point == Vector3.ZERO or _flat(point).distance_to(_flat(wanted)) > 6.0 or not _streamer.is_position_loaded(point):
			continue
		if _in_view(camera, point + Vector3.UP) and _flat(point).distance_to(_flat(here)) < 50.0:
			continue
		spawn_officer_at(point)
		return


func _make_car(xform: Transform3D) -> VehicleController:
	var car := car_scene.instantiate() as VehicleController
	car.name = "Police%d" % _serial
	_serial += 1
	add_child(car)
	car.teleport(xform)
	car.add_to_group(CAR_GROUP)
	(car.get_node("Model") as VehicleModel).set_paint(POLICE_PAINT)
	var bar := PoliceLightBar.new()
	car.add_child(bar)
	(car.get_node("Damage") as VehicleDamage).impacted.connect(_on_police_car_impacted.bind(car))
	return car


func _on_police_car_impacted(impact_kmh: float, _damage: float, car: VehicleController) -> void:
	if impact_kmh < 10.0 or _player == null or not _player.is_in_vehicle() or _player.vehicle == null:
		return
	if _player.vehicle.global_position.distance_to(car.global_position) < 7.0:
		WantedSystem.report_crime(&"hit_police", car.global_position)


# --------------------------------------------------------------------------- roadblocks and helicopter

func _update_roadblocks(delta: float, here: Vector3) -> void:
	var level: int = WantedSystem.level
	_roadblock_timer -= delta
	var driving_fast: bool = _player.is_in_vehicle() and _player.vehicle != null and _player.vehicle.get_speed_kmh() > 20.0
	if enabled and level >= tuning.roadblocks_from and driving_fast and _roadblock_timer <= 0.0:
		_roadblock_timer = tuning.roadblock_interval
		place_roadblock_ahead(level >= tuning.spikes_from)
	var camera: Camera3D = get_viewport().get_camera_3d()
	for block: Node3D in _roadblocks.duplicate():
		if _flat(block.global_position).distance_to(_flat(here)) > 150.0 and not _in_view(camera, block.global_position):
			_remove(block)


## Blocks the road about 90 m ahead of the player's car (following the road whichever lane the
## car is in) with police cars parked across every lane, and a spike strip in front of them if
## `spikes`. Returns the roadblock, or null if the road ahead doesn't go that far.
func place_roadblock_ahead(spikes: bool) -> Node3D:
	var vehicle: VehicleController = _player.vehicle
	if vehicle == null:
		return null
	var graph: LaneGraph = _router.graph
	var heading: Vector3 = vehicle.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var node: int = _router.nearest_node(vehicle.global_position + heading * 6.0)
	var previous: int = -1
	var travelled: float = 0.0
	# Along the road, straight on at junctions, until 90 m ahead and clear of any junction.
	while node >= 0 and (travelled < ROADBLOCK_AHEAD or graph.flags[node] != 0):
		if travelled > ROADBLOCK_AHEAD + 50.0:
			return null
		var best: int = -1
		var best_dot: float = 0.5
		for next: int in _router.neighbours_any_way(node):
			var d: Vector3 = graph.get_position(next) - graph.get_position(node)
			d.y = 0.0
			if next == previous or d.length() < 0.01:
				continue
			if d.normalized().dot(heading) > best_dot:
				best_dot = d.normalized().dot(heading)
				best = next
		if best < 0:
			return null
		var step: Vector3 = graph.get_position(best) - graph.get_position(node)
		step.y = 0.0
		travelled += step.length()
		heading = heading.lerp(step.normalized(), 0.5).normalized()     # follows gentle bends
		previous = node
		node = best
	if node < 0 or previous < 0 or not _streamer.is_position_loaded(graph.get_position(node)):
		return null
	var pos: Vector3 = graph.get_position(node)
	var along: Vector3 = pos - graph.get_position(previous)
	along.y = 0.0
	along = along.normalized()
	var left: Vector3 = Vector3.UP.cross(along)
	# Across all the lanes level with this spot, half a lane beyond the outer ones.
	var lo: float = 0.0
	var hi: float = 0.0
	for offset: float in _router.lanes_across(pos, along):
		lo = minf(lo, offset)
		hi = maxf(hi, offset)
	var centre: Vector3 = pos + left * (lo + hi) * 0.5
	var width: float = hi - lo + 3.4
	var count: int = clampi(ceili(width / ROADBLOCK_CAR_SPAN), 2, 4)
	var block := Node3D.new()
	block.name = "Roadblock%d" % _serial
	_serial += 1
	add_child(block)
	block.global_position = centre
	for i: int in count:
		# Parked across the road (nose pointing left), staggered so neighbours don't overlap,
		# lights flashing, nobody driving.
		var across: float = -width * 0.5 + width / count * (i + 0.5)
		var stagger: float = 1.2 if i % 2 == 0 else -1.2
		var xform := Transform3D(Basis.looking_at(-left, Vector3.UP), centre + left * across + along * stagger + Vector3.UP * 0.6)
		var car: VehicleController = _make_car(xform)
		car.reparent(block)
		(car.get_node("LightBar") as PoliceLightBar).active = true
	if spikes:
		var strip := SpikeStrip.new()
		strip.width = width
		block.add_child(strip)
		strip.global_transform = Transform3D(Basis.looking_at(along, Vector3.UP), centre - along * 14.0)
	_roadblocks.append(block)
	return block


func _update_helicopter(here: Vector3) -> void:
	var wanted: bool = WantedSystem.level >= tuning.helicopter_from
	if wanted and enabled and get_helicopter() == null:
		_heli = PoliceHelicopter.new()
		add_child(_heli)
		var camera: Camera3D = get_viewport().get_camera_3d()
		var away: Vector3 = (here - camera.global_position) if camera != null else Vector3.FORWARD
		away.y = 0.0
		_heli.global_position = here + away.normalized() * 160.0 + Vector3.UP * PoliceHelicopter.ALTITUDE
	var heli: PoliceHelicopter = get_helicopter()
	if heli != null:
		heli.target = (here if seen else WantedSystem.last_known) if wanted else here + Vector3(400.0, 0.0, 0.0)
		if not wanted and heli.global_position.distance_to(here) > 250.0:
			heli.queue_free()
			_heli = null


# --------------------------------------------------------------------------- arrest and leaving

func _check_bust(delta: float) -> void:
	var close: bool = false
	var seconds: float = tuning.bust_seconds
	if _player.is_down():                 # knocked out: the hospital, not the cells
		_bust_timer = 0.0
		return
	if not _player.is_in_vehicle():
		for officer: PoliceOfficer in _officers:
			if not officer.is_down() and _flat(officer.global_position).distance_to(_flat(_player.global_position)) < tuning.bust_distance:
				close = true
	elif _player.vehicle != null and _player.vehicle.get_speed_kmh() < 3.0:
		seconds = tuning.bust_car_seconds
		var car_at: Vector3 = _player.vehicle.global_position
		for node: Node3D in _units(false):
			if node is PoliceOfficer and (node as PoliceOfficer).is_down():
				continue
			if node.global_position.distance_to(car_at) < tuning.bust_car_distance:
				close = true
	_bust_timer = _bust_timer + delta if close else maxf(0.0, _bust_timer - delta * 2.0)
	if _bust_timer >= seconds:
		_bust_timer = 0.0
		WantedSystem.bust()


func get_bust_progress() -> float:
	return _bust_timer


func _wind_down(delta: float, here: Vector3) -> void:
	if _cars.is_empty() and _officers.is_empty() and get_helicopter() == null and _roadblocks.is_empty():
		return
	seen = false
	_bust_timer = 0.0
	_leave_timer += delta
	var camera: Camera3D = get_viewport().get_camera_3d()
	for car: VehicleController in _cars:
		(car.get_node("LightBar") as PoliceLightBar).active = false
		var driver := car.get_node_or_null("Driver") as PoliceDriver
		if driver != null:
			driver.target = here
			driver.set_mode(PoliceDriver.Mode.LEAVE)
	for officer: PoliceOfficer in _officers:
		if not officer.is_down():
			officer.state = PoliceOfficer.State.LEAVE
			var away: Vector3 = officer.global_position - here
			away.y = 0.0
			officer.target = officer.global_position + away.normalized() * 40.0
	_update_helicopter(here)
	for node: Node3D in _units(true):
		var out_of_sight: bool = not _in_view(camera, node.global_position + Vector3.UP)
		var gone: bool = _flat(node.global_position).distance_to(_flat(here)) > 40.0 and out_of_sight
		if gone or (_leave_timer > LEAVE_SECONDS and out_of_sight) or _leave_timer > LEAVE_SECONDS * 3.0:
			_remove(node)


func _remove(node: Node3D) -> void:
	if node is VehicleController:
		_cars.erase(node as VehicleController)
		_deployed.erase(node)
	elif node is PoliceOfficer:
		_officers.erase(node as PoliceOfficer)
	else:
		_roadblocks.erase(node)
	if _player != null and _player.vehicle == node:
		return       # the player took a police car: it is theirs now
	node.queue_free()


## Police cars and officers (and, if `with_roadblocks`, roadblocks) in one untyped list.
func _units(with_roadblocks: bool) -> Array:
	var all: Array = []
	all.append_array(_cars)
	all.append_array(_officers)
	if with_roadblocks:
		all.append_array(_roadblocks)
	return all


func _prune() -> void:
	for list: Array in [_cars, _officers, _roadblocks]:
		for i: int in range(list.size() - 1, -1, -1):
			if not is_instance_valid(list[i]) or (list[i] as Node).is_queued_for_deletion():
				list.remove_at(i)


func _focus_position() -> Vector3:
	return _player.vehicle.global_position if _player.is_in_vehicle() and _player.vehicle != null else _player.global_position


static func _in_view(camera: Camera3D, point: Vector3) -> bool:
	return camera != null and camera.is_position_in_frustum(point)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
