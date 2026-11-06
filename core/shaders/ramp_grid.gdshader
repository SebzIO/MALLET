shader_type spatial;
render_mode cull_disabled;
// Dev grid: lines every 1/8 of the face across and every 5 m along, heavier on the edges and ridge.
// `square` (blocks and cubes, whose UVs are world metres / 4): an even grid, a line every metre both ways.
uniform vec4 tint : source_color = vec4(0.62, 0.66, 0.72, 1.0);
uniform bool square = false;
void fragment() {
	vec2 g = square ? UV * 4.0 : vec2(UV.x * 8.0, UV.y * 4.0);
	vec2 w = fwidth(g) * 1.2;
	vec2 l = smoothstep(vec2(0.0), w, abs(fract(g - 0.5) - 0.5));
	float line = 1.0 - min(l.x, l.y);
	float edge = square ? 0.0 : 1.0 - smoothstep(0.0, 0.02, min(abs(UV.x), min(abs(UV.x - 0.5), abs(UV.x - 1.0))));
	ALBEDO = mix(tint.rgb, tint.rgb * 0.35, max(line * 0.8, edge));
	ROUGHNESS = 0.7;
}
