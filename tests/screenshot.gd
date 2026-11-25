extends Node
## Renders a scene in a real window and saves a PNG: a visual sanity check that also surfaces
## shader compile errors (headless runs skip rendering). Not part of the smoke test.
##
##   "$GODOT" --path . res://tests/screenshot.tscn -- --scene=res://scenes/main/game.tscn \
##       --out=C:/path/shot.png [--frames=90] [--view=yaw,pitch] [--cam=x,y,z --look=x,y,z]
##       [--pause] [--press=ButtonName,OtherButton]
##       [--drive [--throttle=frames] [--steer=-1..1] [--hood] [--health=0..1] [--headlights]] [--lanes]
##       [--crowd[=x,y,z]] [--chase[=n]]
##
## --view sets the player camera angles in degrees; --cam/--look place a free camera instead.
## --pause opens the pause menu; --press presses buttons (found by node name) in order.
## --drive puts the player in the test block's sedan; --throttle holds the accelerator for that
## many frames (with --steer), --hood picks the hood camera, --health sets the car's health share
## (below 0.35 it smokes), --headlights switches them on. --lanes shows the F4 lane/navmesh view.
## --crowd puts pedestrians at the --look point, or at x,y,z (chatting, walking, one going to sit down).
## --chase looks over traffic car n (default the first) once the frames have passed.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", "res://scenes/main/main_menu.tscn")
	var out_path: String = args.get("out", "user://screenshot.png")
	var frames: int = int(args.get("frames", "90"))
	var instance: Node = (load(scene_path) as PackedScene).instantiate()
	add_child(instance)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if args.has("view"):
		var player: PlayerController = instance.get_node_or_null("Player") as PlayerController
		if player != null:
			var view: PackedStringArray = str(args["view"]).split(",")
			player.camera_rig.set_view_degrees(float(view[0]), float(view[1]))
	if args.has("cam"):
		var cam := Camera3D.new()
		cam.fov = float(args.get("fov", "60"))
		cam.far = 2000.0
		add_child(cam)
		cam.global_position = _vec3(str(args["cam"]))
		cam.look_at(_vec3(str(args.get("look", "0,0,0"))), Vector3.UP)
		cam.make_current()
	await get_tree().process_frame
	if args.has("lanes") and instance.has_node("LaneDebug"):
		(instance.get_node("LaneDebug") as LaneGraphDebug).visible = true
	if args.has("drive"):
		await _drive(instance, args)
	if args.has("crowd"):
		var where: String = str(args["crowd"]) if str(args["crowd"]).count(",") == 2 else str(args.get("look", "0,0,0"))
		await _crowd(instance, _vec3(where))
	if args.has("pause"):
		var pause_menu: PauseMenu = instance.get_node_or_null("PauseMenu") as PauseMenu
		if pause_menu != null:
			pause_menu.open()
	if args.has("press"):
		for button_name: String in str(args["press"]).split(","):
			var button := instance.find_child(button_name, true, false) as Button
			if button != null:
				button.pressed.emit()
			await get_tree().process_frame
	for i: int in frames:
		await get_tree().process_frame
	if args.has("chase"):
		await _chase(instance, str(args["chase"]))
	await RenderingServer.frame_post_draw
	print("RENDER STATS  fps %d | draw calls %d | objects %d | primitives %d | video memory %.0f MB" % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	])
	var image: Image = get_viewport().get_texture().get_image()
	var err: Error = image.save_png(out_path)
	print("SCREENSHOT %s -> %s" % ["SAVED" if err == OK else "FAILED (%d)" % err, out_path])
	get_tree().quit(0 if err == OK else 1)


## Puts a camera behind and above traffic car number `which` (in the traffic manager's list;
## anything else = the first), looking up the road ahead of it.
func _chase(game: Node, which: String) -> void:
	var traffic := game.get_node_or_null("Traffic") as TrafficManager
	if traffic == null or traffic.get_cars().is_empty():
		return
	var cars: Array[VehicleController] = traffic.get_cars()
	var car: VehicleController = cars[(int(which) if which.is_valid_int() else 0) % cars.size()]
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	for i: int in 3:
		var back: Vector3 = -car.global_basis.z
		back.y = 0.0
		back = back.normalized()
		cam.global_position = car.global_position + back * 9.0 + Vector3.UP * 3.5
		cam.look_at(car.global_position - back * 8.0, Vector3.UP)
		await get_tree().process_frame
	var driver := car.get_node("Driver") as TrafficDriver
	print("CHASE %s at %s, %.0f km/h, '%s'" % [car.name, car.global_position.snapped(Vector3.ONE), car.get_speed_kmh(), driver.get_reason()])


## Puts people where the camera looks (normal spawning keeps out of sight): two chatting at
## `around`, four walkers near them and one heading for the nearest free bench seat.
func _crowd(game: Node, around: Vector3) -> void:
	var people := game.get_node_or_null("Pedestrians") as PedestrianManager
	if people == null:
		return
	people.enabled = false
	people.clear()
	var map: RID = people.get_world_3d().navigation_map
	var spot := Vector3.ZERO
	for i: int in 300:   # until the streamed chunks' navmeshes have reached the navigation map
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			spot = NavigationServer3D.map_get_closest_point(map, around)
			if spot != Vector3.ZERO and Vector2(spot.x - around.x, spot.z - around.z).length() < 6.0:
				break
	print("CROWD at %s" % spot)
	people.spawn_pair(spot)
	for i: int in 4:
		var angle: float = TAU * i / 4.0 + 0.4
		people.spawn_at(NavigationServer3D.map_get_closest_point(map, around + Vector3(cos(angle), 0.0, sin(angle)) * 7.0))
	var sitter: Pedestrian = people.spawn_at(NavigationServer3D.map_get_closest_point(map, around + Vector3(2.0, 0.0, -2.0)))
	var seat: Node3D = people.claim_seat(sitter)
	if seat != null:
		sitter.go_sit(seat)


func _drive(game: Node, args: Dictionary) -> void:
	var player := game.get_node("Player") as PlayerController
	var car := game.get_node("World/Vehicles/Sedan") as VehicleController
	for i: int in 20:
		await get_tree().physics_frame
	player.global_position = car.get_exit_points()[0]
	player.reset_physics_interpolation()
	for i: int in 5:
		await get_tree().physics_frame
	player.enter_vehicle(car, car.get_exit_points()[0])
	for i: int in 70:
		await get_tree().physics_frame
	var damage := car.get_node("Damage") as VehicleDamage
	if args.has("health"):
		damage.apply_damage(damage.health - car.stats.max_health * float(args["health"]))
	if args.has("headlights"):
		car.set_headlights(true)
	if args.has("hood"):
		(game.get_node("VehicleCamera") as VehicleCamera).set_mode(VehicleCamera.Mode.HOOD)
	var frames: int = int(args.get("throttle", "0"))
	var steer: float = float(args.get("steer", "0"))
	if frames > 0:
		Input.action_press("vehicle_accelerate")
		if steer > 0.0:
			Input.action_press("vehicle_steer_left", steer)
		elif steer < 0.0:
			Input.action_press("vehicle_steer_right", -steer)
		for i: int in frames:
			await get_tree().physics_frame
	print("DRIVE  %.0f km/h, gear %s, health %.0f, at %s" % [car.get_speed_kmh(), (car.get_node("Engine") as VehicleEngine).get_gear_text(), damage.health, car.global_position])


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg: String in raw:
		if arg.begins_with("--") and arg.contains("="):
			var key: String = arg.substr(2, arg.find("=") - 2)
			result[key] = arg.substr(arg.find("=") + 1)
		elif arg.begins_with("--"):
			result[arg.substr(2)] = "true"
	return result


func _vec3(text: String) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
