extends Node3D
## Root of the game scene: puts the player on the block's spawn point, hooks the HUD up to
## the player's stats and captures the mouse for camera look.

@onready var world: CityBlockBuilder = $World
@onready var player: PlayerController = $Player
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	get_tree().paused = false
	player.global_transform = world.get_spawn_transform()
	player.reset_physics_interpolation()
	player.camera_rig.snap_to_target()
	hud.bind_player(player.stats)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
