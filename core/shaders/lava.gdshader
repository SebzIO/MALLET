shader_type spatial;
// Lava: a dark crust drifting slowly over glowing molten cracks that flicker. Also magma (more crust) and plasma.
render_mode cull_disabled;

uniform vec4 hot_color : source_color = vec4(1.0, 0.69, 0.13, 1.0);   // the hottest parts
uniform vec4 tint : source_color = vec4(1.0, 0.29, 0.04, 1.0);        // molten color
uniform vec4 crust_color : source_color = vec4(0.16, 0.07, 0.03, 1.0);
uniform float crust : hint_range(0.0, 1.0) = 0.45;    // how much of it is crust
uniform float glow : hint_range(0.0, 8.0) = 3.0;
uniform vec2 flow = vec2(0.3, 0.1);                    // m/s
uniform float scale = 0.35;                            // bigger = smaller blobs

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 4; i++) { s += a * noise(p); p = p * 2.07 + vec2(1.7, 9.2); a *= 0.5; } return s; }

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz * scale - flow * scale * TIME;
	float warp = fbm(p * 0.6 + vec2(TIME * 0.02, -TIME * 0.015));
	float n = fbm(p + warp * 1.8);
	float heat = smoothstep(crust - 0.08, crust + 0.18, n);             // 0 = crust, 1 = molten
	float flicker = 0.85 + 0.15 * noise(world.xz * 0.8 + TIME * 0.7);
	vec3 molten = mix(tint.rgb, hot_color.rgb, smoothstep(0.55, 1.0, heat * n * 1.4));
	// the crust's bumps catch the light; molten parts are smooth
	float e = 0.08;
	float nx = fbm(p + vec2(e, 0.0) + warp * 1.8);
	float nz = fbm(p + vec2(0.0, e) + warp * 1.8);
	vec3 n_world = normalize(vec3((n - nx) * 6.0 * (1.0 - heat), 1.0, (n - nz) * 6.0 * (1.0 - heat)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	ALBEDO = mix(crust_color.rgb, molten * 0.35, heat);
	EMISSION = molten * heat * glow * flicker + crust_color.rgb * 0.15 * glow * (1.0 - heat);
	ROUGHNESS = mix(0.92, 0.35, heat);
	METALLIC = 0.0;
}
