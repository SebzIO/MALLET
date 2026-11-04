shader_type spatial;
render_mode cull_disabled;
// Brushed steel: fine streaks running along the ramp.
uniform vec4 tint : source_color = vec4(0.78, 0.8, 0.84, 1.0);
float hash(float x) { return fract(sin(x * 91.7) * 43758.5); }
void fragment() {
	float s = hash(floor(UV.x * 420.0)) * 0.6 + hash(floor(UV.x * 97.0)) * 0.4;
	float streak = 0.82 + 0.18 * s + 0.04 * sin(UV.y * 3.0 + s * 6.0);
	ALBEDO = tint.rgb * streak;
	METALLIC = 0.9;
	ROUGHNESS = 0.32 + 0.1 * s;
}
