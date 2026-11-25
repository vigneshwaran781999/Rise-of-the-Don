class_name LuxuryLayout
extends DistrictLayout
## The Luxury District (GDD §2 district 5, M7): villas and the estate, the cell west of Downtown
## (centre at x = -512, z = -512). Clean, quiet, guarded.
## - Downtown's east-west streets carry on into it. Two main roads run north-south and carry on
##   south into the Countryside; the side lanes between them stop short of both edges.
## - Every street is lined with walled villa plots (each model is a whole plot: wall and gate,
##   lawn, house, pool), with green verges between them.
## - The estate (a walled mansion with a gatehouse and a fountain court) on a merged block in the
##   middle, and Sandalwood Park beside it. No police station: the district has its own guards.

const SEED: int = 8123
const MAX_DEPTH: float = 26.0
const LINES_X: Array = [[-176.0, LANE], [-112.0, MAIN], [-40.0, LANE], [40.0, LANE], [128.0, MAIN], [200.0, LANE]]
## East-west streets: Downtown's, so they carry on across the border.
const LINES_Z: Array = [
	[-208.0, LANE], [-144.0, MAIN], [-80.0, LANE], [0.0, MAIN], [80.0, MAIN], [144.0, LANE], [208.0, MAIN],
]
## Along the north edge of the city: one long row of plots.
const NORTH_ROW: Array = [&"standard", -256.0, 256.0, -256.0, -208.0]
## Along the south edge the lanes stop, so only the two main roads carry on into the Countryside.
const SOUTH_ROW: Array = [
	[&"standard", -256.0, -112.0, 208.0, 256.0], [&"standard", -112.0, 128.0, 208.0, 256.0], [&"standard", 128.0, 256.0, 208.0, 256.0],
]
const ESTATE: Array = [&"estate", -40.0, 40.0, -80.0, 0.0]
const PARK: Array = [&"park", 40.0, 128.0, 0.0, 80.0]
## Walled villa plots: [kit, frontage width, depth, weight].
const PLOTS: Array = [
	[&"bld_lx_villa_a", 28.0, 24.0, 1.0], [&"bld_lx_villa_b", 28.0, 24.0, 1.0], [&"bld_lx_villa_c", 28.0, 24.0, 1.0],
]


func _init() -> void:
	id = &"luxury"
	display_name = "Luxury District"


func _lines_x() -> Array:
	return LINES_X


func _lines_z() -> Array:
	return LINES_Z


func _merged() -> Array:
	var out: Array = [NORTH_ROW, ESTATE, PARK]
	out.append_array(SOUTH_ROW)
	return out


func _seed() -> int:
	return SEED


func _lot_kit(_kind: StringName) -> StringName:
	return &"lot_grass"


func _catalogue(_cls: int) -> Array:
	return PLOTS


func _max_depth() -> float:
	return MAX_DEPTH


func _fill_block(kind: StringName, rect: Rect2, interior: Rect2, walk: Array[float], cls: Array[int]) -> void:
	match kind:
		&"estate":
			_lot(&"lot_grass", interior)
			# The estate faces the main road to the south (its gate on that side).
			_place(&"bld_lx_mansion", Vector3(interior.get_center().x, LOT_TOP, interior.end.y - 25.0), 0.0, Vector3.ONE, &"building")
			# Its gate, on the sidewalk outside (a place for the story, like the shops' doors).
			places[&"estate"] = Transform3D(Basis.looking_at(Vector3.BACK, Vector3.UP), Vector3(interior.get_center().x, LOT_TOP, interior.end.y + 2.0))
			for x: float in [interior.position.x + 2.0, interior.end.x - 2.0]:
				var z: float = interior.position.y + 3.0
				while z < interior.end.y - 2.0:
					_place(&"prop_palm_tree", Vector3(x, LOT_TOP, z), _rng.randf() * TAU, Vector3.ONE, &"prop")
					z += 8.0
		&"park":
			_lot(&"lot_grass", interior)
			_park(interior, 0.35)
			var c: Vector2 = interior.get_center()
			for k: int in 4:
				var a: float = TAU * k / 4.0
				_place(&"prop_lx_hedge", Vector3(c.x + cos(a) * 9.0, LOT_TOP, c.y + sin(a) * 9.0), a + PI * 0.5, Vector3.ONE, &"prop")
		_:
			super._fill_block(kind, rect, interior, walk, cls)


## Trees in the gaps between villa plots.
func _fill_yard(_kind: StringName, yard: Rect2) -> void:
	if yard.size.x >= 6.0 and yard.size.y >= 6.0:
		_place(&"prop_neem_tree", Vector3(yard.get_center().x, LOT_TOP, yard.get_center().y), _rng.randf() * TAU, Vector3.ONE, &"prop")


func _after_blocks() -> void:
	var estate: Vector2 = centre + Vector2((float(ESTATE[1]) + float(ESTATE[2])) * 0.5, (float(ESTATE[3]) + float(ESTATE[4])) * 0.5)
	var park: Vector2 = centre + Vector2((float(PARK[1]) + float(PARK[2])) * 0.5, (float(PARK[3]) + float(PARK[4])) * 0.5)
	map_labels = [["THE ESTATE", estate], ["SANDALWOOD PARK", park]]
	# Guard booths where the main roads come in from the Countryside.
	for line: Array in LINES_X:
		if int(line[1]) == MAIN:
			var x: float = centre.x + float(line[0]) + ROAD_HALF[MAIN] + 2.0
			_place(&"prop_lx_guard_booth", Vector3(x, LOT_TOP, centre.y + HALF - 6.0), PI * 0.5, Vector3.ONE, &"prop")
