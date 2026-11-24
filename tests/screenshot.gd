extends Node
## Renders a scene in a real window and saves a PNG: a visual sanity check that also surfaces
## shader compile errors (headless runs skip rendering). Not part of the smoke test.
##
##   "$GODOT" --path . res://tests/screenshot.tscn -- --scene=res://scenes/main/game.tscn \
##       --out=C:/path/shot.png [--frames=90] [--view=yaw,pitch] [--cam=x,y,z --look=x,y,z]
##       [--pause] [--press=ButtonName,OtherButton]
##
## --view sets the player camera angles in degrees; --cam/--look place a free camera instead.
## --pause opens the pause menu; --press presses buttons (found by node name) in order.

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
