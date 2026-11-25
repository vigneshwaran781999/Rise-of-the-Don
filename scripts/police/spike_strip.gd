class_name SpikeStrip
extends Area3D
## A spike strip laid across the road (GDD §7, wanted level 4+): any vehicle driving over it gets
## its tyres burst. Built in code: a low yellow-and-black strip with a row of steel spikes,
## `width` metres long across the road (its local X).

const HAZARD_YELLOW := Color("e8b81c")
## Length of each hazard stripe.
const STRIPE: float = 0.45

var width: float = 9.0


func _ready() -> void:
	name = "SpikeStrip"
	collision_layer = 0
	collision_mask = 4          # vehicles
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 0.6, 0.9)
	shape.shape = box
	shape.position = Vector3(0.0, 0.3, 0.0)
	add_child(shape)
	# Yellow base with black segments over it (hazard stripes), faintly glowing like reflective
	# tape so a driver can see it coming at night too.
	var strip := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.04, 0.45)
	strip.mesh = mesh
	strip.material_override = _paint(HAZARD_YELLOW, 0.35)
	strip.position = Vector3(0.0, 0.03, 0.0)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	var count: int = maxi(3, int(width / STRIPE))
	var seg: float = width / count
	var stripe := BoxMesh.new()
	stripe.size = Vector3(seg, 0.044, 0.454)
	var stripes := MultiMesh.new()
	stripes.transform_format = MultiMesh.TRANSFORM_3D
	stripes.mesh = stripe
	stripes.instance_count = count / 2
	for i: int in stripes.instance_count:
		stripes.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(-width * 0.5 + (2 * i + 1.5) * seg, 0.03, 0.0)))
	var black := MultiMeshInstance3D.new()
	black.multimesh = stripes
	black.material_override = _paint(Color("1b1c1f"), 0.0)
	black.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(black)
	var spikes := MeshInstance3D.new()
	var spike_mesh := BoxMesh.new()
	spike_mesh.size = Vector3(width - 0.2, 0.08, 0.06)
	spikes.mesh = spike_mesh
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("c8ccd2")
	steel.metallic = 0.9
	steel.roughness = 0.3
	spikes.material_override = steel
	spikes.position = Vector3(0.0, 0.08, 0.0)
	add_child(spikes)
	body_entered.connect(_on_body_entered)


static func _paint(colour: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.6
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = glow
	return material


func _on_body_entered(body: Node3D) -> void:
	var vehicle := body as VehicleController
	if vehicle != null:
		vehicle.burst_tyres()
