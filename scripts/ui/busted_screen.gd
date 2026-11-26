class_name BustedScreen
extends CanvasLayer
## The arrest card (GDD §7): "BUSTED" in police red and blue with the fine, while the game holds
## still for a moment. The game session then puts the player at the police station. HospitalScreen
## (M7) is the same card with other words and colours.

const HOLD_SECONDS: float = 3.0

## The big word, the line under it (formatted with the amount) and the colours the word's glow
## flashes between.
var title_text: String = "BUSTED"
var amount_format: String = "Fine: %s"
var flash_colours: Array[Color] = [Color("ff2a3a"), Color("2a5bff")]

var _root: Control
var _title: Label
var _fine: Label


func _ready() -> void:
	layer = 23
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_showing() -> bool:
	return _root.visible


## The amount line as shown.
func get_amount_text() -> String:
	return _fine.text


## Shows the card for a few seconds with the game paused; returns when it is done.
func play(amount: int) -> void:
	_fine.text = amount_format % EconomyManager.format(amount)
	_root.modulate.a = 0.0
	_root.show()
	get_tree().paused = true
	AudioManager.play_ui(&"mission_failed")
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(HOLD_SECONDS, true, false, true).timeout
	_root.hide()
	get_tree().paused = false


func _process(_delta: float) -> void:
	if _root.visible:
		var index: int = int(Time.get_ticks_msec() / 300) % flash_colours.size()
		_title.label_settings.outline_color = flash_colours[index]
		_title.label_settings.shadow_color = Color(flash_colours[index], 0.6)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.04, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = Label.new()
	_title.name = title_text.capitalize() + "Title"
	_title.text = title_text
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var settings: LabelSettings = UIStyle.glow_label(110, UIStyle.TEXT, flash_colours[0], 22)
	settings.outline_size = 10
	settings.outline_color = flash_colours[0]
	_title.label_settings = settings
	box.add_child(_title)
	_fine = Label.new()
	_fine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fine.label_settings = UIStyle.glow_label(30, UIStyle.TEXT, UIStyle.CYAN, 6)
	box.add_child(_fine)
