class_name PlayerFigure
extends MeshInstance3D
## The player's body (GDD §4): a low-poly character baked by CharacterBaker and animated by
## shaders/character.gdshader, like the pedestrians: legs and arms swing with walking speed
## (wider when running), a stride pose in the air, fists up and the right arm thrown out to
## punch. Wears the outfit in GameState.outfit, looked up in the clothes shop's list
## (`wardrobe`); the first outfit there is what the player arrived in.
## A child of the player's Model node (which faces -Z); the character model faces +Z, so this
## node is turned round.

@export var look: PackedScene
@export var skin_color: Color = Color("8d5a3b")
@export var hair_color: Color = Color("1b1612")
@export var wardrobe: ShopData
## Step length (m) walking and sprinting, and leg swing (radians) at those paces.
@export var step_walk: float = 0.7
@export var step_sprint: float = 1.5
@export var swing_walk: float = 0.45
@export var swing_sprint: float = 0.8
## Fists stay up this long after a punch (seconds).
@export var guard_hold: float = 1.5

var _player: PlayerController
var _phase: float = 0.0
var _swing: float = 0.0
var _guard: float = 0.0
var _guard_left: float = 0.0
var _outfit: Outfit


func _ready() -> void:
	_player = owner as PlayerController
	mesh = CharacterBaker.get_mesh(look)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	set_instance_shader_parameter(&"skin_color", skin_color)
	set_instance_shader_parameter(&"hair_color", hair_color)
	GameState.outfit_changed.connect(wear)
	wear(GameState.outfit)


## Puts on outfit `outfit_id` (unknown or &"": the clothes the player arrived in).
func wear(outfit_id: StringName) -> void:
	var outfit: Outfit = null
	if wardrobe != null:
		outfit = wardrobe.get_item(outfit_id) as Outfit
		if outfit == null and not wardrobe.items.is_empty():
			outfit = wardrobe.items[0] as Outfit
	_outfit = outfit
	if outfit != null:
		set_instance_shader_parameter(&"top_color", outfit.top_color)
		set_instance_shader_parameter(&"bottom_color", outfit.bottom_color)


func get_outfit() -> Outfit:
	return _outfit


func _process(delta: float) -> void:
	if _player == null or not is_visible_in_tree():
		return
	var speed: float = _player.get_horizontal_speed()
	var airborne: bool = _player.state in [PlayerController.State.JUMP, PlayerController.State.FALL]
	var target: float
	if airborne:
		target = swing_walk * 0.8
		_phase = lerpf(_phase, snappedf(_phase - PI * 0.5, PI) + PI * 0.5, 1.0 - exp(-10.0 * delta))
	else:
		var pace: float = clampf(speed / 1.4, 0.0, 1.0)
		target = pace * lerpf(swing_walk, swing_sprint, clampf((speed - 2.5) / 5.0, 0.0, 1.0))
		_phase += speed / lerpf(step_walk, step_sprint, clampf((speed - 2.0) / 6.0, 0.0, 1.0)) * PI * delta
	_swing = lerpf(_swing, target, 1.0 - exp(-10.0 * delta))
	set_instance_shader_parameter(&"walk_phase", _phase)
	set_instance_shader_parameter(&"swing", _swing)
	# Fists: up while punching and for a moment after, the right arm thrown out with the blow.
	var progress: float = _player.get_punch_progress()
	_guard_left = guard_hold if progress >= 0.0 else maxf(0.0, _guard_left - delta)
	_guard = move_toward(_guard, 1.0 if _guard_left > 0.0 and not _player.is_down() else 0.0, delta * 5.0)
	set_instance_shader_parameter(&"guard", _guard)
	set_instance_shader_parameter(&"punch", FightPose.arm_out(progress, _player.tuning.punch_hit_at / _player.tuning.punch_time))
