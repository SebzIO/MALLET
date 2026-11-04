shader_type sky;
// SurfForge sky: gradient + sun disc, with optional stars, animated aurora curtains and nebula clouds.

uniform vec3 top_color : source_color = vec3(0.32, 0.46, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.74, 0.82);
uniform vec3 ground_color : source_color = vec3(0.18, 0.19, 0.22);
uniform float sun_size = 0.012;
uniform float stars = 0.0;           // 0..1
uniform float aurora = 0.0;          // 0..1
uniform vec3 aurora_a : source_color = vec3(0.15, 1.0, 0.55);
uniform vec3 aurora_b : source_color = vec3(0.55, 0.25, 1.0);
uniform float nebula = 0.0;          // 0..1
uniform vec3 nebula_color : source_color = vec3(0.75, 0.25, 0.9);

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.03; a *= 0.5; } return s; }

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = h > 0.0 ? mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45))
	                   : mix(horizon_color, ground_color, pow(clamp(-h, 0.0, 1.0), 0.35));
	float up = smoothstep(-0.02, 0.15, h);
	if (nebula > 0.0) {
		float n = fbm(d * 3.0 + vec3(0.0, 0.0, TIME * 0.003));
		float n2 = fbm(d * 7.0 - vec3(TIME * 0.002));
		col += nebula_color * pow(n, 2.6) * 2.2 * nebula * up;
		col += vec3(0.2, 0.4, 0.9) * pow(n2, 3.5) * 1.5 * nebula * up;
	}
	if (stars > 0.0) {
		vec3 p = d * 260.0;
		float r = hash(floor(p));
		float star = smoothstep(1.0 - 0.004 * stars, 1.0, r) * (0.6 + 0.4 * sin(TIME * 2.0 + r * 50.0));
		col += vec3(star) * up * 1.6;
	}
	if (aurora > 0.0 && h > 0.0) {
		// curtains: thin wavy bands seen from below, with vertical rays, a bright lower edge and fading tops
		vec2 q = d.xz / (h + 0.12);
		float t = TIME * 0.08;
		vec3 glow = vec3(0.0);
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float c = q.y * 0.55 + fi * 0.9 - 1.4 + sin(q.x * 0.45 + t * (1.0 + fi * 0.3) + fi * 1.7) * 0.8
				+ sin(q.x * 1.3 - t * 1.7 + fi) * 0.18;
			float band = exp(-c * c * 9.0);
			float along = q.x * 9.0 + fi * 13.0;
			float rays = 0.35 + 0.65 * pow(noise(vec3(along, t * 3.0, fi)), 1.5);
			float lower = smoothstep(0.03, 0.09, h);
			float upper = 1.0 - smoothstep(0.18 + fi * 0.06, 0.7, h);
			vec3 ac = mix(aurora_a, aurora_b, smoothstep(0.12, 0.45, h) * 0.8 + fi * 0.08);
			glow += ac * band * rays * lower * upper * (1.0 - fi * 0.18);
		}
		col += glow * aurora * 0.9;
	}
	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.6, s) * 6.0 + pow(max(s, 0.0), 300.0) * 0.6);
	}
	COLOR = col;
}
