shader_type sky;
// ============================================================================================================
// MALLET example sky: copy this file, rename it (the file name is the name MALLET shows) and change it.
//
// How MALLET reads this file:
//  * "shader_type sky;" at the top makes it a sky. Pick it in the Map panel (click empty space) under "Sky".
//  * Every uniform below becomes a control in the panel, named after the uniform ("cloud_amount" -> "Cloud amount"):
//      float / int        -> a slider. Give it a range with  : hint_range(min, max, step)
//      vec3 / vec4 color  -> a color picker. Mark it with  : source_color
//      bool               -> a checkbox
//      vec2 / vec3 / vec4 -> number boxes
//      sampler2D          -> "Choose image..." (the image is stored inside the exported map)
//  * A comment after a uniform on the same line becomes its tooltip.
//  * Uniforms whose name starts with _ get no control (for values only you should change).
//  * Using TIME animates the sky (MALLET redraws it every frame).
//  * The sun's direction, color and brightness come from the Map panel: LIGHT0_DIRECTION, LIGHT0_COLOR,
//    LIGHT0_ENERGY. The sun, shadow fill and fog settings keep working with your own sky.
//  * Save the file and switch back to MALLET: it reloads on its own. If it has an error, the panel shows the line
//    and MALLET keeps using the built-in sky until it's fixed.
//  * Counter-Strike: Source can't run shaders: the CS:S export renders this sky into a 6-sided skybox.
// Guide: docs/SHADERS.md, or Godot's sky shader docs (docs.godotengine.org).
// ============================================================================================================

uniform vec3 zenith_color : source_color = vec3(0.12, 0.30, 0.62);   // The color straight up
uniform vec3 horizon_color : source_color = vec3(0.70, 0.80, 0.90);  // The color at the horizon
uniform vec3 ground_color : source_color = vec3(0.20, 0.21, 0.24);   // Below the horizon
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);       // Cloud tops
uniform float cloud_amount : hint_range(0.0, 1.0, 0.01) = 0.5;       // 0 = clear sky, 1 = overcast
uniform float cloud_softness : hint_range(0.01, 0.5, 0.01) = 0.18;   // Sharp or fluffy cloud edges
uniform float cloud_scale : hint_range(0.5, 8.0, 0.1) = 2.5;         // Bigger number = smaller clouds
uniform float wind_speed : hint_range(0.0, 0.2, 0.005) = 0.02;       // How fast the clouds drift (0 = still)
uniform float sun_size : hint_range(0.001, 0.05, 0.001) = 0.01;      // The sun disc's size
uniform float sun_glow : hint_range(0.0, 2.0, 0.05) = 0.6;           // The haze around the sun
uniform float _seed = 3.7;                                           // (no control: the name starts with _)

// --- noise helpers (value noise, layered into "fbm" for cloud shapes)
float hash(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.zyx + 31.32); return fract((p.x + p.y) * p.z); }
float noise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	           mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float a = 0.5, s = 0.0; for (int i = 0; i < 5; i++) { s += a * noise(p); p *= 2.07; a *= 0.5; } return s; }

void sky() {
	vec3 d = EYEDIR;                        // the direction this pixel looks in (y = up)
	float h = d.y;
	// 1. gradient: ground -> horizon -> zenith
	vec3 col = h > 0.0 ? mix(horizon_color, zenith_color, pow(h, 0.5)) : mix(horizon_color, ground_color, pow(-h, 0.4));
	// 2. clouds: noise projected onto a flat layer overhead, fading out toward the horizon
	if (h > 0.0 && cloud_amount > 0.0) {
		vec2 uv = d.xz / (h + 0.15) * cloud_scale * 0.25 + vec2(TIME * wind_speed, _seed);
		float n = fbm(vec3(uv, TIME * wind_speed * 0.5));
		float cover = smoothstep(1.0 - cloud_amount - cloud_softness, 1.0 - cloud_amount + cloud_softness, n);
		float shade = mix(0.65, 1.0, smoothstep(0.3, 0.8, n));    // darker undersides
		col = mix(col, cloud_color * shade, cover * smoothstep(0.0, 0.2, h));
	}
	// 3. the sun (from the Map panel's sun settings)
	if (LIGHT0_ENABLED) {
		float s = dot(d, LIGHT0_DIRECTION);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.7, s) * 5.0 + pow(max(s, 0.0), 200.0) * sun_glow);
	}
	COLOR = col;
}
