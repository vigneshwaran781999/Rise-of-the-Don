extends Node
## Performance baseline for the streamed Old Town (milestone M3). Runs the real game scene in a
## 1920x1080 window with VSync off, measures several fixed viewpoints and a streaming drive across
## the district, and prints a Markdown report (paste it into docs/PERFORMANCE.md).
##   "$GODOT" --path . res://tests/perf_baseline.tscn
## Needs a real GPU (not --headless). Takes about a minute; a window opens while it runs.

const GAME: PackedScene = preload("res://scenes/main/game.tscn")
const WARMUP_FRAMES: int = 90
const MEASURE_FRAMES: int = 240
## [name, camera position, look-at point]
const VIEWS: Array = [
	["Spawn street, looking at the east gopuram", Vector3(73.5, 1.9, 1.5), Vector3(36.0, 8.0, 0.0)],
	["Signalized junction (Ring B x north road)", Vector3(9.0, 1.7, 140.0), Vector3(0.0, 2.0, 112.0)],
	["Narrow lane (x = 80), houses both sides", Vector3(80.0, 1.7, -30.0), Vector3(80.0, 1.5, -80.0)],
	["Market square", Vector3(-58.0, 1.8, -58.0), Vector3(-80.0, 2.0, -80.0)],
	["Temple courtyard", Vector3(22.0, 1.7, 20.0), Vector3(-4.0, 8.0, 0.0)],
	["Rooftop height over the tank", Vector3(60.0, 14.0, 60.0), Vector3(-20.0, 0.0, -20.0)],
	["Aerial, whole district (worst case)", Vector3(150.0, 170.0, 150.0), Vector3(0.0, 0.0, 0.0)],
]
const DRIVE_SPEED: float = 20.0   # m/s (72 km/h) along Ring B for the streaming run

var _game: Node
var _camera: Camera3D
var _rows: PackedStringArray = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Settings.persist = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_window().size = Vector2i(1920, 1080)
	_game = GAME.instantiate()
	add_child(_game)
	await _frames(30)
	var world := _game.get_node("World") as District
	var player := _game.get_node("Player") as PlayerController
	(_game.get_node("HUD") as CanvasLayer).hide()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera = Camera3D.new()
	_camera.far = 2000.0
	_camera.fov = 70.0
	add_child(_camera)
	_camera.make_current()

	var results: Array = []
	for view: Array in VIEWS:
		results.append(await _measure_view(world, player, view, true))
	results.append(await _measure_view(world, player, VIEWS[0], false))
	# Where the time goes: the fixed cost of the screen (sky only), then the spawn view with the
	# heaviest screen effects switched off and at a lower 3D render resolution.
	results.append(await _measure_view(world, player, ["Sky only (fixed per-pixel cost)", Vector3(73.5, 1.9, 1.5), Vector3(73.5, 50.0, 1.6)], true))
	var env: Environment = (world.get_node("Lighting").find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	env.ssao_enabled = false
	results.append(await _measure_view(world, player, [VIEWS[0][0] + " - SSAO off", VIEWS[0][1], VIEWS[0][2]], true))
	env.glow_enabled = false
	results.append(await _measure_view(world, player, [VIEWS[0][0] + " - SSAO and glow off", VIEWS[0][1], VIEWS[0][2]], true))
	env.ssao_enabled = true
	env.glow_enabled = true
	get_viewport().scaling_3d_scale = 0.75
	results.append(await _measure_view(world, player, [VIEWS[0][0] + " - 75% 3D resolution", VIEWS[0][1], VIEWS[0][2]], true))
	get_viewport().scaling_3d_scale = 1.0
	var drive: Dictionary = await _streaming_drive(world)
	_print_report(results, drive)
	AudioManager.quit_game(0)


func _measure_view(world: District, player: PlayerController, view: Array, occlusion: bool) -> Dictionary:
	var pos: Vector3 = view[1]
	player.global_position = Vector3(pos.x, 0.2, pos.z)
	world.streamer.focus = player
	world.streamer.load_around_now(player.global_position)
	_camera.global_position = pos
	_camera.look_at(view[2], Vector3.UP)
	get_viewport().use_occlusion_culling = occlusion
	await _frames(WARMUP_FRAMES)
	var times := PackedFloat32Array()
	var draw: float = 0.0
	var objects: float = 0.0
	var prims: float = 0.0
	var last: int = Time.get_ticks_usec()
	for i: int in MEASURE_FRAMES:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	get_viewport().use_occlusion_culling = true
	var stats: Dictionary = _frame_stats(times)
	stats["name"] = str(view[0]) + ("" if occlusion else " (occlusion culling OFF)")
	stats["draw"] = draw / MEASURE_FRAMES
	stats["objects"] = objects / MEASURE_FRAMES
	stats["prims"] = prims / MEASURE_FRAMES
	stats["vram"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	stats["chunks"] = world.streamer.get_loaded_count()
	print("  measured: %s  %.0f FPS" % [stats["name"], stats["fps"]])
	return stats


## A car-height camera travels along Ring B (z = 112) from the west edge to the east edge at
## DRIVE_SPEED while chunks stream in and out around it; records frame times (hitches).
func _streaming_drive(world: District) -> Dictionary:
	var marker := Node3D.new()
	add_child(marker)
	marker.global_position = Vector3(-240.0, 0.2, 109.0)
	world.streamer.focus = marker
	world.streamer.load_around_now(marker.global_position)
	await _frames(WARMUP_FRAMES)
	var loads: Array[int] = [0, 0]
	var on_load := func(_c: Vector2i) -> void: loads[0] += 1
	var on_unload := func(_c: Vector2i) -> void: loads[1] += 1
	world.streamer.chunk_loaded.connect(on_load)
	world.streamer.chunk_unloaded.connect(on_unload)
	var times := PackedFloat32Array()
	var last: int = Time.get_ticks_usec()
	while marker.global_position.x < 240.0:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		var dt: float = (now - last) / 1000000.0
		times.append(dt * 1000.0)
		last = now
		marker.global_position.x += DRIVE_SPEED * minf(dt, 0.05)
		_camera.global_position = marker.global_position + Vector3(-7.0, 2.6, 0.0)
		_camera.look_at(marker.global_position + Vector3(20.0, 0.5, 0.0), Vector3.UP)
	world.streamer.chunk_loaded.disconnect(on_load)
	world.streamer.chunk_unloaded.disconnect(on_unload)
	var stats: Dictionary = _frame_stats(times)
	stats["loads"] = loads[0]
	stats["unloads"] = loads[1]
	stats["seconds"] = 480.0 / DRIVE_SPEED
	return stats


func _frame_stats(times: PackedFloat32Array) -> Dictionary:
	var sorted: PackedFloat32Array = times.duplicate()
	sorted.sort()
	var total: float = 0.0
	for t: float in times:
		total += t
	var avg: float = total / maxf(times.size(), 1)
	var p99: float = sorted[int(sorted.size() * 0.99)] if not sorted.is_empty() else 0.0
	return {"fps": 1000.0 / maxf(avg, 0.001), "avg_ms": avg, "p99_ms": p99,
		"max_ms": sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0}


func _print_report(results: Array, drive: Dictionary) -> void:
	print("")
	print("PERFORMANCE BASELINE (Old Town)")
	print("- GPU: %s (%s)" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()])
	print("- CPU: %s, %d threads" % [OS.get_processor_name(), OS.get_processor_count()])
	print("- Renderer: %s %s, %s, window %s, VSync off" % [ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		RenderingServer.get_video_adapter_api_version(), Engine.get_version_info()["string"], get_window().size])
	print("")
	print("| Viewpoint | FPS | avg ms | 1% worst ms | draw calls | objects | primitives | chunks | VRAM MB |")
	print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
	for r: Dictionary in results:
		print("| %s | %.0f | %.2f | %.2f | %.0f | %.0f | %.0f | %d | %.0f |" % [r["name"], r["fps"], r["avg_ms"], r["p99_ms"],
			r["draw"], r["objects"], r["prims"], r["chunks"], r["vram"]])
	print("")
	print("Streaming drive along Ring B (480 m at %.0f km/h): %.0f FPS average, 1%% worst frame %.1f ms, worst frame %.1f ms, %d chunks loaded and %d unloaded on the way." % [
		DRIVE_SPEED * 3.6, drive["fps"], drive["p99_ms"], drive["max_ms"], drive["loads"], drive["unloads"]])


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame
