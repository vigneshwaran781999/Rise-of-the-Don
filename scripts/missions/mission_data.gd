class_name MissionData
extends Resource
## One mission (GDD §8): where it starts and who gives it, its ordered objectives, the people
## and vehicles it brings into the world, and its reward. Missions live in
## res://resources/missions/ and are listed in story.tres.
##
## Directions in the world use a yaw in degrees: 0 faces north (-Z), 90 faces west (-X).

enum Category { STORY, DRIVING, DELIVERY, RACING, EXPLORATION, RESCUE, BUSINESS }

@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var category: Category = Category.STORY

@export_group("Start")
## Missions that must be passed before this one is offered.
@export var prerequisites: Array[StringName] = []
## Starts by itself when offered (the opening mission on New Game); otherwise the player walks
## into its start marker.
@export var auto_start: bool = false
## The start marker, and where the player stands when the mission (re)starts from the top.
@export var start_position: Vector3
@export var start_yaw_degrees: float = 0.0
## Who offers the mission: stands by the start marker while it is on offer (optional).
@export var giver: MissionContact
## Offered again after it has been passed (side jobs; GDD §3, mission 5).
@export var repeatable: bool = false

@export_group("Content")
@export var objectives: Array[MissionObjective] = []
## People the mission needs; they are in the world while it runs.
@export var contacts: Array[MissionContact] = []
## Vehicles the mission lends the player; parked at their spots while it runs.
@export var vehicles: Array[MissionVehicle] = []
## Spoken as the mission starts, "SPEAKER: text" per line.
@export var intro_lines: PackedStringArray = []
## Spoken after it is passed.
@export var outro_lines: PackedStringArray = []

@export_group("Reward")
@export var reward_cash: int = 0


func get_contact(contact_id: StringName) -> MissionContact:
	if giver != null and giver.id == contact_id:
		return giver
	for contact: MissionContact in contacts:
		if contact.id == contact_id:
			return contact
	return null


func get_vehicle(vehicle_id: StringName) -> MissionVehicle:
	for vehicle: MissionVehicle in vehicles:
		if vehicle.id == vehicle_id:
			return vehicle
	return null


## Items the player holds when objective `index` starts (gifts and hand-overs before it).
func items_before(index: int) -> Array[StringName]:
	var items: Array[StringName] = []
	for k: int in mini(index, objectives.size()):
		var objective: MissionObjective = objectives[k]
		if objective.take_item != &"":
			items.erase(objective.take_item)
		if objective.give_item != &"" and not items.has(objective.give_item):
			items.append(objective.give_item)
	return items


## The checkpoint at or before objective `index` (0 = the top of the mission).
func checkpoint_for(index: int) -> int:
	for k: int in range(mini(index, objectives.size() - 1), 0, -1):
		if objectives[k].checkpoint:
			return k
	return 0


## Where the player stands when (re)starting from checkpoint `index`, and their yaw.
func checkpoint_spot(index: int) -> Array:
	if index <= 0 or index >= objectives.size():
		return [start_position, start_yaw_degrees]
	return [objectives[index].checkpoint_position, objectives[index].checkpoint_yaw_degrees]
