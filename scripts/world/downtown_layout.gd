class_name DowntownLayout
extends DistrictLayout
## Downtown (GDD §2 district 1, M7): Velanagar's business district, the cell north of Old Town
## (centre at z = -512). Glass towers, offices, hotels and a mall on big blocks between busy main
## roads, neon at night.
## - All thirteen of Old Town's north-south streets carry on across the border for one block, to
##   the main road at z = -304; north of it the side lanes stop, leaving wide blocks for towers.
## - Main roads run east-west at z = -656, -512, -432 and -304; lanes at -720, -592 and -368.
## - Central Plaza (a fountain, palms and benches) and Vela Mall sit on merged blocks either side
##   of the north road; the police headquarters is on the central road, west of the plaza.
## - Along the northern edge of the city, one long row of buildings backs onto the boundary.

const SEED: int = 4417
const MAX_DEPTH: float = 24.0
## North-south streets (x), the same lines as Old Town's so its streets carry on.
const LINES_X: Array = [
	[-232.0, LANE], [-184.0, MAIN], [-148.0, LANE], [-112.0, MAIN], [-80.0, LANE], [-48.0, LANE],
	[0.0, MAIN], [48.0, LANE], [80.0, LANE], [112.0, MAIN], [148.0, LANE], [184.0, MAIN], [232.0, LANE],
]
## East-west streets (z relative to the centre at -512), north to south.
const LINES_Z: Array = [
	[-208.0, LANE], [-144.0, MAIN], [-80.0, LANE], [0.0, MAIN], [80.0, MAIN], [144.0, LANE], [208.0, MAIN],
]
## Where the side lanes (x = +-148, +-80) are dropped north of the first main road: the wide blocks.
const WIDE_COLUMNS: Array = [[-184.0, -112.0], [-112.0, -48.0], [48.0, 112.0], [112.0, 184.0]]
const WIDE_ROWS: Array = [[-208.0, -144.0], [-144.0, -80.0], [-80.0, 0.0], [0.0, 80.0], [80.0, 144.0], [144.0, 208.0]]
const PLAZA: Array = [&"plaza", -112.0, -48.0, -80.0, 0.0]
const MALL: Array = [&"mall", 48.0, 112.0, 0.0, 80.0]
## The row along the north edge of the city.
const NORTH_ROW: Array = [&"standard", -256.0, 256.0, -256.0, -208.0]
## Buildings facing main roads: [kit, frontage width, depth, weight].
const MAIN_FRONT: Array = [
	[&"bld_dt_tower_a", 20.0, 20.0, 1.0], [&"bld_dt_tower_b", 24.0, 20.0, 0.35], [&"bld_dt_tower_c", 18.0, 18.0, 0.9],
	[&"bld_dt_office_a", 16.0, 16.0, 1.4], [&"bld_dt_hotel", 24.0, 18.0, 0.35], [&"bld_dt_office_b", 12.0, 14.0, 1.0],
	[&"bld_dt_retail_a", 12.0, 14.0, 0.8], [&"bld_dt_retail_b", 12.0, 14.0, 0.8],
]
## Buildings facing lanes.
const LANE_FRONT: Array = [
	[&"bld_dt_office_b", 12.0, 14.0, 2.0], [&"bld_dt_retail_a", 12.0, 14.0, 1.0], [&"bld_dt_retail_b", 12.0, 14.0, 1.0],
	[&"bld_dt_office_a", 16.0, 16.0, 1.0], [&"bld_dt_tower_c", 18.0, 18.0, 0.5],
]
## The police headquarters takes the place of the mid-rise office nearest this point, just west
## of Central Plaza (door spot 9.6 m in front of its centre: half its depth plus the sidewalk); the
## hospital (M7) takes the one nearest a point east of the plaza.
const SPECIAL_BUILDINGS: Array = [
	[&"police_downtown", &"bld_dt_office_a", Vector3(-130.0, 0.0, 40.0), &"bld_dt_police", 9.6],
	[&"hospital_downtown", &"bld_dt_office_a", Vector3(130.0, 0.0, -40.0), &"bld_dt_hospital", 9.6],
]
const CLEARABLE: Array[StringName] = [&"prop_streetlight", &"prop_neem_tree", &"prop_palm_tree"]

var _merged_cache: Array = []


func _init() -> void:
	id = &"downtown"
	display_name = "Downtown"


func _lines_x() -> Array:
	return LINES_X


func _lines_z() -> Array:
	return LINES_Z


func _merged() -> Array:
	if _merged_cache.is_empty():
		_merged_cache.append(NORTH_ROW)
		_merged_cache.append(PLAZA)
		_merged_cache.append(MALL)
		for col: Array in WIDE_COLUMNS:
			for row: Array in WIDE_ROWS:
				var taken: bool = false
				for special: Array in [PLAZA, MALL]:
					if is_equal_approx(float(special[1]), float(col[0])) and is_equal_approx(float(special[3]), float(row[0])):
						taken = true
				if not taken:
					_merged_cache.append([&"standard", col[0], col[1], row[0], row[1]])
	return _merged_cache


func _seed() -> int:
	return SEED


func _lot_kit(_kind: StringName) -> StringName:
	return &"lot_plaza"


func _catalogue(cls: int) -> Array:
	return MAIN_FRONT if cls == MAIN else LANE_FRONT


func _max_depth() -> float:
	return MAX_DEPTH


func _fill_block(kind: StringName, rect: Rect2, interior: Rect2, walk: Array[float], cls: Array[int]) -> void:
	match kind:
		&"plaza":
			_lot(&"lot_plaza", interior)
			_plaza(interior)
		&"mall":
			_lot(&"lot_plaza", interior)
			# The mall faces the main road on the north side; its canopy reaches 7 m out front.
			_place(&"bld_dt_mall", Vector3(interior.get_center().x, LOT_TOP, interior.position.y + 7.5 + 24.0), PI,
				Vector3.ONE, &"building")
			for x: float in [interior.position.x + 2.5, interior.end.x - 2.5]:
				var z: float = interior.position.y + 4.0
				while z < interior.end.y - 2.0:
					_place(&"prop_palm_tree", Vector3(x, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
					z += 9.0
		_:
			super._fill_block(kind, rect, interior, walk, cls)


func _fill_yard(_kind: StringName, yard: Rect2) -> void:
	if yard.size.x >= 8.0 and yard.size.y >= 8.0:
		_place(&"prop_neem_tree", Vector3(yard.get_center().x + _rng.randf_range(-2.0, 2.0), LOT_TOP,
			yard.get_center().y + _rng.randf_range(-2.0, 2.0)), _rng.randf() * TAU, Vector3.ONE, &"prop")


func _after_blocks() -> void:
	_special_buildings(SPECIAL_BUILDINGS, CLEARABLE)
	var plaza: Vector2 = centre + Vector2((float(PLAZA[1]) + float(PLAZA[2])) * 0.5, (float(PLAZA[3]) + float(PLAZA[4])) * 0.5)
	var mall: Vector2 = centre + Vector2((float(MALL[1]) + float(MALL[2])) * 0.5, (float(MALL[3]) + float(MALL[4])) * 0.5)
	map_labels = [["CENTRAL PLAZA", plaza], ["VELA MALL", mall]]
	if has_police_station:
		map_labels.append(["POLICE HQ", Vector2(police_station.origin.x, police_station.origin.z)])
	for hospital: Transform3D in hospitals:
		map_labels.append(["HOSPITAL", Vector2(hospital.origin.x, hospital.origin.z)])


## Central Plaza: paving, the fountain in the middle, a ring of palms, benches facing it and
## neem trees in the corners.
func _plaza(interior: Rect2) -> void:
	var c: Vector2 = interior.get_center()
	_place(&"prop_dt_fountain", Vector3(c.x, LOT_TOP, c.y), 0.0, Vector3.ONE, &"prop")
	for k: int in 8:
		var a: float = TAU * k / 8.0
		_place(&"prop_palm_tree", Vector3(c.x + cos(a) * 13.0, LOT_TOP, c.y + sin(a) * 13.0), _rng.randf() * TAU, Vector3.ONE, &"prop")
	for k: int in 4:
		var a: float = TAU * k / 4.0 + PI * 0.25
		var at := Vector3(c.x + cos(a) * 7.5, LOT_TOP, c.y + sin(a) * 7.5)
		_bench(at, atan2(c.x - at.x, c.y - at.z), &"prop")
	for corner: Vector2 in [Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
		_place(&"prop_neem_tree", Vector3(interior.position.x + interior.size.x * corner.x, LOT_TOP,
			interior.position.y + interior.size.y * corner.y), _rng.randf() * TAU, Vector3.ONE, &"prop")
