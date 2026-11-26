class_name CutsceneActor
extends Resource
## Someone in a cutscene (CutsceneData) besides the player: a figure that walks along `path`
## (cutscene frame), reaching point i at `times`[i] seconds from the start, and stands facing
## `yaw_degrees` (0 = the cutscene's ahead, -Z; 90 = to its left) until it first moves. While
## one of their lines is up they gesture. A mission contact can lend them their name, look and
## colours (`contact`): its figure in the world hides while the cutscene plays.

## Their name as it appears before their lines (matched against each shot's speaker, any case).
@export var speaker: String = ""
## A MissionContact id of the running mission; overrides speaker, look and colours.
@export var contact: StringName
@export_enum("Man", "Woman", "Older man") var look: int = 0
@export var top_color: Color = Color("e9e4d6")
@export var bottom_color: Color = Color("2c3a55")
@export var skin_color: Color = Color("8d5a3b")
@export var hair_color: Color = Color("1a1412")
## Where they stand, then walk to: at least one point.
@export var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO])
## When they reach each point of `path` (seconds); the first is where they start.
@export var times: PackedFloat32Array = PackedFloat32Array([0.0])
@export var yaw_degrees: float = 0.0
## Fists up (a thug squaring up).
@export var guard: bool = false
## Turn to face the player whenever standing still.
@export var face_player: bool = true
