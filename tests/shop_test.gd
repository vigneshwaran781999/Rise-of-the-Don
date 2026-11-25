extends Node
## Shops and property test (per-feature test scene, M6). Runs the real game scene (traffic and
## pedestrians off) and uses the shops and the house like a player would, through the prompts
## and the shop menu:
## - the places are in the district and on the map (food, clothes, garage, house for sale);
## - the tiffin stall: food restores health and costs cash; nothing sold to someone not hungry;
## - the clothes shop: buy an outfit (worn at once, the player's figure changes colour), change
##   back for free, refused when you can't afford it;
## - the garage: drive in hurt, wanted and on burst tyres; respray: new paint, repaired, new
##   tyres, no stars, the fee paid. Refused with too many stars, no charge;
## - the house: refused without the cash; bought; then a save point (the save slots open) that
##   pays rent each new day;
## - outfit and what you own survive a save and load.
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/shop_test.tscn
## Prints "SHOP TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const GAME: PackedScene = preload("res://scenes/main/game.tscn")

var _catcher: ErrorCatcher
var _game: GameSession
var _places: PlaceDirector
var _menu: ShopMenu
var _hud: Hud
var _player: PlayerController
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
	_places = _game.places
	_menu = _game.shop_menu
	_hud = _game.hud
	_player = _game.player
	(_game.get_node("Traffic") as TrafficManager).enabled = false
	(_game.get_node("Traffic") as TrafficManager).clear()
	(_game.get_node("Pedestrians") as PedestrianManager).enabled = false
	(_game.get_node("Pedestrians") as PedestrianManager).clear()
	(_game.get_node("Police") as PoliceManager).enabled = false
	# Mission 1 runs from the start; quit it so its prompts and dialogue stay out of the way.
	MissionManager.quit_mission()
	# The clothes shop opens with mission 3 and the house goes on sale after mission 4.
	MissionManager.from_save({"completed": ["welcome", "first_opportunity", "new_connection", "city_chase"]})
	await _ticks(30)
	var steps: Array[Callable] = [
		_check_places, _check_food, _check_clothes, _check_respray, _check_property, _check_save_round_trip,
	]
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
	if _menu.is_open():
		_menu.close()
	WantedSystem.clear()
	get_tree().paused = false
	print("SHOP REPORT")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("SHOP TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_places() -> String:
	var data: CityData = _game.world.data
	for place_id: StringName in [&"tiffin", &"textiles", &"garage", &"house", &"police_station"]:
		if not data.places.has(place_id):
			return "the district has no place '%s'" % place_id
	var letters: Array[String] = []
	for blip: Dictionary in _places.get_map_blips():
		letters.append(str(blip.get("letter", "")))
	letters.sort()
	if letters != ["C", "F", "G", "₹"]:
		return "map blips should be food F, clothes C, garage G and a house for sale ₹ (got %s)" % [letters]
	_note("places: tiffin stall, clothes shop, garage, house for sale, police station; map blips %s" % [letters])
	return ""


func _check_food() -> String:
	var tiffin: ShopData = _places.get_shop(&"tiffin")
	await _walk_to(_places.get_spot(tiffin))
	if _hud.get_prompt_text() != "E  BUY FOOD":
		return "at the tiffin stall the prompt should be 'E  BUY FOOD' (got '%s')" % _hud.get_prompt_text()
	EconomyManager.set_cash(1000)
	_player.stats.set_health(40.0)
	await _interact()
	if not _menu.is_open() or not get_tree().paused:
		return "E should open the stall's menu and pause"
	if _menu.get_row_ids() != [&"coffee", &"idli", &"meals"] or _menu.get_note(&"idli") != "₹50":
		return "menu rows %s, idli %s" % [_menu.get_row_ids(), _menu.get_note(&"idli")]
	var before: float = _player.stats.health     # (a little regenerated since; the menu pauses it now)
	_menu.choose(&"idli")
	if absf(_player.stats.health - before - 35.0) > 0.01 or EconomyManager.cash != 950:
		return "idli and vada should give +35 health for ₹50 (health %.1f -> %.1f, cash %d)" % [before, _player.stats.health, EconomyManager.cash]
	_menu.choose(&"meals")
	if absf(_player.stats.health - _player.stats.get_max_health()) > 0.01 or EconomyManager.cash != 830:
		return "full meals should restore all health for ₹120 (health %.0f, cash %d)" % [_player.stats.health, EconomyManager.cash]
	_menu.choose(&"coffee")
	if EconomyManager.cash != 830 or not _menu.get_message().contains("not hungry"):
		return "nothing should be sold to a full player (cash %d, '%s')" % [EconomyManager.cash, _menu.get_message()]
	_menu.close()
	await _frames(2)
	if get_tree().paused:
		return "leaving the shop should unpause"
	_note("tiffin stall: 'E  BUY FOOD', idli +35 health for ₹50, meals to full for ₹120, no sale when full")
	return ""


func _check_clothes() -> String:
	var textiles: ShopData = _places.get_shop(&"textiles")
	var figure := _player.get_node("Model/Figure") as PlayerFigure
	await _walk_to(_places.get_spot(textiles))
	if _hud.get_prompt_text() != "E  BUY CLOTHES":
		return "at the clothes shop the prompt should be 'E  BUY CLOTHES' (got '%s')" % _hud.get_prompt_text()
	EconomyManager.set_cash(1000)
	await _interact()
	if not _menu.is_open() or _menu.get_note(&"arrival") != "WEARING" or _menu.get_note(&"veshti") != "₹600":
		return "the shop should show the travelling clothes as WEARING and the veshti at ₹600 (%s, %s)" % [_menu.get_note(&"arrival"), _menu.get_note(&"veshti")]
	_menu.choose(&"veshti")
	var veshti := textiles.get_item(&"veshti") as Outfit
	if GameState.outfit != &"veshti" or EconomyManager.cash != 400 or figure.get_outfit() != veshti:
		return "buying the veshti should wear it at once for ₹600 (outfit %s, cash %d)" % [GameState.outfit, EconomyManager.cash]
	if _menu.get_note(&"veshti") != "WEARING" or _menu.get_note(&"arrival") != "OWNED":
		return "after buying: veshti %s, travelling clothes %s" % [_menu.get_note(&"veshti"), _menu.get_note(&"arrival")]
	_menu.choose(&"arrival")
	if GameState.outfit != &"arrival" or EconomyManager.cash != 400:
		return "changing back to owned clothes should be free"
	_menu.choose(&"veshti")
	if GameState.outfit != &"veshti" or EconomyManager.cash != 400:
		return "an outfit once bought should be free to wear again (cash %d)" % EconomyManager.cash
	_menu.choose(&"sandal")
	if GameState.outfit != &"veshti" or EconomyManager.cash != 400 or not _menu.get_message().contains("afford"):
		return "the ₹3,500 shirt should be refused with ₹400"
	_menu.close()
	await _frames(2)
	_note("clothes shop: veshti bought for ₹600 and worn (figure recoloured), free to change back and forth, ₹3,500 shirt refused with ₹400")
	return ""


func _check_respray() -> String:
	var garage: ShopData = _places.get_shop(&"garage")
	var spot: Vector3 = _places.get_spot(garage)
	var place: Transform3D = _places.get_place(garage.place)
	var car := _game.get_node("World/Vehicles/Sedan") as VehicleController
	# Drive in: the car stands in the bay facing in, hurt and on burst tyres.
	_game.world.streamer.load_around_now(spot)
	car.teleport(Transform3D(Basis.looking_at(-place.basis.z, Vector3.UP), spot + Vector3.UP * 0.6))
	await _ticks(20)
	_player.global_position = car.get_exit_points()[0] + Vector3.UP * 0.2
	_player.reset_physics_interpolation()
	await _ticks(5)
	_player.enter_vehicle(car, car.get_exit_points()[0])
	for i: int in 90:
		await get_tree().physics_frame
		if _player.is_in_vehicle():
			break
	if not _player.is_in_vehicle():
		return "couldn't get into the car"
	car.set_controls(0.0, 1.0, 0.0, true)
	await _ticks(60)
	(car.get_node("Damage") as VehicleDamage).apply_damage(car.stats.max_health * 0.6)
	car.burst_tyres()
	var paint: Color = (car.get_node("Model") as VehicleModel).get_paint()
	EconomyManager.set_cash(2000)
	# Too hot: four stars are refused, nothing charged.
	WantedSystem.set_level(4, car.global_position)
	await _ticks(5)
	if _hud.get_prompt_text() != "E  RESPRAY":
		return "stopped in the garage bay the prompt should be 'E  RESPRAY' (got '%s', car %.1f m from the bay)" % [
			_hud.get_prompt_text(), Vector2(car.global_position.x - spot.x, car.global_position.z - spot.z).length()]
	await _interact()
	_menu.choose(&"respray")
	if EconomyManager.cash != 2000 or WantedSystem.level != 4 or not _menu.get_message().contains("stars"):
		return "a respray with 4 stars should be refused without charge ('%s')" % _menu.get_message()
	_menu.close()
	# Two stars, out of sight: done.
	WantedSystem.set_level(2, car.global_position)
	await _ticks(5)
	await _interact()
	_menu.choose(&"respray")
	for i: int in 240:
		await get_tree().process_frame
		if not get_tree().paused and not _menu.is_open() and WantedSystem.level == 0:
			break
	await _frames(5)
	var damage := car.get_node("Damage") as VehicleDamage
	var new_paint: Color = (car.get_node("Model") as VehicleModel).get_paint()
	if WantedSystem.level != 0 or EconomyManager.cash != 1500:
		return "the respray should clear 2 stars for ₹500 (level %d, cash %d)" % [WantedSystem.level, EconomyManager.cash]
	if new_paint.is_equal_approx(paint) or damage.get_health_fraction() < 0.999 or car.are_tyres_burst():
		return "the car should come out repainted, repaired and on new tyres (paint changed %s, health %.2f, burst %s)" % [
			not new_paint.is_equal_approx(paint), damage.get_health_fraction(), car.are_tyres_burst()]
	if get_tree().paused:
		return "the game should run again after the respray"
	_player.exit_vehicle(car.get_exit_points()[0])
	await _ticks(60)
	_note("garage: 'E  RESPRAY' in the bay; refused at 4 stars (no charge); at 2 stars ₹500: new paint, full health, new tyres, no stars")
	return ""


func _check_property() -> String:
	var house: PropertyData = _places.get_property(&"verandah_house")
	var door: Vector3 = _places.get_place(house.place).origin
	if not _places.has_sale_board(house):
		return "the house should have a FOR SALE board"
	await _walk_to(door)
	if _hud.get_prompt_text() != "E  BUY VERANDAH HOUSE  ₹6,000":
		return "at the house the prompt should offer it for ₹6,000 (got '%s')" % _hud.get_prompt_text()
	EconomyManager.set_cash(3000)
	await _interact()
	_menu.choose(&"buy")
	if EconomyManager.owns(house.id) or EconomyManager.cash != 3000:
		return "the house shouldn't be sold for ₹3,000"
	_menu.close()
	await _frames(2)
	EconomyManager.set_cash(10000)
	await _interact()
	_menu.choose(&"buy")
	await _frames(3)
	if not EconomyManager.owns(house.id) or EconomyManager.cash != 4000 or _menu.is_open():
		return "buying the house should take ₹6,000 and close the menu (owned %s, cash %d)" % [EconomyManager.owns(house.id), EconomyManager.cash]
	if _places.has_sale_board(house):
		return "the FOR SALE board should go once it's yours"
	var owned_blip: bool = false
	for blip: Dictionary in _places.get_map_blips():
		owned_blip = owned_blip or (blip["kind"] == &"property" and blip.get("letter") == "H")
	if not owned_blip:
		return "the map should mark the house as yours (H)"
	await _ticks(5)
	if _hud.get_prompt_text() != "E  SAVE GAME":
		return "at your own house the prompt should be 'E  SAVE GAME' (got '%s')" % _hud.get_prompt_text()
	await _interact()
	if not _game.pause_menu.is_saving():
		return "E at your house should open the save slots"
	await _press(&"ui_cancel")
	if _game.pause_menu.is_saving() or get_tree().paused:
		return "backing out of the save slots should go straight back to the game"
	# Rent: a new day pays.
	var cash: int = EconomyManager.cash
	GameState.set_hour(23.9)
	GameState.advance_hours(0.2)
	if EconomyManager.cash != cash + house.daily_income:
		return "a new day should pay %s rent (cash %d -> %d)" % [EconomyManager.format(house.daily_income), cash, EconomyManager.cash]
	_note("house: refused with ₹3,000; bought for ₹6,000 (board gone, map shows H); then 'E  SAVE GAME' opens the save slots; a new day pays %s rent" % EconomyManager.format(house.daily_income))
	return ""


func _check_save_round_trip() -> String:
	var economy: Dictionary = JSON.parse_string(JSON.stringify(EconomyManager.to_save()))
	var state: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_save()))
	EconomyManager.start_new_game(200)
	GameState.start_new_game()
	var figure := _player.get_node("Model/Figure") as PlayerFigure
	if EconomyManager.owns(&"verandah_house") or GameState.outfit != &"" or figure.get_outfit().id != &"arrival":
		return "a new game should own nothing and wear the travelling clothes"
	EconomyManager.from_save(economy)
	GameState.from_save(state)
	if not EconomyManager.owns(&"verandah_house") or not EconomyManager.owns(&"outfit_veshti"):
		return "loading should bring back the house and the veshti (owned %s)" % [EconomyManager.get_owned()]
	if GameState.outfit != &"veshti" or figure.get_outfit().id != &"veshti":
		return "loading should put the veshti back on"
	_note("save and load keep the house, the bought outfit and the one being worn")
	return ""


## Puts the player on foot at `pos` and lets the prompts catch up.
func _walk_to(pos: Vector3) -> void:
	_game.world.streamer.load_around_now(pos)
	_player.global_position = pos + Vector3.UP * 0.1
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _ticks(20)


## Presses the interact key.
func _interact() -> void:
	await _press("interact")


## Presses and releases an input action as real input events.
func _press(action: StringName) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _note(line: String) -> void:
	_report.append(line)
	print("  .. " + line)
