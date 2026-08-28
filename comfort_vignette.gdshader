shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;

// 0 = invisible; 1 = narrowest comfort aperture.
uniform float strength : hint_range(0.0, 1.0) = 0.0;


void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius = length(centered);
	// Keep a fully clear centre, but let ordinary walking visibly reach the
	// peripheral field. A wide feather avoids a distracting hard tunnel edge.
	float shaped_strength = smoothstep(0.0, 1.0, strength);
	float inner_radius = mix(0.98, 0.38, shaped_strength);
	float feather = mix(0.24, 0.34, shaped_strength);
	float mask = smoothstep(inner_radius, inner_radius + feather, radius);
	ALBEDO = vec3(0.0);
	ALPHA = mask * min(strength * 1.35, 0.9);
}
