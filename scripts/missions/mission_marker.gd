class_name MissionMarker
extends Node3D
## A mission marker in the world (GDD §8).
## - START: a magenta light beam and ground ring where a mission can be started.
## - GOAL: a cyan beam and ring around a place to go (the ring shows the arrival radius).
## - TARGET: a floating cyan diamond above a person or vehicle (parent it to them).
## Unlit and additive, so it reads in any light; casts no shadows.

enum Kind { START, GOAL, TARGET }

const START_COLOUR := Color("ff2bd6")
const GOAL_COLOUR := Color("22e6ff")
const BEAM_HEIGHT: float = 30.0

var kind: Kind = Kind.GOAL
var _ring: MeshInstance3D
var _diamond: MeshInstance3D
var _time: float = 0.0
var _diamond_height: float = 0.0


## Builds the marker; `radius` is the ground ring for START and GOAL, `height` how high the
## TARGET diamond floats above the parent's origin.
func setup(marker_kind: Kind, radius: float = 2.0, height: float = 2.6) -> void:
	kind = marker_kind
	var colour: Color = START_COLOUR if kind == Kind.START else GOAL_COLOUR
	if kind == Kind.TARGET:
		_diamond = _mesh_instance(_diamond_mesh(), _material(colour, 0.9, false))
		_diamond_height = height
		_diamond.position = Vector3(0.0, height, 0.0)
		return
	var beam := CylinderMesh.new()
	beam.top_radius = 0.35
	beam.bottom_radius = 0.35
	beam.height = BEAM_HEIGHT
	beam.cap_top = false
	beam.cap_bottom = false
	beam.radial_segments = 12
	var beam_instance: MeshInstance3D = _mesh_instance(beam, _material(colour, 0.55, true))
	beam_instance.position = Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(radius - 0.18, 0.1)
	ring.outer_radius = radius
	ring.rings = 48
	ring.ring_segments = 6
	_ring = _mesh_instance(ring, _material(colour, 0.8, false))
	_ring.position = Vector3(0.0, 0.12, 0.0)
	_ring.scale = Vector3(1.0, 0.25, 1.0)


## How high above the marker's origin the HUD should put its waypoint (just over the diamond
## of a TARGET, about head height for a beam).
func get_label_height() -> float:
	return _diamond_height + 0.55 if kind == Kind.TARGET else 1.2


func _process(delta: float) -> void:
	_time += delta
	if _ring != null:
		var pulse: float = 1.0 + sin(_time * 3.0) * 0.04
		_ring.scale = Vector3(pulse, 0.25, pulse)
	if _diamond != null:
		_diamond.rotation.y = _time * 1.6
		_diamond.position.y = _diamond_height + sin(_time * 2.4) * 0.12


func _mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


## A double pyramid (the classic "go here" diamond).
static func _diamond_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.62
	sphere.radial_segments = 4
	sphere.rings = 1
	return sphere


## Unlit additive glow. A beam fades out towards the top.
static func _material(colour: Color, strength: float, fade_up: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.albedo_color = Color(colour, strength)
	if fade_up:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0.0))
		gradient.set_color(1, Color(1, 1, 1, 1.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill_from = Vector2(0.0, 0.0)
		texture.fill_to = Vector2(0.0, 1.0)
		texture.width = 4
		texture.height = 64
		material.albedo_texture = texture
	return material
