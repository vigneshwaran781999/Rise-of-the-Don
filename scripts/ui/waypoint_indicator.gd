class_name WaypointIndicator
extends Control
## Points at the current mission waypoint (GDD §8, until the minimap arrives in M6): a diamond
## with the distance over the spot when it is on screen, or an arrow at the screen edge pointing
## towards it when it is off screen or behind the camera.

const COLOUR := Color("22e6ff")
const EDGE_MARGIN: float = 70.0
const HEIGHT_OFFSET: float = 1.2

var target: Node3D
## Where the distance is measured from (the player).
var origin: Node3D

var _font: Font


func _ready() -> void:
	name = "WaypointIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UIStyle.get_font()


## True when the indicator is drawn, and where (screen position of the diamond or arrow).
func get_screen_point() -> Variant:
	var placed: Array = _placement()
	return placed[0] if not placed.is_empty() else null


func is_on_screen() -> bool:
	var placed: Array = _placement()
	return not placed.is_empty() and placed[1]


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var placed: Array = _placement()
	if placed.is_empty():
		return
	var point: Vector2 = placed[0]
	var on_screen: bool = placed[1]
	var distance: float = 0.0
	if origin != null and is_instance_valid(origin):
		distance = Vector2(origin.global_position.x - target.global_position.x, origin.global_position.z - target.global_position.z).length()
	if on_screen:
		var diamond := PackedVector2Array([point + Vector2(0, -13), point + Vector2(10, 0), point + Vector2(0, 13), point + Vector2(-10, 0)])
		draw_colored_polygon(diamond, Color(COLOUR, 0.85))
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(0, 0, 0, 0.6), 2.0)
	else:
		var centre: Vector2 = size * 0.5
		var direction: Vector2 = (point - centre).normalized()
		var side := Vector2(-direction.y, direction.x)
		var tip: Vector2 = point + direction * 14.0
		var arrow := PackedVector2Array([tip, point - direction * 10.0 + side * 13.0, point - direction * 4.0, point - direction * 10.0 - side * 13.0])
		draw_colored_polygon(arrow, Color(COLOUR, 0.9))
	var text: String = "%d m" % roundi(distance)
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var at: Vector2 = point + Vector2(-width * 0.5, 36.0 if on_screen else 40.0)
	draw_string(_font, at + Vector2(1, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0, 0, 0, 0.7))
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIStyle.TEXT)


## [screen point, on screen] for the target, or [] when there is nothing to show.
func _placement() -> Array:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return []
	var lift: float = HEIGHT_OFFSET
	if target is MissionMarker:
		lift = (target as MissionMarker).get_label_height()
	var world_point: Vector3 = target.global_position + Vector3.UP * lift
	var behind: bool = camera.is_position_behind(world_point)
	var screen: Vector2 = camera.unproject_position(world_point)
	var rect := Rect2(Vector2(EDGE_MARGIN, EDGE_MARGIN), size - Vector2(EDGE_MARGIN, EDGE_MARGIN) * 2.0)
	if not behind and rect.has_point(screen):
		return [screen, true]
	# Off screen: push the point to the edge, along the direction from the screen centre.
	var centre: Vector2 = size * 0.5
	var direction: Vector2 = screen - centre
	if behind:
		direction = -direction
	if direction.length_squared() < 1.0:
		direction = Vector2(0.0, 1.0)
	var half: Vector2 = rect.size * 0.5
	var scale_to_edge: float = minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
	return [centre + direction * scale_to_edge, false]
