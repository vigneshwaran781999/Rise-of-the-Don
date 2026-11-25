shader_type spatial;
// Shared material for district meshes baked by KitBaker (tools/godot/build_old_town.gd).
// Each vertex carries its original material's look, so a whole building, road tile or prop is
// one surface and one draw call:
//   COLOR.rgb   albedo (linear)
//   UV2         x = roughness, y = metallic
//   CUSTOM0.rgb emission (linear, already multiplied by its energy)
render_mode cull_back, depth_draw_opaque;

varying vec3 v_emission;

void vertex() {
	v_emission = CUSTOM0.rgb;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = UV2.x;
	METALLIC = UV2.y;
	EMISSION = v_emission;
}
