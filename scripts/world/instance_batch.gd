class_name InstanceBatch
extends MultiMeshInstance3D
## Many copies of one mesh drawn in one go (road tiles, sidewalks, streetlights, trees...).
## The instance transforms are stored as plain data and the MultiMesh is created when the chunk
## loads: a MultiMesh keeps its instances in the rendering server, which the headless district
## builder doesn't have, so a MultiMesh saved from there would be empty.

@export var mesh: Mesh
## 12 floats per instance, MultiMesh 3D buffer layout: basis row x, origin x, row y, origin y, ...
@export var transforms: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size() / 12
	mm.buffer = transforms
	multimesh = mm


func get_instance_count() -> int:
	return transforms.size() / 12


## Packs transforms into the buffer layout above (build time).
static func pack(xforms: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(xforms.size() * 12)
	for i: int in xforms.size():
		var t: Transform3D = xforms[i]
		var b: Basis = t.basis
		var values: Array[float] = [b.x.x, b.y.x, b.z.x, t.origin.x, b.x.y, b.y.y, b.z.y, t.origin.y,
			b.x.z, b.y.z, b.z.z, t.origin.z]
		for k: int in 12:
			out[i * 12 + k] = values[k]
	return out
