class_name SavePanel
extends MenuPanel
## Save slots (GDD §14): the autosave and three manual slots, each showing the mission, cash,
## time played and when it was saved. In SAVE mode (pause menu) a manual slot is written when
## picked (an occupied slot asks to be picked again to overwrite); in LOAD mode (main menu) any
## readable slot is loaded.

enum Mode { SAVE, LOAD }

const MONTHS: PackedStringArray = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var mode: Mode = Mode.SAVE

var _heading: Label
var _rows: Dictionary = {}    # slot -> Button
var _status: Label
var _confirm_slot: int = -1
var _back: Button


func _ready() -> void:
	name = "SavePanel"
	custom_minimum_size = Vector2(860.0, 0.0)
	_build()
	hide()


func open_as(panel_mode: Mode) -> void:
	mode = panel_mode
	open()


func get_row(slot: int) -> Button:
	return _rows.get(slot)


func get_status_text() -> String:
	return _status.text


func _on_opening() -> void:
	_confirm_slot = -1
	_status.text = ""
	_heading.text = "SAVE GAME" if mode == Mode.SAVE else "LOAD GAME"
	if mode == Mode.SAVE and MissionManager.is_replay():
		_status.text = "You can't save during a mission replay. End it from Pause → Missions, or play it through."
	_refresh()


func _focus_target() -> Control:
	for slot: int in SaveManager.ALL_SLOTS:
		var row: Button = _rows[slot]
		if not row.disabled:
			return row
	return _back


func _refresh() -> void:
	for slot: int in SaveManager.ALL_SLOTS:
		var row: Button = _rows[slot]
		var data: Dictionary = SaveManager.read_slot(slot)
		row.text = "%s\n%s" % [_slot_name(slot), describe(data)]
		if mode == Mode.SAVE:
			row.disabled = slot == SaveManager.AUTOSAVE_SLOT or not SaveManager.can_save()
		else:
			row.disabled = data.is_empty() or data.has("error")
		row.focus_mode = Control.FOCUS_NONE if row.disabled else Control.FOCUS_ALL


func _on_row_pressed(slot: int) -> void:
	if mode == Mode.LOAD:
		var err: Error = SaveManager.load_game(slot)
		if err != OK:
			_status.text = "That save can't be loaded."
		return
	if not SaveManager.read_slot(slot).is_empty() and _confirm_slot != slot:
		_confirm_slot = slot
		_status.text = "%s already holds a game. Select it again to overwrite it." % _slot_name(slot)
		return
	_confirm_slot = -1
	var err: Error = SaveManager.save_game(slot)
	_status.text = ("Saved to %s." % _slot_name(slot).to_lower()) if err == OK else "Saving failed (error %d)." % err
	if err == OK:
		AudioManager.play_ui(&"ui_accept")
	_refresh()
	(_rows[slot] as Button).grab_focus()


## One line about a slot's contents: mission, cash, time played, when saved.
static func describe(data: Dictionary) -> String:
	if data.is_empty():
		return "Empty"
	if data.has("error"):
		return "Damaged save" if data["error"] == "damaged" else "Saved by a different version of the game"
	var summary: Dictionary = data.get("summary", {})
	var mission: String = str(summary.get("mission", ""))
	var passed: int = int(summary.get("missions_passed", 0))
	var progress: String = mission.to_upper() if mission != "" else "Free roam, %d mission%s passed" % [passed, "" if passed == 1 else "s"]
	return "%s   ·   %s   ·   %s played   ·   %s" % [progress, EconomyManager.format(int(summary.get("cash", 0))),
		GameState.format_time(float(summary.get("play_time", 0.0))), _when(int(float(data.get("saved_at", 0.0))))]


static func _slot_name(slot: int) -> String:
	return "Autosave" if slot == SaveManager.AUTOSAVE_SLOT else "Slot %d" % slot


## Local date and time of a save, e.g. "25 Nov 2026, 14:05".
static func _when(unix_time: int) -> String:
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var t: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%d %s %d, %02d:%02d" % [t["day"], MONTHS[int(t["month"]) - 1], t["year"], t["hour"], t["minute"]]


func _build() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	_heading = UIStyle.make_heading("SAVE GAME")
	box.add_child(_heading)
	box.add_child(HSeparator.new())
	for slot: int in SaveManager.ALL_SLOTS:
		var row: Button = UIStyle.make_button(_slot_name(slot), "SlotButton%d" % slot)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(800.0, 84.0)
		row.add_theme_font_size_override("font_size", 21)
		row.pressed.connect(_on_row_pressed.bind(slot))
		box.add_child(row)
		_rows[slot] = row
	_status = Label.new()
	_status.name = "SaveStatus"
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", UIStyle.CYAN)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_back = _make_back_button()
	box.add_child(_back)
