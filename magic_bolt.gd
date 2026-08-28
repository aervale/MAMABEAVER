# =============================================================================
# magic_bolt.gd — the beaver-collecting projectile. Spawned into the scene
# root by spaceship_flight.gd's _try_fire() (VR trigger or desktop
# right-click); at most max_live_bolts exist at once. Airborne shots are
# visual only; only bolts fired while LANDED can collect beavers.
#
# Its HORIZONTAL velocity is nudged every tick by the same gravity field
# the ship feels — via the flight controller's get_total_gravity_at() — so
# bolts visibly bend around planets and curve toward black holes. The pull
# is scaled by `gravity_scale` (well under 1.0): at full strength a bolt
# fired at a beaver 6 m away curved into the planet before arriving, which
# made aiming feel random. Scaled down, shots fly essentially where you
# point them and the curve is flavour you can exploit, not fight.
# Vertical velocity is left ballistic-free (beavers live near the flight
# plane; keeping bolts there keeps shots makeable).
#
# No physics bodies (project style): hits are distance checks.
# Despawns when it: exceeds its lifetime, leaves the play volume, splashes
# into a planet (duck-typed target_diameter_meters), is eaten by a black
# hole (captures()), or connects with an IDLE beaver — which the director
# then tractors to the ship.
#
# Visual (per the reference art): a hot white-blue core inside a translucent
# cyan envelope stretched along its flight path, trailing a spray of sparks,
# and bursting into a splash when it lands. One low-range OmniLight each,
# bounded by max_live_bolts (<= 3 alive).
# =============================================================================
extends Node3D
class_name MagicBolt

const MAX_LIFETIME := 8.0
const SurfaceDustScript = preload("res://surface_dust.gd")

var velocity := Vector3.ZERO
var hit_radius := 2.0
## Fraction of real gravity applied to the bolt. 0 = laser, 1 = full field.
var gravity_scale := 0.0
## Snapshot of the ship state at launch. An airborne shot must remain unable
## to collect even if the ship lands before the projectile reaches a beaver.
var can_capture_beavers := true
## The planet the shooter is standing on. Skipped by the splash test so
## surface-skimming shots reach the beavers instead of being absorbed.
var ignored_planet: Node3D = null

var _flight: Node3D
var _director: Node3D
var _obstacles_root: Node3D
var _black_holes_root: Node3D
var _play_min := Vector2(-20.0, -20.0)
var _play_max := Vector2(220.0, 220.0)

var _lifetime := 0.0
var _head: MeshInstance3D
var _shell: MeshInstance3D
var _light: OmniLight3D
var _sparks: GPUParticles3D


## Called by the flight controller right after instantiation, before add_child.
func setup(
	flight: Node3D,
	director: Node3D,
	obstacles_root: Node3D,
	black_holes_root: Node3D,
	play_min: Vector2,
	play_max: Vector2
) -> void:
	_flight = flight
	_director = director
	_obstacles_root = obstacles_root
	_black_holes_root = black_holes_root
	_play_min = play_min
	_play_max = play_max


func _ready() -> void:
	# Look, per the reference art: a hot white-blue core wrapped in a
	# translucent cyan shell, stretched along its flight path like a comet,
	# with a spray of sparks trailing behind it. Not a plain sphere.
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(0.92, 0.99, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.45, 0.9, 1.0)
	core_material.emission_energy_multiplier = 6.0

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.13
	core_mesh.height = 0.26
	core_mesh.radial_segments = 28
	core_mesh.rings = 16
	core_mesh.material = core_material

	_head = MeshInstance3D.new()
	_head.name = "BoltCore"
	_head.mesh = core_mesh
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_head)

	# Translucent outer envelope, stretched backwards into a teardrop.
	var shell_material := StandardMaterial3D.new()
	shell_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shell_material.albedo_color = Color(0.25, 0.75, 1.0, 0.5)
	shell_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.26
	shell_mesh.height = 0.52
	shell_mesh.radial_segments = 32
	shell_mesh.rings = 18
	shell_mesh.material = shell_material

	_shell = MeshInstance3D.new()
	_shell.name = "BoltShell"
	_shell.mesh = shell_mesh
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Squashed sideways and stretched back: a comet head, not a ball.
	_shell.scale = Vector3(0.75, 0.75, 2.6)
	add_child(_shell)

	_light = OmniLight3D.new()
	_light.name = "BoltLight"
	_light.light_color = Color(0.4, 0.8, 1.0)
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)

	_build_spark_trail()


## Spray of sparks streaming off the head, matching the speckle in the
## reference art. World-space so they hang in the air as the bolt moves on.
func _build_spark_trail() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 3.2
	process.gravity = Vector3.ZERO
	process.damping_min = 1.0
	process.damping_max = 3.0
	process.scale_min = 0.4
	process.scale_max = 1.0

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.85, 0.98, 1.0, 0.9))
	gradient.add_point(0.4, Color(0.35, 0.8, 1.0, 0.6))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.1, 0.5, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp

	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.vertex_color_use_as_albedo = true
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	spark_material.disable_receive_shadows = true

	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.12, 0.12)
	spark_mesh.material = spark_material

	_sparks = GPUParticles3D.new()
	_sparks.name = "SparkTrail"
	_sparks.amount = 90
	_sparks.lifetime = 0.75
	_sparks.local_coords = false
	_sparks.visibility_aabb = AABB(Vector3.ONE * -30.0, Vector3.ONE * 60.0)
	_sparks.process_material = process
	_sparks.draw_pass_1 = spark_mesh
	_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparks.emitting = true
	add_child(_sparks)


## Submit all expensive visual variants to the renderer during loading. The
## projectile is sub-pixel but deliberately visible: `visible = false` would
## skip the draw list and leave the first trigger pull compiling GPU pipelines.
func prepare_render_prewarm() -> void:
	_lifetime = 0.0
	scale = Vector3.ONE * 0.0005
	visible = true
	# Lights have no shader pipeline to warm and could flash even when their
	# parent is tiny, so only meshes and GPU particles participate.
	if _light != null:
		_light.visible = false
	if _sparks != null:
		_sparks.emitting = true
		_sparks.restart()


## Restore a prewarmed bolt to a pristine first-shot state. Restarting the
## world-space trail also discards microscopic particles emitted by the camera
## during warm-up instead of leaving a cyan speck behind the player's head.
func prepare_for_launch() -> void:
	_lifetime = 0.0
	scale = Vector3.ONE
	visible = true
	if _light != null:
		_light.visible = true
	if _sparks != null:
		_sparks.restart()
		_sparks.emitting = true


## Splash burst left behind when the bolt ends, like the reference impact.
func _burst(color: Color, amount: int) -> void:
	var dust := SurfaceDustScript.new() as SurfaceDust
	dust.surface_normal = -velocity.normalized() if velocity.length() > 0.01 else Vector3.UP
	dust.burst_amount = amount
	dust.burst_speed = 7.0
	dust.puff_lifetime = 0.6
	dust.puff_size = 0.26
	dust.dust_color = color
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(dust)
	dust.global_position = global_position


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()
		return

	# Curve through the shared gravity field (logical XY == world XZ).
	if _flight != null and _flight.has_method("get_total_gravity_at"):
		var gravity: Vector2 = _flight.call("get_total_gravity_at", global_position)
		velocity.x += gravity.x * gravity_scale * delta
		velocity.z += gravity.y * gravity_scale * delta
	global_position += velocity * delta

	# Point the stretched envelope along the direction of travel.
	if _shell != null and velocity.length_squared() > 0.001:
		var forward := velocity.normalized()
		var reference := Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT
		_shell.global_basis = Basis().looking_at(forward, reference)
		_shell.scale = Vector3(0.75, 0.75, 2.6)

	# Out of the play volume?
	if (
		global_position.x < _play_min.x or global_position.x > _play_max.x
		or global_position.z < _play_min.y or global_position.z > _play_max.y
		# Generous vertical bounds: walking a sphere puts the player far
		# above or below the flight plane, and the old 0..30 window killed
		# bolts the instant they were fired from a pole.
		or global_position.y < -60.0 or global_position.y > 90.0
	):
		queue_free()
		return

	# Splash on a planet's surface.
	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var planet := child as Node3D
			if planet == null or planet == ignored_planet:
				continue
			var diameter: Variant = planet.get("target_diameter_meters")
			if diameter == null:
				continue
			if global_position.distance_to(planet.global_position) <= float(diameter) * 0.5:
				_burst(Color(0.5, 0.85, 1.0, 0.6), 38)
				queue_free()
				return

	# Eaten by a black hole (the same field that just curved us).
	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("captures"):
				continue
			if bool(black_hole.call("captures", global_position, 0.3)):
				queue_free()
				return

	# The payoff: connect with a beaver.
	if can_capture_beavers and _director != null and _director.has_method("find_beaver_near"):
		var beaver: Node3D = _director.call("find_beaver_near", global_position, hit_radius)
		if beaver != null:
			_director.call("begin_tractor", beaver, _flight)
			_burst(Color(0.6, 0.95, 1.0, 0.7), 55)
			queue_free()
