class_name MapIcons
extends RefCounted
## How map blips look on the minimap and the full map (GDD §11), drawn with simple shapes.
## A blip is {"position": Vector3, "kind": StringName, ...}; kinds:
##   mission  - a mission to start (magenta ring)       objective - where the mission goes (cyan diamond)
##   waypoint - the player's own waypoint (yellow pin)  shop / property - a letter in a badge ("letter")
##   police   - a police unit (flashing red/blue)        zone - a search area (translucent, "radius" m)

const MISSION := Color("ff2bd6")
const OBJECTIVE := Color("22e6ff")
const WAYPOINT := Color("ffd23a")
const SHOP := Color("38d27a")
const PROPERTY := Color("ff9a2e")
const POLICE_RED := Color("ff3b4e")
const POLICE_BLUE := Color("3b7bff")
const OUTLINE := Color(0.03, 0.03, 0.06, 0.95)
## The full map's legend: [kind, text].
const LEGEND: Array = [
	[&"player", "You"], [&"mission", "Mission"], [&"objective", "Objective"], [&"waypoint", "Waypoint"],
	[&"shop", "Shop"], [&"property", "Property"], [&"police", "Police"],
]


static func colour(kind: StringName, blip: Dictionary = {}) -> Color:
	match kind:
		&"mission":
			return MISSION
		&"objective":
			return OBJECTIVE
		&"waypoint":
			return WAYPOINT
		&"shop":
			return blip.get("colour", SHOP)
		&"property":
			return PROPERTY
		&"police":
			return POLICE_RED if int(Time.get_ticks_msec() / 250) % 2 == 0 else POLICE_BLUE
		&"zone":
			return Color(1.0, 0.25, 0.3, 0.22)
	return Color.WHITE


static func route_colour(to_waypoint: bool) -> Color:
	return Color(WAYPOINT, 0.9) if to_waypoint else Color(OBJECTIVE, 0.85)


## Blips that stay on the minimap's rim when out of range (the rest just disappear).
static func stays_on_rim(kind: StringName) -> bool:
	return kind in [&"mission", &"objective", &"waypoint"]


static func draw(canvas: CanvasItem, kind: StringName, at: Vector2, scale: float, blip: Dictionary = {}) -> void:
	var c: Color = colour(kind, blip)
	match kind:
		&"mission":
			canvas.draw_circle(at, 9.0 * scale, OUTLINE)
			canvas.draw_circle(at, 7.0 * scale, c)
			canvas.draw_circle(at, 3.0 * scale, Color.WHITE)
		&"objective":
			var d := PackedVector2Array([at + Vector2(0, -9), at + Vector2(8, 0), at + Vector2(0, 9), at + Vector2(-8, 0)])
			for i: int in d.size():
				d[i] = at + (d[i] - at) * scale
			canvas.draw_colored_polygon(_grow(d, at, 2.5 * scale), OUTLINE)
			canvas.draw_colored_polygon(d, c)
		&"waypoint":
			var tip: Vector2 = at
			var head: Vector2 = at + Vector2(0, -16) * scale
			canvas.draw_line(tip, head, OUTLINE, 4.0 * scale)
			canvas.draw_line(tip, head, c, 2.0 * scale)
			canvas.draw_colored_polygon(PackedVector2Array([head, head + Vector2(11, 4) * scale, head + Vector2(0, 8) * scale]), c)
			canvas.draw_circle(tip, 2.5 * scale, c)
		&"shop", &"property":
			canvas.draw_circle(at, 10.0 * scale, OUTLINE)
			canvas.draw_circle(at, 8.5 * scale, c)
			var letter: String = str(blip.get("letter", "$" if kind == &"shop" else "H"))
			var font: Font = UIStyle.get_font()
			var font_size: int = int(14 * scale)
			var w: float = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			canvas.draw_string(font, at + Vector2(-w * 0.5, 5.0 * scale), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, OUTLINE)
		&"police":
			canvas.draw_circle(at, 6.5 * scale, OUTLINE)
			canvas.draw_circle(at, 5.0 * scale, c)
		&"player":
			draw_player(canvas, at, 0.0, scale)
		_:
			canvas.draw_circle(at, 5.0 * scale, c)


## The player's arrow at `at`, pointing `angle` radians clockwise from up.
static func draw_player(canvas: CanvasItem, at: Vector2, angle: float, scale: float) -> void:
	var points := PackedVector2Array([Vector2(0, -12), Vector2(8, 9), Vector2(0, 4), Vector2(-8, 9)])
	for i: int in points.size():
		points[i] = at + points[i].rotated(angle) * scale
	canvas.draw_colored_polygon(_grow(points, at, 2.5 * scale), OUTLINE)
	canvas.draw_colored_polygon(points, Color.WHITE)


static func _grow(points: PackedVector2Array, centre: Vector2, by: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(p + (p - centre).normalized() * by)
	return out
