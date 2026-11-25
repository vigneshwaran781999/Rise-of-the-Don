extends Node
## Mission progress (GDD §8): which missions are passed, which are on offer, and the running
## mission's current objective and last checkpoint. It knows nothing about the world: the game
## scene's MissionDirector makes objectives happen and reports back through complete_objective()
## and fail(). Rewards, stats and the autosave hang off the signals. Autoload: MissionManager.

signal mission_started(mission: MissionData, checkpoint: int)
signal objective_started(mission: MissionData, index: int)
signal mission_passed(mission: MissionData)
signal mission_failed(mission: MissionData, reason: String)
## After a mission is passed, or quit (usually after failing it).
signal mission_ended(mission: MissionData)
## The set of missions on offer changed.
signal availability_changed

const STORY_PATH: String = "res://resources/missions/story.tres"

var story: StoryData

var _completed: Array[StringName] = []
var _active: MissionData
var _index: int = -1
var _checkpoint: int = 0
var _failed: bool = false
var _resume_id: StringName = &""
var _resume_checkpoint: int = 0


func _ready() -> void:
	story = load(STORY_PATH) as StoryData


## Forgets all progress (New Game).
func start_new_game() -> void:
	_completed.clear()
	_clear_active()
	_resume_id = &""
	availability_changed.emit()


func get_mission(id: StringName) -> MissionData:
	for mission: MissionData in story.missions:
		if mission.id == id:
			return mission
	return null


func is_completed(id: StringName) -> bool:
	return _completed.has(id)


func get_completed() -> Array[StringName]:
	return _completed.duplicate()


## Missions the player can start now: not running, not passed (unless repeatable), prerequisites
## passed.
func get_available() -> Array[MissionData]:
	var result: Array[MissionData] = []
	for mission: MissionData in story.missions:
		if mission == _active or (_completed.has(mission.id) and not mission.repeatable):
			continue
		var unlocked: bool = true
		for needed: StringName in mission.prerequisites:
			unlocked = unlocked and _completed.has(needed)
		if unlocked:
			result.append(mission)
	return result


func is_active() -> bool:
	return _active != null


func get_active() -> MissionData:
	return _active


func is_failed() -> bool:
	return _failed


func get_objective_index() -> int:
	return _index


func get_objective() -> MissionObjective:
	return _active.objectives[_index] if _active != null and _index >= 0 and _index < _active.objectives.size() else null


func get_checkpoint() -> int:
	return _checkpoint


## Starts mission `id` (at checkpoint objective `checkpoint`). False if another mission runs or
## this one isn't on offer.
func start(id: StringName, checkpoint: int = 0) -> bool:
	var mission: MissionData = get_mission(id)
	if _active != null or mission == null or not get_available().has(mission) or mission.objectives.is_empty():
		return false
	_active = mission
	_failed = false
	_checkpoint = mission.checkpoint_for(checkpoint)
	_begin_at_checkpoint()
	availability_changed.emit()
	return true


## Starts every offered mission that starts by itself (the opening mission), one at most.
func start_auto_missions() -> void:
	if _active != null:
		return
	for mission: MissionData in get_available():
		if mission.auto_start:
			start(mission.id)
			return


## The director reports the current objective done: on to the next one, or the mission is passed.
func complete_objective() -> void:
	if _active == null or _failed:
		return
	var next: int = _index + 1
	if next >= _active.objectives.size():
		_pass()
		return
	_index = next
	if _active.objectives[next].checkpoint:
		_checkpoint = next
	objective_started.emit(_active, _index)


func fail(reason: String) -> void:
	if _active == null or _failed:
		return
	_failed = true
	mission_failed.emit(_active, reason)


## After a failure: back to the last checkpoint.
func retry() -> void:
	if _active == null or not _failed:
		return
	_failed = false
	_begin_at_checkpoint()


## Gives up the running mission (it goes back on offer).
func quit_mission() -> void:
	if _active == null:
		return
	var mission: MissionData = _active
	_clear_active()
	mission_ended.emit(mission)
	availability_changed.emit()


# --------------------------------------------------------------------------- saving

func to_save() -> Dictionary:
	var completed: Array[String] = []
	for id: StringName in _completed:
		completed.append(String(id))
	return {
		"completed": completed,
		"active": String(_active.id) if _active != null else "",
		"checkpoint": _checkpoint if _active != null else 0,
	}


## Restores progress from a save. The running mission (if any) restarts at its checkpoint when
## the game scene calls resume().
func from_save(data: Dictionary) -> void:
	_completed.clear()
	for id: Variant in data.get("completed", []):
		if get_mission(StringName(str(id))) != null:
			_completed.append(StringName(str(id)))
	_clear_active()
	_resume_id = StringName(str(data.get("active", "")))
	_resume_checkpoint = int(data.get("checkpoint", 0))
	availability_changed.emit()


## Once the world is ready: restarts the saved running mission, or starts the opening mission.
func resume() -> void:
	var id: StringName = _resume_id
	_resume_id = &""
	if id != &"" and start(id, _resume_checkpoint):
		return
	start_auto_missions()


func _begin_at_checkpoint() -> void:
	_index = _checkpoint
	mission_started.emit(_active, _checkpoint)
	objective_started.emit(_active, _index)


func _pass() -> void:
	var mission: MissionData = _active
	_completed.append(mission.id)
	_clear_active()
	mission_passed.emit(mission)
	mission_ended.emit(mission)
	availability_changed.emit()


func _clear_active() -> void:
	_active = null
	_index = -1
	_checkpoint = 0
	_failed = false
