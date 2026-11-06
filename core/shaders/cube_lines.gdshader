shader_type spatial;
// Build mode's cube outlines (key 7): bright, unshaded, and pulled a hair toward the camera so they win against the
// faces they lie on (plain lines on a face flicker in and out of it - "z-fighting" - and were nearly invisible).
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 line_color : source_color = vec4(0.15, 1.0, 1.0, 1.0);

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z *= 1.0015;                // reversed depth: a tiny bit nearer, in proportion to the distance
}

void fragment() {
	ALBEDO = line_color.rgb;
}
