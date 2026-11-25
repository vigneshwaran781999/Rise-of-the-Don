extends Node
## Renders a scene in a real window and saves a PNG: a visual sanity check that also surfaces
## shader compile errors (headless runs skip rendering). Not part of the smoke test.
##
##   "$GODOT" --path . res://tests/screenshot.tscn -- --scene=res://scenes/main/game.tscn \
##       --out=C:/path/shot.png [--frames=90] [--view=yaw,pitch] [--cam=x,y,z --look=x,y,z]
##       [--pause] [--press=ButtonName,OtherButton]
##       [--drive [--throttle=frames] [--steer=-1..1] [--hood] [--health=0..1] [--headlights]] [--lanes]
##       [--crowd[=x,y,z]] [--chase[=n]] [--hour=0..24] [--waypoint=x,z]
##       [--wanted=1..5 [--police=off|car|roadblock|heli]] [--outfit=id] [--shop=id] [--mission=id[:n] [--talk]]
##
## --view sets the player camera angles in degrees; --cam/--look place a free camera instead.
## --pause opens the pause menu; --press presses buttons (found by node name) in order.
## --drive puts the player in the test block's sedan; --throttle holds the accelerator for that
## many frames (with --steer), --hood picks the hood camera, --health sets the car's health share
## (below 0.35 it smokes), --headlights switches them on. --lanes shows the F4 lane/navmesh view.
## --crowd puts pedestrians at the --look point, or at x,y,z (chatting, walking, one going to sit down).
## --chase looks over traffic car n (default the first) once the frames have passed.
## --hour sets the in-game clock (day/night) before the frames run; --waypoint=x,z sets a GPS waypoint.
## --outfit dresses the player (an Outfit id); --shop=id puts them at that shop or property's door
## and opens it (the shop menu, or the offer for a property on sale).

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
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # a still camera: its view at once
		cam.fov = float(args.get("fov", "60"))
		cam.far = 2000.0
		add_child(cam)
		cam.global_position = _vec3(str(args["cam"]))
		cam.look_at(_vec3(str(args.get("look", "0,0,0"))), Vector3.UP)
		cam.make_current()
	await get_tree().process_frame
	if args.has("waypoint") and instance.has_node("Gps"):
		var at: PackedStringArray = str(args["waypoint"]).split(",")
		(instance.get_node("Gps") as GpsNavigator).set_waypoint(Vector3(float(at[0]), 0.0, float(at[1])))
	if args.has("hour"):
		GameState.set_hour(float(args["hour"]))
		var cycle := instance.get_node_or_null("DayNight") as DayNightCycle
		if cycle != null:
			cycle.refresh()
	if args.has("lanes") and instance.has_node("LaneDebug"):
		(instance.get_node("LaneDebug") as LaneGraphDebug).visible = true
	if args.has("drive"):
		await _drive(instance, args)
	if args.has("wanted"):
		await _police(instance, args)
	if args.has("outfit"):
		GameState.set_outfit(StringName(str(args["outfit"])))
	if args.has("shop"):
		await _shop(instance, StringName(str(args["shop"])))
	if args.has("mission"):
		await _mission(instance, str(args["mission"]), args.has("talk"))
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
	if str(args.get("police", "")) == "heli":
		await _look_at_helicopter(instance)
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


## --wanted=1..5 makes the player wanted. --police picks a scene: "off" (no units appear, so
## out of sight the police start searching: stars blinking, search circle on the minimap),
## "car" (a police car parked at the lane nearest the --look point, lights flashing, nobody
## driving), "roadblock" (needs --drive: a roadblock with a spike strip ahead of the car, seen
## from up the road), "heli" (only the helicopter, close by; the camera looks up at it at the end).
func _police(game: Node, args: Dictionary) -> void:
	var police := game.get_node("Police") as PoliceManager
	var player := game.get_node("Player") as PlayerController
	var kind: String = str(args.get("police", ""))
	police.enabled = kind == "" or kind == "heli"
	WantedSystem.set_level(int(args["wanted"]), player.global_position)
	if kind == "car":
		var router: RoadRouter = RoadRouter.for_graph((game.get_node("World") as District).get_lane_graph())
		var car: VehicleController = police.spawn_car_at(router.nearest_node(_vec3(str(args.get("look", "0,0,0")))))
		car.get_node("Driver").queue_free()
		car.set_controls(0.0, 0.0, 0.0, true)
	elif kind == "roadblock" and player.is_in_vehicle():
		var block: Node3D = police.place_roadblock_ahead(true)
		if block == null:
			push_warning("screenshot: no room for a roadblock ahead")
			return
		# Seen from up the road: the spike strip lies 14 m before the block along it.
		var strip := block.find_child("SpikeStrip", true, false) as Node3D
		var back: Vector3 = strip.global_position - block.global_position
		back.y = 0.0
		var cam := Camera3D.new()
		cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # a still camera: its view at once
		cam.fov = 60.0
		add_child(cam)
		cam.global_position = strip.global_position + back.normalized() * 12.0 + Vector3(0.0, 4.0, 0.0)
		cam.look_at(block.global_position + Vector3.UP * 0.5, Vector3.UP)
		cam.make_current()
	elif kind == "heli":
		# Only the helicopter (officers would make an arrest first), brought in close.
		for i: int in 3:
			await get_tree().physics_frame
		police.enabled = false
		for car: VehicleController in police.get_cars():
			car.queue_free()
		for officer: PoliceOfficer in police.get_officers():
			officer.queue_free()
		var heli: PoliceHelicopter = police.get_helicopter()
		if heli != null:
			heli.global_position = player.global_position + Vector3(25.0, PoliceHelicopter.ALTITUDE, 25.0)
	await get_tree().process_frame


func _look_at_helicopter(game: Node) -> void:
	var heli: PoliceHelicopter = (game.get_node("Police") as PoliceManager).get_helicopter()
	if heli == null:
		return
	var player := game.get_node("Player") as PlayerController
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # a still camera: its view at once
	cam.fov = 70.0
	cam.far = 2000.0
	add_child(cam)
	var side: Vector3 = (player.global_position - heli.global_position)
	side.y = 0.0
	cam.global_position = player.global_position + side.normalized() * 18.0 + Vector3(0.0, 3.0, 0.0)
	cam.look_at(heli.global_position.lerp(player.global_position, 0.45), Vector3.UP)
	cam.make_current()
	# A new camera's view only takes effect on the next frames (physics interpolation).
	for i: int in 3:
		await get_tree().process_frame


## Puts a camera behind and above traffic car number `which` (in the traffic manager's list;
## anything else = the first), looking up the road ahead of it.
func _chase(game: Node, which: String) -> void:
	var traffic := game.get_node_or_null("Traffic") as TrafficManager
	if traffic == null or traffic.get_cars().is_empty():
		return
	var cars: Array[VehicleController] = traffic.get_cars()
	var car: VehicleController = cars[(int(which) if which.is_valid_int() else 0) % cars.size()]
	var cam := Camera3D.new()
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF     # a still camera: its view at once
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


func _shop(game: Node, place_id: StringName) -> void:
	var places := game.get_node("Places") as PlaceDirector
	var player := game.get_node("Player") as PlayerController
	var at := Vector3.ZERO
	var shop: ShopData = places.get_shop(place_id)
	var property: PropertyData = places.get_property(place_id)
	if shop != null:
		at = places.get_spot(shop)
	elif property != null:
		at = places.get_place(property.place).origin
	else:
		push_warning("screenshot: no shop or property '%s'" % place_id)
		return
	(game.get_node("World") as District).streamer.load_around_now(at)
	player.global_position = at + Vector3.UP * 0.1
	player.reset_physics_interpolation()
	# Wait for the prompt (opening dialogue keeps the interact key for a few seconds).
	for i: int in 60 * 20:
		await get_tree().physics_frame
		if places.get_prompt()[0] != "":
			break
	places.interact()


## --mission=id[:n]: story mission `id` starts (the missions listed before it count as passed) and
## skips to its objective n; with --talk the player then walks up to that objective's contact and
## presses interact (a dialogue scene shows its camera and letterbox).
func _mission(game: Node, spec: String, talk: bool) -> void:
	var id := StringName(spec.get_slice(":", 0))
	var skip: int = int(spec.get_slice(":", 1)) if spec.contains(":") else 0
	MissionManager.quit_mission()
	var done: Array[String] = []
	for mission: MissionData in MissionManager.story.missions:
		if mission.id == id:
			break
		done.append(String(mission.id))
	MissionManager.from_save({"completed": done})
	await get_tree().physics_frame
	MissionManager.start(id)
	for i: int in skip:
		MissionManager.complete_objective()
	for i: int in 10:
		await get_tree().physics_frame
	if not talk:
		return
	var director := game.get_node("Missions") as MissionDirector
	var npc: MissionContactNPC = director.get_contact(MissionManager.get_objective().contact)
	if npc == null:
		push_warning("screenshot: the objective has no contact to talk to")
		return
	var player := game.get_node("Player") as PlayerController
	(game.get_node("World") as District).streamer.load_around_now(npc.global_position)
	player.global_position = npc.global_position + npc.global_basis.z * 1.7 + Vector3.UP * 0.1
	player.reset_physics_interpolation()
	for i: int in 20:
		await get_tree().physics_frame
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
