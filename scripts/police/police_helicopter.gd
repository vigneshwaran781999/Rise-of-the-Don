class_name PoliceHelicopter
extends Node3D
## The police helicopter (GDD §7, wanted level 5): flies at searchlight height towards the
## player (or where they were last seen), circling over them, its searchlight on the target and
## its rotor turning and thudding. It sees a long way, so it is hard to lose.

const MODEL: PackedScene = preload("res://assets/models/vehicles/veh_police_heli.glb")
const ALTITUDE: float = 38.0
const SPEED: float = 24.0
const ORBIT: float = 22.0
## How bright the searchlight beam looks at full night (share of the light's colour added).
const BEAM_STRENGTH: float = 0.03

static var _rotor_sound: AudioStreamWAV

## Where it is heading for (the player or where they were last seen).
var target := Vector3.ZERO

var _rotor: Node3D
var _tail_rotor: Node3D
var _light: SpotLight3D
var _beam: MeshInstance3D
var _time: float = 0.0


func _ready() -> void:
	name = "Helicopter"
	var model := MODEL.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_rotor = model.find_child("rotor", true, false) as Node3D
	_tail_rotor = model.find_child("tail_rotor", true, false) as Node3D
	_light = SpotLight3D.new()
	_light.name = "Searchlight"
	_light.spot_range = 70.0
	_light.spot_angle = 11.0
	_light.light_energy = 14.0
	_light.light_color = Color(1.0, 0.97, 0.88)
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.4, -1.8)
	add_child(_light)
	# The beam itself, seen in the dark: a faint additive cone down the light's -Z (a cylinder
	# 1 m long and 1 m wide at its far end, stretched to reach the ground each frame).
	_beam = MeshInstance3D.new()
	_beam.name = "Beam"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.04
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 16
	cone.cap_top = false
	cone.cap_bottom = false
	_beam.mesh = cone
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	glow.albedo_color = Color.BLACK
	_beam.material_override = glow
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light.add_child(_beam)
	if _rotor_sound == null:
		_rotor_sound = AudioSynth.rotor_loop()
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _rotor_sound
	sound.bus = &"SFX"
	sound.unit_size = 30.0
	sound.max_distance = 260.0
	sound.autoplay = true
	add_child(sound)


func get_searchlight() -> SpotLight3D:
	return _light


func _process(delta: float) -> void:
	_time += delta
	if _rotor != null:
		_rotor.rotate_y(delta * 28.0)
	if _tail_rotor != null:
		_tail_rotor.rotate_x(delta * 40.0)
	# Circle the target at altitude, nose along the way it flies.
	var orbit := Vector3(cos(_time * 0.35), 0.0, sin(_time * 0.35)) * ORBIT
	var wanted: Vector3 = target + orbit + Vector3.UP * ALTITUDE
	var to: Vector3 = wanted - global_position
	var step: Vector3 = to.limit_length(SPEED * delta)
	global_position += step
	var flat := Vector3(step.x, 0.0, step.z)
	if flat.length() > 0.001:
		var heading: float = atan2(flat.x, flat.z)       # the model's nose is its +Z
		rotation.y = lerp_angle(rotation.y, heading, 1.0 - exp(-2.0 * delta))
	rotation.x = lerpf(rotation.x, clampf(flat.length() / maxf(delta, 0.001) / SPEED, 0.0, 1.0) * 0.15, 1.0 - exp(-3.0 * delta))   # nose down when moving
	# The searchlight looks at the target; the beam shows after dark.
	var reach: float = _light.global_position.distance_to(target)
	if reach > 1.0:
		_light.look_at(target + Vector3.UP * 0.5, Vector3.UP)
	var darkness: float = GameState.get_darkness()
	_beam.visible = darkness > 0.05 and reach > 1.0
	if _beam.visible:
		var width: float = tan(deg_to_rad(_light.spot_angle)) * reach
		_beam.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(width, reach, width)), Vector3(0.0, 0.0, -reach * 0.5))
		# Additive: colour x alpha is added, through both faces of the cone.
		(_beam.material_override as StandardMaterial3D).albedo_color = Color(_light.light_color, BEAM_STRENGTH * darkness)
