extends Node3D
## Root of the game scene: puts the player on the district's spawn point and streams the city in
## around them, hooks the HUD up to the player, hands the view between the on-foot and vehicle
## cameras when the player gets in or out, and captures the mouse for camera look.

const ENTER_BLEND_SECONDS: float = 0.6
const EXIT_BLEND_SECONDS: float = 0.45

@onready var world: District = $World
@onready var player: PlayerController = $Player
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var vehicle_camera: VehicleCamera = $VehicleCamera
@onready var camera_transition: CameraTransition = $CameraTransition
@onready var lane_debug: LaneGraphDebug = $LaneDebug


func _ready() -> void:
	get_tree().paused = false
	var spawn: Transform3D = world.get_spawn_transform()
	player.global_position = spawn.origin
	player.reset_physics_interpolation()
	world.start_streaming(player)
	# Face the way the spawn point faces (its -Z), camera behind the player.
	var facing: Vector3 = -spawn.basis.z
	player.camera_rig.set_view_degrees(rad_to_deg(atan2(-facing.x, -facing.z)), player.camera_rig.settings.default_pitch_degrees)
	player.model.rotation.y = atan2(-facing.x, -facing.z)
	player.camera_rig.snap_to_target()
	hud.bind_player(player.stats)
	hud.bind_interactor(player.get_node("VehicleInteractor") as VehicleInteractor)
	hud.show_area_title(world.get_display_name().to_upper(), "VELANAGAR")
	lane_debug.setup(world.get_lane_graph(), player, world)
	player.vehicle_entered.connect(_on_vehicle_entered)
	player.vehicle_exited.connect(_on_vehicle_exited)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
