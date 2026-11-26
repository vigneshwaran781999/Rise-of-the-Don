class_name PoliceOfficer
extends CharacterBody3D
## A police officer on foot (GDD §7): runs after the player along the sidewalks (navmesh) and
## straight at them when close; searches around where they were last seen; walks off when the
## player is clear. A car or the player's fists can knock them down (assaulting an officer is a
## crime). Built in code: a capsule, the rigged man (HumanFigure) in khaki, a NavigationAgent3D.

enum State { CHASE, SEARCH, KNOCKED, LEAVE }

const GROUP: StringName = &"police_officers"
const KHAKI := Color("b49a64")
const DARK_KHAKI := Color("8a7448")
const DIRECT_RANGE: float = 6.0
const KNOCKED_SECONDS: float = 3.5
## People the player can punch (PlayerFists).
const HITTABLE_GROUP: StringName = &"hittable"
## A punch that doesn't floor the officer pushes them back this hard (m/s) for this long.
const HIT_KNOCKBACK: float = 2.5
const HIT_STAGGER_SECONDS: float = 0.6

var state: State = State.CHASE
## Where to go (the player, or where they were last seen).
var target := Vector3.ZERO
var run_speed: float = 5.6
## Health against punches (set from WantedTuning.officer_health).
var max_health: float = 60.0
var manager: Node

var model: HumanFigure
var agent: NavigationAgent3D

var _shape: CollisionShape3D
var _gravity: float = 9.8
var _timer: float = 0.0
var _repath: float = 0.0
var _health: float = 60.0
var _stagger_left: float = 0.0
var _punched: bool = false             # punched before (only the first blow is the serious crime)


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
	model = HumanFigure.new()
	model.name = "Model"
	model.set_colours({&"top_color": KHAKI, &"bottom_color": DARK_KHAKI, &"skin_color": skin, &"hair_color": Color("17120f")})
	add_child(model)
	model.set_look(look)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.0
	agent.target_desired_distance = 1.0
	agent.radius = 0.35
	add_child(agent)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(HITTABLE_GROUP)
	_health = max_health
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func is_down() -> bool:
	return state == State.KNOCKED


func get_state_name() -> String:
	return State.keys()[state]


## Called by a car's VehicleBumper when it reaches the officer.
func hit_by_vehicle(vehicle: VehicleController, speed: float) -> void:
	if state == State.KNOCKED or speed < 2.0:
		return
	_knock_down(vehicle.global_position)
	if manager != null and manager.has_method(&"officer_hit"):
		manager.call(&"officer_hit", self, vehicle)


## A punch from `attacker` at `from` (PlayerFists): costs health and pushes the officer back for a
## moment; at none left they go down. Punching an officer is a crime.
func take_hit(damage: float, from: Vector3, attacker: Node3D = null) -> void:
	if state == State.KNOCKED:
		return
	_health -= damage
	if _health <= 0.0:
		_knock_down(from)
	else:
		var push := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
		push = push.normalized() if push.length_squared() > 0.0001 else -global_basis.z
		velocity.x = push.x * HIT_KNOCKBACK
		velocity.z = push.z * HIT_KNOCKBACK
		_stagger_left = HIT_STAGGER_SECONDS
		model.play(&"hit")
	if manager != null and manager.has_method(&"officer_punched"):
		manager.call(&"officer_punched", self, attacker, not _punched)
	_punched = true


## Falls flat on their back away from `from`, gets up a few seconds later at full strength.
func _knock_down(from: Vector3) -> void:
	_shape.set_deferred(&"disabled", true)
	velocity = Vector3.ZERO
	_stagger_left = 0.0
	var push: Vector3 = global_position - from
	push.y = 0.0
	if push.length_squared() > 0.01:
		rotation.y = atan2(-push.x, -push.z)
	model.play(&"knocked")
	_timer = KNOCKED_SECONDS
	_health = max_health
	state = State.KNOCKED


func _physics_process(delta: float) -> void:
	match state:
		State.KNOCKED:
			_timer -= delta
			if _timer <= 0.0:
				model.play(&"getup")
				_shape.set_deferred(&"disabled", false)
				state = State.CHASE
			_animate(delta, 0.0)
			return
		State.CHASE, State.SEARCH, State.LEAVE:
			if _stagger_left > 0.0:          # reeling from a punch
				_stagger_left -= delta
				velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
			else:
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


func _animate(_delta: float, speed: float) -> void:
	model.set_state(&"down" if state == State.KNOCKED else &"move")
	model.set_speed(0.0 if _stagger_left > 0.0 else speed)
