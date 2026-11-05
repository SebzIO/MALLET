shader_type spatial;
// Water surface: gently moving ripples (layered waves in the normal), see-through with a fresnel edge, tinted.
render_mode cull_disabled, depth_draw_always;

uniform vec4 tint : source_color = vec4(0.12, 0.42, 0.55, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.55;   // 0 = murky, 1 = glass-clear
uniform float waves : hint_range(0.0, 2.0) = 1.0;
uniform float glow : hint_range(0.0, 8.0) = 0.0;       // lava / acid: make it shine

float wave(vec2 p, vec2 dir, float freq, float speed) {
	return sin(dot(p, dir) * freq + TIME * speed);
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;
	float dx = 0.0;
	float dz = 0.0;
	// a few waves crossing each other; derivatives give the ripple normal
	vec2 d1 = normalize(vec2(1.0, 0.3));
	vec2 d2 = normalize(vec2(-0.4, 1.0));
	vec2 d3 = normalize(vec2(0.7, -0.8));
	dx += cos(dot(p, d1) * 0.9 + TIME * 1.3) * d1.x * 0.9;
	dz += cos(dot(p, d1) * 0.9 + TIME * 1.3) * d1.y * 0.9;
	dx += cos(dot(p, d2) * 1.7 + TIME * 1.9) * d2.x * 0.5;
	dz += cos(dot(p, d2) * 1.7 + TIME * 1.9) * d2.y * 0.5;
	dx += cos(dot(p, d3) * 3.1 + TIME * 2.6) * d3.x * 0.25;
	dz += cos(dot(p, d3) * 3.1 + TIME * 2.6) * d3.y * 0.25;
	vec3 n_world = normalize(vec3(-dx * 0.08 * waves, 1.0, -dz * 0.08 * waves));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = tint.rgb * glow;
	ALPHA = clamp(mix(1.0 - clarity * 0.85, 1.0, fres), 0.0, 1.0);
}
