class_name CashDisplay
extends VBoxContainer
## The player's cash in the HUD's top-right corner (GDD §10). Changes count up or down to the new
## balance, with the amount flashed underneath ("+₹1,000").

const COUNT_SECONDS: float = 0.9
const FLASH_SECONDS: float = 2.6
const GAIN_COLOUR := Color("5dff9a")
const LOSS_COLOUR := Color("ff5d7a")

var _label: Label
var _delta_label: Label
var _shown: float = 0.0
var _tween: Tween
var _flash_tween: Tween


func _ready() -> void:
	name = "CashDisplay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 0)
	_label = Label.new()
	_label.name = "CashLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.label_settings = UIStyle.glow_label(40, UIStyle.TEXT, Color("2fd27a"), 10)
	add_child(_label)
	_delta_label = Label.new()
	_delta_label.name = "CashDelta"
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delta_label.add_theme_font_size_override("font_size", 24)
	_delta_label.modulate.a = 0.0
	add_child(_delta_label)
	EconomyManager.cash_changed.connect(_on_cash_changed)
	_set_shown(EconomyManager.cash)


## The amount on screen right now (it counts towards the balance after a change).
func get_shown_text() -> String:
	return _label.text


func _on_cash_changed(cash: int, delta: int, _reason: StringName) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if delta == 0:
		_set_shown(cash)
		return
	_tween = create_tween()
	_tween.tween_method(_set_shown, _shown, float(cash), COUNT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_delta_label.text = ("+" if delta > 0 else "") + EconomyManager.format(delta)
	_delta_label.add_theme_color_override("font_color", GAIN_COLOUR if delta > 0 else LOSS_COLOUR)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_delta_label.modulate.a = 1.0
	_flash_tween = create_tween()
	_flash_tween.tween_interval(FLASH_SECONDS)
	_flash_tween.tween_property(_delta_label, "modulate:a", 0.0, 0.8)
	if delta > 0:
		AudioManager.play_ui(&"cash")


func _set_shown(value: float) -> void:
	_shown = value
	_label.text = EconomyManager.format(roundi(value))


func _exit_tree() -> void:
	if EconomyManager.cash_changed.is_connected(_on_cash_changed):
		EconomyManager.cash_changed.disconnect(_on_cash_changed)
