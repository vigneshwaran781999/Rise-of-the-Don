class_name MissionContactNPC
extends StaticBody3D
## A mission character standing in the world (a giver, someone to talk to or deliver to): a
## pedestrian model in fixed colours, solid like a post, who turns to face the player when they
## come close and gestures while talking.

const FACE_DISTANCE: float = 7.0

var data: MissionContact
## Set while one of their lines is being spoken.
var talking: bool = false
## Who to turn towards when close (the player).
var watch: Node3D

var _model: MeshInstance3D
var _rest_yaw: float = 0.0
var _phase: float = 0.0


func setup(contact: MissionContact, look_scene: PackedScene) -> void:
	data = contact
	name = "Contact_%s" % contact.id
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(shape)
	_model = MeshInstance3D.new()
	_model.name = "Model"
	_model.mesh = CharacterBaker.get_mesh(look_scene)
	_model.material_override = CharacterBaker.get_material()
	add_child(_model)
	_model.set_instance_shader_parameter(&"top_color", contact.top_color)
	_model.set_instance_shader_parameter(&"bottom_color", contact.bottom_color)
	_model.set_instance_shader_parameter(&"skin_color", contact.skin_color)
	_model.set_instance_shader_parameter(&"hair_color", contact.hair_color)
	# Mission yaw: 0 faces north (-Z). The model faces its +Z.
	_rest_yaw = deg_to_rad(contact.yaw_degrees) + PI
	_model.rotation.y = _rest_yaw


func _ready() -> void:
	position = data.position if data != null else position


func _process(delta: float) -> void:
	if _model == null:
		return
	var wanted: float = _rest_yaw
	if watch != null and is_instance_valid(watch) and watch.is_visible_in_tree():
		var to_watch: Vector3 = watch.global_position - global_position
		to_watch.y = 0.0
		if to_watch.length() < FACE_DISTANCE and to_watch.length() > 0.3:
			wanted = atan2(to_watch.x, to_watch.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, wanted, 1.0 - exp(-4.0 * delta))
	_phase += delta * (2.5 if talking else 0.0)
	_model.set_instance_shader_parameter(&"walk_phase", _phase)
	_model.set_instance_shader_parameter(&"swing", 0.14 if talking else 0.0)
