class_name CutsceneFigure
extends Node3D
## Someone in a cutscene (a CutsceneActor). CutscenePlayer's AnimationPlayer moves it along its
## path (its position track), then calls update(): it turns the way it walks and swings its legs
## and arms to its speed; standing still, it faces `face` (the player) if asked, or the way it
## last faced; it gestures while one of its lines is up, and can hold its fists up.
## Looks come from shaders/character.gdshader (CharacterBaker), like pedestrians.

## Matched against the speakers of the lines.
var speaker: String = ""
## Whom to turn to when standing still (null: keep facing the same way).
var face: Node3D
var talking: bool = false

var _model: MeshInstance3D
var _yaw: float = 0.0
var _last := Vector3.INF
var _phase: float = 0.0
var _swing: float = 0.0
var _guard: bool = false


## Dresses the figure as `actor` (or the mission contact standing in for it) and puts it at its
## first point. `frame` is the cutscene's frame.
func setup(actor: CutsceneActor, contact: MissionContact, looks: Array[PackedScene], frame: Transform3D) -> void:
	speaker = contact.display_name if contact != null else actor.speaker
	var look: int = contact.look if contact != null else actor.look
	_model = MeshInstance3D.new()
	_model.name = "Model"
	_model.mesh = CharacterBaker.get_mesh(looks[clampi(look, 0, looks.size() - 1)])
	_model.material_override = CharacterBaker.get_material()
	add_child(_model)
	_model.set_instance_shader_parameter(&"top_color", contact.top_color if contact != null else actor.top_color)
	_model.set_instance_shader_parameter(&"bottom_color", contact.bottom_color if contact != null else actor.bottom_color)
	_model.set_instance_shader_parameter(&"skin_color", contact.skin_color if contact != null else actor.skin_color)
	_model.set_instance_shader_parameter(&"hair_color", contact.hair_color if contact != null else actor.hair_color)
	_guard = actor.guard
	_model.set_instance_shader_parameter(&"guard", 1.0 if _guard else 0.0)
	# Facing: yaw 0 looks along the frame's -Z; the model faces its own +Z.
	_yaw = frame.basis.get_euler().y + deg_to_rad(actor.yaw_degrees) + PI
	_model.rotation.y = _yaw
	position = frame * actor.path[0]


## Called after each animation step: walk cycle and facing from how far it moved.
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
	var target_swing: float = clampf(speed / 1.4, 0.0, 1.0) * 0.45 * (1.5 if speed > 2.5 else 1.0)
	if talking and speed < 0.3:
		target_swing = 0.14
		_phase += delta * 2.5
	else:
		_phase += speed / 0.7 * PI * delta
	_swing = lerpf(_swing, target_swing, 1.0 - exp(-8.0 * delta))
	_model.set_instance_shader_parameter(&"walk_phase", _phase)
	_model.set_instance_shader_parameter(&"swing", _swing)


func get_yaw() -> float:
	return _model.rotation.y
