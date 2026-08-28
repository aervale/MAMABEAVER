// Deep-space procedural sky (assigned to the WorldEnvironment's Sky in
// main.tscn). Replaces the old ProceduralSkyMaterial + floor grid: the game
// now takes place in open space, so this shader is the entire backdrop.
//
// Built for the Quest mobile renderer: no textures, value noise capped at
// 2-3 octaves, and no TIME dependency (a static sky lets Godot cache the
// radiance map and avoids per-frame recompute cost).
//
// Three layers, all derived from the view direction EYEDIR:
//   1. base_color   — near-black space.
//   2. nebula       — cheap value-noise clouds tinted cool blue / warm
//                     purple, concentrated into a tilted "milky way" band
//                     (exponential falloff from a great circle).
//   3. stars        — three cube-grid layers: each grid cell hashes to at
//                     most one star with random position/brightness. Sparse
//                     bright stars + two denser dim layers; the dimmest
//                     layer is boosted inside the band so the galaxy reads
//                     as depth, not decoration.
shader_type sky;

uniform vec3 base_color : source_color = vec3(0.004, 0.005, 0.012);
uniform vec3 nebula_cool : source_color = vec3(0.045, 0.065, 0.17);
uniform vec3 nebula_warm : source_color = vec3(0.10, 0.045, 0.16);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.6;
// Normal of the galactic-band plane; tweak to reorient the milky way.
uniform vec3 band_normal = vec3(0.2, 1.0, 0.35);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// Trilinearly interpolated value noise (8 hashes per call — the budget item).
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float c000 = hash13(i);
	float c100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float c010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float c110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float c001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float c101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float c011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float c111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(c000, c100, u.x), mix(c010, c110, u.x), u.y),
		mix(mix(c001, c101, u.x), mix(c011, c111, u.x), u.y),
		u.z
	);
}

// One star layer: quantize the view ray into a cube grid at `scale`; a cell
// whose hash clears `cutoff` owns one star at a jittered position. Distance
// to that point in cell space gives a soft round dot. Cube-grid projection
// slightly stretches stars near cell corners — invisible in practice.
float star_layer(vec3 dir, float scale, float cutoff, float radius) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	vec3 jitter = vec3(hash13(cell + 17.1), hash13(cell + 31.7), hash13(cell + 47.3));
	vec3 star_pos = cell + 0.5 + (jitter - 0.5) * 0.8;
	float dist = length(p - star_pos);
	float core = smoothstep(radius, radius * 0.25, dist);
	// fract(h * 91.7) re-hashes the cell for per-star brightness variety.
	return core * step(cutoff, h) * (0.35 + 0.65 * fract(h * 91.7));
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 color = base_color;

	// Galactic band: strongest where the view ray is perpendicular to the
	// band normal (i.e. looking along the plane of the "galaxy").
	float band = exp(-3.2 * abs(dot(dir, normalize(band_normal))));

	float clouds = vnoise(dir * 3.1) * 0.65 + vnoise(dir * 7.3) * 0.35;
	vec3 nebula = mix(nebula_cool, nebula_warm, vnoise(dir * 1.7));
	color += nebula * clouds * (0.25 + band) * nebula_intensity;

	float stars = star_layer(dir, 26.0, 0.94, 0.35) * 1.4;
	stars += star_layer(dir, 55.0, 0.88, 0.42) * 0.55;
	stars += star_layer(dir, 90.0, 0.82, 0.5) * 0.22 * (0.4 + band * 1.6);
	color += vec3(0.9, 0.95, 1.0) * stars * star_brightness;

	COLOR = color;
}
