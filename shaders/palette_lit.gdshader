shader_type spatial;
// Shared material for meshes baked by KitBaker (district buildings, tiles, props, vehicles).
// Each vertex carries its original material's look, so a whole model is one surface and one
// draw call:
//   COLOR.rgb   albedo (linear)
//   COLOR.a     1 = keep COLOR.rgb, 0 = use this instance's tint (e.g. a car's paint)
//   UV2         x = roughness, y = metallic
//   CUSTOM0.rgb emission (linear, already multiplied by its energy)
//   CUSTOM0.a   when it glows: 0 = always, 1 = at night (streetlight lenses), 2 = lit window
//               at night (each building floor is lit or dark, chosen from the building's position)
// city_lights (a global set by the day/night cycle) is 0 by day and 1 at night.
// wetness (a global set by the weather, M7) is 0 when dry and 1 after rain: surfaces facing up
// (roads, sidewalks, roofs, car bonnets) darken and turn glossy.
render_mode cull_back, depth_draw_opaque;

global uniform float city_lights;
global uniform float wetness;
instance uniform vec4 tint : source_color = vec4(1.0);

varying vec4 v_emission;
varying float v_window_lit;
varying float v_up;

void vertex() {
	v_emission = CUSTOM0;
	// Lit or dark: one random pick per building (its origin) and floor (3 m bands of the model).
	vec3 origin = MODEL_MATRIX[3].xyz;
	float band = floor(VERTEX.y / 3.0);
	float h = fract(sin(dot(vec3(origin.x, origin.z, band), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	v_window_lit = h < 0.35 ? 0.0 : mix(0.55, 1.0, h);
	v_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	float wet = wetness * smoothstep(0.55, 0.9, v_up);
	ALBEDO = mix(tint.rgb, COLOR.rgb, COLOR.a) * (1.0 - 0.35 * wet);
	ROUGHNESS = mix(UV2.x, 0.12, wet);
	METALLIC = UV2.y;
	float night_only = clamp(v_emission.a, 0.0, 1.0);
	float lit = v_emission.a > 1.5 ? v_window_lit : 1.0;
	EMISSION = v_emission.rgb * mix(1.0, city_lights * lit, night_only);
}
