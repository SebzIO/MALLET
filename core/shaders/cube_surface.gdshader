shader_type spatial;
// Cube faces with Sauerbraten's texture settings: a tint, see-through (when SEE_THROUGH is defined), scrolling, and
// a second texture (the blend layer) that shows where it's been painted in (vertex color alpha). UVs come from the
// mesh (UV = the texture, UV2 = the layer's).
#if defined(SEE_THROUGH) && defined(DOUBLE_SIDED)
render_mode cull_disabled, depth_draw_always;
#elif defined(SEE_THROUGH)
render_mode cull_back, depth_draw_always;
#elif defined(DOUBLE_SIDED)
render_mode cull_disabled;
#else
render_mode cull_back;
#endif

uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_normal = false;
uniform sampler2D glow_tex : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_glow = false;
uniform float glow_energy = 1.6;
uniform bool has_rough = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha = 1.0;
uniform vec2 scroll = vec2(0.0);
// Spiral motion (0.23.0): each repeat of the texture turns around its own middle at `spin` degrees a second, and
// `swirl` twists it more the nearer the middle it is (degrees at the middle, fading to none at the repeat's edge),
// so together they make a turning spiral. "Fit to selection" (one repeat over the whole face) spins the face as one.
uniform float spin = 0.0;
uniform float swirl = 0.0;
// The material's finish (MaterialLibrary.finish): bright x, light of its own, gloss 0-1, reflect (metal) 0-1.
uniform float bright = 1.0;
uniform float self_glow = 0.0;
uniform float gloss = 0.0;
uniform float reflect = 0.0;
uniform bool use_layer = false;
uniform sampler2D layer_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool layer_has_normal = false;

void fragment() {
	vec2 uv = UV + scroll * TIME;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	if (spin != 0.0 || swirl != 0.0) {
		vec2 cell = floor(uv);
		vec2 p = uv - cell - 0.5;
		float a = radians(spin) * TIME + radians(swirl) * max(1.0 - length(p) * 2.0, 0.0);
		float ca = cos(a);
		float sa = sin(a);
		p = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
		uv = cell + p + 0.5;
	}
	vec4 c = textureGrad(albedo_tex, uv, dx, dy) * tint;
	vec3 nm = has_normal ? textureGrad(normal_tex, uv, dx, dy).rgb : vec3(0.5, 0.5, 1.0);
	float r = has_rough ? textureGrad(rough_tex, uv, dx, dy).r : 0.9;
	if (use_layer) {
		float w = clamp(COLOR.a, 0.0, 1.0);
		vec4 lc = texture(layer_tex, UV2);
		vec3 ln = layer_has_normal ? texture(layer_normal, UV2).rgb : vec3(0.5, 0.5, 1.0);
		c = mix(c, lc, w);
		nm = mix(nm, ln, w);
	}
	ALBEDO = c.rgb * bright;
	if (has_glow) {
		EMISSION = textureGrad(glow_tex, uv, dx, dy).rgb * tint.rgb * glow_energy * (1.0 + self_glow);
	} else if (self_glow > 0.0) {
		EMISSION = c.rgb * self_glow;
	}
	NORMAL_MAP = nm;
	ROUGHNESS = r * (1.0 - gloss);
	METALLIC = reflect;
	SPECULAR = 0.5 + 0.5 * reflect;
#ifdef SEE_THROUGH
	ALPHA = alpha;
#endif
}
