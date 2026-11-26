class_name HumanFigure
extends Node3D
## A person's body (M8): the rigged model in `look` (tools/blender/humans.py, baked by
## HumanBaker), coloured per person, animated by an AnimationTree that every figure shares:
## - moving: idle, walk, run and sprint blended by speed (set_speed), played a little faster or
##   slower to match it;
## - a whole-body state (set_state): move, sit, drive, down (lying), fall (in the air), talk;
## - fists up over any of them (set_guard 0-1: arms and chest only);
## - one-off actions over everything (play): punch, windup, hit, jump, land, knocked, getup.
## The model faces +Z, like the old shader figures. Its owner (a pedestrian, the player, ...)
## decides what to show; the figure only shows it.

const STATES: Array[StringName] = [&"move", &"sit", &"drive", &"down", &"fall", &"talk"]
const ACTIONS: Array[StringName] = [&"punch", &"windup", &"hit", &"jump", &"land", &"knocked", &"getup"]
## Speeds (m/s) the locomotion clips are made for.
const IDLE_SPEED: float = 0.0
const WALK_SPEED: float = 1.3
const RUN_SPEED: float = 4.0
const SPRINT_SPEED: float = 6.5
## Bones the guard layer moves.
const GUARD_BONES: Array[String] = ["Chest", "UpperChest", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const SKELETON_PATH: String = "Rig/Skeleton3D"

@export var look: PackedScene

static var _tree_root: AnimationNodeBlendTree

var _model: Node3D
var _body: MeshInstance3D
var _tree: AnimationTree
var _state: StringName = &"move"
var _guard: float = 0.0
var _speed: float = 0.0
var _colours: Dictionary = {}
var _last_action: StringName = &""


func _ready() -> void:
	if look != null and _model == null:
		set_look(look)


## Dresses the figure as the person in `look_scene` (a rigged GLB); keeps the colours.
func set_look(look_scene: PackedScene) -> void:
	look = look_scene
	if _model != null:
		_model.queue_free()
	var parts: Dictionary = HumanBaker.get_parts(look_scene)
	_model = look_scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	var player := _model.find_child("AnimationPlayer", true, false)
	if player != null:
		player.free()                       # the shared tree holds the clips instead
	_body = _model.find_child("Body", true, false) as MeshInstance3D
	_body.mesh = parts["mesh"]
	_body.skin = parts["skin"]
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for key: StringName in _colours:
		_body.set_instance_shader_parameter(key, _colours[key])
	_tree = AnimationTree.new()
	_tree.name = "Animation"
	_tree.add_animation_library(&"", parts["library"])
	_tree.tree_root = _shared_tree()
	_model.add_child(_tree)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.active = true
	set_state(_state)
	set_speed(_speed)
	set_guard(_guard)


## The figure's colours: any of top_color, bottom_color, skin_color, hair_color.
func set_colours(colours: Dictionary) -> void:
	for key: StringName in colours:
		_colours[key] = colours[key]
		if _body != null:
			_body.set_instance_shader_parameter(key, colours[key])


func get_colour(key: StringName) -> Color:
	return _colours.get(key, Color.WHITE)


func has_body() -> bool:
	return _body != null and _body.mesh != null


func get_body() -> MeshInstance3D:
	return _body


func get_skeleton() -> Skeleton3D:
	return _model.get_node_or_null(SKELETON_PATH) as Skeleton3D if _model != null else null


## How fast the person moves over the ground (m/s): picks and blends the gait.
func set_speed(speed: float) -> void:
	_speed = maxf(speed, 0.0)
	if _tree == null:
		return
	_tree.set(&"parameters/loco/blend_position", _speed)
	var pace: float = 1.0
	if _speed > 0.2 and _speed < 2.6:
		pace = clampf(_speed / WALK_SPEED, 0.8, 1.35)
	elif _speed >= 2.6 and _speed < 5.2:
		pace = clampf(_speed / RUN_SPEED, 0.85, 1.25)
	elif _speed >= 5.2:
		pace = clampf(_speed / SPRINT_SPEED, 0.85, 1.25)
	_tree.set(&"parameters/pace/scale", pace)


## move, sit, drive, down, fall or talk.
func set_state(state: StringName) -> void:
	if state not in STATES:
		push_error("HumanFigure: unknown state %s" % state)
		return
	_state = state
	if _tree != null and str(_tree.get(&"parameters/state/current_state")) != str(state):
		_tree.set(&"parameters/state/transition_request", String(state))


func get_state() -> StringName:
	return _state


## Fists up (1) or down (0), over whatever the body is doing.
func set_guard(amount: float) -> void:
	_guard = clampf(amount, 0.0, 1.0)
	if _tree != null:
		_tree.set(&"parameters/guard/blend_amount", _guard)


func get_guard() -> float:
	return _guard


## Plays a one-off action over everything else: punch, windup, hit, jump, land, knocked, getup.
func play(action: StringName) -> void:
	if action not in ACTIONS:
		push_error("HumanFigure: unknown action %s" % action)
		return
	_last_action = action
	if _tree == null:
		return
	_tree.set(&"parameters/action/transition_request", String(action))
	_tree.set(&"parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Stops a one-off action at once (a punch cut short by a blow).
func stop_action() -> void:
	if _tree != null:
		_tree.set(&"parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Whether a one-off action (`action`, or any if empty) is playing.
func is_playing(action: StringName = &"") -> bool:
	if _tree == null or not bool(_tree.get(&"parameters/shot/active")):
		return false
	return action == &"" or action == _last_action


## The tree every figure shares (its per-figure settings live in each AnimationTree's parameters).
static func _shared_tree() -> AnimationNodeBlendTree:
	if _tree_root != null:
		return _tree_root
	var tree := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = 8.0
	loco.sync = true
	for point: Array in [[&"idle", IDLE_SPEED], [&"walk", WALK_SPEED], [&"run", RUN_SPEED], [&"sprint", SPRINT_SPEED]]:
		loco.add_blend_point(_clip(point[0]), point[1])
	tree.add_node(&"loco", loco)
	tree.add_node(&"pace", AnimationNodeTimeScale.new())
	tree.connect_node(&"pace", 0, &"loco")
	var state := AnimationNodeTransition.new()
	state.input_count = STATES.size()
	state.xfade_time = 0.25
	for i: int in STATES.size():
		state.set_input_name(i, String(STATES[i]))
		if i > 0:
			tree.add_node(STATES[i], _clip(STATES[i]))
	tree.add_node(&"state", state)
	tree.connect_node(&"state", 0, &"pace")
	for i: int in range(1, STATES.size()):
		tree.connect_node(&"state", i, STATES[i])
	var guard := AnimationNodeBlend2.new()
	guard.filter_enabled = true
	for bone: String in GUARD_BONES:
		guard.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)
	tree.add_node(&"guard", guard)
	tree.add_node(&"guard_clip", _clip(&"guard"))
	tree.connect_node(&"guard", 0, &"state")
	tree.connect_node(&"guard", 1, &"guard_clip")
	var action := AnimationNodeTransition.new()
	action.input_count = ACTIONS.size()
	action.xfade_time = 0.0
	action.allow_transition_to_self = true
	for i: int in ACTIONS.size():
		action.set_input_name(i, String(ACTIONS[i]))
		tree.add_node(StringName("do_" + ACTIONS[i]), _clip(ACTIONS[i]))
	tree.add_node(&"action", action)
	for i: int in ACTIONS.size():
		tree.connect_node(&"action", i, StringName("do_" + ACTIONS[i]))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.06
	shot.fadeout_time = 0.14
	tree.add_node(&"shot", shot)
	tree.connect_node(&"shot", 0, &"guard")
	tree.connect_node(&"shot", 1, &"action")
	tree.connect_node(&"output", 0, &"shot")
	_tree_root = tree
	return tree


static func _clip(clip: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	return node
