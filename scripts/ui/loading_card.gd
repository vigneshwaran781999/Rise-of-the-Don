class_name LoadingCard
extends CanvasLayer
## The card while a game loads (M8): VELANAGAR, a progress bar and a tip, over the menu and on
## into the game until the city has streamed in and drawn its first frames, then it fades. The
## game scene loads on a background thread meanwhile. Start it with LoadingCard.change_to().

const TIPS: PackedStringArray = [
	"Traffic keeps left in Velanagar.",
	"Lose the police: get out of their sight and out of the red circle on the minimap.",
	"The East Road Garage resprays your car and clears up to three stars.",
	"Selvi's tiffin stall puts your health back. Coffee for a little, full meals for all of it.",
	"Your house is a save point, and it pays rent.",
	"Hit a fighter while they wind up their punch and you'll break it.",
	"Two punches on someone in the street, and the police take an interest.",
	"Press M for the map. Click it to set a waypoint and follow the GPS line.",
	"Sprinting uses stamina. Let it fill up again before you need it.",
	"Knocked out, you wake at the nearest hospital, a little poorer.",
]
## Frames the new scene runs (the city streaming in) before the card fades.
const SETTLE_FRAMES: int = 20
const FADE_SECONDS: float = 0.4

var _root: Control
var _bar: ProgressBar


## Shows the card and switches the game to the scene at `path` behind it.
static func change_to(tree: SceneTree, path: String) -> void:
	var card := LoadingCard.new()
	card.name = "LoadingCard"
	tree.root.add_child(card)
	card._load(path)


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func get_progress() -> float:
	return _bar.value / _bar.max_value


func _load(path: String) -> void:
	await get_tree().process_frame            # the card is on screen before the work starts
	await get_tree().process_frame
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		push_error("LoadingCard: could not start loading %s" % path)
		get_tree().change_scene_to_file(path)
	else:
		var progress: Array = []
		while ResourceLoader.load_threaded_get_status(path, progress) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_bar.value = float(progress[0]) * 0.8 if not progress.is_empty() else _bar.value
			await get_tree().process_frame
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene == null:
			push_error("LoadingCard: could not load %s" % path)
			queue_free()
			return
		_bar.value = 0.8
		get_tree().change_scene_to_packed(scene)
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
		_bar.value = 0.8 + 0.2 * float(i + 1) / SETTLE_FRAMES
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SECONDS)
	await tween.finished
	queue_free()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = Color(0.03, 0.01, 0.05)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	_root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.name = "Title"
	title.text = "VELANAGAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = UIStyle.glow_label(72, UIStyle.TEXT, UIStyle.MAGENTA, 18)
	box.add_child(title)
	var centre := CenterContainer.new()
	box.add_child(centre)
	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.custom_minimum_size = Vector2(520.0, 10.0)
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override(&"fill", UIStyle.make_bar_fill(UIStyle.CYAN))
	centre.add_child(_bar)
	var tip := Label.new()
	tip.name = "Tip"
	tip.text = TIPS[randi() % TIPS.size()]
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(760.0, 0.0)
	tip.add_theme_font_size_override(&"font_size", 22)
	tip.add_theme_color_override(&"font_color", UIStyle.TEXT_DIM)
	var tip_centre := CenterContainer.new()
	box.add_child(tip_centre)
	tip_centre.add_child(tip)
