extends Node3D
class_name FlightRewardPoint

## A non-blocking collectible. The visible sphere is deliberately much
## smaller than its collection radius so it reads clearly without filling the
## flight corridor in first-person XR.

signal reward_collected(reward: FlightRewardPoint)

@export_range(0.1, 2.0, 0.05) var visual_radius := 0.55
@export_range(0.5, 10.0, 0.25) var detection_radius := 3.0
@export_range(1, 1000, 1) var reward_value := 100

var is_collected := false

var _visual_root: Node3D
var _elapsed := 0.0
var _phase := 0.0


func _ready() -> void:
	_phase = float(abs(String(name).hash()) % 1000) * 0.006
	_build_visuals()
	set_process(true)


func _process(delta: float) -> void:
	if is_collected or _visual_root == null:
		return
	_elapsed += delta
	_visual_root.position.y = sin(_elapsed * 1.8 + _phase) * 0.12
	_visual_root.rotation.y += delta * 0.8
	var pulse := 1.0 + sin(_elapsed * 2.6 + _phase) * 0.08
	_visual_root.scale = Vector3.ONE * pulse


func collect() -> int:
	if is_collected:
		return 0
	is_collected = true
	visible = false
	set_process(false)
	reward_collected.emit(self)
	return reward_value


func reset_reward() -> void:
	is_collected = false
	visible = true
	_elapsed = 0.0
	set_process(true)
	if _visual_root != null:
		_visual_root.position = Vector3.ZERO
		_visual_root.scale = Vector3.ONE


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "AnimatedVisual"
	add_child(_visual_root)

	var core_material := StandardMaterial3D.new()
	core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_material.albedo_color = Color(0.08, 1.0, 0.3, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.02, 1.0, 0.2)
	core_material.emission_energy_multiplier = 5.0

	var core_mesh := SphereMesh.new()
	core_mesh.radius = visual_radius
	core_mesh.height = visual_radius * 2.0
	core_mesh.radial_segments = 24
	core_mesh.rings = 12
	core_mesh.material = core_material
	_add_mesh("GreenRewardCore", core_mesh)

	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.albedo_color = Color(0.1, 1.0, 0.32, 0.13)
	halo_material.emission_enabled = true
	halo_material.emission = Color(0.02, 1.0, 0.22)
	halo_material.emission_energy_multiplier = 2.5
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = visual_radius * 1.55
	halo_mesh.height = visual_radius * 3.1
	halo_mesh.radial_segments = 20
	halo_mesh.rings = 10
	halo_mesh.material = halo_material
	_add_mesh("GreenRewardHalo", halo_mesh)


func _add_mesh(mesh_name: String, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(instance)
