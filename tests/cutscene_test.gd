extends Node
## Cutscene test (per-feature test scene, M7 cutscenes). Runs the real game scene (traffic and
## pedestrians off) and plays a three-shot cutscene built here on the east gopuram road:
## - the camera rig follows the shots' keys (an eased glide, a cut, a steady glide), looking at
##   its target, with each shot's field of view; captions and subtitles in the letterbox;
## - an actor walks its path on time, facing the way it walks, and gestures on its line;
## - the player stands where the cutscene puts them, held still; the HUD steps aside;
## - interact skips shot by shot; at the end the game camera, control and HUD come back;
## - as a mission objective (CUTSCENE): a mission contact plays a part (their figure in the
##   world steps aside), the objective completes at the end; a failure mid-cutscene stops it.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/cutscene_test.tscn
## Prints "CUTSCENE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
## The north sidewalk of the east gopuram road; the cutscene faces east along it.
const SPOT := Vector3(70.0, 0.15, -8.0)
const FRAME_YAW: float = -90.0
const CAPTION: String = "OLD TOWN, AFTER DARK"

var _catcher: ErrorCatcher
var _game: GameSession
var _player: PlayerController
var _director: MissionDirector
var _cutscene: CutscenePlayer
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	SaveManager.save_dir = "user://test_saves"
	_game = GAME.instantiate() as GameSession
	add_child(_game)
	_run.call_deferred()


func _run() -> void:
	_player = _game.player
	_director = _game.missions
	_cutscene = _director.get_cutscene()
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).clear()
	MissionManager.quit_mission()
	await _frames(10)
	var steps: Array[Callable] = [_check_playback, _check_skip, _check_objective, _check_failure]
	var failure: String = ""
	for step: Callable in steps:
		failure = await step.call()
		if failure != "":
			failure = "%s: %s" % [step.get_method(), failure]
			break
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "%s: engine/script error: %s" % [step.get_method(), errors[0]]
			break
	_cutscene.stop()
	get_tree().paused = false
	print("CUTSCENE REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("CUTSCENE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


## Three shots: a wide establishing glide with a caption (eased), a cut to Ravi walking up with
## his line (steady), and a reverse shot for Vetri's reply. Ravi walks 6 m -> 2 m in front of the
## player between 1 s and 3.5 s; a thug stands by with fists up.
func _make_cutscene(contact_id: StringName = &"") -> CutsceneData:
	var data := CutsceneData.new()
	data.id = &"test_meeting"
	data.anchor = SPOT
	data.anchor_yaw_degrees = FRAME_YAW
	data.player_position = Vector3.ZERO
	data.player_yaw_degrees = 0.0
	var ravi := CutsceneActor.new()
	ravi.speaker = "Ravi"
	ravi.contact = contact_id
	ravi.top_color = Color("c23a2b")
	ravi.path = PackedVector3Array([Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -6.0), Vector3(0.0, 0.0, -2.0)])
	ravi.times = PackedFloat32Array([0.0, 1.0, 3.5])
	ravi.yaw_degrees = 180.0
	var thug := CutsceneActor.new()
	thug.speaker = "Thug"
	thug.guard = true
	thug.path = PackedVector3Array([Vector3(2.0, 0.0, -5.0)])
	data.actors = [ravi, thug]
	var wide := CutsceneShot.new()
	wide.seconds = 2.0
	wide.camera_from = Vector3(6.0, 4.0, 4.0)
	wide.camera_to = Vector3(4.0, 3.0, 2.0)
	wide.look_from = Vector3(0.0, 1.0, -3.0)
	wide.look_to = Vector3(0.0, 1.0, -3.0)
	wide.fov_from = 60.0
	wide.fov_to = 50.0
	wide.caption = CAPTION
	var close := CutsceneShot.new()
	close.seconds = 2.0
	close.camera_from = Vector3(1.5, 1.6, -1.0)
	close.camera_to = Vector3(1.5, 1.6, -1.5)
	close.look_from = Vector3(0.0, 1.5, -4.0)
	close.look_to = Vector3(0.0, 1.5, -3.0)
	close.fov_from = 40.0
	close.fov_to = 40.0
	close.ease = false
	close.line = "RAVI: You took your time."
	var reverse := CutsceneShot.new()
	reverse.seconds = 1.5
	reverse.camera_from = Vector3(-0.8, 1.7, -3.2)
	reverse.camera_to = Vector3(-0.8, 1.7, -3.2)
	reverse.look_from = Vector3(0.0, 1.5, 0.0)
	reverse.look_to = Vector3(0.0, 1.5, 0.0)
	reverse.line = "VETRI: Traffic."
	data.shots = [wide, close, reverse]
	return data


func _check_playback() -> String:
	_game.place_player(Transform3D(Basis.IDENTITY, SPOT + Vector3(-5.0, 0.15, 3.0)))
	await _frames(10)
	var data: CutsceneData = _make_cutscene()
	var frame: Transform3D = data.get_frame()
	var game_camera: Camera3D = get_viewport().get_camera_3d()
	var ended: Array[bool] = [false]
	_cutscene.finished.connect(func(_d: CutsceneData) -> void: ended[0] = true, CONNECT_ONE_SHOT)
	_cutscene.play(data, _player)
	await _frames(1)
	if not _cutscene.is_playing() or get_viewport().get_camera_3d() != _cutscene.get_camera():
		return "playing should switch to the cutscene camera"
	if not _player.input_locked or _flat(_player.global_position).distance_to(_flat(frame * data.player_position)) > 0.3:
		return "the player should be held still at their spot (held %s, %.1f m off)" % [
			_player.input_locked, _flat(_player.global_position).distance_to(_flat(frame * data.player_position))]
	if _game.hud.visible:
		return "the HUD should step aside during a cutscene"
	var animation: Animation = _cutscene.get_animation()
	if animation == null or animation.get_track_count() != 3 + data.actors.size() or absf(animation.length - 5.5) > 0.01:
		return "the animation should have camera, target, fov and one track per actor, 5.5 s long (%s)" % [
			"none" if animation == null else "%d tracks, %.2f s" % [animation.get_track_count(), animation.length]]
	var start_error: float = _cutscene.get_camera().global_position.distance_to(frame * data.shots[0].camera_from)
	if start_error > 0.1:
		return "the first shot should start at its camera_from (%.2f m off)" % start_error
	# A quarter of the way into the eased first shot it has moved less than a quarter of the way.
	await _until(0.5)
	var from0: Vector3 = frame * data.shots[0].camera_from
	var to0: Vector3 = frame * data.shots[0].camera_to
	var eased: float = (_cutscene.get_camera().global_position - from0).length() / (to0 - from0).length()
	if eased > 0.2:
		return "the first shot is eased: at a quarter of its time it should be under a quarter of the way (%.2f)" % eased
	var letterbox: Letterbox = _cutscene.get_letterbox()
	if letterbox.get_share() < 0.99 or letterbox.get_caption() != CAPTION or letterbox.get_subtitle() != "":
		return "the letterbox should be in with the caption and no subtitle (share %.2f, caption '%s', subtitle '%s')" % [
			letterbox.get_share(), letterbox.get_caption(), letterbox.get_subtitle()]
	var looking: float = rad_to_deg((-_cutscene.get_camera().global_basis.z).angle_to(
		(frame * data.shots[0].look_from - _cutscene.get_camera().global_position).normalized()))
	if looking > 2.0:
		return "the camera should look at its target (%.1f degrees off)" % looking
	# The cut to the second shot: the camera jumps.
	await _until(1.95)
	var before_cut: Vector3 = _cutscene.get_camera().global_position
	await _until(2.05)
	var jump: float = before_cut.distance_to(_cutscene.get_camera().global_position)
	var cut_error: float = _cutscene.get_camera().global_position.distance_to(frame * data.shots[1].camera_from)
	if _cutscene.get_shot() != 1 or jump < 2.0 or cut_error > 0.1:
		return "the second shot should cut in at its camera_from (shot %d, jumped %.1f m, %.2f m off)" % [_cutscene.get_shot(), jump, cut_error]
	if not letterbox.get_subtitle().contains("You took your time") or not letterbox.get_subtitle().begins_with("RAVI"):
		return "the second shot's subtitle should show (got '%s')" % letterbox.get_subtitle()
	if absf(_cutscene.get_camera().fov - 40.0) > 0.5:
		return "the second shot's field of view should be 40 (%.1f)" % _cutscene.get_camera().fov
	# Ravi, halfway along his walk (2.25 s), facing the way he walks, talking.
	await _until(2.25)
	var figures: Array[CutsceneFigure] = _cutscene.get_figures()
	var ravi: CutsceneFigure = figures[0]
	var thug: CutsceneFigure = figures[1]
	var walk_error: float = _flat(ravi.global_position).distance_to(_flat(frame * Vector3(0.0, 0.0, -4.0)))
	var heading: float = rad_to_deg(Vector3(sin(ravi.get_yaw()), 0.0, cos(ravi.get_yaw())).angle_to(frame.basis * Vector3(0.0, 0.0, 1.0)))
	if walk_error > 0.3:
		return "Ravi should be halfway along his walk at 2.25 s (%.2f m off)" % walk_error
	if heading > 20.0:
		return "Ravi should face the way he walks (%.0f degrees off)" % heading
	if not ravi.talking or thug.talking:
		return "Ravi should gesture on his line, the thug not (Ravi %s, thug %s)" % [ravi.talking, thug.talking]
	# The second shot glides steadily: halfway through (3 s) the camera is halfway.
	await _until(3.0)
	var steady_error: float = _cutscene.get_camera().global_position.distance_to(frame * Vector3(1.5, 1.6, -1.25))
	if steady_error > 0.05:
		return "the second shot glides steadily: halfway through it should be halfway (%.2f m off)" % steady_error
	await _until(4.0)
	if not letterbox.get_subtitle().begins_with("VETRI"):
		return "the third shot's subtitle should be Vetri's (got '%s')" % letterbox.get_subtitle()
	for i: int in 120:
		if ended[0]:
			break
		await get_tree().process_frame
	if not ended[0] or _cutscene.is_playing():
		return "the cutscene should end after 5.5 s"
	await _frames(30)
	if get_viewport().get_camera_3d() != game_camera or _player.input_locked or not _game.hud.visible:
		return "afterwards the game camera, control and the HUD should come back"
	if letterbox.get_share() > 0.01 or not _cutscene.get_figures().is_empty():
		return "afterwards the letterbox and the actors should be gone"
	_note("playback: eased wide shot with a caption (%.0f%% of the way at a quarter of the time), a %.1f m cut to the close-up, a steady glide, fov keys; Ravi walks his path on time facing the way he goes and gestures on his line; HUD aside, player held; all back at the end" % [
		eased * 100.0, jump])
	return ""


func _check_skip() -> String:
	var data: CutsceneData = _make_cutscene()
	var ended: Array[bool] = [false]
	_cutscene.finished.connect(func(_d: CutsceneData) -> void: ended[0] = true, CONNECT_ONE_SHOT)
	_cutscene.play(data, _player)
	await _frames(20)
	var shots: Array[int] = [_cutscene.get_shot()]
	for press: int in 3:
		_press(&"interact")
		await _frames(3)
		shots.append(_cutscene.get_shot())
	if shots != [0, 1, 2, -1] or not ended[0]:
		return "interact should skip shot by shot to the end (shots %s, ended %s)" % [shots, ended[0]]
	if _player.input_locked or not _game.hud.visible:
		return "skipping to the end should give control back"
	_note("interact skips shot by shot to the end (shots %s)" % [shots])
	return ""


## A mission whose first objective is the cutscene, with Ravi played by the mission's contact.
func _make_mission(id: StringName) -> MissionData:
	var contact := MissionContact.new()
	contact.id = &"ravi"
	contact.display_name = "Ravi"
	contact.look = 2
	contact.top_color = Color("2f7d4f")
	contact.position = SPOT + Vector3(12.0, 0.0, 0.0)
	var scene := MissionObjective.new()
	scene.type = MissionObjective.Type.CUTSCENE
	scene.text = "Meet Ravi."
	scene.cutscene = _make_cutscene(&"ravi")
	var walk := MissionObjective.new()
	walk.type = MissionObjective.Type.GO_TO
	walk.text = "Go to the temple."
	walk.position = Vector3(30.0, 0.15, -8.0)
	var mission := MissionData.new()
	mission.id = id
	mission.title = "Cutscene Test"
	mission.start_position = SPOT
	mission.contacts = [contact]
	mission.objectives = [scene, walk]
	MissionManager.story.missions.append(mission)
	return mission


func _check_objective() -> String:
	var mission: MissionData = _make_mission(&"cutscene_test")
	if not MissionManager.start(mission.id):
		return "couldn't start the test mission"
	for i: int in 30:
		if _cutscene.is_playing():
			break
		await get_tree().process_frame
	if not _cutscene.is_playing():
		return "a CUTSCENE objective should play its cutscene"
	var stand_in: MissionContactNPC = _director.get_contact(&"ravi")
	var ravi: CutsceneFigure = _cutscene.get_figures()[0]
	var shirt: Color = ravi.get_node("Model").get_instance_shader_parameter(&"top_color")
	if stand_in == null or stand_in.visible:
		return "Ravi's figure in the world should step aside while he plays his part"
	if ravi.speaker != "Ravi" or not shirt.is_equal_approx(mission.contacts[0].top_color):
		return "the contact should lend the actor their name and colours (speaker '%s', shirt %s)" % [ravi.speaker, shirt]
	for press: int in 3:
		_press(&"interact")
		await _frames(3)
	await _frames(5)
	if MissionManager.get_objective_index() != 1:
		return "the cutscene's end should complete the objective (objective %d)" % MissionManager.get_objective_index()
	if not stand_in.visible:
		return "Ravi's figure should be back after the cutscene"
	MissionManager.quit_mission()
	await _frames(5)
	_note("as an objective: plays at once, the contact lends Ravi his name and colours and steps aside, the end moves the mission on")
	return ""


func _check_failure() -> String:
	if not MissionManager.start(&"cutscene_test"):
		return "couldn't start the test mission again"
	for i: int in 30:
		if _cutscene.is_playing():
			break
		await get_tree().process_frame
	await _frames(20)
	MissionManager.fail("Test failure.")
	await _frames(5)
	if _cutscene.is_playing() or _player.input_locked or not _game.hud.visible:
		return "a failure mid-cutscene should stop it and give control back"
	var failed := _game.get_node("MissionFailed") as MissionFailedScreen
	for i: int in 120:
		if failed.is_open():
			break
		await get_tree().process_frame
	failed.quit_mission()
	await _frames(5)
	MissionManager.story.missions.erase(MissionManager.get_mission(&"cutscene_test"))
	_note("a failure mid-cutscene stops it: camera, control and HUD back")
	return ""


# --------------------------------------------------------------------------- helpers

## Waits until the cutscene is `seconds` in.
func _until(seconds: float) -> void:
	while _cutscene.is_playing() and _cutscene.get_time() < seconds:
		await get_tree().process_frame


func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
