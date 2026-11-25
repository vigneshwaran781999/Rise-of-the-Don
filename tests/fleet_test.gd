extends Node
## Fleet test (per-feature test scene, M7): the sports car, SUV, bus and truck on the flat test
## pad. For each: it settles on four wheels at the ride height its model was built for, then
## acceleration, top speed, braking, turning circle and a full-lock turn at speed, each in a sane
## range for its kind of vehicle. Prints a handling report per vehicle. Run from the project root:
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/fleet_test.tscn
## Prints "FLEET TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
## [name, scene, ride height (chassis centre above the road), sprint to (km/h), [min, max] seconds
##  to it, braking from (km/h), [min, max] metres, turning circle [min, max] m, turn test km/h]
const FLEET: Array = [
	["sports car", "res://scenes/vehicles/sports.tscn", 0.52, 100.0, [3.0, 7.5], 100.0, [20.0, 48.0], [8.0, 15.0], 60.0],
	["SUV", "res://scenes/vehicles/suv.tscn", 0.50, 100.0, [6.0, 14.0], 100.0, [26.0, 62.0], [9.0, 16.0], 50.0],
	["bus", "res://scenes/vehicles/bus.tscn", 1.35, 50.0, [6.0, 18.0], 50.0, [10.0, 36.0], [16.0, 30.0], 30.0],
	["truck", "res://scenes/vehicles/truck.tscn", 1.25, 50.0, [5.0, 15.0], 50.0, [10.0, 36.0], [13.0, 26.0], 35.0],
]

var _catcher: ErrorCatcher
var _car: VehicleController
var _driver: Node3D
var _report: PackedStringArray = []


func _ready() -> void:
	_catcher = ErrorCatcher.new()
	OS.add_logger(_catcher)
	_build_pad()
	_driver = Node3D.new()
	_driver.name = "TestDriver"
	add_child(_driver)
	_run.call_deferred()


func _run() -> void:
	var failure: String = ""
	for spec: Array in FLEET:
		_car = (load(spec[1]) as PackedScene).instantiate() as VehicleController
		add_child(_car)
		_report.append("%s:" % spec[0])
		for step: Callable in [_check_settle, _check_acceleration, _check_braking, _check_turning]:
			failure = await step.call(spec)
			if failure == "" and not _catcher.get_errors().is_empty():
				failure = "engine/script error: %s" % _catcher.get_errors()[0]
			if failure != "":
				failure = "%s, %s: %s" % [spec[0], step.get_method(), failure]
				break
		_car.queue_free()
		await _ticks(5)
		if failure != "":
			break
	print("HANDLING REPORT (fleet)")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("FLEET TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


func _check_settle(spec: Array) -> String:
	await _reset(Vector3.ZERO, 0.0, false)
	await _ticks(150)
	var contacts: int = 0
	for wheel: VehicleWheel3D in _car.get_wheels():
		contacts += 1 if wheel.is_in_contact() else 0
	var ride: float = _car.global_position.y
	var tilt: float = rad_to_deg(acos(clampf(_car.global_basis.y.y, -1.0, 1.0)))
	_note("at rest: ride height %.3f m (model %.2f m), tilt %.2f deg, %d wheels down" % [ride, spec[2], tilt, contacts])
	if contacts != 4:
		return "only %d wheels touch the ground at rest" % contacts
	if absf(ride - float(spec[2])) > 0.06:
		return "settled ride height %.3f m, the model expects %.2f m" % [ride, spec[2]]
	if tilt > 1.5 or _car.linear_velocity.length() > 0.05:
		return "not settled (tilt %.2f deg, speed %.3f m/s)" % [tilt, _car.linear_velocity.length()]
	return ""


func _check_acceleration(spec: Array) -> String:
	await _reset(Vector3(0.0, 0.0, -1900.0), 0.0, true)
	var target: float = spec[3]
	var t_target: float = -1.0
	var top: float = 0.0
	_car.set_controls(1.0, 0.0, 0.0, false)
	for i: int in 60 * 40:
		await get_tree().physics_frame
		var kmh: float = _car.get_forward_speed() * 3.6
		top = maxf(top, kmh)
		if t_target < 0.0 and kmh >= target:
			t_target = i / 60.0
	var drift: float = absf(_car.global_position.x)
	var window: Array = spec[4]
	_note("0-%.0f km/h %.1f s (expected %.0f-%.0f), top speed after 40 s %.0f km/h (limit %.0f), drift %.2f m" % [
		target, t_target, window[0], window[1], top, _car.stats.top_speed_kmh, drift])
	if t_target < 0.0 or t_target < float(window[0]) or t_target > float(window[1]):
		return "0-%.0f km/h took %.1f s (expected %.0f-%.0f s)" % [target, t_target, window[0], window[1]]
	if top > _car.stats.top_speed_kmh + 3.0 or top < _car.stats.top_speed_kmh * 0.85:
		return "top speed %.0f km/h, expected close to %.0f" % [top, _car.stats.top_speed_kmh]
	if drift > 2.0:
		return "drifted %.2f m sideways driving straight" % drift
	return ""


func _check_braking(spec: Array) -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(spec[5])
	var start: Vector3 = _car.global_position
	_car.set_controls(0.0, 1.0, 0.0, false)
	var frames: int = 0
	while _car.get_forward_speed() > 0.3 and frames < 900:
		await get_tree().physics_frame
		frames += 1
	var distance: float = start.distance_to(_car.global_position)
	var window: Array = spec[6]
	_note("braking %.0f-0 km/h: %.1f m in %.1f s" % [spec[5], distance, frames / 60.0])
	_car.set_controls(0.0, 0.0, 0.0, false)
	if distance < float(window[0]) or distance > float(window[1]):
		return "stopping from %.0f km/h took %.1f m (expected %.0f-%.0f m)" % [spec[5], distance, window[0], window[1]]
	return ""


func _check_turning(spec: Array) -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(15.0)
	var slow: Dictionary = await _steady_turn(1.0, 15.0, 5.0)
	var circle: float = slow["radius"] * 2.0
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(spec[8])
	var fast: Dictionary = await _steady_turn(1.0, spec[8], 3.0)
	var window: Array = spec[7]
	_note("turning circle at 15 km/h %.1f m (expected %.0f-%.0f); full lock at %.0f km/h: %.2f g, worst tilt %.0f deg, upright %s" % [
		circle, window[0], window[1], spec[8], fast["lateral_g"], fast["max_tilt"], fast["upright"]])
	_car.set_controls(0.0, 0.0, 0.0, false)
	if slow["yaw_change"] < 0.5:
		return "full left lock should turn left (yaw change %.2f rad)" % slow["yaw_change"]
	if circle < float(window[0]) or circle > float(window[1]):
		return "turning circle %.1f m (expected %.0f-%.0f m)" % [circle, window[0], window[1]]
	if not fast["upright"] or fast["max_tilt"] > 25.0:
		return "rolled or tilted %.0f deg in a full-lock turn at %.0f km/h" % [fast["max_tilt"], spec[8]]
	return ""


# --------------------------------------------------------------------------- helpers (as in vehicle_test.gd)

func _steady_turn(steer: float, kmh: float, seconds: float) -> Dictionary:
	var turned: float = 0.0           # integrated, so a turn past 180 degrees still counts
	var max_tilt: float = 0.0
	var upright: bool = true
	var yaw_rate_sum: float = 0.0
	var speed_sum: float = 0.0
	var samples: int = 0
	var frames: int = int(seconds * 60.0)
	for i: int in frames:
		var throttle: float = clampf((kmh - _car.get_speed_kmh()) * 0.2, 0.0, 1.0)
		_car.set_controls(throttle, 0.0, steer, false)
		await get_tree().physics_frame
		turned += _car.angular_velocity.y / 60.0
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(_car.global_basis.y.y, -1.0, 1.0))))
		upright = upright and _car.global_basis.y.y > 0.5
		if i > frames / 2:
			yaw_rate_sum += absf(_car.angular_velocity.y)
			speed_sum += _car.linear_velocity.length()
			samples += 1
	var yaw_rate: float = yaw_rate_sum / maxf(samples, 1)
	var speed: float = speed_sum / maxf(samples, 1)
	return {
		"yaw_change": turned * signf(steer),
		"radius": speed / maxf(yaw_rate, 0.001),
		"lateral_g": speed * yaw_rate / 9.81,
		"max_tilt": max_tilt,
		"upright": upright,
	}


func _reset(pos: Vector3, yaw: float, driven: bool) -> void:
	_car.set_controls(0.0, 0.0, 0.0, false)
	_car.set_driver(null)
	_car.teleport(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * 1.5))   # above the ride height of the tallest
	await _ticks(60)
	if driven:
		_car.set_driver(_driver)
		await _ticks(2)


func _reach_speed(kmh: float) -> void:
	_car.set_controls(1.0, 0.0, 0.0, false)
	var frames: int = 0
	while _car.get_forward_speed() * 3.6 < kmh and frames < 60 * 30:
		await get_tree().physics_frame
		frames += 1
	_car.set_controls(0.0, 0.0, 0.0, false)


func _heading() -> float:
	var forward: Vector3 = _car.global_basis.z
	return atan2(forward.x, forward.z)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _note(line: String) -> void:
	_report.append("  " + line)
	print("  .. " + line)


func _build_pad() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Pad"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 2.0, 4000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(shape)
	add_child(ground)
