class_name DialogueScene
extends Node3D
## A dialogue scene (GDD §3: "a dialogue scene" with an important contact): while the
## conversation plays the camera cuts to a side-on two-shot of the player and whoever they're
## talking to, black bars (Letterbox) slide in at the top and bottom of the screen, and the player stands
## still, turned towards them. stop() puts everything back. MissionDirector runs one for TALK_TO
## objectives marked `scene`.

var _camera: Camera3D
var _bars: Letterbox
var _previous: Camera3D
var _player: PlayerController
var _playing: bool = false


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "SceneCamera"
	_camera.fov = 48.0
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # placed by hand, cut to at once
	add_child(_camera)
	_bars = Letterbox.new()
	_bars.name = "Letterbox"
	add_child(_bars)


func is_playing() -> bool:
	return _playing


func get_camera() -> Camera3D:
	return _camera


## Cuts to the two-shot of `player` and `other` and locks the player in place.
func play(player: PlayerController, other: Node3D) -> void:
	_player = player
	if not _playing:
		_previous = get_viewport().get_camera_3d()
	_playing = true
	player.input_locked = true
	var a: Vector3 = player.global_position
	var b: Vector3 = other.global_position
	var across: Vector3 = b - a
	across.y = 0.0
	var gap: float = across.length()
	across = across.normalized() if gap > 0.1 else Vector3.FORWARD
	player.model.rotation.y = atan2(-across.x, -across.z)     # the model faces -Z
	var mid: Vector3 = (a + b) * 0.5 + Vector3.UP * 1.45
	var side: Vector3 = Vector3.UP.cross(across)
	var reach: float = clampf(gap * 1.4 + 1.8, 2.8, 5.0)
	# Prefer the side the camera is already on; step in if a wall is in the way.
	var sides: Array[Vector3] = [side, -side]
	if _previous != null and (_previous.global_position - mid).dot(side) < 0.0:
		sides.reverse()
	var best := Vector3.ZERO
	var best_reach: float = -1.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for s: Vector3 in sides:
		var want: Vector3 = mid + s * reach + Vector3.UP * 0.2
		var query := PhysicsRayQueryParameters3D.create(mid, want, 1)
		var hit: Dictionary = space.intersect_ray(query)
		var got: float = reach if hit.is_empty() else maxf(mid.distance_to(hit["position"]) - 0.35, 0.0)
		if got > best_reach + 0.5:
			best_reach = got
			best = mid + s * got + Vector3.UP * 0.2
		if got >= reach:
			break
	_camera.global_position = best
	_camera.look_at(mid, Vector3.UP)
	_camera.make_current()
	_bars.set_shown(true)


## Back to the game camera; the player can move again.
func stop() -> void:
	if not _playing:
		return
	_playing = false
	if _player != null and is_instance_valid(_player):
		_player.input_locked = false
	if _previous != null and is_instance_valid(_previous):
		_previous.make_current()
	_previous = null
	_bars.set_shown(false)
