shader_type spatial;
// Cube faces with Sauerbraten's texture settings: a tint, see-through (when SEE_THROUGH is defined), scrolling, and
// a second texture (the blend layer) that shows where it's been painted in (vertex color alpha). UVs come from the
// mesh (UV = the texture, UV2 = the layer's).
#ifdef SEE_THROUGH
render_mode cull_back, depth_draw_always;
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
uniform bool use_layer = false;
uniform sampler2D layer_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool layer_has_normal = false;

void fragment() {
	vec2 uv = UV + scroll * TIME;
	vec4 c = texture(albedo_tex, uv) * tint;
	vec3 nm = has_normal ? texture(normal_tex, uv).rgb : vec3(0.5, 0.5, 1.0);
	float r = has_rough ? texture(rough_tex, uv).r : 0.9;
	if (use_layer) {
		float w = clamp(COLOR.a, 0.0, 1.0);
		vec4 lc = texture(layer_tex, UV2);
		vec3 ln = layer_has_normal ? texture(layer_normal, UV2).rgb : vec3(0.5, 0.5, 1.0);
		c = mix(c, lc, w);
		nm = mix(nm, ln, w);
	}
	ALBEDO = c.rgb;
	if (has_glow) {
		EMISSION = texture(glow_tex, uv).rgb * tint.rgb * glow_energy;
	}
	NORMAL_MAP = nm;
	ROUGHNESS = r;
#ifdef SEE_THROUGH
	ALPHA = alpha;
#endif
}
