class_name UIStyle
extends RefCounted
## Neon-on-dark look shared by every menu and the HUD (GDD §10): dark translucent panels,
## magenta and cyan accents, a clean sans-serif font. Builds one Theme in code.

const MAGENTA := Color("ff2bd6")
const CYAN := Color("22e6ff")
const HEALTH := Color("ff3d6e")
const TEXT := Color("f4eefc")
const TEXT_DIM := Color("a99fbb")
const PANEL_BG := Color(0.045, 0.025, 0.07, 0.9)
const BUTTON_BG := Color(0.09, 0.05, 0.13, 0.8)
## Optional bundled open-licence font. If it isn't there, the OS font below is used.
const FONT_FILE: String = "res://assets/fonts/Rajdhani-SemiBold.ttf"
const SYSTEM_FONTS: PackedStringArray = ["Bahnschrift", "Segoe UI", "Arial"]

static var _theme: Theme
static var _font: Font


static func get_font() -> Font:
	if _font == null:
		if ResourceLoader.exists(FONT_FILE):
			_font = load(FONT_FILE)
		else:
			var system_font := SystemFont.new()
			system_font.font_names = SYSTEM_FONTS
			system_font.font_weight = 600
			_font = system_font
	return _font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


## A menu button with the standard size and UI sounds.
static func make_button(text: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(440.0, 64.0)
	var hover_sound := func() -> void:
		if not button.disabled:
			AudioManager.play_ui(&"ui_move")
	button.mouse_entered.connect(hover_sound)
	button.focus_entered.connect(hover_sound)
	button.pressed.connect(func() -> void: AudioManager.play_ui(&"ui_accept"))
	return button


static func make_heading(text: String, size: int = 44) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = glow_label(size, TEXT, MAGENTA)
	return label


static func glow_label(size: int, color: Color, glow: Color, glow_size: int = 14) -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = get_font()
	settings.font_size = size
	settings.font_color = color
	settings.shadow_color = Color(glow, 0.75)
	settings.shadow_size = glow_size
	settings.shadow_offset = Vector2.ZERO
	return settings


static func make_bar_fill(color: Color) -> StyleBoxFlat:
	var fill := _box(color, Color.TRANSPARENT, 0, 0)
	fill.set_corner_radius_all(2)
	fill.shadow_color = Color(color, 0.45)
	fill.shadow_size = 6
	_margins(fill, 0, 0)
	return fill


static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = get_font()
	t.default_font_size = 26

	# Buttons: dark slab with a magenta edge; hover turns the edge cyan and adds a glow.
	t.set_stylebox("normal", "Button", _box(BUTTON_BG, Color(MAGENTA, 0.6), 4, 0))
	var hover := _box(Color(0.16, 0.07, 0.22, 0.92), CYAN, 8, 0)
	hover.shadow_color = Color(CYAN, 0.28)
	hover.shadow_size = 12
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", _box(Color(MAGENTA, 0.55), MAGENTA, 8, 0))
	t.set_stylebox("disabled", "Button", _box(Color(0.05, 0.035, 0.07, 0.85), Color(TEXT_DIM, 0.25), 4, 0))
	var focus := _box(Color.TRANSPARENT, CYAN, 8, 2)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_font_size("font_size", "Button", 28)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.45))

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 24)

	# Panels
	var panel := _box(PANEL_BG, Color(MAGENTA, 0.35), 1, 1)
	panel.border_width_top = 3
	panel.border_color = Color(MAGENTA, 0.55)
	panel.set_corner_radius_all(4)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 28
	_margins(panel, 40, 32)
	t.set_stylebox("panel", "PanelContainer", panel)

	# Sliders: thin track, magenta fill, round grabber.
	var track := _box(Color(1, 1, 1, 0.12), Color.TRANSPARENT, 0, 0)
	track.set_corner_radius_all(3)
	_margins(track, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = MAGENTA
	t.set_stylebox("grabber_area", "HSlider", filled)
	var filled_hi := track.duplicate() as StyleBoxFlat
	filled_hi.bg_color = CYAN
	t.set_stylebox("grabber_area_highlight", "HSlider", filled_hi)
	t.set_icon("grabber", "HSlider", _dot(TEXT))
	t.set_icon("grabber_highlight", "HSlider", _dot(CYAN))
	t.set_icon("grabber_disabled", "HSlider", _dot(TEXT_DIM))
	var slider_focus := _box(Color.TRANSPARENT, CYAN, 1, 1)
	slider_focus.draw_center = false
	slider_focus.set_corner_radius_all(4)
	t.set_stylebox("focus", "HSlider", slider_focus)

	# Check buttons (invert Y)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_focus_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", Color.WHITE)
	t.set_stylebox("focus", "CheckButton", slider_focus)

	# Progress bars (HUD)
	var bar_bg := _box(Color(1, 1, 1, 0.1), Color.TRANSPARENT, 0, 0)
	bar_bg.set_corner_radius_all(2)
	_margins(bar_bg, 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", make_bar_fill(MAGENTA))

	# Separators and scrollbars
	var line := StyleBoxLine.new()
	line.color = Color(MAGENTA, 0.35)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	var scroll_grab := _box(Color(MAGENTA, 0.6), Color.TRANSPARENT, 0, 0)
	scroll_grab.set_corner_radius_all(3)
	_margins(scroll_grab, 3, 3)
	t.set_stylebox("grabber", "VScrollBar", scroll_grab)
	var scroll_grab_hi := scroll_grab.duplicate() as StyleBoxFlat
	scroll_grab_hi.bg_color = CYAN
	t.set_stylebox("grabber_highlight", "VScrollBar", scroll_grab_hi)
	t.set_stylebox("grabber_pressed", "VScrollBar", scroll_grab_hi)
	var scroll_bg := _box(Color(1, 1, 1, 0.05), Color.TRANSPARENT, 0, 0)
	_margins(scroll_bg, 3, 3)
	t.set_stylebox("scroll", "VScrollBar", scroll_bg)
	return t


static func _box(bg: Color, border: Color, border_left: int, border_rest: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_left
	sb.border_width_top = border_rest
	sb.border_width_right = border_rest
	sb.border_width_bottom = border_rest
	sb.set_corner_radius_all(3)
	sb.anti_aliasing = true
	_margins(sb, 28, 12)
	return sb


static func _margins(sb: StyleBox, horizontal: float, vertical: float) -> void:
	sb.content_margin_left = horizontal
	sb.content_margin_right = horizontal
	sb.content_margin_top = vertical
	sb.content_margin_bottom = vertical


static func _dot(color: Color) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.72, 1.0])
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0), Color(color, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 24
	tex.height = 24
	return tex
