class_name HumanBaker
extends RefCounted
## Turns a rigged person GLB (tools/blender/humans.py) into what every figure of that kind
## shares, built once and cached: one skinned surface for shaders/human.gdshader (each vertex
## records its base colour, roughness and which colour channel tints it), the skin binding it
## to the skeleton, and the animation library with the looping clips set to loop.

const SHADER: Shader = preload("res://shaders/human.gdshader")
const TINTS: Dictionary = {"chr_top": 1, "chr_bottom": 2, "chr_skin": 3, "chr_hair": 4}
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"fall", &"guard", &"down", &"sit", &"drive", &"talk"]

static var _cache: Dictionary = {}
static var _material: ShaderMaterial


## {"mesh": ArrayMesh, "skin": Skin, "library": AnimationLibrary} for the person in `look`.
static func get_parts(look: PackedScene) -> Dictionary:
	if not _cache.has(look.resource_path):
		var root := look.instantiate() as Node3D
		var body := root.find_child("Body", true, false) as MeshInstance3D
		var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_cache[look.resource_path] = {
			"mesh": bake(body.mesh),
			"skin": body.skin,
			"library": loop_clips(player.get_animation_library(&"")),
		}
		root.free()
	return _cache[look.resource_path]


static func get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## One surface from the model's surfaces (one per material), keeping the bone weights.
static func bake(mesh: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for surface: int in mesh.get_surface_count():
		var mat := mesh.surface_get_material(surface) as BaseMaterial3D
		var colour := Color(0.8, 0.8, 0.8)
		var roughness: float = 0.85
		var channel: int = 0
		if mat != null:
			channel = int(TINTS.get(mat.resource_name, 0))
			colour = Color.WHITE if channel > 0 else mat.albedo_color.srgb_to_linear()
			roughness = mat.roughness
		var arrays: Array = mesh.surface_get_arrays(surface)
		var base: int = verts.size()
		var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		bones.append_array(arrays[Mesh.ARRAY_BONES])
		weights.append_array(arrays[Mesh.ARRAY_WEIGHTS])
		for i: int in count:
			colours.append(colour)
			uv2.append(Vector2(roughness, channel))
		for index: int in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			indices.append(base + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, get_material())
	return out


## A copy of the model's clips, the looping ones set to loop and ending on their last key (the
## exporter's closing frame repeats the first pose, so the loop is seamless).
static func loop_clips(source: AnimationLibrary) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for name: StringName in source.get_animation_list():
		var clip := source.get_animation(name).duplicate(true) as Animation
		if name in LOOPING:
			clip.loop_mode = Animation.LOOP_LINEAR
			var last: float = 0.0
			for track: int in clip.get_track_count():
				var keys: int = clip.track_get_key_count(track)
				if keys > 0:
					last = maxf(last, clip.track_get_key_time(track, keys - 1))
			if last > 0.0:
				clip.length = last
		library.add_animation(name, clip)
	return library
