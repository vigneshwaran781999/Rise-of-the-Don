class_name ShopItem
extends Resource
## Something a shop sells (GDD §9). FoodItem and Outfit add what it does.

@export var id: StringName
@export var title: String
## One short line shown under the list in the shop.
@export var description: String
@export var price: int = 0
