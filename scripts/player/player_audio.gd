class_name PlayerAudio
extends Node
## Footsteps and landing thuds for the on-foot player (synthesised placeholders, SFX bus). Each
## step sounds like the ground it lands on (M7: the city's surface map: road, paving, sand, grass,
## the pier's boards, a splash when wading).
## Must be a direct child of the PlayerController.

## Below this horizontal speed (m/s) no footsteps play.
@export var min_step_speed: float = 0.6

## The city, for what the ground is made of (the game session sets it; without it every step
## sounds paved).
var city: CityData
## The surface of the last footstep (tests).
var last_surface: StringName = &""

var _player: PlayerController
var _stride_progress: float = 0.0


func _ready() -> void:
	_player = get_parent() as PlayerController
	_player.landed.connect(_on_landed)


func _physics_process(delta: float) -> void:
	if not _player.is_on_floor():
		return
	var speed: float = _player.get_horizontal_speed()
	if speed < min_step_speed:
		_stride_progress = 0.0
		return
	_stride_progress += speed * delta
	var stride: float = 0.55 + speed * 0.12
	if _stride_progress >= stride:
		_stride_progress -= stride
		var loudness: float = clampf(speed / 8.0, 0.0, 1.0)
		last_surface = city.surface_at(_player.global_position) if city != null else &"paved"
		AudioManager.play_sfx(StringName("footstep_" + last_surface), lerpf(-16.0, -5.0, loudness), randf_range(0.9, 1.12))


func _on_landed(impact_speed: float) -> void:
	if impact_speed < 1.5:
		return
	var loudness: float = clampf((impact_speed - 1.5) / 8.0, 0.0, 1.0)
	AudioManager.play_sfx(&"land", lerpf(-12.0, 0.0, loudness), randf_range(0.92, 1.05))
