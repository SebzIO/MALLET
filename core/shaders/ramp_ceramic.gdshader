shader_type spatial;
render_mode cull_disabled;
// Glazed ceramic: off-white glaze, a coloured double rim line along both edges, very glossy.
uniform vec4 tint : source_color = vec4(0.13, 0.25, 0.59, 1.0);   // rim colour
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 4375.85); }
void fragment() {
	float e = min(UV.x, abs(1.0 - UV.x));
	float rim = step(0.025, e) * (1.0 - step(0.06, e)) + step(0.075, e) * (1.0 - step(0.09, e));
	vec3 glaze = vec3(0.94, 0.93, 0.9) - hash(floor(UV * vec2(300.0, 60.0))) * 0.015;
	ALBEDO = UV.x > 1.0 ? vec3(0.85) : mix(glaze, tint.rgb, rim);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
