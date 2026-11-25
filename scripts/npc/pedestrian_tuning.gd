class_name PedestrianTuning
extends Resource
## How pedestrians move and behave. Edit res://resources/characters/pedestrian.tres.

@export_group("Movement")
@export var walk_speed_min: float = 1.1
@export var walk_speed_max: float = 1.5
@export var run_speed: float = 4.2
## Metres per step (drives the walk cycle).
@export var stride: float = 0.7
## Leg swing at walking speed, radians (running swings more).
@export var swing: float = 0.45
@export var turn_speed: float = 8.0

@export_group("Wandering")
@export var wander_min: float = 12.0
@export var wander_max: float = 45.0
@export var idle_min: float = 2.0
@export var idle_max: float = 6.0
## Chance to stop and stand for a while on reaching a destination.
@export_range(0.0, 1.0) var idle_chance: float = 0.3
## Chance to go and sit on a free bench nearby on reaching a destination.
@export_range(0.0, 1.0) var sit_chance: float = 0.25
@export var sit_search_radius: float = 40.0
@export var sit_min: float = 10.0
@export var sit_max: float = 25.0
@export var talk_min: float = 8.0
@export var talk_max: float = 18.0
## Idle people this close may start chatting.
@export var talk_radius: float = 4.0

@export_group("Reactions")
@export var flee_distance: float = 22.0
@export var flee_time: float = 7.0
## Lying on the ground after being hit by a car, seconds.
@export var knocked_time: float = 3.0
## Hit by a car faster than this (m/s) knocks someone down; slower just makes them step aside.
@export var knock_speed: float = 2.0
## The player counts as bumping into someone this close (metres) while walking at them.
@export var bump_distance: float = 0.85
@export var bump_cooldown: float = 3.0
