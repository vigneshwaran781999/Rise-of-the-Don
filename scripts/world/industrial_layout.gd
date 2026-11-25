class_name IndustrialLayout
extends DistrictLayout
## The Industrial Zone (GDD §2 district 4, M7): factories, warehouses and the harbour, the cell
## north of the Beach and east of Downtown (centre at x = 512, z = -512). Grey and rust by day,
## sodium orange at night.
## - Downtown's east-west streets and the Beach's north-south roads carry on into it. Beyond the
##   first block the side lanes stop, leaving big yards for warehouses, the factory and tank farms.
## - The Coast Road carries on north as the harbour road. East of it: the quay, with the container
##   yard, three gantry cranes at the berth where a cargo ship is moored, and the fishing harbour
##   (a fish-market shed and boats) at the south end. The sea begins at SHORE, as on the Beach.

const SEED: int = 6271
const MAX_DEPTH: float = 26.0
const HARBOUR_ROAD: float = 16.0
const SHORE: float = BeachLayout.SHORE
const BARRIER: float = BeachLayout.BARRIER
const LINES_X: Array = [[-208.0, MAIN], [-136.0, LANE], [-64.0, MAIN], [HARBOUR_ROAD, MAIN]]
## East-west streets: Downtown's, so they all carry on across the border.
const LINES_Z: Array = [
	[-208.0, LANE], [-144.0, MAIN], [-80.0, LANE], [0.0, MAIN], [80.0, MAIN], [144.0, LANE], [208.0, MAIN],
]
const HARBOUR: Array = [&"harbour", HARBOUR_ROAD, 256.0, -256.0, 256.0]
## East of the first north-south road, the lanes at z = -208, -80 and 144 stop.
const WIDE_COLUMNS: Array = [[-208.0, -136.0], [-136.0, -64.0], [-64.0, HARBOUR_ROAD]]
const WIDE_ROWS: Array = [[-256.0, -144.0], [-144.0, 0.0], [80.0, 208.0]]
## The berth: where the cranes stand and the ship lies (z relative to the centre).
const BERTH_Z: Array[float] = [-150.0, -95.0, -40.0]
const SHIP_Z: float = -95.0
## Buildings facing main roads: [kit, frontage width, depth, weight].
const MAIN_FRONT: Array = [
	[&"bld_in_warehouse_a", 30.0, 20.0, 1.4], [&"bld_in_warehouse_b", 24.0, 16.0, 1.2], [&"bld_in_factory", 36.0, 24.0, 0.6],
	[&"bld_in_office", 10.0, 12.0, 1.0], [&"bld_in_tanks", 24.0, 12.0, 0.6],
]
## Buildings facing lanes.
const LANE_FRONT: Array = [
	[&"bld_in_warehouse_b", 24.0, 16.0, 1.4], [&"bld_in_office", 10.0, 12.0, 1.2], [&"bld_in_tanks", 24.0, 12.0, 0.8],
]
const CONTAINERS: Array[StringName] = [&"prop_in_container_a", &"prop_in_container_b", &"prop_in_container_c"]
const CONTAINER_HEIGHT: float = 2.6
## The police post takes the place of the site office nearest this point.
const SPECIAL_BUILDINGS: Array = [
	[&"police_industrial", &"bld_in_office", Vector3(-180.0, 0.0, 40.0), &"bld_in_police", 7.6],
]
const CLEARABLE: Array[StringName] = [&"prop_streetlight_sodium"]

var _merged_cache: Array = []


func _init() -> void:
	id = &"industrial"
	display_name = "Industrial Zone"


func _lines_x() -> Array:
	return LINES_X


func _lines_z() -> Array:
	return LINES_Z


func _merged() -> Array:
	if _merged_cache.is_empty():
		_merged_cache.append(HARBOUR)
		for col: Array in WIDE_COLUMNS:
			for row: Array in WIDE_ROWS:
				_merged_cache.append([&"standard", col[0], col[1], row[0], row[1]])
	return _merged_cache


func _seed() -> int:
	return SEED


func _lot_kit(_kind: StringName) -> StringName:
	return &"lot_concrete"


func _catalogue(cls: int) -> Array:
	return MAIN_FRONT if cls == MAIN else LANE_FRONT


func _max_depth() -> float:
	return MAX_DEPTH


func _streetlight_kit() -> StringName:
	return &"prop_streetlight_sodium"


func _fill_block(kind: StringName, rect: Rect2, interior: Rect2, walk: Array[float], cls: Array[int]) -> void:
	if kind == &"harbour":
		_harbour(interior)
	else:
		super._fill_block(kind, rect, interior, walk, cls)


## A yard: a few container stacks if there's room, otherwise nothing.
func _fill_yard(_kind: StringName, yard: Rect2) -> void:
	if yard.size.x < 16.0 or yard.size.y < 8.0:
		return
	var rows: int = mini(4, int((yard.size.y - 2.0) / 3.0))
	for r: int in rows:
		if _rng.randf() < 0.3:
			continue
		var at := Vector3(yard.get_center().x, LOT_TOP, yard.position.y + 2.5 + r * 3.0)
		_stack(at, 0.0, 1 + _rng.randi() % 2)


func _after_blocks() -> void:
	_special_buildings(SPECIAL_BUILDINGS, CLEARABLE)
	var shore: float = centre.x + SHORE
	water.append(Rect2(shore, centre.y - HALF, centre.x + HALF - shore, 2.0 * HALF))
	barriers.append(Rect2(centre.x + BARRIER, centre.y - HALF, 1.0, 2.0 * HALF))
	map_labels = [
		["HARBOUR", centre + Vector2(SHORE - 30.0, SHIP_Z)], ["CONTAINER YARD", centre + Vector2(68.0, 10.0)],
		["FISHING HARBOUR", centre + Vector2(70.0, 205.0)],
	]
	for p: Dictionary in placements:
		if p["kit"] == &"bld_in_factory":
			var o: Vector3 = (p["xform"] as Transform3D).origin
			map_labels.append(["FACTORY", Vector2(o.x, o.z)])
	if has_police_station:
		map_labels.append(["POLICE", Vector2(police_station.origin.x, police_station.origin.z)])


## A stack of 1-4 containers (random colours), long side along `yaw`.
func _stack(at: Vector3, yaw: float, height: int) -> void:
	for level: int in height:
		_place(CONTAINERS[_rng.randi() % CONTAINERS.size()], at + Vector3.UP * (CONTAINER_HEIGHT * level), yaw, Vector3.ONE, &"prop")


## The quay east of the harbour road: container yard, cranes at the berth with a ship alongside,
## and the fishing harbour at the south end.
func _harbour(interior: Rect2) -> void:
	var shore: float = centre.x + SHORE
	_lot(&"lot_concrete", Rect2(interior.position, Vector2(shore - interior.position.x, interior.size.y)))
	# Container yard: blocks of stacks with aisles between, from the north end to past the middle.
	var z: float = interior.position.y + 8.0
	var row: int = 0
	while z < centre.y + 60.0:
		if row % 7 != 6:                                     # every seventh row is an aisle
			for col_x: float in [interior.position.x + 16.0, interior.position.x + 30.0, interior.position.x + 44.0, interior.position.x + 58.0]:
				if _rng.randf() < 0.8:
					_stack(Vector3(col_x, LOT_TOP, z), 0.0, 1 + _rng.randi() % 3)
		z += 3.0
		row += 1
	# Cranes on the quay edge at the berth, booms out over the ship (always in view: landmarks).
	for bz: float in BERTH_Z:
		_place(&"bld_in_crane", Vector3(shore - 9.0, LOT_TOP, centre.y + bz), PI * 0.5, Vector3.ONE, &"landmark")
	_place(&"bld_in_ship", Vector3(shore + 13.0, -0.6, centre.y + SHIP_Z), PI, Vector3.ONE, &"building")
	# Fishing harbour: the market shed, boats moored along the quay, nets of boxes (containers' cousins).
	_place(&"bld_in_fish_shed", Vector3(interior.position.x + 40.0, LOT_TOP, centre.y + 205.0), PI * 0.5, Vector3.ONE, &"building")
	for k: int in 9:
		_place(&"prop_bh_boat", Vector3(shore + 3.5 + _rng.randf_range(-0.5, 0.5), 0.05, centre.y + 160.0 + k * 9.0),
			PI * 0.5 + _rng.randf_range(-0.15, 0.15), Vector3.ONE, &"prop")
	for k: int in 3:
		_bench(Vector3(shore - 4.0, LOT_TOP, centre.y + 175.0 + k * 25.0), -PI * 0.5, &"prop")
