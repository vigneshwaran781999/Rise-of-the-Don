class_name StoryData
extends Resource
## Every mission in the game and how a new game starts (GDD §3, §8).
## Edit res://resources/missions/story.tres.

## All missions, in story order.
@export var missions: Array[MissionData] = []
## Cash in the player's pocket on New Game, ₹ (they arrive broke).
@export var starting_cash: int = 200
