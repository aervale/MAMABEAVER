# =============================================================================
# surface_dust.gd — a self-deleting one-shot dust puff.
#
# Spawned by spaceship_flight.gd when the ship touches down on a planet (a
# big burst scaled by impact speed) and, much smaller, repeatedly while the
# player walks around the surface. Everything is built in code, like the
# rest of the project's effects, so there is no scene file to keep in sync.
#
# Quest notes: one_shot particles with explosiveness 1.0 emit a single burst
# and then the node frees itself after `lifetime`, so nothing accumulates.
# Unshaded, alpha-blended billboards, no shadows, no lights.
# =============================================================================
extends Node3D
class_name SurfaceDust

## Set these BEFORE add_child (they are read in _ready).
var burst_amount := 24
var burst_speed := 3.0
var puff_lifetime := 0.9
var puff_size := 0.35
## Deliberately low alpha: at 0.55 the landing burst whited out the view
## and you could not see what you were shooting at.
var dust_color := Color(0.72, 0.66, 0.58, 0.16)
## Direction the dust is thrown (usually the planet's surface normal).
var surface_normal := Vector3.UP


func _ready() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.25
	# Dust sprays outward along the surface, not straight up: a shallow cone
	# around the normal reads as kicked-up regolith.
	process.direction = surface_normal
	process.spread = 75.0
	process.initial_velocity_min = burst_speed * 0.35
	process.initial_velocity_max = burst_speed
	process.gravity = Vector3.ZERO
	process.damping_min = 1.5
	process.damping_max = 3.5
	process.scale_min = 0.45
	process.scale_max = 1.1
	# Grow slightly as it fades, like a real dust cloud expanding.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.5))
	scale_curve.add_point(Vector2(1.0, 1.0))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process.scale_curve = scale_texture

	var gradient := Gradient.new()
	gradient.set_color(0, dust_color)
	gradient.add_point(0.35, dust_color)
	gradient.set_color(gradient.get_point_count() - 1, Color(dust_color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(puff_size, puff_size)
	quad.material = material

	var particles := GPUParticles3D.new()
	particles.name = "DustBurst"
	particles.amount = burst_amount
	particles.lifetime = puff_lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3.ONE * -8.0, Vector3.ONE * 16.0)
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = true
	add_child(particles)

	# Self-cleanup once the burst has fully faded.
	get_tree().create_timer(puff_lifetime + 0.4).timeout.connect(queue_free)
