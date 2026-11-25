shader_type canvas_item;
// The minimap (GDD §11): a round window onto the district map image, centred on the player and
// turned so the camera's forward direction points up.

uniform sampler2D map_texture : source_color, filter_linear, repeat_disable;
// World X/Z of the map image's corner, and its size in metres.
uniform vec4 map_rect = vec4(-256.0, -256.0, 512.0, 512.0);
// World X/Z shown in the middle.
uniform vec2 centre = vec2(0.0);
// The world direction shown as "up", as a compass angle (0 = north, -Z) in radians.
uniform float heading = 0.0;
// Metres across the window.
uniform float metres_across = 150.0;
uniform vec4 ring_color : source_color = vec4(0.13, 0.9, 1.0, 1.0);
uniform vec4 outside_color : source_color = vec4(0.06, 0.07, 0.11, 1.0);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	vec2 s = p * metres_across;
	float c = cos(heading);
	float sn = sin(heading);
	vec2 world = centre + vec2(s.x * c - s.y * sn, s.x * sn + s.y * c);
	vec2 uv = (world - map_rect.xy) / map_rect.zw;
	bool outside = uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0;
	vec4 col = outside ? outside_color : texture(map_texture, uv);
	col.rgb *= 1.0 - smoothstep(0.3, 0.5, r) * 0.25;
	COLOR = mix(col, ring_color, smoothstep(0.468, 0.482, r));
	COLOR.a = 0.92 * (1.0 - smoothstep(0.492, 0.5, r));
}
