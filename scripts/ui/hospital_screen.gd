class_name HospitalScreen
extends BustedScreen
## The card when the player is knocked out (M7): "HOSPITALISED" glowing in hospital green and
## white with the bill, while the game holds still for a moment. The game session then wakes the
## player at the nearest hospital or clinic.


func _init() -> void:
	title_text = "HOSPITALISED"
	amount_format = "Hospital bill: %s"
	flash_colours = [Color("2fd27e"), Color("e8fff2")]
