class_name StreetLightPool
extends Node3D
## Real light from the streetlights at night (GDD §12: pooled lights). Every streetlight's lens
## glows through its material; only the few nearest the camera also get a real OmniLight3D,
## moved between lamps as the camera travels. Lamp positions come from the streamed chunks'
## streetlight batches.

## Where the light hangs on a streetlight model (just under the lens on the arm).
const LAMP_OFFSET := Vector3(2.45, 7.9, 0.0)
const BATCH_PATH: String = "Props/prop_streetlight"

@export var light_range: float = 24.0
@export var light_energy: float = 4.0
@export var light_color: Color = Color(1.0, 0.78, 0.5)

var _lights: Array[OmniLight3D] = []
var _lamps: Dictionary = {}     # chunk coord -> PackedVector3Array of lamp positions
var _streamer: WorldStreamer


func setup(streamer: WorldStreamer, count: int) -> void:
	_streamer = streamer
	for i: int in count:
		var light := OmniLight3D.new()
		light.name = "StreetLight%d" % i
		light.omni_range = light_range
		light.light_energy = light_energy
		light.light_color = light_color
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
	streamer.chunk_loaded.connect(_on_chunk_loaded)
	streamer.chunk_unloaded.connect(func(c: Vector2i) -> void: _lamps.erase(c))
	for c: Vector2i in streamer.get_loaded_coords():
		_on_chunk_loaded(c)


## Lights the `strength` (0-1) share of the pool's lamps nearest `around`.
func update(around: Vector3, strength: float) -> void:
	if strength < 0.02:
		for light: OmniLight3D in _lights:
			light.visible = false
		return
	var candidates: Array = []
	for positions: PackedVector3Array in _lamps.values():
		for p: Vector3 in positions:
			candidates.append([p.distance_squared_to(around), p])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i: int in _lights.size():
		var light: OmniLight3D = _lights[i]
		light.visible = i < candidates.size()
		if light.visible:
			light.global_position = candidates[i][1]
			light.light_energy = light_energy * strength


func get_lit_count() -> int:
	var count: int = 0
	for light: OmniLight3D in _lights:
		count += 1 if light.visible else 0
	return count


func get_lamp_count() -> int:
	var count: int = 0
	for positions: PackedVector3Array in _lamps.values():
		count += positions.size()
	return count


func _on_chunk_loaded(c: Vector2i) -> void:
	var chunk: Node = _streamer.get_chunk(c)
	var batch := chunk.get_node_or_null(BATCH_PATH) as InstanceBatch if chunk != null else null
	if batch == null:
		_lamps[c] = PackedVector3Array()
		return
	var v: PackedFloat32Array = batch.transforms
	var positions := PackedVector3Array()
	for i: int in batch.get_instance_count():
		var o: int = i * 12
		var l: Vector3 = LAMP_OFFSET
		positions.append(Vector3(
			v[o] * l.x + v[o + 1] * l.y + v[o + 2] * l.z + v[o + 3],
			v[o + 4] * l.x + v[o + 5] * l.y + v[o + 6] * l.z + v[o + 7],
			v[o + 8] * l.x + v[o + 9] * l.y + v[o + 10] * l.z + v[o + 11]))
	_lamps[c] = positions
