class_name RoadRouter
extends RefCounted
## Routes along the roads: A* over a district's lane graph (directed, keeps left), plus a quick
## "nearest lane node" lookup. Built once per lane graph and shared (the GPS, police drivers).

const GRID: float = 16.0

static var _shared: Dictionary = {}      # LaneGraph instance id -> RoadRouter

var graph: LaneGraph
var _astar := AStar3D.new()
var _astar_any := AStar3D.new()          # the same roads, every lane both ways
var _grid: Dictionary = {}               # Vector2i cell -> PackedInt32Array of lane nodes


static func for_graph(lane_graph: LaneGraph) -> RoadRouter:
	var key: int = lane_graph.get_instance_id()
	if not _shared.has(key):
		var router := RoadRouter.new()
		router._build(lane_graph)
		_shared[key] = router
	return _shared[key]


## Positions along the roads from near `from` to near `to` ([] if there is no way). With a
## `heading` (a vehicle's forward direction) the route starts on a lane going that way, so a car
## isn't sent round the block from the lane opposite.
func route(from: Vector3, to: Vector3, heading: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	var start: int = nearest_node(from) if heading == Vector3.ZERO else nearest_node_heading(from, heading)
	var goal: int = nearest_node(to)
	if start < 0 or goal < 0:
		return PackedVector3Array()
	return _astar.get_point_path(start, goal)


## Like route(), but any lane may be driven either way (emergency vehicles ignoring the rules):
## the shortest way along the roads.
func route_any_way(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start: int = nearest_node(from)
	var goal: int = nearest_node(to)
	if start < 0 or goal < 0:
		return PackedVector3Array()
	return _astar_any.get_point_path(start, goal)


## The lane nodes joined to `node` along the road, ahead or behind (lanes taken either way).
func neighbours_any_way(node: int) -> PackedInt64Array:
	return _astar_any.get_point_connections(node)


## Sideways offsets (along UP x `along`, so positive is left of `along`) of the lanes level with
## `pos` on the same road: lane segments running with or against `along` that pass level with
## `pos` within `reach` metres to the side.
func lanes_across(pos: Vector3, along: Vector3, reach: float = 9.0) -> PackedFloat32Array:
	var forward := Vector3(along.x, 0.0, along.z).normalized()
	var side: Vector3 = Vector3.UP.cross(forward)
	var offsets := PackedFloat32Array()
	var centre := Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))
	for dx: int in range(-2, 3):
		for dz: int in range(-2, 3):
			for i: int in _grid.get(centre + Vector2i(dx, dz), PackedInt32Array()):
				if graph.has_flag(i, LaneGraph.Flag.IN_JUNCTION):
					continue
				var a: Vector3 = graph.get_position(i)
				for n: int in graph.get_next(i):
					var lane: Vector3 = graph.get_position(n) - a
					lane.y = 0.0
					if lane.length() < 0.01 or absf(lane.normalized().dot(forward)) < 0.9:
						continue
					var t: float = Vector3(pos.x - a.x, 0.0, pos.z - a.z).dot(lane) / lane.length_squared()
					if t < 0.0 or t > 1.0:
						continue
					var across: float = (a + lane * t - pos).dot(side)
					if absf(across) > reach:
						continue
					var known: bool = false
					for o: float in offsets:
						known = known or absf(o - across) < 1.0
					if not known:
						offsets.append(across)
	return offsets


## The lane node nearest `pos` (horizontally), or -1.
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
					var p: Vector3 = graph.get_position(i)
					var d: float = (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
					if d < best_d:
						best_d = d
						best = i
		if best >= 0 and ring >= 1:
			break
	return best if best >= 0 else graph.nearest(pos)


## The nearest lane node within 20 m whose lane runs along `heading` (falls back to the nearest).
func nearest_node_heading(pos: Vector3, heading: Vector3) -> int:
	var flat := Vector3(heading.x, 0.0, heading.z).normalized()
	var centre := Vector2i(floori(pos.x / GRID), floori(pos.z / GRID))
	var best: int = -1
	var best_d: float = 20.0 * 20.0
	for dx: int in range(-2, 3):
		for dz: int in range(-2, 3):
			for i: int in _grid.get(centre + Vector2i(dx, dz), PackedInt32Array()):
				var next: PackedInt32Array = graph.get_next(i)
				if next.is_empty():
					continue
				var lane: Vector3 = graph.get_position(next[0]) - graph.get_position(i)
				lane.y = 0.0
				if lane.normalized().dot(flat) < 0.5:
					continue
				var p: Vector3 = graph.get_position(i)
				var d: float = (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
				if d < best_d:
					best_d = d
					best = i
	return best if best >= 0 else nearest_node(pos)


func _build(lane_graph: LaneGraph) -> void:
	graph = lane_graph
	_astar.reserve_space(graph.size())
	_astar_any.reserve_space(graph.size())
	# Gathered in plain Arrays (shared by reference: appending to a packed array fetched out of a
	# Dictionary appends to a copy), then packed.
	var cells: Dictionary = {}
	for i: int in graph.size():
		var p: Vector3 = graph.get_position(i)
		_astar.add_point(i, p)
		_astar_any.add_point(i, p)
		var cell := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
		if not cells.has(cell):
			cells[cell] = []
		(cells[cell] as Array).append(i)
	for cell: Vector2i in cells:
		_grid[cell] = PackedInt32Array(cells[cell])
	for i: int in graph.size():
		for n: int in graph.get_next(i):
			_astar.connect_points(i, n, false)
			_astar_any.connect_points(i, n, true)
