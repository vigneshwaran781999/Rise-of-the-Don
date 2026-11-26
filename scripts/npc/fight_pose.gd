class_name FightPose
extends RefCounted
## How far a punching arm is thrown out (shaders/character.gdshader `punch`, 0-1) through a punch:
## out fast up to the moment the blow lands, back more slowly. Shared by the player and fighters.


## `progress` 0-1 through the punch (below 0: not punching); `hit_fraction` 0-1, when the blow lands.
static func arm_out(progress: float, hit_fraction: float) -> float:
	if progress < 0.0:
		return 0.0
	var h: float = clampf(hit_fraction, 0.05, 0.95)
	if progress < h:
		return smoothstep(0.0, h, progress)
	return 1.0 - smoothstep(h, 1.0, progress)
