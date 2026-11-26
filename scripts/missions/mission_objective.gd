class_name MissionObjective
extends Resource
## One step of a mission (GDD §8). The HUD shows `text` while it is current.
## - GO_TO: reach `position` (within `radius`), on foot, in any vehicle or in a mission vehicle.
## - TALK_TO: walk up to contact `contact` and press interact; `lines` are spoken, then the
##   contact hands over `give_item` and/or takes `take_item` (a delivery).
## - ENTER_VEHICLE: get into mission vehicle `vehicle`.
## - CHECKPOINTS: drive (or run) through `checkpoints` in order, each within `radius`; no need to
##   stop. `mode` and `vehicle` as for GO_TO.
## - LOSE_WANTED: get the wanted level back to 0 (lose the police, or a respray).
## - BUY_PROPERTY: own property `property` (bought at its door; `position` marks the door).
## - CUTSCENE: watch `cutscene` (the player is put in it, on foot); it ends the objective.
## - FIGHT: knock out everyone in `fighters` (they come for the player once close).
## - FOLLOW: tail mission vehicle `vehicle` as it drives through `checkpoints` (its route) to the
##   last one, staying within `follow_far` m (further loses it) and not within `follow_near` m for
##   more than `spotted_seconds` (they spot you). Put each stop in the lane the car should be in
##   (cars change lanes only at junctions; turning left, the kerb lane).
## - ESCAPE: get `radius` m away from `position`; any `fighters` chase you at once.
## - CHOICE: pick one of `choices`; the answer is kept under `choice_id` (GameState).
## Any objective can raise the wanted level when it starts (`wanted_level`), and runs only when an
## earlier choice `if_choice` was answered `if_answer` (if set: the story's branches).

enum Type { GO_TO, TALK_TO, ENTER_VEHICLE, CHECKPOINTS, LOSE_WANTED, BUY_PROPERTY, CUTSCENE, FIGHT, FOLLOW, ESCAPE, CHOICE }
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
## If not empty, each time the objective starts it goes to one of these, picked at random,
## instead of `position` (side jobs to a different customer each time).
@export var alternatives: PackedVector3Array = PackedVector3Array()

@export_group("Talk to and deliver")
@export var contact: StringName
## "SPEAKER: text" per line.
@export var lines: PackedStringArray = []
@export var give_item: StringName
@export var take_item: StringName
## Plays as a dialogue scene: a two-shot camera and letterbox bars, the player standing still.
@export var scene: bool = false

@export_group("Checkpoints")
## CHECKPOINTS: the points to pass, in order.
@export var checkpoints: PackedVector3Array = PackedVector3Array()

@export_group("Cutscene")
@export var cutscene: CutsceneData

@export_group("Fight and escape")
## FIGHT: the people to knock out; ESCAPE: people chasing you.
@export var fighters: Array[FighterSpec] = []
## FIGHT: they come for the player once this close.
@export var aggro_range: float = 22.0

@export_group("Follow")
@export var follow_near: float = 10.0
@export var follow_far: float = 80.0
@export var spotted_seconds: float = 4.0
## How fast the car being tailed drives.
@export var route_speed_kmh: float = 40.0

@export_group("Choice")
## The answers (button texts), in order.
@export var choices: PackedStringArray = PackedStringArray()
@export var choice_id: StringName

@export_group("Branch")
## Run this objective only if choice `if_choice` was answered `if_answer` (empty: always).
@export var if_choice: StringName
@export var if_answer: int = 0

@export_group("Property and police")
## BUY_PROPERTY: the PropertyData id to own.
@export var property: StringName
## When the objective starts the wanted level rises to at least this (0 = leave it).
@export_range(0, 5) var wanted_level: int = 0

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


## Where a GO_TO goes this time: `position`, or one of `alternatives` at random.
func pick_position(rng: RandomNumberGenerator) -> Vector3:
	return position if alternatives.is_empty() else alternatives[rng.randi() % alternatives.size()]


## Whether it runs, given the story's choices so far (GameState).
func applies() -> bool:
	return if_choice == &"" or GameState.get_choice(if_choice) == if_answer
