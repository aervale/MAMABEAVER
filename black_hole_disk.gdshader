shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec3 inner_color : source_color = vec3(1.0, 0.92, 0.72);
uniform vec3 hot_color : source_color = vec3(1.0, 0.28, 0.035);
uniform vec3 outer_color : source_color = vec3(0.18, 0.025, 0.32);
uniform float inner_radius : hint_range(0.1, 0.8) = 0.34;
uniform float spin_speed : hint_range(-5.0, 5.0) = 0.42;
uniform float emission_energy : hint_range(0.0, 12.0) = 5.0;


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	if (radius < inner_radius || radius > 1.0) {
		discard;
	}

	float angle = atan(p.y, p.x);
	float normalized_radius = (radius - inner_radius) / (1.0 - inner_radius);
	float spiral = sin(angle * 5.0 - normalized_radius * 28.0 - TIME * spin_speed * 6.0);
	float fine_bands = sin(normalized_radius * 105.0 + angle * 2.0 + TIME * spin_speed * 2.0);
	float turbulence = 0.55 + 0.3 * spiral + 0.15 * fine_bands;
	float inner_heat = pow(1.0 - normalized_radius, 2.6);
	float outer_fade = 1.0 - smoothstep(0.72, 1.0, normalized_radius);
	float inner_fade = smoothstep(0.0, 0.05, normalized_radius);
	float alpha = clamp((0.32 + turbulence * 0.68) * outer_fade * inner_fade, 0.0, 1.0);

	vec3 color = mix(outer_color, hot_color, 1.0 - normalized_radius);
	color = mix(color, inner_color, inner_heat);
	ALBEDO = color;
	EMISSION = color * emission_energy * (0.55 + inner_heat * 1.7);
	ALPHA = alpha;
}
