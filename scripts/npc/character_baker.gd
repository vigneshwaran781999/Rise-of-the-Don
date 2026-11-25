class_name CharacterBaker
extends RefCounted
## Turns a pedestrian GLB (tools/blender/characters.py) into one mesh for
## shaders/character.gdshader: every vertex records its part (body, legs, arms), the joint it
## swings about, and which colour channel tints it. Baked once per model and cached, so every
## pedestrian of a kind shares the mesh.

const SHADER: Shader = preload("res://shaders/character.gdshader")
const PARTS: Dictionary = {"body": 0, "leg_l": 1, "leg_r": 2, "arm_l": 3, "arm_r": 4}
const TINTS: Dictionary = {"chr_top": 1, "chr_bottom": 2, "chr_skin": 3, "chr_hair": 4}

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


static func get_mesh(scene: PackedScene) -> ArrayMesh:
	if not _meshes.has(scene.resource_path):
		var root := scene.instantiate() as Node3D
		_meshes[scene.resource_path] = bake(root)
		root.free()
	return _meshes[scene.resource_path]


static func get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


static func bake(root: Node3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var part: int = int(PARTS.get(str(mesh_instance.name), 0))
		var xf: Transform3D = KitBaker.relative_transform(root, mesh_instance)
		var normal_basis: Basis = xf.basis.inverse().transposed()
		var mesh: Mesh = mesh_instance.mesh
		for surface: int in mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(surface) as BaseMaterial3D
			var colour := Color(0.8, 0.8, 0.8)
			var roughness: float = 0.85
			var channel: int = 0
			if mat != null:
				colour = mat.albedo_color.srgb_to_linear()
				roughness = mat.roughness
				channel = int(TINTS.get(mat.resource_name, 0))
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i: int in indices:
				st.set_color(colour)
				st.set_uv2(Vector2(part, channel))
				st.set_custom(0, Color(xf.origin.x, xf.origin.y, xf.origin.z, roughness))
				st.set_normal((normal_basis * normals[i]).normalized())
				st.add_vertex(xf * verts[i])
	st.index()
	var out: ArrayMesh = st.commit()
	out.surface_set_material(0, get_material())
	return out
