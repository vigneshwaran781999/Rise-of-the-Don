class_name TrafficSignal
extends Node3D
## Traffic lights at one junction (GDD §6, M3). Two phases: traffic travelling along Z
## (north-south, axis 0) gets green while east-west (axis 1) waits, then the other way round,
## each with amber and an all-red gap. AI traffic (M4) asks get_light() for the axis of its
## stop line (LaneGraph.signal_axis and junction id).
##
## Children are signal poles (instances of prop_signal_pole.glb) with the metadata
## "signal_axis" (0 or 1). Each axis gets its own red/amber/green lamp materials.

enum Light { RED, AMBER, GREEN }

const GROUP: StringName = &"traffic_signals"
const LAMP_NAMES: Array[String] = ["sig_red", "sig_amber", "sig_green"]
const LAMP_ON: float = 4.5
const LAMP_OFF: float = 0.04

@export var junction_id: int = -1
@export var timing: SignalTiming
## Seconds into the cycle at load, so neighbouring junctions don't all change together.
@export var time_offset: float = 0.0

## Loaded signals by junction id (traffic asks for the junction ahead of it).
static var _by_junction: Dictionary = {}

var _time: float = 0.0
## _lamps[axis][Light] -> StandardMaterial3D
var _lamps: Array = [[], []]
var _shown: Array[int] = [-1, -1]


func _ready() -> void:
	add_to_group(GROUP)
	_time = time_offset
	for axis: int in 2:
		for i: int in 3:
			(_lamps[axis] as Array).append(null)
	for child: Node in get_children():
		if not child.has_meta(&"signal_axis"):
			continue
		var axis: int = int(child.get_meta(&"signal_axis"))
		for node: Node in child.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			for surface: int in mesh_instance.mesh.get_surface_count():
				var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null:
					continue
				var lamp: int = LAMP_NAMES.find(source.resource_name)
				if lamp < 0:
					continue
				if _lamps[axis][lamp] == null:
					var copy := source.duplicate() as StandardMaterial3D
					copy.emission_enabled = true
					_lamps[axis][lamp] = copy
				mesh_instance.set_surface_override_material(surface, _lamps[axis][lamp])
	_update_lamps()


func _enter_tree() -> void:
	_by_junction[junction_id] = self


func _exit_tree() -> void:
	if _by_junction.get(junction_id) == self:
		_by_junction.erase(junction_id)


## The loaded signal at a junction, or null (unsignalized, or its chunk isn't loaded).
static func find(junction: int) -> TrafficSignal:
	return _by_junction.get(junction) as TrafficSignal


func _physics_process(delta: float) -> void:
	_time += delta
	_update_lamps()


## The light shown to traffic travelling along `axis` (0 = along Z, 1 = along X) right now.
func get_light(axis: int) -> Light:
	return light_at(_time, axis)


## The light for `axis` at `time` seconds into this signal's clock.
func light_at(time: float, axis: int) -> Light:
	var g: float = timing.green_seconds
	var a: float = timing.amber_seconds
	var r: float = timing.all_red_seconds
	var t: float = fposmod(time, timing.cycle_seconds())
	var phase_axis: int = 0
	if t >= g + a + r:
		t -= g + a + r
		phase_axis = 1
	if axis != phase_axis or t >= g + a:
		return Light.RED
	return Light.GREEN if t < g else Light.AMBER


## Jumps the signal's clock (tests use this instead of waiting for a whole cycle).
func set_time(time: float) -> void:
	_time = time
	_update_lamps()


## Glow of one lamp for one axis (for tests): high when lit.
func get_lamp_energy(axis: int, light: Light) -> float:
	var mat := _lamps[axis][light] as StandardMaterial3D
	return mat.emission_energy_multiplier if mat != null else 0.0


func _update_lamps() -> void:
	for axis: int in 2:
		var light: int = get_light(axis)
		if light == _shown[axis]:
			continue
		_shown[axis] = light
		for lamp: int in 3:
			var mat := _lamps[axis][lamp] as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = LAMP_ON if lamp == light else LAMP_OFF
