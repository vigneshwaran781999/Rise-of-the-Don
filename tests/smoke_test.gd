extends Node
## Headless smoke test. Run from the project root:
##   "$GODOT" --headless --path . res://tests/smoke_test.tscn
## Prints "SMOKE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.
## Any engine or script error logged while it runs also fails the test.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const TIMEOUT_SEC: float = 90.0
const TEST_CUBE_PATH: String = "res://assets/models/test/prop_test_cube.glb"
const REQUIRED_ACTIONS: PackedStringArray = [
	"move_forward", "move_back", "move_left", "move_right", "sprint", "jump",
	"look_left", "look_right", "look_up", "look_down",
	"vehicle_enter_exit", "interact", "pause",
]

var _catcher: ErrorCatcher
var _finished: bool = false


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	get_tree().create_timer(TIMEOUT_SEC, true, false, true).timeout.connect(_on_timeout)
	_run.call_deferred()


func _run() -> void:
	var failure: String = await _run_checks()
	_finish(failure)


func _run_checks() -> String:
	var result: String = _check_project_settings()
	if result != "":
		return result
	result = _check_input_map()
	if result != "":
		return result
	result = await _check_test_cube()
	if result != "":
		return result
	return ""


# --------------------------------------------------------------------------- checks

func _check_project_settings() -> String:
	var engine: String = ProjectSettings.get_setting("physics/3d/physics_engine", "")
	if engine != "Jolt Physics":
		return "physics engine is '%s', expected 'Jolt Physics'" % engine
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	if w != 1920 or h != 1080:
		return "viewport is %dx%d, expected 1920x1080" % [w, h]
	print("  ok  project settings (Jolt, 1920x1080)")
	return ""


func _check_input_map() -> String:
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			return "input action '%s' is missing" % action
		if InputMap.action_get_events(action).is_empty():
			return "input action '%s' has no bindings" % action
	print("  ok  input map (%d actions)" % REQUIRED_ACTIONS.size())
	return ""


func _check_test_cube() -> String:
	if not ResourceLoader.exists(TEST_CUBE_PATH):
		return "test cube GLB was not imported: " + TEST_CUBE_PATH
	var packed: PackedScene = load(TEST_CUBE_PATH)
	var cube: Node3D = packed.instantiate()
	add_child(cube)
	var meshes: Array[Node] = cube.find_children("*", "MeshInstance3D", true, false)
	var bodies: Array[Node] = cube.find_children("*", "StaticBody3D", true, false)
	if meshes.size() != 1:
		return "test cube should have 1 visual mesh, found %d" % meshes.size()
	if bodies.size() != 1:
		return "test cube '-colonly' should import as 1 StaticBody3D, found %d" % bodies.size()
	var aabb: AABB = (meshes[0] as MeshInstance3D).get_aabb()
	if absf(aabb.position.y) > 0.01 or absf(aabb.size.y - 1.0) > 0.01:
		return "test cube should be 1 m tall with its pivot at the base, got AABB %s" % aabb

	# Drop a 0.5 m-radius ball on it: it must come to rest on top (centre at y = 1.5).
	var ball := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	ball.add_child(shape)
	ball.position = Vector3(0.0, 3.0, 0.0)
	add_child(ball)
	for i: int in 120:
		await get_tree().physics_frame
	var rest_y: float = ball.global_position.y
	cube.queue_free()
	ball.queue_free()
	if absf(rest_y - 1.5) > 0.1:
		return "ball should rest on the cube's imported collision at y=1.5, got y=%.3f" % rest_y
	print("  ok  test cube GLB imported with collision (ball rests at y=%.2f)" % rest_y)
	return ""


# --------------------------------------------------------------------------- result

func _on_timeout() -> void:
	_finish("timed out after %d s" % int(TIMEOUT_SEC))


func _finish(failure: String) -> void:
	if _finished:
		return
	_finished = true
	var errors: PackedStringArray = _catcher.get_errors()
	OS.remove_logger(_catcher)
	if failure == "" and not errors.is_empty():
		failure = "%d engine/script error(s) logged, first: %s" % [errors.size(), errors[0]]
	if failure == "":
		print("SMOKE TEST PASSED")
		get_tree().quit(0)
	else:
		print("FAILED: " + failure)
		get_tree().quit(1)
