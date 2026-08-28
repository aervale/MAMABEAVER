shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;

// 0 = invisible; 1 = narrowest comfort aperture.
uniform float strength : hint_range(0.0, 1.0) = 0.0;


void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float radius = length(centered);
	// The clear centre contracts as motion grows. Edges stay soft so the
	// overlay reads as reduced peripheral vision rather than a hard mask.
	float inner_radius = mix(0.92, 0.34, strength);
	float mask = smoothstep(inner_radius, inner_radius + 0.32, radius);
	ALBEDO = vec3(0.0);
	ALPHA = mask * min(strength * 1.18, 0.86);
}
