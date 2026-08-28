# =============================================================================
# ambient_dust.gd — drifting solar-dust motes around the player.
#
# Sits under XROrigin3D in main.tscn, so the emission box FOLLOWS the ship;
# with local_coords disabled the already-spawned motes stay put in world
# space, which is what sells motion — fly forward and you stream through
# them. Everything (process material, gradient, mesh, draw material) is built
# in code at _ready(), matching this project's build-visuals-in-code style.
#
# The motes drift along the sun's light direction (read live from the
# SunLight node via sun_path), i.e. "blown" by solar wind away from the sun,
# and are tinted the same warm orange as the sky shader's sun dust so the
# whole scene reads as one atmosphere. Rendered as tiny additive billboards:
# cheap on Quest (a few hundred quads, unshaded, no shadows).
#
# preprocess warms the field up so the space is already dusty on spawn
# instead of filling in over the first ~10 seconds.
# =============================================================================
extends Node3D
class_name AmbientDust

@export_node_path("DirectionalLight3D") var sun_path: NodePath

@export_range(50, 1000, 10) var particle_count := 240
## Half-size of the box (centered on this node) where new motes appear.
@export var box_extents := Vector3(22.0, 12.0, 22.0)
@export_range(0.1, 6.0, 0.1) var drift_speed := 1.1
@export var dust_color := Color(1.0, 0.62, 0.3, 0.5)
@export_range(0.01, 0.3, 0.005) var mote_size_meters := 0.06

func _ready() -> void:
	# Dust travels the same way the sunlight does: along the light's -Z.
	var drift_direction := Vector3(-0.3, -0.1, 0.5)
	var sun := get_node_or_null(sun_path) as DirectionalLight3D
	if sun != null:
		drift_direction = -sun.global_basis.z
	else:
		push_warning("AmbientDust|WARN: no SunLight assigned, using fallback drift")

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = box_extents
	process.direction = drift_direction
	process.spread = 30.0
	process.initial_velocity_min = drift_speed * 0.4
	process.initial_velocity_max = drift_speed
	process.gravity = Vector3.ZERO
	process.scale_min = 0.35
	process.scale_max = 1.0
	# Fade in/out over the mote's life so spawns/despawns never pop.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(dust_color, 0.0))
	gradient.add_point(0.2, dust_color)
	gradient.add_point(0.8, dust_color)
	gradient.set_color(gradient.get_point_count() - 1, Color(dust_color, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp

	var draw_material := StandardMaterial3D.new()
	draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_material.vertex_color_use_as_albedo = true
	draw_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_material.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(mote_size_meters, mote_size_meters)
	quad.material = draw_material

	var particles := GPUParticles3D.new()
	particles.name = "DustParticles"
	particles.amount = particle_count
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	# World-space simulation: the emitter box follows the ship, spawned motes
	# do not (that relative motion is the whole effect).
	particles.local_coords = false
	# Generous hand-set bounds; the default auto AABB would cull the system
	# when the emitter node itself leaves the view frustum.
	particles.visibility_aabb = AABB(Vector3.ONE * -80.0, Vector3.ONE * 160.0)
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
