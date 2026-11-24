extends Node
## Player-facing settings: audio volumes and mouse look. Changes apply immediately and are
## persisted to user://settings.cfg (GDD §14). Autoload: Settings.

signal changed(key: StringName)

const SAVE_PATH: String = "user://settings.cfg"
const MOUSE_SENSITIVITY_MIN: float = 0.2
const MOUSE_SENSITIVITY_MAX: float = 3.0
## Volume setting -> audio bus it drives.
const VOLUME_BUSES: Dictionary = {
	&"master_volume": &"Master",
	&"music_volume": &"Music",
	&"sfx_volume": &"SFX",
}

## When false nothing is written to disk (the smoke test uses this so it never touches real settings).
var persist: bool = true

var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
var mouse_sensitivity: float = 1.0
var invert_y: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for key: StringName in VOLUME_BUSES:
		_apply_volume(key)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()


func get_volume(key: StringName) -> float:
	match key:
		&"master_volume":
			return master_volume
		&"music_volume":
			return music_volume
		&"sfx_volume":
			return sfx_volume
	push_error("Settings: unknown volume key '%s'" % key)
	return 0.0


func set_volume(key: StringName, linear: float) -> void:
	var value: float = clampf(linear, 0.0, 1.0)
	match key:
		&"master_volume":
			master_volume = value
		&"music_volume":
			music_volume = value
		&"sfx_volume":
			sfx_volume = value
		_:
			push_error("Settings: unknown volume key '%s'" % key)
			return
	_apply_volume(key)
	changed.emit(key)


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	changed.emit(&"mouse_sensitivity")


func set_invert_y(enabled: bool) -> void:
	invert_y = enabled
	changed.emit(&"invert_y")


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [SAVE_PATH, err])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # first run: keep defaults
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)),
			MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))


func _apply_volume(key: StringName) -> void:
	var bus: int = AudioServer.get_bus_index(VOLUME_BUSES[key])
	if bus < 0:
		push_warning("Settings: audio bus '%s' is missing" % VOLUME_BUSES[key])
		return
	var linear: float = get_volume(key)
	AudioServer.set_bus_mute(bus, linear <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))
