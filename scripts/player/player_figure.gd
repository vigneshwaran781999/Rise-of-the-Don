class_name PlayerFigure
extends HumanFigure
## The player's body (GDD §4; rigged and animated since M8): the rigged man (HumanFigure) in the
## outfit in GameState.outfit, looked up in the clothes shop's list (`wardrobe`; the first outfit
## there is what the player arrived in). It follows the PlayerController: walking, running and
## sprinting by speed, in the air (jump, fall, land), punching with the fists up for a moment
## after, staggering from a blow, knocked down and getting up again.
## A child of the player's Model node (which faces -Z); the model faces +Z, so this node is
## turned round.

@export var skin_color: Color = Color("8d5a3b")
@export var hair_color: Color = Color("1b1612")
@export var wardrobe: ShopData
## Fists stay up this long after a punch (seconds).
@export var guard_hold: float = 1.5

var _player: PlayerController
var _outfit: Outfit
var _guard_left: float = 0.0


func _ready() -> void:
	_player = owner as PlayerController
	set_colours({&"skin_color": skin_color, &"hair_color": hair_color})
	super._ready()
	GameState.outfit_changed.connect(wear)
	wear(GameState.outfit)
	if _player != null:
		_player.state_changed.connect(_on_state_changed)
		_player.jumped.connect(func() -> void: play(&"jump"))
		_player.landed.connect(func(_impact: float) -> void: play(&"land"))
		_player.hurt.connect(_on_hurt)


## Puts on outfit `outfit_id` (unknown or &"": the clothes the player arrived in).
func wear(outfit_id: StringName) -> void:
	var outfit: Outfit = null
	if wardrobe != null:
		outfit = wardrobe.get_item(outfit_id) as Outfit
		if outfit == null and not wardrobe.items.is_empty():
			outfit = wardrobe.items[0] as Outfit
	_outfit = outfit
	if outfit != null:
		set_colours({&"top_color": outfit.top_color, &"bottom_color": outfit.bottom_color})


func get_outfit() -> Outfit:
	return _outfit


func _process(delta: float) -> void:
	if _player == null or not is_visible_in_tree():
		return
	var airborne: bool = _player.state in [PlayerController.State.JUMP, PlayerController.State.FALL]
	if _player.state == PlayerController.State.DOWN:
		set_state(&"down")
	elif airborne:
		set_state(&"fall")
	else:
		set_state(&"move")
	set_speed(_player.get_horizontal_speed() if not airborne else 0.0)
	_guard_left = guard_hold if _player.state == PlayerController.State.PUNCH else maxf(0.0, _guard_left - delta)
	set_guard(move_toward(get_guard(), 1.0 if _guard_left > 0.0 and not _player.is_down() else 0.0, delta * 5.0))


func _on_state_changed(previous: PlayerController.State, current: PlayerController.State) -> void:
	match current:
		PlayerController.State.PUNCH:
			play(&"punch")
		PlayerController.State.DOWN:
			play(&"knocked")
		PlayerController.State.IDLE:
			if previous == PlayerController.State.DOWN:
				play(&"getup")


func _on_hurt(_damage: float) -> void:
	if not _player.is_down():
		play(&"hit")
