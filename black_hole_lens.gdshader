// Gravitational-lensing shell for black_hole.gd.
//
// This is the "distorts everything near it" effect, and it deliberately is
// NOT a downloaded model: lensing has to bend whatever is actually behind
// the object each frame, so it can only come from a shader that reads the
// screen. A static mesh can only ever fake a painted-on swirl.
//
// The shader goes on a large transparent sphere centred on the black hole.
// For every fragment it works out how far that pixel is from the hole's
// centre ON SCREEN, then re-samples the screen texture from a point pulled
// toward the centre, with a 1/r falloff — the same shape as real light
// deflection. Stars, planets and the nebula therefore smear around the hole
// and the disk appears to wrap over the top.
//
// Everything is derived from NODE_POSITION_VIEW, so one material serves
// every black hole regardless of its size or where the camera is; the only
// per-instance value is shadow_world_radius (set from capture_radius).
//
// Cost: one dependent screen-texture read per covered pixel. Bounded by
// keeping the shell small on screen; there are only five black holes and
// they are rarely close together. If this ever costs too much on Quest,
// setting enable_lensing = false on the node falls back to the opaque
// horizon + disk and nothing else changes.
shader_type spatial;
// cull_disabled + the FRONT_FACING test below: the shell is big enough
// that the player often flies INSIDE it, and with ordinary back-face
// culling the whole effect silently vanishes at exactly the moment it
// should be most dramatic.
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// World radius of the black shadow (matches the node's capture_radius).
uniform float shadow_world_radius = 5.0;
// World radius of the shell mesh itself, used to tell inside from outside.
uniform float shell_world_radius = 20.0;
// How far out the distortion is still visible, in shadow radii.
uniform float lens_falloff_radii : hint_range(1.5, 12.0) = 6.0;
// Overall bend amount.
uniform float lens_strength : hint_range(0.0, 3.0) = 1.0;
uniform vec3 photon_ring_color : source_color = vec3(1.0, 0.72, 0.35);
uniform float photon_ring_energy : hint_range(0.0, 8.0) = 2.6;

void fragment() {
	// Draw the shell's far side only when the camera is inside it, and its
	// near side only when outside — exactly one layer either way, so the
	// deflection is never applied twice.
	bool camera_inside = length(NODE_POSITION_VIEW) < shell_world_radius;
	if (FRONT_FACING == camera_inside) {
		discard;
	}

	vec2 aspect = vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);

	// Where the hole's centre lands on screen, and how big its shadow is
	// there — both projected live, so they stay correct at any distance.
	vec4 centre_clip = PROJECTION_MATRIX * vec4(NODE_POSITION_VIEW, 1.0);
	if (centre_clip.w <= 0.0) {
		discard;  // hole is behind the camera
	}
	vec2 centre_uv = centre_clip.xy / centre_clip.w * 0.5 + 0.5;

	// Project a point one shadow-radius to the side to measure the shadow's
	// on-screen size (the camera's right vector in view space is +X).
	vec4 edge_clip = PROJECTION_MATRIX
		* vec4(NODE_POSITION_VIEW + vec3(shadow_world_radius, 0.0, 0.0), 1.0);
	vec2 edge_uv = edge_clip.xy / max(edge_clip.w, 0.0001) * 0.5 + 0.5;
	float shadow_uv_radius = max(length((edge_uv - centre_uv) * aspect), 0.0001);

	vec2 offset = (SCREEN_UV - centre_uv) * aspect;
	float radius = max(length(offset), 0.00001);
	// Distance from the centre measured in shadow radii: 1.0 is the rim.
	float x = radius / shadow_uv_radius;

	if (x < 1.0) {
		// Inside the shadow: no light escapes.
		ALBEDO = vec3(0.0);
		ALPHA = 1.0;
	} else {
		// Deflection falls off like 1/x, so the smear is violent at the rim
		// and fades to nothing far away.
		float fade = 1.0 - smoothstep(1.0, lens_falloff_radii, x);
		float deflection = lens_strength * shadow_uv_radius / x * fade;
		vec2 direction = offset / radius;
		vec2 sample_uv = SCREEN_UV - direction / aspect * deflection;
		vec3 lensed = texture(screen_texture, clamp(sample_uv, vec2(0.001), vec2(0.999))).rgb;

		// Einstein ring: light grazing the shadow piles up into a bright
		// rim just outside it.
		float ring = exp(-pow((x - 1.06) * 14.0, 2.0));
		lensed += photon_ring_color * ring * photon_ring_energy;

		ALBEDO = lensed;
		// Blend the shell out at its edge so its geometry is never visible.
		ALPHA = clamp(fade + ring, 0.0, 1.0);
	}
}
