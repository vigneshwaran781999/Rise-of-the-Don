class_name VehicleLights
extends Node3D
## Headlights (two spotlights plus glowing lenses), tail lights that brighten under braking,
## and reverse lights. The lens materials from the Blender model (veh_headlight,
## veh_taillight, veh_reverselight) are copied per car, so each car glows on its own.
## Must be a direct child of a VehicleController; the spotlights are this node's children.

const HEADLIGHT_MATERIAL: String = "veh_headlight"
const TAILLIGHT_MATERIAL: String = "veh_taillight"
const REVERSE_MATERIAL: String = "veh_reverselight"

@export var headlight_glow: float = 5.0
@export var tail_glow_off: float = 0.3
@export var tail_glow_running: float = 1.4
@export var tail_glow_braking: float = 5.0
@export var reverse_glow: float = 3.0

var _vehicle: VehicleController
var _head: Array[StandardMaterial3D] = []
var _tail: Array[StandardMaterial3D] = []
var _reverse: Array[StandardMaterial3D] = []
var _beams: Array[SpotLight3D] = []


func _ready() -> void:
	_vehicle = get_parent() as VehicleController
	for child: Node in get_children():
		if child is SpotLight3D:
			_beams.append(child as SpotLight3D)
	_collect_lenses(_vehicle.get_node("Model"))
	_vehicle.headlights_changed.connect(_on_headlights_changed)
	_on_headlights_changed(_vehicle.are_headlights_on())


func are_beams_visible() -> bool:
	return not _beams.is_empty() and _beams[0].visible


func get_tail_glow() -> float:
	return _tail[0].emission_energy_multiplier if not _tail.is_empty() else 0.0


func get_reverse_glow() -> float:
	return _reverse[0].emission_energy_multiplier if not _reverse.is_empty() else 0.0


func get_headlight_glow() -> float:
	return _head[0].emission_energy_multiplier if not _head.is_empty() else 0.0


func _physics_process(_delta: float) -> void:
	var tail: float = tail_glow_running if _vehicle.are_headlights_on() else tail_glow_off
	if _vehicle.is_braking():
		tail = tail_glow_braking
	_set_glow(_tail, tail)
	_set_glow(_reverse, reverse_glow if _vehicle.is_reversing() else 0.0)


func _on_headlights_changed(on: bool) -> void:
	for beam: SpotLight3D in _beams:
		beam.visible = on
	_set_glow(_head, headlight_glow if on else 0.0)


func _set_glow(materials: Array[StandardMaterial3D], energy: float) -> void:
	for mat: StandardMaterial3D in materials:
		mat.emission_energy_multiplier = energy


## Gives every lens surface in the model its own material copy, sorted by kind.
func _collect_lenses(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var list: Array[StandardMaterial3D]
			match source.resource_name:
				HEADLIGHT_MATERIAL:
					list = _head
				TAILLIGHT_MATERIAL:
					list = _tail
				REVERSE_MATERIAL:
					list = _reverse
				_:
					continue
			var copy := source.duplicate() as StandardMaterial3D
			copy.emission_enabled = true
			mesh_instance.set_surface_override_material(surface, copy)
			list.append(copy)
