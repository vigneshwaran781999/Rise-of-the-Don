class_name PlaceDirector
extends Node3D
## Shops and properties in the district (GDD §9), each at its place (DistrictData.places, the spot
## at its door):
## - a ring on the ground at each open shop's door (in the garage, across its bay) and at
##   properties; a FOR SALE board at a property on sale; map blips for all of them;
## - the interact prompt when the player can use one (on foot at a door, or in a car stopped in
##   the garage bay), unless a mission has the key; it opens the ShopMenu;
## - food heals; clothes are bought once (EconomyManager) and worn (GameState); the garage
##   resprays, repairs and re-tyres the car and drops a wanted level up to
##   WantedTuning.respray_max_level, if no police unit can see you; a property can be bought;
## - an owned property is a save point (the pause menu's save slots) and pays its daily income
##   when a new in-game day begins.

signal prompt_changed(action: String, text: String)
## Something to tell the player (a purchase, the rent coming in).
signal message(text: String)

const DOOR_REACH: float = 2.2
## The garage's bay: this far in from its door spot, this wide around its middle.
const BAY_DEPTH: float = 6.6
const BAY_REACH: float = 3.0
const STOP_KMH: float = 3.0
const SHOP_COLOUR := Color(0.22, 0.82, 0.48)
const PROPERTY_COLOUR := Color(1.0, 0.6, 0.18)
const OWNED_COLOUR := Color(1.0, 0.82, 0.3)
const LETTERS: Dictionary = {ShopData.Kind.FOOD: "F", ShopData.Kind.CLOTHES: "C", ShopData.Kind.RESPRAY: "G"}
const PROMPTS: Dictionary = {ShopData.Kind.FOOD: "BUY FOOD", ShopData.Kind.CLOTHES: "BUY CLOTHES", ShopData.Kind.RESPRAY: "RESPRAY"}

@export var shops: Array[ShopData] = []
@export var properties: Array[PropertyData] = []
## Paint a respray picks from (never the car's current colour).
@export var respray_colours: PackedColorArray = PackedColorArray([
	Color("1f4e8c"), Color("2f7d4f"), Color("e8e4da"), Color("1d1d22"), Color("c9a227"), Color("7b1f2c"), Color("5a6470"),
])

## Set by the game session.
var menu: ShopMenu
var pause_menu: PauseMenu

var _player: PlayerController
var _district: DistrictData
var _missions: MissionDirector
var _police: PoliceManager
var _rings: Dictionary = {}          # ShopData / PropertyData -> MeshInstance3D
var _boards: Dictionary = {}         # PropertyData -> Node3D
var _here: Resource                  # what the prompt is for (ShopData / PropertyData), or null
var _open: Resource                  # whose menu is open
var _prompt: Array = ["", ""]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GpsNavigator.BLIP_GROUP)
	_rng.seed = 2207


func setup(player: PlayerController, district: DistrictData, missions: MissionDirector, police: PoliceManager) -> void:
	_player = player
	_district = district
	_missions = missions
	_police = police
	for shop: ShopData in shops:
		var radius: float = BAY_REACH if shop.kind == ShopData.Kind.RESPRAY else 1.1
		_rings[shop] = _make_ring(_spot(shop), radius, SHOP_COLOUR)
	for property: PropertyData in properties:
		_rings[property] = _make_ring(get_place(property.place).origin, 1.1, PROPERTY_COLOUR)
		_boards[property] = _make_sale_board(property)
	menu.chosen.connect(_on_chosen)
	menu.closed.connect(func() -> void: _open = null)
	MissionManager.availability_changed.connect(_refresh_markers)
	EconomyManager.owned_changed.connect(func(_id: StringName) -> void: _refresh_markers())
	GameState.day_changed.connect(_pay_income)
	_refresh_markers()


func get_place(place_id: StringName) -> Transform3D:
	return _district.places.get(place_id, Transform3D())


## Where a shop is used: at its door, or for the garage in the middle of its bay.
func get_spot(shop: ShopData) -> Vector3:
	return _spot(shop)


func get_shop(shop_id: StringName) -> ShopData:
	for shop: ShopData in shops:
		if shop.id == shop_id:
			return shop
	return null


func get_property(property_id: StringName) -> PropertyData:
	for property: PropertyData in properties:
		if property.id == property_id:
			return property
	return null


func get_prompt() -> Array:
	return _prompt


func has_sale_board(property: PropertyData) -> bool:
	return (_boards[property] as Node3D).visible


## Uses whatever the prompt is offering (the interact key does this).
func interact() -> void:
	if _here == null:
		return
	if _here is ShopData:
		_open_shop(_here as ShopData)
	elif _here is PropertyData:
		var property := _here as PropertyData
		if EconomyManager.owns(property.id):
			if pause_menu != null:
				pause_menu.open_save()
		else:
			_open = property
			menu.open(property.title, property.description, _property_rows(property))


func get_map_blips() -> Array[Dictionary]:
	var blips: Array[Dictionary] = []
	for shop: ShopData in shops:
		if shop.is_open():
			blips.append({"position": _spot(shop), "kind": &"shop", "letter": LETTERS[shop.kind], "label": shop.title})
	for property: PropertyData in properties:
		var owned: bool = EconomyManager.owns(property.id)
		if owned or property.is_on_sale():
			blips.append({"position": get_place(property.place).origin, "kind": &"property",
				"letter": "H" if owned else "₹", "colour": OWNED_COLOUR if owned else PROPERTY_COLOUR, "label": property.title})
	return blips


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _here != null and not get_tree().paused:
		interact()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _player == null or get_tree().paused:
		return
	var found: Resource = null
	var text: String = ""
	if not _missions.has_prompt():
		if _player.is_in_vehicle():
			var car: VehicleController = _player.vehicle
			for shop: ShopData in shops:
				if shop.kind == ShopData.Kind.RESPRAY and shop.is_open() and car != null \
						and _flat(car.global_position).distance_to(_flat(_spot(shop))) < BAY_REACH \
						and absf(car.get_speed_kmh()) < STOP_KMH:
					found = shop
					text = PROMPTS[shop.kind]
		else:
			var here: Vector2 = _flat(_player.global_position)
			for shop: ShopData in shops:
				if shop.kind != ShopData.Kind.RESPRAY and shop.is_open() and here.distance_to(_flat(_spot(shop))) < DOOR_REACH:
					found = shop
					text = PROMPTS[shop.kind]
			for property: PropertyData in properties:
				if here.distance_to(_flat(get_place(property.place).origin)) >= DOOR_REACH:
					continue
				if EconomyManager.owns(property.id):
					found = property
					text = "SAVE GAME"
				elif property.is_on_sale():
					found = property
					text = "BUY %s  %s" % [property.title.to_upper(), EconomyManager.format(property.price)]
	_here = found
	_set_prompt("interact" if found != null else "", text)


# --------------------------------------------------------------------------- shops

func _open_shop(shop: ShopData) -> void:
	_open = shop
	menu.open(shop.title, shop.greeting, _shop_rows(shop))


func _shop_rows(shop: ShopData) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	match shop.kind:
		ShopData.Kind.FOOD:
			var full: bool = _player.stats.health >= _player.stats.get_max_health()
			for item: ShopItem in shop.items:
				rows.append({"id": item.id, "text": item.title, "note": EconomyManager.format(item.price),
					"detail": item.description, "dim": full or not EconomyManager.can_afford(item.price)})
		ShopData.Kind.CLOTHES:
			for item: ShopItem in shop.items:
				var outfit := item as Outfit
				var owned: bool = _owns_outfit(outfit)
				var wearing: bool = _wearing(shop, outfit)
				var note: String = "WEARING" if wearing else ("OWNED" if owned else EconomyManager.format(outfit.price))
				rows.append({"id": outfit.id, "text": outfit.title, "note": note, "detail": outfit.description,
					"dim": wearing or (not owned and not EconomyManager.can_afford(outfit.price))})
		ShopData.Kind.RESPRAY:
			var tuning: WantedTuning = WantedSystem.tuning
			rows.append({"id": &"respray", "text": "Respray, repair and new tyres", "note": EconomyManager.format(tuning.respray_fee),
				"detail": "New paint, the body fixed and fresh tyres. Loses up to %d stars, if the police can't see you." % tuning.respray_max_level,
				"dim": not EconomyManager.can_afford(tuning.respray_fee)})
	return rows


func _on_chosen(choice_id: StringName) -> void:
	if _open is PropertyData:
		_buy_property(_open as PropertyData)
		return
	var shop := _open as ShopData
	if shop == null:
		return
	match shop.kind:
		ShopData.Kind.FOOD:
			_eat(shop.get_item(choice_id) as FoodItem)
		ShopData.Kind.CLOTHES:
			_dress(shop, shop.get_item(choice_id) as Outfit)
		ShopData.Kind.RESPRAY:
			_respray()
			return
	if _open == shop:
		menu.set_rows(_shop_rows(shop))


func _eat(food: FoodItem) -> void:
	if food == null:
		return
	if _player.stats.health >= _player.stats.get_max_health():
		menu.set_message("You're not hungry.")
	elif not EconomyManager.try_spend(food.price, &"food"):
		menu.set_message("You can't afford that.")
	else:
		var gained: float = _player.stats.heal(food.health)
		AudioManager.play_sfx(&"cash")
		menu.set_message("%s: +%d health." % [food.title, roundi(gained)])


func _dress(shop: ShopData, outfit: Outfit) -> void:
	if outfit == null:
		return
	if _wearing(shop, outfit):
		menu.set_message("You're wearing it.")
	elif _owns_outfit(outfit):
		GameState.set_outfit(outfit.id)
		menu.set_message("You change into the %s." % outfit.title.to_lower())
	elif EconomyManager.buy(_outfit_key(outfit), outfit.price, &"clothes"):
		GameState.set_outfit(outfit.id)
		AudioManager.play_sfx(&"cash")
		menu.set_message("Bought the %s. Looking sharp." % outfit.title.to_lower())
	else:
		menu.set_message("You can't afford that.")


func _owns_outfit(outfit: Outfit) -> bool:
	return outfit.price <= 0 or EconomyManager.owns(_outfit_key(outfit))


func _wearing(shop: ShopData, outfit: Outfit) -> bool:
	return GameState.outfit == outfit.id or (GameState.outfit == &"" and shop.items.find(outfit) == 0)


static func _outfit_key(outfit: Outfit) -> StringName:
	return StringName("outfit_" + String(outfit.id))


func _respray() -> void:
	var car: VehicleController = _player.vehicle
	var tuning: WantedTuning = WantedSystem.tuning
	if car == null:
		menu.close()
		return
	if WantedSystem.level > tuning.respray_max_level:
		menu.set_message("Not with %d stars on you. Lose a few first." % WantedSystem.level)
	elif WantedSystem.is_wanted() and _police.seen:
		menu.set_message("Not with the police watching. Lose them first.")
	elif not EconomyManager.try_spend(tuning.respray_fee, &"respray"):
		menu.set_message("You can't afford that.")
	else:
		var wanted: bool = WantedSystem.is_wanted()
		var model := car.get_node("Model") as VehicleModel
		var colours: Array[Color] = []
		for colour: Color in respray_colours:
			if not colour.is_equal_approx(model.get_paint()):
				colours.append(colour)
		var paint: Color = colours[_rng.randi() % colours.size()]
		var work := func() -> void:
			model.set_paint(paint)
			(car.get_node("Damage") as VehicleDamage).repair()
			car.repair_tyres()
			WantedSystem.respray()
		menu.close()
		await menu.blackout(work)
		AudioManager.play_sfx(&"cash")
		message.emit("Fresh paint, new tyres. Nobody's looking for this car." if wanted else "Fresh paint and new tyres.")


# --------------------------------------------------------------------------- properties

func _property_rows(property: PropertyData) -> Array[Dictionary]:
	return [{"id": &"buy", "text": "Buy the %s" % property.title.to_lower(), "note": EconomyManager.format(property.price),
		"detail": "A save point, and %s a day in rent." % EconomyManager.format(property.daily_income),
		"dim": not EconomyManager.can_afford(property.price)}]


func _buy_property(property: PropertyData) -> void:
	if not EconomyManager.buy(property.id, property.price, &"property"):
		menu.set_message("You need %s." % EconomyManager.format(property.price))
		return
	AudioManager.play_ui(&"mission_passed")
	menu.close()
	message.emit("The %s is yours. Save the game here; the rent comes in every day." % property.title.to_lower())


func _pay_income(_day: int) -> void:
	for property: PropertyData in properties:
		if EconomyManager.owns(property.id) and property.daily_income > 0:
			EconomyManager.add(property.daily_income, &"rent")
			message.emit("Rent from the %s: +%s" % [property.title.to_lower(), EconomyManager.format(property.daily_income)])


# --------------------------------------------------------------------------- markers

func _refresh_markers() -> void:
	for shop: ShopData in shops:
		(_rings[shop] as Node3D).visible = shop.is_open()
	for property: PropertyData in properties:
		var owned: bool = EconomyManager.owns(property.id)
		(_rings[property] as Node3D).visible = owned or property.is_on_sale()
		(_boards[property] as Node3D).visible = not owned and property.is_on_sale()
		var ring := _rings[property] as MeshInstance3D
		(ring.material_override as StandardMaterial3D).albedo_color = Color(OWNED_COLOUR if owned else PROPERTY_COLOUR, 0.55)


func _spot(shop: ShopData) -> Vector3:
	var place: Transform3D = get_place(shop.place)
	if shop.kind == ShopData.Kind.RESPRAY:
		return place.origin + place.basis.z * BAY_DEPTH     # the place faces out: +Z points inside
	return place.origin


func _make_ring(at: Vector3, radius: float, colour: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.12
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 6
	ring.mesh = torus
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.albedo_color = Color(colour, 0.55)
	ring.material_override = glow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.25, 1.0)
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.06
	return ring


## A FOR SALE board on a post beside the door, facing the street.
func _make_sale_board(property: PropertyData) -> Node3D:
	var place: Transform3D = get_place(property.place)
	var board := Node3D.new()
	board.name = "SaleBoard_" + String(property.id)
	add_child(board)
	var outward: Basis = place.basis * Basis(Vector3.UP, PI)     # +Z towards the street
	board.global_transform = Transform3D(outward, place.origin + place.basis.x * 1.8)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("5a3a22")
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.08, 1.6, 0.08)
	post.mesh = post_mesh
	post.material_override = wood
	post.position = Vector3(0.0, 0.8, 0.0)
	board.add_child(post)
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.1, 0.6, 0.04)
	panel.mesh = panel_mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("f2c230")
	panel.material_override = paint
	panel.position = Vector3(0.0, 1.45, 0.0)
	board.add_child(panel)
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = "FOR SALE\n%s" % EconomyManager.format(property.price)
		label.font = UIStyle.get_font()
		label.font_size = 56
		label.pixel_size = 0.004
		label.modulate = Color("1b1b1f")
		label.outline_size = 0
		label.shaded = true
		label.position = Vector3(0.0, 1.45, 0.025 * side)
		label.rotation.y = 0.0 if side > 0.0 else PI
		board.add_child(label)
	return board


func _set_prompt(action: String, text: String) -> void:
	if action == _prompt[0] and text == _prompt[1]:
		return
	_prompt = [action, text]
	prompt_changed.emit(action, text)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
