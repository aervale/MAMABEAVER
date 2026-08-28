# =============================================================================
# spacecraft_visual.gd — the ship you are actually flying.
#
# Parented under XROrigin3D, so it travels with the player. In the headset
# you sit INSIDE it: the hull and nose sit below and ahead of your eyeline,
# and a canopy rail frames your view without blocking it. On desktop the
# orbit camera sees the whole craft from outside.
#
# Built from primitives in code, like every other model in this project
# (see mit_destination.gd), so there is no asset to license or keep in sync.
#
# It hides itself while you are LANDED — at that point the fiction is that
# you have stepped out onto the surface to collect beavers, and a hull
# wrapped around your head would block every shot.
# =============================================================================
extends Node3D
class_name SpacecraftVisual

@export_node_path("Node3D") var flight_path: NodePath

# FlightState.LANDED, appended last in spaceship_flight.gd's enum.
const STATE_LANDED := 4

var _flight: Node3D
var _engine_glow: Array[MeshInstance3D] = []
var _hull_root: Node3D


func _ready() -> void:
	_flight = get_node_or_null(flight_path) as Node3D
	_build_ship()


func _process(_delta: float) -> void:
	if _flight == null or _hull_root == null:
		return
	# Step out of the ship to collect; bring the hull back as soon as the
	# continuous takeoff begins so the player sees a craft during the glide.
	var taking_off := (
		_flight.has_method("is_takeoff_animating")
		and bool(_flight.call("is_takeoff_animating"))
	)
	_hull_root.visible = int(_flight.get("state")) != STATE_LANDED or taking_off

	# Engines pulse with throttle so the craft feels alive under thrust.
	var velocity: Variant = _flight.get("velocity")
	var throttle := 0.0
	if velocity is Vector2:
		throttle = clampf(velocity.length() / 18.0, 0.0, 1.0)
		_update_heading(velocity)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.009)
	for glow in _engine_glow:
		var material := glow.get_surface_override_material(0) as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 1.5 + throttle * 6.0 * pulse


## Point the ship's nose (-Z) exactly along its current velocity. There is no
## interpolation here: interpolation made the hull lag behind a turn and look
## as though it followed thrust/acceleration instead. Near zero speed we keep
## the last valid heading because velocity direction is undefined there.
## Only the visual rotates; the player's XR tracking origin remains stable.
func _update_heading(logical_velocity: Vector2) -> void:
	if logical_velocity.length_squared() < 0.04:
		return
	var forward := Vector3(logical_velocity.x, 0.0, logical_velocity.y).normalized()
	global_basis = Basis.looking_at(forward, Vector3.UP)


## Downloaded rocket sections (April's STLs, converted to OBJ and
## decimated from ~239k triangles to ~22k for the Quest budget).
const ROCKET_PARTS := [
	["res://models/imported/rocket_front.obj", -1.55],
	["res://models/imported/rocket_middle.obj", 0.0],
	["res://models/imported/rocket_back.obj", 1.55],
]


func _build_ship() -> void:
	_hull_root = Node3D.new()
	_hull_root.name = "Hull"
	add_child(_hull_root)

	# Prefer the imported rocket; fall back to the primitive craft below if
	# the OBJ files are missing.
	if _build_imported_rocket():
		return

	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.62, 0.66, 0.72)
	hull.metallic = 0.7
	hull.roughness = 0.35

	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.1, 0.13, 0.17)
	trim.metallic = 0.5
	trim.roughness = 0.5

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.1, 0.75, 1.0)
	accent.emission_enabled = true
	accent.emission = Color(0.15, 0.8, 1.0)
	accent.emission_energy_multiplier = 3.0

	# --- fuselage below the player, so the eyeline stays clear ---
	_add_box("Belly", Vector3(1.5, 0.28, 2.9), Vector3(0.0, -0.95, -0.1), hull, _hull_root)
	_add_box("Spine", Vector3(0.9, 0.22, 2.2), Vector3(0.0, -0.72, -0.2), trim, _hull_root)

	# --- nose ahead and low, giving a sense of direction ---
	var nose := CylinderMesh.new()
	nose.top_radius = 0.02
	nose.bottom_radius = 0.42
	nose.height = 1.5
	nose.radial_segments = 28
	nose.rings = 4
	nose.material = hull
	var nose_instance := _add_mesh("Nose", nose, Vector3(0.0, -0.78, -2.1), _hull_root)
	# Cylinders are built along +Y; tip it forward onto -Z.
	nose_instance.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	# --- wings ---
	for side in [-1.0, 1.0]:
		var wing := _add_box(
			"Wing%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.5, 0.1, 1.0),
			Vector3(side * 1.35, -0.9, 0.15),
			hull,
			_hull_root
		)
		wing.rotation_degrees = Vector3(0.0, 0.0, side * -9.0)
		_add_box(
			"WingStripe%s" % ("L" if side < 0.0 else "R"),
			Vector3(1.2, 0.04, 0.16),
			Vector3(side * 1.4, -0.84, 0.15),
			accent,
			_hull_root
		)

		# --- engines with glowing nozzles ---
		var pod := CylinderMesh.new()
		pod.top_radius = 0.2
		pod.bottom_radius = 0.2
		pod.height = 1.0
		pod.radial_segments = 24
		pod.rings = 3
		pod.material = trim
		var pod_instance := _add_mesh(
			"Engine%s" % ("L" if side < 0.0 else "R"),
			pod,
			Vector3(side * 0.8, -0.86, 1.05),
			_hull_root
		)
		pod_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)

		var flame_material := StandardMaterial3D.new()
		flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_material.albedo_color = Color(0.4, 0.9, 1.0)
		flame_material.emission_enabled = true
		flame_material.emission = Color(0.2, 0.7, 1.0)
		flame_material.emission_energy_multiplier = 3.0

		var flame := SphereMesh.new()
		flame.radius = 0.17
		flame.height = 0.34
		flame.radial_segments = 20
		flame.rings = 12
		var flame_instance := _add_mesh(
			"EngineGlow%s" % ("L" if side < 0.0 else "R"),
			flame,
			Vector3(side * 0.8, -0.86, 1.6),
			_hull_root
		)
		flame_instance.set_surface_override_material(0, flame_material)
		flame_instance.scale = Vector3(1.0, 1.0, 1.8)
		_engine_glow.append(flame_instance)

	# --- canopy rail: a thin frame at the edge of vision, not across it ---
	_add_box("CanopyFront", Vector3(1.25, 0.07, 0.07), Vector3(0.0, -0.34, -1.05), trim, _hull_root)
	for side in [-1.0, 1.0]:
		var rail := _add_box(
			"CanopyRail%s" % ("L" if side < 0.0 else "R"),
			Vector3(0.07, 0.07, 1.9),
			Vector3(side * 0.62, -0.34, -0.15),
			trim,
			_hull_root
		)
		rail.rotation_degrees = Vector3(0.0, side * 2.0, 0.0)
	# Console strip glowing just under the forward view.
	_add_box("Console", Vector3(1.1, 0.05, 0.34), Vector3(0.0, -0.52, -0.92), accent, _hull_root)


## Assemble the three downloaded sections nose-to-tail beneath the player.
## Each is normalized independently and then placed along -Z, so a section
## arriving at a different scale from its siblings cannot skew the ship.
func _build_imported_rocket() -> bool:
	var built := false
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.78, 0.8, 0.85)
	body.metallic = 0.55
	body.roughness = 0.4

	for spec in ROCKET_PARTS:
		var path := spec[0] as String
		if not ResourceLoader.exists(path):
			continue
		var mesh := load(path) as Mesh
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = path.get_file().get_basename()
		instance.mesh = mesh
		instance.material_override = body
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hull_root.add_child(instance)

		var bounds := mesh.get_aabb()
		var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		if longest <= 0.0001:
			instance.queue_free()
			continue
		var uniform := 1.7 / longest
		instance.scale = Vector3.ONE * uniform
		# Sit the section below the eyeline and slide it along the fuselage.
		instance.position = Vector3(0.0, -1.05, spec[1] as float) \
			- bounds.get_center() * uniform
		built = true

	if built:
		_add_engine_glows()
		print("SpacecraftVisual|INFO: using imported rocket sections")
	return built


## Engine flares for the imported hull (the primitive build makes its own).
func _add_engine_glows() -> void:
	for side in [-0.42, 0.42]:
		var flame_material := StandardMaterial3D.new()
		flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame_material.albedo_color = Color(0.4, 0.9, 1.0)
		flame_material.emission_enabled = true
		flame_material.emission = Color(0.2, 0.7, 1.0)
		flame_material.emission_energy_multiplier = 3.0

		var flame := SphereMesh.new()
		flame.radius = 0.22
		flame.height = 0.44
		flame.radial_segments = 20
		flame.rings = 12
		var instance := _add_mesh(
			"ImportedEngineGlow%.0f" % (side * 100.0),
			flame,
			Vector3(side, -1.05, 2.5),
			_hull_root
		)
		instance.set_surface_override_material(0, flame_material)
		instance.scale = Vector3(1.0, 1.0, 2.0)
		_engine_glow.append(instance)


func _add_box(
	name_value: String,
	size_value: Vector3,
	position_value: Vector3,
	material: Material,
	parent: Node3D
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	mesh.material = material
	return _add_mesh(name_value, mesh, position_value, parent)


func _add_mesh(
	name_value: String,
	mesh: Mesh,
	position_value: Vector3,
	parent: Node3D
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
