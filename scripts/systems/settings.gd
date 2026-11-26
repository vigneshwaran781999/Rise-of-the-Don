extends Node
## Player-facing settings: audio volumes, mouse look, how busy the streets are (pedestrian and
## traffic density, GDD §6) and graphics (M8: a quality preset, ambient occlusion, glow, shadows,
## render scale, VSync, fullscreen) and, after 1.0, the controls (rebinding; InputBindings). Changes
## apply immediately and are persisted to user://settings.cfg (GDD §14). Autoload: Settings.

signal changed(key: StringName)

const SAVE_PATH: String = "user://settings.cfg"
const MOUSE_SENSITIVITY_MIN: float = 0.2
const MOUSE_SENSITIVITY_MAX: float = 3.0
## Density levels for pedestrians and traffic (index = level).
const DENSITY_NAMES: PackedStringArray = ["Low", "Medium", "High"]
const QUALITY_NAMES: PackedStringArray = ["Low", "Medium", "High"]
const SHADOW_NAMES: PackedStringArray = ["Low", "Medium", "High"]
const RENDER_SCALES: PackedFloat32Array = [0.67, 0.77, 0.85, 1.0]
## What each quality preset sets: [ambient occlusion, glow, shadow quality, render scale].
## Low aims at 60 FPS at 1080p on integrated graphics (Intel UHD 730); Medium at 60 on a
## GTX 1650-class laptop (40+ on the UHD 730); High adds ambient occlusion and the best shadows.
const QUALITY_PRESETS: Array = [
	[false, false, 0, 0.77],
	[false, true, 1, 0.77],
	[true, true, 2, 1.0],
]
## Per shadow quality ("shadows and lights"): [sun shadow atlas size, split count, shadow distance
## factor, soft filter, streetlights that cast real light at night].
const SHADOW_LEVELS: Array = [
	[2048, 2, 0.6, RenderingServer.SHADOW_QUALITY_HARD, 2],
	[4096, 4, 1.0, RenderingServer.SHADOW_QUALITY_SOFT_LOW, 4],
	[4096, 4, 1.25, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, 4],
]
## Volume setting -> audio bus it drives.
const VOLUME_BUSES: Dictionary = {
	&"master_volume": &"Master",
	&"music_volume": &"Music",
	&"sfx_volume": &"SFX",
}

## When false nothing is written to disk and the controls are the defaults (tests use this, so
## they never touch real settings and their key presses mean what they expect).
var persist: bool = true:
	set(value):
		persist = value
		if not value:
			InputMap.load_from_project_settings()
			_bindings.clear()
## The settings file (tests point this at a scratch file).
var save_path: String = SAVE_PATH
## Rebound controls (after 1.0): action -> its three slots as InputBindings.to_data() data.
var _bindings: Dictionary = {}

var master_volume: float = 0.8
var music_volume: float = 0.6
var sfx_volume: float = 0.8
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
## 0 low, 1 medium, 2 high (counts per level: resources/characters/population.tres).
var pedestrian_density: int = 1
var traffic_density: int = 1

## The quality preset last chosen (QUALITY_NAMES); changing one option after it keeps the name
## but the options are what count.
var quality: int = 1
## Screen-space ambient occlusion (soft shadows in corners), where the time of day uses it.
var ambient_occlusion: bool = false
## Bloom around bright lights and neon.
var glow: bool = true
## SHADOW_NAMES: how sharp the sun's shadows are and how far they reach.
var shadow_quality: int = 1
## Share of the window's resolution the 3D view renders at (upscaled with AMD FSR below 100%).
var render_scale: float = 1.0
var vsync: bool = true
var fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for key: StringName in VOLUME_BUSES:
		_apply_volume(key)
	apply_display()


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


## key: &"pedestrian_density" or &"traffic_density"; level 0 low, 1 medium, 2 high.
func set_density(key: StringName, level: int) -> void:
	var value: int = clampi(level, 0, DENSITY_NAMES.size() - 1)
	match key:
		&"pedestrian_density":
			pedestrian_density = value
		&"traffic_density":
			traffic_density = value
		_:
			push_error("Settings: unknown density key '%s'" % key)
			return
	changed.emit(key)


func get_density(key: StringName) -> int:
	return pedestrian_density if key == &"pedestrian_density" else traffic_density


# --------------------------------------------------------------------------- graphics

## Sets every graphics option to quality preset `level` (QUALITY_PRESETS).
func set_quality(level: int) -> void:
	quality = clampi(level, 0, QUALITY_PRESETS.size() - 1)
	var preset: Array = QUALITY_PRESETS[quality]
	ambient_occlusion = preset[0]
	glow = preset[1]
	shadow_quality = preset[2]
	render_scale = preset[3]
	_graphics_changed()


func set_ambient_occlusion(enabled: bool) -> void:
	ambient_occlusion = enabled
	_graphics_changed()


func set_glow(enabled: bool) -> void:
	glow = enabled
	_graphics_changed()


func set_shadow_quality(level: int) -> void:
	shadow_quality = clampi(level, 0, SHADOW_NAMES.size() - 1)
	_graphics_changed()


## The nearest of RENDER_SCALES to `scale`.
func set_render_scale(scale: float) -> void:
	var best: float = RENDER_SCALES[RENDER_SCALES.size() - 1]
	for option: float in RENDER_SCALES:
		if absf(option - scale) < absf(best - scale):
			best = option
	render_scale = best
	_graphics_changed()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	_graphics_changed()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_graphics_changed()


## [atlas size, splits, distance factor, soft filter] for the shadow quality (SHADOW_LEVELS).
func get_shadow_level() -> Array:
	return SHADOW_LEVELS[shadow_quality]


## Applies what belongs to the window and the renderer: render scale (FSR upscaling below 100%),
## VSync, fullscreen, the sun's shadow atlas and filter. WorldLighting applies ambient occlusion,
## glow, shadow splits and distance (on `changed` with &"graphics").
func apply_display() -> void:
	var root: Viewport = get_tree().root
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = render_scale
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(mode)
	var level: Array = get_shadow_level()
	RenderingServer.directional_shadow_atlas_set_size(int(level[0]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(level[3])


func _graphics_changed() -> void:
	apply_display()
	changed.emit(&"graphics")


func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("world", "pedestrian_density", pedestrian_density)
	cfg.set_value("world", "traffic_density", traffic_density)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "ambient_occlusion", ambient_occlusion)
	cfg.set_value("graphics", "glow", glow)
	cfg.set_value("graphics", "shadow_quality", shadow_quality)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	for action: StringName in _bindings:
		cfg.set_value("bindings", String(action), _bindings[action])
	var err: Error = cfg.save(save_path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [save_path, err])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return  # first run: keep defaults
	_load_bindings(cfg)
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)),
			MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	pedestrian_density = clampi(int(cfg.get_value("world", "pedestrian_density", pedestrian_density)), 0, 2)
	traffic_density = clampi(int(cfg.get_value("world", "traffic_density", traffic_density)), 0, 2)
	quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, QUALITY_NAMES.size() - 1)
	ambient_occlusion = bool(cfg.get_value("graphics", "ambient_occlusion", ambient_occlusion))
	glow = bool(cfg.get_value("graphics", "glow", glow))
	shadow_quality = clampi(int(cfg.get_value("graphics", "shadow_quality", shadow_quality)), 0, SHADOW_NAMES.size() - 1)
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.5, 1.0)
	vsync = bool(cfg.get_value("graphics", "vsync", vsync))
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", fullscreen))


# --------------------------------------------------------------------------- controls (after 1.0)

## Puts `event` in `slot` (InputBindings.Slot) of `action`; null clears the slot. A keyboard or
## mouse input goes only in a key slot, a gamepad one only in the gamepad slot. If another action
## that is live at the same time already has that input, the two swap: it gets this slot's old
## input. Saved at once. Returns the action it swapped with, or &"".
func bind(action: StringName, slot: int, event: InputEvent) -> StringName:
	if not InputBindings.CONTEXTS.has(action):
		return &""
	if event != null and InputBindings.is_keyboard(event) != (slot != InputBindings.Slot.PAD):
		return &""
	var slots: Array = InputBindings.get_slots(action)
	var old: InputEvent = slots[slot]
	var swapped: StringName = &""
	if event != null:
		var kinds: Array = [InputBindings.Slot.PAD] if slot == InputBindings.Slot.PAD else [InputBindings.Slot.KEY, InputBindings.Slot.ALT_KEY]
		for other: StringName in InputBindings.get_actions():
			if other != action and not InputBindings.clash(action, other):
				continue
			var other_slots: Array = slots if other == action else InputBindings.get_slots(other)
			for other_slot: int in kinds:
				if (other == action and other_slot == slot) or not InputBindings.same_input(other_slots[other_slot], event):
					continue
				other_slots[other_slot] = old
				if other != action:
					InputBindings.set_slots(other, other_slots)
					_remember(other)
					swapped = other
	slots[slot] = event
	InputBindings.set_slots(action, slots)
	_remember(action)
	save_settings()
	changed.emit(&"controls")
	return swapped


## Every control back to its default (project.godot's input map).
func reset_controls() -> void:
	InputMap.load_from_project_settings()
	_bindings.clear()
	save_settings()
	changed.emit(&"controls")


func _remember(action: StringName) -> void:
	var data: Array = []
	for event: Variant in InputBindings.get_slots(action):
		data.append(InputBindings.to_data(event as InputEvent))
	_bindings[action] = data


func _load_bindings(cfg: ConfigFile) -> void:
	InputMap.load_from_project_settings()
	_bindings.clear()
	if not cfg.has_section("bindings"):
		return
	for key: String in cfg.get_section_keys("bindings"):
		var action := StringName(key)
		var data: Variant = cfg.get_value("bindings", key, [])
		if not InputBindings.CONTEXTS.has(action) or not InputMap.has_action(action) or not (data is Array) or (data as Array).size() != 3:
			continue
		var slots: Array = []
		for entry: Variant in data:
			slots.append(InputBindings.from_data(entry as Dictionary) if entry is Dictionary else null)
		InputBindings.set_slots(action, slots)
		_remember(action)


func _apply_volume(key: StringName) -> void:
	var bus: int = AudioServer.get_bus_index(VOLUME_BUSES[key])
	if bus < 0:
		push_warning("Settings: audio bus '%s' is missing" % VOLUME_BUSES[key])
		return
	var linear: float = get_volume(key)
	AudioServer.set_bus_mute(bus, linear <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))
