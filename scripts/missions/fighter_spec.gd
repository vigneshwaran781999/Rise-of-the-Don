class_name FighterSpec
extends Resource
## Someone a FIGHT or ESCAPE objective brings in to fight the player (a Fighter): where they
## stand, facing `yaw_degrees` (0 = north, as for contacts), and how they look. They come for the
## player once they are close (or straight away in an ESCAPE).

@export var position: Vector3
@export var yaw_degrees: float = 0.0
@export_enum("Man", "Woman", "Older man") var look: int = 0
@export var top_color: Color = Color("3a3431")
@export var bottom_color: Color = Color("22252b")
@export var skin_color: Color = Color("7a4a30")
@export var hair_color: Color = Color("15110e")
## Health (0 = the fighter tuning's, four punches); a leader can take more.
@export var health: float = 0.0
