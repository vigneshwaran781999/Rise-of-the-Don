class_name OccluderBatch
extends Node3D
## A chunk's box occluders (occlusion culling inside buildings' upper floors). The boxes are
## stored as plain data and the occluders are made when the chunk enters the tree, on the main
## thread: chunks are loaded on a background thread, and creating occluders there races with the
## main thread (Godot's occluder store is not thread-safe), which corrupted occluder RIDs.

## 15 floats per box: its transform (12, the InstanceBatch layout) then its size (3).
@export var boxes: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	for i: int in get_box_count():
		var v: PackedFloat32Array = boxes.slice(i * 15, i * 15 + 15)
		var occluder := BoxOccluder3D.new()
		occluder.size = Vector3(v[12], v[13], v[14])
		var instance := OccluderInstance3D.new()
		instance.occluder = occluder
		instance.transform = Transform3D(Basis(Vector3(v[0], v[4], v[8]), Vector3(v[1], v[5], v[9]), Vector3(v[2], v[6], v[10])),
			Vector3(v[3], v[7], v[11]))
		add_child(instance)


func get_box_count() -> int:
	return boxes.size() / 15


## Packs [Transform3D, size] pairs into the layout above (build time).
static func pack(entries: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for entry: Array in entries:
		out.append_array(InstanceBatch.pack([entry[0]]))
		var size: Vector3 = entry[1]
		out.append_array(PackedFloat32Array([size.x, size.y, size.z]))
	return out
