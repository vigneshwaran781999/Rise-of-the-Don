class_name StreetLightPool
extends Node3D
## Real light from the streetlights at night (GDD §12: pooled lights). Every streetlight's lens
## glows through its material; only the few nearest the camera also get real light: a cone shining
## down from the lamp (a SpotLight3D: on integrated graphics a cone costs about half a sphere of
## the same reach), moved between lamps as the camera travels. How many is the graphics setting's
## (Settings.get_shadow_level(): 2 on Low, 4 above). Lamp positions come from the streamed chunks'
## streetlight batches: the city's warm lamps, and the Industrial Zone's orange sodium lamps (M7).

## Where the light hangs on a streetlight model (just under the lens on the arm).
const LAMP_OFFSET := Vector3(2.45, 7.9, 0.0)
## Streetlight batches in a chunk, and whether their light is sodium orange (both models share
## the same shape, so LAMP_OFFSET fits both).
const BATCHES: Dictionary = {"Props/prop_streetlight": false, "Props/prop_streetlight_sodium": true}

@export var light_range: float = 13.0
## Half-angle of the cone of light (degrees).
@export var light_angle: float = 62.0
@export var light_energy: float = 4.0
@export var light_color: Color = Color(1.0, 0.78, 0.5)
@export var sodium_color: Color = Color(1.0, 0.55, 0.2)

var _lights: Array[SpotLight3D] = []
var _active: int = 0             # how many of the pool may light up (the graphics setting)
var _lamps: Dictionary = {}     # chunk coord -> PackedVector3Array of lamp positions
var _sodium: Dictionary = {}    # chunk coord -> PackedByteArray: 1 where that lamp is sodium
var _streamer: WorldStreamer


func setup(streamer: WorldStreamer, count: int) -> void:
	_streamer = streamer
	for i: int in count:
		var light := SpotLight3D.new()
		light.name = "StreetLight%d" % i
		light.spot_range = light_range
		light.spot_angle = light_angle
		light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)          # shining straight down
		light.light_energy = light_energy
		light.light_color = light_color
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
	_active = mini(count, int(Settings.get_shadow_level()[4]))
	Settings.changed.connect(func(key: StringName) -> void:
		if key == &"graphics":
			_active = mini(_lights.size(), int(Settings.get_shadow_level()[4])))
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(func(c: Vector2i) -> void:
		_lamps.erase(c)
		_sodium.erase(c))
	for c: Vector2i in streamer.get_loaded_coords():
		_on_chunk_loaded(c)


## Lights the `strength` (0-1) share of the pool's lamps nearest `around`.
func update(around: Vector3, strength: float) -> void:
	if strength < 0.02:
		for light: SpotLight3D in _lights:
			light.visible = false
		return
	var candidates: Array = []
	for c: Vector2i in _lamps:
		var positions: PackedVector3Array = _lamps[c]
		var sodium: PackedByteArray = _sodium[c]
		for k: int in positions.size():
			candidates.append([positions[k].distance_squared_to(around), positions[k], sodium[k] == 1])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i: int in _lights.size():
		var light: SpotLight3D = _lights[i]
		light.visible = i < candidates.size() and i < _active
		if light.visible:
			light.global_position = candidates[i][1]
			light.light_energy = light_energy * strength
			light.light_color = sodium_color if candidates[i][2] else light_color


func get_lit_count() -> int:
	var count: int = 0
	for light: SpotLight3D in _lights:
		count += 1 if light.visible else 0
	return count


func get_lamp_count() -> int:
	var count: int = 0
	for positions: PackedVector3Array in _lamps.values():
		count += positions.size()
	return count


func _on_chunk_loaded(c: Vector2i) -> void:
	var chunk: Node = _streamer.get_chunk(c)
	var positions := PackedVector3Array()
	var sodium := PackedByteArray()
	for path: String in BATCHES:
		var batch := chunk.get_node_or_null(path) as InstanceBatch if chunk != null else null
		if batch == null:
			continue
		var v: PackedFloat32Array = batch.transforms
		for i: int in batch.get_instance_count():
			var o: int = i * 12
			var l: Vector3 = LAMP_OFFSET
			positions.append(Vector3(
				v[o] * l.x + v[o + 1] * l.y + v[o + 2] * l.z + v[o + 3],
				v[o + 4] * l.x + v[o + 5] * l.y + v[o + 6] * l.z + v[o + 7],
				v[o + 8] * l.x + v[o + 9] * l.y + v[o + 10] * l.z + v[o + 11]))
			sodium.append(1 if BATCHES[path] else 0)
	_lamps[c] = positions
	_sodium[c] = sodium


## How many of the pool may light up (the graphics setting).
func get_active_count() -> int:
	return _active
