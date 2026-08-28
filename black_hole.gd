# =============================================================================
# black_hole.gd — a gameplay black hole (the BlackHoleNN nodes under
# BlackHoleExhibit in main.tscn).
#
# PHYSICS CONTRACT consumed by spaceship_flight.gd via duck typing:
#   get_gravity_acceleration_at(world_pos) -> Vector3
#       Softened inverse-square pull a = mu / (d^2 + softening^2), capped at
#       maximum_acceleration so a grazing pass stays playable instead of
#       slingshotting to infinity.
#   captures(world_pos, body_radius) -> bool
#       True inside capture_radius (+ ship radius) => instant "CAPTURED" loss.
#
# VISUALS are built entirely in code at _ready() (nothing hand-placed):
# a procedural event horizon + shader accretion disk + photon rings, or an
# imported model if one is assigned (normalized to visual_diameter_meters,
# with its tiny embedded "Planet" mesh hidden).
#
# On top of EITHER sits the lensing shell (black_hole_lens.gdshader): a
# large transparent sphere that re-samples the screen to bend the stars,
# planets and nebula behind it around the hole. That distortion is the
# signature of the object and cannot come from a model — a mesh can only
# carry a painted-on swirl, whereas the shader bends whatever is genuinely
# behind it this frame. Set enable_lensing = false to drop it (and its one
# screen-texture read per covered pixel) on weaker hardware.
# @tool makes this run in the editor so the scene viewport shows it too.
# NOTE: the visuals are purely decorative; only capture_radius and the field
# parameters affect gameplay.
# =============================================================================
@tool
extends Node3D
class_name GameplayBlackHole

## A gameplay black hole using a softened inverse-square field:
## acceleration = mu / (distance^2 + softening^2).

const DISK_SHADER := preload("res://black_hole_disk.gdshader")
const LENS_SHADER := preload("res://black_hole_lens.gdshader")

@export_group("Imported model")
@export var model_scene: PackedScene
@export_range(4.0, 40.0, 0.5) var visual_diameter_meters := 18.0
@export var hide_embedded_planet := true

@export_group("Physics")
@export_range(0.0, 2000.0, 10.0) var gravitational_parameter_mu := 500.0
@export_range(0.1, 10.0, 0.1) var gravity_softening_length := 3.0
@export_range(0.5, 10.0, 0.25) var capture_radius := 3.0
@export_range(1.0, 100.0, 1.0) var maximum_acceleration := 25.0

@export_group("Gravitational lensing")
@export var enable_lensing := true
## Shell size as a multiple of capture_radius; also how far the smear reaches.
@export_range(2.0, 12.0, 0.5) var lens_falloff_radii := 3.5
@export_range(0.0, 3.0, 0.05) var lens_strength := 1.0

@export_group("Visuals")
@export_range(4.0, 20.0, 0.5) var accretion_disk_radius := 9.0
@export_range(-90.0, 90.0, 1.0) var disk_tilt_degrees := 24.0
@export_range(-45.0, 45.0, 1.0) var disk_roll_degrees := -12.0
@export_range(-30.0, 30.0, 0.5) var disk_rotation_degrees_per_second := 5.0

var _generated_root: Node3D
var _disk_root: Node3D
var _imported_model_root: Node3D


func _ready() -> void:
	_build_visuals()
	set_process(true)


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _disk_root != null:
		_disk_root.rotate_y(deg_to_rad(disk_rotation_degrees_per_second) * delta)


func get_gravity_acceleration_at(world_position: Vector3) -> Vector3:
	var to_center := global_position - world_position
	var distance := to_center.length()
	if distance <= 0.0001:
		return Vector3.ZERO
	var denominator := distance * distance + gravity_softening_length * gravity_softening_length
	var magnitude := gravitational_parameter_mu / denominator
	magnitude = minf(magnitude, maximum_acceleration)
	return to_center / distance * magnitude


func captures(world_position: Vector3, body_radius: float = 0.0) -> bool:
	return world_position.distance_to(global_position) <= capture_radius + body_radius


func _build_visuals() -> void:
	if _generated_root != null and is_instance_valid(_generated_root):
		_generated_root.queue_free()

	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedBlackHole"
	add_child(_generated_root)

	_disk_root = Node3D.new()
	_disk_root.name = "RotatingVisualRoot"
	_disk_root.rotation_degrees = Vector3(disk_tilt_degrees, 0.0, disk_roll_degrees)
	_generated_root.add_child(_disk_root)

	if model_scene != null:
		_build_imported_visual()
	else:
		_build_procedural_visual()

	if enable_lensing:
		_build_lens_shell()

	var glow := OmniLight3D.new()
	glow.name = "AccretionGlow"
	glow.light_color = Color(1.0, 0.28, 0.06)
	glow.light_energy = 2.5
	glow.omni_range = accretion_disk_radius * 1.6
	glow.shadow_enabled = false
	_generated_root.add_child(glow)


## Transparent sphere carrying the screen-space lens. It is sized to the
## point where the distortion has faded out, so its own geometry is never
## visible; it is added OUTSIDE _disk_root so the tilted, rotating disk does
## not drag the lens around with it.
func _build_lens_shell() -> void:
	var material := ShaderMaterial.new()
	material.shader = LENS_SHADER
	material.set_shader_parameter("shadow_world_radius", capture_radius)
	material.set_shader_parameter("shell_world_radius", capture_radius * lens_falloff_radii)
	material.set_shader_parameter("lens_falloff_radii", lens_falloff_radii)
	material.set_shader_parameter("lens_strength", lens_strength)
	# Draw after the accretion disk so the disk is itself lensed.
	material.render_priority = 4

	var mesh := SphereMesh.new()
	mesh.radius = capture_radius * lens_falloff_radii
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = material

	var shell := _add_mesh("LensShell", mesh, Vector3.ZERO, _generated_root)
	# Never cull it early: the shell is big and usually straddles the frustum.
	shell.extra_cull_margin = mesh.radius


func _build_imported_visual() -> void:
	_imported_model_root = model_scene.instantiate() as Node3D
	if _imported_model_root == null:
		push_error("GameplayBlackHole|FATAL: imported model root is not Node3D")
		_build_procedural_visual()
		return
	_imported_model_root.name = "ImportedSketchfabBlackHole"
	_disk_root.add_child(_imported_model_root)

	var meshes: Array[MeshInstance3D] = []
	var pending: Array[Node] = [_imported_model_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var is_embedded_planet := String(node.name).to_lower() == "planet"
		if is_embedded_planet and node is Node3D and hide_embedded_planet:
			(node as Node3D).visible = false
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			meshes.append(node as MeshInstance3D)
		for child in node.get_children():
			pending.append(child)

	if meshes.is_empty():
		push_error("GameplayBlackHole|FATAL: imported scene contains no visible meshes")
		return

	var inverse_root := _imported_model_root.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		var relative_transform := inverse_root * mesh_instance.global_transform
		var mesh_bounds := relative_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true

	var source_diameter := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if source_diameter <= 0.0001:
		push_error("GameplayBlackHole|FATAL: imported model has invalid bounds")
		return
	var uniform_scale := visual_diameter_meters / source_diameter
	_imported_model_root.scale = Vector3.ONE * uniform_scale
	_imported_model_root.position = -bounds.get_center() * uniform_scale
	print("GameplayBlackHole|INFO: imported model normalized to %.2f m" % visual_diameter_meters)


func _build_procedural_visual() -> void:

	var horizon_material := StandardMaterial3D.new()
	horizon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	horizon_material.albedo_color = Color(0.0, 0.0, 0.002, 1.0)
	horizon_material.roughness = 1.0

	var horizon_mesh := SphereMesh.new()
	horizon_mesh.radius = capture_radius
	horizon_mesh.height = capture_radius * 2.0
	horizon_mesh.radial_segments = 32
	horizon_mesh.rings = 16
	horizon_mesh.material = horizon_material
	_add_mesh("EventHorizon", horizon_mesh, Vector3.ZERO, _generated_root)

	# NOTE: an earlier build wrapped the horizon in a big translucent purple
	# "corona" sphere. It swamped the disk and the lensing and just read as
	# a flat purple ball, so the glow now comes from the photon rings and
	# the lens shell's Einstein ring instead.

	var disk_material := ShaderMaterial.new()
	disk_material.shader = DISK_SHADER
	disk_material.render_priority = 2
	var disk_mesh := PlaneMesh.new()
	disk_mesh.size = Vector2(accretion_disk_radius * 2.0, accretion_disk_radius * 2.0)
	disk_mesh.material = disk_material
	_add_mesh("AnimatedAccretionDisk", disk_mesh, Vector3.ZERO, _disk_root)

	var photon_material := StandardMaterial3D.new()
	photon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	photon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	photon_material.albedo_color = Color(1.0, 0.56, 0.16, 0.82)
	photon_material.emission_enabled = true
	photon_material.emission = Color(1.0, 0.24, 0.035)
	photon_material.emission_energy_multiplier = 5.0
	photon_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_add_torus(
		"InnerPhotonRing",
		capture_radius * 1.08,
		capture_radius * 1.22,
		photon_material
	)
	_add_torus(
		"OuterPhotonRing",
		accretion_disk_radius * 0.62,
		accretion_disk_radius * 0.66,
		photon_material
	)

func _add_torus(
	name_value: String,
	inner_radius: float,
	outer_radius: float,
	material: Material
) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 48
	mesh.ring_segments = 10
	mesh.material = material
	_add_mesh(name_value, mesh, Vector3.ZERO, _disk_root)


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
