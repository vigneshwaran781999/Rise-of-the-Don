class_name VehicleModel
extends Node3D
## A car's visuals, built from its Blender models when it spawns:
## - the body baked into one palette surface, painted with this car's paint_color,
## - the lamp lenses as a small separate mesh (VehicleLights makes them glow),
## - one baked mesh per wheel, added under each VehicleWheel3D (they spin and steer with it).
## Bakes are cached per model, so every car of a kind shares the same meshes. This turns about
## 21 draw calls per sedan into 8. Must be the vehicle's "Model" child, above Lights.

const LENS_MATERIALS: PackedStringArray = ["veh_headlight", "veh_taillight", "veh_reverselight"]
const PAINT_MATERIALS: PackedStringArray = ["veh_paint"]
const SHADER: Shader = preload("res://shaders/palette_lit.gdshader")

@export var body_scene: PackedScene
@export var wheel_scene: PackedScene
@export var paint_color: Color = Color("a3162b")

static var _cache: Dictionary = {}   # resource path -> ArrayMesh, path + ":lenses" -> ArrayMesh
static var _material: ShaderMaterial

var _body: MeshInstance3D


func _ready() -> void:
	_body = _add_mesh(self, "Body", _baked(body_scene, false))
	_add_mesh(self, "Lenses", _baked(body_scene, true))
	set_paint(paint_color)
	for child: Node in get_parent().get_children():
		var wheel := child as VehicleWheel3D
		if wheel == null:
			continue
		var tyre: MeshInstance3D = _add_mesh(wheel, "Mesh", _baked(wheel_scene, false))
		if wheel.position.x < 0.0:
			tyre.rotation.y = PI   # rims face outwards on the right-hand side too


func set_paint(colour: Color) -> void:
	paint_color = colour
	if _body != null:
		_body.set_instance_shader_parameter(&"tint", colour)


func get_paint() -> Color:
	return paint_color


func _add_mesh(parent: Node, node_name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


static func _baked(scene: PackedScene, lenses: bool) -> ArrayMesh:
	var key: String = scene.resource_path + (":lenses" if lenses else "")
	if not _cache.has(key):
		if _material == null:
			_material = ShaderMaterial.new()
			_material.shader = SHADER
		var root := scene.instantiate() as Node3D
		if lenses:
			_cache[key] = KitBaker.extract_surfaces(root, LENS_MATERIALS)
		else:
			_cache[key] = KitBaker.bake_mesh(root, _material, LENS_MATERIALS, PAINT_MATERIALS)
		root.free()
	return _cache[key]
