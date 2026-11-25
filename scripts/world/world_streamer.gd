class_name WorldStreamer
extends Node3D
## Streams the city's chunk scenes in and out around a focus node (GDD §2: "a grid of
## chunks, each its own scene, streamed in and out around the player by a WorldStreamer").
## Chunks within load_distance are loaded on a background thread (ResourceLoader threaded
## requests) and added at most one per frame; chunks beyond unload_distance are freed.
## Vehicles standing on ground that isn't loaded are frozen so they can't fall through.

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

const MONITOR: StringName = &"world/chunks_loaded"

@export var city: CityData
## A chunk is loaded when its nearest point is this close to the focus (metres).
@export var load_distance: float = 200.0
## ...and freed when it is further than this (larger, so chunks don't flicker in and out).
@export var unload_distance: float = 250.0
## Seconds between checks of which chunks are wanted.
@export var update_interval: float = 0.25

## Usually the player. Streaming centres on its position.
var focus: Node3D

var _loaded: Dictionary = {}       # Vector2i -> Node3D
var _requested: Dictionary = {}    # Vector2i -> String (path of a threaded load in flight)
var _timer: float = 0.0


func _ready() -> void:
	if not Performance.has_custom_monitor(MONITOR):
		Performance.add_custom_monitor(MONITOR, get_loaded_count)


func _exit_tree() -> void:
	if Performance.has_custom_monitor(MONITOR):
		Performance.remove_custom_monitor(MONITOR)
	# Finish any background loads so nothing is left half-loaded on exit.
	for path: String in _requested.values():
		ResourceLoader.load_threaded_get(path)
	_requested.clear()


func get_loaded_count() -> int:
	return _loaded.size()


func get_loaded_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in _loaded:
		out.append(c)
	return out


func get_chunk(coord: Vector2i) -> Node3D:
	return _loaded.get(coord) as Node3D


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _loaded.has(coord)


func is_position_loaded(pos: Vector3) -> bool:
	return _loaded.has(city.chunk_at(pos))


## Chunks that should be loaded around pos, nearest first.
func wanted_chunks(pos: Vector3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z: int in city.chunk_count.y:
		for x: int in city.chunk_count.x:
			var c := Vector2i(x, z)
			if city.has_chunk(c) and city.distance_to_chunk(pos, c) <= load_distance:
				out.append(c)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return city.distance_to_chunk(pos, a) < city.distance_to_chunk(pos, b))
	return out


## Loads every chunk wanted around pos right now, blocking (new game, teleports).
func load_around_now(pos: Vector3) -> void:
	for c: Vector2i in wanted_chunks(pos):
		if _loaded.has(c):
			continue
		if _requested.has(c):
			var path: String = _requested[c]
			_requested.erase(c)
			_add_chunk(c, ResourceLoader.load_threaded_get(path) as PackedScene)
		else:
			_add_chunk(c, load(city.chunk_path(c)) as PackedScene)
	_unload_far(pos)
	_update_frozen_vehicles()


func _process(delta: float) -> void:
	_finish_one_request()
	_timer -= delta
	if _timer > 0.0 or focus == null or city == null:
		return
	_timer = update_interval
	var pos: Vector3 = focus.global_position
	for c: Vector2i in wanted_chunks(pos):
		if not _loaded.has(c) and not _requested.has(c):
			var path: String = city.chunk_path(c)
			if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
				_requested[c] = path
	_unload_far(pos)
	_update_frozen_vehicles()


## Adds at most one chunk whose background load has finished (spreads the cost over frames).
func _finish_one_request() -> void:
	for c: Vector2i in _requested.keys():
		var path: String = _requested[c]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_requested.erase(c)
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if status != ResourceLoader.THREAD_LOAD_LOADED or scene == null:
			push_error("WorldStreamer: could not load chunk %s (%s)" % [c, path])
			return
		if focus == null or city.distance_to_chunk(focus.global_position, c) <= unload_distance:
			_add_chunk(c, scene)
		return


func _add_chunk(c: Vector2i, scene: PackedScene) -> void:
	if scene == null or _loaded.has(c):
		return
	var chunk := scene.instantiate() as Node3D
	add_child(chunk)
	_loaded[c] = chunk
	chunk_loaded.emit(c)


func _unload_far(pos: Vector3) -> void:
	for c: Vector2i in _loaded.keys():
		if city.distance_to_chunk(pos, c) > unload_distance:
			(_loaded[c] as Node3D).queue_free()
			_loaded.erase(c)
			chunk_unloaded.emit(c)


func _update_frozen_vehicles() -> void:
	for node: Node in get_tree().get_nodes_in_group(VehicleController.GROUP):
		var vehicle := node as VehicleController
		if vehicle == null or vehicle.is_occupied():
			continue
		var should_freeze: bool = not is_position_loaded(vehicle.global_position)
		if vehicle.freeze != should_freeze:
			vehicle.freeze = should_freeze
