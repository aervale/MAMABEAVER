@tool
extends Node3D
class_name MITDestination

## Lightweight, original interpretation of MIT's Great Dome built entirely
## from Godot primitives for predictable Quest performance.

var _model_root: Node3D
var _limestone: StandardMaterial3D
var _shadow: StandardMaterial3D
var _glass: StandardMaterial3D
var _mit_red: StandardMaterial3D
var _dome_copper: StandardMaterial3D
var _beacon: StandardMaterial3D


func _ready() -> void:
	_build_model()


func _build_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()

	_create_materials()
	_model_root = Node3D.new()
	_model_root.name = "GeneratedMITModel"
	add_child(_model_root)

	# Foundation and main pavilion.
	_add_box("LowerPlinth", Vector3(8.2, 0.45, 5.8), Vector3(0, 0.225, 0), _limestone)
	_add_box("UpperPlinth", Vector3(7.6, 0.35, 5.3), Vector3(0, 0.625, 0), _limestone)
	_add_box("MainHall", Vector3(7.0, 4.9, 4.6), Vector3(0, 3.25, 0.15), _shadow)

	# Side walls keep the silhouette solid while the darker central facade
	# gives the colonnade readable depth.
	_add_box("LeftWing", Vector3(0.75, 4.7, 4.9), Vector3(-3.15, 3.35, 0), _limestone)
	_add_box("RightWing", Vector3(0.75, 4.7, 4.9), Vector3(3.15, 3.35, 0), _limestone)
	_add_box("FacadeShadow", Vector3(5.6, 3.8, 0.18), Vector3(0, 3.35, -2.23), _glass)

	# Classical front colonnade.
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.17
	column_mesh.bottom_radius = 0.22
	column_mesh.height = 3.8
	column_mesh.radial_segments = 12
	column_mesh.rings = 0
	column_mesh.material = _limestone
	for index in 10:
		var x := lerpf(-2.7, 2.7, float(index) / 9.0)
		_add_mesh("FrontColumn%02d" % index, column_mesh, Vector3(x, 3.15, -2.5))
		_add_box(
			"ColumnBase%02d" % index,
			Vector3(0.42, 0.16, 0.42),
			Vector3(x, 1.22, -2.5),
			_limestone
		)
		_add_box(
			"ColumnCapital%02d" % index,
			Vector3(0.46, 0.18, 0.46),
			Vector3(x, 5.08, -2.5),
			_limestone
		)

	# Entablature, a text-free MIT-red destination band and roof plates.
	_add_box("LowerEntablature", Vector3(6.4, 0.32, 0.65), Vector3(0, 5.35, -2.45), _limestone)
	_add_box("MITBand", Vector3(5.7, 0.32, 0.12), Vector3(0, 5.82, -2.81), _mit_red)
	_add_box("UpperEntablature", Vector3(6.8, 0.42, 0.75), Vector3(0, 6.15, -2.36), _limestone)
	_add_box("RoofSlab", Vector3(8.0, 0.38, 5.7), Vector3(0, 6.55, 0), _limestone)
	_add_box("RoofCap", Vector3(7.2, 0.26, 5.0), Vector3(0, 6.86, 0), _limestone)

	# Circular drum and stepped base for the Great Dome.
	_add_cylinder("DrumBase", 2.45, 0.55, Vector3(0, 7.18, 0), _limestone, 32)
	_add_cylinder("DrumShadow", 2.18, 0.48, Vector3(0, 7.65, 0), _glass, 32)
	_add_cylinder("DrumCrown", 2.32, 0.28, Vector3(0, 8.03, 0), _limestone, 32)

	# An oblate sphere buried in the drum reads as a hemispherical dome while
	# remaining much cheaper than a bespoke imported mesh.
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 2.15
	dome_mesh.height = 4.3
	dome_mesh.radial_segments = 32
	dome_mesh.rings = 12
	dome_mesh.material = _dome_copper
	var dome := _add_mesh("GreatDome", dome_mesh, Vector3(0, 8.55, 0))
	dome.scale = Vector3(1.0, 0.62, 1.0)

	_add_cylinder("LanternBase", 0.62, 0.22, Vector3(0, 9.94, 0), _limestone, 20)
	_add_cylinder("Lantern", 0.42, 0.44, Vector3(0, 10.25, 0), _glass, 20)
	_add_cylinder("LanternCap", 0.57, 0.16, Vector3(0, 10.55, 0), _beacon, 20)

	# A compact beacon identifies the building as the goal without replacing
	# it with another large collision sphere.
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.22
	beacon_mesh.height = 0.44
	beacon_mesh.radial_segments = 12
	beacon_mesh.rings = 6
	beacon_mesh.material = _beacon
	_add_mesh("GoalBeacon", beacon_mesh, Vector3(0, 10.88, 0))

	var goal_light := OmniLight3D.new()
	goal_light.name = "GoalLight"
	goal_light.position = Vector3(0, 10.6, 0)
	goal_light.light_color = Color(0.9, 0.12, 0.18)
	goal_light.light_energy = 3.0
	goal_light.omni_range = 8.0
	goal_light.shadow_enabled = false
	_model_root.add_child(goal_light)


func _create_materials() -> void:
	_limestone = StandardMaterial3D.new()
	_limestone.albedo_color = Color(0.78, 0.75, 0.68)
	_limestone.roughness = 0.78

	_shadow = StandardMaterial3D.new()
	_shadow.albedo_color = Color(0.16, 0.18, 0.2)
	_shadow.roughness = 0.85

	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.025, 0.075, 0.11)
	_glass.metallic = 0.25
	_glass.roughness = 0.28
	_glass.emission_enabled = true
	_glass.emission = Color(0.01, 0.08, 0.14)
	_glass.emission_energy_multiplier = 1.5

	_mit_red = StandardMaterial3D.new()
	_mit_red.albedo_color = Color(0.55, 0.035, 0.08)
	_mit_red.roughness = 0.45
	_mit_red.emission_enabled = true
	_mit_red.emission = Color(0.45, 0.01, 0.035)
	_mit_red.emission_energy_multiplier = 2.2

	# An oxidized-copper dome adds a distinct color landmark without using text.
	_dome_copper = StandardMaterial3D.new()
	_dome_copper.albedo_color = Color(0.08, 0.42, 0.38)
	_dome_copper.metallic = 0.48
	_dome_copper.roughness = 0.42
	_dome_copper.emission_enabled = true
	_dome_copper.emission = Color(0.015, 0.15, 0.13)
	_dome_copper.emission_energy_multiplier = 1.1

	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = Color(1.0, 0.12, 0.18)
	_beacon.roughness = 0.25
	_beacon.emission_enabled = true
	_beacon.emission = Color(1.0, 0.02, 0.06)
	_beacon.emission_energy_multiplier = 6.0


func _add_box(
	name_value: String,
	size_value: Vector3,
	position_value: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	mesh.material = material
	return _add_mesh(name_value, mesh, position_value)


func _add_cylinder(
	name_value: String,
	radius: float,
	height: float,
	position_value: Vector3,
	material: Material,
	segments: int
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	mesh.material = material
	return _add_mesh(name_value, mesh, position_value)


func _add_mesh(
	name_value: String,
	mesh: Mesh,
	position_value: Vector3
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	_model_root.add_child(instance)
	return instance
