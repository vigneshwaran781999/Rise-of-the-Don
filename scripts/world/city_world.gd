class_name CityWorld
extends Node3D
## Root of the streamed city (scenes/world/city.tscn): lighting, the always-loaded landmarks
## (temple, skyline and the city's edge), the player spawn, parked vehicles and the
## WorldStreamer that brings the chunks in around the player.

@export var data: CityData

@onready var streamer: WorldStreamer = $WorldStreamer


func get_spawn_transform() -> Transform3D:
	return ($PlayerSpawn as Node3D).global_transform


func get_lane_graph() -> LaneGraph:
	return data.lane_graph


func get_display_name() -> String:
	return data.display_name


## Loads the chunks around `focus` (blocking) and keeps streaming around it from then on.
func start_streaming(focus: Node3D) -> void:
	streamer.city = data
	streamer.focus = focus
	streamer.load_around_now(focus.global_position)
