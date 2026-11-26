class_name CutsceneShot
extends Resource
## One camera shot of a cutscene (CutsceneData): the camera moves from `camera_from` to
## `camera_to` while looking from `look_from` to `look_to`, over `seconds`. Positions are in the
## cutscene's own frame (CutsceneData: x to the right, y up, -z ahead of its anchor). A shot that
## starts where the last one ended carries on smoothly; anything else is a cut.

@export var seconds: float = 3.0
@export var camera_from: Vector3 = Vector3(0.0, 1.7, 4.0)
@export var camera_to: Vector3 = Vector3(0.0, 1.7, 4.0)
@export var look_from: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var look_to: Vector3 = Vector3(0.0, 1.5, 0.0)
## Field of view (degrees) at the start and end of the shot.
@export var fov_from: float = 50.0
@export var fov_to: float = 50.0
## Ease the move in and out (otherwise a steady glide).
@export var ease: bool = true
## Subtitle shown through the shot: "SPEAKER: text" (no speaker: narration).
@export var line: String = ""
## Big text across the middle of the screen through the shot (a place, a time).
@export var caption: String = ""
