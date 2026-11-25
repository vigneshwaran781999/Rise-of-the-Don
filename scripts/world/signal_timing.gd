class_name SignalTiming
extends Resource
## Traffic-light timing shared by every signalized junction. Edit
## res://resources/world/signal_timing.tres.

## Green time for each direction (north-south, then east-west), seconds.
@export var green_seconds: float = 14.0
@export var amber_seconds: float = 3.0
## Both directions red between phases, seconds.
@export var all_red_seconds: float = 2.0


func cycle_seconds() -> float:
	return 2.0 * (green_seconds + amber_seconds + all_red_seconds)
