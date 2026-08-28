# =============================================================================
# mit_destination.gd — the goal landmark: a stylized MIT Great Dome assembled
# from ~50 Godot primitive meshes in code (cheap on Quest, nothing imported).
# Purely visual: arrival is a distance check in spaceship_flight.gd
# (destination / arrival_radius), NOT a collision against this model. Placed
# in main.tscn at the logical (100, 100) destination. @tool: visible in the
# editor viewport without running the game.
# =============================================================================
@tool
extends Node3D
class_name MITDestination

## Lightweight, original interpretation of MIT's Great Dome built entirely
## from Godot primitives for predictable Quest performance.

## Downloaded Great Dome mesh (April's Printables OBJ, decimated). When it
## is present the procedural dome is replaced by it; the colonnade, plinths
## and asteroid below are still built here.
const DOME_MODEL_PATH := "res://models/imported/mit_dome.obj"

var _model_root: Node3D
var _rock: StandardMaterial3D
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

	# --- Asteroid base ---
	# The campus floats in open space (the floor plane was removed), so a
	# rocky outcrop grounds it visually. Overlapping irregularly scaled
	# spheres read as one asteroid at Quest-friendly cost. Purely visual,
	# like the rest of this model.
	for spec in [
		# [name, radius, position, non-uniform scale]
		# A broad, flat-topped island so the campus sits ON something rather
		# than balancing on a ball, with a tapering keel underneath.
		["IslandTop", 12.5, Vector3(0.0, -2.6, 0.0), Vector3(1.0, 0.3, 0.86)],
		["IslandBody", 10.5, Vector3(0.0, -5.0, 0.0), Vector3(1.0, 0.5, 0.86)],
		["IslandLumpA", 5.0, Vector3(8.6, -4.4, 1.6), Vector3(1.0, 0.62, 1.0)],
		["IslandLumpB", 4.6, Vector3(-8.2, -4.8, -1.7), Vector3(1.1, 0.58, 1.0)],
		["IslandLumpC", 3.6, Vector3(1.4, -5.6, -5.2), Vector3(1.0, 0.7, 1.0)],
		["IslandKeel", 3.4, Vector3(-0.4, -10.5, 0.6), Vector3(0.8, 1.9, 0.8)],
		["IslandKeelTip", 1.8, Vector3(0.2, -14.5, 0.4), Vector3(0.7, 2.1, 0.7)],
	]:
		var rock_radius := spec[1] as float
		var rock_mesh := SphereMesh.new()
		rock_mesh.radius = rock_radius
		rock_mesh.height = rock_radius * 2.0
		rock_mesh.radial_segments = 32
		rock_mesh.rings = 18
		rock_mesh.material = _rock
		var rock := _add_mesh(spec[0] as String, rock_mesh, spec[2] as Vector3)
		rock.scale = spec[3] as Vector3

	# Foundation and main pavilion.
	# Widened to match the real Great Dome's broad neoclassical frontage;
	# the previous footprint read as a narrow tower.
	_add_box("LowerPlinth", Vector3(14.5, 0.5, 6.6), Vector3(0, 0.25, 0), _limestone)
	_add_box("UpperPlinth", Vector3(13.6, 0.4, 6.1), Vector3(0, 0.7, 0), _limestone)
	_add_box("MainHall", Vector3(12.6, 4.9, 5.2), Vector3(0, 3.35, 0.15), _shadow)
	# Flanking wings give the building real width.
	for side in [-1.0, 1.0]:
		_add_box(
			"OuterWing%s" % ("L" if side < 0.0 else "R"),
			Vector3(3.4, 4.1, 5.0),
			Vector3(side * 8.4, 2.95, 0.0),
			_limestone
		)
		_add_box(
			"OuterWingRoof%s" % ("L" if side < 0.0 else "R"),
			Vector3(3.8, 0.34, 5.4),
			Vector3(side * 8.4, 5.2, 0.0),
			_limestone
		)

	# Side walls keep the silhouette solid while the darker central facade
	# gives the colonnade readable depth.
	_add_box("LeftWing", Vector3(0.85, 4.7, 5.2), Vector3(-6.0, 3.35, 0), _limestone)
	_add_box("RightWing", Vector3(0.85, 4.7, 5.2), Vector3(6.0, 3.35, 0), _limestone)
	_add_box("FacadeShadow", Vector3(11.0, 3.8, 0.2), Vector3(0, 3.35, -2.5), _glass)

	# Classical front colonnade.
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.17
	column_mesh.bottom_radius = 0.22
	column_mesh.height = 3.8
	column_mesh.radial_segments = 24
	column_mesh.rings = 0
	column_mesh.material = _limestone
	for index in 16:
		var x := lerpf(-5.4, 5.4, float(index) / 15.0)
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
	_add_box("LowerEntablature", Vector3(12.2, 0.34, 0.7), Vector3(0, 5.35, -2.72), _limestone)
	_add_box("MITBand", Vector3(11.2, 0.34, 0.14), Vector3(0, 5.85, -3.08), _mit_red)
	_add_box("UpperEntablature", Vector3(12.8, 0.46, 0.82), Vector3(0, 6.2, -2.62), _limestone)
	_add_box("Pediment", Vector3(7.4, 0.9, 0.5), Vector3(0, 6.9, -2.6), _limestone)
	_add_box("RoofSlab", Vector3(14.2, 0.4, 6.4), Vector3(0, 6.6, 0), _limestone)
	_add_box("RoofCap", Vector3(13.2, 0.28, 5.7), Vector3(0, 6.92, 0), _limestone)

	# Circular drum and stepped base for the Great Dome.
	_add_cylinder("DrumBase", 3.3, 0.6, Vector3(0, 7.3, 0), _limestone, 48)
	_add_cylinder("DrumShadow", 3.0, 0.55, Vector3(0, 7.85, 0), _glass, 48)
	_add_cylinder("DrumCrown", 3.15, 0.3, Vector3(0, 8.3, 0), _limestone, 48)

	# An oblate sphere buried in the drum reads as a hemispherical dome while
	# remaining much cheaper than a bespoke imported mesh.
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 2.95
	dome_mesh.height = 5.9
	dome_mesh.radial_segments = 56
	dome_mesh.rings = 28
	dome_mesh.material = _dome_copper
	var dome := _add_mesh("GreatDome", dome_mesh, Vector3(0, 8.8, 0))
	dome.scale = Vector3(1.0, 0.62, 1.0)
	if _install_dome_model(dome):
		dome.visible = false

	_add_cylinder("LanternBase", 0.8, 0.24, Vector3(0, 10.6, 0), _limestone, 32)
	_add_cylinder("Lantern", 0.55, 0.5, Vector3(0, 10.98, 0), _glass, 32)
	_add_cylinder("LanternCap", 0.72, 0.18, Vector3(0, 11.34, 0), _beacon, 32)

	# A compact beacon identifies the building as the goal without replacing
	# it with another large collision sphere.
	var beacon_mesh := SphereMesh.new()
	beacon_mesh.radius = 0.22
	beacon_mesh.height = 0.44
	beacon_mesh.radial_segments = 12
	beacon_mesh.rings = 6
	beacon_mesh.material = _beacon
	_add_mesh("GoalBeacon", beacon_mesh, Vector3(0, 11.66, 0))

	# The dome sits at the far corner of the field and was reading as a dim
	# grey lump. A soft white halo plus a wide warm light makes it the
	# landmark it needs to be, and the light is what actually illuminates
	# the stonework — the halo itself is unshaded and lights nothing.
	# A BILLBOARD with a radial gradient, not sphere shells: a shell of
	# constant alpha has no falloff, so it renders as a flat grey disc with
	# a hard rim (it looked like a bubble had been pasted over the dome).
	# The gradient fades to nothing at its edge, so this reads as light.
	var glow_gradient := Gradient.new()
	glow_gradient.set_color(0, Color(1.0, 0.98, 0.92, 0.85))
	glow_gradient.add_point(0.25, Color(0.9, 0.94, 1.0, 0.34))
	glow_gradient.add_point(0.55, Color(0.7, 0.85, 1.0, 0.08))
	glow_gradient.set_color(glow_gradient.get_point_count() - 1, Color(0.6, 0.8, 1.0, 0.0))

	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow_gradient
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(1.0, 0.5)
	glow_texture.width = 128
	glow_texture.height = 128

	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_texture = glow_texture
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_material.disable_receive_shadows = true

	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(46.0, 46.0)
	glow_mesh.material = glow_material

	var glow := _add_mesh("GoalGlow", glow_mesh, Vector3(0, 7.0, 0))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.extra_cull_margin = 46.0

	var goal_light := OmniLight3D.new()
	goal_light.name = "GoalLight"
	goal_light.position = Vector3(0, 9.0, 0)
	goal_light.light_color = Color(1.0, 0.96, 0.92)
	goal_light.light_energy = 6.0
	goal_light.omni_range = 34.0
	goal_light.shadow_enabled = false
	_model_root.add_child(goal_light)

	var beacon_light := OmniLight3D.new()
	beacon_light.name = "BeaconLight"
	beacon_light.position = Vector3(0, 10.9, 0)
	beacon_light.light_color = Color(1.0, 0.25, 0.3)
	beacon_light.light_energy = 3.0
	beacon_light.omni_range = 10.0
	beacon_light.shadow_enabled = false
	_model_root.add_child(beacon_light)


## Swap in the imported dome, normalized to sit on the drum. Returns false
## if the file is missing so the procedural dome stays as the fallback.
func _install_dome_model(reference: MeshInstance3D) -> bool:
	if not ResourceLoader.exists(DOME_MODEL_PATH):
		return false
	var mesh := load(DOME_MODEL_PATH) as Mesh
	if mesh == null:
		push_warning("MITDestination|WARN: dome model failed to load")
		return false

	var instance := MeshInstance3D.new()
	instance.name = "GreatDomeModel"
	instance.mesh = mesh
	instance.material_override = _dome_copper
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model_root.add_child(instance)

	# 3D-printing models are almost always authored Z-up, so the dome
	# arrives lying on its side in Godot's Y-up world. Rotate first, then
	# measure: fitting the raw bounds put the dome on its face.
	var upright := Basis(Vector3.RIGHT, -PI * 0.5)
	var bounds := Transform3D(upright, Vector3.ZERO) * mesh.get_aabb()
	var widest := maxf(bounds.size.x, bounds.size.z)
	if widest <= 0.0001:
		instance.queue_free()
		return false
	var target_width := 6.6
	var uniform := target_width / widest
	instance.transform = Transform3D(
		upright.scaled(Vector3.ONE * uniform),
		Vector3(
			-bounds.get_center().x * uniform,
			8.3 - bounds.position.y * uniform,
			-bounds.get_center().z * uniform
		)
	)
	print("MITDestination|INFO: imported dome fitted to %.1f m" % target_width)
	return true


func _create_materials() -> void:
	# Charcoal asteroid rock, kept rough and dark so the lit building pops.
	_rock = StandardMaterial3D.new()
	_rock.albedo_color = Color(0.21, 0.195, 0.185)
	_rock.roughness = 0.96

	_limestone = StandardMaterial3D.new()
	_limestone.albedo_color = Color(0.9, 0.89, 0.85)
	_limestone.roughness = 0.72

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

	# The real Great Dome is pale limestone/white, not weathered copper.
	# A faint warm emission keeps it readable as the goal at long range
	# without turning it into a coloured blob.
	_dome_copper = StandardMaterial3D.new()
	_dome_copper.albedo_color = Color(0.94, 0.94, 0.92)
	_dome_copper.metallic = 0.0
	_dome_copper.roughness = 0.58
	_dome_copper.emission_enabled = true
	_dome_copper.emission = Color(0.5, 0.52, 0.55)
	_dome_copper.emission_energy_multiplier = 0.35

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
