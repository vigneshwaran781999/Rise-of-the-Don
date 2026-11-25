shader_type spatial;
// Shared material for meshes baked by KitBaker (district buildings, tiles, props, vehicles).
// Each vertex carries its original material's look, so a whole model is one surface and one
// draw call:
//   COLOR.rgb   albedo (linear)
//   COLOR.a     1 = keep COLOR.rgb, 0 = use this instance's tint (e.g. a car's paint)
//   UV2         x = roughness, y = metallic
//   CUSTOM0.rgb emission (linear, already multiplied by its energy)
render_mode cull_back, depth_draw_opaque;

instance uniform vec4 tint : source_color = vec4(1.0);

varying vec3 v_emission;

void vertex() {
	v_emission = CUSTOM0.rgb;
}

void fragment() {
	ALBEDO = mix(tint.rgb, COLOR.rgb, COLOR.a);
	ROUGHNESS = UV2.x;
	METALLIC = UV2.y;
	EMISSION = v_emission;
}
