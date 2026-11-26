extends Node
## Day / night test (per-feature test scene, M6). Runs the real game scene and checks the clock
## (rate, midnight, HUD), the looks it blends between (sun, sky, fog), the city lights coming on
## at dusk and off at dawn (the city_lights shader global, the pool of real streetlights near the
## camera, traffic headlights) and that a new day is announced.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/day_night_test.tscn
## Prints "DAY NIGHT TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")

var _catcher: ErrorCatcher
var _game: GameSession
var _cycle: DayNightCycle
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
	_cycle = _game.get_node("DayNight") as DayNightCycle
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	var steps: Array[Callable] = [_check_clock, _check_blend, _check_city_lights, _check_dusk_and_dawn, _check_new_day]
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
	print("DAY NIGHT REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("DAY NIGHT TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_clock() -> String:
	var settings: DayNightSettings = GameState.DAY_NIGHT
	if absf(GameState.hour - settings.start_hour) > 0.05 or GameState.day != 1:
		return "New Game should start on day 1 at %.2f h (clock %.2f, day %d)" % [settings.start_hour, GameState.hour, GameState.day]
	var before: float = GameState.hour
	await _ticks(600)    # 10 s of play
	var expected: float = 10.0 * 24.0 / (settings.day_length_minutes * 60.0)
	var advanced: float = GameState.hour - before
	if absf(advanced - expected) > expected * 0.1:
		return "10 s of play moved the clock %.3f h, expected %.3f h (a %.0f-minute day)" % [advanced, expected, settings.day_length_minutes]
	var hud := _game.get_node("HUD") as Hud
	await _frames(2)
	if hud.get_clock_shown() != GameState.get_clock_text():
		return "HUD clock '%s', game clock '%s'" % [hud.get_clock_shown(), GameState.get_clock_text()]
	_note("New Game: day 1, %s; 10 s of play = %.0f game minutes (%.0f-minute day); HUD clock matches" % [
		GameState.get_clock_text(), advanced * 60.0, settings.day_length_minutes])
	return ""


func _check_blend() -> String:
	var settings: DayNightSettings = GameState.DAY_NIGHT
	var afternoon: LightingPreset = settings.preset_at(16.5)
	var dusk: LightingPreset = settings.preset_at(18.6)
	var between: LightingPreset = settings.preset_at(17.55)
	if absf(between.sun_elevation_degrees - (afternoon.sun_elevation_degrees + dusk.sun_elevation_degrees) * 0.5) > 0.5:
		return "half-way between afternoon and dusk the sun should be half-way down (%.1f vs %.1f / %.1f)" % [
			between.sun_elevation_degrees, afternoon.sun_elevation_degrees, dusk.sun_elevation_degrees]
	var midnight: LightingPreset = settings.preset_at(0.0)
	var noon: LightingPreset = settings.preset_at(13.0)
	if midnight.sun_energy >= noon.sun_energy * 0.5 or midnight.sky_top_color.v >= noon.sky_top_color.v * 0.5:
		return "midnight should be much darker than noon (light %.2f vs %.2f)" % [midnight.sun_energy, noon.sun_energy]
	GameState.set_hour(13.0)
	_cycle.refresh()
	var lighting := _game.get_node("World/Lighting") as WorldLighting
	if absf(lighting.sun.light_energy - noon.sun_energy) > 0.01:
		return "at 13:00 the sun's energy is %.2f, the noon look has %.2f" % [lighting.sun.light_energy, noon.sun_energy]
	_note("looks blend through the day (17:33 is half-way from afternoon to dusk); midnight light %.2f, noon %.2f; the sun follows the clock" % [
		midnight.sun_energy, noon.sun_energy])
	return ""


func _check_city_lights() -> String:
	var settings: DayNightSettings = GameState.DAY_NIGHT
	for pair: Array in [[12.0, 0.0], [18.0, 0.0], [18.5, 0.5], [19.0, 1.0], [2.0, 1.0], [6.75, 0.5], [7.5, 0.0]]:
		var got: float = settings.city_lights_at(pair[0])
		if absf(got - float(pair[1])) > 0.01:
			return "city lights at %.2f h are %.2f, expected %.2f" % [pair[0], got, pair[1]]
	_note("city lights: off by day, fading on 18:15-18:45, off again 06:30-07:00")
	return ""


func _check_dusk_and_dawn() -> String:
	var traffic := _game.get_node("Traffic") as TrafficManager
	# Let some traffic appear by day first.
	var frames: int = 0
	while traffic.get_count() < 3 and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
	GameState.set_hour(13.0)
	_cycle.refresh()
	await _ticks(2)
	if _cycle.is_dark() or _cycle.street_lights.get_lit_count() != 0 or traffic.headlights_on:
		return "by day: dark %s, %d streetlights lit, traffic headlights %s" % [_cycle.is_dark(), _cycle.street_lights.get_lit_count(), traffic.headlights_on]
	GameState.set_hour(21.0)
	_cycle.refresh()
	await _ticks(2)
	var lamps: int = _cycle.street_lights.get_lamp_count()
	var lit: int = _cycle.street_lights.get_lit_count()
	if not _cycle.is_dark() or lamps < 20 or lit != mini(_cycle.street_lights.get_active_count(), lamps):
		return "at night: dark %s, %d lamps known, %d real lights lit" % [_cycle.is_dark(), lamps, lit]
	if not traffic.headlights_on:
		return "traffic headlights should come on at night"
	for car: VehicleController in traffic.get_cars():
		if not car.are_headlights_on():
			return "%s drives without headlights at night" % car.name
		if (car.get_node("Lights") as VehicleLights).are_beams_visible():
			return "%s has real headlight beams (traffic should only light its lenses)" % car.name
	var camera: Camera3D = get_viewport().get_camera_3d()
	var nearest_lit: float = INF
	for i: int in _cycle.street_lights.get_child_count():
		var light := _cycle.street_lights.get_child(i) as Light3D
		if light.visible:
			nearest_lit = minf(nearest_lit, light.global_position.distance_to(camera.global_position))
	if nearest_lit > 60.0:
		return "the nearest real streetlight is %.0f m from the camera" % nearest_lit
	var cars: int = traffic.get_count()
	GameState.set_hour(7.5)
	_cycle.refresh()
	await _ticks(2)
	if _cycle.is_dark() or _cycle.street_lights.get_lit_count() != 0 or traffic.headlights_on:
		return "after dawn the lights should be off again"
	_note("at 21:00: dark, %d of %d known streetlights cast real light (nearest %.0f m from the camera), %d traffic cars with headlights (lenses only); all off again at 07:30" % [
		lit, lamps, nearest_lit, cars])
	return ""


func _check_new_day() -> String:
	var days: Array[int] = []
	var on_day := func(day: int) -> void: days.append(day)
	GameState.day_changed.connect(on_day)
	var day_before: int = GameState.day
	GameState.set_hour(23.9)
	GameState.advance_hours(0.2)
	GameState.day_changed.disconnect(on_day)
	if GameState.day != day_before + 1 or days != [day_before + 1] or absf(GameState.hour - 0.1) > 0.001:
		return "passing midnight: day %d (signals %s), clock %.2f" % [GameState.day, days, GameState.hour]
	_note("passing midnight starts day %d (announced once)" % GameState.day)
	return ""


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
