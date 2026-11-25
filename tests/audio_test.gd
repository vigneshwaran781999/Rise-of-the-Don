extends Node
## Audio test (per-feature test scene, M7 audio pass). Runs the real game scene and checks:
## the city's surface map (road, sidewalk, sand, sea, the pier's boards, grass, paddy), footsteps
## that sound like the ground (sand on the beach, a splash wading in the sea), and the ambience of
## each district (city hum, waves at the coast, machinery in the Industrial Zone, birds in the
## Countryside by day and crickets at night).
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/audio_test.tscn
## Prints "AUDIO TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")
## [what, world position, expected surface]
const SURFACE_SPOTS: Array = [
	["the east gopuram road", Vector3(66.0, 0.0, 0.0), &"road"],
	["its north sidewalk", Vector3(70.0, 0.0, -8.0), &"paved"],
	["the beach", Vector3(600.0, 0.0, 0.0), &"sand"],
	["the sea", Vector3(700.0, 0.0, 0.0), &"water"],
	["the pier", Vector3(640.0, 0.0, 60.0), &"wood"],
	["an Old Town park", Vector3(-130.0, 0.0, 130.0), &"grass"],
	["a paddy field", Vector3(-500.0, 0.0, 60.0), &"grass"],
	["a Countryside lake", Vector3(-690.0, 0.0, 56.0), &"water"],
]

var _catcher: ErrorCatcher
var _game: GameSession
var _ambience: AmbienceDirector
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
	_ambience = _game.get_node("Ambience") as AmbienceDirector
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	MissionManager.quit_mission()
	var steps: Array[Callable] = [_check_surfaces, _check_footsteps, _check_district_ambience, _check_night]
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
	print("AUDIO REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("AUDIO TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_surfaces() -> String:
	var city: CityData = _game.world.data
	var found: PackedStringArray = []
	for spot: Array in SURFACE_SPOTS:
		var surface: StringName = city.surface_at(spot[1])
		if surface != spot[2]:
			return "%s should be %s underfoot, the surface map says %s" % [spot[0], spot[2], surface]
		found.append("%s %s" % [spot[0], surface])
	for surface: StringName in CityData.SURFACES:
		if not AudioManager.has_stream(StringName("footstep_" + surface)):
			return "no footstep sound for %s" % surface
	_note("surface map: %s; a footstep sound for each" % ", ".join(found))
	return ""


## Walks the player forwards from `at` for a second and returns the surface of the last step.
func _walk_on(at: Vector3, yaw: float) -> StringName:
	_game.place_player(Transform3D(Basis(Vector3.UP, yaw), at))
	await _ticks(10)
	var audio := _game.player.get_node("Audio") as PlayerAudio
	audio.last_surface = &""
	_press(&"move_forward", true)
	await _ticks(70)
	_press(&"move_forward", false)
	await _ticks(20)
	return audio.last_surface


func _check_footsteps() -> String:
	var shore: float = CityLayout.COAST_X
	var on_sand: StringName = await _walk_on(Vector3(shore - 25.0, 0.3, -60.0), -PI * 0.5)
	var in_sea: StringName = await _walk_on(Vector3(shore + 12.0, 0.4, -60.0), -PI * 0.5)
	var on_road: StringName = await _walk_on(Vector3(66.0, 0.3, 1.5), PI * 0.5)
	if on_sand != &"sand":
		return "walking on the beach should sound like sand (got %s)" % on_sand
	if in_sea != &"water":
		return "wading in the sea should splash (got %s)" % in_sea
	if on_road != &"road":
		return "walking on the road should sound like the road (got %s)" % on_road
	_note("footsteps: %s on the beach, %s wading in the sea, %s on the road" % [on_sand, in_sea, on_road])
	return ""


## Puts the player at `at` (on foot) at noon or midnight and lets the ambience settle.
func _listen_at(at: Vector3, hour: float) -> void:
	GameState.set_hour(hour)
	(_game.get_node("DayNight") as DayNightCycle).refresh()
	_game.place_player(Transform3D(Basis.IDENTITY, at))
	await _ticks(60 * 5)


func _check_district_ambience() -> String:
	var started: int = Time.get_ticks_msec()
	while not AudioManager.has_stream(&"amb_city") and Time.get_ticks_msec() - started < 20000:
		await get_tree().process_frame
	if not AudioManager.has_stream(&"amb_city"):
		return "the ambience loops were never synthesised"
	await _listen_at(Vector3(70.0, 0.3, -8.0), 12.0)            # Old Town
	var old_town: float = AudioManager.get_ambience(&"amb_city")
	await _listen_at(Vector3(CityLayout.COAST_X - 10.0, 0.3, -60.0), 12.0)   # on the beach by the water
	var waves: float = AudioManager.get_ambience(&"amb_waves")
	await _listen_at(Vector3(452.0, 0.3, -500.0), 12.0)         # an Industrial Zone sidewalk
	var machines: float = AudioManager.get_ambience(&"amb_industrial")
	var city_there: float = AudioManager.get_ambience(&"amb_city")
	await _listen_at(Vector3(-500.0, 0.3, 60.0), 12.0)          # Countryside fields
	var birds: float = AudioManager.get_ambience(&"amb_birds")
	var hum: float = AudioManager.get_ambience(&"amb_city")
	if old_town < 0.4:
		return "Old Town should have the city's hum (%.2f)" % old_town
	if waves < 0.5:
		return "the beach by the water should have waves (%.2f)" % waves
	if machines < 0.5 or city_there > machines:
		return "the Industrial Zone should sound of machinery more than traffic (machines %.2f, city %.2f)" % [machines, city_there]
	if birds < 0.4 or hum > 0.05:
		return "the Countryside should have birdsong and no city hum (birds %.2f, hum %.2f)" % [birds, hum]
	_note("ambience by day: Old Town city hum %.2f; beach waves %.2f; Industrial machinery %.2f (traffic %.2f); Countryside birds %.2f (city %.2f)" % [
		old_town, waves, machines, city_there, birds, hum])
	return ""


func _check_night() -> String:
	await _listen_at(Vector3(-500.0, 0.3, 64.0), 23.0)
	var birds: float = AudioManager.get_ambience(&"amb_birds")
	var crickets: float = AudioManager.get_ambience(&"amb_crickets")
	if crickets < 0.4 or birds > 0.1:
		return "at night the Countryside's birds should give way to crickets (birds %.2f, crickets %.2f)" % [birds, crickets]
	_note("Countryside at 23:00: crickets %.2f, birds %.2f" % [crickets, birds])
	return ""


func _press(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
