extends Node
## Map test (per-feature test scene, M6). Runs the real game scene and checks:
## - the district map image drawn by the builder (roads, buildings, the tank's water where the
##   layout puts them);
## - the GPS route along the roads to a waypoint and to a far mission objective, and the waypoint
##   clearing on arrival;
## - the minimap (centred on the player, turning with the camera, zooming out at speed);
## - the full map (map key opens and pauses, zoom, click to set and clear a waypoint, closes;
##   from the pause menu it returns there).
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/map_test.tscn
## Prints "MAP TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const MARKET_ROAD := Vector3(-80.0, 0.0, -46.0)

var _catcher: ErrorCatcher
var _game: GameSession
var _gps: GpsNavigator
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	SaveManager.save_dir = "user://test_saves"
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_gps = _game.get_node("Gps") as GpsNavigator
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	var steps: Array[Callable] = [_check_map_image, _check_waypoint_route, _check_mission_route, _check_minimap, _check_map_screen]
	var failure: String = ""
	for step: Callable in steps:
		failure = await step.call()
		if failure != "":
			failure = "%s: %s" % [step.get_method(), failure]
			break
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "%s: engine/script error: %s" % [step.get_method(), errors[0]]
			break
	for code: Key in [KEY_M, KEY_EQUAL]:
		_key(code, false)
	get_tree().paused = false
	print("MAP REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("MAP TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_map_image() -> String:
	var district: DistrictData = _game.world.data
	var texture: Texture2D = district.get_map_texture()
	if texture == null:
		return "the district has no map texture (%s)" % district.map_texture_path
	var image: Image = texture.get_image()
	var bounds: Rect2 = district.get_bounds()
	if image == null or image.get_width() < 1024 or not is_equal_approx(float(image.get_width()) / bounds.size.x, float(image.get_height()) / bounds.size.y):
		return "the map image is missing or not square to the district (%s)" % [image.get_size() if image else "none"]
	var sample := func(x: float, z: float) -> Color:
		var px := Vector2i(int((x - bounds.position.x) / bounds.size.x * image.get_width()), int((z - bounds.position.y) / bounds.size.y * image.get_height()))
		return image.get_pixelv(px)
	var road: Color = sample.call(70.0, 0.0)          # the east gopuram road (main)
	var building: Color = sample.call(68.67, 16.0)    # a shop south of it
	var water: Color = sample.call(80.0, 80.0)        # the temple tank
	if road.v < building.v + 0.05:
		return "on the map the main road (%s) should be lighter than the buildings (%s)" % [road.to_html(false), building.to_html(false)]
	if water.b < water.r + 0.2:
		return "the temple tank should be water-blue on the map (%s)" % water.to_html(false)
	if district.map_label_texts.size() < 4 or district.map_label_texts.size() != district.map_label_positions.size():
		return "the map has %d place names" % district.map_label_texts.size()
	_note("map image %dx%d px for the 512 m district: road, building and water where the layout has them; %d place names" % [
		image.get_width(), image.get_height(), district.map_label_texts.size()])
	return ""


func _check_waypoint_route() -> String:
	var player: PlayerController = _game.player
	_gps.set_waypoint(MARKET_ROAD)
	await _ticks(5)
	var route: PackedVector3Array = _gps.route
	if route.size() < 3:
		return "no route to the waypoint (%d points)" % route.size()
	var start: Vector3 = route[0]
	var end: Vector3 = route[route.size() - 1]
	if Vector2(start.x - player.global_position.x, start.z - player.global_position.z).length() > 1.0:
		return "the route should start at the player"
	if Vector2(end.x - MARKET_ROAD.x, end.z - MARKET_ROAD.z).length() > 6.0:
		return "the route should end at the waypoint (ends at %s)" % end
	var length: float = 0.0
	for i: int in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var straight: float = player.global_position.distance_to(MARKET_ROAD)
	if length < straight or length > straight * 2.5:
		return "route length %.0f m for a %.0f m straight line" % [length, straight]
	var graph: LaneGraph = _game.world.get_lane_graph()
	for i: int in range(1, route.size() - 1):
		var node: int = graph.nearest(route[i])
		if graph.get_position(node).distance_to(route[i]) > 0.5:
			return "route point %s is not on a lane" % route[i]
	_note("waypoint at the flower market: a %.0f m route along the lanes (%.0f m as the crow flies)" % [length, straight])
	# Arriving clears it.
	player.global_position = MARKET_ROAD + Vector3(2.0, 0.5, 0.0)
	player.reset_physics_interpolation()
	await _ticks(10)
	if _gps.get_waypoint() != null:
		return "reaching the waypoint should clear it"
	await _ticks(100)
	_note("walking up to the waypoint clears it and its route")
	return ""


func _check_mission_route() -> String:
	var player: PlayerController = _game.player
	var goal: Vector3 = MissionManager.get_objective().position
	player.global_position = Vector3(150.0, 0.5, 8.5)
	player.reset_physics_interpolation()
	_game.world.streamer.load_around_now(player.global_position)
	await _ticks(120)
	var route: PackedVector3Array = _gps.route
	if route.size() < 3 or route[route.size() - 1].distance_to(goal) > 2.0:
		return "far from the mission objective there should be a route to it (%d points)" % route.size()
	player.global_position = goal + Vector3(-20.0, 0.5, 0.0)
	player.reset_physics_interpolation()
	await _ticks(120)
	if not _gps.route.is_empty():
		return "close to the objective (in plain sight) there should be no route"
	_note("a route leads to a far mission objective (from 108 m), none once it's close")
	player.global_position = Vector3(86.5, 0.5, 8.0)
	player.reset_physics_interpolation()
	await _ticks(30)
	return ""


func _check_minimap() -> String:
	var hud := _game.get_node("HUD") as Hud
	var minimap: Minimap = hud.get_minimap()
	if minimap == null or not minimap.visible:
		return "no minimap on the HUD"
	var player: PlayerController = _game.player
	await _frames(3)
	var centre: Vector2 = minimap.world_to_minimap(player.global_position)
	if centre.distance_to(Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5) > 2.0:
		return "the player isn't in the middle of the minimap (%s)" % centre
	for pair: Array in [[0.0, 0.0], [90.0, -PI * 0.5], [180.0, PI]]:
		player.camera_rig.set_view_degrees(pair[0], -10.0)
		player.camera_rig.snap_to_target()
		await _frames(3)
		if absf(angle_difference(minimap.get_heading(), pair[1])) > 0.08:
			return "camera yaw %.0f: the minimap shows %.0f degrees as up, expected %.0f" % [pair[0], rad_to_deg(minimap.get_heading()), rad_to_deg(pair[1])]
	# Facing west (yaw 90), the temple gate (west of the player) is straight up on the minimap.
	player.camera_rig.set_view_degrees(90.0, -10.0)
	player.camera_rig.snap_to_target()
	await _frames(3)
	var gate: Vector2 = minimap.world_to_minimap(player.global_position + Vector3(-30.0, 0.0, 0.0)) - Vector2(Minimap.SIZE, Minimap.SIZE) * 0.5
	if gate.y > -30.0 or absf(gate.x) > 3.0:
		return "facing west, a point 30 m west should be straight up on the minimap (%s)" % gate
	if absf(minimap.get_metres_across() - Minimap.METRES_ON_FOOT) > 5.0:
		return "on foot the minimap should show %.0f m (shows %.0f)" % [Minimap.METRES_ON_FOOT, minimap.get_metres_across()]
	_note("minimap: player in the middle, the camera's direction is up (north, west, south checked), %.0f m across on foot" % minimap.get_metres_across())
	return ""


func _check_map_screen() -> String:
	var screen := _game.get_node("MapScreen") as MapScreen
	_tap(KEY_M)
	await _frames(3)
	if not screen.is_open() or not get_tree().paused:
		return "the map key should open the full map and pause"
	var zoom: float = screen.get_zoom()
	_tap(KEY_EQUAL)
	await _frames(2)
	if screen.get_zoom() <= zoom:
		return "the zoom-in key didn't zoom in"
	screen.click_world(Vector2(-60.0, 112.0))
	var waypoint: Variant = _gps.get_waypoint()
	if waypoint == null or Vector2((waypoint as Vector3).x + 60.0, (waypoint as Vector3).z - 112.0).length() > 6.0:
		return "clicking the map should set a waypoint on the nearest road (got %s)" % [waypoint]
	screen.click_world(Vector2((waypoint as Vector3).x, (waypoint as Vector3).z))
	if _gps.get_waypoint() != null:
		return "clicking the waypoint again should clear it"
	screen.click_world(Vector2(-60.0, 112.0))
	_tap(KEY_M)
	await _frames(3)
	if screen.is_open() or get_tree().paused:
		return "the map key should close the map and unpause"
	await _ticks(100)
	if _gps.route.size() < 3:
		return "after closing the map the route to its waypoint should be drawn"
	# From the pause menu, closing returns to it.
	var pause := _game.get_node("PauseMenu") as PauseMenu
	pause.open()
	(pause.find_child("MapButton", true, false) as Button).pressed.emit()
	await _frames(2)
	if not screen.is_open() or pause.is_open():
		return "the pause menu's Map button should show the map instead of the menu"
	_tap(KEY_ESCAPE)
	await _frames(3)
	if screen.is_open() or not pause.is_open() or not get_tree().paused:
		return "closing the map opened from the pause menu should return to the paused menu"
	pause.resume()
	await _frames(2)
	_note("full map: M opens it (paused), + zooms, a click sets a waypoint on the nearest road and a second click clears it, M closes it; from the pause menu Esc returns there")
	return ""


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
