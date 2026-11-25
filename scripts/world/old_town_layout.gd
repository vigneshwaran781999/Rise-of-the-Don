class_name OldTownLayout
extends DistrictLayout
## Old Town (GDD §2 district 3, milestone M3), the centre of Velanagar: a temple town on the
## 512 m square around the origin (x and z from -256 to 256; -Z is north).
## - the walled temple compound with four gopurams in the middle, ringed by a lane (Ring A),
## - main roads along the gopuram axes and on two rings at +-112 and +-184; lanes in between:
##   the tight streets,
## - blocks lined with shops on main roads and houses on lanes, a market square with a hall and
##   stalls, a temple tank, two small parks, the bus stand where the story starts, and the
##   special buildings of M6 (police station, tiffin stall, garage, clothes shop, the house).

const MAX_DEPTH: float = 12.0
## Half size of the temple tank model (bld_ot_tank, 30 x 30 m).
const TANK_HALF: float = 15.0
## The bus stand where New Game begins (base centre of the shelter).
const BUS_STAND := Vector3(97.0, LOT_TOP, 7.0)
## Props a special building may clear from in front of its door.
const CLEARABLE: Array[StringName] = [&"prop_streetlight", &"prop_bollard", &"prop_neem_tree", &"prop_palm_tree"]
## Special buildings (M6, see DistrictLayout._special_buildings). The police station is on Ring B;
## the tiffin stall faces the bus stand across the east gopuram road; the garage is further east
## on that road (cars drive in, so the lamp posts in front go); the clothes shop is on Ring B
## west; the house for sale is north of Ring B east.
const SPECIAL_BUILDINGS: Array = [
	[&"police_station", &"bld_ot_shop_04", Vector3(-40.0, 0.0, 115.0), &"bld_ot_police_station", 7.6],
	[&"tiffin", &"bld_ot_shop_04", Vector3(91.0, 0.0, -16.0), &"bld_ot_tiffin", 7.6],
	[&"garage", &"bld_ot_shop_04", Vector3(160.0, 0.0, -16.0), &"bld_ot_garage", 7.6, 6.0],
	[&"textiles", &"bld_ot_shop_02", Vector3(-58.0, 0.0, 127.0), &"bld_ot_textiles", 7.6],
	[&"house", &"bld_ot_house_05", Vector3(60.0, 0.0, 137.0), &"bld_ot_house_05", 7.6],
]
const SEED: int = 7031
## Street lines, the same on both axes: [position, class].
const LINES: Array = [
	[-232.0, LANE], [-184.0, MAIN], [-148.0, LANE], [-112.0, MAIN], [-80.0, LANE], [-48.0, LANE],
	[0.0, MAIN], [48.0, LANE], [80.0, LANE], [112.0, MAIN], [148.0, LANE], [184.0, MAIN], [232.0, LANE],
]
## Big blocks spanning several grid cells (the streets inside them don't exist): [kind, x0, x1, z0, z1].
const MERGED: Array = [
	[&"temple", -48.0, 48.0, -48.0, 48.0],
	[&"tank", 48.0, 112.0, 48.0, 112.0],
	[&"market", -112.0, -48.0, -112.0, -48.0],
]
## Grid cells that become small parks: [x0, x1, z0, z1] in line positions.
const PARKS: Array = [[-148.0, -112.0, 112.0, 148.0], [148.0, 184.0, -148.0, -112.0]]
## Buildings facing main roads: [kit, frontage width, depth, weight].
const MAIN_FRONT: Array = [
	[&"bld_ot_shop_02", 6.0, 12.0, 2.0], [&"bld_ot_shop_03", 8.0, 12.0, 2.0], [&"bld_ot_shop_04", 10.0, 12.0, 2.0],
	[&"bld_ot_lodge_01", 12.0, 12.0, 1.0], [&"bld_shophouse_01", 8.0, 12.0, 1.0], [&"bld_shophouse_02", 8.0, 12.0, 1.0],
	[&"bld_shophouse_03", 8.0, 12.0, 1.0], [&"bld_ot_shop_01", 6.0, 10.0, 1.5], [&"bld_ot_shop_06", 6.0, 10.0, 1.5],
	[&"bld_apartment_01", 16.0, 12.0, 0.4], [&"bld_apartment_02", 16.0, 12.0, 0.4],
]
## Buildings facing lanes.
const LANE_FRONT: Array = [
	[&"bld_ot_house_01", 6.0, 10.0, 2.0], [&"bld_ot_house_02", 6.0, 10.0, 2.0], [&"bld_ot_house_03", 8.0, 10.0, 2.0],
	[&"bld_ot_house_04", 8.0, 10.0, 2.0], [&"bld_ot_house_05", 10.0, 12.0, 1.0], [&"bld_ot_house_06", 6.0, 10.0, 2.0],
	[&"bld_ot_house_07", 8.0, 10.0, 2.0], [&"bld_ot_shop_05", 8.0, 10.0, 1.0], [&"bld_ot_shop_01", 6.0, 10.0, 1.0],
	[&"bld_ot_shop_06", 6.0, 10.0, 1.0],
]
const MAP_LABELS: Array = [
	["TEMPLE", Vector2(0.0, 0.0)], ["TEMPLE TANK", Vector2(80.0, 80.0)],
	["FLOWER MARKET", Vector2(-80.0, -80.0)], ["PARK", Vector2(-130.0, 130.0)],
	["PARK", Vector2(166.0, -130.0)], ["BUS STAND", Vector2(97.0, 14.0)],
]


func _init() -> void:
	id = &"old_town"
	display_name = "Old Town"


func _lines_x() -> Array:
	return LINES


func _lines_z() -> Array:
	return LINES


func _merged() -> Array:
	return MERGED


func _cell_kind(x0: float, z0: float) -> StringName:
	for p: Array in PARKS:
		if is_equal_approx(float(p[0]), x0) and is_equal_approx(float(p[2]), z0):
			return &"park"
	return &"standard"


func _seed() -> int:
	return SEED


## Signalized junctions get zebras on every arm; so do the main roads that end at the temple
## ring in front of each gopuram.
func _zebra(signalized: bool, arm_cls: int, crossing_line: float) -> bool:
	return signalized or (arm_cls == MAIN and is_equal_approx(absf(crossing_line), 48.0))


func _lot_kit(kind: StringName) -> StringName:
	return {&"temple": &"lot_stone", &"tank": &"lot_stone", &"market": &"lot_warm", &"park": &"lot_grass"}.get(kind, &"lot_paved")


func _fill_block(kind: StringName, _rect: Rect2, interior: Rect2, _walk: Array[float], cls: Array[int]) -> void:
	var ground: StringName = _lot_kit(kind)
	if kind != &"tank":
		_lot(ground, interior)
	match kind:
		&"temple":
			_temple()
		&"tank":
			var yard: Rect2 = _frontages(interior, [null, MAIN_FRONT, null, MAIN_FRONT], 10.0)
			_place(&"bld_ot_tank", Vector3(yard.get_center().x, LOT_TOP, yard.get_center().y), 0.0, Vector3.ONE, &"building")
			# Lot ground everywhere except over the sunken pond itself.
			var pond := Rect2(yard.get_center() - Vector2(TANK_HALF, TANK_HALF), Vector2(TANK_HALF, TANK_HALF) * 2.0)
			_lot(ground, Rect2(interior.position, Vector2(interior.size.x, pond.position.y - interior.position.y)))
			_lot(ground, Rect2(interior.position.x, pond.end.y, interior.size.x, interior.end.y - pond.end.y))
			_lot(ground, Rect2(interior.position.x, pond.position.y, pond.position.x - interior.position.x, pond.size.y))
			_lot(ground, Rect2(pond.end.x, pond.position.y, interior.end.x - pond.end.x, pond.size.y))
			for corner: Vector2 in [Vector2(0.06, 0.06), Vector2(0.94, 0.06), Vector2(0.06, 0.94), Vector2(0.94, 0.94)]:
				_place(&"prop_neem_tree", Vector3(yard.position.x + yard.size.x * corner.x, LOT_TOP,
					yard.position.y + yard.size.y * corner.y), _rng.randf() * TAU, Vector3.ONE, &"prop")
			_benches_facing_in(yard, 1.8, &"prop")
		&"market":
			var square: Rect2 = _frontages(interior, [MAIN_FRONT, null, MAIN_FRONT, null], MAX_DEPTH)
			_market(square)
		&"park":
			_park(interior)
		_:
			var sides: Array = []
			for c: int in cls:
				sides.append(null if c < 0 else (MAIN_FRONT if c == MAIN else LANE_FRONT))
			var yard: Rect2 = _frontages(interior, sides, MAX_DEPTH)
			if yard.size.x >= 7.0 and yard.size.y >= 7.0 and _rng.randf() < 0.75:
				_place(&"prop_neem_tree", Vector3(yard.get_center().x + _rng.randf_range(-1.5, 1.5), LOT_TOP,
					yard.get_center().y + _rng.randf_range(-1.5, 1.5)), _rng.randf() * TAU, Vector3.ONE, &"prop")


func _after_blocks() -> void:
	_bus_stand()
	_special_buildings(SPECIAL_BUILDINGS, CLEARABLE)
	map_labels = MAP_LABELS.duplicate()
	map_labels.append(["POLICE", Vector2(police_station.origin.x, police_station.origin.z)])


## The bus stand on the south kerb of the east gopuram road, where New Game begins (M5): the
## shelter opens towards the road, and its bench seats two waiting pedestrians.
func _bus_stand() -> void:
	var yaw: float = PI   # model's open side (+Z) faces -Z, the road
	_place(&"prop_bus_shelter", BUS_STAND, yaw, Vector3.ONE, &"prop")
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-0.6, 0.6]:
		# Seat top at 0.5 m, front edge 0.1 m behind the centre line.
		sit_spots.append({"xform": Transform3D(basis, BUS_STAND + basis * Vector3(side, -0.38, -0.18)), "kind": &"prop"})


func _market(square: Rect2) -> void:
	var cx: float = square.get_center().x
	_place(&"bld_ot_market_hall", Vector3(cx, LOT_TOP, square.position.y + 9.0), 0.0, Vector3.ONE, &"building")
	var row_z: Array[float] = [square.position.y + 22.0, square.position.y + 27.0]
	var x: float = square.position.x + 4.0
	var k: int = 0
	while x < square.end.x - 3.0:
		for r: int in 2:
			_place(&"prop_market_stall_a" if (k + r) % 2 == 0 else &"prop_market_stall_b",
				Vector3(x, LOT_TOP, row_z[r]), 0.0 if r == 0 else PI, Vector3.ONE, &"prop")
		x += 3.4
		k += 1
	for z: float in [square.position.y + 6.0, square.position.y + 11.0]:
		_place(&"prop_flower_stall", Vector3(square.end.x - 2.0, LOT_TOP, z), PI * 0.5, Vector3.ONE, &"prop")
	_place(&"prop_handcart", Vector3(square.end.x - 2.5, LOT_TOP, square.position.y + 31.0), 0.4, Vector3.ONE, &"prop")
	_place(&"prop_handcart", Vector3(square.position.x + 3.0, LOT_TOP, square.end.y - 2.5), -1.2, Vector3.ONE, &"prop")
	for bench_x: float in [square.position.x + 10.0, square.position.x + 20.0]:
		_bench(Vector3(bench_x, LOT_TOP, square.end.y - 2.0), PI, &"prop")


## The temple compound (always loaded as the skyline landmark): walls, four gopurams, the
## central shrine with its pillared hall, trees, flower stalls by the gates, bollards.
func _temple() -> void:
	var wall_half: float = 36.0
	var c: float = -34.0
	while c <= 34.0:
		if absf(c) >= 9.5:
			_place(&"prop_temple_wall", Vector3(c, LOT_TOP, -wall_half), 0.0, Vector3.ONE, &"landmark")
			_place(&"prop_temple_wall", Vector3(c, LOT_TOP, wall_half), 0.0, Vector3.ONE, &"landmark")
			_place(&"prop_temple_wall", Vector3(-wall_half, LOT_TOP, c), PI * 0.5, Vector3.ONE, &"landmark")
			_place(&"prop_temple_wall", Vector3(wall_half, LOT_TOP, c), PI * 0.5, Vector3.ONE, &"landmark")
		c += 4.0
	for arm: int in 4:
		var out: Vector3 = ARM_DIRS[arm]
		var yaw: float = atan2(out.x, out.z)
		_place(&"bld_temple_gopuram", out * wall_half + Vector3.UP * LOT_TOP, yaw, Vector3.ONE, &"landmark")
		var side := Vector3(-out.z, 0.0, out.x)
		for s: float in [-11.0, 11.0]:
			_place(&"prop_flower_stall", out * 39.5 + side * s + Vector3.UP * LOT_TOP, yaw, Vector3.ONE, &"landmark")
		var b: float = -6.0
		while b <= 6.01:
			_place(&"prop_bollard", out * 43.4 + side * b + Vector3.UP * LOT_TOP, 0.0, Vector3.ONE, &"landmark")
			b += 2.0
	_place(&"bld_ot_vimana", Vector3(-4.0, LOT_TOP, 0.0), PI * 0.5, Vector3.ONE, &"landmark")
	_place(&"bld_ot_mandapam", Vector3(12.0, LOT_TOP, 0.0), PI * 0.5, Vector3.ONE, &"landmark")
	for p: Vector2 in [Vector2(-28, -28), Vector2(28, -28), Vector2(-28, 28), Vector2(28, 28)]:
		_place(&"prop_palm_tree", Vector3(p.x, LOT_TOP, p.y), _rng.randf() * TAU, Vector3.ONE, &"landmark")
	for p: Vector2 in [Vector2(-18, -22), Vector2(18, -22), Vector2(-18, 22), Vector2(18, 22)]:
		_place(&"prop_neem_tree", Vector3(p.x, LOT_TOP, p.y), _rng.randf() * TAU, Vector3.ONE, &"landmark")
	# Benches along the inside of the walls, between the gopurams, facing the shrine.
	for s: float in [-10.0, 10.0]:
		_bench(Vector3(s, LOT_TOP, -31.5), 0.0, &"landmark")
		_bench(Vector3(s, LOT_TOP, 31.5), PI, &"landmark")
		_bench(Vector3(-31.5, LOT_TOP, s), PI * 0.5, &"landmark")
		_bench(Vector3(31.5, LOT_TOP, s), -PI * 0.5, &"landmark")


# --------------------------------------------------------------------------- signals, crossings
