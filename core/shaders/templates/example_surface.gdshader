shader_type spatial;
// ============================================================================================================
// MALLET example surface: copy this file, rename it (the file name is the name MALLET shows) and change it.
//
// How MALLET reads this file:
//  * "shader_type spatial;" at the top makes it a surface. Select a ramp or block, set Look to "Your own shader"
//    and pick it.
//  * Every uniform below becomes a control in the panel, named after the uniform ("stripe_width" -> "Stripe width"):
//      float / int        -> a slider. Give it a range with  : hint_range(min, max, step)
//      vec3 / vec4 color  -> a color picker. Mark it with  : source_color
//      bool               -> a checkbox
//      vec2 / vec3 / vec4 -> number boxes
//      sampler2D          -> "Choose image..." (the image is stored inside the exported map)
//  * A comment after a uniform on the same line becomes its tooltip.
//  * Uniforms whose name starts with _ get no control.
//  * Using TIME animates it.
//  * UV on ramps: x goes 0..1 across the riding face, y is meters along the ramp / 20.
//    On blocks, UV is meters / 4 (lined up across blocks). World position: (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz
//  * Ramps are drawn from both sides: keep "cull_disabled" in render_mode.
//  * Save the file and switch back to MALLET: it reloads on its own. If it has an error, the panel shows the line
//    and the surface stays a plain color until it's fixed.
//  * Counter-Strike: Source can't run shaders: the CS:S export uses this shader's first image (if you chose one),
//    otherwise its first color.
// Guide: docs/SHADERS.md, or Godot's spatial shader docs (docs.godotengine.org).
// ============================================================================================================
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.85, 0.86, 0.9);      // The main color (also the color in CS:S)
uniform vec3 stripe_color : source_color = vec3(1.0, 0.45, 0.1);     // The stripes' color
uniform float stripe_width : hint_range(0.0, 0.5, 0.01) = 0.08;      // How wide the stripes are (0 = none)
uniform float stripe_spacing : hint_range(0.5, 20.0, 0.5) = 4.0;     // Meters between stripes along the ramp
uniform float stripe_glow : hint_range(0.0, 4.0, 0.1) = 1.0;         // Makes the stripes shine
uniform float scroll_speed : hint_range(-5.0, 5.0, 0.1) = 0.0;       // Stripes slide along (0 = still)
uniform float roughness_amount : hint_range(0.0, 1.0, 0.01) = 0.35;  // 0 = glossy, 1 = matte
uniform float metal : hint_range(0.0, 1.0, 0.01) = 0.0;              // 0 = plastic or stone, 1 = metal
uniform bool use_image = false;                                      // Lay the image below over the base color
uniform sampler2D image : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // Any picture (PNG / JPG)
uniform float image_size : hint_range(0.05, 4.0, 0.05) = 1.0;        // Bigger number = bigger picture

void fragment() {
	vec3 col = base_color;
	if (use_image) {
		col *= texture(image, UV / image_size).rgb;
	}
	// a stripe every stripe_spacing meters along the ramp (UV.y is meters / 20)
	float along = fract(UV.y * 20.0 / stripe_spacing + TIME * scroll_speed / stripe_spacing);
	float stripe = step(1.0 - stripe_width, along);
	ALBEDO = mix(col, stripe_color, stripe);
	EMISSION = stripe_color * stripe * stripe_glow;
	ROUGHNESS = roughness_amount;
	METALLIC = metal;
}
