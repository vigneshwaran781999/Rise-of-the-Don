class_name CityBlockBuilder
extends Node3D
## Builds the M1 test block at runtime from the Blender road kit, buildings and props.
##
## Layout (metres, +X east, -Z north): three roads each way on the lines -60, 0 and +60,
## 12 m wide, with a crosswalk on every junction approach; 4 m sidewalks; raised lots between
## them (paved, grass, temple sand); 12 buildings; a walled temple compound with a gopuram
## gateway and a raised platform (one gentle ramp, one too-steep ramp to test slope limits);
## streetlights; palms; invisible boundary walls at +-102 m. The player spawns at PlayerSpawn.
## The roads stop at the walls for now; M3 replaces this block with streamed chunks.

const ROAD_STRAIGHT: PackedScene = preload("res://assets/models/road/road_straight.glb")
const ROAD_CROSSWALK: PackedScene = preload("res://assets/models/road/road_crosswalk.glb")
const ROAD_INTERSECTION: PackedScene = preload("res://assets/models/road/road_intersection.glb")
const SIDEWALK: PackedScene = preload("res://assets/models/road/road_sidewalk.glb")
const SIDEWALK_CORNER: PackedScene = preload("res://assets/models/road/road_sidewalk_corner.glb")
const STREETLIGHT: PackedScene = preload("res://assets/models/props/prop_streetlight.glb")
const PALM: PackedScene = preload("res://assets/models/props/prop_palm_tree.glb")
const TEMPLE_WALL: PackedScene = preload("res://assets/models/props/prop_temple_wall.glb")
const GOPURAM: PackedScene = preload("res://assets/models/buildings/bld_temple_gopuram.glb")
const SHRINE: PackedScene = preload("res://assets/models/buildings/bld_temple_shrine.glb")
const BUILDING_SCENES: Dictionary = {
	&"shophouse_01": preload("res://assets/models/buildings/bld_shophouse_01.glb"),
	&"shophouse_02": preload("res://assets/models/buildings/bld_shophouse_02.glb"),
	&"shophouse_03": preload("res://assets/models/buildings/bld_shophouse_03.glb"),
	&"apartment_01": preload("res://assets/models/buildings/bld_apartment_01.glb"),
	&"apartment_02": preload("res://assets/models/buildings/bld_apartment_02.glb"),
	&"office_01": preload("res://assets/models/buildings/bld_office_01.glb"),
	&"office_02": preload("res://assets/models/buildings/bld_office_02.glb"),
}

const LINES: Array = [-60.0, 0.0, 60.0]
const EXTENT: float = 102.0
const TILE: float = 12.0
const ROAD_HALF: float = 6.0
const WALK_WIDTH: float = 4.0
const WALK_TILE: float = 8.0
const LOT_TOP: float = 0.15

## [building, x, z, yaw degrees]. Buildings face +Z at yaw 0 (south); 90 faces east.
const BUILDINGS: Array = [
	[&"office_01", -30.0, -22.0, 0.0],
	[&"apartment_01", 21.0, -17.0, 0.0],
	[&"apartment_02", 39.0, -17.0, 0.0],
	[&"shophouse_01", -16.5, 16.0, 90.0],
	[&"shophouse_02", -16.5, 24.0, 90.0],
	[&"shophouse_03", -16.5, 32.0, 90.0],
	[&"shophouse_01", -16.5, 40.0, 90.0],
	[&"shophouse_03", -27.0, 43.5, 0.0],
	[&"shophouse_02", -35.0, 43.5, 0.0],
	[&"office_02", -30.0, -84.0, 0.0],
]
## Temple compound occupies the lot x 10..50, z 10..50.
const GOPURAM_POS := Vector3(15.0, LOT_TOP, 30.0)
const PLATFORM_CENTER := Vector3(35.0, LOT_TOP, 30.0)
const PLATFORM_SIZE := Vector3(12.0, 1.0, 12.0)
## Lot centre (rounded) -> ground kind. Everything else is grass.
const LOT_KINDS: Dictionary = {
	Vector2i(-30, -30): &"paved",
	Vector2i(30, -30): &"grass",
	Vector2i(-30, 30): &"paved_old",
	Vector2i(30, 30): &"sand",
	Vector2i(-30, -86): &"paved",
}
const GROUND_COLOURS: Dictionary = {
	&"grass": Color("5f7d3c"),
	&"paved": Color("8e897f"),
	&"paved_old": Color("9b8a74"),
	&"sand": Color("c9aa7c"),
	&"stone": Color("a39581"),
	&"outer": Color("67703f"),
}
const PALM_SPOTS: Array = [
	Vector2(14.0, 14.0), Vector2(46.0, 14.0), Vector2(46.0, 46.0), Vector2(14.0, 46.0),
	Vector2(24.0, 16.0), Vector2(24.0, 44.0),
	Vector2(14.0, -44.0), Vector2(24.0, -36.0), Vector2(34.0, -44.0), Vector2(44.0, -33.0), Vector2(19.0, -29.0),
	Vector2(-46.0, -46.0), Vector2(-14.0, -46.0), Vector2(-46.0, -14.0), Vector2(-14.0, -14.0),
	Vector2(-44.0, 14.0), Vector2(-36.0, 22.0), Vector2(-46.0, 30.0),
]
const PALM_SEED: int = 1337

var _materials: Dictionary = {}
var _roads: Node3D
var _walks: Node3D
var _ground: Node3D
var _buildings: Node3D
var _props: Node3D


func _ready() -> void:
	_roads = _group("Roads")
	_walks = _group("Sidewalks")
	_ground = _group("Ground")
	_buildings = _group("Buildings")
	_props = _group("Props")
	_build_roads()
	_build_sidewalks()
	_build_lots()
	_build_buildings()
	_build_temple()
	_build_streetlights()
	_build_palms()
	_build_bounds()


func get_spawn_transform() -> Transform3D:
	return ($PlayerSpawn as Marker3D).global_transform


# --------------------------------------------------------------------------- roads

func _build_roads() -> void:
	for cx: float in LINES:
		for cz: float in LINES:
			_place(ROAD_INTERSECTION, Vector3(cx, 0.0, cz), 0.0, _roads)
	for line: float in LINES:
		var t: float = -EXTENT + TILE * 0.5
		while t < EXTENT:
			var gap: float = t - _nearest_line(t)
			if absf(gap) > 1.0:
				if absf(gap) < TILE + 1.0:
					# First tile out of a junction: zebra end (local -Z) faces the junction.
					var s: float = signf(gap)
					_place(ROAD_CROSSWALK, Vector3(line, 0.0, t), _yaw_facing(Vector3(0.0, 0.0, -s)), _roads)
					_place(ROAD_CROSSWALK, Vector3(t, 0.0, line), _yaw_facing(Vector3(-s, 0.0, 0.0)), _roads)
				else:
					_place(ROAD_STRAIGHT, Vector3(line, 0.0, t), 0.0, _roads)
					_place(ROAD_STRAIGHT, Vector3(t, 0.0, line), PI * 0.5, _roads)
			t += TILE


func _build_sidewalks() -> void:
	var offset: float = ROAD_HALF + WALK_WIDTH * 0.5
	for line: float in LINES:
		for seg: Vector2 in _walk_intervals():
			var t: float = seg.x + WALK_TILE * 0.5
			while t < seg.y:
				for side: float in [-1.0, 1.0]:
					_place(SIDEWALK, Vector3(line + side * offset, 0.0, t), _yaw_curb(Vector3(-side, 0.0, 0.0)), _walks)
					_place(SIDEWALK, Vector3(t, 0.0, line + side * offset), _yaw_curb(Vector3(0.0, 0.0, -side)), _walks)
				t += WALK_TILE
	for cx: float in LINES:
		for cz: float in LINES:
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_place(SIDEWALK_CORNER, Vector3(cx + sx * offset, 0.0, cz + sz * offset), _yaw_corner(sx, sz), _walks)


## Stretches along each axis not taken by roads or junction corners: [-102,-70], [-50,-10], ...
func _walk_intervals() -> Array[Vector2]:
	var result: Array[Vector2] = []
	var start: float = -EXTENT
	for line: float in LINES:
		result.append(Vector2(start, line - ROAD_HALF - WALK_WIDTH))
		start = line + ROAD_HALF + WALK_WIDTH
	result.append(Vector2(start, EXTENT))
	return result


func _nearest_line(t: float) -> float:
	var best: float = LINES[0]
	for line: float in LINES:
		if absf(t - line) < absf(t - best):
			best = line
	return best


# --------------------------------------------------------------------------- ground

func _build_lots() -> void:
	var intervals: Array[Vector2] = _walk_intervals()
	for ix: Vector2 in intervals:
		for iz: Vector2 in intervals:
			var center := Vector2i(roundi((ix.x + ix.y) * 0.5), roundi((iz.x + iz.y) * 0.5))
			var kind: StringName = LOT_KINDS.get(center, &"grass")
			var size := Vector3(ix.y - ix.x, 0.5, iz.y - iz.x)
			var pos := Vector3((ix.x + ix.y) * 0.5, LOT_TOP - 0.25, (iz.x + iz.y) * 0.5)
			_solid_box("Lot_%d_%d" % [center.x, center.y], Transform3D(Basis.IDENTITY, pos), size, kind, _ground)
	# Ground beyond the walls (visual only), so the horizon isn't a void.
	var outer := MeshInstance3D.new()
	outer.name = "OuterGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600.0, 1600.0)
	plane.material = _material(&"outer")
	outer.mesh = plane
	outer.position = Vector3(0.0, -0.05, 0.0)
	_ground.add_child(outer)


func _solid_box(node_name: String, xform: Transform3D, size: Vector3, kind: StringName, parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.transform = xform
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(kind)
	mesh_instance.mesh = box
	body.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)


func _material(kind: StringName) -> StandardMaterial3D:
	if not _materials.has(kind):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GROUND_COLOURS[kind]
		mat.roughness = 0.95
		_materials[kind] = mat
	return _materials[kind]


# --------------------------------------------------------------------------- buildings

func _build_buildings() -> void:
	for entry: Array in BUILDINGS:
		var scene: PackedScene = BUILDING_SCENES[entry[0]]
		var node: Node3D = _place(scene, Vector3(entry[1], LOT_TOP, entry[2]), deg_to_rad(entry[3]), _buildings)
		node.name = "%s_%d_%d" % [str(entry[0]), int(entry[1]), int(entry[2])]


func _build_temple() -> void:
	var temple := Node3D.new()
	temple.name = "Temple"
	_buildings.add_child(temple)
	var gopuram: Node3D = _place(GOPURAM, GOPURAM_POS, deg_to_rad(-90.0), temple)
	gopuram.name = "Gopuram"

	# Compound wall: west side leaves a gap exactly where the gopuram stands (z 23..37).
	var wall_z: Array[float] = [12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0]
	for x: float in [12.0, 16.0, 20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 44.0, 48.0]:
		_place(TEMPLE_WALL, Vector3(x, LOT_TOP, 10.5), 0.0, temple)
		_place(TEMPLE_WALL, Vector3(x, LOT_TOP, 49.5), 0.0, temple)
	for z: float in wall_z:
		_place(TEMPLE_WALL, Vector3(49.5, LOT_TOP, z), PI * 0.5, temple)
	for z: float in [13.0, 17.0, 21.0, 39.0, 43.0, 47.0]:
		_place(TEMPLE_WALL, Vector3(10.5, LOT_TOP, z), PI * 0.5, temple)

	# Raised platform with the shrine on top.
	var top: float = PLATFORM_CENTER.y + PLATFORM_SIZE.y
	_solid_box("Platform", Transform3D(Basis.IDENTITY, PLATFORM_CENTER + Vector3.UP * PLATFORM_SIZE.y * 0.5),
			PLATFORM_SIZE, &"stone", temple)
	var shrine: Node3D = _place(SHRINE, Vector3(PLATFORM_CENTER.x, top, PLATFORM_CENTER.z), deg_to_rad(-90.0), temple)
	shrine.name = "Shrine"
	# West ramp at 18 degrees (walkable); south ramp at 50 degrees (steeper than the 46 degree limit).
	var west_edge := Vector3(PLATFORM_CENTER.x - PLATFORM_SIZE.x * 0.5, top, PLATFORM_CENTER.z)
	_ramp("RampWalkable", west_edge, Vector3.LEFT, PLATFORM_SIZE.y, 18.0, 4.0, temple)
	var south_edge := Vector3(PLATFORM_CENTER.x, top, PLATFORM_CENTER.z + PLATFORM_SIZE.z * 0.5)
	_ramp("RampTooSteep", south_edge, Vector3.BACK, PLATFORM_SIZE.y, 50.0, 4.0, temple)


## A tilted slab whose top surface runs from `top_edge` down `rise` metres, heading `outward`.
func _ramp(node_name: String, top_edge: Vector3, outward: Vector3, rise: float, angle_degrees: float,
		width: float, parent: Node3D) -> void:
	var angle: float = deg_to_rad(angle_degrees)
	var run: float = rise / tan(angle)
	var length: float = rise / sin(angle)
	var thickness: float = 0.4
	var low: Vector3 = top_edge + outward * run - Vector3.UP * rise
	var along: Vector3 = (low - top_edge).normalized()
	var side: Vector3 = outward.cross(Vector3.UP).normalized()
	var normal: Vector3 = side.cross(along).normalized()
	if normal.y < 0.0:
		normal = -normal
	var basis := Basis(side, normal, along)
	if basis.determinant() < 0.0:
		basis.x = -basis.x
	var center: Vector3 = (top_edge + low) * 0.5 - normal * thickness * 0.5
	_solid_box(node_name, Transform3D(basis, center), Vector3(width, thickness, length), &"stone", parent)


# --------------------------------------------------------------------------- props

func _build_streetlights() -> void:
	var offset: float = ROAD_HALF + 0.6
	for line: float in LINES:
		var index: int = 0
		for seg: Vector2 in _walk_intervals():
			var t: float = seg.x + WALK_TILE * 0.5
			while t < seg.y:
				if index % 2 == 0:
					var side: float = 1.0 if index % 4 == 0 else -1.0
					# Arm (local +X) reaches out over the road.
					_place(STREETLIGHT, Vector3(line + side * offset, LOT_TOP, t), _yaw_arm(Vector3(-side, 0.0, 0.0)), _props)
					_place(STREETLIGHT, Vector3(t, LOT_TOP, line + side * offset), _yaw_arm(Vector3(0.0, 0.0, -side)), _props)
				index += 1
				t += WALK_TILE


func _build_palms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PALM_SEED
	var spots: Array[Vector2] = []
	for spot: Vector2 in PALM_SPOTS:
		spots.append(spot)
	# A few more scattered over the outer lots, clear of the office tower in the north lot.
	var intervals: Array[Vector2] = _walk_intervals()
	for ix: Vector2 in intervals:
		for iz: Vector2 in intervals:
			var outer_lot: bool = absf(ix.x) >= EXTENT - 1.0 or absf(ix.y) >= EXTENT - 1.0 \
					or absf(iz.x) >= EXTENT - 1.0 or absf(iz.y) >= EXTENT - 1.0
			if not outer_lot:
				continue
			for i: int in rng.randi_range(2, 4):
				var p := Vector2(rng.randf_range(ix.x + 3.0, ix.y - 3.0), rng.randf_range(iz.x + 3.0, iz.y - 3.0))
				if Rect2(-40.0, -94.0, 20.0, 20.0).has_point(p):
					continue
				spots.append(p)
	for spot: Vector2 in spots:
		var palm: Node3D = _place(PALM, Vector3(spot.x, LOT_TOP, spot.y), rng.randf_range(-PI, PI), _props)
		palm.scale = Vector3.ONE * rng.randf_range(0.85, 1.2)


func _build_bounds() -> void:
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	add_child(bounds)
	var span: float = EXTENT * 2.0 + 4.0
	for wall: Array in [
		[Vector3(EXTENT + 1.0, 20.0, 0.0), Vector3(2.0, 40.0, span)],
		[Vector3(-EXTENT - 1.0, 20.0, 0.0), Vector3(2.0, 40.0, span)],
		[Vector3(0.0, 20.0, EXTENT + 1.0), Vector3(span, 40.0, 2.0)],
		[Vector3(0.0, 20.0, -EXTENT - 1.0), Vector3(span, 40.0, 2.0)],
		[Vector3(0.0, -2.0, 0.0), Vector3(span, 2.0, span)],  # safety floor under everything
	]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall[1]
		shape.shape = box
		shape.position = wall[0]
		bounds.add_child(shape)


# --------------------------------------------------------------------------- helpers

func _group(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node


func _place(scene: PackedScene, pos: Vector3, yaw: float, parent: Node3D) -> Node3D:
	var node: Node3D = scene.instantiate()
	node.position = pos
	node.rotation = Vector3(0.0, yaw, 0.0)
	parent.add_child(node)
	return node


## Yaw that points a piece's local -Z along `direction`.
func _yaw_facing(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## Yaw that points a sidewalk's kerb side (local -X) along `direction`.
func _yaw_curb(direction: Vector3) -> float:
	return atan2(direction.z, -direction.x)


## Yaw that points a streetlight's arm (local +X) along `direction`.
func _yaw_arm(direction: Vector3) -> float:
	return atan2(-direction.z, direction.x)


## Yaw for a corner piece (kerbs on local -X and +Z) so both kerbs face the junction centre.
func _yaw_corner(sx: float, sz: float) -> float:
	var want_a := Vector3(-sx, 0.0, 0.0)
	var want_b := Vector3(0.0, 0.0, -sz)
	for k: int in 4:
		var yaw: float = k * PI * 0.5
		var a: Vector3 = Vector3.LEFT.rotated(Vector3.UP, yaw)
		var b: Vector3 = Vector3.BACK.rotated(Vector3.UP, yaw)
		if (a.is_equal_approx(want_a) and b.is_equal_approx(want_b)) \
				or (a.is_equal_approx(want_b) and b.is_equal_approx(want_a)):
			return yaw
	push_error("CityBlockBuilder: no corner rotation for (%s, %s)" % [sx, sz])
	return 0.0
