class_name ShopData
extends Resource
## A shop in the district (GDD §9), placed at one of the district's places (CityData.places:
## the spot in front of its door). Edit the .tres files in res://resources/shops/.
## - FOOD: items are FoodItems, eaten on the spot for health.
## - CLOTHES: items are Outfits, bought once and then worn at will.
## - RESPRAY: drive a car into the garage: new paint, repairs and new tyres for a fee, and a
##   wanted level up to WantedTuning.respray_max_level is dropped (WantedTuning.respray_fee).

enum Kind { FOOD, CLOTHES, RESPRAY }

@export var id: StringName
@export var title: String
@export var kind: Kind = Kind.FOOD
## Key into CityData.places.
@export var place: StringName
## The shop opens once this mission has been passed (empty: open from the start).
@export var unlock_mission: StringName
## What the shopkeeper says when the shop opens.
@export var greeting: String
@export var items: Array[ShopItem] = []


func get_item(item_id: StringName) -> ShopItem:
	for item: ShopItem in items:
		if item.id == item_id:
			return item
	return null


func is_open() -> bool:
	return unlock_mission == &"" or MissionManager.is_completed(unlock_mission)
