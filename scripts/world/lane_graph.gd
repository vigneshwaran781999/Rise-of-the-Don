class_name LaneGraph
extends Resource
## Directed graph of traffic lanes for the whole city (GDD §6: traffic follows a lane graph, not
## the navmesh). Left-hand traffic. Built by tools/godot/build_city.gd; AI traffic (M4)
## drives from node to node. Node i has a position on its lane centre line, a speed limit, and
## for nodes at a stop line or inside a junction the junction's id. Successors are stored in
## compressed form: the nodes after i are next_list[next_start[i] .. next_start[i + 1]).

enum Flag {
	STOP_LINE = 1,     ## last node before a junction; stop here on red / to give way
	SIGNALIZED = 2,    ## the junction has traffic lights (check signal_axis)
	GIVE_WAY = 4,      ## unsignalized junction where this approach must yield (lane meeting a main road)
	IN_JUNCTION = 8,   ## on a turn/straight path through a junction box
	U_TURN = 16,       ## turning back where a road ends (the edge of the city)
}

@export var positions: PackedVector3Array = PackedVector3Array()
@export var speed_kmh: PackedFloat32Array = PackedFloat32Array()
## Junction id for stop-line and in-junction nodes, otherwise -1.
@export var junction: PackedInt32Array = PackedInt32Array()
## For stop lines: 0 = travelling along Z (north-south), 1 = along X. Matches TrafficSignal axes.
@export var signal_axis: PackedInt32Array = PackedInt32Array()
@export var flags: PackedInt32Array = PackedInt32Array()
## For nodes on a road with two lanes each way: the node level with this one in the other lane
## going the same way (traffic changes lanes to pass a parked car), otherwise -1.
@export var side_lane: PackedInt32Array = PackedInt32Array()
## Centre of each junction, by junction id (traffic checks whether a junction is clear).
@export var junction_positions: PackedVector3Array = PackedVector3Array()
@export var next_start: PackedInt32Array = PackedInt32Array()
@export var next_list: PackedInt32Array = PackedInt32Array()


func size() -> int:
	return positions.size()


func get_position(i: int) -> Vector3:
	return positions[i]


func get_next(i: int) -> PackedInt32Array:
	return next_list.slice(next_start[i], next_start[i + 1])


func has_flag(i: int, flag: Flag) -> bool:
	return (flags[i] & flag) != 0


## Index of the node nearest to pos (horizontal distance), or -1 for an empty graph.
func nearest(pos: Vector3) -> int:
	var best: int = -1
	var best_d: float = INF
	for i: int in positions.size():
		var p: Vector3 = positions[i]
		var d: float = (p.x - pos.x) * (p.x - pos.x) + (p.z - pos.z) * (p.z - pos.z)
		if d < best_d:
			best_d = d
			best = i
	return best


## Number of nodes that can't be reached from node 0 or can't get back to it (0 means every
## lane is part of one connected network with no dead ends).
func count_disconnected() -> int:
	if size() == 0:
		return 0
	var forward: PackedByteArray = _reach(false)
	var backward: PackedByteArray = _reach(true)
	var missing: int = 0
	for i: int in size():
		if forward[i] == 0 or backward[i] == 0:
			missing += 1
	return missing


func _reach(reverse: bool) -> PackedByteArray:
	var n: int = size()
	var adjacency: Array[PackedInt32Array] = []
	adjacency.resize(n)
	for i: int in n:
		adjacency[i] = PackedInt32Array()
	for i: int in n:
		for j: int in get_next(i):
			if reverse:
				adjacency[j].append(i)
			else:
				adjacency[i].append(j)
	var seen := PackedByteArray()
	seen.resize(n)
	var stack: Array[int] = [0]
	seen[0] = 1
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for j: int in adjacency[i]:
			if seen[j] == 0:
				seen[j] = 1
				stack.append(j)
	return seen
