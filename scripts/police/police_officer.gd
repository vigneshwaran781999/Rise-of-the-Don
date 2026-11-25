class_name PoliceOfficer
extends CharacterBody3D
## A police officer on foot (GDD §7): runs after the player along the sidewalks (navmesh) and
## straight at them when close; searches around where they were last seen; walks off when the
## player is clear. A car can knock them down (assaulting an officer is a crime). Built in code:
## a capsule, the pedestrian man model in khaki, a NavigationAgent3D.

enum State { CHASE, SEARCH, KNOCKED, LEAVE }

const GROUP: StringName = &"police_officers"
const KHAKI := Color("b49a64")
const DARK_KHAKI := Color("8a7448")
const DIRECT_RANGE: float = 6.0
const KNOCKED_SECONDS: float = 3.5

var state: State = State.CHASE
## Where to go (the player, or where they were last seen).
var target := Vector3.ZERO
var run_speed: float = 5.6
var manager: Node

var model: MeshInstance3D
var agent: NavigationAgent3D

var _shape: CollisionShape3D
var _gravity: float = 9.8
var _phase: float = 0.0
var _swing: float = 0.0
var _timer: float = 0.0
var _repath: float = 0.0


func setup(look: PackedScene, skin: Color) -> void:
	name = "Officer"
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.7
	_shape.shape = capsule
	_shape.position = Vector3(0.0, 0.85, 0.0)
	add_child(_shape)
	model = MeshInstance3D.new()
	model.name = "Model"
	model.mesh = CharacterBaker.get_mesh(look)
	model.material_override = CharacterBaker.get_material()
	add_child(model)
	model.set_instance_shader_parameter(&"top_color", KHAKI)
	model.set_instance_shader_parameter(&"bottom_color", DARK_KHAKI)
	model.set_instance_shader_parameter(&"skin_color", skin)
	model.set_instance_shader_parameter(&"hair_color", Color("17120f"))
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	agent.radius = 0.35
	add_child(agent)


func _ready() -> void:
	add_to_group(GROUP)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func is_down() -> bool:
	return state == State.KNOCKED


func get_state_name() -> String:
	return State.keys()[state]


## Called by a car's VehicleBumper when it reaches the officer.
func hit_by_vehicle(vehicle: VehicleController, speed: float) -> void:
	if state == State.KNOCKED or speed < 2.0:
		return
	_shape.set_deferred(&"disabled", true)
	velocity = Vector3.ZERO
	var push: Vector3 = global_position - vehicle.global_position
	push.y = 0.0
	if push.length_squared() > 0.01:
		rotation.y = atan2(-push.x, -push.z)
	model.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	model.position = Vector3(0.0, 0.12, 0.0)
	_timer = KNOCKED_SECONDS
	state = State.KNOCKED
	if manager != null and manager.has_method(&"officer_hit"):
		manager.call(&"officer_hit", self, vehicle)


func _physics_process(delta: float) -> void:
	match state:
		State.KNOCKED:
			_timer -= delta
			if _timer <= 0.0:
				model.rotation = Vector3.ZERO
				model.position = Vector3.ZERO
				_shape.set_deferred(&"disabled", false)
				state = State.CHASE
			_animate(delta, 0.0)
			return
		State.CHASE, State.SEARCH, State.LEAVE:
			_move_towards(target, run_speed if state != State.SEARCH else 2.6, delta)
	velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	_animate(delta, Vector2(velocity.x, velocity.z).length())


func _move_towards(goal: Vector3, speed: float, delta: float) -> void:
	var to_goal: Vector3 = goal - global_position
	to_goal.y = 0.0
	var step: Vector3
	if to_goal.length() < DIRECT_RANGE:
		step = to_goal.normalized() * speed if to_goal.length() > 0.9 else Vector3.ZERO
	else:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.5
			agent.target_position = goal
		var next: Vector3 = agent.get_next_path_position() - global_position
		next.y = 0.0
		step = next.normalized() * speed if next.length() > 0.1 else to_goal.normalized() * speed
	velocity.x = step.x
	velocity.z = step.z
	if step.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), 1.0 - exp(-10.0 * delta))


func _animate(delta: float, speed: float) -> void:
	_phase += speed / 0.75 * PI * delta
	_swing = lerpf(_swing, clampf(speed / 1.4, 0.0, 1.0) * 0.45 * (1.5 if speed > 3.0 else 1.0), 1.0 - exp(-8.0 * delta))
	model.set_instance_shader_parameter(&"walk_phase", _phase)
	model.set_instance_shader_parameter(&"swing", _swing)
