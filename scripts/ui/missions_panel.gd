class_name MissionsPanel
extends MenuPanel
## Pause → Missions (after 1.0): the story missions already passed, in story order; picking one
## replays it (MissionReplay: no reward, and the player comes back where they were). While a
## replay runs, End Replay stops it. When a replay can't start (another mission running, the
## police after you, in a vehicle), the rows are greyed and the reason is shown.

## The player picked a mission to replay.
signal replay_chosen(id: StringName)
## The player chose End Replay.
signal end_chosen

## Set by the pause menu.
var replay: MissionReplay

var _status: Label
var _end: Button
var _list: VBoxContainer
var _empty: Label
var _back: Button
var _rows: Dictionary = {}     # StringName -> Button


func _ready() -> void:
	name = "MissionsPanel"
	custom_minimum_size = Vector2(860.0, 0.0)
	_build()
	hide()


## The row replaying mission `id` (null if it isn't listed).
func get_row(id: StringName) -> Button:
	return _rows.get(id)


func get_status_text() -> String:
	return _status.text


func _on_opening() -> void:
	_refresh()


func _focus_target() -> Control:
	if _end.visible:
		return _end
	for row: Button in _rows.values():
		if not row.disabled:
			return row
	return _back


func _refresh() -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_rows.clear()
	var running: bool = replay != null and replay.is_running()
	var reason: String = replay.get_block_reason() if replay != null else "Not now."
	_end.visible = running
	if running:
		_end.text = "End Replay: %s" % replay.get_mission().title
	_status.text = "" if running else reason
	_status.visible = _status.text != ""
	var missions: Array[MissionData] = MissionManager.get_replayable()
	_empty.visible = missions.is_empty()
	var number: int = 0
	for mission: MissionData in missions:
		number += 1
		var row: Button = UIStyle.make_button("%d.  %s\n%s" % [number, mission.title, _first_sentence(mission.description)],
			"Replay_%s" % mission.id)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(780.0, 84.0)
		row.add_theme_font_size_override("font_size", 21)
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.disabled = reason != ""
		row.focus_mode = Control.FOCUS_NONE if row.disabled else Control.FOCUS_ALL
		row.pressed.connect(func() -> void: replay_chosen.emit(mission.id))
		_list.add_child(row)
		_rows[mission.id] = row


static func _first_sentence(text: String) -> String:
	var line: String = text.strip_edges().replace("\n", " ")
	var stop: int = line.find(". ")
	return line.substr(0, stop + 1) if stop > 0 else line


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	box.add_child(UIStyle.make_heading("MISSIONS"))
	var note := Label.new()
	note.text = "Replay a story mission you've passed. No reward, nothing is saved, and afterwards you're back where you were."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(note)
	box.add_child(HSeparator.new())
	_end = UIStyle.make_button("End Replay", "EndReplayButton")
	_end.pressed.connect(func() -> void: end_chosen.emit())
	box.add_child(_end)
	_status = Label.new()
	_status.name = "MissionsStatus"
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", UIStyle.CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.name = "Rows"
	scroll.custom_minimum_size = Vector2(0.0, 480.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.text = "Pass a story mission and you can replay it here."
	_empty.add_theme_font_size_override("font_size", 21)
	_empty.add_theme_color_override("font_color", UIStyle.TEXT_DIM)
	box.add_child(_empty)
	_back = _make_back_button()
	box.add_child(_back)
