class_name VehicleAudio
extends Node3D
## Positional car sounds on the SFX bus (GDD §13): engine note pitched by rpm and louder with
## throttle, horn, tyre screech while sliding, crash on impacts and a door thunk when someone
## gets in or out. All sounds are synthesised placeholders (AudioSynth) shared by every car.
## Must be a direct child of a VehicleController with Engine and Damage siblings.

const BUS: StringName = &"SFX"
## Below this speed (m/s) sliding tyres stay quiet.
const SKID_MIN_SPEED: float = 4.0

static var _streams: Dictionary = {}

var _vehicle: VehicleController
var _engine: VehicleEngine
var _engine_player: AudioStreamPlayer3D
var _horn_player: AudioStreamPlayer3D
var _skid_player: AudioStreamPlayer3D
var _oneshot_player: AudioStreamPlayer3D
var _engine_level: float = 0.0


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	_engine = _vehicle.get_node("Engine") as VehicleEngine
	_engine_player = _make_player("EngineSound", &"engine", 10.0)
	_horn_player = _make_player("HornSound", &"horn", 14.0)
	_skid_player = _make_player("SkidSound", &"skid", 10.0)
	_oneshot_player = _make_player("ImpactSound", &"crash", 12.0)
	_vehicle.horn_changed.connect(_on_horn_changed)
	_vehicle.driver_changed.connect(_on_driver_changed)
	(_vehicle.get_node("Damage") as VehicleDamage).impacted.connect(_on_impacted)


func is_engine_audible() -> bool:
	return _engine_player.playing


func is_horn_playing() -> bool:
	return _horn_player.playing


func _physics_process(delta: float) -> void:
	# Engine: fades in and out with the engine, pitch follows rpm, louder under load.
	var target_level: float = 1.0 if _vehicle.is_engine_running() else 0.0
	_engine_level = move_toward(_engine_level, target_level, delta * (2.5 if target_level > 0.0 else 1.2))
	if _engine_level > 0.0 and _engine.rpm > 50.0:
		if not _engine_player.playing:
			_engine_player.play()
		_engine_player.pitch_scale = clampf(_engine.rpm / AudioSynth.ENGINE_LOOP_RPM, 0.3, 3.6)
		var loudness: float = lerpf(-16.0, -5.0, _vehicle.get_engine_load())
		_engine_player.volume_db = loudness + linear_to_db(maxf(_engine_level, 0.001))
	elif _engine_player.playing:
		_engine_player.stop()

	# Tyres: screech in proportion to how much the worst wheel is sliding.
	var slide: float = 0.0
	if _vehicle.linear_velocity.length() > SKID_MIN_SPEED:
		for wheel: VehicleWheel3D in _vehicle.get_wheels():
			if wheel.is_in_contact():
				slide = maxf(slide, 1.0 - wheel.get_skidinfo())
	if slide > 0.25:
		if not _skid_player.playing:
			_skid_player.play()
		_skid_player.volume_db = lerpf(-20.0, -4.0, clampf((slide - 0.25) / 0.6, 0.0, 1.0))
	elif _skid_player.playing:
		_skid_player.stop()


func _on_horn_changed(on: bool) -> void:
	if on:
		_horn_player.play()
	else:
		_horn_player.stop()


func _on_impacted(impact_kmh: float, _damage: float) -> void:
	var loudness: float = clampf((impact_kmh - 6.0) / 50.0, 0.0, 1.0)
	_oneshot_player.stream = _stream(&"crash")
	_oneshot_player.volume_db = lerpf(-14.0, 2.0, loudness)
	_oneshot_player.pitch_scale = randf_range(0.9, 1.08)
	_oneshot_player.play()


func _on_driver_changed(_driver: Node3D) -> void:
	_oneshot_player.stream = _stream(&"door")
	_oneshot_player.volume_db = -6.0
	_oneshot_player.pitch_scale = randf_range(0.95, 1.05)
	_oneshot_player.play()


func _make_player(node_name: String, sound: StringName, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.bus = BUS
	player.stream = _stream(sound)
	player.unit_size = unit_size
	player.max_distance = 120.0
	add_child(player)
	return player


static func _stream(sound: StringName) -> AudioStream:
	if not _streams.has(sound):
		match sound:
			&"engine":
				_streams[sound] = AudioSynth.engine_loop()
			&"horn":
				_streams[sound] = AudioSynth.horn_loop()
			&"skid":
				_streams[sound] = AudioSynth.skid_loop()
			&"crash":
				_streams[sound] = AudioSynth.crash()
			&"door":
				_streams[sound] = AudioSynth.thump(0.16, 0.22, 78.0, 0.9, 31)
	return _streams[sound]
