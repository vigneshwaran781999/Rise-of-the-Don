extends SceneTree

func _init() -> void:
	var scene := load("res://assets/models/characters/chr_man.glb") as PackedScene
	var root := scene.instantiate()
	_print(root, 0)
	var skel := root.find_child("*", true, false) as Node
	for n: Node in root.find_children("*", "Skeleton3D", true, false):
		var s := n as Skeleton3D
		print("SKELETON %s bones %d: %s" % [s.get_path(), s.get_bone_count(), ", ".join(PackedStringArray(range(s.get_bone_count()).map(func(i: int) -> String: return s.get_bone_name(i))))])
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		print("MESH %s surfaces %d skin %s" % [mi.name, mi.mesh.get_surface_count(), mi.skin != null])
		for i: int in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(i)
			print("  surface %d %s verts %d bones %s weights %s" % [i, mi.mesh.surface_get_material(i).resource_name if mi.mesh.surface_get_material(i) else "-",
				(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), arrays[Mesh.ARRAY_BONES] != null, arrays[Mesh.ARRAY_WEIGHTS] != null])
	for n: Node in root.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		for name: StringName in ap.get_animation_list():
			var a: Animation = ap.get_animation(name)
			print("ANIM %-10s %.2f s loop %d tracks %d (first %s)" % [name, a.length, a.loop_mode, a.get_track_count(), a.track_get_path(0)])
	root.free()
	quit(0)

func _print(n: Node, depth: int) -> void:
	print("  ".repeat(depth) + "%s (%s)" % [n.name, n.get_class()])
	for c: Node in n.get_children():
		_print(c, depth + 1)
