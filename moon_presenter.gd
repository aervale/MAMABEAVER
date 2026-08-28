# =============================================================================
# moon_presenter.gd — displays the Sketchfab Moon FBX, and doubles as a
# PLANET: every "PlanetNN" node under MoonExhibit runs this script.
#
# The exported `target_diameter_meters` is not just visual — spacecraft
# flight reads it (duck-typed) for both gravity and collision radius, so the
# sphere you see IS exactly the sphere that kills you. Planet positions and
# sizes follow Map_Coordinates_and_Radius.png.
#
# FBX files arrive with arbitrary source units, so _normalize_model_size()
# rescales and recenters the model by its merged mesh bounds to hit the
# target diameter exactly. @tool: also runs in the editor viewport.
# =============================================================================
@tool
extends Node3D
class_name MoonPresenter

## Loads the external Moon model, applies its PBR textures and normalizes its
## size so FBX unit differences cannot place it outside the visible scene.

@export var model_scene: PackedScene
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
@export_range(0.25, 100.0, 0.05) var target_diameter_meters := 1.6
@export_range(-30.0, 30.0, 0.1) var rotation_speed_degrees := 2.0

var _model_root: Node3D


func _ready() -> void:
	if model_scene == null:
		push_error("MoonPresenter|FATAL: no Moon model scene assigned")
		return

	_model_root = model_scene.instantiate() as Node3D
	if _model_root == null:
		push_error("MoonPresenter|FATAL: Moon model root is not Node3D")
		return

	_model_root.name = "MoonModel"
	add_child(_model_root)
	_apply_pbr_material()
	_normalize_model_size()


func _process(delta: float) -> void:
	# Keep the editor preview still; rotation is only part of the running app.
	if not Engine.is_editor_hint() and _model_root != null:
		_model_root.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)


func _apply_pbr_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo_texture
	material.roughness = 1.0
	material.roughness_texture = roughness_texture
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.normal_enabled = normal_texture != null
	material.normal_texture = normal_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	for mesh_instance in _find_mesh_instances(_model_root):
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)


func _normalize_model_size() -> void:
	var meshes := _find_mesh_instances(_model_root)
	if meshes.is_empty():
		push_error("MoonPresenter|FATAL: Moon scene contains no MeshInstance3D")
		return

	var inverse_root := _model_root.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		var relative_transform := inverse_root * mesh_instance.global_transform
		var mesh_bounds := relative_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true

	var source_diameter := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if source_diameter <= 0.0001:
		push_error("MoonPresenter|FATAL: Moon model has invalid bounds")
		return

	var uniform_scale := target_diameter_meters / source_diameter
	_model_root.scale = Vector3.ONE * uniform_scale
	_model_root.position = -bounds.get_center() * uniform_scale
	print("MoonPresenter|INFO: Moon normalized to %.2f m diameter" % target_diameter_meters)


func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			result.append(node as MeshInstance3D)
		for child in node.get_children():
			pending.append(child)
	return result
