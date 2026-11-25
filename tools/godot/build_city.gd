extends SceneTree
## Builds the streamed city of Velanagar (M3's Old Town builder, grown in M7 to every district)
## from the Blender kit:
##   1. bakes every model the city uses into a one-draw-call mesh in assets/world/kit/ (KitBaker),
##   2. lays out the city (CityLayout: the districts side by side, deterministic),
##   3. writes one scene per 128 m chunk inside a district to scenes/world/chunks/city/: ground
##      tiles and props as MultiMeshes, buildings, occluders (as data, see OccluderBatch), traffic
##      signals, simple convex collision and the baked pedestrian navmesh for that chunk,
##   4. writes the always-loaded landmark scene (the temple, the skyline stand-ins for the tall
##      towers, the walls and ground around the edge of the city), the lane graph, the city map
##      and the manifest (CityData).
## Re-run after changing a layout or any Blender asset the city uses (after an import):
##   "$GODOT" --headless --path . --script res://tools/godot/build_city.gd

const KIT_DIR: String = "res://assets/world/kit/"
const OUT_DIR: String = "res://scenes/world/chunks/city/"
const LANDMARKS_PATH: String = OUT_DIR + "landmarks.scn"
const LANES_PATH: String = "res://resources/world/city_lanes.res"
const CITY_PATH: String = "res://resources/world/city.tres"
const MATERIAL_PATH: String = KIT_DIR + "palette_material.tres"
const SHADER_PATH: String = "res://shaders/palette_lit.gdshader"
const SIGNAL_POLE_PATH: String = "res://assets/models/props/prop_signal_pole.glb"
const SIGNAL_TIMING_PATH: String = "res://resources/world/signal_timing.tres"
const LOT_COLOURS: Dictionary = {
	&"lot_paved": Color("8e897f"), &"lot_warm": Color("a08a70"), &"lot_stone": Color("a39581"), &"lot_grass": Color("5f7d3c"),
	&"lot_plaza": Color("aba79f"),
}
## The city map (GDD §11): drawn from the layout, 4 pixels per metre, flat game-map colours,
## saved as a small lossless PNG. Its import settings (MAP_IMPORT, written if missing) have Godot
## block-compress it for the GPU, so the whole city fits in a few MB of video memory.
const MAP_PATH: String = "res://assets/world/maps/city_map.png"
const MAP_IMPORT: String = "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\nmipmaps/generate=false\ndetect_3d/compress_to=0\n"
const MAP_PIXELS_PER_METRE: int = 4
const MAP_COLOURS: Dictionary = {
	"empty": Color("10131c"), "lot_paved": Color("1d2230"), "lot_stone": Color("2c2a33"),
	"lot_warm": Color("302820"), "lot_grass": Color("1d3b2a"), "lot_plaza": Color("252a38"), "walk": Color("2a3142"),
	"road_main": Color("566079"), "road_lane": Color("414960"), "building": Color("353d53"),
	"building_edge": Color("4d5877"), "tower": Color("3c4a66"), "tower_edge": Color("6a7fa6"),
	"temple": Color("6e4c36"), "temple_edge": Color("9a6a46"),
	"market": Color("5b4433"), "water": Color("1f5b8c"), "tree": Color("2f6b45"),
}
## Static world collision layer, and a private layer for the navmesh source shapes.
const WORLD_LAYER: int = 1
const NAV_SOURCE_LAYER: int = 1 << 30
const BUILDING_VISIBILITY: float = 280.0
const PROP_VISIBILITY: float = 200.0
## Buildings at least this tall get a simple stand-in on the always-loaded skyline (M7), so
## Downtown's towers stay on the horizon when their chunks aren't loaded. The stand-in follows
## the building's collision boxes, starts above the street-level lobby and sits a little inside
## the real walls (hidden whenever the real building is there).
const SKYLINE_MIN_HEIGHT: float = 30.0
const SKYLINE_BASE: float = 6.0
const SKYLINE_INSET: float = 0.5
## The average wall colour counts the light frames and fins as much as the dark glass; seen from
## afar the towers read darker than that.
const SKYLINE_SHADE: float = 0.6
## Ground and walls around the city's edge.
const SURROUND_MARGIN: float = 1000.0
const SURROUND_COLOUR := Color(0.41, 0.44, 0.25)
const CITY_GROUND_COLOUR := Color(0.44, 0.43, 0.41)
const EDGE_WALL_HEIGHT: float = 12.0

var _material: ShaderMaterial
var _kit: Dictionary = {}          # StringName -> KitPiece (mesh saved in KIT_DIR)
var _layout: CityLayout
var _solids: Array = []            # [ConvexPolygonShape3D, AABB] for every non-ground placement hull
var _stats: Dictionary = {"buildings": 0, "props": 0, "ground": 0, "shapes": 0, "nav_polys": 0, "signals": 0, "skyline": 0}


func _initialize() -> void:
	# The scene tree only runs from the first frame on (navmesh parsing needs it), so build then.
	_run.call_deferred()


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(KIT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_material = _make_material()
	_layout = CityLayout.new()
	_layout.generate()
	if not _bake_kit():
		quit(1)
		return
	_collect_solids()
	var timing := load(SIGNAL_TIMING_PATH) as SignalTiming
	var pole := load(SIGNAL_POLE_PATH) as PackedScene
	var chunks: Array[Vector2i] = _layout.district_chunks()
	for coord: Vector2i in chunks:
		if not _build_chunk(coord, timing, pole):
			quit(1)
			return
	if not _build_landmarks():
		quit(1)
		return
	var err: Error = ResourceSaver.save(_layout.lane_graph, LANES_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("build_city: could not save the lane graph (%d)" % err)
		quit(1)
		return
	if not _write_map():
		quit(1)
		return
	var city := CityData.new()
	city.display_name = "Velanagar"
	city.map_texture_path = MAP_PATH
	city.police_stations = _layout.police_stations.duplicate()
	city.places = _layout.places.duplicate()
	for label: Array in _layout.map_labels:
		city.map_label_texts.append(label[0])
		city.map_label_positions.append(label[1])
	for d: DistrictLayout in _layout.districts:
		city.region_ids.append(str(d.id))
		city.region_names.append(d.display_name)
		city.region_rects.append(d.get_rect())
	var bounds: Rect2 = _layout.get_bounds()
	city.chunk_size = CityLayout.CHUNK_SIZE
	city.origin = bounds.position
	city.chunk_count = _layout.chunk_count()
	city.chunks = chunks
	city.chunk_path_format = OUT_DIR + "chunk_%d_%d.scn"
	city.lane_graph = load(LANES_PATH) as LaneGraph
	err = ResourceSaver.save(city, CITY_PATH)
	if err != OK:
		push_error("build_city: could not save the city (%d)" % err)
		quit(1)
		return
	var lanes: LaneGraph = _layout.lane_graph
	var names: PackedStringArray = PackedStringArray()
	for d: DistrictLayout in _layout.districts:
		names.append(d.display_name)
	print("build_city: districts %s, %d roads between them" % [", ".join(names), _layout.through_count])
	print("build_city: %d chunks, %d buildings, %d props, %d ground tiles, %d collision shapes, %d navmesh polygons, %d skyline stand-ins" % [
		chunks.size(), _stats["buildings"], _stats["props"], _stats["ground"], _stats["shapes"], _stats["nav_polys"], _stats["skyline"]])
	print("build_city: %d junctions (%d with traffic lights), %d crossings, lane graph %d nodes (%d disconnected), %d kit meshes, %d police stations" % [
		_layout.junction_count, _stats["signals"], _layout.crossings.size(), lanes.size(), lanes.count_disconnected(), _kit.size(),
		_layout.police_stations.size()])
	print("build_city: done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit(0)


# --------------------------------------------------------------------------- map

## Draws the city from above into MAP_PATH: lots, sidewalks, roads (main roads brighter),
## buildings (temple buildings warm, towers blue), the tank's water and trees.
func _write_map() -> bool:
	var bounds: Rect2 = _layout.get_bounds()
	var image := Image.create(int(bounds.size.x) * MAP_PIXELS_PER_METRE, int(bounds.size.y) * MAP_PIXELS_PER_METRE, false, Image.FORMAT_RGB8)
	image.fill(MAP_COLOURS["empty"])
	var layers: Array[Array] = [[], [], [], [], []]      # lots, walks, roads, buildings, trees
	for p: Dictionary in _layout.placements:
		var kit: String = str(p["kit"])
		if kit.begins_with("lot_"):
			layers[0].append(p)
		elif kit.begins_with("road_walk"):
			layers[1].append(p)
		elif kit.begins_with("road_"):
			layers[2].append(p)
		elif p["kind"] == &"building" or p["kind"] == &"landmark" and kit.begins_with("bld_"):
			layers[3].append(p)
		elif kit == "prop_neem_tree" or kit == "prop_palm_tree":
			layers[4].append(p)
	for p: Dictionary in layers[0]:
		_map_fill(image, bounds, _map_rect(p), MAP_COLOURS.get(str(p["kit"]), MAP_COLOURS["lot_paved"]))
	for p: Dictionary in layers[1]:
		_map_fill(image, bounds, _map_rect(p), MAP_COLOURS["walk"])
	for p: Dictionary in layers[2]:
		var kit: String = str(p["kit"])
		var main: bool = kit.contains("main") or kit.ends_with("_mm") or kit.ends_with("_ml")
		_map_fill(image, bounds, _map_rect(p), MAP_COLOURS["road_main" if main else "road_lane"])
	for p: Dictionary in layers[3]:
		var kit: String = str(p["kit"])
		var rect: Rect2 = _map_rect(p)
		if kit == "bld_ot_tank":
			_map_fill(image, bounds, rect, MAP_COLOURS["lot_stone"])
			_map_fill(image, bounds, rect.grow(-6.0), MAP_COLOURS["water"])
			continue
		var temple: bool = kit.contains("temple") or kit.contains("vimana") or kit.contains("mandapam")
		var market: bool = kit.contains("market")
		var tower: bool = (_kit[p["kit"]] as KitPiece).bounds.end.y >= SKYLINE_MIN_HEIGHT
		var edge: Color = MAP_COLOURS["temple_edge"] if temple else (MAP_COLOURS["tower_edge"] if tower else MAP_COLOURS["building_edge"])
		var fill: Color = MAP_COLOURS["temple"] if temple else (MAP_COLOURS["market"] if market else (MAP_COLOURS["tower"] if tower else MAP_COLOURS["building"]))
		_map_fill(image, bounds, rect, edge)
		_map_fill(image, bounds, rect.grow(-0.4), fill)
	for p: Dictionary in layers[4]:
		var o: Vector3 = (p["xform"] as Transform3D).origin
		_map_fill(image, bounds, Rect2(o.x - 1.5, o.z - 1.5, 3.0, 3.0), MAP_COLOURS["tree"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_PATH.get_base_dir()))
	var import_path: String = ProjectSettings.globalize_path(MAP_PATH + ".import")
	if not FileAccess.file_exists(import_path):
		var file := FileAccess.open(import_path, FileAccess.WRITE)
		if file != null:
			file.store_string(MAP_IMPORT)
			file.close()
	var err: Error = image.save_png(ProjectSettings.globalize_path(MAP_PATH))
	if err != OK:
		push_error("build_city: could not save the map (%d)" % err)
		return false
	return true


## A placement's footprint (its piece's bounds, transformed) as a world X/Z rectangle.
func _map_rect(p: Dictionary) -> Rect2:
	var b: AABB = (_kit[p["kit"]] as KitPiece).bounds
	var xform: Transform3D = p["xform"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k: int in 8:
		var corner: Vector3 = xform * b.get_endpoint(k)
		lo = Vector2(minf(lo.x, corner.x), minf(lo.y, corner.z))
		hi = Vector2(maxf(hi.x, corner.x), maxf(hi.y, corner.z))
	return Rect2(lo, hi - lo)


func _map_fill(image: Image, bounds: Rect2, world: Rect2, colour: Color) -> void:
	var scale: float = MAP_PIXELS_PER_METRE
	var x0: int = clampi(roundi((world.position.x - bounds.position.x) * scale), 0, image.get_width())
	var y0: int = clampi(roundi((world.position.y - bounds.position.y) * scale), 0, image.get_height())
	var x1: int = clampi(roundi((world.end.x - bounds.position.x) * scale), 0, image.get_width())
	var y1: int = clampi(roundi((world.end.y - bounds.position.y) * scale), 0, image.get_height())
	if x1 > x0 and y1 > y0:
		image.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), colour)


# --------------------------------------------------------------------------- kit

func _make_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	ResourceSaver.save(mat, MATERIAL_PATH)
	return load(MATERIAL_PATH) as ShaderMaterial


func _bake_kit() -> bool:
	var names: Array[StringName] = []
	for p: Dictionary in _layout.placements:
		if not names.has(p["kit"]):
			names.append(p["kit"])
	names.sort()
	for kit_name: StringName in names:
		var piece: KitPiece
		if LOT_COLOURS.has(kit_name):
			piece = KitPiece.new()
			piece.mesh = _lot_quad(LOT_COLOURS[kit_name])
			piece.bounds = piece.mesh.get_aabb()
		else:
			var path: String = _glb_path(kit_name)
			if not ResourceLoader.exists(path):
				push_error("build_city: missing model %s" % path)
				return false
			piece = KitBaker.bake(load(path) as PackedScene, _material)
		var mesh_path: String = KIT_DIR + str(kit_name) + ".res"
		var err: Error = ResourceSaver.save(piece.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("build_city: could not save %s (%d)" % [mesh_path, err])
			return false
		piece.mesh = load(mesh_path) as ArrayMesh
		_kit[kit_name] = piece
	return true


func _glb_path(kit_name: StringName) -> String:
	var n: String = str(kit_name)
	var folder: String = "road" if n.begins_with("road_") else ("props" if n.begins_with("prop_") else "buildings")
	return "res://assets/models/%s/%s.glb" % [folder, n]


## A 1 x 1 m patch of lot ground at sidewalk height, coloured for the palette material.
func _lot_quad(colour: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var y: float = DistrictLayout.LOT_TOP
	var corners: Array[Vector3] = [Vector3(-0.5, y, -0.5), Vector3(0.5, y, -0.5), Vector3(0.5, y, 0.5), Vector3(-0.5, y, 0.5)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(colour.srgb_to_linear())
		st.set_uv2(Vector2(0.95, 0.0))
		st.set_custom(0, Color(0, 0, 0))
		st.set_normal(Vector3.UP)
		st.add_vertex(corners[i])
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _material)
	return mesh


# --------------------------------------------------------------------------- navmesh

func _nav_template() -> NavigationMesh:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = NAV_SOURCE_LAYER
	nav.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav.cell_size = 0.25
	nav.cell_height = 0.1        # matches navigation/3d/default_cell_height (setup_project.gd)
	nav.agent_height = 2.0      # multiples of the 0.25 m cells
	nav.agent_radius = 0.5
	nav.agent_max_climb = 0.3
	nav.agent_max_slope = 40.0
	nav.edge_max_error = 1.0
	nav.border_size = 1.0
	return nav


## Every hull of everything standing on the ground (buildings, props, landmarks), placed in the
## world, with its bounding box: the solid part of the navmesh source.
func _collect_solids() -> void:
	for p: Dictionary in _layout.placements:
		if p["kind"] == &"ground":
			continue
		for hull: PackedVector3Array in (_kit[p["kit"]] as KitPiece).hulls:
			var shape: ConvexPolygonShape3D = _hull_shape(hull, p["xform"])
			if shape != null:
				_solids.append([shape, _points_aabb(shape.points)])


## The navmesh source around one area: walkable ground (block slabs and the crossings over roads)
## plus everything standing on it. Roads themselves are left out, so people only cross them at
## crossings. Only what reaches into `area` goes in, so each chunk's bake stays small.
func _nav_source(area: Rect2) -> NavigationMeshSourceGeometryData3D:
	var root := Node3D.new()
	root.name = "NavSource"
	get_root().add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = NAV_SOURCE_LAYER
	root.add_child(body)
	for b: Dictionary in _layout.blocks:
		if (b["rect"] as Rect2).intersects(area):
			_add_shape(body, _block_hull(b["rect"], b["walk"], b["rect"]))
	for r: Rect2 in _layout.crossings:
		if r.intersects(area):
			var box := BoxShape3D.new()
			box.size = Vector3(r.size.x, 0.2, r.size.y)
			_add_shape(body, box, Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, -0.1, r.get_center().y)))
	var solids: Array[ConvexPolygonShape3D] = []
	for s: Array in _solids:
		var box: AABB = s[1]
		if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(area):
			_add_shape(body, s[0])
			solids.append(s[0])
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_nav_template(), source, root)
	root.free()
	# Recast only sees surfaces: a closed hull's floor face, with its roof cut off by the bake's
	# height filter, reads as open floor, which left a walkable island inside every building.
	# Marking each hull's footprint as solid (over its own height range only, so the floor under
	# a raised roof stays walkable) keeps the navmesh outside.
	for shape: ConvexPolygonShape3D in solids:
		_add_obstruction(source, shape.points)
	return source


func _add_obstruction(source: NavigationMeshSourceGeometryData3D, points: PackedVector3Array) -> void:
	var flat := PackedVector2Array()
	var low: float = INF
	var high: float = -INF
	for p: Vector3 in points:
		flat.append(Vector2(p.x, p.z))
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var outline: PackedVector2Array = Geometry2D.convex_hull(flat)
	if outline.size() < 4:     # convex_hull repeats the first point at the end
		return
	var vertices := PackedVector3Array()
	for k: int in outline.size() - 1:
		vertices.append(Vector3(outline[k].x, low, outline[k].y))
	source.add_projected_obstruction(vertices, low - 0.3, high - low + 0.3, false)


# --------------------------------------------------------------------------- chunks

func _build_chunk(coord: Vector2i, timing: SignalTiming, pole: PackedScene) -> bool:
	var rect: Rect2 = _layout.chunk_rect(coord)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	var ground := _child(root, root, Node3D.new(), "Ground")
	var buildings := _child(root, root, Node3D.new(), "Buildings")
	var props := _child(root, root, Node3D.new(), "Props")
	var occluder_boxes: Array = []
	var signals := _child(root, root, Node3D.new(), "Signals")
	var body := _child(root, root, StaticBody3D.new(), "Collision") as StaticBody3D
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0

	# Ground under the roads: one slab for the whole chunk, top at road level.
	var slab := BoxShape3D.new()
	slab.size = Vector3(rect.size.x, 1.0, rect.size.y)
	_own_shape(root, body, slab, Transform3D(Basis.IDENTITY, Vector3(rect.get_center().x, -0.5, rect.get_center().y)))
	# Raised blocks (sidewalks and lots), clipped to the chunk, kerbs bevelled for walking up.
	for b: Dictionary in _layout.blocks:
		var part: Rect2 = (b["rect"] as Rect2).intersection(rect)
		if part.size.x > 0.01 and part.size.y > 0.01:
			_own_shape(root, body, _block_hull(part, b["walk"], b["rect"]))

	var multimesh: Dictionary = {}   # kit -> Array[Transform3D]
	var index: int = 0
	for p: Dictionary in _layout.placements:
		var xform: Transform3D = p["xform"]
		if p["kind"] == &"landmark" or _layout.chunk_of(xform.origin.x, xform.origin.z) != coord:
			continue
		var piece: KitPiece = _kit[p["kit"]]
		if p["kind"] == &"building":
			var mi := MeshInstance3D.new()
			mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mi.mesh = piece.mesh
			mi.transform = xform
			mi.visibility_range_end = BUILDING_VISIBILITY
			_child(root, buildings, mi, "B%03d_%s" % [index, str(p["kit"]).trim_prefix("bld_")])
			var box: Array = _occluder_box(piece, xform)
			if not box.is_empty():
				occluder_boxes.append(box)
			_stats["buildings"] += 1
			index += 1
		else:
			if not multimesh.has(p["kit"]):
				multimesh[p["kit"]] = []
			(multimesh[p["kit"]] as Array).append(xform)
			_stats["ground" if p["kind"] == &"ground" else "props"] += 1
		for hull: PackedVector3Array in piece.hulls:
			var shape: ConvexPolygonShape3D = _hull_shape(hull, xform)
			if shape != null:
				_own_shape(root, body, shape)
	for kit_name: StringName in multimesh:
		var is_ground: bool = str(kit_name).begins_with("road_") or str(kit_name).begins_with("lot_")
		var mmi: InstanceBatch = _multimesh(_kit[kit_name], multimesh[kit_name])
		if is_ground:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.visibility_range_end = PROP_VISIBILITY
		_child(root, ground if is_ground else props, mmi, str(kit_name))
	var occluders := OccluderBatch.new()
	occluders.boxes = OccluderBatch.pack(occluder_boxes)
	_child(root, root, occluders, "Occluders")

	for s: Dictionary in _layout.signals:
		var centre: Vector3 = s["position"]
		if _layout.chunk_of(centre.x, centre.z) != coord:
			continue
		var sig := TrafficSignal.new()
		sig.junction_id = int(s["junction"])
		sig.timing = timing
		sig.time_offset = fposmod(float(s["junction"]) * 7.3, timing.cycle_seconds())
		sig.position = centre
		_child(root, signals, sig, "Signal_%d" % int(s["junction"]))
		var k: int = 0
		for head: Array in s["heads"]:
			var head_xform: Transform3D = head[0]
			var instance := pole.instantiate() as Node3D
			instance.transform = Transform3D(head_xform.basis, head_xform.origin - centre)
			instance.set_meta(&"signal_axis", int(head[1]))
			instance.name = "Pole%d" % k
			sig.add_child(instance)
			instance.owner = root
			k += 1
		_stats["signals"] += 1

	_add_sit_spots(root, &"prop", coord)

	var region := NavigationRegion3D.new()
	var nav: NavigationMesh = _nav_template()
	# Bake the chunk grown by the border size: the border is trimmed off again, which leaves edges
	# exactly on the chunk boundary, so neighbouring chunks' navmeshes join up.
	var grown: Rect2 = rect.grow(nav.border_size)
	# Only street level (to 2.6 m: a person's height above the sidewalks), so rooftops never become
	# unreachable islands of navmesh.
	nav.filter_baking_aabb = AABB(Vector3(grown.position.x, -2.0, grown.position.y), Vector3(grown.size.x, 4.6, grown.size.y))
	NavigationServer3D.bake_from_source_geometry_data(nav, _nav_source(rect.grow(4.0)))
	region.navigation_mesh = nav
	_child(root, root, region, "Navigation")
	_stats["nav_polys"] += nav.get_polygon_count()

	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + "chunk_%d_%d.scn" % [coord.x, coord.y], ResourceSaver.FLAG_COMPRESS)
	root.free()
	if err != OK:
		push_error("build_city: could not save chunk %s (%d)" % [coord, err])
		return false
	return true


## Always loaded: the temple compound (the gopurams stay on the skyline from anywhere), the
## skyline stand-ins for the tall towers, and the edge of the city (walls you can't drive
## through, a safety floor, and plain ground stretching away beyond).
func _build_landmarks() -> bool:
	var root := Node3D.new()
	root.name = "CityLandmarks"
	var visuals := _child(root, root, Node3D.new(), "Temple")
	var body := _child(root, root, StaticBody3D.new(), "Collision") as StaticBody3D
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	_add_sit_spots(root, &"landmark", Vector2i(-1, -1))
	var groups: Dictionary = {}
	for p: Dictionary in _layout.placements:
		if p["kind"] != &"landmark":
			continue
		if not groups.has(p["kit"]):
			groups[p["kit"]] = []
		(groups[p["kit"]] as Array).append(p["xform"])
		for hull: PackedVector3Array in (_kit[p["kit"]] as KitPiece).hulls:
			var shape: ConvexPolygonShape3D = _hull_shape(hull, p["xform"])
			if shape != null:
				_own_shape(root, body, shape)
	for kit_name: StringName in groups:
		var xforms: Array = groups[kit_name]
		if xforms.size() >= 3:
			_child(root, visuals, _multimesh(_kit[kit_name], xforms), str(kit_name))
		else:
			for k: int in xforms.size():
				var mi := MeshInstance3D.new()
				mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				mi.mesh = (_kit[kit_name] as KitPiece).mesh
				mi.transform = xforms[k]
				_child(root, visuals, mi, "%s_%d" % [str(kit_name), k])
	var skyline: ArrayMesh = _skyline_mesh()
	if skyline != null:
		var mi := MeshInstance3D.new()
		mi.mesh = skyline
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_child(root, root, mi, "Skyline")
	_build_edge(root)
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LANDMARKS_PATH, ResourceSaver.FLAG_COMPRESS)
	root.free()
	if err != OK:
		push_error("build_city: could not save the landmarks (%d)" % err)
	return err == OK


## Walls along every district edge that faces no other district, a safety floor under the whole
## city, and flat ground beyond the edge (around the city and in any empty cell inside it).
func _build_edge(root: Node3D) -> void:
	var edge := _child(root, root, StaticBody3D.new(), "CityEdge") as StaticBody3D
	edge.collision_layer = WORLD_LAYER
	edge.collision_mask = 0
	var bounds: Rect2 = _layout.get_bounds()
	for e: Array in _layout.outer_edges():
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var mid: Vector2 = (a + b) * 0.5
		var inward: Vector2 = Vector2.ZERO
		for d: DistrictLayout in _layout.districts:
			var r: Rect2 = d.get_rect()
			if r.grow(0.01).has_point(mid):
				inward = (r.get_center() - mid).normalized()
		var along: bool = absf(b.x - a.x) > absf(b.y - a.y)
		var box := BoxShape3D.new()
		box.size = Vector3(absf(b.x - a.x) + 4.0, EDGE_WALL_HEIGHT, 2.0) if along else Vector3(2.0, EDGE_WALL_HEIGHT, absf(b.y - a.y) + 4.0)
		var at: Vector2 = mid - inward * 1.0
		_own_shape(root, edge, box, Transform3D(Basis.IDENTITY, Vector3(at.x, EDGE_WALL_HEIGHT * 0.5 - 1.0, at.y)))
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(bounds.size.x + 200.0, 2.0, bounds.size.y + 200.0)
	_own_shape(root, edge, floor_box, Transform3D(Basis.IDENTITY, Vector3(bounds.get_center().x, -4.0, bounds.get_center().y)))

	var surround := _child(root, root, Node3D.new(), "Surroundings")
	var material := StandardMaterial3D.new()
	material.albedo_color = SURROUND_COLOUR
	material.roughness = 1.0
	var m: float = SURROUND_MARGIN
	var rects: Array[Rect2] = [
		Rect2(bounds.position.x - m, bounds.position.y - m, bounds.size.x + 2.0 * m, m),
		Rect2(bounds.position.x - m, bounds.end.y, bounds.size.x + 2.0 * m, m),
		Rect2(bounds.position.x - m, bounds.position.y, m, bounds.size.y),
		Rect2(bounds.end.x, bounds.position.y, m, bounds.size.y),
	]
	var cells: Vector2i = Vector2i(roundi(bounds.size.x / CityLayout.CELL), roundi(bounds.size.y / CityLayout.CELL))
	for cz: int in cells.y:
		for cx: int in cells.x:
			var cell := Rect2(bounds.position + Vector2(cx, cz) * CityLayout.CELL, Vector2(CityLayout.CELL, CityLayout.CELL))
			if _layout.district_at(cell.get_center()) == null:
				rects.append(cell)
	# Under the districts too, a little below the road surface: where a chunk isn't loaded (seen
	# from a rooftop, or from afar) the skyline stands on plain ground instead of nothing.
	var under := StandardMaterial3D.new()
	under.albedo_color = CITY_GROUND_COLOUR
	under.roughness = 1.0
	for d: DistrictLayout in _layout.districts:
		var plane := PlaneMesh.new()
		plane.size = d.get_rect().size
		plane.material = under
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position = Vector3(d.centre.x, -0.08, d.centre.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_child(root, surround, mi, "Under_%s" % d.id)
	var k: int = 0
	for r: Rect2 in rects:
		var plane := PlaneMesh.new()
		plane.size = r.size
		plane.material = material
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position = Vector3(r.get_center().x, -0.03, r.get_center().y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_child(root, surround, mi, "Ground%d" % k)
		k += 1


# --------------------------------------------------------------------------- skyline

## One mesh with a simple stand-in for every tall building: its collision boxes (above the
## lobby, a little inside the walls) in the building's average wall colour, in 3 m floor bands
## that glow at night where the building has lit windows (each floor lit or dark at random).
func _skyline_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var looks: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var any: bool = false
	for p: Dictionary in _layout.placements:
		if p["kind"] != &"building":
			continue
		var piece: KitPiece = _kit[p["kit"]]
		if piece.bounds.end.y < SKYLINE_MIN_HEIGHT:
			continue
		if not looks.has(p["kit"]):
			looks[p["kit"]] = _wall_look(piece.mesh)
		var look: Dictionary = looks[p["kit"]]
		var xform: Transform3D = p["xform"]
		for hull: PackedVector3Array in piece.hulls:
			var box: AABB = _points_aabb(hull)
			var y0: float = maxf(box.position.y, SKYLINE_BASE)
			var y1: float = box.end.y - 0.3
			if y1 - y0 < 1.0 or box.size.x < 2.0 * SKYLINE_INSET + 1.0 or box.size.z < 2.0 * SKYLINE_INSET + 1.0:
				continue
			var x0: float = box.position.x + SKYLINE_INSET
			var x1: float = box.end.x - SKYLINE_INSET
			var z0: float = box.position.z + SKYLINE_INSET
			var z1: float = box.end.z - SKYLINE_INSET
			var y: float = y0
			while y < y1 - 0.01:
				var top: float = minf(y + 3.0, y1)
				var glow := Color(0, 0, 0, 0)
				if float(look["windows"]) > 0.0:
					var h: float = rng.randf()
					if h >= 0.35:
						glow = (look["emission"] as Color) * lerpf(0.55, 1.0, h)
						glow.a = 1.0     # glows at night only
				_skyline_band(st, xform, x0, x1, z0, z1, y, top, look["albedo"], glow)
				y = top
			_skyline_quad(st, xform, [Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0)],
				look["albedo"], Color(0, 0, 0, 0))
			any = true
		_stats["skyline"] += 1
	if not any:
		return null
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _material)
	return mesh


func _skyline_band(st: SurfaceTool, xform: Transform3D, x0: float, x1: float, z0: float, z1: float,
		y0: float, y1: float, albedo: Color, glow: Color) -> void:
	_skyline_quad(st, xform, [Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)], albedo, glow)
	_skyline_quad(st, xform, [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)], albedo, glow)
	_skyline_quad(st, xform, [Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)], albedo, glow)
	_skyline_quad(st, xform, [Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1)], albedo, glow)


## Adds a quad (corners counter-clockwise seen from outside) in world space.
func _skyline_quad(st: SurfaceTool, xform: Transform3D, corners: Array, albedo: Color, glow: Color) -> void:
	var w: Array[Vector3] = []
	for c: Vector3 in corners:
		w.append(xform * c)
	var normal: Vector3 = (w[1] - w[0]).cross(w[2] - w[0]).normalized()
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(Color(albedo.r, albedo.g, albedo.b, 1.0))
		st.set_uv2(Vector2(0.35, 0.45))     # glassy, like the towers they stand in for
		st.set_custom(0, glow)
		st.set_normal(normal)
		st.add_vertex(w[i])


## A building's average wall colour (area-weighted over its upright faces), and whether and how
## its windows glow: {albedo: Color (linear), windows: float (share of lit-window area), emission}.
func _wall_look(mesh: ArrayMesh) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var count: int = indices.size() if not indices.is_empty() else verts.size()
	var total: float = 0.0
	var window_area: float = 0.0
	var albedo := Color(0, 0, 0)
	var emission := Color(0, 0, 0)
	for t: int in range(0, count, 3):
		var i0: int = indices[t] if not indices.is_empty() else t
		var i1: int = indices[t + 1] if not indices.is_empty() else t + 1
		var i2: int = indices[t + 2] if not indices.is_empty() else t + 2
		var cross: Vector3 = (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		var area: float = cross.length() * 0.5
		if area <= 0.0 or absf(cross.normalized().y) > 0.3:
			continue
		total += area
		albedo += colours[i0] * area
		if custom.size() >= (i0 + 1) * 4 and custom[i0 * 4 + 3] > 1.5:
			window_area += area
			emission += Color(custom[i0 * 4], custom[i0 * 4 + 1], custom[i0 * 4 + 2]) * area
	if total <= 0.0:
		return {"albedo": Color(0.5, 0.5, 0.5), "windows": 0.0, "emission": Color(0, 0, 0)}
	albedo = albedo / total
	var share: float = window_area / total
	return {
		"albedo": Color(albedo.r, albedo.g, albedo.b) * SKYLINE_SHADE,
		"windows": share,
		"emission": (emission / window_area) * share * 0.8 if window_area > 0.0 else Color(0, 0, 0),
	}


# --------------------------------------------------------------------------- shapes and nodes

## Convex slab for (part of) a block: bottom at road level, top at sidewalk height, bevelled
## towards the road on sides that face one (walk width > 0) so people and wheels can mount it.
func _block_hull(part: Rect2, walk: Array, whole: Rect2) -> ConvexPolygonShape3D:
	var bevel: float = DistrictLayout.KERB_BEVEL
	var inset: Array[float] = [0.0, 0.0, 0.0, 0.0]   # w, e, n, s
	if float(walk[0]) > 0.0 and is_equal_approx(part.position.x, whole.position.x):
		inset[0] = bevel
	if float(walk[1]) > 0.0 and is_equal_approx(part.end.x, whole.end.x):
		inset[1] = bevel
	if float(walk[2]) > 0.0 and is_equal_approx(part.position.y, whole.position.y):
		inset[2] = bevel
	if float(walk[3]) > 0.0 and is_equal_approx(part.end.y, whole.end.y):
		inset[3] = bevel
	var top: float = DistrictLayout.LOT_TOP
	var pts := PackedVector3Array([
		Vector3(part.position.x, -0.05, part.position.y), Vector3(part.end.x, -0.05, part.position.y),
		Vector3(part.end.x, -0.05, part.end.y), Vector3(part.position.x, -0.05, part.end.y),
		Vector3(part.position.x + inset[0], top, part.position.y + inset[2]), Vector3(part.end.x - inset[1], top, part.position.y + inset[2]),
		Vector3(part.end.x - inset[1], top, part.end.y - inset[3]), Vector3(part.position.x + inset[0], top, part.end.y - inset[3]),
	])
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


## A kit hull placed in the world (scale baked into the points), or null if it is too flat.
func _hull_shape(hull: PackedVector3Array, xform: Transform3D) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	var box := AABB()
	for k: int in hull.size():
		var p: Vector3 = xform * hull[k]
		pts.append(p)
		box = AABB(p, Vector3.ZERO) if k == 0 else box.expand(p)
	if box.size.x < 0.02 or box.size.y < 0.02 or box.size.z < 0.02:
		return null
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


func _points_aabb(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p: Vector3 in points:
		box = box.expand(p)
	return box


## Bench seats as markers in the persistent "sit_spots" group (pedestrians look them up).
## kind &"landmark" = the temple's (any chunk), &"prop" = the benches in this chunk.
func _add_sit_spots(root: Node3D, kind: StringName, coord: Vector2i) -> void:
	var spots := _child(root, root, Node3D.new(), "SitSpots")
	var k: int = 0
	for s: Dictionary in _layout.sit_spots:
		var xform: Transform3D = s["xform"]
		if s["kind"] != kind or (kind == &"prop" and _layout.chunk_of(xform.origin.x, xform.origin.z) != coord):
			continue
		var marker := Marker3D.new()
		marker.transform = xform
		marker.add_to_group(&"sit_spots", true)
		_child(root, spots, marker, "Seat%d" % k)
		k += 1


## Box occluder inside a building's upper floors (never over open shopfronts or verandahs):
## [Transform3D, size] for an OccluderBatch, or [] if the building is too low for one.
func _occluder_box(piece: KitPiece, xform: Transform3D) -> Array:
	var b: AABB = piece.bounds
	var bottom: float = 3.6
	var top: float = b.end.y - 1.0
	if top - bottom < 2.0:
		return []
	var scale: Vector3 = xform.basis.get_scale()
	var size := Vector3(b.size.x * 0.7 * scale.x, top - bottom, b.size.z * 0.6 * scale.z)
	var local_centre := Vector3(b.get_center().x, (bottom + top) * 0.5, b.get_center().z)
	return [Transform3D(xform.basis.orthonormalized(), xform * local_centre), size]


func _multimesh(piece: KitPiece, xforms: Array) -> InstanceBatch:
	var batch := InstanceBatch.new()
	batch.mesh = piece.mesh
	batch.transforms = InstanceBatch.pack(xforms)
	batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # static scenery
	return batch


func _add_shape(body: StaticBody3D, shape: Shape3D, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	body.add_child(cs)


func _own_shape(root: Node3D, body: StaticBody3D, shape: Shape3D, xform: Transform3D = Transform3D.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	_child(root, body, cs, "S%d" % body.get_child_count())
	_stats["shapes"] += 1


func _child(root: Node3D, parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	if node != root:
		node.owner = root
	return node
