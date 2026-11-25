class_name LaneGraphDebug
extends MeshInstance3D
## Debug view, toggled with toggle_lane_debug (F4): draws the lane graph around the player
## (lanes cyan, paths through junctions white, U-turns magenta, stop lines coloured by their
## traffic light) and the edges of the pedestrian navmesh in green. Off by default.

const LIFT: float = 0.25

@export var radius: float = 90.0

var graph: LaneGraph
var focus: Node3D
## Searched for NavigationRegion3D nodes (the streamed chunks).
var world: Node

var _lines: ImmediateMesh
var _timer: float = 0.0


func _ready() -> void:
	_lines = ImmediateMesh.new()
	mesh = _lines
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat
	visible = false


func setup(lane_graph: LaneGraph, follow: Node3D, search_root: Node) -> void:
	graph = lane_graph
	focus = follow
	world = search_root


func is_showing() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_lane_debug"):
		visible = not visible
		_timer = 0.0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or graph == null or focus == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	_redraw()


func _redraw() -> void:
	var points := PackedVector3Array()
	var colours := PackedColorArray()
	var here: Vector3 = focus.global_position
	var r2: float = radius * radius
	var signal_by_junction: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(TrafficSignal.GROUP):
		var sig := node as TrafficSignal
		signal_by_junction[sig.junction_id] = sig
	for i: int in graph.size():
		var p: Vector3 = graph.get_position(i)
		if (p.x - here.x) * (p.x - here.x) + (p.z - here.z) * (p.z - here.z) > r2:
			continue
		var colour: Color = UIStyle.CYAN
		if graph.has_flag(i, LaneGraph.Flag.IN_JUNCTION):
			colour = Color(1, 1, 1, 0.8)
		elif graph.has_flag(i, LaneGraph.Flag.U_TURN):
			colour = UIStyle.MAGENTA
		for j: int in graph.get_next(i):
			points.append(p + Vector3.UP * LIFT)
			points.append(graph.get_position(j) + Vector3.UP * LIFT)
			colours.append(colour)
			colours.append(colour)
		if graph.has_flag(i, LaneGraph.Flag.STOP_LINE):
			var stop_colour := Color(1, 1, 1)
			if graph.has_flag(i, LaneGraph.Flag.SIGNALIZED) and signal_by_junction.has(graph.junction[i]):
				var light: int = (signal_by_junction[graph.junction[i]] as TrafficSignal).get_light(graph.signal_axis[i])
				stop_colour = [Color(1, 0.15, 0.1), Color(1, 0.7, 0.1), Color(0.2, 1, 0.4)][light]
			elif graph.has_flag(i, LaneGraph.Flag.GIVE_WAY):
				stop_colour = Color(1, 0.85, 0.2)
			for a: Vector3 in [Vector3(-0.8, 0, 0), Vector3(0, 0, -0.8)]:
				points.append(p + a + Vector3.UP * LIFT)
				points.append(p - a + Vector3.UP * LIFT)
				colours.append(stop_colour)
				colours.append(stop_colour)
	if world != null:
		# Navmesh edges first (dim), lanes on top.
		var nav_points := PackedVector3Array()
		var nav_colours := PackedColorArray()
		for node: Node in world.find_children("*", "NavigationRegion3D", true, false):
			var nav_mesh: NavigationMesh = (node as NavigationRegion3D).navigation_mesh
			if nav_mesh == null:
				continue
			var verts: PackedVector3Array = nav_mesh.get_vertices()
			for poly: int in nav_mesh.get_polygon_count():
				var idx: PackedInt32Array = nav_mesh.get_polygon(poly)
				var first: Vector3 = verts[idx[0]]
				if (first.x - here.x) * (first.x - here.x) + (first.z - here.z) * (first.z - here.z) > r2:
					continue
				for k: int in idx.size():
					nav_points.append(verts[idx[k]] + Vector3.UP * 0.08)
					nav_points.append(verts[idx[(k + 1) % idx.size()]] + Vector3.UP * 0.08)
					nav_colours.append(Color(0.3, 1, 0.45, 0.3))
					nav_colours.append(Color(0.3, 1, 0.45, 0.3))
		nav_points.append_array(points)
		nav_colours.append_array(colours)
		points = nav_points
		colours = nav_colours
	_lines.clear_surfaces()
	if points.is_empty():
		return
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for k: int in points.size():
		_lines.surface_set_color(colours[k])
		_lines.surface_add_vertex(points[k])
	_lines.surface_end()
