shader_type spatial;
render_mode cull_disabled;
// Aurora: flowing green / teal / violet bands that drift along the ramp, glowing.
uniform vec4 tint : source_color = vec4(0.15, 1.0, 0.6, 1.0);
uniform vec4 tint_b : source_color = vec4(0.55, 0.25, 1.0, 1.0);
void fragment() {
	float t = TIME * 0.35;
	float b = sin(UV.y * 1.7 + t + sin(UV.x * 6.0 + t * 0.7) * 1.3) * 0.5 + 0.5;
	float b2 = sin(UV.y * 0.9 - t * 0.6 + UV.x * 3.0) * 0.5 + 0.5;
	vec3 c = mix(tint.rgb, tint_b.rgb, b2);
	float ridge = 1.0 - smoothstep(0.0, 0.05, abs(UV.x - 0.5));
	ALBEDO = c * 0.25;
	EMISSION = c * (0.35 + 1.1 * pow(b, 3.0)) + vec3(1.0) * ridge * 0.35;
	ROUGHNESS = 0.35;
}
