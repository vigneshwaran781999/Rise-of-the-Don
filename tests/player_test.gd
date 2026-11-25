extends Node
## Player movement course (per-feature test scene) on the M1 test block, a controlled level:
## step up a kerb, climb an 18-degree ramp, fail to climb a 50-degree ramp (slope limit 46),
## and walk through a gopuram gateway. The game itself starts in Old Town now.
##   "$GODOT" --headless --path . res://tests/player_test.tscn
## Prints "PLAYER TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const TEST_BLOCK: PackedScene = preload("res://scenes/world/test_block.tscn")
const PLAYER: PackedScene = preload("res://scenes/player/player.tscn")

var _catcher: ErrorCatcher
var _player: PlayerController


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	Settings.persist = false
	Input.use_accumulated_input = false
	var block := TEST_BLOCK.instantiate() as CityBlockBuilder
	add_child(block)
	_player = PLAYER.instantiate() as PlayerController
	add_child(_player)
	_player.global_transform = block.get_spawn_transform()
	_player.reset_physics_interpolation()
	_run.call_deferred()


func _run() -> void:
	await _physics_frames(30)
	var failure: String = await _course()
	for code: Key in [KEY_W, KEY_A, KEY_D]:
		_key(code, false)
	var errors: PackedStringArray = _catcher.get_errors()
	OS.remove_logger(_catcher)
	if failure == "" and not errors.is_empty():
		failure = "engine/script error: " + errors[0]
	if failure == "":
		print("PLAYER TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


## Camera yaw 0, so W = north, A = west, D = east.
func _course() -> String:
	if not _player.is_on_floor():
		return "the player is not standing on the test block after spawning"
	_player.camera_rig.set_view_degrees(0.0, -12.0)

	await _teleport(Vector3(-4.0, 0.1, 30.0))
	await _hold(KEY_A, 60)
	if _player.global_position.x > -6.6 or absf(_player.global_position.y - 0.15) > 0.05:
		return "could not step west onto the sidewalk over the kerb (at %s)" % _player.global_position
	print("  ok  stepped up the bevelled kerb onto the sidewalk")

	await _teleport(Vector3(24.0, 0.25, 30.0))
	await _hold(KEY_D, 90)
	if absf(_player.global_position.y - 1.15) > 0.08 or not _player.is_on_floor():
		return "could not walk up the 18-degree ramp onto the platform (at %s)" % _player.global_position
	print("  ok  walked up the 18-degree ramp")

	await _teleport(Vector3(35.0, 0.25, 39.0))
	await _hold(KEY_W, 90)
	if _player.global_position.y > 0.6:
		return "walked up the 50-degree ramp, steeper than the slope limit (y=%.2f)" % _player.global_position.y
	print("  ok  the 50-degree ramp is too steep to climb")

	await _teleport(Vector3(3.0, 0.1, 30.0))
	await _hold(KEY_D, 240)   # 4 s at 5 m/s: road -> kerb -> plinth -> passage -> courtyard (x ~ 23)
	if _player.global_position.x < 21.0:
		return "could not walk east through the gopuram gateway into the courtyard (at %s)" % _player.global_position
	print("  ok  walked through the gopuram gateway into the courtyard")
	return ""


func _teleport(pos: Vector3) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_player.camera_rig.snap_to_target()
	await _physics_frames(15)


func _hold(code: Key, frames: int) -> void:
	_key(code, true)
	await _physics_frames(frames)
	_key(code, false)
	await _physics_frames(20)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
