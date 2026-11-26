extends Node
## Mission progress (GDD §8): which missions are passed, which are on offer, and the running
## mission's current objective and last checkpoint. It knows nothing about the world: the game
## scene's MissionDirector makes objectives happen and reports back through complete_objective()
## and fail(). Rewards, stats and the autosave hang off the signals. Autoload: MissionManager.
## A passed story mission can be replayed (after 1.0; Pause → Missions, MissionReplay): it runs
## like any mission, but passing it emits replay_passed instead of mission_passed (no reward,
## stats or autosave), it is never saved as the running mission, and saving waits until it ends.

signal mission_started(mission: MissionData, checkpoint: int)
signal objective_started(mission: MissionData, index: int)
signal mission_passed(mission: MissionData)
## A replay was played through to the end (it was passed before: nothing new is earned).
signal replay_passed(mission: MissionData)
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
var _replay: bool = false
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


## Story missions already passed, in story order: the ones that can be replayed (the side jobs
## are on offer again anyway).
func get_replayable() -> Array[MissionData]:
	var result: Array[MissionData] = []
	for mission: MissionData in story.missions:
		if _completed.has(mission.id) and not mission.repeatable and not mission.objectives.is_empty():
			result.append(mission)
	return result


## Replays passed mission `id` from the top. False if a mission runs or it can't be replayed.
func replay(id: StringName) -> bool:
	var mission: MissionData = get_mission(id)
	if _active != null or mission == null or not get_replayable().has(mission):
		return false
	_active = mission
	_replay = true
	_failed = false
	_checkpoint = 0
	_begin_at_checkpoint()
	availability_changed.emit()
	return true


## Whether the running mission is a replay.
func is_replay() -> bool:
	return _active != null and _replay


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
	var next: int = _next_applying(_index + 1)
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
	var running: bool = _active != null and not _replay      # a replay is never saved
	return {
		"completed": completed,
		"active": String(_active.id) if running else "",
		"checkpoint": _checkpoint if running else 0,
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
	_index = _next_applying(_checkpoint)
	mission_started.emit(_active, _checkpoint)
	if _index >= _active.objectives.size():
		_pass()
		return
	objective_started.emit(_active, _index)


## The first objective from `from` on that runs given the story's choices (objectives.size() if
## none does).
func _next_applying(from: int) -> int:
	var index: int = from
	while index < _active.objectives.size() and not _active.objectives[index].applies():
		index += 1
	return index


func _pass() -> void:
	var mission: MissionData = _active
	var replayed: bool = _replay
	if not replayed:
		_completed.append(mission.id)
	_clear_active()
	if replayed:
		replay_passed.emit(mission)
	else:
		mission_passed.emit(mission)
	mission_ended.emit(mission)
	availability_changed.emit()


func _clear_active() -> void:
	_active = null
	_index = -1
	_checkpoint = 0
	_failed = false
	_replay = false
