class_name CutsceneData
extends Resource
## A scripted cutscene (M7, GDD §15): camera shots with subtitles and captions, people who walk
## and talk, the player standing in it, the letterbox. Played by CutscenePlayer, which turns it
## into an Animation for an AnimationPlayer driving a camera rig. Everything is placed in the
## cutscene's own frame, pinned to the world at `anchor` facing `anchor_yaw_degrees` (0 = north,
## -Z; 90 = west, as Godot turns), so it can be moved without rewriting the shots.

@export var id: StringName
@export var anchor: Vector3
@export var anchor_yaw_degrees: float = 0.0
@export var shots: Array[CutsceneShot] = []
@export var actors: Array[CutsceneActor] = []
## Where the player stands for it (cutscene frame) and which way they face (as for actors).
@export var player_position: Vector3 = Vector3.ZERO
@export var player_yaw_degrees: float = 0.0
## Can interact skip on to the next shot.
@export var skippable: bool = true

@export_group("Time and weather")
## When it happens: outside this window of hours (from-to, may run past midnight, e.g. 20 to 4.5)
## the clock skips forward to `hour_from` as it starts (StoryClock). Negative: any time.
@export var hour_from: float = -1.0
@export var hour_to: float = -1.0
## The weather it sets at once (a WeatherLook id; empty: leave the weather alone).
@export var weather: StringName = &""


## The frame everything is placed in.
func get_frame() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(anchor_yaw_degrees)), anchor)


func get_length() -> float:
	var total: float = 0.0
	for shot: CutsceneShot in shots:
		total += shot.seconds
	return total
