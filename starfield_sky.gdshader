// Deep-space procedural sky (assigned to the WorldEnvironment's Sky in
// main.tscn). The game takes place in open space, so this shader is the
// entire backdrop — there is no floor or horizon.
//
// QUALITY/COST SPLIT (important for Quest):
//   render_mode use_half_res_pass makes Godot call sky() twice. The
//   expensive nebula (domain-warped 4-octave fbm + dust + core glow) runs in
//   the HALF-RES pass — quarter the pixels, and the upscale doubles as free
//   softening for gas clouds. Crisp things (stars, dither) run full-res and
//   read the nebula back through HALF_RES_COLOR.
//   No TIME anywhere: a static sky keeps the radiance map (used for ambient
//   reflections) cacheable instead of re-rendering every frame.
//
// LAYERS, all derived from the view direction EYEDIR:
//   1. base_color — near-black space.
//   2. nebula     — value-noise fbm, domain-warped so clouds look wispy
//                   instead of blobby, tinted cool blue / warm purple,
//                   concentrated into a tilted "milky way" band
//                   (exponential falloff from a great circle).
//   3. dust       — high-frequency noise DARKENS the band's midline,
//                   faking the galaxy's dust lanes.
//   4. core glow  — warm brightening toward core_direction, the galactic
//                   center. Gives the band a bright anchor point.
//   5. sun + dust — reads the scene's DirectionalLight (LIGHT0_*
//                   built-ins) so the backdrop always matches the actual
//                   sun: a wide fbm-textured orange dust veil in the gas
//                   pass, plus a tight halo and a hot core disc full-res
//                   (the disc overshoots 1.0 so bloom picks it up).
//   6. stars      — four cube-grid layers (each cell hashes to at most one
//                   star with jittered position/brightness) with per-star
//                   color temperature (blue-white .. warm). The two dim
//                   layers get denser inside the band.
//   7. dither     — ±0.5/255 hash noise so the dark gradients don't band
//                   on Quest's display.
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 base_color : source_color = vec3(0.004, 0.005, 0.012);
uniform vec3 nebula_cool : source_color = vec3(0.045, 0.065, 0.17);
uniform vec3 nebula_warm : source_color = vec3(0.10, 0.045, 0.16);
uniform vec3 core_color : source_color = vec3(0.35, 0.22, 0.12);
uniform float nebula_intensity : hint_range(0.0, 2.0) = 0.9;
uniform float dust_strength : hint_range(0.0, 1.0) = 0.6;
uniform float star_brightness : hint_range(0.0, 4.0) = 1.6;
// Normal of the galactic-band plane; tweak to reorient the milky way.
uniform vec3 band_normal = vec3(0.2, 1.0, 0.35);
// Direction of the bright galactic core (should lie roughly in the band
// plane, i.e. near-perpendicular to band_normal).
uniform vec3 core_direction = vec3(0.9, -0.1, -0.42);

// Sun-facing dust: warm haze scattered toward the DirectionalLight.
uniform vec3 sun_dust_color : source_color = vec3(0.9, 0.45, 0.16);
uniform float sun_dust_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec3 sun_halo_color : source_color = vec3(1.0, 0.72, 0.4);

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

// 4-octave fractal noise. The 1.31 lacunarity offset between octaves breaks
// up grid-aligned artifacts from the underlying value noise.
float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += vnoise(p) * amplitude;
		p = p * 2.13 + vec3(1.31);
		amplitude *= 0.5;
	}
	return total;
}

// Per-star color temperature: hot blue-white through white to cool orange,
// re-hashed from the star cell's base hash so it's stable per star.
vec3 star_tint(float h) {
	float t = fract(h * 7.31);
	vec3 hot = vec3(0.62, 0.78, 1.0);
	vec3 white = vec3(0.95, 0.97, 1.0);
	vec3 cool = vec3(1.0, 0.80, 0.55);
	return t < 0.5 ? mix(hot, white, t * 2.0) : mix(white, cool, t * 2.0 - 1.0);
}

// One star layer: quantize the view ray into a cube grid at `scale`; a cell
// whose hash clears `cutoff` owns one star at a jittered position. Distance
// to that point in cell space gives a soft round dot. Returns tinted color.
vec3 star_layer(vec3 dir, float scale, float cutoff, float radius) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	vec3 jitter = vec3(hash13(cell + 17.1), hash13(cell + 31.7), hash13(cell + 47.3));
	vec3 star_pos = cell + 0.5 + (jitter - 0.5) * 0.8;
	float dist = length(p - star_pos);
	float core = smoothstep(radius, radius * 0.25, dist);
	float intensity = core * step(cutoff, h) * (0.35 + 0.65 * fract(h * 91.7));
	return star_tint(h) * intensity;
}

void sky() {
	vec3 dir = EYEDIR;

	// Galactic band: strongest where the view ray lies in the band plane.
	float band = exp(-3.2 * abs(dot(dir, normalize(band_normal))));

	if (AT_HALF_RES_PASS) {
		// ---- expensive gas pass, quarter the pixels ----
		// Domain warp: offset the sample position by low-frequency noise so
		// cloud edges smear into filaments instead of round blobs.
		vec3 warp = vec3(
			vnoise(dir * 2.1 + 13.7),
			vnoise(dir * 2.1 + 57.2),
			vnoise(dir * 2.1 + 91.4)
		) - 0.5;
		vec3 warped_dir = dir + warp * 0.55;

		float clouds = fbm(warped_dir * 3.4);
		// Sharpen: pull the fbm midtones apart so clouds have shape.
		clouds = smoothstep(0.25, 0.85, clouds);

		vec3 gas_tint = mix(nebula_cool, nebula_warm, vnoise(warped_dir * 1.6));
		vec3 gas = gas_tint * clouds * (0.22 + band * 1.35) * nebula_intensity;

		// Dust lanes: high-frequency noise carves dark streaks, strongest
		// along the band midline where real galaxies show silhouetted dust.
		float dust = fbm(warped_dir * 6.8 + 31.0);
		dust = smoothstep(0.45, 0.75, dust) * band * dust_strength;
		gas *= 1.0 - dust;

		// Galactic core: warm glow around one direction along the band.
		float core_alignment = max(dot(dir, normalize(core_direction)), 0.0);
		gas += core_color * pow(core_alignment, 9.0) * (0.35 + band) * nebula_intensity;

		// Orange dust veil toward the sun: a wide scatter lobe, broken up
		// by the same fbm so it reads as lit dust, not a flat gradient.
		if (LIGHT0_ENABLED) {
			float sun_amount = clamp(dot(dir, normalize(LIGHT0_DIRECTION)), 0.0, 1.0);
			float veil = 0.55 + 0.45 * fbm(warped_dir * 4.7 + 7.0);
			gas += sun_dust_color * pow(sun_amount, 3.0) * veil * sun_dust_strength;
		}

		COLOR = gas;
		ALPHA = 1.0;
	} else {
		// ---- crisp full-res pass: nebula readback + stars + dither ----
		vec3 color = base_color + HALF_RES_COLOR.rgb;

		vec3 stars = star_layer(dir, 26.0, 0.94, 0.35) * 1.4;
		stars += star_layer(dir, 55.0, 0.88, 0.42) * 0.55;
		stars += star_layer(dir, 90.0, 0.82, 0.5) * 0.22 * (0.4 + band * 1.6);
		stars += star_layer(dir, 140.0, 0.78, 0.55) * 0.10 * (0.2 + band * 2.2);
		color += stars * star_brightness;

		// Sun halo + core disc, crisp so they must be full-res. The core
		// deliberately exceeds 1.0: the environment's glow pass blooms it.
		if (LIGHT0_ENABLED) {
			float sun_amount = clamp(dot(dir, normalize(LIGHT0_DIRECTION)), 0.0, 1.0);
			color += sun_dust_color * pow(sun_amount, 12.0) * sun_dust_strength * 0.6;
			color += sun_halo_color * pow(sun_amount, 220.0) * 2.2;
			color += sun_halo_color * smoothstep(0.99965, 0.99995, sun_amount) * 22.0;
		}

		// Break up banding in the dark gradients (visible on Quest panels).
		color += (hash13(dir * 1024.7) - 0.5) * (1.0 / 255.0);

		COLOR = max(color, vec3(0.0));
	}
}
