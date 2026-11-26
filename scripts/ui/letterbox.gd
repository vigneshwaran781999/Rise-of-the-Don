class_name Letterbox
extends CanvasLayer
## Black bars sliding in at the top and bottom of the screen for cinematic moments (dialogue
## scenes, cutscenes), with a subtitle in the bottom bar, a caption across the middle of the
## screen (a place or a time) and a small skip hint in the top bar.

## Bar height as a share of the screen height.
const BAR_SHARE: float = 0.11
const SLIDE_SECONDS: float = 0.35
const SPEAKER_COLOUR: String = "ff2bd6"

var _top: ColorRect
var _bottom: ColorRect
var _subtitle: RichTextLabel
var _caption: Label
var _hint: Label
var _share: float = 0.0
var _tween: Tween
var _caption_tween: Tween


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_top = _make_bar(true)
	_bottom = _make_bar(false)
	_subtitle = RichTextLabel.new()
	_subtitle.name = "Subtitle"
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.scroll_active = false
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.add_theme_font_override(&"normal_font", UIStyle.get_font())
	_subtitle.add_theme_font_size_override(&"normal_font_size", 26)
	_subtitle.add_theme_color_override(&"default_color", UIStyle.TEXT)
	_bottom.add_child(_subtitle)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_subtitle.offset_left = 80.0
	_subtitle.offset_right = -80.0
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.label_settings = UIStyle.glow_label(52, UIStyle.TEXT, UIStyle.MAGENTA, 16)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.get_theme()
	add_child(root)
	move_child(root, 0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = Label.new()
	_hint.name = "SkipHint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.label_settings = UIStyle.glow_label(18, UIStyle.TEXT_DIM, Color(0, 0, 0, 0), 0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint.offset_right = -30.0
	_set_share(0.0)


## Slides the bars in (or out); their text goes when they do.
func set_shown(shown: bool) -> void:
	if not shown:
		show_subtitle("", "")
		show_caption("")
		set_skip_hint("")
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_share, _share, 1.0 if shown else 0.0, SLIDE_SECONDS)


## How far the bars are in (0 out, 1 fully in).
func get_share() -> float:
	return _share


## A line in the bottom bar ("" text hides it); the speaker's name goes first in magenta.
func show_subtitle(speaker: String, text: String) -> void:
	if text == "":
		_subtitle.text = ""
		return
	var who: String = "[color=#%s]%s[/color]   " % [SPEAKER_COLOUR, speaker.to_upper()] if speaker != "" else ""
	_subtitle.text = who + text.replace("[", "[lb]")


func get_subtitle() -> String:
	return _subtitle.get_parsed_text()


## Big text across the middle of the screen, faded in ("" fades it out).
func show_caption(text: String) -> void:
	if _caption_tween != null and _caption_tween.is_valid():
		_caption_tween.kill()
	if text != "":
		_caption.text = text
	_caption_tween = create_tween()
	_caption_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_caption_tween.tween_property(_caption, "modulate:a", 1.0 if text != "" else 0.0, 0.5)


func get_caption() -> String:
	return _caption.text if _caption.modulate.a > 0.01 else ""


func set_skip_hint(text: String) -> void:
	_hint.text = text


func _set_share(share: float) -> void:
	_share = share
	_top.anchor_bottom = BAR_SHARE * share
	_bottom.anchor_top = 1.0 - BAR_SHARE * share
	_top.visible = share > 0.001
	_bottom.visible = share > 0.001


func _make_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.name = "TopBar" if top else "BottomBar"
	bar.color = Color.BLACK
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0 if top else 1.0
	bar.anchor_bottom = 0.0 if top else 1.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 0.0
	return bar
