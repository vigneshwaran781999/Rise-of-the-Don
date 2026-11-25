class_name District
extends Node3D
## Root of a streamed district scene (scenes/world/old_town.tscn): lighting, the always-loaded
## landmarks, the district boundary, the player spawn, parked vehicles and the WorldStreamer
## that brings the chunks in around the player.

@export var data: DistrictData

@onready var streamer: WorldStreamer = $WorldStreamer


func get_spawn_transform() -> Transform3D:
	return ($PlayerSpawn as Node3D).global_transform


func get_lane_graph() -> LaneGraph:
	return data.lane_graph


func get_display_name() -> String:
	return data.display_name


## Loads the chunks around `focus` (blocking) and keeps streaming around it from then on.
func start_streaming(focus: Node3D) -> void:
	streamer.district = data
	streamer.focus = focus
	streamer.load_around_now(focus.global_position)
