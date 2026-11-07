shader_type spatial;
render_mode cull_disabled;
// Nebula: deep space clouds and twinkling stars, fixed in world space so neighboring ramps line up.
uniform vec4 tint : source_color = vec4(0.85, 0.2, 0.9, 1.0);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic: no facets
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise(p); p = p * 2.07 + vec3(1.7, 9.2, 3.1); a *= 0.5; } return s; }
void fragment() {
	vec3 p = wp * 0.012 + vec3(0.0, 0.0, TIME * 0.015);
	vec3 warp = vec3(fbm(p + 3.1), fbm(p + 7.7), fbm(p + 1.3));
	float n = fbm(p + warp * 1.6);
	vec3 deep = vec3(0.04, 0.02, 0.12);
	vec3 c = mix(deep, tint.rgb, smoothstep(0.35, 0.75, n));
	c = mix(c, vec3(0.25, 0.5, 1.0), smoothstep(0.55, 0.85, fbm(p * 1.7 + warp)) * 0.55);
	float star = step(0.9985, hash(floor(wp * 2.0))) * (0.6 + 0.4 * sin(TIME * 3.0 + hash(floor(wp)) * 40.0));
	ALBEDO = c * 0.45;
	EMISSION = c * 0.65 + vec3(star) * 2.5;
	ROUGHNESS = 0.35;
}
