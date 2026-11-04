shader_type spatial;
render_mode cull_disabled;
// Neon edges: dark glossy body with glowing edge and ridge lines and a pulse running down the ramp.
uniform vec4 tint : source_color = vec4(0.1, 0.9, 1.0, 1.0);
void fragment() {
	float d = min(abs(UV.x), min(abs(UV.x - 0.5), abs(UV.x - 1.0)));
	float line = 1.0 - smoothstep(0.004, 0.018, d);
	float pulse = smoothstep(0.92, 1.0, sin(UV.y * 1.2 + TIME * 4.0) * 0.5 + 0.5);
	ALBEDO = vec3(0.03, 0.03, 0.05);
	ROUGHNESS = 0.15;
	EMISSION = tint.rgb * (line * 3.0 + pulse * 0.6 * (1.0 - step(1.0, UV.x)));
}
