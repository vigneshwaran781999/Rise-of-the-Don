class_name MissionReplay
extends Node
## Replays a story mission already passed (after 1.0; Pause → Missions). Starting one notes where
## the player stands and faces, their health, the time of day and the story's choices, fades to
## black and starts the mission from the top (MissionManager.replay(): no reward, nothing saved).
## When the replay ends (passed, failed and quit, or ended from the pause menu) it puts all of
## that back and fades the player in where they were: a different answer to a story choice in the
## replay leaves the saved story as it was.

## A line for the HUD (the reason a replay can't start, or that the player is back).
signal message(text: String)

const FADE_SECONDS: float = 0.35
## After a replay is passed: at least this long for the banner, and at most OUTRO_MAX_SECONDS
## for the closing lines, before the player goes back.
const BANNER_SECONDS: float = 2.0
const OUTRO_MAX_SECONDS: float = 12.0

var _player: PlayerController
var _director: MissionDirector
var _police: PoliceManager
var _place: Callable
var _mission: MissionData
var _passed: bool = false
var _returning: bool = false
var _snapshot: Dictionary = {}
var _fade: ScreenFade


func _ready() -> void:
	_fade = ScreenFade.new()
	_fade.name = "Fade"
	add_child(_fade)
	MissionManager.replay_passed.connect(_on_replay_passed)
	MissionManager.mission_ended.connect(_on_mission_ended)


func _exit_tree() -> void:
	for pair: Array in [[MissionManager.replay_passed, _on_replay_passed], [MissionManager.mission_ended, _on_mission_ended]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


## `place` puts the player on foot at a Transform3D (GameSession.place_player).
func setup(player: PlayerController, director: MissionDirector, police: PoliceManager, place: Callable) -> void:
	_player = player
	_director = director
	_police = police
	_place = place


## The replay running (or on its way back), or null.
func get_mission() -> MissionData:
	return _mission


## Whether a replay is being played now (not yet ended).
func is_running() -> bool:
	return _mission != null and not _returning and MissionManager.is_replay()


## Why a replay can't start now ("" if it can).
func get_block_reason() -> String:
	if _returning:
		return "Taking you back..."
	if _mission != null:
		return "You're replaying %s. End it first." % _mission.title
	if MissionManager.is_active():
		return "Finish the mission you're on first."
	if WantedSystem.level > 0:
		return "Lose the police first."
	if _player == null or _player.is_down():
		return "Not now."
	if _player.is_in_vehicle():
		return "Get out of the vehicle first."
	return ""


## Replays passed mission `id`; false (and a message) if it can't start now.
func start(id: StringName) -> bool:
	var reason: String = get_block_reason()
	if reason != "":
		message.emit(reason)
		return false
	_snapshot = {
		"position": _player.global_position,
		"yaw": _player.camera_rig.get_yaw(),
		"health": _player.stats.health,
		"hour": GameState.hour,
		"day": GameState.day,
		"choices": GameState.choices.duplicate(),
	}
	_fade.set_alpha(1.0)                 # the jump to the mission's start happens behind black
	if not MissionManager.replay(id):
		_fade.set_alpha(0.0)
		_snapshot = {}
		message.emit("That mission can't be replayed.")
		return false
	_mission = MissionManager.get_mission(id)
	_passed = false
	_fade.fade_to(0.0, FADE_SECONDS * 1.5)
	return true


## Ends the running replay where it stands (the pause menu's End Replay); the player goes back.
func end() -> void:
	if _mission != null and MissionManager.is_replay() and MissionManager.get_active() == _mission:
		MissionManager.quit_mission()


func _on_replay_passed(mission: MissionData) -> void:
	if mission == _mission:
		_passed = true


func _on_mission_ended(mission: MissionData) -> void:
	if mission != _mission or _returning:
		return
	_returning = true
	GameState.choices = (_snapshot["choices"] as Dictionary).duplicate()   # the story as it was
	_go_back.call_deferred()


## After a pass, the banner and the closing lines first; then black, everything put back, and
## the player fades in where they were. Should they have started another mission meanwhile
## (walked into a start marker), they stay with it.
func _go_back() -> void:
	if _passed:
		var waited: float = 0.0
		while waited < OUTRO_MAX_SECONDS and (waited < BANNER_SECONDS or _director.dialogue.is_playing()):
			await get_tree().create_timer(0.25, false).timeout
			waited += 0.25
	if not MissionManager.is_active():
		await _fade.fade_to(1.0, FADE_SECONDS).finished
		_restore()
		message.emit("Back where you were.")
		_fade.fade_to(0.0, FADE_SECONDS * 1.5)
	_mission = null
	_snapshot = {}
	_returning = false


func _restore() -> void:
	WantedSystem.clear()                 # the replay started with a clean record
	_police.clear_all()
	_place.call(Transform3D(Basis(Vector3.UP, float(_snapshot["yaw"])), _snapshot["position"]))
	if _player.is_down():
		_player.revive()
	_player.stats.set_health(float(_snapshot["health"]))
	GameState.day = int(_snapshot["day"])
	GameState.set_hour(float(_snapshot["hour"]))
