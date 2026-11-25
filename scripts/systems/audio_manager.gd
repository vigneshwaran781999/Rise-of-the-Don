extends Node
## Plays UI sounds, one-shot sound effects, music and looping ambience layers (rain from M7) on the
## right audio buses (GDD §13).
## Every sound is currently a synthesised placeholder (see AudioSynth). Autoload: AudioManager.

const UI_BUS: StringName = &"UI"
const SFX_BUS: StringName = &"SFX"
const MUSIC_BUS: StringName = &"Music"
const AMBIENCE_BUS: StringName = &"Ambience"
const UI_VOICES: int = 4
const SFX_VOICES: int = 8
const MUSIC_DB: float = -6.0

var _streams: Dictionary = {}  # StringName -> AudioStream
var _ui_players: Array[AudioStreamPlayer] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _music_tween: Tween
var _current_music: StringName = &""
var _wanted_music: StringName = &""
var _pad_task: int = -1
var _pad_stream: AudioStreamWAV  # written by the worker thread, read once the task completes
var _ambience: Dictionary = {}  # layer StringName -> AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_streams[&"ui_move"] = AudioSynth.blips(PackedFloat32Array([1320.0]), 0.035, 0.16)
	_streams[&"ui_accept"] = AudioSynth.blips(PackedFloat32Array([880.0, 1320.0]), 0.045, 0.24)
	_streams[&"ui_back"] = AudioSynth.blips(PackedFloat32Array([1320.0, 880.0]), 0.045, 0.2)
	_streams[&"footstep"] = AudioSynth.thump(0.09, 0.35, 95.0, 0.55, 11)
	_streams[&"land"] = AudioSynth.thump(0.22, 0.2, 62.0, 0.85, 23)
	# Mission stingers (GDD §13): rising for start and pass, falling for failure.
	_streams[&"mission_start"] = AudioSynth.blips(PackedFloat32Array([523.3, 784.0, 1046.5]), 0.11, 0.22)
	_streams[&"mission_passed"] = AudioSynth.blips(PackedFloat32Array([523.3, 659.3, 784.0, 1046.5, 1318.5]), 0.13, 0.26)
	_streams[&"mission_failed"] = AudioSynth.blips(PackedFloat32Array([440.0, 370.0, 311.1, 233.1]), 0.18, 0.26)
	_streams[&"objective"] = AudioSynth.blips(PackedFloat32Array([1174.7, 1568.0]), 0.07, 0.2)
	_streams[&"cash"] = AudioSynth.blips(PackedFloat32Array([1975.5, 2637.0]), 0.05, 0.16)
	_streams[&"rain"] = AudioSynth.rain_loop()
	for i: int in UI_VOICES:
		_ui_players.append(_make_player(UI_BUS))
	for i: int in SFX_VOICES:
		_sfx_players.append(_make_player(SFX_BUS))
	_music_player = _make_player(MUSIC_BUS)
	_pad_task = WorkerThreadPool.add_task(_build_pad, false, "Synthesise menu music")


func _process(_delta: float) -> void:
	if _pad_task == -1 or not WorkerThreadPool.is_task_completed(_pad_task):
		return
	WorkerThreadPool.wait_for_task_completion(_pad_task)
	_pad_task = -1
	_streams[&"menu_pad"] = _pad_stream
	set_process(false)
	if _wanted_music != &"" and _current_music != _wanted_music:
		play_music(_wanted_music)


func _exit_tree() -> void:
	if _pad_task != -1:
		WorkerThreadPool.wait_for_task_completion(_pad_task)
		_pad_task = -1
	_silence()


## Stops every sound, gives the audio thread a moment to release them, then quits. Quitting
## while a sound plays makes Godot report the playing stream as leaked at exit. The game is
## paused first so nothing (a running car engine, for one) starts a sound again meanwhile.
func quit_game(exit_code: int = 0) -> void:
	get_tree().paused = true
	_silence()
	for node: Node in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		(node as AudioStreamPlayer3D).stop()
		(node as AudioStreamPlayer3D).stream = null    # drops the playback at once
	await get_tree().create_timer(0.1, true, false, true).timeout
	OS.delay_msec(60)   # real time for the audio thread (game time can run faster, e.g. --fixed-fps)
	get_tree().quit(exit_code)


func _silence() -> void:
	_kill_music_tween()
	_wanted_music = &""
	_current_music = &""
	for player: AudioStreamPlayer in _ui_players + _sfx_players + [_music_player]:
		player.stop()
		player.stream = null
	for layer: StringName in _ambience:
		(_ambience[layer] as AudioStreamPlayer).stop()
		(_ambience[layer] as AudioStreamPlayer).stream = null
	_ambience.clear()


func has_stream(sound: StringName) -> bool:
	return _streams.has(sound)


func play_ui(sound: StringName) -> void:
	_play_on(_ui_players, sound, 0.0, 1.0)


func play_sfx(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_play_on(_sfx_players, sound, volume_db, pitch)


## Fades in a looping track. If it is still being synthesised it starts as soon as it's ready.
func play_music(track: StringName, fade_seconds: float = 1.5) -> void:
	_wanted_music = track
	if not _streams.has(track):
		return
	if _current_music == track and _music_player.playing:
		return
	_current_music = track
	_kill_music_tween()
	_music_player.stream = _streams[track]
	_music_player.volume_db = -40.0
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", MUSIC_DB, fade_seconds)


func stop_music(fade_seconds: float = 0.8) -> void:
	_wanted_music = &""
	_current_music = &""
	if not _music_player.playing:
		return
	_kill_music_tween()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", -40.0, fade_seconds)
	_music_tween.tween_callback(_music_player.stop)


func is_music_playing() -> bool:
	return _music_player.playing


## Plays the looping ambience layer `layer` (a sound name: &"rain"...) at `level` (0-1, linear
## volume) on the Ambience bus; 0 stops it.
func set_ambience(layer: StringName, level: float) -> void:
	var player: AudioStreamPlayer = _ambience.get(layer)
	if level <= 0.001:
		if player != null and player.playing:
			player.stop()
		return
	if player == null:
		if not _streams.has(layer):
			return
		player = _make_player(AMBIENCE_BUS)
		player.stream = _streams[layer]
		_ambience[layer] = player
	player.volume_db = linear_to_db(level)
	if not player.playing:
		player.play()


## The level an ambience layer is playing at (0 when it isn't).
func get_ambience(layer: StringName) -> float:
	var player: AudioStreamPlayer = _ambience.get(layer)
	return db_to_linear(player.volume_db) if player != null and player.playing else 0.0


func _play_on(pool: Array[AudioStreamPlayer], sound: StringName, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		push_warning("AudioManager: unknown sound '%s'" % sound)
		return
	var player: AudioStreamPlayer = pool[0]
	for candidate: AudioStreamPlayer in pool:
		if not candidate.playing:
			player = candidate
			break
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _make_player(bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()


func _build_pad() -> void:
	_pad_stream = AudioSynth.ambient_pad()
