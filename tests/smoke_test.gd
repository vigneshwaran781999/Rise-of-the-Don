extends Node
## Headless smoke test. Run from the project root:
##   "$GODOT" --headless --path . res://tests/smoke_test.tscn
## Prints "SMOKE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.
## Any engine or script error logged while it runs also fails the test.
##
## It drives the real game: main menu -> New Game -> walk, sprint, jump, look, HUD, pause ->
## back to the main menu. Input goes through the real input map (simulated key events).

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const TIMEOUT_SEC: float = 120.0
const MAIN_MENU: String = "res://scenes/main/main_menu.tscn"
const GAME: String = "res://scenes/main/game.tscn"
const TEST_CUBE_PATH: String = "res://assets/models/test/prop_test_cube.glb"
const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump",
	"look_left", "look_right", "look_up", "look_down",
	"vehicle_enter_exit", "interact", "pause", "toggle_fps",
]
const REQUIRED_BUSES: PackedStringArray = ["Master", "Music", "SFX", "Ambience", "UI"]
## Every generated asset must import with at least one auto-built collision body.
const COLLIDABLE_ASSETS: PackedStringArray = [
	"road/road_straight", "road/road_crosswalk", "road/road_intersection",
	"road/road_sidewalk", "road/road_sidewalk_corner",
	"buildings/bld_shophouse_01", "buildings/bld_shophouse_02", "buildings/bld_shophouse_03",
	"buildings/bld_apartment_01", "buildings/bld_apartment_02",
	"buildings/bld_office_01", "buildings/bld_office_02",
	"buildings/bld_temple_gopuram", "buildings/bld_temple_shrine",
	"props/prop_streetlight", "props/prop_palm_tree", "props/prop_temple_wall",
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
	Input.use_accumulated_input = false
	var failure: String = await _run_checks()
	_release_all_keys()
	_finish(failure)


func _run_checks() -> String:
	var steps: Array[Callable] = [
		_check_project_settings, _check_input_map, _check_audio_and_settings, _check_test_cube,
		_check_asset_collisions, _check_main_menu, _check_new_game, _check_spawn,
		_check_walk_forward, _check_sprint, _check_jump, _check_kerbs_ramps_and_gateway,
		_check_camera, _check_hud,
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
		node.free()
		if meshes < 1 or bodies < 1:
			return "%s should have a mesh and a '-colonly' body (meshes %d, bodies %d)" % [asset, meshes, bodies]
	print("  ok  %d Blender assets imported, each with visuals and collision" % COLLIDABLE_ASSETS.size())
	return ""


# --------------------------------------------------------------------------- menu -> game

func _check_main_menu() -> String:
	get_tree().change_scene_to_file(MAIN_MENU)
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	if menu == null:
		return "main menu did not load"
	for button_name: String in ["NewGameButton", "ContinueButton", "SettingsButton", "ControlsButton",
			"CreditsButton", "ExitButton"]:
		if _find(menu, button_name) == null:
			return "main menu has no %s" % button_name
	if not (_find(menu, "ContinueButton") as Button).disabled:
		return "Continue should be disabled while no save exists"

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
	print("  ok  main menu (buttons, Continue disabled, settings sliders work, controls, credits)")
	return ""


func _check_new_game() -> String:
	var menu: Node = get_tree().current_scene
	(_find(menu, "NewGameButton") as Button).pressed.emit()
	var game: Node = await _wait_for_scene(GAME)
	if game == null:
		return "New Game did not load the game scene"
	if _player() == null:
		return "game scene has no player"
	var buildings: Node = game.get_node_or_null("World/Buildings")
	var count: int = buildings.get_child_count() if buildings != null else 0
	if count < 8:
		return "expected the block to have 8-12 buildings (+ temple group), found %d nodes" % count
	print("  ok  New Game loads the city block (%d building nodes)" % count)
	return ""


# --------------------------------------------------------------------------- player

func _check_spawn() -> String:
	var player: PlayerController = _player()
	await _physics_frames(30)
	if not player.is_on_floor():
		return "player is not standing on the ground after spawning (y=%.2f)" % player.global_position.y
	print("  ok  player spawned and standing on the road (state %s)" % player.get_state_name())
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
	if flat.length() <= 3.0:
		return "holding W for 2 s moved the player only %.2f m" % flat.length()
	if moved.z > -2.5:
		return "W should move away from the camera (north, -Z); moved %s" % moved
	if not states.has(PlayerController.State.RUN):
		return "never entered RUN while holding W"
	await _physics_frames(30)
	print("  ok  holding W for 2 s moved the player %.1f m north" % flat.length())
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


## Walks over the bevelled kerb, up the 18-degree ramp, into the 50-degree ramp (must fail)
## and through the gopuram gateway. Camera yaw 0, so W = north, A = west, D = east.
func _check_kerbs_ramps_and_gateway() -> String:
	var player: PlayerController = _player()
	player.camera_rig.set_view_degrees(0.0, -12.0)

	await _teleport(player, Vector3(-4.0, 0.1, 30.0))
	await _hold(KEY_A, 60)
	if player.global_position.x > -6.6 or absf(player.global_position.y - 0.15) > 0.05:
		return "could not step west onto the sidewalk over the kerb (at %s)" % player.global_position

	await _teleport(player, Vector3(24.0, 0.25, 30.0))
	await _hold(KEY_D, 90)
	var platform_y: float = 1.15
	if absf(player.global_position.y - platform_y) > 0.08 or not player.is_on_floor():
		return "could not walk up the 18-degree ramp onto the platform (at %s)" % player.global_position

	await _teleport(player, Vector3(35.0, 0.25, 39.0))
	await _hold(KEY_W, 90)
	if player.global_position.y > 0.6:
		return "walked up the 50-degree ramp, which is steeper than the slope limit (y=%.2f)" % player.global_position.y

	await _teleport(player, Vector3(3.0, 0.1, 30.0))
	await _hold(KEY_D, 240)  # 4 s at 5 m/s: road -> kerb -> plinth -> passage -> courtyard (x ~ 23)
	if player.global_position.x < 21.0:
		return "could not walk east through the gopuram gateway into the courtyard (at %s)" % player.global_position

	await _teleport(player, Vector3(-3.0, 0.1, 30.0))
	print("  ok  kerb step-up, 18-degree ramp climbed, 50-degree ramp refused, walked through the gateway")
	return ""


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
	_key(KEY_F3, true)
	_key(KEY_F3, false)
	await _process_frames(2)
	if not shown or hud.is_fps_visible():
		return "F3 did not toggle the FPS counter on and off"
	print("  ok  HUD health/stamina bars follow the player; F3 toggles FPS")
	return ""


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
	(_find(pause, "MainMenuButton") as Button).pressed.emit()
	var menu: Node = await _wait_for_scene(MAIN_MENU)
	if menu == null:
		return "pause menu's Main Menu button did not return to the main menu"
	if get_tree().paused:
		return "tree is still paused after returning to the main menu"
	print("  ok  Esc pauses (player frozen) and resumes; Main Menu returns to the title screen")
	return ""


# --------------------------------------------------------------------------- helpers

func _player() -> PlayerController:
	var scene: Node = get_tree().current_scene
	return scene.get_node_or_null("Player") as PlayerController if scene != null else null


func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _release_all_keys() -> void:
	for code: Key in [KEY_W, KEY_A, KEY_D, KEY_SHIFT, KEY_SPACE, KEY_ESCAPE, KEY_F3]:
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
		get_tree().quit(0)
	else:
		print("FAILED: " + failure)
		get_tree().quit(1)
