class_name ChoiceCard
extends CanvasLayer
## A story decision (M7 CHOICE objectives): the game holds still and the question comes up with
## one button per answer. Keyboard, mouse and gamepad; there is no backing out of it (Esc doesn't
## open the pause menu underneath). MissionDirector asks (choice_requested); the answer goes back
## through `chosen`.

signal chosen(answer: int)

var _root: Control
var _question: Label
var _answers: VBoxContainer


func _ready() -> void:
	layer = 21
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func is_open() -> bool:
	return _root.visible


func get_question() -> String:
	return _question.text if _root.visible else ""


## The answer buttons on screen.
func get_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _answers.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## Puts the question up with its answers.
func ask(question: String, answers: PackedStringArray) -> void:
	for child: Node in _answers.get_children():
		child.queue_free()
	_question.text = question
	for i: int in answers.size():
		var button: Button = UIStyle.make_button(answers[i], "Answer%d" % i)
		button.pressed.connect(answer.bind(i))
		_answers.add_child(button)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	AudioManager.play_ui(&"objective")
	if _answers.get_child_count() > 0:
		(_answers.get_child(_answers.get_child_count() - answers.size()) as Button).grab_focus()


## Gives answer `index` (the buttons call this).
func answer(index: int) -> void:
	if not _root.visible:
		return
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_ui(&"ui_accept")
	chosen.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.05, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	_root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "ChoicePanel"
	panel.custom_minimum_size = Vector2(680.0, 0.0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = "YOUR CHOICE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.label_settings = UIStyle.glow_label(48, UIStyle.TEXT, UIStyle.MAGENTA, 14)
	box.add_child(heading)
	_question = Label.new()
	_question.name = "Question"
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.add_theme_font_size_override("font_size", 26)
	_question.add_theme_color_override("font_color", UIStyle.TEXT)
	box.add_child(_question)
	box.add_child(HSeparator.new())
	_answers = VBoxContainer.new()
	_answers.name = "Answers"
	_answers.add_theme_constant_override("separation", 12)
	box.add_child(_answers)
