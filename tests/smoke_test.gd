extends Node
## Headless smoke test. Run from the project root:
##   "$GODOT" --headless --path . res://tests/smoke_test.tscn
## Prints "SMOKE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.
## Any engine or script error logged while it runs also fails the test.
##
## It drives the real game: main menu -> New Game (Old Town, the opening mission starts) -> traffic and pedestrians appear
## (then switched off) -> chunk streaming, traffic signals, lane graph, pedestrian navmesh ->
## walk, sprint, jump, kerb, look, HUD -> get in the sedan, drive, brake, reverse, steer,
## cameras, horn, lights, crash, get out -> pause, save to a slot -> back to the main menu. Input goes through
## the real input map (simulated key events).
## More detail lives in per-feature tests: tests/vehicle_test.tscn (handling figures),
## tests/player_test.tscn (kerb, ramps and gateway on the M1 test block),
## tests/traffic_test.tscn and tests/pedestrian_test.tscn (M4 city life), tests/mission_test.tscn
## and tests/save_test.tscn (M5 missions, cash, saving). Saves go to user://test_saves.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const TIMEOUT_SEC: float = 180.0
const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const GAME: String = "res://scenes/main/game.tscn"
const TEST_CUBE_PATH: String = "res://assets/models/test/prop_test_cube.glb"
const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump",
	"look_left", "look_right", "look_up", "look_down",
	"vehicle_enter_exit", "interact", "pause", "toggle_fps",
	"vehicle_accelerate", "vehicle_brake", "vehicle_steer_left", "vehicle_steer_right",
	"vehicle_handbrake", "vehicle_horn", "vehicle_headlights", "vehicle_camera", "toggle_lane_debug",
	"map", "map_zoom_in", "map_zoom_out",
]
## Vehicle models: visuals only, no static '-colonly' body (a car is a moving rigid body).
const VEHICLE_ASSETS: PackedStringArray = [
	"vehicles/veh_sedan_body", "vehicles/veh_sedan_wheel", "vehicles/veh_police_lightbar", "vehicles/veh_police_heli",
]
## Pedestrian models: visuals only too (a pedestrian is a CharacterBody3D with its own capsule).
const CHARACTER_ASSETS: PackedStringArray = ["characters/chr_ped_man", "characters/chr_ped_woman", "characters/chr_ped_elder"]
## City kit pieces (Old Town, Downtown, Beach District, Industrial Zone) that must exist as baked meshes (one surface each).
const KIT_MESHES: PackedStringArray = [
	"road_main_seg", "road_lane_seg", "road_junction_mm", "road_walk_main", "road_walk_corner",
	"bld_ot_house_01", "bld_ot_shop_04", "bld_ot_lodge_01", "bld_temple_gopuram", "bld_ot_vimana",
	"bld_ot_tank", "bld_ot_market_hall", "bld_ot_police_station", "prop_streetlight", "prop_neem_tree",
	"prop_market_stall_a", "prop_bench", "lot_plaza", "bld_dt_tower_a", "bld_dt_tower_b", "bld_dt_tower_c", "bld_dt_office_a",
	"bld_dt_office_b", "bld_dt_retail_a", "bld_dt_retail_b", "bld_dt_hotel", "bld_dt_mall", "bld_dt_police", "prop_dt_fountain",
	"lot_sand", "bld_bh_resort", "bld_bh_hotel", "bld_bh_seafood", "bld_bh_police", "bld_bh_cottage", "bld_bh_lighthouse", "bld_bh_pier",
	"prop_bh_umbrella", "prop_bh_boat", "prop_bh_lifeguard", "prop_bh_kiosk",
	"lot_concrete", "bld_in_warehouse_a", "bld_in_warehouse_b", "bld_in_factory", "bld_in_office", "bld_in_police", "bld_in_tanks",
	"bld_in_crane", "bld_in_ship", "bld_in_fish_shed", "prop_in_container_a", "prop_streetlight_sodium",
]
const SEDAN_PATH: String = "World/Vehicles/Sedan"
## Open stretch of Ring B (the main road along z = 112) between the junctions at x = -44 and -6;
## the car checks put the sedan here, facing west.
const TEST_ROAD := Vector3(-20.0, 0.6, 109.0)
const REQUIRED_BUSES: PackedStringArray = ["Master", "Music", "SFX", "Ambience", "UI"]
## Every generated asset must import with at least one auto-built collision body.
const COLLIDABLE_ASSETS: PackedStringArray = [
	"road/road_straight", "road/road_crosswalk", "road/road_intersection",
	"road/road_sidewalk", "road/road_sidewalk_corner",
	"buildings/bld_shophouse_01", "buildings/bld_shophouse_02", "buildings/bld_shophouse_03",
	"buildings/bld_apartment_01", "buildings/bld_apartment_02",
	"buildings/bld_office_01", "buildings/bld_office_02",
	"buildings/bld_temple_gopuram", "buildings/bld_temple_shrine", "buildings/bld_ot_police_station",
	"props/prop_streetlight", "props/prop_palm_tree", "props/prop_temple_wall", "props/prop_bench",
	"buildings/bld_dt_tower_a", "buildings/bld_dt_tower_b", "buildings/bld_dt_tower_c", "buildings/bld_dt_office_a",
	"buildings/bld_dt_office_b", "buildings/bld_dt_retail_a", "buildings/bld_dt_retail_b", "buildings/bld_dt_hotel",
	"buildings/bld_dt_mall", "buildings/bld_dt_police", "props/prop_dt_fountain",
	"buildings/bld_bh_resort", "buildings/bld_bh_hotel", "buildings/bld_bh_seafood", "buildings/bld_bh_police",
	"buildings/bld_bh_shop_a", "buildings/bld_bh_shop_b", "buildings/bld_bh_cottage", "buildings/bld_bh_lighthouse",
	"buildings/bld_bh_pier", "props/prop_bh_umbrella", "props/prop_bh_boat", "props/prop_bh_lifeguard", "props/prop_bh_kiosk",
	"buildings/bld_in_warehouse_a", "buildings/bld_in_warehouse_b", "buildings/bld_in_factory", "buildings/bld_in_office",
	"buildings/bld_in_police", "buildings/bld_in_tanks", "buildings/bld_in_crane", "buildings/bld_in_ship",
	"buildings/bld_in_fish_shed", "props/prop_in_container_a", "props/prop_in_container_b", "props/prop_in_container_c",
	"props/prop_streetlight_sodium",
]

var _catcher: ErrorCatcher
var _finished: bool = false


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _run() -> void:
	# Hand "current scene" to a stand-in so change_scene_to_file() never frees this test.
	var stand_in := Node.new()
	stand_in.name = "SceneStandIn"
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	# Never write the user's real settings file, and handle simulated input immediately.
	Settings.persist = false
	SaveManager.save_dir = "user://test_saves"   # never the player's real saves
	for slot: int in SaveManager.ALL_SLOTS:
		SaveManager.delete_slot(slot)
	Input.use_accumulated_input = false
	var failure: String = await _run_checks()
	_release_all_keys()
	_finish(failure)


func _run_checks() -> String:
	var steps: Array[Callable] = [
		_check_project_settings, _check_input_map, _check_audio_and_settings, _check_test_cube,
		_check_asset_collisions, _check_main_menu, _check_new_game, _check_city_life, _check_spawn,
		_check_streaming, _check_downtown, _check_beach, _check_industrial,
		_check_traffic_signals, _check_lane_graph, _check_navmesh,
		_check_walk_forward, _check_sprint, _check_jump, _check_kerb_step_up,
		_check_camera, _check_hud,
		_check_vehicle_parked, _check_enter_vehicle, _check_drive_brake_reverse, _check_steering,
		_check_vehicle_cameras, _check_horn_and_lights, _check_crash_damage, _check_pause_in_vehicle,
		_check_exit_vehicle, _check_exit_at_speed, _check_exit_blocked_door,
		_check_pause_and_return_to_menu,
	]
	for step: Callable in steps:
		var result: String = await step.call()
		if result != "":
			return "%s: %s" % [step.get_method(), result]
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			return "%s: engine/script error: %s" % [step.get_method(), errors[0]]
	return ""


# --------------------------------------------------------------------------- setup checks

func _check_project_settings() -> String:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	if engine != "Jolt Physics":
		return "physics engine is '%s', expected 'Jolt Physics'" % engine
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	if w != 1920 or h != 1080:
		return "viewport is %dx%d, expected 1920x1080" % [w, h]
	if ProjectSettings.get_setting("application/run/main_scene", "") != MAIN_MENU:
		return "main scene is not the main menu"
	print("  ok  project settings (Jolt, 1920x1080, main menu is the main scene)")
	return ""


func _check_input_map() -> String:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			return "input action '%s' is missing" % action
		if InputMap.action_get_events(action).is_empty():
			return "input action '%s' has no bindings" % action
	print("  ok  input map (%d actions)" % REQUIRED_ACTIONS.size())
	return ""


func _check_audio_and_settings() -> String:
	for bus_name: String in REQUIRED_BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			return "audio bus '%s' is missing" % bus_name
	var before: float = Settings.master_volume
	Settings.set_volume(&"master_volume", 0.5)
	var db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	Settings.set_volume(&"master_volume", before)
	if absf(db - linear_to_db(0.5)) > 0.01:
		return "master volume 0.5 should set the Master bus to %.2f dB, got %.2f" % [linear_to_db(0.5), db]
	for sound: StringName in [&"ui_move", &"ui_accept", &"ui_back", &"footstep", &"land"]:
		if not AudioManager.has_stream(sound):
			return "AudioManager has no '%s' sound" % sound
	print("  ok  audio buses, volume settings drive the buses, placeholder sounds exist")
	return ""


func _check_test_cube() -> String:
	if not ResourceLoader.exists(TEST_CUBE_PATH):
		return "test cube GLB was not imported: " + TEST_CUBE_PATH
	var cube: Node3D = (load(TEST_CUBE_PATH) as PackedScene).instantiate()
	add_child(cube)
	var ball := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	ball.add_child(shape)
	ball.position = Vector3(0.0, 3.0, 0.0)
	add_child(ball)
	await _physics_frames(120)
	var rest_y: float = ball.global_position.y
	cube.queue_free()
	ball.queue_free()
	if absf(rest_y - 1.5) > 0.1:
		return "ball should rest on the cube's imported collision at y=1.5, got y=%.3f" % rest_y
	print("  ok  Blender -> GLB -> Godot pipeline (ball rests on the test cube at y=%.2f)" % rest_y)
	return ""


func _check_asset_collisions() -> String:
	for asset: String in COLLIDABLE_ASSETS:
		var path: String = "res://assets/models/%s.glb" % asset
		if not ResourceLoader.exists(path):
			return "asset not imported: " + path
		var node: Node = (load(path) as PackedScene).instantiate()
		var meshes: int = node.find_children("*", "MeshInstance3D", true, false).size()
		var bodies: int = node.find_children("*", "StaticBody3D", true, false).size()
		# The district builder turns collision into convex hulls (trimesh split into its pieces):
		# every hull needs real points, or the piece has no collision in the streamed chunks.
		var hulls: Array[PackedVector3Array] = KitBaker.collect_hulls(node as Node3D)
		var empty_hulls: int = 0
		for hull: PackedVector3Array in hulls:
			empty_hulls += 1 if hull.size() < 4 else 0
		node.free()
		if meshes < 1 or bodies < 1:
			return "%s should have a mesh and a '-colonly' body (meshes %d, bodies %d)" % [asset, meshes, bodies]
		if hulls.is_empty() or empty_hulls > 0:
			return "%s: its collision bakes to %d hulls, %d of them empty" % [asset, hulls.size(), empty_hulls]
	for asset: String in VEHICLE_ASSETS + CHARACTER_ASSETS:
		var path: String = "res://assets/models/%s.glb" % asset
		if not ResourceLoader.exists(path):
			return "asset not imported: " + path
		var node: Node = (load(path) as PackedScene).instantiate()
		var meshes: int = node.find_children("*", "MeshInstance3D", true, false).size()
		var bodies: int = node.find_children("*", "StaticBody3D", true, false).size()
		node.free()
		if meshes < 1 or bodies > 0:
			return "%s should be visuals only (meshes %d, static bodies %d)" % [asset, meshes, bodies]
	for kit_name: String in KIT_MESHES:
		var mesh_path: String = "res://assets/world/kit/%s.res" % kit_name
		var mesh := load(mesh_path) as ArrayMesh if ResourceLoader.exists(mesh_path) else null
		if mesh == null or mesh.get_surface_count() != 1 or not (mesh.surface_get_material(0) is ShaderMaterial):
			return "%s should be one surface with the palette material (run tools/godot/build_city.gd)" % mesh_path
	for asset: String in CHARACTER_ASSETS:
		var look := load("res://assets/models/%s.glb" % asset) as PackedScene
		var mesh: ArrayMesh = CharacterBaker.get_mesh(look)
		if mesh == null or mesh.get_surface_count() != 1:
			return "%s should bake to one animated surface" % asset
	print("  ok  %d Blender assets imported, each with visuals and collision (baking to convex hulls); %d vehicle and %d pedestrian models (visuals only, pedestrians bake to one draw call); %d city kit meshes baked to one draw call each" % [
		COLLIDABLE_ASSETS.size(), VEHICLE_ASSETS.size(), CHARACTER_ASSETS.size(), KIT_MESHES.size()])
	return ""


# --------------------------------------------------------------------------- menu -> game

func _check_main_menu() -> String:
	get_tree().change_scene_to_file(MAIN_MENU)
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	if menu == null:
		return "main menu did not load"
	for button_name: String in ["NewGameButton", "ContinueButton", "LoadGameButton", "SettingsButton", "ControlsButton",
			"CreditsButton", "ExitButton"]:
		if _find(menu, button_name) == null:
			return "main menu has no %s" % button_name
	if not (_find(menu, "ContinueButton") as Button).disabled or not (_find(menu, "LoadGameButton") as Button).disabled:
		return "Continue and Load Game should be disabled while no save exists"

	(_find(menu, "SettingsButton") as Button).pressed.emit()
	await _process_frames(2)
	var settings_panel := _find(menu, "SettingsPanel") as SettingsPanel
	if settings_panel == null or not settings_panel.visible:
		return "Settings button did not open the settings panel"
	var master_slider := _find(settings_panel, "MasterSlider") as HSlider
	var sensitivity := _find(settings_panel, "SensitivitySlider") as HSlider
	var old_volume: float = Settings.master_volume
	var old_sensitivity: float = Settings.mouse_sensitivity
	master_slider.value = 35.0
	sensitivity.value = 1.75
	var volume_ok: bool = absf(Settings.master_volume - 0.35) < 0.001
	var sensitivity_ok: bool = absf(Settings.mouse_sensitivity - 1.75) < 0.001
	master_slider.value = old_volume * 100.0
	sensitivity.value = old_sensitivity
	if not volume_ok or not sensitivity_ok:
		return "settings sliders did not update Settings (volume %s, sensitivity %s)" % [volume_ok, sensitivity_ok]
	# Density buttons cycle Low -> Medium -> High -> Low and show the level.
	for pair: Array in [["PedestrianDensityButton", &"pedestrian_density"], ["TrafficDensityButton", &"traffic_density"]]:
		var button := _find(settings_panel, pair[0]) as Button
		if button == null:
			return "the settings panel has no %s" % pair[0]
		var before: int = Settings.get_density(pair[1])
		var seen: Array[int] = []
		for press: int in 3:
			button.pressed.emit()
			seen.append(Settings.get_density(pair[1]))
			if not button.text.to_upper().contains(str(Settings.DENSITY_NAMES[seen[press]]).to_upper()):
				return "%s shows '%s' for level %s" % [pair[0], button.text, Settings.DENSITY_NAMES[seen[press]]]
		if seen[2] != before or seen[0] == before or seen[1] == before or seen[0] == seen[1]:
			return "%s should cycle through all three levels (from %d: %s)" % [pair[0], before, seen]
	(_find(settings_panel, "BackButton") as Button).pressed.emit()
	await _process_frames(2)
	if settings_panel.visible:
		return "settings Back did not close the panel"

	for pair: Array in [["ControlsButton", "ControlsPanel"], ["CreditsButton", "CreditsPanel"]]:
		(_find(menu, pair[0]) as Button).pressed.emit()
		await _process_frames(2)
		var panel := _find(menu, pair[1]) as MenuPanel
		if panel == null or not panel.visible:
			return "%s did not open %s" % pair
		panel.close()
	var grid := _find(menu, "BindingsGrid") as GridContainer
	if grid == null or grid.get_child_count() < 3 * 4:
		return "controls screen lists no bindings"
	print("  ok  main menu (buttons, Continue and Load Game disabled without saves, settings sliders and density buttons work, controls, credits)")
	return ""


func _check_new_game() -> String:
	var menu: Node = get_tree().current_scene
	(_find(menu, "NewGameButton") as Button).pressed.emit()
	var game: Node = await _wait_for_scene(GAME)
	if game == null:
		return "New Game did not load the game scene"
	if _player() == null:
		return "game scene has no player"
	var world := game.get_node_or_null("World") as CityWorld
	var regions := game.get_node_or_null("Regions") as RegionWatcher
	if world == null or regions == null or regions.get_current_name() != "Old Town":
		return "New Game should start in the Old Town district of the city"
	var buildings: int = 0
	for c: Vector2i in world.streamer.get_loaded_coords():
		buildings += world.streamer.get_chunk(c).get_node("Buildings").get_child_count()
	if buildings < 100:
		return "only %d buildings loaded around the spawn" % buildings
	if world.get_node_or_null("Landmarks/Temple") == null:
		return "the temple landmark is not loaded"
	if _hud().get_area_title() != "OLD TOWN":
		return "no OLD TOWN title card on arrival (got '%s')" % _hud().get_area_title()
	# The story starts: the opening mission runs, with cash and the first objective on the HUD.
	var opening: MissionData = MissionManager.get_active()
	if opening == null or opening.id != &"welcome":
		return "New Game should start the opening mission 'welcome'"
	if _hud().get_cash_shown() != EconomyManager.format(MissionManager.story.starting_cash):
		return "HUD cash shows '%s', expected the starting %s" % [_hud().get_cash_shown(), EconomyManager.format(MissionManager.story.starting_cash)]
	if _hud().get_mission_hud().get_objective_shown() == "":
		return "no objective on the HUD"
	print("  ok  New Game starts in Old Town: %d chunks, %d buildings around the spawn, temple landmark, title card; mission '%s' running ('%s'), %s cash" % [
		world.streamer.get_loaded_count(), buildings, opening.title, _hud().get_mission_hud().get_objective_shown(), _hud().get_cash_shown()])
	return ""


## Traffic and pedestrians appear around the player after New Game and get moving. Then both
## are switched off and cleared so the player and car checks that follow run on quiet streets
## (tests/traffic_test.tscn and tests/pedestrian_test.tscn cover them in depth).
func _check_city_life() -> String:
	var game: Node = get_tree().current_scene
	var traffic := game.get_node_or_null("Traffic") as TrafficManager
	var people := game.get_node_or_null("Pedestrians") as PedestrianManager
	if traffic == null or people == null:
		return "the game scene has no Traffic or Pedestrians manager"
	var car_moving: bool = false
	var person_walking: bool = false
	var frames: int = 0
	while not (car_moving and person_walking) and frames < 60 * 15:
		await get_tree().physics_frame
		frames += 1
		for car: VehicleController in traffic.get_cars():
			car_moving = car_moving or car.get_speed_kmh() > 10.0
		for person: Pedestrian in people.get_pedestrians():
			person_walking = person_walking or (person.state == Pedestrian.State.WALK and person.velocity.length() > 0.5)
	if not car_moving or not person_walking:
		return "after %.0f s: %d cars (one moving: %s), %d people (one walking: %s)" % [
			frames / 60.0, traffic.get_count(), car_moving, people.get_count(), person_walking]
	var counts := Vector2i(traffic.get_count(), people.get_count())
	if counts.x > traffic.target_count() or counts.y > people.target_count():
		return "more cars or people than the density allows (%s)" % counts
	traffic.enabled = false
	people.enabled = false
	traffic.clear()
	people.clear()
	await _physics_frames(5)
	print("  ok  city life: within %.1f s of New Game %d cars were driving and %d people walking around the player (then switched off for the checks below)" % [
		frames / 60.0, counts.x, counts.y])
	return ""


# --------------------------------------------------------------------------- player

func _check_spawn() -> String:
	var player: PlayerController = _player()
	await _physics_frames(30)
	if not player.is_on_floor():
		return "player is not standing on the ground after spawning (y=%.2f)" % player.global_position.y
	print("  ok  player spawned at the bus stand, standing on the sidewalk (state %s)" % player.get_state_name())
	return ""


func _check_walk_forward() -> String:
	var player: PlayerController = _player()
	var start: Vector3 = player.global_position
	var states: Dictionary = {}
	var on_state := func(_previous: int, current: int) -> void: states[current] = true
	player.state_changed.connect(on_state)
	_key(KEY_W, true)
	await _physics_frames(120)  # 2 s
	_key(KEY_W, false)
	player.state_changed.disconnect(on_state)
	var moved: Vector3 = player.global_position - start
	var flat := Vector2(moved.x, moved.z)
	var away: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, player.camera_rig.get_yaw())
	if flat.length() <= 3.0:
		return "holding W for 2 s moved the player only %.2f m" % flat.length()
	if moved.dot(away) < flat.length() * 0.9:
		return "W should move away from the camera (towards the gopuram); moved %s" % moved
	if not states.has(PlayerController.State.RUN):
		return "never entered RUN while holding W"
	await _physics_frames(30)
	print("  ok  holding W for 2 s moved the player %.1f m away from the camera" % flat.length())
	return ""


func _check_sprint() -> String:
	var player: PlayerController = _player()
	var stamina_before: float = player.stats.stamina
	var top_speed: float = 0.0
	var sprinted: bool = false
	_key(KEY_W, true)
	_key(KEY_SHIFT, true)
	for i: int in 60:
		await get_tree().physics_frame
		top_speed = maxf(top_speed, player.get_horizontal_speed())
		sprinted = sprinted or player.state == PlayerController.State.SPRINT
	_key(KEY_SHIFT, false)
	_key(KEY_W, false)
	var used: float = stamina_before - player.stats.stamina
	if not sprinted:
		return "never entered SPRINT while holding W + Shift"
	if top_speed < player.tuning.run_speed + 1.0:
		return "sprint top speed %.2f m/s is not above run speed" % top_speed
	if used < 10.0:
		return "1 s of sprinting used only %.1f stamina" % used
	await _physics_frames(40)
	print("  ok  sprint reached %.1f m/s and used %.0f stamina" % [top_speed, used])
	return ""


func _check_jump() -> String:
	var player: PlayerController = _player()
	await _physics_frames(20)
	if not player.is_on_floor():
		return "player should be on the ground before jumping"
	var start_y: float = player.global_position.y
	var peak: float = start_y
	var left_ground: bool = false
	var landed: bool = false
	var states: Dictionary = {}
	var on_state := func(_previous: int, current: int) -> void: states[current] = true
	player.state_changed.connect(on_state)
	_key(KEY_SPACE, true)
	await _physics_frames(2)
	_key(KEY_SPACE, false)
	for i: int in 150:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y)
		if not player.is_on_floor():
			left_ground = true
		elif left_ground:
			landed = true
			break
	player.state_changed.disconnect(on_state)
	if not left_ground:
		return "Space did not make the player leave the ground"
	if peak - start_y < 0.5:
		return "jump only rose %.2f m" % (peak - start_y)
	if not landed:
		return "player did not land within 2.5 s"
	for needed: PlayerController.State in [PlayerController.State.JUMP, PlayerController.State.FALL]:
		if not states.has(needed):
			return "jump never passed through state %s" % PlayerController.State.keys()[needed]
	print("  ok  jump rose %.2f m and landed (JUMP -> FALL -> ground)" % (peak - start_y))
	return ""


## From the road onto the sidewalk south of the east gopuram road, over the bevelled kerb.
## Camera facing west, so A walks south. (The full kerb/ramp/gateway course: player_test.tscn.)
func _check_kerb_step_up() -> String:
	var player: PlayerController = _player()
	player.camera_rig.set_view_degrees(90.0, -12.0)
	await _teleport(player, Vector3(70.0, 0.1, 4.5))
	await _hold(KEY_A, 60)
	if player.global_position.z < 6.6 or absf(player.global_position.y - 0.15) > 0.05 or not player.is_on_floor():
		return "could not step south from the road onto the sidewalk over the kerb (at %s)" % player.global_position
	await _teleport(player, Vector3(70.0, 0.1, 1.5))
	print("  ok  stepped up the bevelled kerb from the road onto the Old Town sidewalk")
	return ""


# --------------------------------------------------------------------------- Old Town district

## Moves the streaming focus to the far north-west corner while the player is held still: the
## chunks there stream in on a background thread, the chunk around the spawn is freed and the
## sedan parked there freezes (its ground is gone). Then everything is put back.
func _check_streaming() -> String:
	var world: CityWorld = _world()
	var streamer: WorldStreamer = world.streamer
	var data: CityData = world.data
	if data.chunks.size() < 32:
		return "the city should have at least Old Town's and Downtown's 32 chunks (%d)" % data.chunks.size()
	for c: Vector2i in data.chunks:
		if not ResourceLoader.exists(data.chunk_path(c)):
			return "chunk scene missing: " + data.chunk_path(c)
	var player: PlayerController = _player()
	var car: VehicleController = _car()
	var spawn_chunk: Vector2i = data.chunk_at(player.global_position)
	var start_count: int = streamer.get_loaded_count()
	var corner := Node3D.new()
	get_tree().current_scene.add_child(corner)
	corner.global_position = Vector3(-230.0, 0.0, -230.0)
	var corner_chunk: Vector2i = data.chunk_at(corner.global_position)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	streamer.focus = corner
	var frames: int = 0
	while frames < 900 and not (streamer.is_chunk_loaded(corner_chunk) and not streamer.is_chunk_loaded(spawn_chunk)):
		await get_tree().physics_frame
		frames += 1
	var streamed_in: bool = streamer.is_chunk_loaded(corner_chunk)
	var streamed_out: bool = not streamer.is_chunk_loaded(spawn_chunk)
	var far_count: int = streamer.get_loaded_count()
	var car_frozen: bool = car.freeze
	streamer.focus = player
	streamer.load_around_now(player.global_position)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	corner.queue_free()
	await _physics_frames(20)
	if not streamed_in or not streamed_out:
		return "moving the focus to Old Town's far corner should load chunk %s and free the spawn chunk (in %s, out %s)" % [corner_chunk, streamed_in, streamed_out]
	if not car_frozen or car.freeze:
		return "the parked sedan should freeze while its chunk is unloaded and thaw when it is back (frozen %s, now %s)" % [car_frozen, car.freeze]
	if not player.is_on_floor():
		return "after streaming back the player should stand on the ground (at %s)" % player.global_position
	for c: Vector2i in streamer.wanted_chunks(player.global_position):
		if not streamer.is_chunk_loaded(c):
			return "after streaming back, chunk %s near the player is missing" % c
	print("  ok  streaming: %d of the city's %d chunks around the spawn; at Old Town's far corner %d chunks streamed in on a background thread within %.1f s, the spawn chunk was freed and its parked sedan froze; all restored" % [
		start_count, data.chunks.size(), far_count, frames / 60.0])
	return ""


## M7: Downtown, the second district, north of Old Town. Its streets carry on from Old Town's
## (a road route crosses the border), it has its own police station, its towers stand on the
## always-loaded skyline, walls close the edge of the city, and walking in shows its name.
func _check_downtown() -> String:
	var game := get_tree().current_scene as GameSession
	var world: CityWorld = _world()
	var data: CityData = world.data
	var downtown: int = data.region_names.find("Downtown")
	if downtown < 0 or data.region_names.find("Old Town") < 0:
		return "the city should have Old Town and Downtown (%s)" % data.region_names
	var rect: Rect2 = data.region_rects[downtown]
	if not rect.has_point(Vector2(0.0, -512.0)) or not rect.size.is_equal_approx(Vector2(512.0, 512.0)):
		return "Downtown should be the 512 m square north of Old Town (%s)" % rect
	var router := RoadRouter.for_graph(world.get_lane_graph())
	var plaza := Vector3(-80.0, 0.0, -552.0)
	var route: PackedVector3Array = router.route(Vector3(97.0, 0.0, 4.75), plaza)
	if route.size() < 2 or Vector2(route[route.size() - 1].x - plaza.x, route[route.size() - 1].z - plaza.z).length() > 40.0:
		return "no road route from the bus stand to Central Plaza (%d points)" % route.size()
	var length: float = 0.0
	for i: int in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var skyline := world.get_node_or_null("Landmarks/Skyline") as MeshInstance3D
	if skyline == null or skyline.mesh == null or skyline.mesh.get_aabb().end.y < 60.0:
		return "the towers should have stand-ins on the always-loaded skyline"
	var edge := world.get_node_or_null("Landmarks/CityEdge") as StaticBody3D
	if edge == null or edge.get_child_count() < 6:
		return "walls should close the edge of the city (Landmarks/CityEdge)"
	# Walk into Downtown: the chunks there load, towers stand in them, the HUD names the district.
	var player: PlayerController = _player()
	var regions := game.get_node("Regions") as RegionWatcher
	var back := Transform3D(Basis(Vector3.UP, player.model.rotation.y), player.global_position)
	game.place_player(Transform3D(Basis.IDENTITY, Vector3(8.0, 0.25, -400.0)))   # sidewalk of the north road
	var frames: int = 0
	while frames < 120 and regions.get_current_name() != "Downtown":
		await get_tree().physics_frame
		frames += 1
	await _physics_frames(5)
	var title: String = _hud().get_area_title()
	var towers: int = 0
	for c: Vector2i in world.streamer.get_loaded_coords():
		for b: Node in world.streamer.get_chunk(c).get_node("Buildings").get_children():
			towers += 1 if str(b.name).contains("dt_tower") else 0
	var on_floor: bool = player.is_on_floor()
	game.place_player(back)
	await _physics_frames(40)
	if regions.get_current_name() != "Downtown" and title != "DOWNTOWN":
		return "walking into Downtown should show its name (district '%s', title '%s')" % [regions.get_current_name(), title]
	if title != "DOWNTOWN":
		return "the DOWNTOWN title card should show on arrival (got '%s')" % title
	if towers < 5:
		return "only %d towers loaded around Downtown's north road" % towers
	if not on_floor:
		return "the player should stand on Downtown's sidewalk"
	if regions.get_current_name() != "Old Town":
		return "back at the bus stand the player should be in Old Town again (%s)" % regions.get_current_name()
	print("  ok  Downtown: the 512 m square north of Old Town, its streets carry on from Old Town's (route to Central Plaza %.0f m by road), %d police stations in the city, %d towers around its north road, DOWNTOWN title card on arrival, skyline stand-ins and walls at the city's edge" % [
		length, data.police_stations.size(), towers])
	return ""


## M7: the Beach District east of Old Town. Its streets carry on from Old Town's, the sea and the
## lighthouse beam are on the always-loaded landmarks, pedestrians' navmesh stops at the water's
## edge, and walking out to sea you can wade in but not past the barrier.
func _check_beach() -> String:
	var game := get_tree().current_scene as GameSession
	var world: CityWorld = _world()
	var data: CityData = world.data
	var beach: int = data.region_names.find("Beach District")
	if beach < 0 or not data.region_rects[beach].has_point(Vector2(512.0, 0.0)):
		return "the Beach District should be the 512 m square east of Old Town (%s)" % data.region_names
	var router := RoadRouter.for_graph(world.get_lane_graph())
	var coast := Vector3(BeachLayout.COAST_ROAD + 512.0 - 3.0, 0.0, 60.0)
	var route: PackedVector3Array = router.route(Vector3(97.0, 0.0, 4.75), coast)
	if route.size() < 2 or Vector2(route[route.size() - 1].x - coast.x, route[route.size() - 1].z - coast.z).length() > 30.0:
		return "no road route from the bus stand to the Coast Road (%d points)" % route.size()
	var sea := world.get_node_or_null("Landmarks/Sea") as MeshInstance3D
	if sea == null or sea.mesh == null or sea.mesh.get_aabb().end.x < 2000.0:
		return "the sea should be on the always-loaded landmarks, out past the edge of the city"
	if world.get_node_or_null("Landmarks/Beam0") == null:
		return "the lighthouse should have its beam"
	var player: PlayerController = _player()
	var back := Transform3D(Basis(Vector3.UP, player.model.rotation.y), player.global_position)
	var shore: float = CityLayout.COAST_X
	var barrier: float = 512.0 + BeachLayout.BARRIER
	game.place_player(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(shore - 12.0, 0.3, -60.0)))   # on the sand, facing the sea
	var regions := game.get_node("Regions") as RegionWatcher
	var wait: int = 0
	while wait < 120 and regions.get_current_name() != "Beach District":
		await get_tree().physics_frame
		wait += 1
	await _physics_frames(5)
	var nav_map: RID = player.get_world_3d().navigation_map
	var on_shore: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, Vector3(shore + 60.0, 0.3, -60.0))
	var title: String = _hud().get_area_title()
	var furthest: float = player.global_position.x
	_key(KEY_W, true)
	for i: int in 900:
		await get_tree().physics_frame
		furthest = maxf(furthest, player.global_position.x)
	_key(KEY_W, false)
	var wading: bool = player.global_position.x > shore and player.is_on_floor()
	game.place_player(back)
	await _physics_frames(30)
	if title != "BEACH DISTRICT":
		return "the BEACH DISTRICT title card should show on arrival (got '%s')" % title
	if on_shore.x > shore + 1.0:
		return "pedestrians' navmesh should stop at the water's edge (nearest walkable point to the sea at x %.1f)" % on_shore.x
	if furthest < shore + 10.0 or furthest > barrier:
		return "walking out to sea you should wade in but stop at the barrier (got as far as x %.1f; water from %.0f, barrier at %.0f)" % [furthest, shore, barrier]
	if not wading:
		return "the player should be standing in the shallows when stopped by the barrier"
	print("  ok  Beach District: east of Old Town, a road route to the Coast Road, the sea and the lighthouse beam always loaded, BEACH DISTRICT title card; pedestrians stay on the sand; you can wade %.0f m out, no further" % [
		furthest - shore])
	return ""


## M7: the Industrial Zone north of the Beach, east of Downtown: streets from both carry on into
## it, the harbour cranes are always in view, its streets have sodium lamps (lit by the
## street-light pool too), and an arrest there ends at its own police post.
func _check_industrial() -> String:
	var game := get_tree().current_scene as GameSession
	var world: CityWorld = _world()
	var data: CityData = world.data
	var zone: int = data.region_names.find("Industrial Zone")
	if zone < 0 or not data.region_rects[zone].has_point(Vector2(512.0, -512.0)):
		return "the Industrial Zone should be the 512 m square north of the Beach District (%s)" % data.region_names
	var router := RoadRouter.for_graph(world.get_lane_graph())
	var berth := Vector3(512.0 + IndustrialLayout.HARBOUR_ROAD - 3.0, 0.0, -600.0)
	var from_downtown: PackedVector3Array = router.route(Vector3(200.0, 0.0, -514.75), berth)
	var from_beach: PackedVector3Array = router.route(Vector3(525.0, 0.0, -150.0), berth)
	for route: PackedVector3Array in [from_downtown, from_beach]:
		if route.size() < 2 or Vector2(route[route.size() - 1].x - berth.x, route[route.size() - 1].z - berth.z).length() > 30.0:
			return "no road route to the harbour from Downtown and from the Beach"
	var cranes := world.get_node_or_null("Landmarks/Temple/bld_in_crane") as InstanceBatch
	if cranes == null or cranes.get_instance_count() != 3:
		return "the three harbour cranes should be on the always-loaded landmarks"
	if data.police_stations.size() < 4:
		return "every district so far should have a police station (%d)" % data.police_stations.size()
	var player: PlayerController = _player()
	var back := Transform3D(Basis(Vector3.UP, player.model.rotation.y), player.global_position)
	game.place_player(Transform3D(Basis.IDENTITY, Vector3(442.0, 0.3, -470.0)))
	await _physics_frames(10)
	var sodium: int = 0
	for c: Vector2i in world.streamer.get_loaded_coords():
		var batch := world.streamer.get_chunk(c).get_node_or_null("Props/prop_streetlight_sodium") as InstanceBatch
		sodium += batch.get_instance_count() if batch != null else 0
	var pool: StreetLightPool = (game.get_node("DayNight") as DayNightCycle).street_lights
	var lamps: int = pool.get_lamp_count()
	var station: Vector3 = data.nearest_police_station(player.global_position).origin
	game.place_player(back)
	await _physics_frames(30)
	if sodium < 10 or lamps < sodium:
		return "the Industrial Zone's streets should have sodium lamps that the street-light pool knows (%d lamps, pool %d)" % [sodium, lamps]
	if not data.region_rects[zone].has_point(Vector2(station.x, station.z)):
		return "an arrest in the Industrial Zone should end at its own police post (nearest is at %s)" % station
	print("  ok  Industrial Zone: routes in from Downtown and from the Beach, three harbour cranes on the skyline, %d sodium lamps around its west side (in the street-light pool), its own police post" % sodium)
	return ""


func _check_traffic_signals() -> String:
	var signals: Array[Node] = get_tree().get_nodes_in_group(TrafficSignal.GROUP)
	if signals.size() < 4:
		return "only %d traffic signals are loaded around the spawn" % signals.size()
	var sig := signals[0] as TrafficSignal
	var cycle: float = sig.timing.cycle_seconds()
	var seen: Dictionary = {}
	var t: float = 0.0
	while t < cycle:
		var a: int = sig.light_at(t, 0)
		var b: int = sig.light_at(t, 1)
		if a != TrafficSignal.Light.RED and b != TrafficSignal.Light.RED:
			return "both directions get green or amber at %.2f s into the cycle" % t
		seen[Vector2i(0, a)] = true
		seen[Vector2i(1, b)] = true
		t += 0.25
	for axis: int in 2:
		for light: int in 3:
			if not seen.has(Vector2i(axis, light)):
				return "direction %d never shows %s" % [axis, TrafficSignal.Light.keys()[light]]
	sig.set_time(1.0)
	if sig.get_lamp_energy(0, TrafficSignal.Light.GREEN) < 1.0 or sig.get_lamp_energy(0, TrafficSignal.Light.RED) > 0.5 \
			or sig.get_lamp_energy(1, TrafficSignal.Light.RED) < 1.0:
		return "the signal lamps don't follow the lights (north-south green, east-west red)"
	if sig.get_child_count() < 3:
		return "junction %d has only %d signal poles" % [sig.junction_id, sig.get_child_count()]
	print("  ok  %d traffic signals loaded; over a %.0f s cycle each direction gets green, amber and red, never two greens at once; lamps follow the lights" % [
		signals.size(), cycle])
	return ""


func _check_lane_graph() -> String:
	var lanes: LaneGraph = _world().get_lane_graph()
	if lanes == null or lanes.size() < 1000:
		return "the lane graph is missing or tiny"
	var disconnected: int = lanes.count_disconnected()
	if disconnected != 0:
		return "%d lane nodes are dead ends or can't be reached" % disconnected
	# Keep left: on the north road (x = 0, a main road) northbound lanes are west of the centre.
	var kept_left: int = 0
	var wrong_side: int = 0
	for i: int in lanes.size():
		var p: Vector3 = lanes.get_position(i)
		if absf(p.x) > 6.0 or p.z < -175.0 or p.z > -155.0 \
				or lanes.has_flag(i, LaneGraph.Flag.IN_JUNCTION) or lanes.has_flag(i, LaneGraph.Flag.U_TURN):
			continue
		var next: PackedInt32Array = lanes.get_next(i)
		if next.is_empty() or absf(lanes.get_position(next[0]).z - p.z) < 0.5:
			continue
		var northbound: bool = lanes.get_position(next[0]).z < p.z
		if northbound == (p.x < 0.0):
			kept_left += 1
		else:
			wrong_side += 1
	if kept_left < 4 or wrong_side > 0:
		return "traffic should keep left on the north road (%d nodes on the left, %d on the right)" % [kept_left, wrong_side]
	# Every stop line at traffic lights near the player belongs to a loaded TrafficSignal.
	var signal_ids: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(TrafficSignal.GROUP):
		signal_ids[(node as TrafficSignal).junction_id] = true
	var here: Vector3 = _player().global_position
	var stops: int = 0
	var lit: int = 0
	var unmatched: int = 0
	for i: int in lanes.size():
		if not lanes.has_flag(i, LaneGraph.Flag.STOP_LINE):
			continue
		stops += 1
		if lanes.has_flag(i, LaneGraph.Flag.SIGNALIZED):
			lit += 1
			if lanes.get_position(i).distance_to(here) < 150.0 and not signal_ids.has(lanes.junction[i]):
				unmatched += 1
	if lit == 0 or unmatched > 0:
		return "stop lines at traffic lights: %d, %d of them near the player have no signal loaded" % [lit, unmatched]
	print("  ok  lane graph: %d nodes, all connected (no dead ends), traffic keeps left, %d stop lines (%d at traffic lights, each matched to its signal)" % [
		lanes.size(), stops, lit])
	return ""


## Pedestrians walk sidewalks and cross at crossings: the middle of a road is not on the navmesh,
## and getting to the far side of the gopuram road means walking round by the zebra crossing.
func _check_navmesh() -> String:
	var map: RID = _player().get_world_3d().navigation_map
	var north_walk := Vector3(70.0, 0.15, -8.0)
	var south_walk := Vector3(70.0, 0.15, 8.0)
	# Navigation regions are processed in the background: wait until the map has synced the
	# chunks (streamed back in by the earlier checks). The map rebuilds on a thread in real time,
	# so wait by the clock (with --fixed-fps 60 frames go by faster than real time).
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 20000 and _flat(NavigationServer3D.map_get_closest_point(map, south_walk)).distance_to(_flat(south_walk)) > 0.6:
		await get_tree().physics_frame
	var sync_seconds: float = (Time.get_ticks_msec() - started) / 1000.0
	var regions: int = NavigationServer3D.map_get_regions(map).size()
	if regions < 4:
		return "only %d navmesh regions are registered" % regions
	var a: Vector3 = NavigationServer3D.map_get_closest_point(map, north_walk)
	var b: Vector3 = NavigationServer3D.map_get_closest_point(map, south_walk)
	if _flat(a).distance_to(_flat(north_walk)) > 0.6 or _flat(b).distance_to(_flat(south_walk)) > 0.6:
		return "the sidewalks either side of the road are not on the navmesh (%s, %s)" % [a, b]
	var road_middle := Vector3(66.0, 0.0, 0.0)
	var nearest: Vector3 = NavigationServer3D.map_get_closest_point(map, road_middle)
	if _flat(nearest).distance_to(_flat(road_middle)) < 2.0:
		return "the middle of the road is walkable (navmesh at %s)" % nearest
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, a, b, true)
	var length: float = _path_length(path)
	if path.is_empty() or _flat(path[path.size() - 1]).distance_to(_flat(b)) > 0.6:
		return "no walking route across the gopuram road"
	if length < 25.0:
		return "the walk across the road is only %.1f m: it should detour to the zebra crossing" % length
	# A walk along the north temple plaza crosses the border between two chunks (x = 0).
	var west: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(-20.0, 0.15, -40.0))
	var east: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(20.0, 0.15, -40.0))
	var across: PackedVector3Array = NavigationServer3D.map_get_path(map, west, east, true)
	if across.is_empty() or _flat(across[across.size() - 1]).distance_to(_flat(east)) > 0.6 or _path_length(across) > 70.0:
		return "no sensible route along the temple plaza across the chunk border (%.1f m)" % _path_length(across)
	# No walkable islands inside buildings (a closed hull's floor once read as open ground).
	var space: PhysicsDirectSpaceState3D = _player().get_world_3d().direct_space_state
	var probe := PhysicsPointQueryParameters3D.new()
	probe.collision_mask = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var here: Vector3 = _player().global_position
	for i: int in 400:
		var p: Vector3 = NavigationServer3D.map_get_closest_point(map, here + Vector3(rng.randf_range(-120.0, 120.0), 0.0, rng.randf_range(-120.0, 120.0)))
		probe.position = p + Vector3.UP * 0.6
		if p != Vector3.ZERO and not space.intersect_point(probe, 1).is_empty():
			return "the navmesh at %s is inside solid geometry (a building?)" % p
	print("  ok  navmesh: %d regions (synced in %.1f s); roads aren't walkable; crossing the road detours %.0f m via the zebra; routes join across chunk borders; none of 400 sampled points is inside a building" % [
		regions, sync_seconds, length])
	return ""


func _path_length(path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _teleport(player: PlayerController, pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	player.camera_rig.snap_to_target()
	await _physics_frames(15)


func _hold(code: Key, frames: int) -> void:
	_key(code, true)
	await _physics_frames(frames)
	_key(code, false)
	await _physics_frames(20)


func _check_camera() -> String:
	var player: PlayerController = _player()
	var rig: ThirdPersonCamera = player.camera_rig
	if not rig.camera.current:
		return "player camera is not the current camera"
	var pivot: Vector3 = player.global_position + Vector3.UP * rig.settings.pivot_height
	if rig.global_position.distance_to(pivot) > 1.0:
		return "camera rig is %.2f m from the player's pivot" % rig.global_position.distance_to(pivot)
	var cam_distance: float = rig.camera.global_position.distance_to(rig.global_position)
	if cam_distance < 2.0:
		return "camera sits only %.2f m from the pivot in open space" % cam_distance
	var yaw_before: float = rig.get_yaw()
	Input.action_press("look_right", 1.0)
	await _process_frames(20)
	Input.action_release("look_right")
	if absf(angle_difference(yaw_before, rig.get_yaw())) < 0.05:
		return "right-stick look did not turn the camera"
	rig.set_view_degrees(0.0, -200.0)
	if rig.get_pitch() < deg_to_rad(rig.settings.min_pitch_degrees) - 0.001:
		return "camera pitch is not clamped"
	rig.set_view_degrees(0.0, rig.settings.default_pitch_degrees)
	print("  ok  camera follows (arm %.1f m), stick look turns it, pitch is clamped" % cam_distance)
	return ""


func _check_hud() -> String:
	var game: Node = get_tree().current_scene
	var hud := game.get_node("HUD") as Hud
	var player: PlayerController = _player()
	if absf(hud.get_health_shown() - player.stats.health) > 0.01:
		return "HUD health %.1f does not match player health %.1f" % [hud.get_health_shown(), player.stats.health]
	player.stats.apply_damage(25.0)
	if absf(hud.get_health_shown() - player.stats.health) > 0.01:
		return "HUD health bar did not follow damage"
	if absf(hud.get_stamina_shown() - player.stats.stamina) > 0.01:
		return "HUD stamina bar does not match player stamina"
	if hud.is_fps_visible():
		return "FPS counter should start hidden"
	_key(KEY_F3, true)
	_key(KEY_F3, false)
	await _process_frames(2)
	var shown: bool = hud.is_fps_visible()
	var readout: String = (_find(hud, "FpsLabel") as Label).text
	if not (readout.contains("FPS") and readout.contains("chunks") and readout.contains("cars") and readout.contains("people")):
		return "the F3 readout should show FPS, chunks, cars and people (got '%s')" % readout.replace("\n", " | ")
	_key(KEY_F3, true)
	_key(KEY_F3, false)
	await _process_frames(2)
	if not shown or hud.is_fps_visible():
		return "F3 did not toggle the FPS counter on and off"
	# Wanted level (the police test covers the rest): a new game starts clean, no police about.
	var police := game.get_node_or_null("Police") as PoliceManager
	if police == null or WantedSystem.is_wanted() or hud.get_wanted_display().visible:
		return "a new game should start with nobody after you and no wanted stars on the HUD"
	if not police.get_cars().is_empty() or not police.get_officers().is_empty():
		return "no police should be about at level 0"
	var figure := player.get_node_or_null("Model/Figure") as PlayerFigure
	if figure == null or figure.mesh == null or figure.get_outfit() == null or figure.get_outfit().id != &"arrival":
		return "the player should be the character model in their travelling clothes"
	var places := game.get_node_or_null("Places") as PlaceDirector
	if places == null or places.get_map_blips().size() != 2:
		return "at the start the tiffin stall and the garage should be on the map (the clothes shop and the house come later)"
	var stations: Array[Transform3D] = (game.get_node("World") as CityWorld).data.police_stations
	if stations.size() < 2 or stations[0].origin == Vector3.ZERO:
		return "Old Town and Downtown should each have a police station to release you at (%d)" % stations.size()
	print("  ok  HUD health/stamina bars follow the player; F3 toggles the FPS / chunks / cars / people readout; no wanted stars or police at the start; the player is the character model in travelling clothes; the tiffin stall and garage on the map")
	return ""


# --------------------------------------------------------------------------- vehicle

func _check_vehicle_parked() -> String:
	var car: VehicleController = _car()
	if car == null:
		return "no sedan at " + SEDAN_PATH
	if not car.is_in_group(VehicleController.GROUP):
		return "the sedan is not in the vehicles group"
	var down: int = 0
	for wheel: VehicleWheel3D in car.get_wheels():
		down += 1 if wheel.is_in_contact() else 0
	if down != 4:
		return "the parked sedan has %d wheels on the road" % down
	if car.linear_velocity.length() > 0.05 or car.is_occupied() or car.is_engine_running():
		return "the parked sedan should be still, empty and switched off"
	if _hud().is_speedometer_visible():
		return "the speedometer shows while on foot"
	# Walk into it (camera yaw 0, so A = west, towards its back): the player is blocked and
	# the car doesn't budge.
	var player: PlayerController = _player()
	var parked_at: Vector3 = car.global_position
	player.camera_rig.set_view_degrees(0.0, -12.0)
	await _teleport(player, Vector3(parked_at.x + 3.5, 0.05, parked_at.z))
	await _hold(KEY_A, 90)
	var shoved: float = car.global_position.distance_to(parked_at)
	var gap: float = player.global_position.x - parked_at.x
	if gap < 1.1 or shoved > 0.03:
		return "walking into the parked car: player %.2f m from its centre line, car shoved %.3f m" % [gap, shoved]
	print("  ok  sedan parked at the kerb: 4 wheels down, still, empty, engine off; walking into it is blocked (car moved %.3f m)" % shoved)
	return ""


func _check_enter_vehicle() -> String:
	var player: PlayerController = _player()
	var car: VehicleController = _car()
	var hud: Hud = _hud()
	var driver_side: Vector3 = -car.global_basis.x
	await _teleport(player, _flat(car.global_position) + driver_side * 6.0 + Vector3.UP * 0.05)
	if hud.get_prompt_text() != "":
		return "the 'get in' prompt shows 6 m from the car"
	await _teleport(player, _flat(car.global_position) + driver_side * 2.2 + Vector3.UP * 0.05)
	var prompt: String = hud.get_prompt_text()
	if not prompt.begins_with("F") or not prompt.contains("GET IN"):
		return "no 'F  GET IN' prompt next to the car (got '%s')" % prompt
	_tap(KEY_F)
	await _physics_frames(4)
	if player.state != PlayerController.State.ENTER_VEHICLE:
		return "F next to the car did not start getting in (state %s)" % player.get_state_name()
	await _physics_frames(40)
	if not player.is_in_vehicle() or car.get_driver() != player:
		return "the player is not in the driver's seat after getting in (state %s)" % player.get_state_name()
	if player.model.visible or not (player.get_node("CollisionShape3D") as CollisionShape3D).disabled:
		return "the player should be hidden with collision off while driving"
	if not car.is_engine_running():
		return "the engine did not start"
	if hud.get_prompt_text() != "":
		return "the 'get in' prompt still shows inside the car"
	await _physics_frames(45)  # camera hand-over
	if not _vehicle_camera().camera.current:
		return "the vehicle camera did not take over"
	if not hud.is_speedometer_visible():
		return "the speedometer is not shown while driving"
	print("  ok  'F  GET IN' prompt within reach (not from 6 m); F gets in: player hidden, engine on, vehicle camera, speedometer")
	return ""


func _check_drive_brake_reverse() -> String:
	var car: VehicleController = _car()
	var hud: Hud = _hud()
	var engine := car.get_node("Engine") as VehicleEngine
	var audio := car.get_node("Audio") as VehicleAudio
	await _place_car(car, TEST_ROAD)
	var start: Vector3 = car.global_position
	var heading: Vector3 = car.global_basis.z
	var front_wheel: VehicleWheel3D = car.get_node("WheelFrontLeft") as VehicleWheel3D
	var spun: bool = false
	var wheel_basis: Basis = front_wheel.transform.basis
	_key(KEY_W, true)
	for i: int in 180:
		await get_tree().physics_frame
		if i % 7 == 0:
			spun = spun or not front_wheel.transform.basis.is_equal_approx(wheel_basis)
			wheel_basis = front_wheel.transform.basis
	var kmh: float = car.get_speed_kmh()
	var moved: Vector3 = car.global_position - start
	var wheel_rpm: float = absf(car.get_wheels()[0].get_rpm())
	var gear: int = engine.gear
	var audible: bool = audio.is_engine_audible()
	await _process_frames(1)
	var shown: int = hud.get_speed_shown()
	_key(KEY_W, false)
	if kmh < 35.0:
		return "3 s of throttle reached only %.0f km/h" % kmh
	var along: float = moved.dot(heading)
	if along < 15.0 or (moved - heading * along).length() > 1.5:
		return "the car should drive straight ahead; it moved %s" % moved
	if absi(shown - roundi(kmh)) > 2:
		return "the speedometer shows %d km/h, the car does %.0f" % [shown, kmh]
	if wheel_rpm < 100.0 or gear < 2 or not audible:
		return "wheels %.0f rpm, gear %d, engine audible %s" % [wheel_rpm, gear, audible]
	if not spun:
		return "the front wheel model did not visibly spin while driving"

	_key(KEY_S, true)
	var frames: int = 0
	var braked_from: Vector3 = car.global_position
	while car.get_forward_speed() > 0.5 and frames < 240:
		await get_tree().physics_frame
		frames += 1
	var stop_distance: float = braked_from.distance_to(car.global_position)
	if frames >= 240:
		return "holding S did not stop the car"
	await _physics_frames(90)  # keep holding S at a standstill: reverse
	var reverse_kmh: float = car.get_forward_speed() * 3.6
	await _process_frames(1)
	var gear_shown: String = hud.get_gear_shown()
	_key(KEY_S, false)
	await _stop_car(car)
	if reverse_kmh > -4.0:
		return "holding S at a standstill did not reverse (%.1f km/h)" % reverse_kmh
	if gear_shown != "R":
		return "the speedometer shows gear '%s' while reversing" % gear_shown
	print("  ok  W: %.0f km/h in 3 s, %.0f m straight on (speedometer %d, gear %d, engine audible, wheels spin); S: stopped in %.1f m, then reversed at %.0f km/h (gear R)" % [
		kmh, along, shown, gear, stop_distance, reverse_kmh])
	return ""


func _check_steering() -> String:
	var car: VehicleController = _car()
	await _place_car(car, TEST_ROAD)
	var start_heading: float = _heading(car)
	var max_steer: float = 0.0
	var max_axle_turn: float = 0.0
	var front_wheel: VehicleWheel3D = car.get_node("WheelFrontLeft") as VehicleWheel3D
	_key(KEY_W, true)
	_key(KEY_A, true)
	for i: int in 90:
		await get_tree().physics_frame
		max_steer = maxf(max_steer, car.get_steer_angle())
		# The wheel's axle (its X axis) swings round as it steers; spinning alone never moves it.
		max_axle_turn = maxf(max_axle_turn, absf(front_wheel.transform.basis.x.z))
	_key(KEY_A, false)
	_key(KEY_W, false)
	var turned: float = angle_difference(start_heading, _heading(car))
	await _stop_car(car)
	if max_steer < 0.2:
		return "the front wheels did not turn left (max %.2f rad)" % max_steer
	if max_axle_turn < sin(0.2):
		return "the front wheel model did not visibly steer (axle turned %.2f)" % max_axle_turn
	if turned < deg_to_rad(20.0):
		return "W + A for 1.5 s should turn the car left; it turned %.0f deg" % rad_to_deg(turned)
	print("  ok  A steers left: front wheels (and their models) up to %.0f deg, car turned %.0f deg in 1.5 s" % [
		rad_to_deg(max_steer), rad_to_deg(turned)])
	return ""


func _check_vehicle_cameras() -> String:
	var car: VehicleController = _car()
	var cam: VehicleCamera = _vehicle_camera()
	await _place_car(car, TEST_ROAD)
	_key(KEY_W, true)
	await _physics_frames(90)   # the chase camera swings in behind a moving car
	_key(KEY_W, false)
	var to_camera: Vector3 = cam.camera.global_position - car.global_position
	var behind: float = to_camera.dot(car.global_basis.z)
	await _stop_car(car)
	if behind > -2.0 or to_camera.length() < 4.0:
		return "the chase camera should sit behind the car (%.1f m behind, %.1f m away)" % [-behind, to_camera.length()]
	_tap(KEY_V)
	await _process_frames(3)
	if cam.mode != VehicleCamera.Mode.HOOD:
		return "V did not switch to the hood camera"
	var hood: Vector3 = (car.get_node("HoodCamera") as Node3D).global_position
	var ahead: float = (-cam.camera.global_basis.z).dot(car.global_basis.z)
	if cam.camera.global_position.distance_to(hood) > 0.3 or ahead < 0.9:
		return "the hood camera should sit on the hood looking ahead (%.2f m off, facing %.2f)" % [
			cam.camera.global_position.distance_to(hood), ahead]
	_tap(KEY_V)
	await _process_frames(3)
	if cam.mode != VehicleCamera.Mode.CHASE:
		return "a second V did not return to the chase camera"
	print("  ok  chase camera %.1f m behind the moving car; V switches to the hood camera and back" % -behind)
	return ""


func _check_horn_and_lights() -> String:
	var car: VehicleController = _car()
	var audio := car.get_node("Audio") as VehicleAudio
	var lights := car.get_node("Lights") as VehicleLights
	_key(KEY_H, true)
	await _physics_frames(3)
	var horn_on: bool = car.is_horn_on() and audio.is_horn_playing()
	_key(KEY_H, false)
	await _physics_frames(3)
	var horn_off: bool = not car.is_horn_on() and not audio.is_horn_playing()
	if not horn_on or not horn_off:
		return "holding H should sound the horn and releasing it stop it (on %s, off %s)" % [horn_on, horn_off]
	_tap(KEY_L)
	await _physics_frames(2)
	var lit: bool = car.are_headlights_on() and lights.are_beams_visible() and lights.get_headlight_glow() > 1.0
	_tap(KEY_L)
	await _physics_frames(2)
	var dark: bool = not car.are_headlights_on() and not lights.are_beams_visible() and lights.get_headlight_glow() < 0.01
	if not lit or not dark:
		return "L should switch the headlights on and off (on %s, off %s)" % [lit, dark]
	print("  ok  H sounds the horn while held; L switches the headlights (beams and lenses) on and off")
	return ""


func _check_crash_damage() -> String:
	var car: VehicleController = _car()
	var hud: Hud = _hud()
	var damage := car.get_node("Damage") as VehicleDamage
	await _place_car(car, TEST_ROAD)
	var wall: StaticBody3D = _temp_wall(Vector3(TEST_ROAD.x - 16.0, 1.5, 112.0), Vector3(1.0, 3.0, 13.0))
	var before: float = damage.health
	var impacts: Array = []
	var on_impact := func(impact_kmh: float, _amount: float) -> void: impacts.append(impact_kmh)
	damage.impacted.connect(on_impact)
	_key(KEY_W, true)
	var frames: int = 0
	while impacts.is_empty() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_key(KEY_W, false)
	await _physics_frames(30)
	damage.impacted.disconnect(on_impact)
	wall.queue_free()
	var lost: float = before - damage.health
	if impacts.is_empty() or lost <= 0.0:
		return "driving into a wall did no damage"
	await _process_frames(1)
	if absf(hud.get_car_health_shown() - damage.health) > 0.01:
		return "the HUD car-health bar (%.0f) doesn't match the car (%.0f)" % [hud.get_car_health_shown(), damage.health]
	damage.apply_damage(damage.health - car.stats.max_health * 0.2)
	await _physics_frames(2)
	if not damage.is_smoking():
		return "no engine smoke at 20% health"
	print("  ok  hitting a wall at %.0f km/h cost %.0f health (HUD bar matches); the engine smokes at 20%% health" % [
		float(impacts[0]), lost])
	return ""


func _check_pause_in_vehicle() -> String:
	var car: VehicleController = _car()
	await _place_car(car, TEST_ROAD)
	_key(KEY_W, true)
	await _physics_frames(60)
	_tap(KEY_ESCAPE)
	await _process_frames(2)
	if not get_tree().paused:
		return "Esc did not pause while driving"
	var frozen_at: Vector3 = car.global_position
	await _physics_frames(30)
	_key(KEY_W, false)
	var drift: float = car.global_position.distance_to(frozen_at)
	_tap(KEY_ESCAPE)
	await _process_frames(2)
	if get_tree().paused:
		return "Esc did not resume"
	await _stop_car(car)
	if drift > 0.001:
		return "the car moved %.3f m while paused" % drift
	print("  ok  pausing while driving freezes the car; Esc resumes")
	return ""


func _check_exit_vehicle() -> String:
	var player: PlayerController = _player()
	var car: VehicleController = _car()
	var hud: Hud = _hud()
	await _place_car(car, TEST_ROAD)
	_tap(KEY_F)
	await _physics_frames(5)
	if player.is_in_vehicle() or player.vehicle != null:
		return "F did not get the player out of a stopped car"
	var side: float = (player.global_position - car.global_position).dot(-car.global_basis.x)
	if side < 1.0:
		return "the player should step out of the driver's (right-hand) door; side offset %.2f m" % side
	await _physics_frames(30)
	if not player.is_on_floor() or not player.model.visible \
			or (player.get_node("CollisionShape3D") as CollisionShape3D).disabled:
		return "after getting out the player should be visible, solid and standing"
	if car.is_occupied() or car.is_engine_running():
		return "the car should be empty and switched off"
	await _physics_frames(20)
	if not player.camera_rig.camera.current or not player.camera_rig.is_active():
		return "the on-foot camera did not take back over"
	if hud.is_speedometer_visible():
		return "the speedometer still shows on foot"
	if not player.state in PlayerController.ON_FOOT_STATES:
		return "the player is stuck in state %s after getting out" % player.get_state_name()
	print("  ok  F in a stopped car: out of the driver's door, standing, on-foot camera back, car switched off")
	return ""


func _check_exit_at_speed() -> String:
	var player: PlayerController = _player()
	var car: VehicleController = _car()
	if not await _get_in(player, car):
		return "could not get back in from beside the driver's door"
	_key(KEY_W, true)
	await _physics_frames(90)
	_key(KEY_W, false)
	var speed_before: float = car.get_speed_kmh()
	_tap(KEY_F)
	var frames: int = 0
	var braked: bool = false
	while player.is_in_vehicle() and frames < 300:
		await get_tree().physics_frame
		braked = braked or car.is_braking()
		frames += 1
	if player.is_in_vehicle():
		return "the player never got out after asking at %.0f km/h" % speed_before
	var speed_at_exit: float = car.linear_velocity.length()
	if speed_before < 15.0 or not braked or speed_at_exit > player.tuning.vehicle_exit_max_speed + 0.5:
		return "asking to get out at %.0f km/h should brake first (braked %s, got out at %.1f m/s)" % [
			speed_before, braked, speed_at_exit]
	await _physics_frames(60)
	print("  ok  F at %.0f km/h: the car braked and the player got out at %.1f km/h, %.1f s later" % [
		speed_before, speed_at_exit * 3.6, frames / 60.0])
	return ""


func _check_exit_blocked_door() -> String:
	var player: PlayerController = _player()
	var car: VehicleController = _car()
	if not await _get_in(player, car):
		return "could not get back in"
	await _place_car(car, TEST_ROAD)
	var driver_side: Vector3 = -car.global_basis.x
	var wall: StaticBody3D = _temp_wall(car.global_position + driver_side * 1.6 + Vector3.UP * 1.0, Vector3(7.0, 3.0, 0.6))
	await _physics_frames(2)
	_tap(KEY_F)
	await _physics_frames(5)
	wall.queue_free()
	if player.is_in_vehicle():
		return "the player could not get out with the driver's door blocked"
	var side: float = (player.global_position - car.global_position).dot(car.global_basis.x)
	if side < 1.0:
		return "with the driver's door against a wall the player should use the passenger door (offset %.2f m)" % side
	await _physics_frames(40)
	print("  ok  driver's door against a wall: the player climbs out of the passenger side")
	return ""


func _get_in(player: PlayerController, car: VehicleController) -> bool:
	await _physics_frames(30)  # finish stepping out
	_tap(KEY_F)
	await _physics_frames(50)
	return player.is_in_vehicle() and car.get_driver() == player


## Teleports the car (with the player in it) to `pos` facing west, and lets it settle.
func _place_car(car: VehicleController, pos: Vector3) -> void:
	car.teleport(Transform3D(Basis(Vector3.UP, -PI / 2.0), pos))
	await _physics_frames(30)


## Holds S until the car has (nearly) stopped, without letting it reverse.
func _stop_car(car: VehicleController) -> void:
	_key(KEY_S, true)
	var frames: int = 0
	while absf(car.get_forward_speed()) > 0.4 and frames < 300:
		if car.get_forward_speed() < 0.0:
			break
		await get_tree().physics_frame
		frames += 1
	_key(KEY_S, false)
	await _physics_frames(20)


func _temp_wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.name = "TestWall"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	get_tree().current_scene.add_child(wall)
	wall.global_position = pos
	return wall


## Heading of a car's nose as a yaw angle (0 = +Z, positive = turned left).
func _heading(car: VehicleController) -> float:
	var forward: Vector3 = car.global_basis.z
	return atan2(forward.x, forward.z)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _check_pause_and_return_to_menu() -> String:
	var game: Node = get_tree().current_scene
	var pause := game.get_node("PauseMenu") as PauseMenu
	var player: PlayerController = _player()
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _process_frames(2)
	if not get_tree().paused or not pause.is_open():
		return "Esc did not pause the game and open the pause menu"
	var frozen_at: Vector3 = player.global_position
	_key(KEY_W, true)
	await _physics_frames(30)
	_key(KEY_W, false)
	if player.global_position.distance_to(frozen_at) > 0.001:
		return "player moved while paused"
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _process_frames(2)
	if get_tree().paused or pause.is_open():
		return "second Esc did not resume the game"
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _process_frames(2)
	# Save Game: the panel lists the autosave and three slots; saving to slot 1 works.
	(_find(pause, "SaveGameButton") as Button).pressed.emit()
	await _process_frames(2)
	var save_panel := _find(pause, "SavePanel") as SavePanel
	if save_panel == null or not save_panel.visible:
		return "pause menu's Save Game did not open the save panel"
	save_panel.get_row(1).pressed.emit()
	if save_panel.get_status_text() != "Saved to slot 1." or SaveManager.read_slot(1).is_empty():
		return "saving to slot 1 from the pause menu failed ('%s')" % save_panel.get_status_text()
	save_panel.close()
	await _process_frames(2)
	(_find(pause, "MainMenuButton") as Button).pressed.emit()
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	if menu == null:
		return "pause menu's Main Menu button did not return to the main menu"
	if get_tree().paused:
		return "tree is still paused after returning to the main menu"
	if (_find(menu, "ContinueButton") as Button).disabled or (_find(menu, "LoadGameButton") as Button).disabled:
		return "after saving, Continue and Load Game should be enabled on the title screen"
	for slot: int in SaveManager.ALL_SLOTS:
		SaveManager.delete_slot(slot)
	print("  ok  Esc pauses (player frozen) and resumes; Save Game saves to a slot; Main Menu returns to the title screen, where Continue and Load Game are now enabled")
	return ""


# --------------------------------------------------------------------------- helpers

func _player() -> PlayerController:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null("Player") as PlayerController if scene != null else null


func _world() -> CityWorld:
	return get_tree().current_scene.get_node("World") as CityWorld


func _car() -> VehicleController:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null(SEDAN_PATH) as VehicleController if scene != null else null


func _hud() -> Hud:
	return get_tree().current_scene.get_node("HUD") as Hud


func _vehicle_camera() -> VehicleCamera:
	return get_tree().current_scene.get_node("VehicleCamera") as VehicleCamera


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _release_all_keys() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_ESCAPE, KEY_F3,
			KEY_F, KEY_H, KEY_L, KEY_V]:
		_key(code, false)
	Input.action_release("look_right")


func _physics_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _process_frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _wait_for_scene(path: String, max_frames: int = 600) -> Node:
	for i: int in max_frames:
		var scene: Node = get_tree().current_scene
		if scene != null and scene.scene_file_path == path and scene.is_node_ready():
			return scene
		await get_tree().process_frame
	return null


func _on_timeout() -> void:
	_finish("timed out after %d s" % int(TIMEOUT_SEC))


func _finish(failure: String) -> void:
	if _finished:
		return
	_finished = true
	var errors: PackedStringArray = _catcher.get_errors()
	OS.remove_logger(_catcher)
	if failure == "" and not errors.is_empty():
		failure = "%d engine/script error(s) logged, first: %s" % [errors.size(), errors[0]]
	if failure == "":
		print("SMOKE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)
