class_name WantedDisplay
extends Control
## The wanted level in the HUD (GDD §7, §10): five stars under the clock, as many lit as the
## level; they blink while the police are searching (they've lost sight of you). Hidden at 0.

const STAR_SIZE: float = 15.0
const GAP: float = 6.0
const LIT := Color("ffd23a")
const UNLIT := Color(1.0, 1.0, 1.0, 0.18)


func _ready() -> void:
	name = "WantedDisplay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(5.0 * (STAR_SIZE * 2.0 + GAP), STAR_SIZE * 2.0 + 4.0)


func get_lit_count() -> int:
	return WantedSystem.level


func _process(_delta: float) -> void:
	visible = WantedSystem.is_wanted()
	if visible:
		queue_redraw()


func _draw() -> void:
	var blink: bool = WantedSystem.searching and int(Time.get_ticks_msec() / 350) % 2 == 1
	for i: int in 5:
		# Stars fill from the right, like the cash above them.
		var centre := Vector2(size.x - (i + 0.5) * (STAR_SIZE * 2.0 + GAP), size.y * 0.5)
		var lit: bool = i < WantedSystem.level
		var colour: Color = LIT if lit else UNLIT
		if lit and blink:
			colour = Color(LIT, 0.35)
		_star(centre, colour)


func _star(centre: Vector2, colour: Color) -> void:
	var points := PackedVector2Array()
	for k: int in 10:
		var r: float = STAR_SIZE if k % 2 == 0 else STAR_SIZE * 0.45
		var a: float = -PI * 0.5 + k * PI / 5.0
		points.append(centre + Vector2(cos(a), sin(a)) * r)
	var outline := PackedVector2Array()
	for p: Vector2 in points:
		outline.append(centre + (p - centre) * 1.2)
	draw_colored_polygon(outline, Color(0.02, 0.02, 0.05, 0.85 if colour.a > 0.3 else 0.4))
	draw_colored_polygon(points, colour)
