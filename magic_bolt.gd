# =============================================================================
# magic_bolt.gd — the beaver-collecting projectile. Spawned into the scene
# root by spaceship_flight.gd's _try_fire() (VR trigger while LANDED, or
# desktop right-click); at most max_live_bolts exist at once.
#
# Flies at a constant-ish speed but its HORIZONTAL velocity is curved every
# tick by the same gravity field the ship feels — via the flight
# controller's get_total_gravity_at() — so bolts bend around planets and
# visibly spiral into black holes. Vertical velocity is left ballistic-free
# (beavers live near the flight plane; keeping bolts there keeps shots
# makeable).
#
# No physics bodies (project style): hits are distance checks.
# Despawns when it: exceeds its lifetime, leaves the play volume, splashes
# into a planet (duck-typed target_diameter_meters), is eaten by a black
# hole (captures()), or connects with an IDLE beaver — which the director
# then tractors to the ship.
#
# Visual: small emissive orb + a short fading trail of ghost spheres,
# all unshaded; one low-range OmniLight so landings get a light show
# (bounded: <= 3 bolts alive).
# =============================================================================
extends Node3D
class_name MagicBolt

const MAX_LIFETIME := 8.0
const TRAIL_LENGTH := 4
const TRAIL_SPACING_SECONDS := 0.04

var velocity := Vector3.ZERO
var hit_radius := 2.0

var _flight: Node3D
var _director: Node3D
var _obstacles_root: Node3D
var _black_holes_root: Node3D
var _play_min := Vector2(-20.0, -20.0)
var _play_max := Vector2(220.0, 220.0)

var _lifetime := 0.0
var _trail: Array[MeshInstance3D] = []
var _trail_positions: Array[Vector3] = []
var _trail_timer := 0.0


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
	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(0.75, 0.95, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.35, 0.8, 1.0)
	core_material.emission_energy_multiplier = 4.0

	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.radial_segments = 10
	core_mesh.rings = 5
	core_mesh.material = core_material

	var core := MeshInstance3D.new()
	core.name = "BoltCore"
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)

	var light := OmniLight3D.new()
	light.name = "BoltLight"
	light.light_color = Color(0.4, 0.8, 1.0)
	light.light_energy = 1.4
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)

	# Trail: ghost spheres re-anchored to recent positions. They're children
	# of the SCENE (top_level) so they lag behind in world space.
	for index in TRAIL_LENGTH:
		var ghost_material := core_material.duplicate() as StandardMaterial3D
		ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var fade := 1.0 - float(index + 1) / float(TRAIL_LENGTH + 1)
		ghost_material.albedo_color = Color(0.55, 0.85, 1.0, 0.4 * fade)
		ghost_material.emission_energy_multiplier = 2.0 * fade
		var ghost_mesh := SphereMesh.new()
		ghost_mesh.radius = 0.08 * (0.5 + 0.5 * fade)
		ghost_mesh.height = ghost_mesh.radius * 2.0
		ghost_mesh.radial_segments = 8
		ghost_mesh.rings = 4
		ghost_mesh.material = ghost_material
		var ghost := MeshInstance3D.new()
		ghost.mesh = ghost_mesh
		ghost.top_level = true
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ghost)
		_trail.append(ghost)


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()
		return

	# Curve through the shared gravity field (logical XY == world XZ).
	if _flight != null and _flight.has_method("get_total_gravity_at"):
		var gravity: Vector2 = _flight.call("get_total_gravity_at", global_position)
		velocity.x += gravity.x * delta
		velocity.z += gravity.y * delta
	global_position += velocity * delta

	_update_trail(delta)

	# Out of the play volume?
	if (
		global_position.x < _play_min.x or global_position.x > _play_max.x
		or global_position.z < _play_min.y or global_position.z > _play_max.y
		or global_position.y < 0.0 or global_position.y > 30.0
	):
		queue_free()
		return

	# Splash on a planet's surface.
	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var planet := child as Node3D
			if planet == null:
				continue
			var diameter: Variant = planet.get("target_diameter_meters")
			if diameter == null:
				continue
			if global_position.distance_to(planet.global_position) <= float(diameter) * 0.5:
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
	if _director != null and _director.has_method("find_beaver_near"):
		var beaver: Node3D = _director.call("find_beaver_near", global_position, hit_radius)
		if beaver != null:
			_director.call("begin_tractor", beaver, _flight)
			queue_free()


func _update_trail(delta: float) -> void:
	_trail_timer += delta
	if _trail_timer >= TRAIL_SPACING_SECONDS:
		_trail_timer = 0.0
		_trail_positions.push_front(global_position)
		while _trail_positions.size() > TRAIL_LENGTH:
			_trail_positions.pop_back()
	for index in _trail.size():
		if index < _trail_positions.size():
			_trail[index].global_position = _trail_positions[index]
