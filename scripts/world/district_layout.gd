class_name DistrictLayout
extends RefCounted
## One 512 m district of Velanagar on a street grid (M3's Old Town generator, generalised in M7
## so every district shares it). Pure data and deterministic: the same seed always gives the same
## district. CityLayout puts the districts side by side; tools/godot/build_city.gd turns the
## result into streamed chunk scenes, collision, the pedestrian navmesh and the lane graph.
##
## A district is a square of 2 * HALF metres around `centre` (world X/Z; -Z is north) crossed by
## street lines: main roads (12 m, four lanes, traffic lights where two meet) and lanes (8 m, two
## lanes). Merged rectangles join grid cells into big blocks (the streets inside them don't
## exist). Each block gets sidewalks, ground and whatever the district puts on it. Traffic keeps
## left. Where a road reaches a side that borders another district with the same road, it carries
## on (CityLayout links the lanes); anywhere else a road that reaches the edge ends in a U-turn.
##
## Subclasses describe the district through the virtual methods in the "district description"
## section (lines, merged blocks, what fills a block) and may add features in _after_blocks().

const HALF: float = 256.0
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
const NODE_SPACING: float = 10.0
## Where a road ends, its lanes stop this far short of the end (room for the U-turn)...
const DEAD_END_ROOM: float = 6.0
## ...and where it carries on into the next district, this far (the city joins the two ends).
const THROUGH_ROOM: float = 2.0
## Arms of a junction: north, south, west, east (outward directions).
const ARM_DIRS: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]
const N: int = 0
const S: int = 1
const W: int = 2
const E: int = 3

## Short name used in data (save files, regions), e.g. &"old_town".
var id: StringName = &""
var display_name: String = ""
## World X/Z of the district's centre.
var centre: Vector2 = Vector2.ZERO

## {kit: StringName, xform: Transform3D, kind: &"ground" | &"building" | &"prop" | &"landmark"}
var placements: Array[Dictionary] = []
## {rect: Rect2 (x, z), walk: [w, e, n, s] sidewalk widths (0 = district edge), cls, kind: StringName}
var blocks: Array[Dictionary] = []
## Walkable strips across roads for pedestrians (zebras, and corners of lanes), x/z rects.
var crossings: Array[Rect2] = []
## {junction: int, position: Vector3, heads: [[Transform3D, axis]]}
var signals: Array[Dictionary] = []
## Where a pedestrian sits on a bench: {xform: Transform3D of their feet, facing +Z, kind: &"prop" or &"landmark"}
var sit_spots: Array[Dictionary] = []
## Spots at the doors of special buildings (shops, properties, the police station...), by id:
## on the sidewalk, facing out.
var places: Dictionary = {}
## Where you are released after an arrest, if the district has a police station.
var police_station := Transform3D()
var has_police_station: bool = false
## Map labels: [text, world Vector2].
var map_labels: Array = []
## Built only when the district is generated on its own (generate()); in the city, CityLayout
## builds one graph for every district.
var lane_graph: LaneGraph
var junction_count: int = 0
## Centre of each of this district's junctions, by (junction id - junction_base).
var junction_positions := PackedVector3Array()
## Lane ends where a road leaves this district into the next: {point: Vector2 (world x/z of the
## road centre at the edge), out: [last node of each lane leaving], in: [first node of each lane
## arriving]} (lanes in LANE_OFFSETS order).
var edge_ends: Array[Dictionary] = []

## Set by the city before build(): the first junction id of this district (ids are unique in
## the city), and the points (world x/z) where a road crosses into a neighbour that has it too.
var junction_base: int = 0
var through_points: Array[Vector2] = []

var _px: Array[float] = []         # [west edge, x line positions..., east edge] (world)
var _pz: Array[float] = []         # [north edge, z line positions..., south edge] (world)
var _cls_x: Array[int] = []        # road class per _px index (-1 at the district edge)
var _cls_z: Array[int] = []
var _junctions: Dictionary = {}    # Vector2i(x-line index, z-line index) -> Dictionary
var _segments: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


## The district on its own (its own lane graph, no neighbours).
func generate() -> void:
	plan()
	build(null)


## Step 1: the street network (junctions and segments). Nothing is placed yet.
func plan() -> void:
	_rng.seed = _seed()
	_px = [centre.x - HALF]
	_cls_x = [-1]
	for line: Array in _lines_x():
		_px.append(centre.x + float(line[0]))
		_cls_x.append(int(line[1]))
	_px.append(centre.x + HALF)
	_cls_x.append(-1)
	_pz = [centre.y - HALF]
	_cls_z = [-1]
	for line: Array in _lines_z():
		_pz.append(centre.y + float(line[0]))
		_cls_z.append(int(line[1]))
	_pz.append(centre.y + HALF)
	_cls_z.append(-1)
	_find_junctions()
	_find_segments()


## Step 2: roads, blocks, features, signals, crossings and lanes. Lane nodes go into `builder`
## (the city's) or, when it is null, into this district's own lane_graph.
func build(builder: LaneGraphBuilder) -> void:
	_build_roads()
	_build_blocks()
	_after_blocks()
	_build_signals()
	_build_crossings()
	_build_lanes(builder)


## The district's square, as a world x/z rectangle.
func get_rect() -> Rect2:
	return Rect2(centre - Vector2(HALF, HALF), Vector2(HALF, HALF) * 2.0)


## Where roads reach the district edge: [{point: Vector2 world x/z, cls: int}].
func edge_roads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seg: Dictionary in _segments:
		for end: int in 2:
			if seg["j1" if end == 1 else "j0"] != null:
				continue
			var along: float = float(seg["a1" if end == 1 else "a0"])
			var p: Vector3 = _seg_point(seg, along)
			if _on_edge(Vector2(p.x, p.z)):
				out.append({"point": Vector2(p.x, p.z), "cls": int(seg["cls"])})
	return out


# --------------------------------------------------------------------------- district description

## Street lines running north-south: [x relative to the centre, MAIN or LANE], west to east.
func _lines_x() -> Array:
	return []


## Street lines running east-west: [z relative to the centre, class], north to south.
func _lines_z() -> Array:
	return []


## Big blocks spanning several grid cells: [kind, x0, x1, z0, z1] relative to the centre, each
## edge on a line (or the district edge).
func _merged() -> Array:
	return []


## Kind of an ordinary grid cell whose north-west corner is at (x0, z0) relative to the centre.
func _cell_kind(_x0: float, _z0: float) -> StringName:
	return &"standard"


func _seed() -> int:
	return 1


## Whether a junction arm gets a zebra crossing. crossing_line: where the crossing road is, relative
## to the centre (along the arm's road).
func _zebra(signalized: bool, _arm_cls: int, _crossing_line: float) -> bool:
	return signalized


## Fills a block's interior (inside its sidewalks): ground, buildings, props. The default lines
## road-facing sides with buildings from _catalogue() and puts a tree in a big enough yard.
func _fill_block(kind: StringName, _rect: Rect2, interior: Rect2, _walk: Array[float], cls: Array[int]) -> void:
	_lot(_lot_kit(kind), interior)
	var sides: Array = []
	for c: int in cls:
		sides.append(null if c < 0 else _catalogue(c))
	var yard: Rect2 = _frontages(interior, sides, _max_depth())
	_fill_yard(kind, yard)


## Ground of a block's interior (a lot colour, see build_city.gd LOT_COLOURS).
func _lot_kit(_kind: StringName) -> StringName:
	return &"lot_paved"


## Buildings facing a road of class `cls`: [[kit, frontage width, depth, weight]].
func _catalogue(_cls: int) -> Array:
	return []


## Deepest a row of buildings may be.
func _max_depth() -> float:
	return 12.0


## What goes in the courtyard left in the middle of a standard block.
func _fill_yard(_kind: StringName, _yard: Rect2) -> void:
	pass


## Extra features once the blocks are filled (landmarks, special buildings, places).
func _after_blocks() -> void:
	pass


## Props along the sidewalks, which streetlight model and how far apart.
func _streetlight_kit() -> StringName:
	return &"prop_streetlight"


# --------------------------------------------------------------------------- street network

## Whether the street on a line exists along one grid interval. ax 0: the line x = _px[line]
## running along Z over [_pz[interval], _pz[interval + 1]]; ax 1: the line z = _pz[line] along X.
func _enabled(ax: int, line: int, interval: int) -> bool:
	var lines: Array[float] = _px if ax == 0 else _pz
	var spans: Array[float] = _pz if ax == 0 else _px
	if line <= 0 or line >= lines.size() - 1 or interval < 0 or interval >= spans.size() - 1:
		return false
	var c: float = lines[line]
	var a0: float = spans[interval]
	var a1: float = spans[interval + 1]
	for m: Array in _merged():
		var across0: float = (centre.x + float(m[1])) if ax == 0 else (centre.y + float(m[3]))
		var across1: float = (centre.x + float(m[2])) if ax == 0 else (centre.y + float(m[4]))
		var along0: float = (centre.y + float(m[3])) if ax == 0 else (centre.x + float(m[1]))
		var along1: float = (centre.y + float(m[4])) if ax == 0 else (centre.x + float(m[2]))
		if across0 < c and c < across1 and along0 <= a0 and a1 <= along1:
			return false
	return true


func _find_junctions() -> void:
	var count: int = 0
	for j: int in range(1, _pz.size() - 1):
		for i: int in range(1, _px.size() - 1):
			var arms: Array[bool] = [_enabled(0, i, j - 1), _enabled(0, i, j), _enabled(1, j, i - 1), _enabled(1, j, i)]
			if not ((arms[N] or arms[S]) and (arms[W] or arms[E])):
				continue
			count += 1
			var arm_count: int = 0
			for a: bool in arms:
				arm_count += 1 if a else 0
			var signalized: bool = _cls_x[i] == MAIN and _cls_z[j] == MAIN and arm_count >= 3
			var zebra: Array[bool] = [false, false, false, false]
			for arm: int in 4:
				if not arms[arm]:
					continue
				var arm_cls: int = _cls_x[i] if arm <= S else _cls_z[j]
				var crossing: float = (_pz[j] - centre.y) if arm <= S else (_px[i] - centre.x)
				zebra[arm] = _zebra(signalized, arm_cls, crossing)
			_junctions[Vector2i(i, j)] = {
				"key": Vector2i(i, j), "id": junction_base + count - 1, "x": _px[i], "z": _pz[j],
				"cls_x": _cls_x[i], "cls_z": _cls_z[j], "arms": arms, "signalized": signalized,
				"zebra": zebra, "seg": [-1, -1, -1, -1],
			}
	junction_count = count


func _find_segments() -> void:
	for ax: int in 2:
		var lines: Array[float] = _px if ax == 0 else _pz
		var classes: Array[int] = _cls_x if ax == 0 else _cls_z
		var spans: Array[float] = _pz if ax == 0 else _px
		var span_classes: Array[int] = _cls_z if ax == 0 else _cls_x
		for line: int in range(1, lines.size() - 1):
			for interval: int in range(0, spans.size() - 1):
				if not _enabled(ax, line, interval):
					continue
				var lo: int = interval
				var hi: int = interval + 1
				var j0: Variant = _junction_key(ax, line, lo)
				var j1: Variant = _junction_key(ax, line, hi)
				var a0: float = spans[lo] + (ROAD_HALF[span_classes[lo]] if j0 != null else 0.0)
				var a1: float = spans[hi] - (ROAD_HALF[span_classes[hi]] if j1 != null else 0.0)
				var seg: Dictionary = {"ax": ax, "c": lines[line], "cls": classes[line], "a0": a0, "a1": a1, "j0": j0, "j1": j1}
				_segments.append(seg)
				var index: int = _segments.size() - 1
				if j0 != null:   # this segment leaves j0 southwards (ax 0) or eastwards (ax 1)
					(_junctions[j0]["seg"] as Array)[S if ax == 0 else E] = index
				if j1 != null:
					(_junctions[j1]["seg"] as Array)[N if ax == 0 else W] = index


## Key of the junction where line `line` (axis ax) meets the crossing line at index `at`.
func _junction_key(ax: int, line: int, at: int) -> Variant:
	var spans: Array[float] = _pz if ax == 0 else _px
	if at <= 0 or at >= spans.size() - 1:
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


func _on_edge(p: Vector2) -> bool:
	var r: Rect2 = get_rect()
	return is_equal_approx(p.x, r.position.x) or is_equal_approx(p.x, r.end.x) \
		or is_equal_approx(p.y, r.position.y) or is_equal_approx(p.y, r.end.y)


func _is_through(p: Vector3) -> bool:
	for t: Vector2 in through_points:
		if absf(t.x - p.x) < 0.01 and absf(t.y - p.z) < 0.01:
			return true
	return false


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
	var count_x: int = _px.size() - 1
	var count_z: int = _pz.size() - 1
	for iz: int in count_z:
		for ix: int in count_x:
			if _in_merged(_px[ix], _px[ix + 1], _pz[iz], _pz[iz + 1]):
				continue
			_add_block(ix, ix + 1, iz, iz + 1, _cell_kind(_px[ix] - centre.x, _pz[iz] - centre.y))
	for m: Array in _merged():
		_add_block(_px.find(centre.x + float(m[1])), _px.find(centre.x + float(m[2])),
			_pz.find(centre.y + float(m[3])), _pz.find(centre.y + float(m[4])), m[0])


func _in_merged(x0: float, x1: float, z0: float, z1: float) -> bool:
	for m: Array in _merged():
		if centre.x + float(m[1]) <= x0 and x1 <= centre.x + float(m[2]) \
				and centre.y + float(m[3]) <= z0 and z1 <= centre.y + float(m[4]):
			return true
	return false


func _add_block(ix0: int, ix1: int, iz0: int, iz1: int, kind: StringName) -> void:
	var cls: Array[int] = [_cls_x[ix0], _cls_x[ix1], _cls_z[iz0], _cls_z[iz1]]   # w, e, n, s
	var walk: Array[float] = []
	for c: int in cls:
		walk.append(WALK[c] if c >= 0 else 0.0)
	var x0: float = _px[ix0] + (ROAD_HALF[cls[0]] if cls[0] >= 0 else 0.0)
	var x1: float = _px[ix1] - (ROAD_HALF[cls[1]] if cls[1] >= 0 else 0.0)
	var z0: float = _pz[iz0] + (ROAD_HALF[cls[2]] if cls[2] >= 0 else 0.0)
	var z1: float = _pz[iz1] - (ROAD_HALF[cls[3]] if cls[3] >= 0 else 0.0)
	var rect := Rect2(x0, z0, x1 - x0, z1 - z0)
	blocks.append({"rect": rect, "walk": walk, "cls": cls, "kind": kind})
	var interior := Rect2(x0 + walk[0], z0 + walk[2], rect.size.x - walk[0] - walk[1], rect.size.y - walk[2] - walk[3])
	_sidewalks(rect, walk, cls)
	_fill_block(kind, rect, interior, walk, cls)
	_streetlights(rect, walk, cls)


func _lot(kit: StringName, r: Rect2) -> void:
	if r.size.x > 0.05 and r.size.y > 0.05:
		_place(kit, Vector3(r.get_center().x, 0.0, r.get_center().y), 0.0, Vector3(r.size.x, 1.0, r.size.y), &"ground")


## Sidewalk strips along each road-facing side (kerb towards the road) and corner tiles.
func _sidewalks(r: Rect2, walk: Array[float], _cls: Array[int]) -> void:
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
		var at: Vector2 = c[1]
		_place(&"road_walk_corner", Vector3(at.x, 0.0, at.y), float(c[0]), Vector3(wa / 4.0, 1.0, wb / 4.0), &"ground")


func _streetlights(r: Rect2, walk: Array[float], cls: Array[int]) -> void:
	# [road class, kerb normal, start, end, kerb position]
	var sides: Array = [
		[cls[0], Vector3(-1, 0, 0), r.position.y + walk[2], r.end.y - walk[3], r.position.x],
		[cls[1], Vector3(1, 0, 0), r.position.y + walk[2], r.end.y - walk[3], r.end.x],
		[cls[2], Vector3(0, 0, -1), r.position.x + walk[0], r.end.x - walk[1], r.position.y],
		[cls[3], Vector3(0, 0, 1), r.position.x + walk[0], r.end.x - walk[1], r.end.y],
	]
	var kit: StringName = _streetlight_kit()
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
			_place(kit, pos, atan2(-n.z, n.x), Vector3.ONE, &"prop")
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


## Trees in a grid over `interior` (palms with the given chance), with benches facing in.
func _park(interior: Rect2, palm_chance: float = 0.25) -> void:
	var x: float = interior.position.x + 4.0
	while x < interior.end.x - 3.0:
		var z: float = interior.position.y + 4.0
		while z < interior.end.y - 3.0:
			var kit: StringName = &"prop_palm_tree" if _rng.randf() < palm_chance else &"prop_neem_tree"
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


## A stone bench facing +Z rotated by yaw, with two places to sit.
func _bench(pos: Vector3, yaw: float, kind: StringName) -> void:
	_place(&"prop_bench", pos, yaw, Vector3.ONE, kind)
	var basis := Basis(Vector3.UP, yaw)
	for side: float in [-0.45, 0.45]:
		# Feet origin of a seated figure: hips (0.92 m up) just above the 0.47 m seat.
		sit_spots.append({"xform": Transform3D(basis, pos + basis * Vector3(side, -0.41, 0.16)), "kind": kind})


## Special buildings and the places at their doors: each entry [id, ordinary kit it replaces,
## near this point (relative to the centre), its kit, door distance from its centre, optionally a
## radius around the door kept clear of `clearable` props] takes the place of the ordinary
## building of that kit nearest the point (same footprint; the same kit when only the spot is
## needed). Its door spot is recorded in places[id], on the sidewalk facing out.
func _special_buildings(specials: Array, clearable: Array[StringName]) -> void:
	for special: Array in specials:
		var place_id: StringName = special[0]
		var from: StringName = special[1]
		var near: Vector3 = special[2] + Vector3(centre.x, 0.0, centre.y)
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
			push_error("%s: no %s near %s for %s" % [display_name, from, near, place_id])
			continue
		placements[best]["kit"] = special[3]
		var xform: Transform3D = placements[best]["xform"]
		var front: Vector3 = xform.basis.z.normalized()     # buildings face their +Z (Blender -Y)
		var door: Vector3 = xform.origin + front * special[4]
		places[place_id] = Transform3D(Basis.looking_at(front, Vector3.UP), Vector3(door.x, LOT_TOP, door.z))
		var clear: float = float(special[5]) if special.size() > 5 else 0.0
		for i: int in range(placements.size() - 1, -1, -1):
			var kit: StringName = placements[i]["kit"]
			var at: Vector3 = (placements[i]["xform"] as Transform3D).origin
			if clear > 0.0 and kit in clearable and Vector2(at.x - door.x, at.z - door.z).length() < clear:
				placements.remove_at(i)
	for place_id: StringName in places:
		if str(place_id).begins_with("police"):     # the district's police station
			police_station = places[place_id]
			has_police_station = true


# --------------------------------------------------------------------------- signals, crossings

func _build_signals() -> void:
	for jd: Dictionary in _junctions.values():
		if not bool(jd["signalized"]):
			continue
		var at := Vector3(float(jd["x"]), 0.0, float(jd["z"]))
		var heads: Array = []
		for arm: int in 4:
			if not bool((jd["arms"] as Array)[arm]):
				continue
			var out: Vector3 = ARM_DIRS[arm]
			var travel: Vector3 = -out                          # approaching traffic
			var left: Vector3 = Vector3.UP.cross(travel)
			var pos: Vector3 = at + out * (_box_half(jd, arm) + ZEBRA_LENGTH[MAIN] - 0.3) \
				+ left * (_arm_road_half(jd, arm) + 0.8) + Vector3.UP * LOT_TOP
			heads.append([Transform3D(Basis(Vector3.UP, atan2(out.x, out.z)), pos), 0 if arm <= S else 1])
		signals.append({"junction": int(jd["id"]), "position": at, "heads": heads})


func _build_crossings() -> void:
	for jd: Dictionary in _junctions.values():
		var at := Vector2(float(jd["x"]), float(jd["z"]))
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
				var xs: Array[float] = [at.x + out.x * a0, at.x + out.x * a1]
				crossings.append(Rect2(minf(xs[0], xs[1]), at.y - across, absf(a1 - a0), across * 2.0))
			else:
				var zs: Array[float] = [at.y + out.z * a0, at.y + out.z * a1]
				crossings.append(Rect2(at.x - across, minf(zs[0], zs[1]), across * 2.0, absf(a1 - a0)))


# --------------------------------------------------------------------------- lane graph

func _build_lanes(shared: LaneGraphBuilder) -> void:
	var builder: LaneGraphBuilder = shared if shared != null else LaneGraphBuilder.new()
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
				start += _end_room(seg, start) * direction
			if ahead == null:
				stop -= _end_room(seg, stop) * direction
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

	# Where roads end without a junction: a U-turn at a dead end, or (on a road that carries on
	# into the next district) the lane ends the city joins up.
	for s: int in _segments.size():
		var seg: Dictionary = _segments[s]
		for d: int in 2:
			var ahead: Variant = seg["j1"] if d == 0 else seg["j0"]
			if ahead != null:
				continue
			var end_point: Vector3 = _seg_point(seg, float(seg["a1"]) if d == 0 else float(seg["a0"]))
			if _is_through(end_point):
				var out_nodes: Array[int] = []
				var in_nodes: Array[int] = []
				for lane: Array in chains[s][d]:
					out_nodes.append(int(lane[1]))
				for lane: Array in chains[s][1 - d]:
					in_nodes.append(int(lane[0]))
				edge_ends.append({"point": Vector2(end_point.x, end_point.z), "out": out_nodes, "in": in_nodes})
				continue
			var direction: float = 1.0 if d == 0 else -1.0
			var travel: Vector3 = (Vector3(0, 0, direction) if int(seg["ax"]) == 0 else Vector3(direction, 0, 0))
			var back: Array = chains[s][1 - d]
			for k: int in (chains[s][d] as Array).size():
				var lane: Array = chains[s][d][k]
				var back_entry: int = int((back[mini(k, back.size() - 1)] as Array)[0])   # inner to inner, outer to outer
				_link(builder, int(lane[1]), back_entry, travel, 15.0, -1, LaneGraph.Flag.U_TURN, false)
	junction_positions.resize(junction_count)
	for jd: Dictionary in _junctions.values():
		junction_positions[int(jd["id"]) - junction_base] = Vector3(float(jd["x"]), 0.0, float(jd["z"]))
	if shared == null:
		lane_graph = builder.build()
		lane_graph.junction_positions = junction_positions


## How far short of a junction-less road end its lanes stop (see DEAD_END_ROOM, THROUGH_ROOM).
func _end_room(seg: Dictionary, along: float) -> float:
	return THROUGH_ROOM if _is_through(_seg_point(seg, along)) else DEAD_END_ROOM


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
