class_name MissionDirector
extends Node3D
## Makes missions happen in the world (GDD §8); MissionManager keeps the progress.
## - On offer: a magenta start marker (and the giver) for every mission the player can start;
##   walking into one on foot starts it.
## - Running: puts the player at the checkpoint, brings in the mission's people and vehicles,
##   and runs the current objective: a cyan beam to go to, a diamond over the person to talk to
##   or the car to get in, the talk prompt and dialogue, carried items, the time limit, and
##   failure when a vehicle that must survive is wrecked.
## The HUD shows what it announces through the signals below.

signal objective_text_changed(text: String)
signal hint_requested(text: String)
## Interact prompt: action name and text ("" = hide).
signal prompt_changed(action: String, text: String)
## Where the HUD's waypoint arrow points (null = nowhere).
signal waypoint_changed(target: Node3D)
## Seconds left on the objective's clock (negative = no clock).
signal timer_changed(seconds_left: float)

const TALK_REACH: float = 2.6
const START_RADIUS: float = 1.6
## In a vehicle, the goal only counts once the car has (nearly) stopped in it.
const STOP_SPEED_KMH: float = 12.0
## People who were in a finished mission leave once the player is this far away (or not looking).
const LINGER_DISTANCE: float = 45.0

## Models for contacts, by MissionContact.look: man, woman, older man.
@export var looks: Array[PackedScene] = []

var dialogue: DialoguePlayer

var _player: PlayerController
var _world: District
var _offers: Dictionary = {}          # MissionData -> [start marker, giver or null]
var _contacts: Dictionary = {}        # StringName -> MissionContactNPC (running mission)
var _vehicles: Dictionary = {}        # StringName -> VehicleController (running mission)
var _lingering: Array[Node3D] = []
var _items: Array[StringName] = []
var _carried: MeshInstance3D
var _mission: MissionData
var _objective: MissionObjective
var _goal: MissionMarker
var _goal_position := Vector3.ZERO     # where the running GO_TO goes (its position, or a pick)
var _checkpoint_index: int = 0         # CHECKPOINTS: the next one to pass
var _scene: DialogueScene
var _rng := RandomNumberGenerator.new()
var _time_left: float = -1.0
var _talking_to: MissionContactNPC
var _passed: bool = false
var _start_armed: bool = true
var _text: String = ""
var _prompt_action: String = ""
var _prompt_text: String = ""
var _waypoint: Node3D


func _ready() -> void:
	add_to_group(GpsNavigator.BLIP_GROUP)
	_rng.randomize()
	dialogue = DialoguePlayer.new()
	dialogue.name = "Dialogue"
	add_child(dialogue)
	dialogue.line_started.connect(_on_line_started)
	dialogue.finished.connect(_on_dialogue_finished)
	_scene = DialogueScene.new()
	_scene.name = "DialogueScene"
	add_child(_scene)


func setup(player: PlayerController, world: District) -> void:
	_player = player
	_world = world
	MissionManager.mission_started.connect(_on_mission_started)
	MissionManager.objective_started.connect(_on_objective_started)
	MissionManager.mission_failed.connect(_on_mission_failed)
	MissionManager.mission_passed.connect(_on_mission_passed)
	MissionManager.mission_ended.connect(_on_mission_ended)
	MissionManager.availability_changed.connect(_refresh_offers)
	_refresh_offers()


func _exit_tree() -> void:
	for pair: Array in [[MissionManager.mission_started, _on_mission_started],
			[MissionManager.objective_started, _on_objective_started],
			[MissionManager.mission_failed, _on_mission_failed],
			[MissionManager.mission_passed, _on_mission_passed],
			[MissionManager.mission_ended, _on_mission_ended],
			[MissionManager.availability_changed, _refresh_offers]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func get_vehicle(vehicle_id: StringName) -> VehicleController:
	var car: VehicleController = _vehicles.get(vehicle_id)
	return car if car != null and is_instance_valid(car) else null


func get_contact(contact_id: StringName) -> MissionContactNPC:
	var npc: MissionContactNPC = _contacts.get(contact_id)
	return npc if npc != null and is_instance_valid(npc) else null


func get_items() -> Array[StringName]:
	return _items.duplicate()


func get_time_left() -> float:
	return _time_left


func get_objective_text() -> String:
	return _text


## The giver standing at a mission's start marker while it is on offer (or null).
## The dialogue scene (camera and letterbox) used by TALK_TO objectives marked `scene`.
func get_scene() -> DialogueScene:
	return _scene


## Where the running GO_TO objective goes (its position, or the address picked this time).
func get_goal_position() -> Vector3:
	return _goal_position


## Whether a mission action has the interact key now (a talk or hand-over prompt, or dialogue
## playing): other things the player could do with it wait.
func has_prompt() -> bool:
	return _prompt_action != "" or (dialogue != null and dialogue.is_playing())


func get_offer_giver(mission: MissionData) -> MissionContactNPC:
	var offer: Array = _offers.get(mission, [])
	return offer[1] if offer.size() > 1 else null


func has_offer(mission: MissionData) -> bool:
	return _offers.has(mission)


## Map blips (minimap and full map): missions on offer, and where the current objective is.
func get_map_blips() -> Array[Dictionary]:
	var blips: Array[Dictionary] = []
	for mission: MissionData in _offers:
		blips.append({"position": mission.start_position, "kind": &"mission", "label": mission.title})
	if _mission != null and _waypoint != null and is_instance_valid(_waypoint) and _waypoint.is_inside_tree():
		blips.append({"position": _waypoint.global_position, "kind": &"objective", "label": _mission.title})
	return blips


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# A talk prompt wins (it cuts off any other lines); otherwise interact skips the current line.
	if _prompt_action == "interact" and _objective != null and _objective.type == MissionObjective.Type.TALK_TO:
		_start_talk(get_contact(_objective.contact))
		get_viewport().set_input_as_handled()
	elif dialogue.is_playing():
		dialogue.skip()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	_update_lingering()
	if _mission == null:
		_check_offers()
		return
	if MissionManager.is_failed() or _objective == null:
		return
	if _time_left >= 0.0:
		_time_left = maxf(0.0, _time_left - delta)
		timer_changed.emit(_time_left)
		if _time_left <= 0.0:
			MissionManager.fail("You ran out of time.")
			return
	match _objective.type:
		MissionObjective.Type.GO_TO:
			_update_go_to()
		MissionObjective.Type.TALK_TO:
			_update_talk_to()
		MissionObjective.Type.ENTER_VEHICLE:
			_update_enter_vehicle()
		MissionObjective.Type.CHECKPOINTS:
			_update_checkpoints()
		MissionObjective.Type.LOSE_WANTED:
			_update_lose_wanted()
		MissionObjective.Type.BUY_PROPERTY:
			_update_buy_property()


# --------------------------------------------------------------------------- objectives

func _update_go_to() -> void:
	var goal: Vector3 = _goal_position
	if _objective.mode == MissionObjective.Mode.IN_VEHICLE:
		var car: VehicleController = get_vehicle(_objective.vehicle)
		var in_right_car: bool = _player.is_in_vehicle() and (car == null or _player.vehicle == car)
		if not in_right_car:
			if car != null:
				var spec: MissionVehicle = _mission.get_vehicle(_objective.vehicle)
				_show("Get back in %s." % spec.label, _car_marker(car))
			else:
				_show("Get in a vehicle.", _goal)
			return
	var here: Vector3 = _player.vehicle.global_position if _player.is_in_vehicle() else _player.global_position
	var inside: bool = _flat(here).distance_to(_flat(goal)) <= _objective.radius and absf(here.y - goal.y) < 4.0
	if not inside:
		_show(_objective.text, _goal)
	elif _objective.mode == MissionObjective.Mode.ON_FOOT and _player.is_in_vehicle():
		_show("Get out of the vehicle.", _goal)
	elif _player.is_in_vehicle() and _player.vehicle.get_speed_kmh() > STOP_SPEED_KMH:
		_show("Stop in the marker.", _goal)
	else:
		_complete()


## CHECKPOINTS: through each in order; the goal marker moves on to the next.
func _update_checkpoints() -> void:
	if not _in_required_vehicle():
		return
	var here: Vector3 = _player.vehicle.global_position if _player.is_in_vehicle() else _player.global_position
	var point: Vector3 = _objective.checkpoints[_checkpoint_index]
	if _flat(here).distance_to(_flat(point)) > _objective.radius:
		_show(_checkpoint_text(), _goal)
		return
	_checkpoint_index += 1
	if _checkpoint_index >= _objective.checkpoints.size():
		_complete()
		return
	AudioManager.play_ui(&"objective")
	_goal_position = _objective.checkpoints[_checkpoint_index]
	_goal.global_position = _goal_position
	_show(_checkpoint_text(), _goal)


func _checkpoint_text() -> String:
	return "%s (%d/%d)" % [_objective.text, _checkpoint_index + 1, _objective.checkpoints.size()]


## In the vehicle an IN_VEHICLE objective needs; otherwise says what to get back into.
func _in_required_vehicle() -> bool:
	if _objective.mode != MissionObjective.Mode.IN_VEHICLE:
		return true
	var car: VehicleController = get_vehicle(_objective.vehicle)
	if _player.is_in_vehicle() and (car == null or _player.vehicle == car):
		return true
	if car != null:
		_show("Get back in %s." % _mission.get_vehicle(_objective.vehicle).label, _car_marker(car))
	else:
		_show("Get in a vehicle.", _goal)
	return false


func _update_lose_wanted() -> void:
	if not WantedSystem.is_wanted():
		_complete()


func _update_buy_property() -> void:
	if EconomyManager.owns(_objective.property):
		_complete()
	else:
		_show(_objective.text, _goal)


func _update_talk_to() -> void:
	var npc: MissionContactNPC = get_contact(_objective.contact)
	if npc == null:
		return
	if dialogue.is_playing() and _talking_to == npc:
		_set_prompt("", "")
		if _scene.is_playing():
			_show(_text, null)      # no diamond or screen arrow in a dialogue scene
		return
	var near: bool = _flat(npc.global_position).distance_to(_flat(_player.global_position)) <= TALK_REACH
	if near and not _player.is_in_vehicle() and _player.can_enter_vehicle():
		var verb: String = ("GIVE %s THE %s" % [npc.data.display_name, _objective.take_item]) if _objective.take_item != &"" \
			else "TALK TO %s" % npc.data.display_name
		_set_prompt("interact", verb.to_upper())
	else:
		_set_prompt("", "")
	var close_in_car: bool = _player.is_in_vehicle() and _flat(npc.global_position).distance_to(_flat(_player.global_position)) < 12.0
	_show("Get out to talk." if close_in_car else _objective.text, _target_marker(npc))


func _update_enter_vehicle() -> void:
	var car: VehicleController = get_vehicle(_objective.vehicle)
	if car == null:
		return
	_show(_objective.text, _car_marker(car))
	if _player.vehicle == car:
		_complete()


func _start_talk(npc: MissionContactNPC) -> void:
	if npc == null:
		return
	_talking_to = npc
	_set_prompt("", "")
	if _objective.scene and not _objective.lines.is_empty():
		_scene.play(_player, npc)
	if _objective.lines.is_empty():
		_on_dialogue_finished()
	else:
		dialogue.play(_objective.lines)


func _on_dialogue_finished() -> void:
	_scene.stop()
	if _talking_to == null or _objective == null or _objective.type != MissionObjective.Type.TALK_TO:
		return
	_talking_to = null
	var items: Array[StringName] = _items.duplicate()
	if _objective.take_item != &"":
		items.erase(_objective.take_item)
	if _objective.give_item != &"" and not items.has(_objective.give_item):
		items.append(_objective.give_item)
	_set_items(items)
	_complete()


func _on_line_started(speaker: String, _text_line: String) -> void:
	for npc: MissionContactNPC in _all_npcs():
		npc.talking = speaker != "" and npc.data.display_name.to_upper() == speaker.to_upper()


func _complete() -> void:
	_set_prompt("", "")
	MissionManager.complete_objective()


# --------------------------------------------------------------------------- mission lifecycle

func _on_mission_started(mission: MissionData, checkpoint: int) -> void:
	_clear_running(true, false)
	_mission = mission
	_passed = false
	_clear_offers()
	# A mission with the police in it starts (or restarts) with a clean record.
	if mission.uses_police():
		WantedSystem.clear()
	var spot: Array = mission.checkpoint_spot(checkpoint)
	var pos: Vector3 = spot[0]
	if checkpoint > 0 or _player.is_in_vehicle() or _flat(_player.global_position).distance_to(_flat(pos)) > 6.0:
		_place_player(pos, float(spot[1]))
	for contact: MissionContact in ([mission.giver] if mission.giver != null else []) + mission.contacts:
		_contacts[contact.id] = _spawn_contact(contact)
	for spec: MissionVehicle in mission.vehicles:
		if _used_from(mission, spec.id, checkpoint):
			_vehicles[spec.id] = _spawn_vehicle(spec)
	_set_items(mission.items_before(checkpoint))
	if checkpoint == 0 and not mission.intro_lines.is_empty():
		dialogue.play(mission.intro_lines)


func _on_objective_started(mission: MissionData, index: int) -> void:
	_objective = mission.objectives[index]
	_time_left = _objective.time_limit if _objective.time_limit > 0.0 else -1.0
	timer_changed.emit(_time_left)
	_talking_to = null
	if _goal != null:
		_goal.queue_free()
		_goal = null
	_checkpoint_index = 0
	var marked: bool = true
	match _objective.type:
		MissionObjective.Type.GO_TO:
			_goal_position = _objective.pick_position(_rng)
		MissionObjective.Type.CHECKPOINTS:
			_goal_position = _objective.checkpoints[0]
		MissionObjective.Type.BUY_PROPERTY:
			_goal_position = _objective.position
		_:
			marked = false
	if marked:
		_goal = MissionMarker.new()
		_goal.name = "Goal"
		_goal.setup(MissionMarker.Kind.GOAL, _objective.radius)
		add_child(_goal)
		_goal.global_position = _goal_position
	if _objective.wanted_level > WantedSystem.level:
		WantedSystem.set_level(_objective.wanted_level, _player.global_position)
	_text = ""
	_show(_checkpoint_text() if _objective.type == MissionObjective.Type.CHECKPOINTS else _objective.text, _goal)
	if _objective.hint != "":
		hint_requested.emit(ControlsPanel.fill_keys(_objective.hint))
	if index > 0:
		AudioManager.play_ui(&"objective")


func _on_mission_failed(_mission_data: MissionData, _reason: String) -> void:
	dialogue.stop()
	_scene.stop()
	_talking_to = null
	_set_prompt("", "")
	timer_changed.emit(-1.0)
	_show("", null)


func _on_mission_passed(mission: MissionData) -> void:
	_passed = true
	if not mission.outro_lines.is_empty():
		dialogue.play(mission.outro_lines)


func _on_mission_ended(_mission_data: MissionData) -> void:
	_scene.stop()
	if not _passed:
		dialogue.stop()
	_clear_running(not _passed, true)
	_mission = null
	_objective = null
	_start_armed = false      # don't restart at once if the player stands in the marker
	timer_changed.emit(-1.0)
	_show("", null)
	_set_prompt("", "")


## Removes what the running mission put in the world: vehicles too if `remove_vehicles` (the player
## gets out first, as on a retry; after a pass the borrowed car stays where it is), and its people
## at once, or once out of sight if `linger`.
func _clear_running(remove_vehicles: bool, linger: bool) -> void:
	for npc: MissionContactNPC in _contacts.values():
		if not is_instance_valid(npc):
			continue
		npc.talking = false
		if linger:
			_lingering.append(npc)
		else:
			npc.queue_free()
	_contacts.clear()
	for car: VehicleController in _vehicles.values():
		if not is_instance_valid(car):
			continue
		var marker: Node = car.get_meta(&"mission_marker") if car.has_meta(&"mission_marker") else null
		if marker != null and is_instance_valid(marker):
			marker.queue_free()
		for connection: Dictionary in (car.get_node("Damage") as VehicleDamage).wrecked.get_connections():
			(car.get_node("Damage") as VehicleDamage).wrecked.disconnect(connection["callable"])
		if remove_vehicles:
			if _player.vehicle == car:
				_player.exit_vehicle(_player.get_node("VehicleInteractor").find_exit_position(car))
			car.queue_free()
	_vehicles.clear()
	if _goal != null:
		_goal.queue_free()
		_goal = null
	_waypoint = null
	_set_items([])


# --------------------------------------------------------------------------- offers

func _refresh_offers() -> void:
	if _player == null:
		return
	var wanted: Array[MissionData] = []
	if not MissionManager.is_active():
		wanted = MissionManager.get_available()
	for mission: MissionData in _offers.keys():
		if not wanted.has(mission):
			_remove_offer(mission)
	for mission: MissionData in wanted:
		if _offers.has(mission):
			continue
		var marker := MissionMarker.new()
		marker.name = "Start_%s" % mission.id
		marker.setup(MissionMarker.Kind.START, START_RADIUS)
		add_child(marker)
		marker.global_position = mission.start_position
		var giver: MissionContactNPC = _spawn_contact(mission.giver) if mission.giver != null else null
		_offers[mission] = [marker, giver]


func _clear_offers() -> void:
	for mission: MissionData in _offers.keys():
		_remove_offer(mission)


func _remove_offer(mission: MissionData) -> void:
	var offer: Array = _offers.get(mission, [])
	_offers.erase(mission)
	for node: Variant in offer:
		if node != null and is_instance_valid(node):
			(node as Node).queue_free()


func _check_offers() -> void:
	if _player.is_in_vehicle():
		return
	var here: Vector2 = _flat(_player.global_position)
	var nearest: float = INF
	for mission: MissionData in _offers:
		var distance: float = here.distance_to(_flat(mission.start_position))
		nearest = minf(nearest, distance)
		if _start_armed and distance <= START_RADIUS:
			_start_armed = false
			if EconomyManager.cash < mission.min_cash:
				hint_requested.emit("%s needs %s. Side jobs pay: Selvi at the tiffin stall, Murugan at the garage." % [mission.title, EconomyManager.format(mission.min_cash)])
				return
			MissionManager.start(mission.id)
			return
	if nearest > START_RADIUS + 2.0:
		_start_armed = true


# --------------------------------------------------------------------------- world helpers

func _spawn_contact(contact: MissionContact) -> MissionContactNPC:
	var npc := MissionContactNPC.new()
	npc.setup(contact, looks[clampi(contact.look, 0, looks.size() - 1)])
	npc.watch = _player
	npc.talking = dialogue.is_playing() and dialogue.get_speaker().to_upper() == contact.display_name.to_upper()
	add_child(npc)
	return npc


func _spawn_vehicle(spec: MissionVehicle) -> VehicleController:
	var car := spec.scene.instantiate() as VehicleController
	car.name = "MissionCar_%s" % spec.id
	add_child(car)
	# Yaw 0 faces north (-Z); the car's nose is its +Z.
	car.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(spec.yaw_degrees) + PI), spec.position + Vector3.UP * 0.6))
	(car.get_node("Model") as VehicleModel).set_paint(spec.paint)
	(car.get_node("Damage") as VehicleDamage).wrecked.connect(_on_vehicle_wrecked.bind(spec))
	return car


func _on_vehicle_wrecked(spec: MissionVehicle) -> void:
	if _mission != null and spec.must_survive and not MissionManager.is_failed():
		MissionManager.fail("%s is wrecked." % (spec.label.left(1).to_upper() + spec.label.substr(1)))


## True if objective `checkpoint` or a later one uses vehicle `vehicle_id`.
static func _used_from(mission: MissionData, vehicle_id: StringName, checkpoint: int) -> bool:
	for k: int in range(checkpoint, mission.objectives.size()):
		if mission.objectives[k].vehicle == vehicle_id:
			return true
	return false


## Puts the player (on foot) at `pos` facing `yaw_degrees` (0 = north), camera behind them.
func _place_player(pos: Vector3, yaw_degrees: float) -> void:
	if _player.is_in_vehicle():
		_player.exit_vehicle(pos)
	if _world != null:
		_world.streamer.load_around_now(pos)
	_player.global_position = pos + Vector3.UP * 0.05
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.model.rotation.y = deg_to_rad(yaw_degrees)
	_player.camera_rig.set_view_degrees(yaw_degrees, _player.camera_rig.settings.default_pitch_degrees)
	_player.camera_rig.snap_to_target()


## The parcel (or other item) the player is carrying, held in front of them.
func _set_items(items: Array[StringName]) -> void:
	_items = items
	if _player == null:
		return
	if _items.is_empty():
		if _carried != null and is_instance_valid(_carried):
			_carried.queue_free()
		_carried = null
		return
	if _carried == null or not is_instance_valid(_carried):
		_carried = MeshInstance3D.new()
		_carried.name = "CarriedItem"
		var box := BoxMesh.new()
		box.size = Vector3(0.38, 0.26, 0.3)
		_carried.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("a87b4f")
		material.roughness = 0.9
		_carried.material_override = material
		_player.model.add_child(_carried)
		_carried.position = Vector3(0.0, 1.0, -0.42)   # the player model faces -Z


func _target_marker(node: Node3D) -> MissionMarker:
	return _marker_on(node, 2.35)


func _car_marker(car: VehicleController) -> MissionMarker:
	return _marker_on(car, 2.2)


## The diamond floating over `node` (made on first use, shown only while it is the waypoint).
func _marker_on(node: Node3D, height: float) -> MissionMarker:
	var marker: MissionMarker = node.get_meta(&"mission_marker") if node.has_meta(&"mission_marker") else null
	if marker == null or not is_instance_valid(marker):
		marker = MissionMarker.new()
		marker.name = "MissionTarget"
		marker.setup(MissionMarker.Kind.TARGET, 0.0, height)
		marker.visible = false
		node.add_child(marker)
		node.set_meta(&"mission_marker", marker)
	return marker


## Updates the HUD objective line and the waypoint (only when they change).
func _show(text: String, waypoint: Node3D) -> void:
	if text != _text:
		_text = text
		objective_text_changed.emit(text)
	if waypoint != _waypoint:
		if _waypoint != null and is_instance_valid(_waypoint) and _waypoint is MissionMarker \
				and (_waypoint as MissionMarker).kind == MissionMarker.Kind.TARGET:
			_waypoint.visible = false
		_waypoint = waypoint
		if waypoint != null and waypoint is MissionMarker:
			waypoint.visible = true
		waypoint_changed.emit(waypoint)


func _set_prompt(action: String, text: String) -> void:
	if action == _prompt_action and text == _prompt_text:
		return
	_prompt_action = action
	_prompt_text = text
	prompt_changed.emit(action, text)


func _all_npcs() -> Array[MissionContactNPC]:
	var result: Array[MissionContactNPC] = []
	for npc: MissionContactNPC in _contacts.values():
		if is_instance_valid(npc):
			result.append(npc)
	for offer: Array in _offers.values():
		if offer[1] != null and is_instance_valid(offer[1]):
			result.append(offer[1])
	for node: Node3D in _lingering:
		if is_instance_valid(node) and node is MissionContactNPC:
			result.append(node as MissionContactNPC)
	return result


func _update_lingering() -> void:
	if _lingering.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	for node: Node3D in _lingering.duplicate():
		if not is_instance_valid(node):
			_lingering.erase(node)
			continue
		var distance: float = _flat(node.global_position).distance_to(_flat(_player.global_position))
		var seen: bool = camera != null and camera.is_position_in_frustum(node.global_position + Vector3.UP)
		var speaking: bool = node is MissionContactNPC and (node as MissionContactNPC).talking
		if not speaking and (distance > LINGER_DISTANCE or (not seen and distance > 12.0)):
			_lingering.erase(node)
			node.queue_free()


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
