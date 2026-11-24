extends Node
## Vehicle handling test (per-feature test scene). Drives the sedan on a flat test pad and
## prints a handling report: acceleration, top speed, braking, reverse, turning circle,
## high-speed stability, handbrake turn, crash damage, flip recovery and the wrecked state.
## Each figure must fall in a sane range. Run from the project root:
##   "$GODOT" --headless --path . --fixed-fps 60 res://tests/vehicle_test.tscn
## (--fixed-fps runs the simulation as fast as the CPU allows; without it, it takes ~1.5 min.)
## Prints "VEHICLE TEST PASSED" and exits 0, or "FAILED: <reason>" and exits 1.

const ErrorCatcher := preload("res://tests/error_catcher.gd")
const SEDAN: PackedScene = preload("res://scenes/vehicles/sedan.tscn")
const WALL_POSITION := Vector3(600.0, 2.0, 0.0)  # well away from the acceleration runway (x = 0)

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
	_car = SEDAN.instantiate() as VehicleController
	add_child(_car)
	_run.call_deferred()


func _run() -> void:
	var steps: Array[Callable] = [
		_check_settle, _check_acceleration, _check_braking, _check_reverse, _check_turning_circle,
		_check_high_speed_stability, _check_handbrake_turn, _check_crash_damage, _check_flip_recovery,
		_check_wrecked, _check_parked,
	]
	var failure: String = ""
	for step: Callable in steps:
		failure = await step.call()
		if failure != "":
			failure = "%s: %s" % [step.get_method(), failure]
			break
		var errors: PackedStringArray = _catcher.get_errors()
		if not errors.is_empty():
			failure = "%s: engine/script error: %s" % [step.get_method(), errors[0]]
			break
	print("HANDLING REPORT (sedan)")
	for line: String in _report:
		print("  " + line)
	OS.remove_logger(_catcher)
	if failure == "":
		print("VEHICLE TEST PASSED")
		AudioManager.quit_game(0)
	else:
		print("FAILED: " + failure)
		AudioManager.quit_game(1)


# --------------------------------------------------------------------------- checks

func _check_settle() -> String:
	await _reset(Vector3.ZERO, 0.0, false)
	await _ticks(120)
	var contacts: int = 0
	for wheel: VehicleWheel3D in _car.get_wheels():
		contacts += 1 if wheel.is_in_contact() else 0
	var ride: float = _car.global_position.y
	var tilt: float = rad_to_deg(acos(clampf(_car.global_basis.y.y, -1.0, 1.0)))
	_note("at rest: ride height %.3f m (chassis centre above road), tilt %.2f deg, %d wheels down" % [ride, tilt, contacts])
	if contacts != 4:
		return "only %d wheels touch the ground at rest" % contacts
	if absf(ride - 0.55) > 0.05:
		return "settled ride height %.3f m, the model expects 0.55 m" % ride
	if tilt > 1.0 or _car.linear_velocity.length() > 0.05:
		return "car is not settled (tilt %.2f deg, speed %.3f m/s)" % [tilt, _car.linear_velocity.length()]
	return ""


func _check_acceleration() -> String:
	await _reset(Vector3(0.0, 0.0, -1900.0), 0.0, true)   # ~1.4 km of runway ahead
	var t50: float = -1.0
	var t100: float = -1.0
	var top: float = 0.0
	var max_gear: int = 0
	var engine := _car.get_node("Engine") as VehicleEngine
	_car.set_controls(1.0, 0.0, 0.0, false)
	for i: int in 60 * 40:
		await get_tree().physics_frame
		var kmh: float = _car.get_forward_speed() * 3.6
		top = maxf(top, kmh)
		max_gear = maxi(max_gear, engine.gear)
		if t50 < 0.0 and kmh >= 50.0:
			t50 = i / 60.0
		if t100 < 0.0 and kmh >= 100.0:
			t100 = i / 60.0
	var drift: float = absf(_car.global_position.x)
	_note("0-50 km/h %.1f s, 0-100 km/h %.1f s, top speed after 40 s %.0f km/h (limit %.0f), top gear %d, sideways drift %.2f m" % [
		t50, t100, top, _car.stats.top_speed_kmh, max_gear, drift])
	if t100 < 0.0 or t100 > 14.0 or t100 < 4.0:
		return "0-100 km/h took %.1f s (expected 4-14 s)" % t100
	if top > _car.stats.top_speed_kmh + 3.0 or top < _car.stats.top_speed_kmh * 0.85:
		return "top speed %.0f km/h, expected close to %.0f" % [top, _car.stats.top_speed_kmh]
	if max_gear < 4:
		return "gearbox only reached gear %d" % max_gear
	if drift > 2.0:
		return "drifted %.2f m sideways driving straight" % drift
	return ""


func _check_braking() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(100.0)
	var start: Vector3 = _car.global_position
	var lights := _car.get_node("Lights") as VehicleLights
	_car.set_controls(0.0, 1.0, 0.0, false)
	var frames: int = 0
	var brake_glow: float = 0.0
	while _car.get_forward_speed() > 0.3 and frames < 600:
		await get_tree().physics_frame
		frames += 1
		brake_glow = maxf(brake_glow, lights.get_tail_glow())
	var distance: float = start.distance_to(_car.global_position)
	_note("braking 100-0 km/h: %.1f m in %.1f s (%.2f g), brake lights %.1f" % [
		distance, frames / 60.0, (100.0 / 3.6) / (frames / 60.0) / 9.81, brake_glow])
	_car.set_controls(0.0, 0.0, 0.0, false)
	if distance < 25.0 or distance > 60.0:
		return "stopping from 100 km/h took %.1f m (expected 25-60 m)" % distance
	if brake_glow < lights.tail_glow_braking - 0.01:
		return "brake lights did not light up while braking"
	return ""


func _check_reverse() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	var lights := _car.get_node("Lights") as VehicleLights
	var engine := _car.get_node("Engine") as VehicleEngine
	_car.set_controls(0.0, 1.0, 0.0, false)
	await _ticks(60 * 5)
	var kmh: float = _car.get_forward_speed() * 3.6
	var gear: String = engine.get_gear_text()
	var glow: float = lights.get_reverse_glow()
	_car.set_controls(0.0, 0.0, 0.0, false)
	_note("reverse: %.1f km/h after 5 s on the brake pedal (limit %.0f), gear %s, reverse lights %.1f" % [
		kmh, -_car.stats.reverse_top_speed_kmh, gear, glow])
	if kmh > -20.0 or kmh < -_car.stats.reverse_top_speed_kmh - 2.0:
		return "reverse speed %.1f km/h, expected about -%.0f" % [kmh, _car.stats.reverse_top_speed_kmh]
	if gear != "R" or glow <= 0.0:
		return "reversing should show gear R and light the reverse lights (gear %s, glow %.1f)" % [gear, glow]
	return ""


func _check_turning_circle() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(15.0)
	var result: Dictionary = await _steady_turn(1.0, 15.0, 4.0)
	_note("turning circle at 15 km/h, full lock: %.1f m diameter, front wheels %.0f deg" % [
		result["radius"] * 2.0, rad_to_deg(_car.get_steer_angle())])
	_car.set_controls(0.0, 0.0, 0.0, false)
	if result["yaw_change"] < 0.5:
		return "full left lock should turn the car left (yaw change %.2f rad)" % result["yaw_change"]
	if result["radius"] * 2.0 > 16.0 or result["radius"] * 2.0 < 7.0:
		return "turning circle %.1f m (a sedan is about 10-12 m)" % (result["radius"] * 2.0)
	return ""


func _check_high_speed_stability() -> String:
	for kmh: float in [60.0, 100.0]:
		await _reset(Vector3.ZERO, 0.0, true)
		await _reach_speed(kmh)
		var result: Dictionary = await _steady_turn(1.0, kmh, 3.0)
		_note("full lock at %.0f km/h: radius %.0f m, %.2f g sideways, worst tilt %.0f deg, still upright: %s" % [
			kmh, result["radius"], result["lateral_g"], result["max_tilt"], result["upright"]])
		_car.set_controls(0.0, 0.0, 0.0, false)
		if not result["upright"]:
			return "the car rolled over in a full-lock turn at %.0f km/h" % kmh
		if result["max_tilt"] > 25.0:
			return "body tilted %.0f deg in a %.0f km/h turn (should stay planted)" % [result["max_tilt"], kmh]
	return ""


func _check_handbrake_turn() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(60.0)
	var start_yaw: float = _heading()
	_car.set_controls(0.0, 0.0, 1.0, true)
	var slide: float = 0.0
	for i: int in 60:
		await get_tree().physics_frame
		for wheel: VehicleWheel3D in _car.get_wheels():
			if wheel.position.z < 0.0:
				slide = maxf(slide, 1.0 - wheel.get_skidinfo())
	var turned: float = rad_to_deg(absf(angle_difference(start_yaw, _heading())))
	_car.set_controls(0.0, 0.0, 0.0, false)
	await _reset(Vector3.ZERO, 0.0, true)
	await _reach_speed(60.0)
	start_yaw = _heading()
	_car.set_controls(0.0, 0.0, 1.0, false)
	await _ticks(60)
	var turned_plain: float = rad_to_deg(absf(angle_difference(start_yaw, _heading())))
	_car.set_controls(0.0, 0.0, 0.0, false)
	_note("1 s full lock at 60 km/h: %.0f deg with handbrake (rear slip %.2f) vs %.0f deg without" % [turned, slide, turned_plain])
	if turned < turned_plain + 10.0:
		return "the handbrake should swing the car round further (%.0f vs %.0f deg)" % [turned, turned_plain]
	if slide < 0.2:
		return "rear tyres did not slide under the handbrake (slip %.2f)" % slide
	return ""


func _check_crash_damage() -> String:
	var damage := _car.get_node("Damage") as VehicleDamage
	var results: PackedStringArray = []
	var hits: Array = []
	for kmh: float in [10.0, 30.0, 60.0]:
		# Nose 5 m from the wall, already at the test speed, holding it until the hit.
		await _reset(Vector3(WALL_POSITION.x, 0.0, WALL_POSITION.z + 1.0 + 2.25 + 5.0), PI, true)
		damage.health = _car.stats.max_health
		var before: float = damage.health
		var impacts: Array = []
		var on_impact := func(impact_kmh: float, amount: float) -> void: impacts.append([impact_kmh, amount])
		damage.impacted.connect(on_impact)
		_car.linear_velocity = _car.global_basis.z * (kmh / 3.6)
		for i: int in 150:
			var throttle: float = clampf((kmh - _car.get_speed_kmh()) * 0.3, 0.0, 1.0) if impacts.is_empty() else 0.0
			_car.set_controls(throttle, 0.0, 0.0, false)
			await get_tree().physics_frame
		_car.set_controls(0.0, 0.0, 0.0, false)
		damage.impacted.disconnect(on_impact)
		var lost: float = before - damage.health
		hits.append(lost)
		results.append("%.0f km/h -> -%.0f health (%d impact event%s)" % [kmh, lost, impacts.size(), "" if impacts.size() == 1 else "s"])
	_note("crash into a wall: " + ", ".join(results) + " of %.0f" % _car.stats.max_health)
	damage.health = _car.stats.max_health
	if float(hits[0]) > 0.0:
		return "a 10 km/h bump should do no damage (lost %.0f)" % hits[0]
	if float(hits[1]) <= 0.0 or float(hits[2]) <= float(hits[1]):
		return "harder crashes should do more damage (%s)" % ", ".join(results)
	if float(hits[2]) >= _car.stats.max_health:
		return "one 60 km/h crash should not wreck the car outright"
	return ""


func _check_flip_recovery() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	_car.teleport(Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0.0, 1.2, 0.0)))
	var recovery := _car.get_node("Recovery") as VehicleRecovery
	var recovered: Array = [false]
	var on_recovered := func() -> void: recovered[0] = true
	recovery.recovered.connect(on_recovered)
	var frames: int = 0
	while not recovered[0] and frames < 60 * 6:
		await get_tree().physics_frame
		frames += 1
	recovery.recovered.disconnect(on_recovered)
	await _ticks(90)
	var upright: bool = _car.global_basis.y.y > 0.95
	_note("upside down -> back on its wheels after %.1f s (setting %.1f s), upright: %s" % [
		frames / 60.0, _car.stats.flip_recovery_seconds, upright])
	if not recovered[0] or not upright:
		return "an upturned car with a driver was not put back on its wheels"
	return ""


func _check_wrecked() -> String:
	await _reset(Vector3.ZERO, 0.0, true)
	var damage := _car.get_node("Damage") as VehicleDamage
	damage.health = _car.stats.max_health
	damage.apply_damage(_car.stats.max_health * 0.8)
	var smoking_low: bool = damage.is_smoking()
	damage.apply_damage(_car.stats.max_health)
	var wrecked: bool = damage.is_wrecked() and _car.is_engine_disabled() and not _car.is_engine_running()
	_car.set_controls(1.0, 0.0, 0.0, false)
	await _ticks(90)
	var crawl: float = _car.get_speed_kmh()
	_car.set_controls(0.0, 0.0, 0.0, false)
	_note("damage: smoking at 20%% health: %s; at 0 health the engine dies: %s (full throttle -> %.1f km/h)" % [
		smoking_low, wrecked, crawl])
	if not smoking_low:
		return "no smoke at 20% health"
	if not wrecked or crawl > 1.0:
		return "a wrecked car should not drive (wrecked %s, speed %.1f km/h)" % [wrecked, crawl]
	return ""


func _check_parked() -> String:
	# Fresh car: the wrecked one above stays wrecked.
	_car.queue_free()
	await get_tree().physics_frame
	_car = SEDAN.instantiate() as VehicleController
	add_child(_car)
	await _reset(Vector3.ZERO, 0.0, false)
	_car.linear_velocity = _car.global_basis.z * 3.0
	await _ticks(90)
	var speed: float = _car.linear_velocity.length()
	_note("parked (no driver), shoved at 3 m/s: %.2f m/s after 1.5 s, engine running: %s" % [speed, _car.is_engine_running()])
	if speed > 0.2 or _car.is_engine_running():
		return "an empty car should hold itself with the parking brake and keep its engine off"
	return ""


# --------------------------------------------------------------------------- helpers

func _steady_turn(steer: float, kmh: float, seconds: float) -> Dictionary:
	var start_yaw: float = _heading()
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
		var tilt: float = rad_to_deg(acos(clampf(_car.global_basis.y.y, -1.0, 1.0)))
		max_tilt = maxf(max_tilt, tilt)
		upright = upright and _car.global_basis.y.y > 0.5
		if i > frames / 2:
			yaw_rate_sum += absf(_car.angular_velocity.y)
			speed_sum += _car.linear_velocity.length()
			samples += 1
	var yaw_rate: float = yaw_rate_sum / maxf(samples, 1)
	var speed: float = speed_sum / maxf(samples, 1)
	return {
		"yaw_change": angle_difference(start_yaw, _heading()) * signf(steer),
		"radius": speed / maxf(yaw_rate, 0.001),
		"lateral_g": speed * yaw_rate / 9.81,
		"max_tilt": max_tilt,
		"upright": upright,
	}


## Puts the car at pos facing yaw (0 = +Z), still, then lets it settle.
func _reset(pos: Vector3, yaw: float, driven: bool) -> void:
	_car.set_controls(0.0, 0.0, 0.0, false)
	_car.set_driver(null)
	_car.teleport(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, 0.6, 0.0)))
	await _ticks(45)
	if driven:
		_car.set_driver(_driver)
		await _ticks(2)


func _reach_speed(kmh: float) -> void:
	_car.set_controls(1.0, 0.0, 0.0, false)
	var frames: int = 0
	while _car.get_forward_speed() * 3.6 < kmh and frames < 60 * 20:
		await get_tree().physics_frame
		frames += 1
	_car.set_controls(0.0, 0.0, 0.0, false)


## Heading of the car's nose as a yaw angle (0 = +Z, positive = turned left).
func _heading() -> float:
	var forward: Vector3 = _car.global_basis.z
	return atan2(forward.x, forward.z)


func _ticks(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _note(line: String) -> void:
	_report.append(line)
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
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(30.0, 4.0, 2.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = WALL_POSITION
	add_child(wall)
