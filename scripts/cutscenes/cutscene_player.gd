class_name CutscenePlayer
extends Node3D
## Plays a CutsceneData (M7): builds an Animation from its shots (the camera's position, where it
## looks and its field of view, eased or gliding, with cuts between shots) and from its actors'
## paths, and plays it on an AnimationPlayer driving a camera rig and the actors' figures. The
## letterbox slides in with each shot's subtitle and caption; the player stands where the
## cutscene puts them, held still; the game camera comes back at the end. Interact skips to the
## next shot. MissionDirector plays one for CUTSCENE objectives.

signal started(data: CutsceneData)
## The cutscene ran to its end (or was skipped through); not emitted by stop().
signal finished(data: CutsceneData)
## A cutscene started (true) or ended, however it ended (false).
signal playing_changed(playing: bool)
## The subtitle changed ("" text: none).
signal line_shown(speaker: String, text: String)

const ANIMATION: StringName = &"cutscene"
## Keys this long before a shot's end hold its last frame; the next shot cuts in after them.
const CUT_SECONDS: float = 0.001

## Models by look (man, woman, older man); MissionDirector hands over its own.
var looks: Array[PackedScene] = []

var _animator: AnimationPlayer
var _camera: Camera3D
var _target: Node3D
var _actors: Node3D
var _letterbox: Letterbox
var _data: CutsceneData
var _player: PlayerController
var _previous: Camera3D
var _figures: Array[CutsceneFigure] = []
var _hidden: Array[Node3D] = []
var _shot_starts: PackedFloat32Array = PackedFloat32Array()
var _shot: int = -1


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.top_level = true
	_camera.far = 1500.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # moved every frame by the animation
	add_child(_camera)
	_target = Node3D.new()
	_target.name = "Target"
	_target.top_level = true
	add_child(_target)
	_actors = Node3D.new()
	_actors.name = "Actors"
	_actors.top_level = true
	add_child(_actors)
	_animator = AnimationPlayer.new()
	_animator.name = "AnimationPlayer"
	_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	add_child(_animator)
	_animator.root_node = _animator.get_path_to(self)
	_letterbox = Letterbox.new()
	_letterbox.name = "Letterbox"
	add_child(_letterbox)


func is_playing() -> bool:
	return _data != null


func get_data() -> CutsceneData:
	return _data


func get_camera() -> Camera3D:
	return _camera


func get_letterbox() -> Letterbox:
	return _letterbox


func get_figures() -> Array[CutsceneFigure]:
	return _figures


## The shot on screen (-1 when not playing).
func get_shot() -> int:
	return _shot if is_playing() else -1


## Seconds into the cutscene.
func get_time() -> float:
	return _animator.current_animation_position if is_playing() else 0.0


func get_animation() -> Animation:
	return _animator.get_animation(ANIMATION) if _animator.has_animation(ANIMATION) else null


## Plays `data` with `player` in it. `contacts`: MissionContact by id, for actors played by a
## mission's people; `stand_ins`: their figures in the world by id, hidden while it plays.
func play(data: CutsceneData, player: PlayerController, contacts: Dictionary = {}, stand_ins: Dictionary = {}) -> void:
	stop()
	if data.shots.is_empty():
		push_error("CutscenePlayer: cutscene %s has no shots" % data.id)
		finished.emit(data)
		return
	_data = data
	_player = player
	var frame: Transform3D = data.get_frame()
	player.input_locked = true
	if not player.is_in_vehicle():
		player.global_position = frame * data.player_position + Vector3.UP * 0.05
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.model.rotation.y = frame.basis.get_euler().y + deg_to_rad(data.player_yaw_degrees)
	for actor: CutsceneActor in data.actors:
		var contact: MissionContact = contacts.get(actor.contact) as MissionContact
		var figure := CutsceneFigure.new()
		figure.setup(actor, contact, looks, frame)
		figure.name = "Actor%d" % _figures.size()          # unique: its animation track names it
		figure.face = player if actor.face_player else null
		_actors.add_child(figure)
		_figures.append(figure)
		var stand_in: Node3D = stand_ins.get(actor.contact) as Node3D
		if stand_in != null and is_instance_valid(stand_in) and stand_in.visible:
			stand_in.visible = false
			_hidden.append(stand_in)
	var library := AnimationLibrary.new()
	library.add_animation(ANIMATION, _build(data, frame))
	if _animator.has_animation_library(&""):
		_animator.remove_animation_library(&"")
	_animator.add_animation_library(&"", library)
	_previous = get_viewport().get_camera_3d()
	_shot = -1
	_animator.play(ANIMATION)
	_animator.advance(0.0)
	_update(0.0)
	_camera.make_current()
	_letterbox.set_shown(true)
	if data.skippable:
		_letterbox.set_skip_hint(ControlsPanel.fill_keys("{interact} skip"))
	started.emit(data)
	playing_changed.emit(true)


## Ends at once without `finished` (the mission failed); everything goes back.
func stop() -> void:
	if _data != null:
		_wrap_up()


## On to the next shot (or the end, from the last one).
func skip() -> void:
	if _data == null or not _data.skippable:
		return
	var next: int = _shot + 1
	if next >= _shot_starts.size():
		_finish()
		return
	_animator.seek(_shot_starts[next] + CUT_SECONDS * 2.0, true)
	_update(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _data != null and event.is_action_pressed("interact"):
		skip()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _data == null:
		return
	_animator.advance(delta)
	_update(delta)
	if _animator.current_animation_position >= _data.get_length() - CUT_SECONDS or not _animator.is_playing():
		_finish()


## After each animation step: the camera looks at its target, the shot's text goes up, the
## actors walk and turn.
func _update(delta: float) -> void:
	if _camera.global_position.distance_squared_to(_target.global_position) > 0.0001:
		_camera.look_at(_target.global_position, Vector3.UP)
	var t: float = _animator.current_animation_position
	var shot: int = 0
	while shot + 1 < _shot_starts.size() and t >= _shot_starts[shot + 1]:
		shot += 1
	if shot != _shot:
		_show_shot(shot)
	for figure: CutsceneFigure in _figures:
		figure.update(delta)


func _show_shot(index: int) -> void:
	_shot = index
	var shot: CutsceneShot = _data.shots[index]
	var parts: PackedStringArray = DialoguePlayer.split(shot.line) if shot.line != "" else PackedStringArray(["", ""])
	_letterbox.show_subtitle(parts[0], parts[1])
	_letterbox.show_caption(shot.caption)
	for figure: CutsceneFigure in _figures:
		figure.talking = parts[0] != "" and figure.speaker.to_upper() == parts[0].to_upper()
	line_shown.emit(parts[0], parts[1])


func _finish() -> void:
	var data: CutsceneData = _data
	_wrap_up()
	finished.emit(data)


func _wrap_up() -> void:
	_animator.stop()
	for figure: CutsceneFigure in _figures:
		figure.queue_free()
	_figures.clear()
	for node: Node3D in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()
	_letterbox.set_shown(false)
	if _player != null and is_instance_valid(_player):
		_player.input_locked = false
		if not _player.is_in_vehicle():
			_player.camera_rig.set_view_degrees(rad_to_deg(_player.model.rotation.y), _player.camera_rig.settings.default_pitch_degrees)
			_player.camera_rig.snap_to_target()
	if _previous != null and is_instance_valid(_previous):
		_previous.make_current()
	_previous = null
	_data = null
	_shot = -1
	line_shown.emit("", "")
	playing_changed.emit(false)


## The animation: the camera rig's position, look target and field of view through every shot,
## and each actor's walk.
func _build(data: CutsceneData, frame: Transform3D) -> Animation:
	var animation := Animation.new()
	animation.length = data.get_length()
	var camera: int = _value_track(animation, "Camera:position")
	var look: int = _value_track(animation, "Target:position")
	var fov: int = _value_track(animation, "Camera:fov")
	_shot_starts = PackedFloat32Array()
	var t: float = 0.0
	for shot: CutsceneShot in data.shots:
		_shot_starts.append(t)
		var end: float = t + maxf(shot.seconds, CUT_SECONDS * 4.0)
		var transition: float = -2.0 if shot.ease else 1.0          # ease in and out, or linear
		animation.track_insert_key(camera, t, frame * shot.camera_from, transition)
		animation.track_insert_key(camera, end - CUT_SECONDS, frame * shot.camera_to)
		animation.track_insert_key(look, t, frame * shot.look_from, transition)
		animation.track_insert_key(look, end - CUT_SECONDS, frame * shot.look_to)
		animation.track_insert_key(fov, t, shot.fov_from, transition)
		animation.track_insert_key(fov, end - CUT_SECONDS, shot.fov_to)
		t = end
	for i: int in data.actors.size():
		var actor: CutsceneActor = data.actors[i]
		var track: int = _value_track(animation, "Actors/%s:position" % _figures[i].name)
		for p: int in actor.path.size():
			var at: float = actor.times[p] if p < actor.times.size() else float(p)
			animation.track_insert_key(track, clampf(at, 0.0, animation.length), frame * actor.path[p])
	return animation


static func _value_track(animation: Animation, path: String) -> int:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(path))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	animation.value_track_set_update_mode(track, Animation.UPDATE_CONTINUOUS)
	return track
