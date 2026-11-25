shader_type spatial;
// The lighthouse beam (M7): two long faint cones from the lamp, turning slowly around it. The
// turning happens here (no script), and the beam only shows at night: city_lights is the global
// the day/night cycle sets (0 by day, 1 at night). UV.y runs from the lamp (0) to the cone's end (1).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

global uniform float city_lights;
uniform vec3 colour : source_color = vec3(1.0, 0.92, 0.7);
uniform float strength = 0.15;
// Radians per second.
uniform float turn_speed = 0.55;

varying float along;

void vertex() {
	float a = TIME * turn_speed;
	float c = cos(a);
	float s = sin(a);
	VERTEX = vec3(VERTEX.x * c - VERTEX.z * s, VERTEX.y, VERTEX.x * s + VERTEX.z * c);
	along = UV.y;
}

void fragment() {
	float fade = (1.0 - along) * (1.0 - along);
	ALBEDO = colour * strength * fade * city_lights;
}
