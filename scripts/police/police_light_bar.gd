class_name PoliceLightBar
extends Node3D
## A police car's roof light bar and siren. While `active` the red and blue lenses flash in turn,
## a small light flashes red and blue around the car and the siren wails. Child of the car.

const BAR_SCENE: PackedScene = preload("res://assets/models/vehicles/veh_police_lightbar.glb")
const FLASH_HZ: float = 3.0
const LENS_GLOW: float = 9.0

static var _siren: AudioStreamWAV

var active: bool = false:
	set(value):
		active = value
		_apply()

var _red: Array[StandardMaterial3D] = []
var _blue: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _siren_player: AudioStreamPlayer3D
var _time: float = 0.0


func _ready() -> void:
	name = "LightBar"
	var car := get_parent() as VehicleController
	position = Vector3(0.0, _roof_height(car), -0.15)
	var bar := BAR_SCENE.instantiate() as Node3D
	add_child(bar)
	for node: Node in bar.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not (source.resource_name in ["police_red", "police_blue"]):
				continue
			var copy := source.duplicate() as StandardMaterial3D
			copy.emission_enabled = true
			mesh_instance.set_surface_override_material(surface, copy)
			(_red if source.resource_name == "police_red" else _blue).append(copy)
	_light = OmniLight3D.new()
	_light.omni_range = 9.0
	_light.light_energy = 2.5
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.4, 0.0)
	add_child(_light)
	if _siren == null:
		_siren = AudioSynth.siren_loop()
	_siren_player = AudioStreamPlayer3D.new()
	_siren_player.stream = _siren
	_siren_player.bus = &"SFX"
	_siren_player.unit_size = 18.0
	_siren_player.max_distance = 180.0
	_siren_player.volume_db = -4.0
	add_child(_siren_player)
	_apply()


func is_siren_on() -> bool:
	return _siren_player != null and _siren_player.playing


func _process(delta: float) -> void:
	if not active:
		return
	_time += delta
	var red_turn: bool = int(_time * FLASH_HZ * 2.0) % 2 == 0
	_set_glow(_red, LENS_GLOW if red_turn else 0.3)
	_set_glow(_blue, 0.3 if red_turn else LENS_GLOW)
	_light.light_color = Color(1.0, 0.15, 0.2) if red_turn else Color(0.2, 0.35, 1.0)


func _apply() -> void:
	if _light == null:
		return
	_light.visible = active
	if not active:
		_set_glow(_red, 0.2)
		_set_glow(_blue, 0.2)
	if active and not _siren_player.playing:
		_siren_player.play()
	elif not active and _siren_player.playing:
		_siren_player.stop()


func _set_glow(materials: Array[StandardMaterial3D], energy: float) -> void:
	for material: StandardMaterial3D in materials:
		material.emission_energy_multiplier = energy


## Top of the car's body, in the car's space.
static func _roof_height(car: VehicleController) -> float:
	var top: float = 0.95
	var model := car.get_node_or_null("Model") as Node3D
	if model == null:
		return top
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			top = maxf(top, (model.transform * mesh_instance.transform * mesh_instance.mesh.get_aabb()).end.y)
	return top
