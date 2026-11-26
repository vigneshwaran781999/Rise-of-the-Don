class_name Fighter
extends CharacterBody3D
## Someone who fights with their fists (M7): story thugs, brawlers, bodyguards. While `hostile`,
## runs at `target` (the player), stops just in front of them with fists up, and throws punches:
## a wind-up you can see (the right arm drawn back, the shoulders turned), then the blow, which
## lands if the player is still in front of them. Punches (take_hit) cost health, push them back
## and break a wind-up; at no health they go down for good (defeated). Not hostile, they stand
## about until someone punches them. A car can floor them too. They leave a player who is down or
## in a vehicle alone.
## Looks and the walk cycle come from shaders/character.gdshader (CharacterBaker), like
## pedestrians. Missions spawn them (scenes/npc/fighter.tscn).

## Out of the fight (knocked out).
signal defeated(fighter: Fighter)
## Someone punched a fighter who wasn't hostile: they fight back now.
signal provoked(fighter: Fighter)
## A blow of theirs landed on `on`.
signal punch_landed(on: Node3D)

enum State { IDLE, CHASE, WINDUP, PUNCH, STAGGER, DOWN }

const GROUP: StringName = &"fighters"
## People the player can punch (PlayerFists).
const HITTABLE_GROUP: StringName = &"hittable"
## Closer than this they run straight at the target; further, along the navmesh.
const DIRECT_RANGE: float = 6.0
## A blow lands on the target if they are within this angle of where the fighter faces.
const STRIKE_ANGLE_DEGREES: float = 60.0
## The shoulders turn this far back in the wind-up (radians).
const WINDUP_TWIST: float = 0.4

@export var tuning: FighterTuning
@export var look: PackedScene
@export var top_color: Color = Color("3a3431")
@export var bottom_color: Color = Color("22252b")
@export var skin_color: Color = Color("7a4a30")
@export var hair_color: Color = Color("15110e")
## Fighting `target`; otherwise standing about until provoked (or `target` comes within
## `aggro_range`).
@export var hostile: bool = false
## Not hostile yet, they start fighting `target` once it is this close (0: only when provoked).
@export var aggro_range: float = 0.0
## Health (0: the tuning's).
@export var max_health: float = 0.0

## Who they fight (the player; whoever punches them, if no one was set).
var target: Node3D
var state: State = State.IDLE

@onready var model: MeshInstance3D = $Model
@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var _shape: CollisionShape3D = $CollisionShape3D

var _health: float = 80.0
var _timer: float = 0.0
var _cooldown: float = 0.0
var _landed: bool = true
var _repath: float = 0.0
var _phase: float = 0.0
var _swing: float = 0.0
var _guard: float = 0.0
var _gravity: float = 9.8
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(HITTABLE_GROUP)
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_health = max_health if max_health > 0.0 else tuning.health
	_rng.randomize()
	_cooldown = _rng.randf_range(0.2, tuning.cooldown_min)    # not everyone swings at once
	if look != null:
		model.mesh = CharacterBaker.get_mesh(look)
	model.set_instance_shader_parameter(&"top_color", top_color)
	model.set_instance_shader_parameter(&"bottom_color", bottom_color)
	model.set_instance_shader_parameter(&"skin_color", skin_color)
	model.set_instance_shader_parameter(&"hair_color", hair_color)
	_phase = _rng.randf() * TAU


func get_state_name() -> String:
	return State.keys()[state]


func is_down() -> bool:
	return state == State.DOWN


func get_health() -> float:
	return _health


## Starts fighting `who` now.
func attack(who: Node3D) -> void:
	target = who
	hostile = true
	if state == State.IDLE:
		state = State.CHASE


## A punch from `attacker` at `from`: costs health; at none left they go down for good, otherwise
## they are pushed back (breaking a wind-up or punch). Punching someone who wasn't fighting
## provokes them.
func take_hit(damage: float, from: Vector3, attacker: Node3D = null) -> void:
	if state == State.DOWN:
		return
	if attacker != null and (target == null or not hostile):
		target = attacker
	if not hostile:
		hostile = true
		provoked.emit(self)
	_health -= damage
	if _health <= 0.0:
		_go_down(from)
		return
	_stagger(from, tuning.hit_knockback)


## Called by a car's VehicleBumper when it reaches the fighter.
func hit_by_vehicle(vehicle: VehicleController, speed: float) -> void:
	if state == State.DOWN:
		return
	if speed >= tuning.knock_speed:
		_go_down(vehicle.global_position)
	else:
		_stagger(vehicle.global_position, tuning.hit_knockback)


# --------------------------------------------------------------------------- per frame

func _physics_process(delta: float) -> void:
	if state == State.DOWN:
		_animate(delta)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var step := Vector3.ZERO
	match state:
		State.IDLE:
			if not hostile and aggro_range > 0.0 and _target_near(aggro_range) and _can_fight():
				hostile = true
			if hostile and _can_fight():
				state = State.CHASE
			elif _target_near(8.0):
				_face(_to_target(), delta)
		State.CHASE:
			step = _chase(delta)
		State.WINDUP:
			_face(_to_target(), delta)
			_timer -= delta
			if _timer <= 0.0:
				_timer = tuning.punch_time
				_landed = false
				state = State.PUNCH
		State.PUNCH:
			_timer -= delta
			if not _landed and tuning.punch_time - _timer >= tuning.punch_hit_at:
				_landed = true
				_strike()
			if _timer <= 0.0:
				_cooldown = _rng.randf_range(tuning.cooldown_min, tuning.cooldown_max)
				state = State.CHASE
		State.STAGGER:
			_timer -= delta
			if _timer <= 0.0:
				state = State.CHASE if hostile else State.IDLE
	if state == State.STAGGER:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	else:
		velocity.x = step.x
		velocity.z = step.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - _gravity * delta
	move_and_slide()
	_animate(delta)


## Closes in on the target and stands just in front of them, winding up a punch when they are in
## reach and the last one has had its pause. Returns the velocity to move at.
func _chase(delta: float) -> Vector3:
	if not _can_fight():
		if not hostile:
			state = State.IDLE
		return Vector3.ZERO
	var to: Vector3 = _to_target()
	var distance: float = to.length()
	_face(to, delta)
	if distance <= tuning.punch_range and _cooldown <= 0.0 \
			and rad_to_deg(global_basis.z.angle_to(to.normalized())) < tuning.punch_angle_degrees:
		_timer = tuning.windup_time
		state = State.WINDUP
		return Vector3.ZERO
	if distance <= tuning.engage_distance:
		return Vector3.ZERO
	var speed: float = tuning.run_speed if distance > 4.0 else tuning.walk_speed
	if distance < DIRECT_RANGE:
		return to.normalized() * speed
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.5
		agent.target_position = target.global_position
	var next: Vector3 = agent.get_next_path_position() - global_position
	next.y = 0.0
	return (next.normalized() if next.length() > 0.1 else to.normalized()) * speed


## The blow lands if the target is still in reach and in front.
func _strike() -> void:
	if not _can_fight():
		return
	var to: Vector3 = _to_target()
	if to.length() > tuning.punch_reach or rad_to_deg(global_basis.z.angle_to(to.normalized())) > STRIKE_ANGLE_DEGREES:
		return
	target.call(&"take_hit", tuning.punch_damage, global_position, self)
	AudioManager.play_sfx(&"punch_hit", -4.0, _rng.randf_range(0.8, 0.95))
	punch_landed.emit(target)


func _stagger(from: Vector3, knockback: float) -> void:
	var push := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	push = push.normalized() if push.length_squared() > 0.0001 else -global_basis.z
	velocity.x = push.x * knockback
	velocity.z = push.z * knockback
	rotation.y = atan2(-push.x, -push.z)          # turned to face whoever hit them
	_timer = tuning.hit_stagger_time
	_cooldown = maxf(_cooldown, tuning.cooldown_min * 0.5)
	state = State.STAGGER


## Knocked out: flat on their back away from `from`, out of the fight.
func _go_down(from: Vector3) -> void:
	_health = 0.0
	_shape.set_deferred(&"disabled", true)
	velocity = Vector3.ZERO
	var push := Vector3(global_position.x - from.x, 0.0, global_position.z - from.z)
	if push.length_squared() > 0.01:
		rotation.y = atan2(-push.x, -push.z)
	model.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	model.position = Vector3(0.0, 0.12, 0.0)
	state = State.DOWN
	defeated.emit(self)


func _animate(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length() if state != State.DOWN else 0.0
	_phase += speed / tuning.stride * PI * delta
	var target_swing: float = clampf(speed / 1.4, 0.0, 1.0) * tuning.swing * (1.5 if speed > 2.5 else 1.0)
	_swing = lerpf(_swing, target_swing, 1.0 - exp(-8.0 * delta))
	var fighting: bool = hostile and state in [State.CHASE, State.WINDUP, State.PUNCH, State.STAGGER] and _can_fight()
	_guard = move_toward(_guard, 1.0 if fighting else 0.0, delta * 4.0)
	var arm: float = 0.0
	var twist: float = 0.0
	if state == State.WINDUP:
		var drawn: float = clampf(1.0 - _timer / tuning.windup_time, 0.0, 1.0) * 3.0
		arm = -0.6 * minf(drawn, 1.0)                 # the right arm drawn back...
		twist = WINDUP_TWIST * minf(drawn, 1.0)       # ...and the shoulders turned with it
	elif state == State.PUNCH:
		var progress: float = 1.0 - _timer / tuning.punch_time
		arm = FightPose.arm_out(progress, tuning.punch_hit_at / tuning.punch_time)
		twist = lerpf(WINDUP_TWIST, -0.15, minf(progress * 3.0, 1.0)) * (1.0 - arm * 0.3)
	if state != State.DOWN:
		model.rotation.y = lerpf(model.rotation.y, twist, 1.0 - exp(-20.0 * delta))
	model.set_instance_shader_parameter(&"walk_phase", _phase)
	model.set_instance_shader_parameter(&"swing", _swing)
	model.set_instance_shader_parameter(&"guard", _guard)
	model.set_instance_shader_parameter(&"punch", arm)


# --------------------------------------------------------------------------- helpers

## Someone to fight who is standing (not down, not in a vehicle).
func _can_fight() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method(&"is_down") and target.call(&"is_down"):
		return false
	if target.has_method(&"is_in_vehicle") and target.call(&"is_in_vehicle"):
		return false
	return true


func _target_near(distance: float) -> bool:
	return target != null and is_instance_valid(target) and _to_target().length() < distance


func _to_target() -> Vector3:
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	return to


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 1.0 - exp(-tuning.turn_speed * delta))
