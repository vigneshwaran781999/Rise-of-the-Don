extends Node
## The player's cash and what they own (GDD §9): the balance and transactions, announced
## through cash_changed, and things bought for keeps (properties, outfits), announced through
## owned_changed. Mission rewards are paid here when MissionManager reports a mission passed.
## Autoload: EconomyManager.

signal cash_changed(cash: int, delta: int, reason: StringName)
## Something was bought for keeps (or, loading a save, the whole list changed: id is &"").
signal owned_changed(item_id: StringName)

var cash: int = 0
var _owned: Dictionary = {}     # StringName -> true


func _ready() -> void:
	MissionManager.mission_passed.connect(_on_mission_passed)


## New game: the starting purse, nothing owned.
func start_new_game(starting_cash: int) -> void:
	_owned.clear()
	owned_changed.emit(&"")
	set_cash(starting_cash)


func add(amount: int, reason: StringName) -> void:
	if amount == 0:
		return
	cash += amount
	cash_changed.emit(cash, amount, reason)


func can_afford(amount: int) -> bool:
	return cash >= amount


## Takes `amount` if the player has it; false (and nothing taken) otherwise.
func try_spend(amount: int, reason: StringName) -> bool:
	if amount < 0 or cash < amount:
		return false
	add(-amount, reason)
	return true


func set_cash(amount: int) -> void:
	cash = maxi(amount, 0)
	cash_changed.emit(cash, 0, &"set")


func owns(item_id: StringName) -> bool:
	return _owned.has(item_id)


func get_owned() -> Array[StringName]:
	var ids: Array[StringName] = []
	for item_id: StringName in _owned:
		ids.append(item_id)
	return ids


## Buys `item_id` for keeps if it isn't owned yet and the player can pay; true if bought.
func buy(item_id: StringName, price: int, reason: StringName) -> bool:
	if owns(item_id) or not try_spend(price, reason):
		return false
	_owned[item_id] = true
	owned_changed.emit(item_id)
	return true


func to_save() -> Dictionary:
	var owned: Array[String] = []
	for item_id: StringName in _owned:
		owned.append(String(item_id))
	return {"cash": cash, "owned": owned}


func from_save(data: Dictionary) -> void:
	_owned.clear()
	var owned: Variant = data.get("owned", [])
	if owned is Array:
		for item_id: Variant in owned:
			_owned[StringName(str(item_id))] = true
	owned_changed.emit(&"")
	set_cash(int(data.get("cash", 0)))


## "₹1,25,000": rupees with Indian digit grouping (thousands, then lakhs and crores in pairs).
static func format(amount: int) -> String:
	var digits: String = str(absi(amount))
	var grouped: String = digits.right(3)
	var rest: String = digits.left(maxi(digits.length() - 3, 0))
	while rest.length() > 0:
		grouped = rest.right(2) + "," + grouped
		rest = rest.left(maxi(rest.length() - 2, 0))
	return ("-₹" if amount < 0 else "₹") + grouped


func _on_mission_passed(mission: MissionData) -> void:
	add(mission.reward_cash, &"mission")
