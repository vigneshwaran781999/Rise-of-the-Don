class_name PopulationTuning
extends Resource
## How many people and cars live around the player, where they appear and disappear, and what
## they look like (GDD §6). Edit res://resources/characters/population.tres.
## Counts are indexed by the density setting: [low, medium, high].

@export_group("Traffic")
@export var traffic_counts: PackedInt32Array = PackedInt32Array([7, 14, 22])
## Cars appear on lanes between these distances from the player (metres)...
@export var traffic_spawn_min: float = 40.0
@export var traffic_spawn_max: float = 110.0
## ...but never in view closer than this...
@export var traffic_visible_spawn_min: float = 95.0
## ...and are removed beyond this distance when out of view.
@export var traffic_despawn: float = 130.0
@export var paint_colours: PackedColorArray = PackedColorArray([
	Color("f1f1ee"), Color("c9ccd1"), Color("1c1d22"), Color("a3162b"), Color("23508f"),
	Color("2f6d4e"), Color("e3b21f"), Color("7a7f87"), Color("f1f1ee"), Color("c9ccd1"),
])

@export_group("Pedestrians")
@export var pedestrian_counts: PackedInt32Array = PackedInt32Array([12, 26, 42])
@export var pedestrian_spawn_min: float = 25.0
@export var pedestrian_spawn_max: float = 80.0
@export var pedestrian_visible_spawn_min: float = 60.0
@export var pedestrian_despawn: float = 100.0
## Share of new pedestrians that appear as two people chatting.
@export_range(0.0, 1.0) var pair_chance: float = 0.3
@export var top_colours: PackedColorArray = PackedColorArray([
	Color("e9e4d6"), Color("3f6fb0"), Color("c2412f"), Color("e0b43a"), Color("2f8f5b"),
	Color("8c3e8f"), Color("f08a3c"), Color("5fb3c7"), Color("f4f1e8"), Color("2a2f3a"),
])
@export var bottom_colours: PackedColorArray = PackedColorArray([
	Color("2c3a55"), Color("3b3b3f"), Color("6d5a43"), Color("1f2230"), Color("7b7f86"),
])
## Long skirts (bright) and veshtis (white and cream) use their own palettes.
@export var skirt_colours: PackedColorArray = PackedColorArray([
	Color("c2185b"), Color("e8a33c"), Color("2f8f5b"), Color("7b2f8c"), Color("d84a2f"), Color("1f6fb0"),
])
@export var veshti_colours: PackedColorArray = PackedColorArray([Color("f4f1e8"), Color("ece3cf"), Color("f7f5ee")])
@export var skin_tones: PackedColorArray = PackedColorArray([
	Color("8d5a3b"), Color("a0694b"), Color("6e4430"), Color("b07a55"), Color("5c3a28"),
])
@export var hair_colours: PackedColorArray = PackedColorArray([Color("17130f"), Color("1f1a16"), Color("2a221b")])
@export var grey_hair_colours: PackedColorArray = PackedColorArray([Color("cfcac2"), Color("9d968c")])
