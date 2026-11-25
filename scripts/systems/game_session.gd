class_name GameSession
extends Node3D
## Root of the game scene. Starts a new game (fresh cash, stats and missions, player at the
## district spawn, the opening mission begins) or carries on from a loaded save (state restored,
## player where they saved, a running mission resumes at its checkpoint). Streams the city in
## around the player, starts traffic and pedestrians, hooks the HUD up to the player and the
## missions, hands the view between the on-foot and vehicle cameras when the player gets in or
## out, captures the mouse for camera look, and gives SaveManager the player's state.

const ENTER_BLEND_SECONDS: float = 0.6
const EXIT_BLEND_SECONDS: float = 0.45
const DISTRICT_ID: String = "old_town"

@onready var world: District = $World
@onready var player: PlayerController = $Player
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var vehicle_camera: VehicleCamera = $VehicleCamera
@onready var camera_transition: CameraTransition = $CameraTransition
@onready var lane_debug: LaneGraphDebug = $LaneDebug
@onready var traffic: TrafficManager = $Traffic
@onready var pedestrians: PedestrianManager = $Pedestrians
@onready var missions: MissionDirector = $Missions


func _ready() -> void:
	get_tree().paused = false
	var saved: Dictionary = SaveManager.take_pending_load()
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
	hud.show_area_title(world.get_display_name().to_upper(), "VELANAGAR")
	lane_debug.setup(world.get_lane_graph(), player, world)
	traffic.setup(world.get_lane_graph(), player, world.streamer)
	pedestrians.setup(player, world.streamer)
	missions.setup(player, world)
	hud.bind_missions(missions, player)
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
		"district": DISTRICT_ID,
		"position": [at.x, at.y, at.z],
		"yaw": player.camera_rig.get_yaw(),
		"health": player.stats.health,
	}


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
