class_name LaneGraphBuilder
extends RefCounted
## Assembles a LaneGraph node by node (build time). Nodes are added with their attributes,
## connected one way, then packed into the compact LaneGraph resource.

var _positions := PackedVector3Array()
var _speed := PackedFloat32Array()
var _junction := PackedInt32Array()
var _axis := PackedInt32Array()
var _flags := PackedInt32Array()
var _side := PackedInt32Array()
var _next: Array[PackedInt32Array] = []


func add_node(pos: Vector3, speed_kmh: float, junction: int = -1, axis: int = -1, flags: int = 0) -> int:
	_positions.append(pos)
	_speed.append(speed_kmh)
	_junction.append(junction)
	_axis.append(axis)
	_flags.append(flags)
	_side.append(-1)
	_next.append(PackedInt32Array())
	return _positions.size() - 1


func connect_nodes(from: int, to: int) -> void:
	if not _next[from].has(to):
		_next[from].append(to)


func set_flags(i: int, flags: int, junction: int, axis: int) -> void:
	_flags[i] |= flags
	_junction[i] = junction
	_axis[i] = axis


func size() -> int:
	return _positions.size()


func get_position(i: int) -> Vector3:
	return _positions[i]


func build() -> LaneGraph:
	var graph := LaneGraph.new()
	graph.positions = _positions
	graph.speed_kmh = _speed
	graph.junction = _junction
	graph.signal_axis = _axis
	graph.flags = _flags
	graph.side_lane = _side
	var start := PackedInt32Array()
	var targets := PackedInt32Array()
	for list: PackedInt32Array in _next:
		start.append(targets.size())
		targets.append_array(list)
	start.append(targets.size())
	graph.next_start = start
	graph.next_list = targets
	return graph


## Marks a and b as level with each other in neighbouring lanes that go the same way.
func set_side_lanes(a: int, b: int) -> void:
	_side[a] = b
	_side[b] = a
