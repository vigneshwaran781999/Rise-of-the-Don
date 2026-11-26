class_name CutsceneFigure
extends Node3D
## Someone in a cutscene (a CutsceneActor). CutscenePlayer's AnimationPlayer moves it along its
## path (its position track), then calls update(): it turns the way it walks and walks at its
## speed; standing still, it faces `face` (the player) if asked, or the way it last faced; it
## gestures while one of its lines is up, and can hold its fists up. Its body is a rigged
## HumanFigure, like everyone else's.

## Matched against the speakers of the lines.
var speaker: String = ""
## Whom to turn to when standing still (null: keep facing the same way).
var face: Node3D
var talking: bool = false

var _model: HumanFigure
var _yaw: float = 0.0
var _last := Vector3.INF
var _speed: float = 0.0


## Dresses the figure as `actor` (or the mission contact standing in for it) and puts it at its
## first point. `frame` is the cutscene's frame.
func setup(actor: CutsceneActor, contact: MissionContact, looks: Array[PackedScene], frame: Transform3D) -> void:
	speaker = contact.display_name if contact != null else actor.speaker
	var look: int = contact.look if contact != null else actor.look
	_model = HumanFigure.new()
	_model.name = "Model"
	add_child(_model)
	_model.set_look(looks[clampi(look, 0, looks.size() - 1)])
	_model.set_colours({
		&"top_color": contact.top_color if contact != null else actor.top_color,
		&"bottom_color": contact.bottom_color if contact != null else actor.bottom_color,
		&"skin_color": contact.skin_color if contact != null else actor.skin_color,
		&"hair_color": contact.hair_color if contact != null else actor.hair_color,
	})
	_model.set_guard(1.0 if actor.guard else 0.0)
	# Facing: yaw 0 looks along the frame's -Z; the model faces its own +Z.
	_yaw = frame.basis.get_euler().y + deg_to_rad(actor.yaw_degrees) + PI
	_model.rotation.y = _yaw
	position = frame * actor.path[0]


## Called after each animation step: facing and gait from how far it moved.
func update(delta: float) -> void:
	var moved := Vector3.ZERO
	if _last != Vector3.INF:
		moved = position - _last
		moved.y = 0.0
	_last = position
	var speed: float = moved.length() / maxf(delta, 0.0001)
	if speed > 0.3:
		_yaw = atan2(moved.x, moved.z)
	elif face != null and is_instance_valid(face):
		var to: Vector3 = face.global_position - global_position
		to.y = 0.0
		if to.length() > 0.3:
			_yaw = atan2(to.x, to.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, _yaw, 1.0 - exp(-8.0 * delta))
	_speed = lerpf(_speed, speed, 1.0 - exp(-10.0 * delta)) if delta > 0.0 else 0.0
	_model.set_speed(_speed)
	_model.set_state(&"talk" if talking and _speed < 0.3 else &"move")


func get_yaw() -> float:
	return _model.rotation.y


func get_model() -> HumanFigure:
	return _model
