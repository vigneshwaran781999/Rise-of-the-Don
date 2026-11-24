class_name Speedometer
extends Control
## Neon dial for the HUD (GDD §10 "speedometer in vehicles"): a 270° arc filling with speed,
## tick marks every 20 km/h, the speed in big digits, the gear, and a thin rev arc inside.
## Hud feeds it with set_reading() every frame while the player drives.

const ARC_START: float = deg_to_rad(135.0)
const ARC_SWEEP: float = deg_to_rad(270.0)
const RING_WIDTH: float = 10.0

var max_kmh: float = 180.0

var _kmh: float = 0.0
var _rpm_share: float = 0.0
var _gear: String = "N"


func _ready() -> void:
	custom_minimum_size = Vector2(250.0, 250.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_reading(kmh: float, rpm_share: float, gear: String) -> void:
	if is_equal_approx(kmh, _kmh) and is_equal_approx(rpm_share, _rpm_share) and gear == _gear:
		return
	_kmh = kmh
	_rpm_share = rpm_share
	_gear = gear
	queue_redraw()


func get_shown_kmh() -> int:
	return roundi(_kmh)


func get_shown_gear() -> String:
	return _gear


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.5 - RING_WIDTH
	var share: float = clampf(_kmh / max_kmh, 0.0, 1.0)
	draw_circle(centre, radius + RING_WIDTH * 0.5, Color(UIStyle.PANEL_BG, 0.72))
	draw_arc(centre, radius, ARC_START, ARC_START + ARC_SWEEP, 64, Color(1, 1, 1, 0.08), RING_WIDTH, true)
	if share > 0.002:
		var fill: Color = UIStyle.CYAN.lerp(UIStyle.MAGENTA, smoothstep(0.55, 1.0, share))
		draw_arc(centre, radius, ARC_START, ARC_START + ARC_SWEEP * share, 64, Color(fill, 0.25), RING_WIDTH + 8.0, true)
		draw_arc(centre, radius, ARC_START, ARC_START + ARC_SWEEP * share, 64, fill, RING_WIDTH, true)
	# Tick marks every 20 km/h, longer every 40.
	var step: float = 20.0
	var kmh_mark: float = 0.0
	while kmh_mark <= max_kmh + 0.1:
		var angle: float = ARC_START + ARC_SWEEP * (kmh_mark / max_kmh)
		var direction := Vector2(cos(angle), sin(angle))
		var long_tick: bool = int(kmh_mark) % 40 == 0
		var inner: float = radius - RING_WIDTH * 0.5 - (14.0 if long_tick else 8.0)
		draw_line(centre + direction * inner, centre + direction * (radius - RING_WIDTH * 0.5 - 2.0),
			Color(UIStyle.TEXT, 0.55 if long_tick else 0.3), 2.0, true)
		kmh_mark += step
	# Rev arc inside the dial.
	var rev_radius: float = radius - 34.0
	draw_arc(centre, rev_radius, ARC_START, ARC_START + ARC_SWEEP, 48, Color(1, 1, 1, 0.06), 4.0, true)
	if _rpm_share > 0.01:
		var rev_colour: Color = UIStyle.HEALTH if _rpm_share > 0.88 else Color(UIStyle.TEXT, 0.6)
		draw_arc(centre, rev_radius, ARC_START, ARC_START + ARC_SWEEP * _rpm_share, 48, rev_colour, 4.0, true)
	# Digits.
	var font: Font = UIStyle.get_font()
	var speed_text: String = str(roundi(_kmh))
	_draw_centered(font, speed_text, centre + Vector2(0.0, 18.0), 64, UIStyle.TEXT)
	_draw_centered(font, "KM/H", centre + Vector2(0.0, 46.0), 16, UIStyle.TEXT_DIM)
	_draw_centered(font, _gear, centre + Vector2(0.0, radius * 0.78), 26,
		UIStyle.MAGENTA.lightened(0.2) if _gear == "R" else UIStyle.CYAN)


func _draw_centered(font: Font, text: String, baseline_centre: Vector2, font_size: int, colour: Color) -> void:
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, baseline_centre - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
