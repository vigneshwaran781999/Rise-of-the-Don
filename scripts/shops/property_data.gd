class_name PropertyData
extends Resource
## A property for sale (GDD §9): once bought it is a save point and pays its income at the
## start of every in-game day. Edit the .tres files in res://resources/properties/.

@export var id: StringName
@export var title: String
## One line on the "for sale" offer.
@export var description: String
## Key into CityData.places: the spot in front of its door.
@export var place: StringName
@export var price: int = 5000
## Cash paid at the start of each in-game day while you own it.
@export var daily_income: int = 300
## On sale once this mission has been passed (empty: from the start).
@export var unlock_mission: StringName


func is_on_sale() -> bool:
	return unlock_mission == &"" or MissionManager.is_completed(unlock_mission)
