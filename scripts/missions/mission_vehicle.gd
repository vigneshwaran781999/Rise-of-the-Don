class_name MissionVehicle
extends Resource
## A vehicle a mission lends the player, parked at `position` facing `yaw_degrees`
## (0 = north) while the mission runs.

@export var id: StringName
## How objectives and failure messages name it, e.g. "the tailor's car".
@export var label: String
@export var scene: PackedScene
@export var position: Vector3
@export var yaw_degrees: float = 0.0
@export var paint: Color = Color("2f6d4e")
## Wrecking it fails the mission.
@export var must_survive: bool = true
