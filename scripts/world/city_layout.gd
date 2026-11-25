class_name CityLayout
extends RefCounted
## Velanagar (GDD §2, M7): the districts side by side on a grid of 512 m cells, Old Town at the
## centre (cell 0, 0; -Z is north). Each district lays out its own streets (DistrictLayout);
## where a road reaches an edge it shares with a neighbour that has the same road, the two carry
## on into each other and the city joins their lanes, so the whole city has one lane graph.
## Deterministic, like the districts. tools/godot/build_city.gd turns it into chunk scenes.

const CELL: float = 2.0 * DistrictLayout.HALF
const CHUNK_SIZE: float = 128.0
## The coastline (world x): the sea lies east of it (GDD §2), along the Beach District's shore.
const COAST_X: float = CELL + BeachLayout.SHORE

var districts: Array[DistrictLayout] = []
## Everything the districts placed, merged (see DistrictLayout for each entry's format).
var placements: Array[Dictionary] = []
var blocks: Array[Dictionary] = []
var crossings: Array[Rect2] = []
var signals: Array[Dictionary] = []
var sit_spots: Array[Dictionary] = []
var places: Dictionary = {}
var police_stations: Array[Transform3D] = []
var map_labels: Array = []
var water: Array[Rect2] = []
var barriers: Array[Rect2] = []
var beams: Array[Vector3] = []
var lane_graph: LaneGraph
var junction_count: int = 0
## Roads that cross from one district into the next.
var through_count: int = 0


## The districts of the city and where they sit.
static func make_districts() -> Array[DistrictLayout]:
	var old_town := OldTownLayout.new()
	var downtown := DowntownLayout.new()
	downtown.centre = Vector2(0.0, -CELL)
	var beach := BeachLayout.new()
	beach.centre = Vector2(CELL, 0.0)
	return [old_town, downtown, beach]


## The sea (GDD §2: a coastal city): everything east of the coast, out past the edge of the
## city, except land inside a district (its own `water` areas are sea again). World x/z rects.
func sea_rects(margin: float) -> Array[Rect2]:
	var bounds: Rect2 = get_bounds().grow(margin)
	var sea: Array[Rect2] = [Rect2(COAST_X, bounds.position.y, bounds.end.x - COAST_X, bounds.size.y)]
	for d: DistrictLayout in districts:
		sea = _subtract(sea, d.get_rect())
	sea.append_array(water)
	return sea


## What is left of `rects` once `cut` is taken out of each (as up to four rects apiece).
static func _subtract(rects: Array[Rect2], cut: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in rects:
		var i: Rect2 = r.intersection(cut)
		if i.size.x <= 0.0 or i.size.y <= 0.0:
			out.append(r)
			continue
		if i.position.y > r.position.y:
			out.append(Rect2(r.position.x, r.position.y, r.size.x, i.position.y - r.position.y))
		if i.end.y < r.end.y:
			out.append(Rect2(r.position.x, i.end.y, r.size.x, r.end.y - i.end.y))
		if i.position.x > r.position.x:
			out.append(Rect2(r.position.x, i.position.y, i.position.x - r.position.x, i.size.y))
		if i.end.x < r.end.x:
			out.append(Rect2(i.end.x, i.position.y, r.end.x - i.end.x, i.size.y))
	return out


func generate() -> void:
	districts = make_districts()
	var base: int = 0
	for d: DistrictLayout in districts:
		d.junction_base = base
		d.plan()
		base += d.junction_count
	junction_count = base
	_find_through_roads()
	var builder := LaneGraphBuilder.new()
	for d: DistrictLayout in districts:
		d.build(builder)
	_join_lanes(builder)
	lane_graph = builder.build()
	var centres := PackedVector3Array()
	for d: DistrictLayout in districts:
		centres.append_array(d.junction_positions)
	lane_graph.junction_positions = centres
	for d: DistrictLayout in districts:
		placements.append_array(d.placements)
		blocks.append_array(d.blocks)
		crossings.append_array(d.crossings)
		signals.append_array(d.signals)
		sit_spots.append_array(d.sit_spots)
		map_labels.append_array(d.map_labels)
		water.append_array(d.water)
		barriers.append_array(d.barriers)
		beams.append_array(d.beams)
		for place_id: StringName in d.places:
			if places.has(place_id):
				push_error("CityLayout: two districts have a place called %s" % place_id)
			places[place_id] = d.places[place_id]
		if d.has_police_station:
			police_stations.append(d.police_station)


## The rectangle around every district (world x/z), a whole number of chunks.
func get_bounds() -> Rect2:
	var r: Rect2 = districts[0].get_rect()
	for d: DistrictLayout in districts:
		r = r.merge(d.get_rect())
	return r


func chunk_count() -> Vector2i:
	var b: Rect2 = get_bounds()
	return Vector2i(roundi(b.size.x / CHUNK_SIZE), roundi(b.size.y / CHUNK_SIZE))


## The chunk a point is in (clamped to the grid).
func chunk_of(x: float, z: float) -> Vector2i:
	var b: Rect2 = get_bounds()
	var count: Vector2i = chunk_count()
	return Vector2i(clampi(floori((x - b.position.x) / CHUNK_SIZE), 0, count.x - 1),
		clampi(floori((z - b.position.y) / CHUNK_SIZE), 0, count.y - 1))


func chunk_rect(coord: Vector2i) -> Rect2:
	return Rect2(get_bounds().position + Vector2(coord) * CHUNK_SIZE, Vector2(CHUNK_SIZE, CHUNK_SIZE))


## Chunks inside a district (the ones that get a scene).
func district_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var count: Vector2i = chunk_count()
	for cz: int in count.y:
		for cx: int in count.x:
			var c := Vector2i(cx, cz)
			if district_at(chunk_rect(c).get_center()) != null:
				out.append(c)
	return out


func district_at(p: Vector2) -> DistrictLayout:
	for d: DistrictLayout in districts:
		if d.get_rect().has_point(p):
			return d
	return null


## District edges that face no other district (the edge of the city): [from, to] world x/z.
func outer_edges() -> Array:
	var out: Array = []
	for d: DistrictLayout in districts:
		var r: Rect2 = d.get_rect()
		var corners: Array[Vector2] = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		for k: int in 4:
			var a: Vector2 = corners[k]
			var b: Vector2 = corners[(k + 1) % 4]
			var mid: Vector2 = (a + b) * 0.5
			var outward: Vector2 = (mid - r.get_center()).normalized()
			if district_at(mid + outward * 1.0) == null:
				out.append([a, b])
	return out


## Roads that reach a shared edge in both neighbours (same place, same class) carry on.
func _find_through_roads() -> void:
	for i: int in districts.size():
		for j: int in range(i + 1, districts.size()):
			var a: DistrictLayout = districts[i]
			var b: DistrictLayout = districts[j]
			if not a.get_rect().grow(0.5).intersects(b.get_rect()):
				continue
			var b_roads: Array[Dictionary] = b.edge_roads()
			for ea: Dictionary in a.edge_roads():
				for eb: Dictionary in b_roads:
					if (ea["point"] as Vector2).distance_to(eb["point"]) < 0.01 and int(ea["cls"]) == int(eb["cls"]):
						a.through_points.append(ea["point"])
						b.through_points.append(eb["point"])
						through_count += 1


## Joins the lanes of each road that crosses between districts: every lane leaving one side
## continues into the same lane on the other.
func _join_lanes(builder: LaneGraphBuilder) -> void:
	var ends: Dictionary = {}    # Vector2i (decimetres) -> [edge end, edge end]
	for d: DistrictLayout in districts:
		for e: Dictionary in d.edge_ends:
			var p: Vector2 = e["point"]
			var key := Vector2i(roundi(p.x * 10.0), roundi(p.y * 10.0))
			if not ends.has(key):
				ends[key] = []
			(ends[key] as Array).append(e)
	for key: Vector2i in ends:
		var pair: Array = ends[key]
		if pair.size() != 2:
			push_error("CityLayout: road crossing at %s has %d ends" % [key, pair.size()])
			continue
		for k: int in 2:
			var from: Dictionary = pair[k]
			var to: Dictionary = pair[1 - k]
			for lane: int in (from["out"] as Array).size():
				builder.connect_nodes(int(from["out"][lane]), int(to["in"][lane]))
