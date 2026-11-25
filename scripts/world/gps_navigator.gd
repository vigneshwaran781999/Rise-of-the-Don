class_name GpsNavigator
extends Node
## The GPS (GDD §11): a route along the roads (RoadRouter over the lane graph) from the player to
## where they are heading: the waypoint they set on the full map, or else the current mission
## objective. The minimap and the full map draw the route; it is recalculated as the player
## moves or strays. Also offers the waypoint as a map blip.

signal route_changed(route: PackedVector3Array)
signal waypoint_changed(waypoint: Variant)

const BLIP_GROUP: StringName = &"map_blips"
## Recalculate at least this often (seconds), and at once when the player is this far off the route.
const REFRESH_SECONDS: float = 1.5
const OFF_ROUTE: float = 14.0
## Mission objectives closer than this don't get a route (the marker is in plain sight).
const MISSION_ROUTE_MIN: float = 45.0
## Reaching the waypoint (this close) clears it.
const ARRIVED: float = 12.0

var route := PackedVector3Array()

var _router: RoadRouter
var _player: PlayerController
var _waypoint: Variant = null        # Vector3 or null
var _mission_target: Node3D
var _timer: float = 0.0


func _ready() -> void:
	add_to_group(BLIP_GROUP)


func setup(graph: LaneGraph, player: PlayerController, director: MissionDirector) -> void:
	_router = RoadRouter.for_graph(graph)
	_player = player
	director.waypoint_changed.connect(func(target: Node3D) -> void:
		_mission_target = target
		_timer = 0.0)


func get_waypoint() -> Variant:
	return _waypoint


## Sets the player's own waypoint (snapped onto the nearest road); it takes over from the mission.
func set_waypoint(world: Vector3) -> void:
	var node: int = _router.nearest_node(world)
	_waypoint = _router.graph.get_position(node) if node >= 0 else world
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
		if _waypoint != null or Vector2(here.x - goal.x, here.z - goal.z).length() > MISSION_ROUTE_MIN:
			new_route = _router.route(here, goal)
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
