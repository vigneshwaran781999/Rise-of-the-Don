class_name BikeRider
extends MeshInstance3D
## The rider on a motorcycle (M7): unlike in a car, whoever is riding can be seen. Shown while the
## bike has a driver: the player in their outfit (GameState.outfit, from the clothes shop's
## wardrobe), anyone else (traffic) in one of the outfits picked at random. The character's sit
## pose (shaders/character.gdshader) puts the legs forward. A child of the bike's Model node, so it
## leans with the bike.

@export var look: PackedScene
@export var wardrobe: ShopData
@export var skin_color: Color = Color("8d5a3b")
@export var hair_color: Color = Color("1b1612")

var _vehicle: VehicleController


func _ready() -> void:
	_vehicle = owner as VehicleController
	mesh = CharacterBaker.get_mesh(look)
	set_instance_shader_parameter(&"sit", 1.0)
	set_instance_shader_parameter(&"skin_color", skin_color)
	set_instance_shader_parameter(&"hair_color", hair_color)
	_vehicle.driver_changed.connect(_on_driver_changed)
	_on_driver_changed(_vehicle.get_driver())


func _on_driver_changed(driver: Node3D) -> void:
	visible = driver != null
	if driver == null or wardrobe == null or wardrobe.items.is_empty():
		return
	var outfit: Outfit = null
	if driver is PlayerController:
		outfit = wardrobe.get_item(GameState.outfit) as Outfit
	else:
		outfit = wardrobe.items[randi() % wardrobe.items.size()] as Outfit
	if outfit == null:
		outfit = wardrobe.items[0] as Outfit
	set_instance_shader_parameter(&"top_color", outfit.top_color)
	set_instance_shader_parameter(&"bottom_color", outfit.bottom_color)
