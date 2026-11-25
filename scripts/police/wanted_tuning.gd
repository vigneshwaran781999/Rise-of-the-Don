class_name WantedTuning
extends Resource
## How the wanted level and the police behave (GDD §7). Edit res://resources/police/wanted.tres.

@export_group("Crimes and heat")
## Heat each crime adds; the wanted level is the highest level whose threshold the heat reaches.
@export var knockdown_heat: float = 1.0
@export var hit_police_heat: float = 3.0
@export var assault_officer_heat: float = 3.0
## Heat needed for each level 0-5.
@export var level_heat: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 3.0, 6.0, 10.0, 15.0])
## After a crime the police know where you are for this long, whether they see you or not.
@export var dispatch_seconds: float = 6.0
## Seconds of being seen at each level before it rises by one (0 = never).
@export var escalate_seconds: PackedFloat32Array = PackedFloat32Array([0.0, 40.0, 60.0, 75.0, 90.0, 0.0])

@export_group("Searching")
## Out of sight, the police search a circle around where they last saw you: this big...
@export var search_radius_base: float = 55.0
@export var search_radius_per_level: float = 20.0
## ...shrinking this fast (m/s) down to this size.
@export var search_shrink: float = 1.5
@export var search_radius_min: float = 35.0
## Staying outside the circle this long (seconds) drops one level.
@export var clear_seconds: float = 8.0

@export_group("Seeing")
@export var car_sight: float = 75.0
@export var officer_sight: float = 45.0
@export var helicopter_sight: float = 120.0

@export_group("Response")
## Police cars and officers on foot hunting you, by level 0-5.
@export var cars: PackedInt32Array = PackedInt32Array([0, 0, 2, 3, 4, 5])
@export var officers: PackedInt32Array = PackedInt32Array([0, 2, 2, 2, 2, 2])
## Roadblocks across the road ahead from this level, spike strips in front of them from this one,
## and the helicopter from this one.
@export var roadblocks_from: int = 3
@export var spikes_from: int = 4
@export var helicopter_from: int = 5
## Seconds between roadblocks.
@export var roadblock_interval: float = 25.0
## How fast police cars drive when chasing, km/h.
@export var chase_speed_kmh: float = 95.0
@export var officer_run_speed: float = 5.6

@export_group("Busted")
## An officer this close to you on foot for this long arrests you...
@export var bust_distance: float = 1.9
@export var bust_seconds: float = 1.5
## ...or, in a car that has stopped, police this close for this long.
@export var bust_car_distance: float = 5.0
@export var bust_car_seconds: float = 2.5
## The fine: this share of your cash, at least the minimum (never more than you have).
@export_range(0.0, 1.0) var fine_share: float = 0.1
@export var fine_min: int = 100

@export_group("Respray garage")
@export var respray_fee: int = 500
## A respray clears a wanted level up to this one.
@export var respray_max_level: int = 3
