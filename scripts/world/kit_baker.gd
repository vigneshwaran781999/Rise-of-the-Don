class_name KitBaker
extends RefCounted
## Turns an imported GLB scene into a KitPiece (build time only; see
## tools/godot/build_old_town.gd). Every surface of every mesh is merged into ONE surface whose
## vertices carry their material's colour, roughness, metallic and glow (read by
## shaders/palette_lit.gdshader), so the piece costs one draw call however many materials the
## Blender model used. Every collision shape becomes a convex hull (point cloud).

## 1 mm grid used to weld trimesh vertices when splitting a '-colonly' mesh into pieces.
const WELD_SCALE: float = 1000.0
## Materials that only glow at night (scaled by the city_lights shader global; GDD §12), stored
## in the glow's alpha: 1 = glows at night (streetlight lenses, brighter than their daytime
## material), 2 = lit window (some buildings and floors stay dark, chosen in the shader).
const NIGHT_GLOW: Dictionary = {
	"lamp_lens": {"mode": 1.0, "boost": 1.8},
	"window_glass": {"mode": 2.0, "emission": Color(1.0, 0.6, 0.28), "energy": 0.75},
}


static func bake(scene: PackedScene, material: Material) -> KitPiece:
	var root := scene.instantiate() as Node3D
	var piece := KitPiece.new()
	piece.mesh = bake_mesh(root, material)
	piece.bounds = piece.mesh.get_aabb()
	piece.hulls = collect_hulls(root)
	root.free()
	return piece


## Surfaces whose material is named in `exclude` are left out (see extract_surfaces()); those
## named in `tint` take each instance's `tint` colour instead of their own (car paint).
static func bake_mesh(root: Node3D, material: Material, exclude: PackedStringArray = PackedStringArray(),
		tint: PackedStringArray = PackedStringArray()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var xf: Transform3D = relative_transform(root, mesh_instance)
		var normal_basis: Basis = xf.basis.inverse().transposed()
		var mesh: Mesh = mesh_instance.mesh
		for surface: int in mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if mat != null and exclude.has(mat.resource_name):
				continue
			var albedo := Color(0.8, 0.8, 0.8)
			var roughness: float = 0.9
			var metallic: float = 0.0
			var emission := Color(0, 0, 0)
			var glow_mode: float = 0.0
			var double_sided: bool = false
			if mat != null:
				albedo = mat.albedo_color.srgb_to_linear()
				roughness = mat.roughness
				metallic = mat.metallic
				if mat.emission_enabled:
					emission = mat.emission.srgb_to_linear() * mat.emission_energy_multiplier
				double_sided = mat.cull_mode == BaseMaterial3D.CULL_DISABLED
				var night: Dictionary = NIGHT_GLOW.get(mat.resource_name, {})
				if not night.is_empty():
					if night.has("emission"):
						emission = (night["emission"] as Color) * float(night["energy"])
					else:
						emission = emission * float(night.get("boost", 1.0))
					glow_mode = float(night["mode"])
			emission.a = glow_mode      # 0 = always glows (if it has a glow at all)
			albedo.a = 0.0 if mat != null and tint.has(mat.resource_name) else 1.0
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				indices.resize(verts.size())
				for i: int in verts.size():
					indices[i] = i
			for back: bool in ([false, true] if double_sided else [false]):
				for t: int in range(0, indices.size(), 3):
					for k: int in ([0, 2, 1] if back else [0, 1, 2]):
						var i: int = indices[t + k]
						var n: Vector3 = (normal_basis * normals[i]).normalized()
						st.set_color(albedo)
						st.set_uv2(Vector2(roughness, metallic))
						st.set_custom(0, emission)
						st.set_normal(-n if back else n)
						st.add_vertex(xf * verts[i])
	st.index()
	var out: ArrayMesh = st.commit()
	out.surface_set_material(0, material)
	return out


## The surfaces whose material is named in `names`, merged in root space with their original
## materials (one surface per material): e.g. lamp lenses that are switched on at runtime.
static func extract_surfaces(root: Node3D, names: PackedStringArray) -> ArrayMesh:
	var tools: Dictionary = {}   # material name -> [SurfaceTool, Material]
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var xf: Transform3D = relative_transform(root, mesh_instance)
		for surface: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(surface)
			if mat == null or not names.has(mat.resource_name):
				continue
			if not tools.has(mat.resource_name):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mat)
				tools[mat.resource_name] = st
			(tools[mat.resource_name] as SurfaceTool).append_from(mesh_instance.mesh, surface, xf)
	var out := ArrayMesh.new()
	for key: String in tools:
		(tools[key] as SurfaceTool).commit(out)
	return out


## Convex hulls of all collision shapes, in root space. A trimesh ('-colonly') shape is split
## into its separate closed pieces first, so two boxes stay two hulls.
static func collect_hulls(root: Node3D) -> Array[PackedVector3Array]:
	var hulls: Array[PackedVector3Array] = []
	for node: Node in root.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		var xf: Transform3D = relative_transform(root, shape_node)
		var shape: Shape3D = shape_node.shape
		if shape is ConvexPolygonShape3D:
			hulls.append(_transformed(xf, (shape as ConvexPolygonShape3D).points))
		elif shape is BoxShape3D:
			var h: Vector3 = (shape as BoxShape3D).size * 0.5
			var corners := PackedVector3Array()
			for sx: float in [-1.0, 1.0]:
				for sy: float in [-1.0, 1.0]:
					for sz: float in [-1.0, 1.0]:
						corners.append(Vector3(h.x * sx, h.y * sy, h.z * sz))
			hulls.append(_transformed(xf, corners))
		elif shape is ConcavePolygonShape3D:
			for piece: PackedVector3Array in split_pieces((shape as ConcavePolygonShape3D).get_faces()):
				hulls.append(_transformed(xf, piece))
	return hulls


## Groups triangle-soup faces into connected pieces (by welded shared vertices) and returns
## each piece's unique points.
static func split_pieces(faces: PackedVector3Array) -> Array[PackedVector3Array]:
	var ids: Dictionary = {}
	var points: Array[Vector3] = []
	var parent: Array[int] = []
	var corner_ids := PackedInt32Array()
	for p: Vector3 in faces:
		var key := Vector3i(roundi(p.x * WELD_SCALE), roundi(p.y * WELD_SCALE), roundi(p.z * WELD_SCALE))
		if not ids.has(key):
			ids[key] = points.size()
			points.append(p)
			parent.append(points.size() - 1)
		corner_ids.append(int(ids[key]))
	for t: int in range(0, corner_ids.size(), 3):
		_union(parent, corner_ids[t], corner_ids[t + 1])
		_union(parent, corner_ids[t], corner_ids[t + 2])
	var groups: Dictionary = {}
	for i: int in points.size():
		var r: int = _find(parent, i)
		if not groups.has(r):
			groups[r] = PackedVector3Array()
		(groups[r] as PackedVector3Array).append(points[i])
	var out: Array[PackedVector3Array] = []
	for r: int in groups:
		out.append(groups[r])
	return out


static func relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func _transformed(xf: Transform3D, pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i: int in pts.size():
		out[i] = xf * pts[i]
	return out


static func _find(parent: Array[int], i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _union(parent: Array[int], a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[rb] = ra
