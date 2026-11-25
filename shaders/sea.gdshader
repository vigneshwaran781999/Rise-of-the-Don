shader_type spatial;
// The sea along Velanagar's coast (M7). One flat surface; small waves come from the normal alone
// (a few travelling sine waves), the colour runs from turquoise in the shallows to deep blue
// further out, and a band of foam washes at the shoreline (shore_x, world x of the water's edge).
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 shallow_colour : source_color = vec3(0.18, 0.58, 0.62);
uniform vec3 deep_colour : source_color = vec3(0.04, 0.2, 0.36);
uniform float shore_x = 632.0;
// Metres from the shore over which the colour deepens.
uniform float shallow_width = 70.0;
// Width of the foam band (it washes in and out by a third of this).
uniform float foam_width = 3.0;
uniform float wave_strength = 0.06;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Gradient of a travelling wave a * sin(dot(p, dir) * k + t * w).
vec2 wave_grad(vec2 p, vec2 dir, float k, float w, float a) {
	return dir * (a * k * cos(dot(p, dir) * k + TIME * w));
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 g = wave_grad(p, normalize(vec2(-1.0, 0.2)), 0.35, 1.3, 1.0)
		+ wave_grad(p, normalize(vec2(-0.7, -0.7)), 0.8, 2.1, 0.45)
		+ wave_grad(p, normalize(vec2(0.3, 1.0)), 1.9, 3.4, 0.2);
	vec3 n = normalize(vec3(-g.x * wave_strength, 1.0, -g.y * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float from_shore = world_pos.x - shore_x;
	vec3 colour = mix(shallow_colour, deep_colour, clamp(from_shore / shallow_width, 0.0, 1.0));
	float wash = foam_width * (0.67 + 0.33 * sin(TIME * 0.7 + p.y * 0.05));
	float foam = 1.0 - smoothstep(wash * 0.45, wash, from_shore);
	foam *= 0.75 + 0.25 * sin(p.y * 1.7 + TIME * 1.1);
	ALBEDO = mix(colour, vec3(0.9, 0.93, 0.92), clamp(foam, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.8, clamp(foam, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
