extends Node
## The player's cash (GDD §9): balance and transactions, announced through cash_changed.
## Mission rewards are paid here when MissionManager reports a mission passed.
## Autoload: EconomyManager.

signal cash_changed(cash: int, delta: int, reason: StringName)

var cash: int = 0


func _ready() -> void:
	MissionManager.mission_passed.connect(_on_mission_passed)


## New game: the starting purse.
func start_new_game(starting_cash: int) -> void:
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


func to_save() -> Dictionary:
	return {"cash": cash}


func from_save(data: Dictionary) -> void:
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
