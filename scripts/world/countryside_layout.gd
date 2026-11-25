class_name CountrysideLayout
extends DistrictLayout
## The Countryside (GDD §2 district 6, M7): villages, paddy fields, a lake and coconut groves,
## green, open and calm. Twice the size of the other districts: two cells on the west side of the
## city, north (west of Old Town, centre x = -512, z = 0) and south (centre z = 512).
## - North: a country lane runs along Old Town's border and collects its streets; the highway
##   (Old Town's middle road) and the two ring roads go on west. The Luxury District's two main
##   roads come down from the north and run on south through both halves.
## - Big blocks between the roads: paddy fields, coconut groves, the lake, and the village (huts,
##   farmhouses, a tea stall, a shrine and a well; the police post).
## - South: the two main roads, a cross road between them; fields, a grove, a second village and
##   a reservoir.

const SEED: int = 9157
const MAX_DEPTH: float = 14.0
const LINES_X_NORTH: Array = [[-112.0, MAIN], [128.0, MAIN], [232.0, LANE]]
## Old Town's east-west streets, so they all reach the country lane at x = 232.
const LINES_Z_NORTH: Array = [
	[-232.0, LANE], [-184.0, MAIN], [-148.0, LANE], [-112.0, MAIN], [-80.0, LANE], [-48.0, LANE],
	[0.0, MAIN], [48.0, LANE], [80.0, LANE], [112.0, MAIN], [148.0, LANE], [184.0, MAIN], [232.0, LANE],
]
const LINES_X_SOUTH: Array = [[-112.0, MAIN], [128.0, MAIN]]
const LINES_Z_SOUTH: Array = [[120.0, MAIN]]
## [kind, x0, x1, z0, z1]. North: west of the country lane only the roads at z = -112, 0 and 112
## (and, east of x = 128, Old Town's -232 and 184) carry on; Old Town's z = 232 lane ends at the
## border (the corner block).
const MERGED_NORTH: Array = [
	[&"fields", 128.0, 256.0, -256.0, -232.0], [&"fields", 128.0, 256.0, 184.0, 256.0],
	[&"grove", 128.0, 232.0, -232.0, -112.0], [&"grove", 128.0, 232.0, -112.0, 0.0],
	[&"fields", 128.0, 232.0, 0.0, 112.0], [&"fields", 128.0, 232.0, 112.0, 184.0],
	[&"grove", -256.0, -112.0, -256.0, -112.0], [&"fields", -112.0, 128.0, -256.0, -112.0],
	[&"fields", -256.0, -112.0, -112.0, 0.0], [&"village", -112.0, 128.0, -112.0, 0.0],
	[&"lake", -256.0, -112.0, 0.0, 112.0], [&"fields", -112.0, 128.0, 0.0, 112.0],
	[&"grove", -256.0, -112.0, 112.0, 256.0], [&"fields", -112.0, 128.0, 112.0, 256.0],
]
const MERGED_SOUTH: Array = [
	[&"fields", -256.0, -112.0, -256.0, 256.0], [&"grove", 128.0, 256.0, -256.0, 256.0],
	[&"village", -112.0, 128.0, -256.0, 120.0], [&"lake", -112.0, 128.0, 120.0, 256.0],
]
## Village buildings facing the roads: [kit, frontage width, depth, weight].
const VILLAGE_FRONT: Array = [
	[&"bld_cs_hut", 6.0, 6.0, 2.0], [&"bld_cs_farmhouse", 10.0, 12.0, 1.4], [&"bld_cs_teastall", 6.0, 6.0, 0.4],
	[&"bld_ot_house_01", 6.0, 10.0, 0.8], [&"bld_ot_house_03", 8.0, 10.0, 0.8],
]
## The police post (north village) takes the place of the farmhouse nearest this point.
const SPECIAL_BUILDINGS: Array = [
	[&"police_countryside", &"bld_cs_farmhouse", Vector3(0.0, 0.0, -10.0), &"bld_in_police", 7.6],
]
const CLEARABLE: Array[StringName] = [&"prop_streetlight", &"prop_palm_tree", &"prop_neem_tree"]

var north: bool = true


func _init(is_north: bool = true) -> void:
	north = is_north
	id = &"countryside_north" if north else &"countryside_south"
	display_name = "Countryside"


func _lines_x() -> Array:
	return LINES_X_NORTH if north else LINES_X_SOUTH


func _lines_z() -> Array:
	return LINES_Z_NORTH if north else LINES_Z_SOUTH


func _merged() -> Array:
	return MERGED_NORTH if north else MERGED_SOUTH


func _seed() -> int:
	return SEED + (0 if north else 1)


func _lot_kit(kind: StringName) -> StringName:
	return &"lot_paddy" if kind == &"fields" else &"lot_grass"


func _catalogue(_cls: int) -> Array:
	return VILLAGE_FRONT


func _max_depth() -> float:
	return MAX_DEPTH


## Country roads have no streetlights: nights out here are dark (headlights still work).
func _streetlight_kit() -> StringName:
	return &""


func _fill_block(kind: StringName, rect: Rect2, interior: Rect2, walk: Array[float], cls: Array[int]) -> void:
	match kind:
		&"fields":
			_fields(interior)
		&"grove":
			_lot(&"lot_grass", interior)
			_grove(interior)
		&"lake":
			_lot(&"lot_grass", interior)
			_lake(interior)
		&"village":
			_lot(&"lot_grass", interior)
			var sides: Array = []
			for c: int in cls:
				sides.append(null if c < 0 else VILLAGE_FRONT)
			var green: Rect2 = _frontages(interior, sides, MAX_DEPTH)
			_village_green(green)
		_:
			# The narrow strip along Old Town's border: verge and trees.
			_lot(&"lot_grass", interior)
			if interior.size.x >= 6.0 and interior.size.y >= 6.0:
				_place(&"prop_neem_tree", Vector3(interior.get_center().x, LOT_TOP, interior.get_center().y), _rng.randf() * TAU, Vector3.ONE, &"prop")


func _after_blocks() -> void:
	if north:
		_special_buildings(SPECIAL_BUILDINGS, CLEARABLE)
	for m: Array in _merged():
		var at: Vector2 = centre + Vector2((float(m[1]) + float(m[2])) * 0.5, (float(m[3]) + float(m[4])) * 0.5)
		match m[0]:
			&"village":
				map_labels.append(["VILLAGE", at])
			&"lake":
				map_labels.append(["LAKE" if north else "RESERVOIR", at])
	if has_police_station:
		map_labels.append(["POLICE", Vector2(police_station.origin.x, police_station.origin.z)])


## Paddy: field tiles in a grid with a farm track round them, palms along the edges, a farmhouse
## and haystacks in one corner.
func _fields(interior: Rect2) -> void:
	_lot(&"lot_paddy", interior)
	var inner: Rect2 = interior.grow(-4.0)
	var nx: int = int(inner.size.x / 20.0)
	var nz: int = int(inner.size.y / 20.0)
	var x0: float = inner.get_center().x - nx * 10.0
	var z0: float = inner.get_center().y - nz * 10.0
	for ix: int in nx:
		for iz: int in nz:
			if ix == 0 and iz == 0 and nx * nz > 4:
				continue                                     # the farmstead corner
			_place(&"prop_cs_paddy", Vector3(x0 + ix * 20.0 + 10.0, LOT_TOP, z0 + iz * 20.0 + 10.0), 0.0, Vector3.ONE, &"ground")
	if nx * nz > 4:
		_place(&"bld_cs_farmhouse", Vector3(x0 + 10.0, LOT_TOP, z0 + 8.0), 0.0, Vector3(1.0, 1.0, 0.9), &"building")
		_place(&"prop_cs_haystack", Vector3(x0 + 3.0, LOT_TOP, z0 + 17.0), 0.0, Vector3.ONE, &"prop")
		_place(&"prop_cs_haystack", Vector3(x0 + 17.0, LOT_TOP, z0 + 17.5), 0.0, Vector3.ONE, &"prop")
	var x: float = interior.position.x + 1.5
	while x < interior.end.x - 1.0:
		for z: float in [interior.position.y + 1.5, interior.end.y - 1.5]:
			if _rng.randf() < 0.45:
				_place(&"prop_palm_tree", Vector3(x, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
		x += 11.0


## Coconut grove: palms in loose rows.
func _grove(interior: Rect2) -> void:
	var x: float = interior.position.x + 5.0
	while x < interior.end.x - 4.0:
		var z: float = interior.position.y + 5.0
		while z < interior.end.y - 4.0:
			_place(&"prop_palm_tree", Vector3(x + _rng.randf_range(-1.5, 1.5), LOT_TOP, z + _rng.randf_range(-1.5, 1.5)),
				_rng.randf() * TAU, Vector3.ONE, &"prop")
			z += 12.0
		x += 12.0


## A lake with grassy banks, palms and benches looking over the water.
func _lake(interior: Rect2) -> void:
	var water_rect: Rect2 = interior.grow(-14.0)
	lakes.append(water_rect)
	var c: Vector2 = water_rect.get_center()
	for k: int in 4:
		var a: float = TAU * k / 4.0
		var dir := Vector2(cos(a), sin(a))
		var at := Vector3(c.x + dir.x * (water_rect.size.x * 0.5 + 7.0), LOT_TOP, c.y + dir.y * (water_rect.size.y * 0.5 + 7.0))
		_bench(at, atan2(-dir.x, -dir.y), &"prop")
	var x: float = interior.position.x + 4.0
	while x < interior.end.x - 3.0:
		for z: float in [interior.position.y + 4.0, interior.end.y - 4.0]:
			_place(&"prop_palm_tree", Vector3(x, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
		x += 14.0


## The village green in the middle: a shrine, the well, neem trees, haystacks.
func _village_green(green: Rect2) -> void:
	if green.size.x < 20.0 or green.size.y < 20.0:
		return
	var c: Vector2 = green.get_center()
	_place(&"bld_temple_shrine", Vector3(c.x, LOT_TOP, c.y - 6.0), 0.0, Vector3.ONE, &"building")
	_place(&"prop_cs_well", Vector3(c.x + 12.0, LOT_TOP, c.y + 6.0), 0.0, Vector3.ONE, &"prop")
	_benches_facing_in(Rect2(c - Vector2(16.0, 14.0), Vector2(32.0, 28.0)), 0.0, &"prop")
	for corner: Vector2 in [Vector2(0.15, 0.15), Vector2(0.85, 0.15), Vector2(0.15, 0.85), Vector2(0.85, 0.85)]:
		_place(&"prop_neem_tree", Vector3(green.position.x + green.size.x * corner.x, LOT_TOP, green.position.y + green.size.y * corner.y),
			_rng.randf() * TAU, Vector3.ONE, &"prop")
	_place(&"prop_cs_haystack", Vector3(c.x - 14.0, LOT_TOP, c.y + 10.0), 0.0, Vector3.ONE, &"prop")
	# Huts and trees scattered over the rest of the green, clear of the shrine and the well.
	var inner: Rect2 = green.grow(-6.0)
	for k: int in int(green.get_area() / 900.0):
		var at := Vector2(_rng.randf_range(inner.position.x, inner.end.x), _rng.randf_range(inner.position.y, inner.end.y))
		if at.distance_to(c) < 24.0:
			continue
		if _rng.randf() < 0.55:
			_place(&"bld_cs_hut", Vector3(at.x, LOT_TOP, at.y), _rng.randf() * TAU, Vector3.ONE, &"building")
		else:
			_place(&"prop_neem_tree" if _rng.randf() < 0.6 else &"prop_palm_tree", Vector3(at.x, LOT_TOP, at.y), _rng.randf() * TAU, Vector3.ONE, &"prop")
