class_name MapScreen
extends CanvasLayer
## The full map (GDD §11): the whole district with place names, the blips (missions, the
## objective, shops, property, police), the player and the GPS route. Pan by dragging or with
## the movement keys / left stick, zoom with the wheel or the zoom keys / triggers; click (or
## press accept at the crosshair) to set a waypoint, click it again or right-click to clear it.
## Opens with the map key or from the pause menu, and pauses the game while open.

signal closed

const PAN_SPEED: float = 700.0          # screen pixels per second with the keys / stick
const ZOOM_STEP: float = 1.15
const MIN_ZOOM_FACTOR: float = 0.8      # of the zoom that fits the whole district
const MAX_ZOOM: float = 14.0            # pixels per metre
const CLICK_SLOP: float = 6.0

var _root: Control
var _view: Control
var _player: PlayerController
var _navigator: GpsNavigator
var _district: DistrictData
var _texture: Texture2D
var _font: Font
var _zoom: float = 2.0
var _pan := Vector2.ZERO
var _from_pause: bool = false
var _dragging: bool = false
var _drag_moved: float = 0.0


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UIStyle.get_font()
	_build()
	_root.hide()


func setup(player: PlayerController, district: DistrictData, navigator: GpsNavigator) -> void:
	_player = player
	_district = district
	_navigator = navigator
	_texture = district.get_map_texture()


func is_open() -> bool:
	return _root.visible


func open(from_pause: bool = false) -> void:
	if _district == null:
		return
	_from_pause = from_pause
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.show()
	_zoom = _fit_zoom()
	_pan = _district.get_bounds().get_center()     # the whole district in view to begin with
	_view.queue_redraw()
	AudioManager.play_ui(&"ui_accept")


func close() -> void:
	if not is_open():
		return
	_root.hide()
	if not _from_pause:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func get_zoom() -> float:
	return _zoom


func get_pan() -> Vector2:
	return _pan


func world_to_screen(world: Vector2) -> Vector2:
	return _view.size * 0.5 + (world - _pan) * _zoom


func screen_to_world(screen: Vector2) -> Vector2:
	return _pan + (screen - _view.size * 0.5) / _zoom


## Sets or clears the waypoint at a world point (as a click there does).
func click_world(world: Vector2) -> void:
	var current: Variant = _navigator.get_waypoint()
	if current != null and Vector2((current as Vector3).x, (current as Vector3).z).distance_to(world) * _zoom < 18.0:
		_navigator.clear_waypoint()
	else:
		_navigator.set_waypoint(Vector3(world.x, 0.0, world.y))
		AudioManager.play_ui(&"ui_accept")
	_view.queue_redraw()


## Zooms by `factor` keeping the world point under `screen` in place.
func zoom_at(screen: Vector2, factor: float) -> void:
	var before: Vector2 = screen_to_world(screen)
	_zoom = clampf(_zoom * factor, _fit_zoom() * MIN_ZOOM_FACTOR, MAX_ZOOM)
	_pan += before - screen_to_world(screen)
	_clamp_pan()
	_view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		if event.is_action_pressed("map") and not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
	elif event.is_action_pressed("map_zoom_in"):
		zoom_at(_view.size * 0.5, ZOOM_STEP)
	elif event.is_action_pressed("map_zoom_out"):
		zoom_at(_view.size * 0.5, 1.0 / ZOOM_STEP)
	elif event.is_action_pressed("ui_accept"):
		click_world(_pan)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_open():
		return
	var move: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move.length() > 0.05:
		_pan += move * PAN_SPEED * delta / _zoom
		_clamp_pan()
	_view.queue_redraw()


func _on_view_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			zoom_at(button.position, ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			zoom_at(button.position, 1.0 / ZOOM_STEP)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if _drag_moved < CLICK_SLOP:
					click_world(screen_to_world(button.position))
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_navigator.clear_waypoint()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_drag_moved += motion.relative.length()
		_pan -= motion.relative / _zoom
		_clamp_pan()


func _fit_zoom() -> float:
	var bounds: Rect2 = _district.get_bounds()
	return minf(_view.size.x / bounds.size.x, _view.size.y / bounds.size.y) * 0.95


func _clamp_pan() -> void:
	var bounds: Rect2 = _district.get_bounds()
	_pan = _pan.clamp(bounds.position, bounds.end)


func _draw_view() -> void:
	if _district == null:
		return
	var bounds: Rect2 = _district.get_bounds()
	var top_left: Vector2 = world_to_screen(bounds.position)
	_view.draw_rect(Rect2(Vector2.ZERO, _view.size), Color(0.04, 0.05, 0.08))
	if _texture != null:
		_view.draw_texture_rect(_texture, Rect2(top_left, bounds.size * _zoom), false)
	_view.draw_rect(Rect2(top_left, bounds.size * _zoom), Color(UIStyle.CYAN, 0.6), false, 2.0)
	# Place names.
	for i: int in _district.map_label_texts.size():
		var text: String = _district.map_label_texts[i]
		var at: Vector2 = world_to_screen(_district.map_label_positions[i])
		var font_size: int = 18 if _zoom < 3.0 else 22
		var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_view.draw_string_outline(_font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, 0.85))
		_view.draw_string(_font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UIStyle.TEXT)
	# GPS route.
	if _navigator.route.size() >= 2:
		var points := PackedVector2Array()
		for p: Vector3 in _navigator.route:
			points.append(world_to_screen(Vector2(p.x, p.z)))
		_view.draw_polyline(points, MapIcons.route_colour(_navigator.get_waypoint() != null), 4.0, true)
	# Blips and the player.
	for provider: Node in get_tree().get_nodes_in_group(GpsNavigator.BLIP_GROUP):
		for blip: Dictionary in provider.call(&"get_map_blips"):
			var p: Vector3 = blip["position"]
			var kind: StringName = blip["kind"]
			if kind == &"zone":
				_view.draw_circle(world_to_screen(Vector2(p.x, p.z)), float(blip.get("radius", 30.0)) * _zoom, MapIcons.colour(kind))
			else:
				MapIcons.draw(_view, kind, world_to_screen(Vector2(p.x, p.z)), 1.25, blip)
	var focus: Node3D = _player.vehicle if _player.is_in_vehicle() and _player.vehicle != null else _player
	var facing: Vector3 = _player.vehicle.global_basis.z if _player.is_in_vehicle() and _player.vehicle != null else -_player.model.global_basis.z
	MapIcons.draw_player(_view, world_to_screen(Vector2(focus.global_position.x, focus.global_position.z)), atan2(facing.x, -facing.z), 1.4)
	# Crosshair (keyboard / gamepad waypoints) and the header, legend and help.
	var mid: Vector2 = _view.size * 0.5
	for d: Vector2 in [Vector2(14, 0), Vector2(-14, 0), Vector2(0, 14), Vector2(0, -14)]:
		_view.draw_line(mid + d * 0.4, mid + d, Color(1, 1, 1, 0.7), 2.0)
	_view.draw_string_outline(_font, Vector2(40, 64), "%s  ·  VELANAGAR" % _district.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 8, Color(0, 0, 0, 0.8))
	_view.draw_string(_font, Vector2(40, 64), "%s  ·  VELANAGAR" % _district.display_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UIStyle.MAGENTA)
	var legend_at := Vector2(40, _view.size.y - 40.0 - MapIcons.LEGEND.size() * 30.0)
	_view.draw_rect(Rect2(legend_at - Vector2(16, 26), Vector2(190, MapIcons.LEGEND.size() * 30.0 + 20.0)), Color(UIStyle.PANEL_BG, 0.85))
	for i: int in MapIcons.LEGEND.size():
		var row: Vector2 = legend_at + Vector2(0, i * 30.0)
		MapIcons.draw(_view, MapIcons.LEGEND[i][0], row + Vector2(8, -6), 1.0, {})
		_view.draw_string(_font, row + Vector2(30, 0), MapIcons.LEGEND[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UIStyle.TEXT)
	var help: String = ControlsPanel.fill_keys("Click or {ui_accept}: set / clear waypoint    Drag or {move_forward}{move_left}{move_back}{move_right}: move    Wheel or {map_zoom_in} {map_zoom_out}: zoom    {map} or Esc: close")
	var hw: float = _font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_view.draw_string_outline(_font, Vector2((_view.size.x - hw) * 0.5, _view.size.y - 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(0, 0, 0, 0.85))
	_view.draw_string(_font, Vector2((_view.size.x - hw) * 0.5, _view.size.y - 24), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIStyle.TEXT_DIM)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.theme = UIStyle.get_theme()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = Control.new()
	_view.name = "MapView"
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.clip_contents = true
	_root.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_view_input)
