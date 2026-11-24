class_name CreditsPanel
extends MenuPanel
## Credits, including the Godot Engine licence notice that must ship with the game.

const LINES: Array = [
	["RISE OF THE DON", 30, "title"],
	["An original game. Velanagar, its people and its story are fictional.", 22, "text"],
	["Code, placeholder 3D art and placeholder sound: made for this project (GDScript and Blender scripts, sounds synthesised in code).", 22, "text"],
	["Font: your system's UI font (Bahnschrift or Segoe UI).", 22, "text"],
	["Made with the Godot Engine", 26, "title"],
]

const SCROLL_STEP: int = 60

var _back: Button
var _scroll: ScrollContainer


func _ready() -> void:
	name = "CreditsPanel"
	custom_minimum_size = Vector2(860.0, 0.0)
	_build()
	hide()


## Up / down (keys, D-pad) scroll the text; Back keeps focus so Enter / A still closes.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var step: int = 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_scroll.scroll_vertical += step * SCROLL_STEP
		get_viewport().set_input_as_handled()


func _focus_target() -> Control:
	return _back


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	box.add_child(UIStyle.make_heading("CREDITS"))
	box.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.name = "CreditsScroll"
	_scroll.custom_minimum_size = Vector2(0.0, 520.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	_scroll.add_child(body)
	for line: Array in LINES:
		var color: Color = UIStyle.CYAN if str(line[2]) == "title" else UIStyle.TEXT
		body.add_child(_wrapped(str(line[0]), int(line[1]), color))
	body.add_child(_wrapped(Engine.get_license_text(), 16, UIStyle.TEXT_DIM))

	box.add_child(HSeparator.new())
	_back = _make_back_button()
	box.add_child(_back)


func _wrapped(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
