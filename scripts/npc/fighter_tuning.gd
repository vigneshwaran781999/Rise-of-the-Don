class_name FighterTuning
extends Resource
## How fighters (story thugs and brawlers, M7) move and fight. Edit
## res://resources/characters/fighter.tres.

@export_group("Body")
## Health against punches (the player's punch does 20: four blows floor a fighter).
@export var health: float = 80.0
@export var walk_speed: float = 1.6
@export var run_speed: float = 4.4
@export var turn_speed: float = 10.0
## Metres per step (drives the walk cycle) and arm/leg swing at walking pace.
@export var stride: float = 0.75
@export var swing: float = 0.45

@export_group("Fighting")
## Stops this far from the player to throw punches.
@export var engage_distance: float = 1.3
## Throws a punch when the player is this close and within this angle of where it faces.
@export var punch_range: float = 1.7
@export var punch_angle_degrees: float = 40.0
## The wind-up (the right arm drawn back: the player's cue to hit first or step away), then the
## punch; the blow lands this far into the punch.
@export var windup_time: float = 0.45
@export var punch_time: float = 0.4
@export var punch_hit_at: float = 0.15
@export var punch_damage: float = 10.0
## The blow lands on the player if they are still this close and in front.
@export var punch_reach: float = 1.9
## Pause between punches, seconds (random in this range).
@export var cooldown_min: float = 0.9
@export var cooldown_max: float = 1.8

@export_group("Taking hits")
## A blow that doesn't floor them pushes them back this hard (m/s) and stops them for this long
## (it also breaks their wind-up).
@export var hit_knockback: float = 2.8
@export var hit_stagger_time: float = 0.45
## A car faster than this (m/s) floors them outright.
@export var knock_speed: float = 3.0
