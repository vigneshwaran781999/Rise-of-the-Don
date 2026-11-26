class_name ScreenFade
extends CanvasLayer
## A black screen over the game (below the loading card) that fades in and out: jumps in place
## or time happen behind it (mission replays, the story clock skipping hours).

var _black: ColorRect


func _ready() -> void:
	layer = 40
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color(0.0, 0.0, 0.0, 0.0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func get_alpha() -> float:
	return _black.color.a


## Black (1) or clear (0) at once.
func set_alpha(alpha: float) -> void:
	_black.color.a = alpha


## Fades to `alpha` over `seconds`; await the tween's `finished` to wait for it.
func fade_to(alpha: float, seconds: float) -> Tween:
	var tween := create_tween()
	tween.tween_property(_black, "color:a", alpha, seconds)
	return tween
