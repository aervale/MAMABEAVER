// Second layer of the black hole: the swirling gas cloud that sits at the
// same position as the lensing shell but stays translucent.
//
// The pairing follows what real black-hole imagery actually shows (EHT
// images, and the Interstellar renders): a hard-edged shadow ringed by a
// bright photon ring — that is black_hole_lens.gdshader — wrapped in a much
// softer, larger, turbulent glow of infalling gas, which is this file. One
// asset alone reads as a flat sticker; the two together give the object
// depth and make it feel like it is disturbing the space around it.
//
// Drawn on a sphere larger than the lens shell. Density is highest near the
// equator (an inflated disk rather than a ball) and swirls with radius, so
// the gas appears to be spiralling inward. Additive blending on a low alpha
// keeps it from ever hiding the shadow or the starfield behind it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled;

uniform vec3 hot_color : source_color = vec3(1.0, 0.55, 0.18);
uniform vec3 cool_color : source_color = vec3(0.28, 0.42, 1.0);
uniform float density : hint_range(0.0, 1.5) = 0.16;
uniform float swirl_speed : hint_range(-2.0, 2.0) = 0.35;
// How flattened the cloud is: 1 = spherical, higher = disk-like.
uniform float equator_bias : hint_range(1.0, 6.0) = 2.6;

varying vec3 local_position;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y),
		u.z
	);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		total += vnoise(p) * amplitude;
		p = p * 2.17 + vec3(1.7);
		amplitude *= 0.5;
	}
	return total;
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 p = normalize(local_position);

	// Squash toward the equatorial plane so the gas reads as an inflated
	// disk instead of a fog ball.
	float equator = 1.0 - pow(abs(p.y), 1.0 / equator_bias);

	// Twist the sample by height so the pattern shears as it orbits — the
	// cheap way to make gas look like it is spiralling in.
	float angle = TIME * swirl_speed + p.y * 2.5;
	float sine = sin(angle);
	float cosine = cos(angle);
	vec3 swirled = vec3(
		p.x * cosine - p.z * sine,
		p.y,
		p.x * sine + p.z * cosine
	);

	float gas = fbm(swirled * 3.6);
	gas = smoothstep(0.35, 0.95, gas) * equator;

	// Hot on the inside edge, cooler further out.
	vec3 color = mix(cool_color, hot_color, clamp(equator * 1.3, 0.0, 1.0));

	// Fade out toward the sphere's silhouette. Without this the shell has a
	// hard circular edge and reads as a flat sticker pasted over the sky —
	// which is exactly what made the starfield look like it "cut off".
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float softness = pow(facing, 1.7);

	ALBEDO = color;
	EMISSION = color * gas * 1.1 * softness;
	ALPHA = clamp(gas * density * softness, 0.0, 0.5);
}
