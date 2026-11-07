shader_type spatial;
// Glass: the scene seen through it (slightly bent, tinted, blurred when frosted) and reflections at shallow angles.
render_mode cull_back, depth_draw_always, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.9, 0.96, 1.0, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.85;  // how much shows through
uniform float frost : hint_range(0.0, 1.0) = 0.0;     // 0 = clear, 1 = fully frosted
uniform float refraction : hint_range(0.0, 1.0) = 0.3;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec2 bent = SCREEN_UV + NORMAL.xy * refraction * 0.02;
	vec3 seen = textureLod(screen_tex, bent, frost * 5.0).rgb * tint.rgb;
	float through = clarity * (1.0 - fres * 0.7);
	ALBEDO = tint.rgb * (1.0 - through) * 0.6;
	EMISSION = seen * through;
	ROUGHNESS = mix(0.02, 0.45, frost);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
