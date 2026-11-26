shader_type spatial;
// Pedestrian figures baked by CharacterBaker: one surface per person, coloured and posed per
// instance, so a crowd costs one draw call per person and needs no skeleton.
//   COLOR.rgb   base colour (linear); tinted parts are white so the tint shows as-is
//   UV2.x       part: 0 body, 1 left leg, 2 right leg, 3 left arm, 4 right arm
//   UV2.y       tint channel: 0 none, 1 top, 2 bottom, 3 skin, 4 hair
//   CUSTOM0     xyz = the part's joint (hip or shoulder), w = roughness
// The model faces +Z. Legs and arms swing about their joints (walk cycle); sitting folds the
// legs forwards; a fighting stance raises both arms (guard) and a punch throws the right arm
// straight out in front.
render_mode cull_back, depth_draw_opaque;

instance uniform vec4 top_color : source_color = vec4(1.0);
instance uniform vec4 bottom_color : source_color = vec4(1.0);
instance uniform vec4 skin_color : source_color = vec4(1.0);
instance uniform vec4 hair_color : source_color = vec4(1.0);
// Walk cycle angle (radians, advanced by the pedestrian script) and swing size (radians).
instance uniform float walk_phase = 0.0;
instance uniform float swing = 0.0;
// 0 standing, 1 seated.
instance uniform float sit = 0.0;
// 0 arms down, 1 fists up (a fighting stance); 0-1 how far the right arm is thrown out.
instance uniform float guard = 0.0;
instance uniform float punch = 0.0;

varying float v_tint;
varying float v_roughness;

vec3 rotate_x(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

void vertex() {
	float part = UV2.x;
	v_tint = UV2.y;
	v_roughness = CUSTOM0.w;
	if (part > 0.5) {
		float angle;
		if (part < 2.5) {
			float side = part < 1.5 ? 1.0 : -1.0;
			angle = sin(walk_phase) * swing * side - sit * 0.85;
		} else {
			float side = part < 3.5 ? -1.0 : 1.0;
			angle = sin(walk_phase) * swing * 0.8 * side * (1.0 - guard * 0.7) - sit * 0.3 - guard * 0.75;
			if (part > 3.5) {
				angle -= punch * (1.55 - guard * 0.75);
			}
		}
		vec3 pivot = CUSTOM0.xyz;
		VERTEX = rotate_x(VERTEX - pivot, angle) + pivot;
		NORMAL = rotate_x(NORMAL, angle);
	}
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
