class_name OldTownLayout
extends RefCounted
## The Old Town street plan (GDD §2 district 3, milestone M3). Pure data and deterministic: the
## same seed always gives the same town. tools/godot/build_old_town.gd turns the output into
## streamed chunk scenes, collision, a pedestrian navmesh and the lane graph.
##
## A temple town on a 512 m square (x and z from -256 to 256; -Z is north):
## - the walled temple compound with four gopurams in the middle, ringed by a lane (Ring A),
## - main roads (12 m, four lanes, traffic lights where two meet) along the gopuram axes and on
##   two rings at +-112 and +-184; lanes (8 m, two lanes) in between: the tight streets,
## - blocks lined with shops on main roads and houses on lanes, a market square with a hall and
##   stalls, a temple tank, two small parks. Traffic keeps left.

const HALF: float = 256.0
const CHUNK_SIZE: float = 128.0
const MAIN: int = 0
const LANE: int = 1
const ROAD_HALF: Array[float] = [6.0, 4.0]
const WALK: Array[float] = [4.0, 2.0]
const ZEBRA_LENGTH: Array[float] = [4.0, 3.0]
const SPEED_KMH: Array[float] = [50.0, 30.0]
## Lane centre offsets to the left of the direction of travel: [inner, outer] on main roads.
const LANE_OFFSETS: Array = [[1.5, 4.5], [2.0]]
const LOT_TOP: float = 0.15
const KERB_BEVEL: float = 0.29
const MAX_DEPTH: float = 12.0
## Half size of the temple tank model (bld_ot_tank, 30 x 30 m).
const TANK_HALF: float = 15.0
## The bus stand where New Game begins (base centre of the shelter).
const BUS_STAND := Vector3(97.0, LOT_TOP, 7.0)
## Props a special building may clear from in front of its door.
const CLEARABLE: Array[StringName] = [&"prop_streetlight", &"prop_bollard", &"prop_neem_tree", &"prop_palm_tree"]
## Special buildings (M6): [place id, ordinary kit it replaces, near this point, its kit, door
## distance from its centre, optionally a radius around the door kept clear of CLEARABLE props
## (the garage: cars drive in)]. The police station is on Ring B; the tiffin stall faces the bus
## stand across the east gopuram road; the garage is further east on that road; the clothes shop
## is on Ring B west; the house for sale is north of Ring B east.
const SPECIAL_BUILDINGS: Array = [
	[&"police_station", &"bld_ot_shop_04", Vector3(-40.0, 0.0, 115.0), &"bld_ot_police_station", 7.6],
	[&"tiffin", &"bld_ot_shop_04", Vector3(91.0, 0.0, -16.0), &"bld_ot_tiffin", 7.6],
	[&"garage", &"bld_ot_shop_04", Vector3(160.0, 0.0, -16.0), &"bld_ot_garage", 7.6, 6.0],
	[&"textiles", &"bld_ot_shop_02", Vector3(-58.0, 0.0, 127.0), &"bld_ot_textiles", 7.6],
	[&"house", &"bld_ot_house_05", Vector3(60.0, 0.0, 137.0), &"bld_ot_house_05", 7.6],
]
const NODE_SPACING: float = 10.0
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
## Arms of a junction: north, south, west, east (outward directions).
const ARM_DIRS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
const N: int = 0
const S: int = 1
const W: int = 2
const E: int = 3

## {kit: StringName, xform: Transform3D, kind: &"ground" | &"building" | &"prop" | &"landmark"}
var placements: Array[Dictionary] = []
## {rect: Rect2 (x, z), walk: [w, e, n, s] sidewalk widths (0 = district edge), kind: StringName}
var blocks: Array[Dictionary] = []
## Walkable strips across roads for pedestrians (zebras, and corners of lanes), x/z rects.
var crossings: Array[Rect2] = []
## {junction: int, position: Vector3, heads: [[Transform3D, axis]]}
var signals: Array[Dictionary] = []
## Where a pedestrian sits on a bench: {xform: Transform3D of their feet, facing +Z, kind: &"prop" or &"landmark"}
var sit_spots: Array[Dictionary] = []
## Where you are released after an arrest: on the sidewalk at the police station door, facing out.
var police_station := Transform3D()
## Spots at the doors of the special buildings, by id (see SPECIAL_BUILDINGS).
var places: Dictionary = {}
var lane_graph: LaneGraph
var junction_count: int = 0

var _pos: Array[float] = []        # [-256, line positions..., 256]
var _cls: Array[int] = []          # road class per _pos index (-1 at the district edge)
var _junctions: Dictionary = {}    # Vector2i(x-line index, z-line index) -> Dictionary
var _segments: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func generate() -> void:
	_rng.seed = SEED
	_pos = [-HALF]
	_cls = [-1]
	for line: Array in LINES:
		_pos.append(float(line[0]))
		_cls.append(int(line[1]))
	_pos.append(HALF)
	_cls.append(-1)
	_find_junctions()
	_find_segments()
	_build_roads()
	_build_blocks()
	_bus_stand()
	_special_buildings()
	_build_signals()
	_build_crossings()
	_build_lanes()


static func chunk_of(x: float, z: float) -> Vector2i:
	var count: int = int(2.0 * HALF / CHUNK_SIZE)
	return Vector2i(clampi(int(floor((x + HALF) / CHUNK_SIZE)), 0, count - 1),
		clampi(int(floor((z + HALF) / CHUNK_SIZE)), 0, count - 1))


# --------------------------------------------------------------------------- street network

## Whether the street on a line exists along one grid interval. ax 0: the line x = _pos[line]
## running along Z over [_pos[interval], _pos[interval + 1]]; ax 1: the line z = _pos[line] along X.
func _enabled(ax: int, line: int, interval: int) -> bool:
	if line <= 0 or line >= _pos.size() - 1 or interval < 0 or interval >= _pos.size() - 1:
		return false
	var c: float = _pos[line]
	var a0: float = _pos[interval]
	var a1: float = _pos[interval + 1]
	for m: Array in MERGED:
		var across0: float = float(m[1]) if ax == 0 else float(m[3])
		var across1: float = float(m[2]) if ax == 0 else float(m[4])
		var along0: float = float(m[3]) if ax == 0 else float(m[1])
		var along1: float = float(m[4]) if ax == 0 else float(m[2])
		if across0 < c and c < across1 and along0 <= a0 and a1 <= along1:
			return false
	return true


func _find_junctions() -> void:
	var keys: Array[Vector2i] = []
	for j: int in range(1, _pos.size() - 1):
		for i: int in range(1, _pos.size() - 1):
			var arms: Array[bool] = [_enabled(0, i, j - 1), _enabled(0, i, j), _enabled(1, j, i - 1), _enabled(1, j, i)]
			if (arms[N] or arms[S]) and (arms[W] or arms[E]):
				keys.append(Vector2i(i, j))
				var count: int = 0
				for a: bool in arms:
					count += 1 if a else 0
				var signalized: bool = _cls[i] == MAIN and _cls[j] == MAIN and count >= 3
				var zebra: Array[bool] = [false, false, false, false]
				for arm: int in 4:
					if not arms[arm]:
						continue
					var arm_cls: int = _cls[i] if arm <= S else _cls[j]
					var other: float = absf(_pos[j]) if arm <= S else absf(_pos[i])
					# Signalized junctions get zebras on every arm; so do the main roads that end
					# at the temple ring in front of each gopuram.
					zebra[arm] = signalized or (arm_cls == MAIN and is_equal_approx(other, 48.0))
				_junctions[Vector2i(i, j)] = {
					"key": Vector2i(i, j), "id": keys.size() - 1, "x": _pos[i], "z": _pos[j],
					"cls_x": _cls[i], "cls_z": _cls[j], "arms": arms, "signalized": signalized,
					"zebra": zebra, "seg": [-1, -1, -1, -1],
				}
	junction_count = keys.size()


func _find_segments() -> void:
	for ax: int in 2:
		for line: int in range(1, _pos.size() - 1):
			for interval: int in range(0, _pos.size() - 1):
				if not _enabled(ax, line, interval):
					continue
				var lo: int = interval
				var hi: int = interval + 1
				var j0: Variant = _junction_key(ax, line, lo)
				var j1: Variant = _junction_key(ax, line, hi)
				var a0: float = _pos[lo] + (ROAD_HALF[_cls[lo]] if j0 != null else 0.0)
				var a1: float = _pos[hi] - (ROAD_HALF[_cls[hi]] if j1 != null else 0.0)
				var seg: Dictionary = {"ax": ax, "c": _pos[line], "cls": _cls[line], "a0": a0, "a1": a1, "j0": j0, "j1": j1}
				_segments.append(seg)
				var index: int = _segments.size() - 1
				if j0 != null:   # this segment leaves j0 southwards (ax 0) or eastwards (ax 1)
					(_junctions[j0]["seg"] as Array)[S if ax == 0 else E] = index
				if j1 != null:
					(_junctions[j1]["seg"] as Array)[N if ax == 0 else W] = index


## Key of the junction where line `line` (axis ax) meets the crossing line at _pos index `at`.
func _junction_key(ax: int, line: int, at: int) -> Variant:
	if at <= 0 or at >= _pos.size() - 1:
		return null
	var key := Vector2i(line, at) if ax == 0 else Vector2i(at, line)
	return key if _junctions.has(key) else null


func _box_half(junction: Dictionary, arm: int) -> float:
	# Half extent of the junction box along the arm: the width of the road crossing it.
	return ROAD_HALF[int(junction["cls_z"])] if arm <= S else ROAD_HALF[int(junction["cls_x"])]


func _arm_road_half(junction: Dictionary, arm: int) -> float:
	return ROAD_HALF[int(junction["cls_x"])] if arm <= S else ROAD_HALF[int(junction["cls_z"])]


func _arm_class(junction: Dictionary, arm: int) -> int:
	return int(junction["cls_x"]) if arm <= S else int(junction["cls_z"])


# --------------------------------------------------------------------------- road surfaces

func _build_roads() -> void:
	for jd: Dictionary in _junctions.values():
		var cx: int = int(jd["cls_x"])
		var cz: int = int(jd["cls_z"])
		var kit: StringName = &"road_junction_ll"
		var yaw: float = 0.0
		if cx == MAIN and cz == MAIN:
			kit = &"road_junction_mm"
		elif cx == MAIN:
			kit = &"road_junction_ml"
		elif cz == MAIN:
			kit = &"road_junction_ml"
			yaw = PI * 0.5
		_place(kit, Vector3(float(jd["x"]), 0.0, float(jd["z"])), yaw, Vector3.ONE, &"ground")
	for seg: Dictionary in _segments:
		var cls: int = int(seg["cls"])
		var a0: float = float(seg["a0"])
		var a1: float = float(seg["a1"])
		var zl: float = ZEBRA_LENGTH[cls]
		var zebra_kit: StringName = &"road_zebra_main" if cls == MAIN else &"road_zebra_lane"
		if seg["j0"] != null and bool((_junctions[seg["j0"]]["zebra"] as Array)[S if int(seg["ax"]) == 0 else E]):
			_place(zebra_kit, _seg_point(seg, a0 + zl * 0.5), _seg_yaw(seg, -1), Vector3.ONE, &"ground")
			a0 += zl
		if seg["j1"] != null and bool((_junctions[seg["j1"]]["zebra"] as Array)[N if int(seg["ax"]) == 0 else W]):
			_place(zebra_kit, _seg_point(seg, a1 - zl * 0.5), _seg_yaw(seg, 1), Vector3.ONE, &"ground")
			a1 -= zl
		var length: float = a1 - a0
		if length <= 0.05:
			continue
		var count: int = maxi(1, roundi(length / 6.0))
		var piece: float = length / count
		for k: int in count:
			_place(&"road_main_seg" if cls == MAIN else &"road_lane_seg",
				_seg_point(seg, a0 + piece * (k + 0.5)), _seg_yaw(seg, 1), Vector3(1, 1, piece / 6.0), &"ground")


func _seg_point(seg: Dictionary, along: float) -> Vector3:
	return Vector3(float(seg["c"]), 0.0, along) if int(seg["ax"]) == 0 else Vector3(along, 0.0, float(seg["c"]))


## Yaw that points a tile's local +Z along the segment, forwards (+1) or backwards (-1).
func _seg_yaw(seg: Dictionary, direction: int) -> float:
	if int(seg["ax"]) == 0:
		return 0.0 if direction > 0 else PI
	return PI * 0.5 if direction > 0 else -PI * 0.5


# --------------------------------------------------------------------------- blocks

func _build_blocks() -> void:
	var count: int = _pos.size() - 1
	for iz: int in count:
		for ix: int in count:
			if _in_merged(_pos[ix], _pos[ix + 1], _pos[iz], _pos[iz + 1]):
				continue
			var kind: StringName = &"standard"
			for p: Array in PARKS:
				if is_equal_approx(float(p[0]), _pos[ix]) and is_equal_approx(float(p[2]), _pos[iz]):
					kind = &"park"
			_add_block(ix, ix + 1, iz, iz + 1, kind)
	for m: Array in MERGED:
		_add_block(_pos.find(float(m[1])), _pos.find(float(m[2])), _pos.find(float(m[3])), _pos.find(float(m[4])), m[0])


func _in_merged(x0: float, x1: float, z0: float, z1: float) -> bool:
	for m: Array in MERGED:
		if float(m[1]) <= x0 and x1 <= float(m[2]) and float(m[3]) <= z0 and z1 <= float(m[4]):
			return true
	return false


func _add_block(ix0: int, ix1: int, iz0: int, iz1: int, kind: StringName) -> void:
	var cls: Array[int] = [_cls[ix0], _cls[ix1], _cls[iz0], _cls[iz1]]   # w, e, n, s
	var walk: Array[float] = []
	for c: int in cls:
		walk.append(WALK[c] if c >= 0 else 0.0)
	var x0: float = _pos[ix0] + (ROAD_HALF[cls[0]] if cls[0] >= 0 else 0.0)
	var x1: float = _pos[ix1] - (ROAD_HALF[cls[1]] if cls[1] >= 0 else 0.0)
	var z0: float = _pos[iz0] + (ROAD_HALF[cls[2]] if cls[2] >= 0 else 0.0)
	var z1: float = _pos[iz1] - (ROAD_HALF[cls[3]] if cls[3] >= 0 else 0.0)
	var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
	blocks.append({"rect": rect, "walk": walk, "cls": cls, "kind": kind})
	var interior := Rect2(x0 + walk[0], z0 + walk[2], rect.size.x - walk[0] - walk[1], rect.size.y - walk[2] - walk[3])
	_sidewalks(rect, walk, cls)
	var ground: StringName = {&"temple": &"lot_stone", &"tank": &"lot_stone", &"market": &"lot_warm", &"park": &"lot_grass"}.get(kind, &"lot_paved")
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
	_streetlights(rect, walk, cls)


func _lot(kit: StringName, r: Rect2) -> void:
	if r.size.x > 0.05 and r.size.y > 0.05:
		_place(kit, Vector3(r.get_center().x, 0.0, r.get_center().y), 0.0, Vector3(r.size.x, 1.0, r.size.y), &"ground")


## Sidewalk strips along each road-facing side (kerb towards the road) and corner tiles.
func _sidewalks(r: Rect2, walk: Array[float], cls: Array[int]) -> void:
	var x0: float = r.position.x
	var z0: float = r.position.y
	var x1: float = r.end.x
	var z1: float = r.end.y
	# [kerb normal, strip rect, width]
	var strips: Array = [
		[Vector3(-1, 0, 0), Rect2(x0, z0 + walk[2], walk[0], r.size.y - walk[2] - walk[3]), walk[0]],
		[Vector3(1, 0, 0), Rect2(x1 - walk[1], z0 + walk[2], walk[1], r.size.y - walk[2] - walk[3]), walk[1]],
		[Vector3(0, 0, -1), Rect2(x0 + walk[0], z0, r.size.x - walk[0] - walk[1], walk[2]), walk[2]],
		[Vector3(0, 0, 1), Rect2(x0 + walk[0], z1 - walk[3], r.size.x - walk[0] - walk[1], walk[3]), walk[3]],
	]
	for s: Array in strips:
		var width: float = float(s[2])
		if width <= 0.0:
			continue
		var n: Vector3 = s[0]
		var rect: Rect2 = s[1]
		var along_x: bool = absf(n.z) > 0.5
		var length: float = rect.size.x if along_x else rect.size.y
		var count: int = maxi(1, roundi(length / 6.0))
		var piece: float = length / count
		var basis := Basis(-n, Vector3.UP, (-n).cross(Vector3.UP))
		for k: int in count:
			var c: Vector2 = rect.get_center()
			var t: float = (rect.position.x if along_x else rect.position.y) + piece * (k + 0.5)
			var pos := Vector3(t, 0.0, c.y) if along_x else Vector3(c.x, 0.0, t)
			_place_xform(&"road_walk_main" if width > 3.0 else &"road_walk_lane",
				Transform3D(basis * Basis.from_scale(Vector3(1, 1, piece / 6.0)), pos), &"ground")
	# Corners: the tile's kerbs face local -X and +Z.
	var corners: Array = [   # [yaw, centre, width facing local -X, width facing local +Z]
		[-PI * 0.5, Vector2(x0 + walk[0] * 0.5, z0 + walk[2] * 0.5), walk[2], walk[0]],   # north-west
		[PI, Vector2(x1 - walk[1] * 0.5, z0 + walk[2] * 0.5), walk[1], walk[2]],         # north-east
		[0.0, Vector2(x0 + walk[0] * 0.5, z1 - walk[3] * 0.5), walk[0], walk[3]],         # south-west
		[PI * 0.5, Vector2(x1 - walk[1] * 0.5, z1 - walk[3] * 0.5), walk[3], walk[1]],    # south-east
	]
	for c: Array in corners:
		var wa: float = float(c[2])
		var wb: float = float(c[3])
		if wa <= 0.0 or wb <= 0.0:
			continue
		var centre: Vector2 = c[1]
		_place(&"road_walk_corner", Vector3(centre.x, 0.0, centre.y), float(c[0]), Vector3(wa / 4.0, 1.0, wb / 4.0), &"ground")


func _streetlights(r: Rect2, walk: Array[float], cls: Array[int]) -> void:
	# [road class, kerb normal, start, end, kerb position]
	var sides: Array = [
		[cls[0], Vector3(-1, 0, 0), r.position.y + walk[2], r.end.y - walk[3], r.position.x],
		[cls[1], Vector3(1, 0, 0), r.position.y + walk[2], r.end.y - walk[3], r.end.x],
		[cls[2], Vector3(0, 0, -1), r.position.x + walk[0], r.end.x - walk[1], r.position.y],
		[cls[3], Vector3(0, 0, 1), r.position.x + walk[0], r.end.x - walk[1], r.end.y],
	]
	for s: Array in sides:
		var c: int = int(s[0])
		var n: Vector3 = s[1]
		if c < 0 or (c == LANE and n.x + n.z < 0.0):
			continue      # lanes get lights on one side only
		var spacing: float = 24.0 if c == MAIN else 30.0
		var inset: float = 0.55 if c == MAIN else 0.3
		var t: float = float(s[2]) + 5.0
		while t <= float(s[3]) - 3.0:
			var kerb: float = float(s[4])
			var pos := Vector3(t, LOT_TOP, kerb - n.z * inset) if absf(n.z) > 0.5 else Vector3(kerb - n.x * inset, LOT_TOP, t)
			_place(&"prop_streetlight", pos, atan2(-n.z, n.x), Vector3.ONE, &"prop")
			t += spacing


## Lines the sides of `interior` with buildings facing outwards. sides: [w, e, n, s] building
## catalogues (null = no buildings on that side). North and south rows run the full width; west
## and east rows fill between them. Returns what is left in the middle (a courtyard).
func _frontages(interior: Rect2, sides: Array, depth_limit: float) -> Rect2:
	var has: Array[bool] = [sides[0] != null, sides[1] != null, sides[2] != null, sides[3] != null]
	var dz_n: float = 0.0
	var dz_s: float = 0.0
	var dx_w: float = 0.0
	var dx_e: float = 0.0
	var both_ns: bool = has[2] and has[3]
	var both_we: bool = has[0] and has[1]
	if has[2]:
		dz_n = minf(depth_limit, interior.size.y * (0.5 if both_ns else 1.0))
	if has[3]:
		dz_s = minf(depth_limit, interior.size.y * (0.5 if both_ns else 1.0))
	if has[0]:
		dx_w = minf(depth_limit, interior.size.x * (0.5 if both_we else 1.0))
	if has[1]:
		dx_e = minf(depth_limit, interior.size.x * (0.5 if both_we else 1.0))
	var x0: float = interior.position.x
	var x1: float = interior.end.x
	var z0: float = interior.position.y
	var z1: float = interior.end.y
	if has[2]:
		_fill_side(x0, x1, Vector3(0, 0, -1), z0, dz_n, sides[2])
	if has[3]:
		_fill_side(x0, x1, Vector3(0, 0, 1), z1, dz_s, sides[3])
	if has[0]:
		_fill_side(z0 + dz_n, z1 - dz_s, Vector3(-1, 0, 0), x0, dx_w, sides[0])
	if has[1]:
		_fill_side(z0 + dz_n, z1 - dz_s, Vector3(1, 0, 0), x1, dx_e, sides[1])
	return Rect2(x0 + dx_w, z0 + dz_n, interior.size.x - dx_w - dx_e, interior.size.y - dz_n - dz_s)


## One row of buildings between a0 and a1 along a side whose front line is at `front` (an x or
## z coordinate) and faces direction n, at most `depth` deep.
func _fill_side(a0: float, a1: float, n: Vector3, front: float, depth: float, catalogue: Array) -> void:
	var length: float = a1 - a0
	if length < 5.5 or depth < 7.0:
		return
	var picks: Array = []
	var used: float = 0.0
	while true:
		var fits: Array = []
		for entry: Array in catalogue:
			if float(entry[1]) <= length - used + 0.01 and depth >= float(entry[2]) * 0.72:
				fits.append(entry)
		if fits.is_empty():
			break
		var pick: Array = _weighted(fits)
		picks.append(pick)
		used += float(pick[1])
	if picks.is_empty():
		return
	var gap: float = (length - used) / (picks.size() + 1)
	var t: float = a0 + gap
	var yaw: float = atan2(n.x, n.z)
	for pick: Array in picks:
		var w: float = float(pick[1])
		var d: float = float(pick[2])
		var depth_scale: float = minf(1.0, depth / d)
		var along: float = t + w * 0.5
		var front_point := Vector3(along, LOT_TOP, front) if absf(n.z) > 0.5 else Vector3(front, LOT_TOP, along)
		_place(pick[0], front_point - n * (d * depth_scale * 0.5), yaw, Vector3(1, 1, depth_scale), &"building")
		t += w + gap


func _weighted(entries: Array) -> Array:
	var total: float = 0.0
	for e: Array in entries:
		total += float(e[3])
	var roll: float = _rng.randf() * total
	for e: Array in entries:
		roll -= float(e[3])
		if roll <= 0.0:
			return e
	return entries[entries.size() - 1]


func _park(interior: Rect2) -> void:
	var x: float = interior.position.x + 4.0
	while x < interior.end.x - 3.0:
		var z: float = interior.position.y + 4.0
		while z < interior.end.y - 3.0:
			var kit: StringName = &"prop_palm_tree" if _rng.randf() < 0.25 else &"prop_neem_tree"
			_place(kit, Vector3(x + _rng.randf_range(-1.5, 1.5), LOT_TOP, z + _rng.randf_range(-1.5, 1.5)),
				_rng.randf() * TAU, Vector3.ONE, &"prop")
			z += 9.0
		x += 9.0
	_benches_facing_in(interior, 2.0, &"prop")


## A bench at the middle of each side of `r`, `inset` metres in, facing the middle.
func _benches_facing_in(r: Rect2, inset: float, kind: StringName) -> void:
	var c: Vector2 = r.get_center()
	_bench(Vector3(c.x, LOT_TOP, r.position.y + inset), 0.0, kind)
	_bench(Vector3(c.x, LOT_TOP, r.end.y - inset), PI, kind)
	_bench(Vector3(r.position.x + inset, LOT_TOP, c.y), PI * 0.5, kind)
	_bench(Vector3(r.end.x - inset, LOT_TOP, c.y), -PI * 0.5, kind)


## Special buildings (M6) and the places at their doors (DistrictData.places): each one takes the
## place of the ordinary building of kit `from` nearest `near` (same footprint; the same kit when
## only the spot is needed), and its door spot is recorded under `id`, on the sidewalk facing out.
func _special_buildings() -> void:
	for special: Array in SPECIAL_BUILDINGS:
		var id: StringName = special[0]
		var from: StringName = special[1]
		var near: Vector3 = special[2]
		var best: int = -1
		var best_d: float = INF
		for i: int in placements.size():
			if placements[i]["kit"] != from:
				continue
			var d: float = (placements[i]["xform"] as Transform3D).origin.distance_to(near)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			push_error("OldTownLayout: no %s near %s for %s" % [from, near, id])
			continue
		placements[best]["kit"] = special[3]
		var xform: Transform3D = placements[best]["xform"]
		var front: Vector3 = xform.basis.z.normalized()     # buildings face their +Z (Blender -Y)
		var door: Vector3 = xform.origin + front * special[4]
		places[id] = Transform3D(Basis.looking_at(front, Vector3.UP), Vector3(door.x, LOT_TOP, door.z))
		var clear: float = float(special[5]) if special.size() > 5 else 0.0
		for i: int in range(placements.size() - 1, -1, -1):
			var kit: StringName = placements[i]["kit"]
			var at: Vector3 = (placements[i]["xform"] as Transform3D).origin
			if clear > 0.0 and kit in CLEARABLE and Vector2(at.x - door.x, at.z - door.z).length() < clear:
				placements.remove_at(i)
	police_station = places.get(&"police_station", Transform3D())


## The bus stand on the south kerb of the east gopuram road, where New Game begins (M5): the
## shelter opens towards the road, and its bench seats two waiting pedestrians.
func _bus_stand() -> void:
	var yaw: float = PI   # model's open side (+Z) faces -Z, the road
	_place(&"prop_bus_shelter", BUS_STAND, yaw, Vector3.ONE, &"prop")
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-0.6, 0.6]:
		# Seat top at 0.5 m, front edge 0.1 m behind the centre line.
		sit_spots.append({"xform": Transform3D(basis, BUS_STAND + basis * Vector3(side, -0.38, -0.18)), "kind": &"prop"})


## A stone bench facing +Z rotated by yaw, with two places to sit.
func _bench(pos: Vector3, yaw: float, kind: StringName) -> void:
	_place(&"prop_bench", pos, yaw, Vector3.ONE, kind)
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-0.45, 0.45]:
		# Feet origin of a seated figure: hips (0.92 m up) just above the 0.47 m seat.
		sit_spots.append({"xform": Transform3D(basis, pos + basis * Vector3(side, -0.41, 0.16)), "kind": kind})


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

func _build_signals() -> void:
	for jd: Dictionary in _junctions.values():
		if not bool(jd["signalized"]):
			continue
		var centre := Vector3(float(jd["x"]), 0.0, float(jd["z"]))
		var heads: Array = []
		for arm: int in 4:
			if not bool((jd["arms"] as Array)[arm]):
				continue
			var out: Vector3 = ARM_DIRS[arm]
			var travel: Vector3 = -out                          # approaching traffic
			var left: Vector3 = Vector3.UP.cross(travel)
			var pos: Vector3 = centre + out * (_box_half(jd, arm) + ZEBRA_LENGTH[MAIN] - 0.3) \
				+ left * (_arm_road_half(jd, arm) + 0.8) + Vector3.UP * LOT_TOP
			heads.append([Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), pos), 0 if arm <= S else 1])
		signals.append({"junction": int(jd["id"]), "position": centre, "heads": heads})


func _build_crossings() -> void:
	for jd: Dictionary in _junctions.values():
		var centre := Vector2(float(jd["x"]), float(jd["z"]))
		for arm: int in 4:
			if not bool((jd["arms"] as Array)[arm]):
				continue
			var span: Vector2
			if bool((jd["zebra"] as Array)[arm]):
				span = Vector2(0.2, ZEBRA_LENGTH[_arm_class(jd, arm)] * 0.62)
			elif _arm_class(jd, arm) == LANE:
				span = Vector2(0.0, 2.5)
			else:
				continue
			var out: Vector3 = ARM_DIRS[arm]
			var hb: float = _box_half(jd, arm)
			var across: float = _arm_road_half(jd, arm) + 0.6
			var a0: float = hb + span.x
			var a1: float = hb + span.y
			if absf(out.x) > 0.5:
				var xs: Array[float] = [centre.x + out.x * a0, centre.x + out.x * a1]
				crossings.append(Rect2(minf(xs[0], xs[1]), centre.y - across, absf(a1 - a0), across * 2.0))
			else:
				var zs: Array[float] = [centre.y + out.z * a0, centre.y + out.z * a1]
				crossings.append(Rect2(centre.x - across, minf(zs[0], zs[1]), across * 2.0, absf(a1 - a0)))


# --------------------------------------------------------------------------- lane graph

func _build_lanes() -> void:
	var builder := LaneGraphBuilder.new()
	# chains[segment][dir 0 = increasing, 1 = decreasing][lane] = [first node, last node]
	var chains: Array = []
	for seg: Dictionary in _segments:
		var per_dir: Array = []
		for d: int in 2:
			var direction: float = 1.0 if d == 0 else -1.0
			var travel: Vector3 = (Vector3(0, 0, direction) if int(seg["ax"]) == 0 else Vector3(direction, 0, 0))
			var left: Vector3 = Vector3.UP.cross(travel)
			var cls: int = int(seg["cls"])
			var ahead: Variant = seg["j1"] if d == 0 else seg["j0"]
			var behind: Variant = seg["j0"] if d == 0 else seg["j1"]
			var start: float = float(seg["a0"]) if d == 0 else float(seg["a1"])
			var stop: float = float(seg["a1"]) if d == 0 else float(seg["a0"])
			if behind == null:
				start += 6.0 * direction        # leave room for the U-turn at the district edge
			if ahead == null:
				stop -= 6.0 * direction
			else:
				var arm: int = (N if int(seg["ax"]) == 0 else W) if d == 0 else (S if int(seg["ax"]) == 0 else E)
				var has_zebra: bool = bool((_junctions[ahead]["zebra"] as Array)[arm])
				stop -= (ZEBRA_LENGTH[cls] * 0.82 if has_zebra else 0.5) * direction
			var lanes: Array = []
			for offset: float in LANE_OFFSETS[cls]:
				var steps: int = maxi(1, ceili(absf(stop - start) / NODE_SPACING))
				var first: int = -1
				var previous: int = -1
				for k: int in steps + 1:
					var along: float = lerpf(start, stop, float(k) / steps)
					var p: Vector3 = _seg_point(seg, along) + left * offset
					var node: int = builder.add_node(p, SPEED_KMH[cls])
					if previous >= 0:
						builder.connect_nodes(previous, node)
					else:
						first = node
					previous = node
				if ahead != null:
					var jd: Dictionary = _junctions[ahead]
					var flags: int = LaneGraph.Flag.STOP_LINE
					if bool(jd["signalized"]):
						flags |= LaneGraph.Flag.SIGNALIZED
					elif cls == LANE and (int(jd["cls_x"]) == MAIN or int(jd["cls_z"]) == MAIN):
						flags |= LaneGraph.Flag.GIVE_WAY
					builder.set_flags(previous, flags, int(jd["id"]), int(seg["ax"]))
				lanes.append([first, previous])
			if lanes.size() == 2:
				# Both lanes have the same number of nodes, added in order: link them pairwise.
				for k: int in int(lanes[0][1]) - int(lanes[0][0]) + 1:
					builder.set_side_lanes(int(lanes[0][0]) + k, int(lanes[1][0]) + k)
			per_dir.append(lanes)
		chains.append(per_dir)

	# Turns through junctions.
	for jd: Dictionary in _junctions.values():
		var segs: Array = jd["seg"]
		for arm_in: int in 4:
			if int(segs[arm_in]) < 0:
				continue
			# Arriving through arm_in: N arm -> segment ends here, travelling increasing (dir 0), etc.
			var in_dir: int = 0 if arm_in == N or arm_in == W else 1
			var in_lanes: Array = chains[int(segs[arm_in])][in_dir]
			var travel_in: Vector3 = -ARM_DIRS[arm_in]
			var left_in: Vector3 = Vector3.UP.cross(travel_in)
			for arm_out: int in 4:
				if arm_out == arm_in or int(segs[arm_out]) < 0:
					continue
				var out_dir: int = 0 if arm_out == S or arm_out == E else 1
				var out_lanes: Array = chains[int(segs[arm_out])][out_dir]
				var travel_out: Vector3 = ARM_DIRS[arm_out]
				var straight: bool = travel_in.dot(travel_out) > 0.5
				var left_turn: bool = not straight and travel_out.dot(left_in) > 0.0
				for li: int in in_lanes.size():
					var lo: int = 0
					if straight:
						lo = mini(li, out_lanes.size() - 1)
					elif left_turn:
						if in_lanes.size() > 1 and li == 0:
							continue          # left turns use the outer (kerb-side) lane
						lo = out_lanes.size() - 1
					else:
						if in_lanes.size() > 1 and li == in_lanes.size() - 1:
							continue          # right turns use the inner lane
						lo = 0
					var from: int = int((in_lanes[li] as Array)[1])
					var to: int = int((out_lanes[lo] as Array)[0])
					var speed: float = 20.0 if not straight and not left_turn else 25.0
					_link(builder, from, to, travel_in, speed, int(jd["id"]), LaneGraph.Flag.IN_JUNCTION, straight)

	# U-turns where roads meet the district edge.
	for s: int in _segments.size():
		var seg: Dictionary = _segments[s]
		for d: int in 2:
			var ahead: Variant = seg["j1"] if d == 0 else seg["j0"]
			if ahead != null:
				continue
			var direction: float = 1.0 if d == 0 else -1.0
			var travel: Vector3 = (Vector3(0, 0, direction) if int(seg["ax"]) == 0 else Vector3(direction, 0, 0))
			var back: Array = chains[s][1 - d]
			for k: int in (chains[s][d] as Array).size():
				var lane: Array = chains[s][d][k]
				var back_entry: int = int((back[mini(k, back.size() - 1)] as Array)[0])   # inner to inner, outer to outer
				_link(builder, int(lane[1]), back_entry, travel, 15.0, -1, LaneGraph.Flag.U_TURN, false)
	lane_graph = builder.build()
	var centres := PackedVector3Array()
	centres.resize(junction_count)
	for jd: Dictionary in _junctions.values():
		centres[int(jd["id"])] = Vector3(float(jd["x"]), 0.0, float(jd["z"]))
	lane_graph.junction_positions = centres


## Joins two lane nodes with a short curve (two in-between nodes). Turns bend around the point
## where the two lane lines cross; U-turns bulge forwards.
func _link(builder: LaneGraphBuilder, from: int, to: int, travel_in: Vector3, speed: float,
		junction: int, flag: int, straight: bool) -> void:
	var p0: Vector3 = builder.get_position(from)
	var p3: Vector3 = builder.get_position(to)
	var control: Vector3
	if straight:
		control = (p0 + p3) * 0.5
	elif flag == LaneGraph.Flag.U_TURN:
		control = (p0 + p3) * 0.5 + travel_in * 5.0
	else:
		control = p0 + travel_in * (p3 - p0).dot(travel_in)
	var previous: int = from
	for t: float in [1.0 / 3.0, 2.0 / 3.0]:
		var p: Vector3 = p0.lerp(control, t).lerp(control.lerp(p3, t), t)
		var node: int = builder.add_node(p, speed, junction, -1, flag)
		builder.connect_nodes(previous, node)
		previous = node
	builder.connect_nodes(previous, to)


# --------------------------------------------------------------------------- helpers

func _place(kit: StringName, pos: Vector3, yaw: float, scale: Vector3, kind: StringName) -> void:
	_place_xform(kit, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), pos), kind)


func _place_xform(kit: StringName, xform: Transform3D, kind: StringName) -> void:
	placements.append({"kit": kit, "xform": xform, "kind": kind})
