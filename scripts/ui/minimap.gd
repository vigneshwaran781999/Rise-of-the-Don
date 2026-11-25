class_name Minimap
extends Control
## The round minimap in the HUD's bottom-left corner (GDD §11). Shows the district map around
## the player, turned so the camera looks "up", zooming out at speed. On top: the GPS route, the
## blips that systems offer (group "map_blips", get_map_blips(): missions, the objective, the
## waypoint, shops, police...), a north tick, and the player's arrow. Important blips that are
## out of range sit on the rim.

const SHADER: Shader = preload("res://shaders/minimap.gdshader")
const SIZE: float = 250.0
const METRES_ON_FOOT: float = 140.0
const METRES_AT_SPEED: float = 260.0

var player: PlayerController
var navigator: GpsNavigator

var _view: ColorRect
var _overlay: Control
var _material: ShaderMaterial
var _centre := Vector2.ZERO
var _heading: float = 0.0
var _metres: float = METRES_ON_FOOT
var _font: Font


func _ready() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	_font = UIStyle.get_font()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_view = ColorRect.new()
	_view.name = "MapView"
	_view.material = _material
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)


func bind(the_player: PlayerController, district: CityData, gps: GpsNavigator) -> void:
	player = the_player
	navigator = gps
	var texture: Texture2D = district.get_map_texture()
	_material.set_shader_parameter(&"map_texture", texture)
	var bounds: Rect2 = district.get_bounds()
	_material.set_shader_parameter(&"map_rect", Vector4(bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y))
	visible = texture != null


## Metres across the window right now (it zooms out with speed).
func get_metres_across() -> float:
	return _metres


## Compass angle (radians, 0 = north) shown as "up".
func get_heading() -> float:
	return _heading


## Where a world point lands on the minimap (pixels from its top-left corner).
func world_to_minimap(world: Vector3) -> Vector2:
	var d := Vector2(world.x - _centre.x, world.z - _centre.y) / _metres * SIZE
	var c: float = cos(_heading)
	var s: float = sin(_heading)
	return Vector2(SIZE, SIZE) * 0.5 + Vector2(d.x * c + d.y * s, -d.x * s + d.y * c)


func _process(_delta: float) -> void:
	if player == null:
		return
	var focus: Node3D = player.vehicle if player.is_in_vehicle() and player.vehicle != null else player
	_centre = Vector2(focus.global_position.x, focus.global_position.z)
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var forward: Vector3 = -camera.global_basis.z
		if Vector2(forward.x, forward.z).length() > 0.01:
			_heading = atan2(forward.x, -forward.z)
	var speed: float = player.vehicle.get_speed_kmh() if player.is_in_vehicle() and player.vehicle != null else 0.0
	var wanted: float = lerpf(METRES_ON_FOOT, METRES_AT_SPEED, clampf(speed / 90.0, 0.0, 1.0))
	_metres = lerpf(_metres, wanted, 0.05)
	_material.set_shader_parameter(&"centre", _centre)
	_material.set_shader_parameter(&"heading", _heading)
	_material.set_shader_parameter(&"metres_across", _metres)
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	if player == null:
		return
	var centre := Vector2(SIZE, SIZE) * 0.5
	var radius: float = SIZE * 0.5 - 10.0
	# GPS route, clipped to the circle.
	if navigator != null and navigator.route.size() >= 2:
		var colour: Color = MapIcons.route_colour(navigator.get_waypoint() != null)
		for i: int in navigator.route.size() - 1:
			var a: Vector2 = world_to_minimap(navigator.route[i])
			var b: Vector2 = world_to_minimap(navigator.route[i + 1])
			var steps: int = maxi(1, int(a.distance_to(b) / 5.0))
			for k: int in steps:
				var p0: Vector2 = a.lerp(b, float(k) / steps)
				var p1: Vector2 = a.lerp(b, float(k + 1) / steps)
				if p0.distance_to(centre) < radius and p1.distance_to(centre) < radius:
					_overlay.draw_line(p0, p1, colour, 4.0, true)
	# Blips.
	for provider: Node in get_tree().get_nodes_in_group(GpsNavigator.BLIP_GROUP):
		for blip: Dictionary in provider.call(&"get_map_blips"):
			var at: Vector2 = world_to_minimap(blip["position"])
			var kind: StringName = blip["kind"]
			if kind == &"zone":
				# Only the part inside the map disc (the ring starts at 0.468 of the size).
				var zone_radius: float = float(blip.get("radius", 30.0)) / _metres * SIZE
				var disc: PackedVector2Array = _circle_points(centre, SIZE * 0.468)
				for piece: PackedVector2Array in Geometry2D.intersect_polygons(_circle_points(at, zone_radius), disc):
					_overlay.draw_colored_polygon(piece, MapIcons.colour(kind, blip))
				continue
			var offset: Vector2 = at - centre
			if offset.length() > radius:
				if not MapIcons.stays_on_rim(kind):
					continue
				at = centre + offset.normalized() * radius
			MapIcons.draw(_overlay, kind, at, 1.0, blip)
	# North tick on the rim.
	var north: Vector2 = centre + (world_to_minimap(Vector3(_centre.x, 0.0, _centre.y - 1000.0)) - centre).normalized() * (radius + 1.0)
	_overlay.draw_circle(north, 11.0, Color(0.05, 0.05, 0.08, 0.95))
	_overlay.draw_string(_font, north + Vector2(-5.5, 6.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UIStyle.TEXT)
	# The player, pointing the way they face.
	var facing: Vector3
	if player.is_in_vehicle() and player.vehicle != null:
		facing = player.vehicle.global_basis.z
	else:
		facing = -player.model.global_basis.z
	var tip: Vector2 = world_to_minimap(player.global_position + Vector3(facing.x, 0.0, facing.z).normalized()) - centre
	MapIcons.draw_player(_overlay, centre, tip.angle() + PI * 0.5, 1.0)


static func _circle_points(at: Vector2, radius: float, count: int = 48) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in count:
		points.append(at + Vector2.from_angle(TAU * i / count) * radius)
	return points
