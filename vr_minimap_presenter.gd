extends Node3D
class_name VRMiniMapPresenter

## Renders FlightMiniMap into a head-locked quad in the upper-right view.

const FlightMiniMapScript = preload("res://flight_minimap.gd")

@export_range(128, 1024, 64) var texture_size := 512
@export_range(0.2, 1.0, 0.05) var display_size_meters := 0.48


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.name = "MapViewport"
	viewport.size = Vector2i(texture_size, texture_size)
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var minimap := FlightMiniMapScript.new() as Control
	minimap.position = Vector2.ZERO
	minimap.size = Vector2(texture_size, texture_size)
	viewport.add_child(minimap)

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(display_size_meters, display_size_meters)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = viewport.get_texture()
	quad_mesh.material = material

	var display := MeshInstance3D.new()
	display.name = "MapDisplay"
	display.mesh = quad_mesh
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
