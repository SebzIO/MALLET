shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// Infinite-looking editor ground grid: thin lines every `minor` m, stronger every `major` m, fading with distance.
uniform float minor = 10.0;
uniform float major = 100.0;
uniform vec4 line_color : source_color = vec4(0.55, 0.6, 0.7, 1.0);
uniform float fade_distance = 2500.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 p, float spacing) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) / fwidth(p / spacing);
	return 1.0 - min(min(g.x, g.y), 1.0);
}

void fragment() {
	float a = grid_line(world_pos.xz, minor) * 0.25 + grid_line(world_pos.xz, major) * 0.6;
	float axis = 1.0 - min(min(abs(world_pos.x), abs(world_pos.z)) / fwidth(world_pos.x) * 0.5, 1.0);
	float fade = 1.0 - smoothstep(fade_distance * 0.3, fade_distance, length(world_pos.xz - CAMERA_POSITION_WORLD.xz));
	ALBEDO = mix(line_color.rgb, vec3(0.9, 0.5, 0.2), axis);
	ALPHA = clamp(max(a, axis * 0.8), 0.0, 1.0) * fade;
}
