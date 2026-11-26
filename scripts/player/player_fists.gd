class_name PlayerFists
extends Node
## The player's fists (GDD §4 Punch, M7): the attack button throws a punch. The player turns to
## the nearest person in front within reach (a little help aiming), and part-way through the swing
## the blow lands on whoever is in front: anything in the "hittable" group with a
## take_hit(damage, from, attacker) method (pedestrians, police officers, fighters).
## Must be a direct child of the PlayerController.

## People within this distance and this angle of the way the player faces are turned to.
const AIM_DISTANCE: float = 2.6
const AIM_DEGREES: float = 70.0
const HITTABLE_GROUP: StringName = &"hittable"

## The blow landed on `target`.
signal punch_landed(target: Node3D)

var _player: PlayerController
var _query := PhysicsShapeQueryParameters3D.new()
var _landed: bool = true


func _ready() -> void:
	_player = get_parent() as PlayerController
	var sphere := SphereShape3D.new()
	sphere.radius = _player.tuning.punch_radius
	_query.shape = sphere
	_query.collision_mask = 8              # people: pedestrians, officers, fighters
	_query.exclude = [_player.get_rid()]


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("attack") and _player.start_punch():
		_aim()
		_landed = false
		AudioManager.play_sfx(&"punch_swing", -8.0, randf_range(0.9, 1.1))
	if not _landed and _player.get_punch_progress() * _player.tuning.punch_time >= _player.tuning.punch_hit_at:
		_landed = true
		_strike()


## Throws a punch now (tests, which can't press the mouse button).
func punch() -> bool:
	if not _player.start_punch():
		return false
	_aim()
	_landed = false
	return true


## Turns to the nearest hittable person roughly in front.
func _aim() -> void:
	var facing: Vector3 = _player.get_facing()
	var best: Node3D = null
	var best_d: float = AIM_DISTANCE
	for node: Node in get_tree().get_nodes_in_group(HITTABLE_GROUP):
		var other := node as Node3D
		if other == null or (other.has_method(&"is_down") and other.call(&"is_down")):
			continue
		var to: Vector3 = other.global_position - _player.global_position
		to.y = 0.0
		var d: float = to.length()
		if d < best_d and d > 0.01 and rad_to_deg(facing.angle_to(to / d)) < AIM_DEGREES:
			best_d = d
			best = other
	if best != null:
		var to: Vector3 = best.global_position - _player.global_position
		_player.model.rotation.y = atan2(-to.x, -to.z)


## The blow: the nearest hittable thing in the sphere in front of the player.
func _strike() -> void:
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var centre: Vector3 = _player.global_position + _player.get_facing() * _player.tuning.punch_reach + Vector3.UP * 1.1
	_query.transform = Transform3D(Basis.IDENTITY, centre)
	var target: Node3D = null
	var best: float = INF
	for hit: Dictionary in space.intersect_shape(_query, 8):
		var body := hit["collider"] as Node3D
		if body == null or not body.is_in_group(HITTABLE_GROUP) or not body.has_method(&"take_hit"):
			continue
		var d: float = body.global_position.distance_to(centre)
		if d < best:
			best = d
			target = body
	if target == null:
		return
	target.call(&"take_hit", _player.tuning.punch_damage, _player.global_position, _player)
	AudioManager.play_sfx(&"punch_hit", -2.0, randf_range(0.9, 1.1))
	punch_landed.emit(target)
