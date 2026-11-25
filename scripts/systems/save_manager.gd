extends Node
## Saving and loading (GDD §14): one JSON file per slot in user://saves/ (slot_0.json is the
## autosave, slots 1-3 are manual), with a version field so later builds can tell old saves
## apart. A save holds the player's position and health, cash, mission progress (the running
## mission restarts at its last checkpoint), play time and stats.
## Autosaves after every mission passed. Autoload: SaveManager.

signal saved(slot: int)

const SAVE_VERSION: int = 1
const AUTOSAVE_SLOT: int = 0
const MANUAL_SLOTS: Array[int] = [1, 2, 3]
const ALL_SLOTS: Array[int] = [0, 1, 2, 3]
const GAME_SCENE: String = "res://scenes/main/game.tscn"

## Where the slot files live (tests point this at a scratch folder).
var save_dir: String = "user://saves"

var _session: GameSession
var _pending: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	MissionManager.mission_passed.connect(func(_mission: MissionData) -> void: _autosave.call_deferred())


## The running game scene registers itself; saving is only possible while one is bound.
func bind_session(session: GameSession) -> void:
	_session = session


func unbind_session(session: GameSession) -> void:
	if _session == session:
		_session = null


func can_save() -> bool:
	return _session != null and is_instance_valid(_session) and _session.is_inside_tree()


func slot_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.json" % slot)


func save_game(slot: int) -> Error:
	if not can_save() or not ALL_SLOTS.has(slot):
		return ERR_UNAVAILABLE
	var err: Error = DirAccess.make_dir_recursive_absolute(save_dir)
	if err != OK and not DirAccess.dir_exists_absolute(save_dir):
		return err
	# Write a temporary file first, so a failed write never destroys the old save.
	var temp_path: String = slot_path(slot) + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(_collect(slot), "\t"))
	file.close()
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))
	err = DirAccess.rename_absolute(temp_path, slot_path(slot))
	if err != OK:
		return err
	saved.emit(slot)
	return OK


## The slot's file as saved, {} if the slot is empty, or {"error": "damaged" | "version"}.
func read_slot(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {}
	var json := JSON.new()   # an instance parse reports a damaged file quietly, through its result
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(slot_path(slot))) == OK else null
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("state") or not ((parsed as Dictionary)["state"] is Dictionary):
		return {"error": "damaged"}
	var data: Dictionary = parsed
	if int(data.get("version", -1)) != SAVE_VERSION:
		return {"error": "version"}
	return data


func has_any_save() -> bool:
	return latest_slot() >= 0


## The slot saved most recently, or -1 if there is no readable save.
func latest_slot() -> int:
	var best: int = -1
	var best_time: float = -1.0
	for slot: int in ALL_SLOTS:
		var data: Dictionary = read_slot(slot)
		if data.is_empty() or data.has("error"):
			continue
		var when: float = float(data.get("saved_at", 0.0))
		if when > best_time:
			best_time = when
			best = slot
	return best


## Loads the slot and starts the game scene from it. Fails without changing anything if the
## slot is empty or can't be read.
func load_game(slot: int) -> Error:
	var data: Dictionary = read_slot(slot)
	if data.is_empty():
		return ERR_FILE_NOT_FOUND
	if data.has("error"):
		return ERR_FILE_UNRECOGNIZED if data["error"] == "version" else ERR_FILE_CORRUPT
	_pending = data["state"]
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
	return OK


## The game scene takes the state it should start from ({} = New Game).
func take_pending_load() -> Dictionary:
	var state: Dictionary = _pending
	_pending = {}
	return state


func delete_slot(slot: int) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))


func _autosave() -> void:
	if can_save():
		save_game(AUTOSAVE_SLOT)


func _collect(slot: int) -> Dictionary:
	var player: Dictionary = _session.collect_player_save()
	var active: MissionData = MissionManager.get_active()
	return {
		"version": SAVE_VERSION,
		"slot": slot,
		"saved_at": Time.get_unix_time_from_system(),
		"summary": {
			"mission": active.title if active != null else "",
			"missions_passed": MissionManager.get_completed().size(),
			"cash": EconomyManager.cash,
			"play_time": GameState.play_time,
			"district": player.get("district", ""),
		},
		"state": {
			"game": GameState.to_save(),
			"economy": EconomyManager.to_save(),
			"missions": MissionManager.to_save(),
			"player": player,
		},
	}
