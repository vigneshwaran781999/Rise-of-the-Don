class_name GpsNavigator
extends Node
## The GPS (GDD §11): a route along the roads (the lane graph) from the player to where they are
## heading: the waypoint they set on the full map, or else the current mission objective. The
## minimap and the full map draw the route; it is recalculated as the player moves or strays.
## Also offers the waypoint as a map blip.

signal route_changed(route: PackedVector3Array)
signal waypoint_changed(waypoint: Variant)

const BLIP_GROUP: StringName = &"map_blips"
const GRID: float = 16.0
## Recalculate at least this often (seconds), and at once when the player is this far off the route.
const REFRESH_SECONDS: float = 1.5
const OFF_ROUTE: float = 14.0
## Mission objectives closer than this don't get a route (the marker is in plain sight).
const MISSION_ROUTE_MIN: float = 45.0
## Reaching the waypoint (this close) clears it.
const ARRIVED: float = 12.0

var route := PackedVector3Array()

var _graph: LaneGraph
var _player: PlayerController
var _astar := AStar3D.new()
var _grid: Dictionary = {}           # Vector2i cell -> PackedInt32Array of lane nodes
var _waypoint: Variant = null        # Vector3 or null
var _mission_target: Node3D
var _timer: float = 0.0
var _goal_node: int = -1


func _ready() -> void:
	add_to_group(BLIP_GROUP)


func setup(graph: LaneGraph, player: PlayerController, director: MissionDirector) -> void:
	_graph = graph
	_player = player
	_astar.reserve_space(graph.size())
	for i: int in graph.size():
		_astar.add_point(i, graph.get_position(i))
		var cell := Vector2i(floori(graph.get_position(i).x / GRID), floori(graph.get_position(i).z / GRID))
		if not _grid.has(cell):
			_grid[cell] = PackedInt32Array()
		(_grid[cell] as PackedInt32Array).append(i)
	for i: int in graph.size():
		for n: int in graph.get_next(i):
			_astar.connect_points(i, n, false)
	director.waypoint_changed.connect(func(target: Node3D) -> void:
		_mission_target = target
		_timer = 0.0)


func get_waypoint() -> Variant:
	return _waypoint


## Sets the player's own waypoint (snapped onto the nearest road); it takes over from the mission.
func set_waypoint(world: Vector3) -> void:
	var node: int = nearest_node(world)
	_waypoint = _graph.get_position(node) if node >= 0 else world
	_timer = 0.0
	waypoint_changed.emit(_waypoint)


func clear_waypoint() -> void:
	_waypoint = null
	_timer = 0.0
	waypoint_changed.emit(null)


## Where the route leads now (the waypoint, or the mission objective), or null.
func get_target() -> Variant:
	if _waypoint != null:
		return _waypoint
	if _mission_target != null and is_instance_valid(_mission_target) and _mission_target.is_inside_tree():
		return _mission_target.global_position
	return null


## The lane node nearest `pos` (horizontal), or -1.
func nearest_node(pos: Vector3) -> int:
	var centre := Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))
	var best: int = -1
	var best_d: float = INF
	for ring: int in 4:
		for dx: int in range(-ring, ring + 1):
			for dz: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				for i: int in _grid.get(centre + Vector2i(dx, dz), PackedInt32Array()):
					var p: Vector3 = _graph.get_position(i)
					var d: float = (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
					if d < best_d:
						best_d = d
						best = i
		if best >= 0 and ring >= 1:
			break
	return best if best >= 0 else _graph.nearest(pos)


func get_map_blips() -> Array[Dictionary]:
	var blips: Array[Dictionary] = []
	if _waypoint != null:
		blips.append({"position": _waypoint, "kind": &"waypoint", "label": "Waypoint"})
	return blips


func _process(delta: float) -> void:
	if _player == null:
		return
	var here: Vector3 = _player.global_position
	if _waypoint != null and Vector2(here.x - (_waypoint as Vector3).x, here.z - (_waypoint as Vector3).z).length() < ARRIVED:
		clear_waypoint()
	_timer -= delta
	if _timer > 0.0 and not _off_route(here):
		return
	_timer = REFRESH_SECONDS
	_update_route(here)


func _update_route(here: Vector3) -> void:
	var target: Variant = get_target()
	var new_route := PackedVector3Array()
	if target != null:
		var goal: Vector3 = target
		var far_enough: bool = _waypoint != null or Vector2(here.x - goal.x, here.z - goal.z).length() > MISSION_ROUTE_MIN
		if far_enough:
			var start: int = nearest_node(here)
			_goal_node = nearest_node(goal)
			if start >= 0 and _goal_node >= 0:
				new_route = _astar.get_point_path(start, _goal_node)
				if not new_route.is_empty():
					new_route.insert(0, Vector3(here.x, new_route[0].y, here.z))
					new_route.append(goal)
	if new_route != route:
		route = new_route
		route_changed.emit(route)


func _off_route(here: Vector3) -> bool:
	if route.size() < 2:
		return false
	var flat := Vector2(here.x, here.z)
	var best: float = INF
	for i: int in mini(route.size() - 1, 8):
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i + 1].x, route[i + 1].z)
		best = minf(best, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, a, b)))
	return best > OFF_ROUTE
