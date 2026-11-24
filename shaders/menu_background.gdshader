// Main menu backdrop: dusk sky, two parallax skyline layers with lit windows,
// a magenta horizon glow and a neon grid floor scrolling toward the viewer.
shader_type canvas_item;

uniform vec4 sky_top : source_color = vec4(0.015, 0.008, 0.04, 1.0);
uniform vec4 sky_horizon : source_color = vec4(0.26, 0.045, 0.25, 1.0);
uniform vec4 neon_magenta : source_color = vec4(1.0, 0.17, 0.84, 1.0);
uniform vec4 neon_cyan : source_color = vec4(0.13, 0.9, 1.0, 1.0);
uniform float horizon : hint_range(0.3, 0.9) = 0.64;
uniform float scroll_speed = 0.35;

float hash11(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Building height above the horizon (in UV units) at horizontal position x.
float skyline(float x, float seed, float scale) {
	float id = floor(x);
	float h = 0.05 + 0.2 * pow(hash11(id + seed), 2.0);
	h += step(0.88, hash11(id * 3.1 + seed)) * 0.12;
	return h * scale;
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 col = vec3(0.0);

	if (uv.y < horizon) {
		float t = clamp(uv.y / horizon, 0.0, 1.0);
		col = mix(sky_top.rgb, sky_horizon.rgb, pow(t, 2.2));
		vec2 g = (uv - vec2(0.7, horizon)) * vec2(aspect, 2.2);
		col += neon_magenta.rgb * 0.55 * exp(-length(g) * 3.0);

		float above = horizon - uv.y;
		float xf = uv.x * aspect * 9.0 + TIME * 0.02;
		if (above < skyline(xf, 17.0, 0.8)) {
			col = mix(col, vec3(0.07, 0.03, 0.1), 0.85);
		}
		float xn = uv.x * aspect * 5.0 + TIME * 0.05;
		float hn = skyline(xn, 3.0, 1.15);
		if (above < hn) {
			col = vec3(0.025, 0.012, 0.04);
			vec2 cell = vec2(floor(xn * 6.0), floor(uv.y * 120.0));
			vec2 f = vec2(fract(xn * 6.0), fract(uv.y * 120.0));
			float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.75);
			float lit = step(0.82, hash21(cell));
			vec3 window_col = mix(neon_cyan.rgb, vec3(1.0, 0.75, 0.4), step(0.5, hash21(cell + 7.0)));
			col += window_col * win * lit * 0.6;
			col += neon_magenta.rgb * 0.35 * (1.0 - smoothstep(0.0, 0.004, hn - above));
		}
	} else {
		float g = (uv.y - horizon) / (1.0 - horizon);
		float depth = 1.0 / (g + 0.035);
		vec2 grid = vec2((uv.x - 0.5) * aspect * depth * 0.9, depth + TIME * scroll_speed * 4.0);
		vec2 d = abs(fract(grid - 0.5) - 0.5);
		vec2 w = fwidth(grid) * 1.5;
		vec2 lines = 1.0 - smoothstep(vec2(0.0), w, d);
		float line = max(lines.x, lines.y) * smoothstep(0.0, 0.35, g);
		col = vec3(0.02, 0.005, 0.03);
		col += neon_magenta.rgb * 0.3 * exp(-g * 6.0) * exp(-abs(uv.x - 0.7) * aspect * 2.0);
		col = mix(col, neon_magenta.rgb * 0.85, line * 0.75);
	}

	// Darken the left side so the menu column reads cleanly over the skyline.
	col *= mix(0.12, 1.0, smoothstep(0.12, 0.5, uv.x));
	col *= 1.0 - 0.5 * pow(length((uv - 0.5) * vec2(1.0, 1.2)), 2.2);
	COLOR = vec4(col, 1.0);
}
