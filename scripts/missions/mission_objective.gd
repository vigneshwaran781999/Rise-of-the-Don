class_name MissionObjective
extends Resource
## One step of a mission (GDD §8). The HUD shows `text` while it is current.
## - GO_TO: reach `position` (within `radius`), on foot, in any vehicle or in a mission vehicle.
## - TALK_TO: walk up to contact `contact` and press interact; `lines` are spoken, then the
##   contact hands over `give_item` and/or takes `take_item` (a delivery).
## - ENTER_VEHICLE: get into mission vehicle `vehicle`.

enum Type { GO_TO, TALK_TO, ENTER_VEHICLE }
## How the player must arrive at a GO_TO point.
enum Mode { ANY, ON_FOOT, IN_VEHICLE }

@export var type: Type = Type.GO_TO
## Objective line on the HUD.
@export var text: String
## Tutorial hint shown when the objective starts; {action_name} becomes that action's key.
@export var hint: String

@export_group("Go to")
@export var position: Vector3
@export var radius: float = 3.0
@export var mode: Mode = Mode.ANY

@export_group("Talk to and deliver")
@export var contact: StringName
## "SPEAKER: text" per line.
@export var lines: PackedStringArray = []
@export var give_item: StringName
@export var take_item: StringName

@export_group("Vehicle")
## ENTER_VEHICLE: the mission vehicle to get into. GO_TO in IN_VEHICLE mode: the mission vehicle
## to arrive in (empty = any vehicle).
@export var vehicle: StringName

@export_group("Timer and checkpoint")
## Seconds allowed for this objective (0 = no limit). Running out fails the mission.
@export var time_limit: float = 0.0
## Retrying after a failure, or loading a save made from here on, restarts at this objective.
@export var checkpoint: bool = false
## Where the player is put when restarting here.
@export var checkpoint_position: Vector3
@export var checkpoint_yaw_degrees: float = 0.0
