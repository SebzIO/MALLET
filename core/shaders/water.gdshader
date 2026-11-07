shader_type spatial;
// Water surface: moving waves, the scene seen through it (bent by the waves), deeper water getting darker, foam where
// it meets walls and the shore, and reflections at shallow angles. Also acid (glow) and rivers (flow).
render_mode cull_disabled, depth_draw_always, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.16, 0.56, 0.69, 1.0);       // shallow color
uniform vec4 deep_color : source_color = vec4(0.04, 0.18, 0.29, 1.0); // color it turns where it's deep
uniform float clarity : hint_range(0.0, 1.0) = 0.65;   // 0 = murky, 1 = crystal clear
uniform float waves : hint_range(0.0, 2.0) = 1.0;
uniform float foam : hint_range(0.0, 1.0) = 0.5;
uniform vec2 flow = vec2(0.0);                          // m/s: a river's current
uniform float glow : hint_range(0.0, 8.0) = 0.0;       // acid: make it shine
uniform float refraction : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

float hash(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
// the surface's height at a point: three layers of soft noise drifting different ways, plus the current
float height(vec2 p, float t) {
	vec2 q = p - flow * t;
	return noise(q * 0.45 + vec2(t * 0.11, t * 0.07)) * 0.6 + noise(q * 1.3 - vec2(t * 0.19, -t * 0.13)) * 0.3
		+ noise(q * 3.1 + vec2(-t * 0.31, t * 0.27)) * 0.1;
}

float scene_distance(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 view = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float e = 0.15;
	float h0 = height(world.xz, t);
	float hx = height(world.xz + vec2(e, 0.0), t);
	float hz = height(world.xz + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3((h0 - hx) / e * 0.35 * waves, 1.0, (h0 - hz) / e * 0.35 * waves));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// how much water the view looks through (straight behind, then where the waves bend it)
	float surface = -VERTEX.z;
	float behind = scene_distance(SCREEN_UV, INV_PROJECTION_MATRIX) - surface;
	vec2 bent = SCREEN_UV + n_world.xz * refraction * 0.03 * clamp(behind, 0.0, 1.0);
	float behind_bent = scene_distance(bent, INV_PROJECTION_MATRIX) - surface;
	if (behind_bent < 0.0) { bent = SCREEN_UV; behind_bent = behind; }   // (don't show things in front of the water)
	float thick = max(behind_bent, 0.0);
	float absorb = mix(0.9, 0.04, clarity);
	float opacity = 1.0 - exp(-thick * absorb);
	vec3 water = mix(tint.rgb, deep_color.rgb, clamp(1.0 - exp(-thick * absorb * 0.5), 0.0, 1.0));
	vec3 seen = textureLod(screen_tex, bent, 0.0).rgb * mix(vec3(1.0), tint.rgb * 1.4, 0.35);

	// foam: a broken white line where the water meets something
	float edge = 1.0 - smoothstep(0.0, 0.45, max(behind, 0.0));
	float foam_mask = edge * smoothstep(0.35, 0.75, noise(world.xz * 3.0 - flow * t * 1.5 + vec2(t * 0.4, 0.0))) * foam;
	foam_mask += foam * 0.25 * smoothstep(0.82, 0.95, h0);              // a little on the wave crests too

	ALBEDO = mix(water * opacity, vec3(0.92), clamp(foam_mask, 0.0, 1.0));
	EMISSION = seen * (1.0 - opacity) * (1.0 - clamp(foam_mask, 0.0, 1.0)) + tint.rgb * glow;
	ROUGHNESS = mix(0.04, 0.6, clamp(foam_mask, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.55;
	ALPHA = 1.0;
}
