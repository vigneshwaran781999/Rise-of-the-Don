shader_type spatial;
// Rigged people (M8, HumanBaker): one skinned surface per kind of person, coloured per
// instance, so everyone of a kind shares the mesh and this material.
//   COLOR.rgb   base colour (linear); tinted parts are white so the tint shows as-is
//   UV2.x       roughness
//   UV2.y       tint channel: 0 none, 1 top, 2 bottom, 3 skin, 4 hair
// The skeleton (an AnimationTree) moves the vertices before this shader sees them.
render_mode cull_back, depth_draw_opaque;

instance uniform vec4 top_color : source_color = vec4(1.0);
instance uniform vec4 bottom_color : source_color = vec4(1.0);
instance uniform vec4 skin_color : source_color = vec4(1.0);
instance uniform vec4 hair_color : source_color = vec4(1.0);

varying float v_tint;
varying float v_roughness;

void vertex() {
	v_tint = UV2.y;
	v_roughness = UV2.x;
}

void fragment() {
	vec3 colour = COLOR.rgb;
	int channel = int(v_tint + 0.5);
	if (channel == 1) {
		colour *= top_color.rgb;
	} else if (channel == 2) {
		colour *= bottom_color.rgb;
	} else if (channel == 3) {
		colour *= skin_color.rgb;
	} else if (channel == 4) {
		colour *= hair_color.rgb;
	}
	ALBEDO = colour;
	ROUGHNESS = v_roughness;
}
