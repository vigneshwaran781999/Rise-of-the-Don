class_name MissionContact
extends Resource
## A person a mission needs (a giver, someone to talk to or deliver to). They stand at
## `position` facing `yaw_degrees` (0 = north) and wear the colours given here.

@export var id: StringName
## Shown over their lines and in the talk prompt.
@export var display_name: String
@export_enum("Man", "Woman", "Older man") var look: int = 0
@export var top_color: Color = Color("e9e4d6")
@export var bottom_color: Color = Color("2c3a55")
@export var skin_color: Color = Color("8d5a3b")
@export var hair_color: Color = Color("1a1412")
@export var position: Vector3
@export var yaw_degrees: float = 0.0
