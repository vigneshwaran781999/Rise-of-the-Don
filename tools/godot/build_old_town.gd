extends SceneTree
## Builds the streamed Old Town district (M3) from the Blender kit:
##   1. bakes every model it uses into a one-draw-call mesh in assets/world/kit/ (KitBaker),
##   2. lays out the town (OldTownLayout, deterministic),
##   3. writes one scene per 128 m chunk to scenes/world/chunks/old_town/: ground tiles and props
##      as MultiMeshes, buildings, occluders (as data, see OccluderBatch), traffic signals, simple convex collision and the
##      baked pedestrian navmesh for that chunk,
##   4. writes the always-loaded temple landmark scene, the lane graph and the district manifest.
## Re-run after changing the layout or any Blender asset (after build_all.sh and an import):
##   "$GODOT" --headless --path . --script res://tools/godot/build_old_town.gd

const KIT_DIR: String = "res://assets/world/kit/"
const OUT_DIR: String = "res://scenes/world/chunks/old_town/"
const LANDMARKS_PATH: String = OUT_DIR + "landmarks.scn"
const LANES_PATH: String = "res://resources/world/old_town_lanes.res"
const DISTRICT_PATH: String = "res://resources/world/old_town.tres"
const MATERIAL_PATH: String = KIT_DIR + "palette_material.tres"
const SHADER_PATH: String = "res://shaders/palette_lit.gdshader"
const SIGNAL_POLE_PATH: String = "res://assets/models/props/prop_signal_pole.glb"
const SIGNAL_TIMING_PATH: String = "res://resources/world/signal_timing.tres"
const LOT_COLOURS: Dictionary = {
	&"lot_paved": Color("8e897f"), &"lot_warm": Color("a08a70"), &"lot_stone": Color("a39581"), &"lot_grass": Color("5f7d3c"),
}
## The district map (GDD §11): drawn from the layout, 4 pixels per metre, flat game-map colours.
const MAP_PATH: String = "res://assets/world/maps/old_town_map.png"
const MAP_PIXELS_PER_METRE: int = 4
const MAP_COLOURS: Dictionary = {
	"empty": Color("10131c"), "lot_paved": Color("1d2230"), "lot_stone": Color("2c2a33"),
	"lot_warm": Color("302820"), "lot_grass": Color("1d3b2a"), "walk": Color("2a3142"),
	"road_main": Color("566079"), "road_lane": Color("414960"), "building": Color("353d53"),
	"building_edge": Color("4d5877"), "temple": Color("6e4c36"), "temple_edge": Color("9a6a46"),
	"market": Color("5b4433"), "water": Color("1f5b8c"), "tree": Color("2f6b45"),
}
const MAP_LABELS: Array = [
	["TEMPLE", Vector2(0.0, 0.0)], ["TEMPLE TANK", Vector2(80.0, 80.0)],
	["FLOWER MARKET", Vector2(-80.0, -80.0)], ["PARK", Vector2(-130.0, 130.0)],
	["PARK", Vector2(166.0, -130.0)], ["BUS STAND", Vector2(97.0, 14.0)],
]
## Static world collision layer, and a private layer for the navmesh source shapes.
const WORLD_LAYER: int = 1
const NAV_SOURCE_LAYER: int = 1 << 30
const BUILDING_VISIBILITY: float = 280.0
const PROP_VISIBILITY: float = 200.0

var _material: ShaderMaterial
var _kit: Dictionary = {}          # StringName -> KitPiece (mesh saved in KIT_DIR)
var _layout: OldTownLayout
var _stats: Dictionary = {"buildings": 0, "props": 0, "ground": 0, "shapes": 0, "nav_polys": 0, "signals": 0}


func _initialize() -> void:
	# The scene tree only runs from the first frame on (navmesh parsing needs it), so build then.
	_run.call_deferred()


func _run() -> void:
	var started: int = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(KIT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_material = _make_material()
	_layout = OldTownLayout.new()
	_layout.generate()
	if not _bake_kit():
		quit(1)
		return
	var source: NavigationMeshSourceGeometryData3D = _parse_nav_source()
	var timing := load(SIGNAL_TIMING_PATH) as SignalTiming
	var pole := load(SIGNAL_POLE_PATH) as PackedScene
	var count: int = int(2.0 * OldTownLayout.HALF / OldTownLayout.CHUNK_SIZE)
	for cz: int in count:
		for cx: int in count:
			if not _build_chunk(Vector2i(cx, cz), source, timing, pole):
				quit(1)
				return
	if not _build_landmarks():
		quit(1)
		return
	var err: Error = ResourceSaver.save(_layout.lane_graph, LANES_PATH, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("build_old_town: could not save the lane graph (%d)" % err)
		quit(1)
		return
	if not _write_map():
		quit(1)
		return
	var district := DistrictData.new()
	district.display_name = "Old Town"
	district.map_texture_path = MAP_PATH
	for label: Array in MAP_LABELS:
		district.map_label_texts.append(label[0])
		district.map_label_positions.append(label[1])
	district.chunk_size = OldTownLayout.CHUNK_SIZE
	district.origin = Vector2(-OldTownLayout.HALF, -OldTownLayout.HALF)
	district.chunk_count = Vector2i(count, count)
	district.chunk_path_format = OUT_DIR + "chunk_%d_%d.scn"
	district.lane_graph = load(LANES_PATH) as LaneGraph
	err = ResourceSaver.save(district, DISTRICT_PATH)
	if err != OK:
		push_error("build_old_town: could not save the district (%d)" % err)
		quit(1)
		return
	var lanes: LaneGraph = _layout.lane_graph
	print("build_old_town: %d chunks, %d buildings, %d props, %d ground tiles, %d collision shapes, %d navmesh polygons" % [
		count * count, _stats["buildings"], _stats["props"], _stats["ground"], _stats["shapes"], _stats["nav_polys"]])
	print("build_old_town: %d junctions (%d with traffic lights), %d crossings, lane graph %d nodes (%d disconnected), %d kit meshes" % [
		_layout.junction_count, _stats["signals"], _layout.crossings.size(), lanes.size(), lanes.count_disconnected(), _kit.size()])
	print("build_old_town: done in %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	quit(0)


# --------------------------------------------------------------------------- map

## Draws the district from above into MAP_PATH: lots, sidewalks, roads (main roads brighter),
## buildings (temple buildings warm), the tank's water and trees.
func _write_map() -> bool:
	var size: int = int(2.0 * OldTownLayout.HALF) * MAP_PIXELS_PER_METRE
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
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
		_map_fill(image, _map_rect(p), MAP_COLOURS.get(str(p["kit"]), MAP_COLOURS["lot_paved"]))
	for p: Dictionary in layers[1]:
		_map_fill(image, _map_rect(p), MAP_COLOURS["walk"])
	for p: Dictionary in layers[2]:
		var kit: String = str(p["kit"])
		var main: bool = kit.contains("main") or kit.ends_with("_mm") or kit.ends_with("_ml")
		_map_fill(image, _map_rect(p), MAP_COLOURS["road_main" if main else "road_lane"])
	for p: Dictionary in layers[3]:
		var kit: String = str(p["kit"])
		var rect: Rect2 = _map_rect(p)
		if kit == "bld_ot_tank":
			_map_fill(image, rect, MAP_COLOURS["lot_stone"])
			_map_fill(image, rect.grow(-6.0), MAP_COLOURS["water"])
			continue
		var temple: bool = kit.contains("temple") or kit.contains("vimana") or kit.contains("mandapam")
		var market: bool = kit.contains("market")
		var edge: Color = MAP_COLOURS["temple_edge"] if temple else MAP_COLOURS["building_edge"]
		var fill: Color = MAP_COLOURS["temple"] if temple else (MAP_COLOURS["market"] if market else MAP_COLOURS["building"])
		_map_fill(image, rect, edge)
		_map_fill(image, rect.grow(-0.4), fill)
	for p: Dictionary in layers[4]:
		var o: Vector3 = (p["xform"] as Transform3D).origin
		_map_fill(image, Rect2(o.x - 1.5, o.z - 1.5, 3.0, 3.0), MAP_COLOURS["tree"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAP_PATH.get_base_dir()))
	var err: Error = image.save_png(ProjectSettings.globalize_path(MAP_PATH))
	if err != OK:
		push_error("build_old_town: could not save the map (%d)" % err)
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


func _map_fill(image: Image, world: Rect2, colour: Color) -> void:
	var scale: float = MAP_PIXELS_PER_METRE
	var x0: int = clampi(roundi((world.position.x + OldTownLayout.HALF) * scale), 0, image.get_width())
	var y0: int = clampi(roundi((world.position.y + OldTownLayout.HALF) * scale), 0, image.get_height())
	var x1: int = clampi(roundi((world.end.x + OldTownLayout.HALF) * scale), 0, image.get_width())
	var y1: int = clampi(roundi((world.end.y + OldTownLayout.HALF) * scale), 0, image.get_height())
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
				push_error("build_old_town: missing model %s" % path)
				return false
			piece = KitBaker.bake(load(path) as PackedScene, _material)
		var mesh_path: String = KIT_DIR + str(kit_name) + ".res"
		var err: Error = ResourceSaver.save(piece.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
		if err != OK:
			push_error("build_old_town: could not save %s (%d)" % [mesh_path, err])
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
	var y: float = OldTownLayout.LOT_TOP
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


## Walkable ground (every block slab and the crossings over roads) plus everything standing on
## it (buildings, props, the temple), for the whole district. Roads themselves are left out, so
## people only cross them at crossings.
func _parse_nav_source() -> NavigationMeshSourceGeometryData3D:
	var root := Node3D.new()
	root.name = "NavSource"
	get_root().add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = NAV_SOURCE_LAYER
	root.add_child(body)
	for b: Dictionary in _layout.blocks:
		_add_shape(body, _block_hull(b["rect"], b["walk"], b["rect"]))
	for r: Rect2 in _layout.crossings:
		var box := BoxShape3D.new()
		box.size = Vector3(r.size.x, 0.2, r.size.y)
		_add_shape(body, box, Transform3D(Basis.IDENTITY, Vector3(r.get_center().x, -0.1, r.get_center().y)))
	var solids: Array[ConvexPolygonShape3D] = []
	for p: Dictionary in _layout.placements:
		if p["kind"] == &"ground":
			continue
		for hull: PackedVector3Array in (_kit[p["kit"]] as KitPiece).hulls:
			var shape: ConvexPolygonShape3D = _hull_shape(hull, p["xform"])
			if shape != null:
				_add_shape(body, shape)
				solids.append(shape)
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

func _build_chunk(coord: Vector2i, source: NavigationMeshSourceGeometryData3D, timing: SignalTiming, pole: PackedScene) -> bool:
	var rect := Rect2(-OldTownLayout.HALF + coord.x * OldTownLayout.CHUNK_SIZE, -OldTownLayout.HALF + coord.y * OldTownLayout.CHUNK_SIZE,
		OldTownLayout.CHUNK_SIZE, OldTownLayout.CHUNK_SIZE)
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
		if p["kind"] == &"landmark" or OldTownLayout.chunk_of(xform.origin.x, xform.origin.z) != coord:
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
		if OldTownLayout.chunk_of(centre.x, centre.z) != coord:
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
	NavigationServer3D.bake_from_source_geometry_data(nav, source)
	region.navigation_mesh = nav
	_child(root, root, region, "Navigation")
	_stats["nav_polys"] += nav.get_polygon_count()

	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUT_DIR + "chunk_%d_%d.scn" % [coord.x, coord.y], ResourceSaver.FLAG_COMPRESS)
	root.free()
	if err != OK:
		push_error("build_old_town: could not save chunk %s (%d)" % [coord, err])
		return false
	return true


## The temple compound: always loaded so the gopurams stay on the skyline from anywhere.
func _build_landmarks() -> bool:
	var root := Node3D.new()
	root.name = "OldTownLandmarks"
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
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, LANDMARKS_PATH, ResourceSaver.FLAG_COMPRESS)
	root.free()
	if err != OK:
		push_error("build_old_town: could not save the landmarks (%d)" % err)
	return err == OK


# --------------------------------------------------------------------------- shapes and nodes

## Convex slab for (part of) a block: bottom at road level, top at sidewalk height, bevelled
## towards the road on sides that face one (walk width > 0) so people and wheels can mount it.
func _block_hull(part: Rect2, walk: Array, whole: Rect2) -> ConvexPolygonShape3D:
	var bevel: float = OldTownLayout.KERB_BEVEL
	var inset: Array[float] = [0.0, 0.0, 0.0, 0.0]   # w, e, n, s
	if float(walk[0]) > 0.0 and is_equal_approx(part.position.x, whole.position.x):
		inset[0] = bevel
	if float(walk[1]) > 0.0 and is_equal_approx(part.end.x, whole.end.x):
		inset[1] = bevel
	if float(walk[2]) > 0.0 and is_equal_approx(part.position.y, whole.position.y):
		inset[2] = bevel
	if float(walk[3]) > 0.0 and is_equal_approx(part.end.y, whole.end.y):
		inset[3] = bevel
	var top: float = OldTownLayout.LOT_TOP
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


## Bench seats as markers in the persistent "sit_spots" group (pedestrians look them up).
## kind &"landmark" = the temple's (any chunk), &"prop" = the benches in this chunk.
func _add_sit_spots(root: Node3D, kind: StringName, coord: Vector2i) -> void:
	var spots := _child(root, root, Node3D.new(), "SitSpots")
	var k: int = 0
	for s: Dictionary in _layout.sit_spots:
		var xform: Transform3D = s["xform"]
		if s["kind"] != kind or (kind == &"prop" and OldTownLayout.chunk_of(xform.origin.x, xform.origin.z) != coord):
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
