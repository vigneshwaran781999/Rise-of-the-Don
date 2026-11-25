class_name BeachLayout
extends DistrictLayout
## The Beach District (GDD §2 district 2, M7): the seafront, the cell east of Old Town (centre at
## x = 512). Warm, low and colourful, facing the sea.
## - All thirteen of Old Town's east-west streets carry on across the border to Beach Road (the
##   first main road); the main roads and the lanes beside the temple axis go on to the coast.
## - The Coast Road runs north-south 16 m east of the centre, lined with seafood restaurants,
##   small hotels and beach shops; two Sea Breeze resorts face it across the road from the sand.
## - East of it: the promenade (palms, benches, kiosks), then the beach (umbrellas, fishing
##   boats, lifeguard towers), the pier, and the lighthouse at the south end. The sea begins at
##   SHORE; you can wade out to BARRIER.
## - Cottages and pastel houses on the lanes; a police post.

const SEED: int = 5309
const MAX_DEPTH: float = 16.0
## Distances east of the centre: the Coast Road, the water's edge, and how far out you can wade.
const COAST_ROAD: float = 16.0
const SHORE: float = 120.0
const BARRIER: float = 160.0
const PIER_Z: float = 60.0
const LIGHTHOUSE := Vector2(110.0, 228.0)
## Height of the lighthouse lamp above its base (bld_bh_lighthouse).
const LAMP_HEIGHT: float = 29.2
const LINES_X: Array = [[-208.0, MAIN], [-136.0, LANE], [-64.0, MAIN], [COAST_ROAD, MAIN]]
## East-west streets: Old Town's, so they all carry on across the border.
const LINES_Z: Array = [
	[-232.0, LANE], [-184.0, MAIN], [-148.0, LANE], [-112.0, MAIN], [-80.0, LANE], [-48.0, LANE],
	[0.0, MAIN], [48.0, LANE], [80.0, LANE], [112.0, MAIN], [148.0, LANE], [184.0, MAIN], [232.0, LANE],
]
const BEACH: Array = [&"beach", COAST_ROAD, 256.0, -256.0, 256.0]
const RESORTS: Array = [[&"resort", -64.0, 16.0, -112.0, -48.0], [&"resort", -64.0, 16.0, 48.0, 112.0]]
## East of Beach Road the lanes at z = +-232, +-148 and +-80 stop, leaving bigger blocks.
const WIDE_COLUMNS: Array = [[-208.0, -136.0], [-136.0, -64.0], [-64.0, 16.0]]
const WIDE_ROWS: Array = [[-256.0, -184.0], [-184.0, -112.0], [-112.0, -48.0], [48.0, 112.0], [112.0, 184.0], [184.0, 256.0]]
## Buildings facing main roads: [kit, frontage width, depth, weight].
const MAIN_FRONT: Array = [
	[&"bld_bh_seafood", 12.0, 12.0, 1.4], [&"bld_bh_hotel", 20.0, 14.0, 0.7], [&"bld_bh_shop_a", 8.0, 10.0, 1.2],
	[&"bld_bh_shop_b", 8.0, 10.0, 1.2], [&"bld_ot_shop_03", 8.0, 12.0, 0.5], [&"bld_ot_lodge_01", 12.0, 12.0, 0.4],
]
## Buildings facing lanes.
const LANE_FRONT: Array = [
	[&"bld_bh_cottage", 8.0, 10.0, 2.2], [&"bld_ot_house_01", 6.0, 10.0, 1.0], [&"bld_ot_house_03", 8.0, 10.0, 1.0],
	[&"bld_ot_house_06", 6.0, 10.0, 1.0], [&"bld_bh_shop_a", 8.0, 10.0, 0.6],
]
## Buildings facing the Coast Road (looking out to sea).
const COAST_FRONT: Array = [
	[&"bld_bh_seafood", 12.0, 12.0, 2.0], [&"bld_bh_hotel", 20.0, 14.0, 1.0], [&"bld_bh_shop_a", 8.0, 10.0, 1.0],
	[&"bld_bh_shop_b", 8.0, 10.0, 1.0],
]
## The police post takes the place of the seafood restaurant nearest this point, on the
## main road south of the northern resort.
const SPECIAL_BUILDINGS: Array = [
	[&"police_beach", &"bld_bh_seafood", Vector3(-100.0, 0.0, -118.0), &"bld_bh_police", 7.6],
]
const CLEARABLE: Array[StringName] = [&"prop_streetlight", &"prop_neem_tree", &"prop_palm_tree"]

var _merged_cache: Array = []


func _init() -> void:
	id = &"beach"
	display_name = "Beach District"


func _lines_x() -> Array:
	return LINES_X


func _lines_z() -> Array:
	return LINES_Z


func _merged() -> Array:
	if _merged_cache.is_empty():
		_merged_cache.append(BEACH)
		_merged_cache.append_array(RESORTS)
		for col: Array in WIDE_COLUMNS:
			for row: Array in WIDE_ROWS:
				var taken: bool = false
				for r: Array in RESORTS:
					if is_equal_approx(float(r[1]), float(col[0])) and is_equal_approx(float(r[3]), float(row[0])):
						taken = true
				if not taken:
					_merged_cache.append([&"standard", col[0], col[1], row[0], row[1]])
	return _merged_cache


func _seed() -> int:
	return SEED


func _lot_kit(kind: StringName) -> StringName:
	return &"lot_sand" if kind == &"beach" else &"lot_paved"


func _catalogue(cls: int) -> Array:
	return MAIN_FRONT if cls == MAIN else LANE_FRONT


func _max_depth() -> float:
	return MAX_DEPTH


func _fill_block(kind: StringName, rect: Rect2, interior: Rect2, walk: Array[float], cls: Array[int]) -> void:
	match kind:
		&"beach":
			_beach(interior)
		&"resort":
			_lot(&"lot_paved", interior)
			_resort(interior)
		_:
			_lot(&"lot_paved", interior)
			var sides: Array = []
			for k: int in 4:
				var c: int = cls[k]
				sides.append(null if c < 0 else _catalogue(c))
			# The side facing the Coast Road gets the seafront catalogue.
			if is_equal_approx(rect.end.x + ROAD_HALF[MAIN], centre.x + COAST_ROAD):
				sides[1] = COAST_FRONT
			var yard: Rect2 = _frontages(interior, sides, _max_depth())
			if yard.size.x >= 7.0 and yard.size.y >= 7.0 and _rng.randf() < 0.8:
				_place(&"prop_palm_tree", Vector3(yard.get_center().x + _rng.randf_range(-1.5, 1.5), LOT_TOP,
					yard.get_center().y + _rng.randf_range(-1.5, 1.5)), _rng.randf() * TAU, Vector3.ONE, &"prop")


func _after_blocks() -> void:
	_special_buildings(SPECIAL_BUILDINGS, CLEARABLE)
	var shore: float = centre.x + SHORE
	water.append(Rect2(shore, centre.y - HALF, centre.x + HALF - shore, 2.0 * HALF))
	barriers.append(Rect2(centre.x + BARRIER, centre.y - HALF, 1.0, 2.0 * HALF))
	map_labels = [
		["VELA BEACH", centre + Vector2(78.0, -20.0)], ["PIER", centre + Vector2(120.0, PIER_Z + 8.0)],
		["LIGHTHOUSE", centre + LIGHTHOUSE + Vector2(0.0, -12.0)],
	]
	for r: Array in RESORTS:
		map_labels.append(["SEA BREEZE", centre + Vector2((float(r[1]) + float(r[2])) * 0.5, (float(r[3]) + float(r[4])) * 0.5)])
	if has_police_station:
		map_labels.append(["POLICE", Vector2(police_station.origin.x, police_station.origin.z)])


## A Sea Breeze resort facing the Coast Road (east), its pool behind, palms around.
func _resort(interior: Rect2) -> void:
	# Its front (canopy 4 m out) at the east side of the block; the pool reaches 25 m behind.
	var x: float = interior.end.x - 4.0 - 11.0
	_place(&"bld_bh_resort", Vector3(x, LOT_TOP, interior.get_center().y), PI * 0.5, Vector3.ONE, &"building")
	for z: float in [interior.position.y + 3.0, interior.end.y - 3.0]:
		var px: float = interior.position.x + 4.0
		while px < interior.end.x - 3.0:
			_place(&"prop_palm_tree", Vector3(px, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
			px += 10.0


## The seafront east of the Coast Road: promenade, sand, the pier and the lighthouse.
func _beach(interior: Rect2) -> void:
	var x0: float = interior.position.x                  # inner edge of the promenade
	var shore: float = centre.x + SHORE
	_lot(&"lot_plaza", Rect2(x0, interior.position.y, 8.0, interior.size.y))
	_lot(&"lot_sand", Rect2(x0 + 8.0, interior.position.y, shore - x0 - 8.0, interior.size.y))
	var pier_z: float = centre.y + PIER_Z
	var lighthouse := Vector2(centre.x + LIGHTHOUSE.x, centre.y + LIGHTHOUSE.y)
	var near_pier := func(z: float, margin: float) -> bool: return absf(z - pier_z) < margin
	# Promenade: palms, benches looking out to sea, kiosks on the sand's edge.
	var z: float = interior.position.y + 6.0
	var k: int = 0
	while z < interior.end.y - 4.0:
		if not near_pier.call(z, 6.0):
			_place(&"prop_palm_tree", Vector3(x0 + 2.0, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
			if k % 3 == 1:
				_bench(Vector3(x0 + 5.5, LOT_TOP, z + 6.0), PI * 0.5, &"prop")
			if k % 6 == 3:
				_place(&"prop_bh_kiosk", Vector3(x0 + 14.0, LOT_TOP, z), PI * 0.5, Vector3.ONE, &"prop")
		z += 12.0
		k += 1
	# Umbrellas in three loose rows, all looking out to sea.
	for row_x: float in [x0 + 36.0, x0 + 50.0, x0 + 64.0]:
		z = interior.position.y + 10.0
		while z < interior.end.y - 10.0:
			var at := Vector3(row_x + _rng.randf_range(-2.0, 2.0), LOT_TOP, z + _rng.randf_range(-2.5, 2.5))
			if not near_pier.call(at.z, 10.0) and Vector2(at.x, at.z).distance_to(lighthouse) > 26.0 and _rng.randf() < 0.8:
				_place(&"prop_bh_umbrella", at, PI * 0.5 + _rng.randf_range(-0.25, 0.25), Vector3.ONE, &"prop")
			z += 15.0
	# Fishing boats drawn up near the water, bows to the sea, in a few groups.
	for group_z: float in [-205.0, -150.0, -40.0, 15.0, 130.0, 175.0]:
		for n: int in 3:
			var at := Vector3(shore - 10.0 + _rng.randf_range(-3.0, 3.0), LOT_TOP, centre.y + group_z + n * 5.5 + _rng.randf_range(-1.0, 1.0))
			_place(&"prop_bh_boat", at, PI * 0.5 + _rng.randf_range(-0.3, 0.3), Vector3.ONE, &"prop")
	for lz: float in [-170.0, -5.0, 150.0]:
		_place(&"prop_bh_lifeguard", Vector3(shore - 18.0, LOT_TOP, centre.y + lz), PI * 0.5, Vector3.ONE, &"prop")
	# The pier runs out to sea from the sand (its ramp starts 34 m short of the water).
	_place(&"bld_bh_pier", Vector3(shore - 4.0, LOT_TOP, pier_z), -PI * 0.5, Vector3.ONE, &"building")
	# The lighthouse at the south end, half on the sand, half in the water; always in view.
	_place(&"bld_bh_lighthouse", Vector3(lighthouse.x, LOT_TOP, lighthouse.y), 0.0, Vector3.ONE, &"landmark")
	beams.append(Vector3(lighthouse.x, LOT_TOP + LAMP_HEIGHT, lighthouse.y))
