# =============================================================================
# vr_minimap_presenter.gd — puts the shared FlightMiniMap into the headset.
# Builds, in code: a SubViewport rendering a FlightMiniMap Control to a
# transparent texture, shown on an unshaded quad. The node sits under
# XRCamera3D in main.tscn so the quad is head-locked; no_depth_test keeps it
# readable through world geometry. main.gd toggles it per runtime mode.
# =============================================================================
extends Node3D
class_name VRMiniMapPresenter

## Renders FlightMiniMap into a head-locked quad in the upper-right view.
##
## Squeezing the controller grip expands it: the quad grows and swings in
## toward the centre of view so you can actually read the info cards, then
## eases back when released (see SpacecraftFlightController.is_map_expanded).
## The SubViewport is allocated once at the LARGER resolution and the quad
## is scaled — resizing a render target every frame would be far costlier
## than drawing a few extra pixels.

const FlightMiniMapScript = preload("res://flight_minimap.gd")

@export_range(128, 1024, 64) var texture_size := 640
@export_range(0.2, 1.0, 0.05) var display_size_meters := 0.48
@export_range(0.4, 2.5, 0.05) var expanded_size_meters := 1.15
## Where the quad sits when expanded, relative to the head.
@export var expanded_offset := Vector3(0.0, 0.0, -1.25)
@export_range(1.0, 20.0, 0.5) var transition_speed := 8.0

var _flight: Node3D
var _display: MeshInstance3D
var _quad: QuadMesh
var _resting_offset := Vector3.ZERO


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

	_display = display
	_quad = quad_mesh
	# This node is parented under XRCamera3D, so its own position IS the
	# head-relative resting spot the map returns to.
	_resting_offset = position
	_flight = get_tree().current_scene.get_node_or_null("XROrigin3D") as Node3D
	set_process(true)


func _process(delta: float) -> void:
	if _quad == null or _display == null:
		return
	var expanded := false
	if _flight != null and _flight.has_method("is_map_expanded"):
		expanded = bool(_flight.call("is_map_expanded"))

	var target_size := expanded_size_meters if expanded else display_size_meters
	var target_offset := expanded_offset if expanded else _resting_offset
	var weight := clampf(delta * transition_speed, 0.0, 1.0)
	_quad.size = _quad.size.lerp(Vector2(target_size, target_size), weight)
	position = position.lerp(target_offset, weight)
