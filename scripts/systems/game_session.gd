class_name GameSession
extends Node3D
## Root of the game scene. Starts a new game (fresh cash, stats and missions, player at the
## district spawn, the opening mission begins) or carries on from a loaded save (state restored,
## player where they saved, a running mission resumes at its checkpoint). Streams the city in
## around the player and runs its day and night, starts traffic and pedestrians, hooks the HUD up
## to the player and the missions, hands the view between the on-foot and vehicle cameras when
## the player gets in or out, takes a knocked-out player to hospital (M7), captures the mouse for
## camera look, and gives SaveManager the player's state.

const ENTER_BLEND_SECONDS: float = 0.6
const EXIT_BLEND_SECONDS: float = 0.45
## Knocked out, the player lies on the ground this long before the HOSPITALISED card.
const DOWN_SECONDS: float = 1.5

@onready var world: CityWorld = $World
@onready var player: PlayerController = $Player
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var vehicle_camera: VehicleCamera = $VehicleCamera
@onready var camera_transition: CameraTransition = $CameraTransition
@onready var lane_debug: LaneGraphDebug = $LaneDebug
@onready var traffic: TrafficManager = $Traffic
@onready var pedestrians: PedestrianManager = $Pedestrians
@onready var missions: MissionDirector = $Missions
@onready var day_night: DayNightCycle = $DayNight
@onready var gps: GpsNavigator = $Gps
@onready var map_screen: MapScreen = $MapScreen
@onready var police: PoliceManager = $Police
@onready var busted_screen: BustedScreen = $Busted
@onready var hospital_screen: HospitalScreen = $Hospital
@onready var choice_card: ChoiceCard = $Choice
@onready var places: PlaceDirector = $Places
@onready var shop_menu: ShopMenu = $ShopMenu
@onready var regions: RegionWatcher = $Regions
@onready var weather: WeatherCycle = $Weather
@onready var ambience: AmbienceDirector = $Ambience


func _ready() -> void:
	get_tree().paused = false
	var saved: Dictionary = SaveManager.take_pending_load()
	WantedSystem.clear()    # a new game or a loaded save starts with a clean record
	var start := Transform3D()
	if saved.is_empty():
		MissionManager.start_new_game()
		EconomyManager.start_new_game(MissionManager.story.starting_cash)
		GameState.start_new_game()
		start = world.get_spawn_transform()
	else:
		GameState.from_save(saved.get("game", {}))
		EconomyManager.from_save(saved.get("economy", {}))
		MissionManager.from_save(saved.get("missions", {}))
		start = _saved_transform(saved.get("player", {}))
	player.global_position = start.origin
	player.reset_physics_interpolation()
	world.start_streaming(player)
	# Face the way the start transform faces (its -Z), camera behind the player.
	var facing: Vector3 = -start.basis.z
	player.camera_rig.set_view_degrees(rad_to_deg(atan2(-facing.x, -facing.z)), player.camera_rig.settings.default_pitch_degrees)
	player.model.rotation.y = atan2(-facing.x, -facing.z)
	player.camera_rig.snap_to_target()
	if not saved.is_empty():
		player.stats.set_health(float((saved.get("player", {}) as Dictionary).get("health", player.stats.health)))
	hud.bind_player(player.stats)
	hud.bind_interactor(player.get_node("VehicleInteractor") as VehicleInteractor)
	regions.setup(player, world.data)
	_show_region(regions.get_current())
	regions.region_changed.connect(_show_region)
	ambience.setup(player, regions)
	(player.get_node("Audio") as PlayerAudio).city = world.data
	lane_debug.setup(world.get_lane_graph(), player, world)
	weather.set_weather(GameState.weather, true)     # a new game's clear sky, or the saved weather
	weather.setup(world.get_node("Lighting") as WorldLighting)
	day_night.weather = weather
	day_night.setup(world.get_node("Lighting") as WorldLighting, world.streamer)
	traffic.setup(world.get_lane_graph(), player, world.streamer)
	traffic.set_headlights(day_night.is_dark())
	day_night.darkness_changed.connect(traffic.set_headlights)
	pedestrians.setup(player, world.streamer)
	police.setup(player, world.streamer, world.get_lane_graph(), pedestrians)
	WantedSystem.busted.connect(_on_busted)
	player.died.connect(_on_player_died)
	missions.setup(player, world)
	missions.get_cutscene().playing_changed.connect(_on_cutscene_playing)
	missions.choice_requested.connect(choice_card.ask)
	choice_card.chosen.connect(missions.answer_choice)
	hud.bind_missions(missions, player)
	places.menu = shop_menu
	places.pause_menu = pause_menu
	places.setup(player, world.data, missions, police)
	hud.bind_places(places)
	gps.setup(world.get_lane_graph(), player, missions)
	hud.bind_map(player, world.data, gps)
	map_screen.setup(player, world.data, gps)
	pause_menu.map_screen = map_screen
	player.vehicle_entered.connect(_on_vehicle_entered)
	player.vehicle_exited.connect(_on_vehicle_exited)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	SaveManager.bind_session(self)
	GameState.playing = true
	MissionManager.resume()


func _exit_tree() -> void:
	SaveManager.unbind_session(self)
	GameState.playing = false


## The player's part of a save: where they stand (beside the car if they are driving), facing,
## health, and the district.
func collect_player_save() -> Dictionary:
	var at: Vector3 = player.global_position
	if player.is_in_vehicle() and player.vehicle != null:
		at = (player.get_node("VehicleInteractor") as VehicleInteractor).find_exit_position(player.vehicle)
	return {
		"district": str(regions.get_current_id()),
		"position": [at.x, at.y, at.z],
		"yaw": player.camera_rig.get_yaw(),
		"health": player.stats.health,
	}


## Arrested (GDD §7): the BUSTED card, a fine, out at the nearest police station's door with the
## police gone; a mission that was running fails.
func _on_busted() -> void:
	var tuning: WantedTuning = WantedSystem.tuning
	var fine: int = mini(EconomyManager.cash, maxi(tuning.fine_min, int(EconomyManager.cash * tuning.fine_share)))
	var mission_running: bool = MissionManager.is_active() and not MissionManager.is_failed()
	await busted_screen.play(fine)
	police.clear_all()
	place_player(world.data.nearest_police_station(player.global_position))
	EconomyManager.try_spend(fine, &"fine")
	if mission_running and MissionManager.is_active():
		MissionManager.fail("You were busted.")


## Knocked out (M7): a moment on the ground, the HOSPITALISED card and a bill, then awake at the
## nearest hospital or clinic at full health with the police gone and the record clean; a mission
## that was running fails.
func _on_player_died() -> void:
	var tuning: PlayerTuning = player.tuning
	var fee: int = mini(EconomyManager.cash, maxi(tuning.hospital_fee_min, int(EconomyManager.cash * tuning.hospital_fee_share)))
	var mission_running: bool = MissionManager.is_active() and not MissionManager.is_failed()
	await get_tree().create_timer(DOWN_SECONDS).timeout
	await hospital_screen.play(fee)
	police.clear_all()
	WantedSystem.clear()
	place_player(world.data.nearest_hospital(player.global_position))
	player.revive()
	EconomyManager.try_spend(fee, &"hospital")
	if mission_running and MissionManager.is_active():
		MissionManager.fail("You were hospitalised.")


## Puts the player (on foot) at `xform`'s position, facing its -Z, camera behind them.
func place_player(xform: Transform3D) -> void:
	if player.is_in_vehicle():
		player.exit_vehicle(xform.origin)
	world.streamer.load_around_now(xform.origin)
	player.global_position = xform.origin + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var facing: Vector3 = -xform.basis.z
	var yaw: float = atan2(-facing.x, -facing.z)
	player.model.rotation.y = yaw
	player.camera_rig.set_view_degrees(rad_to_deg(yaw), player.camera_rig.settings.default_pitch_degrees)
	player.camera_rig.snap_to_target()


func _saved_transform(data: Dictionary) -> Transform3D:
	var spawn: Transform3D = world.get_spawn_transform()
	var p: Array = data.get("position", [])
	if p.size() != 3:
		return spawn
	var yaw: float = float(data.get("yaw", 0.0))
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2])))


func _on_vehicle_entered(vehicle: VehicleController) -> void:
	var rig: ThirdPersonCamera = player.camera_rig
	vehicle_camera.activate(vehicle, rig.get_yaw(), rig.get_pitch())
	rig.set_active(false)
	camera_transition.blend_to(vehicle_camera.camera, ENTER_BLEND_SECONDS)
	hud.bind_vehicle(vehicle)


func _on_vehicle_exited(_vehicle: VehicleController) -> void:
	var rig: ThirdPersonCamera = player.camera_rig
	rig.set_view_degrees(rad_to_deg(vehicle_camera.get_view_yaw()), rig.settings.default_pitch_degrees)
	rig.set_active(true)
	camera_transition.blend_to(rig.camera, EXIT_BLEND_SECONDS)
	vehicle_camera.deactivate()
	hud.unbind_vehicle()


## The district's name fades in at the top of the screen (on arrival, and when you cross into another).
func _show_region(index: int) -> void:
	var title: String = world.data.get_region_name(index)
	hud.show_area_title((title if title != "" else world.get_display_name()).to_upper(), "VELANAGAR")


## The HUD steps aside while a cutscene plays (the letterbox carries its subtitles).
func _on_cutscene_playing(playing: bool) -> void:
	hud.visible = not playing
