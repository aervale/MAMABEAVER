# =============================================================================
# vr_hud_presenter.gd — puts FlightHUDGraphic into the headset, replacing the
# old FlightHUD Label3D (three lines of numbers across the bottom of view).
#
# Same trick as vr_minimap_presenter.gd: render the Control into a
# SubViewport and show that texture on an unshaded, head-locked quad. It
# sits low in the field of view, wide and short, like a cockpit strip.
# no_depth_test keeps it readable through planets.
#
# main.gd shows this in headset mode and hides it on desktop, where the
# CanvasLayer HUD already carries the same information.
# =============================================================================
extends Node3D
class_name VRHUDPresenter

const FlightHUDScript = preload("res://flight_hud_graphic.gd")
const MissionResultsScript = preload("res://mission_results.gd")

@export var texture_size := Vector2i(1024, 160)
## Metres wide in front of the player; height follows the texture's ratio.
@export_range(0.3, 2.0, 0.05) var display_width_meters := 0.95

var _hud_display: MeshInstance3D
var _results_display: MeshInstance3D
var _results_viewport: SubViewport
var _results_control: MissionResults


func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.name = "HUDViewport"
	viewport.size = texture_size
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var hud := FlightHUDScript.new() as Control
	hud.position = Vector2.ZERO
	hud.size = Vector2(texture_size)
	viewport.add_child(hud)

	var aspect := float(texture_size.y) / float(texture_size.x)
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(display_width_meters, display_width_meters * aspect)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = viewport.get_texture()
	quad_mesh.material = material

	_hud_display = MeshInstance3D.new()
	_hud_display.name = "HUDDisplay"
	_hud_display.mesh = quad_mesh
	_hud_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hud_display)
	_build_results_display()


func _process(_delta: float) -> void:
	if _results_control == null:
		return
	var showing := _results_control.is_showing()
	_hud_display.visible = not showing
	_results_display.visible = showing
	_results_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if showing else SubViewport.UPDATE_DISABLED
	)


## A larger central quad appears only on victory. Keeping its SubViewport
## disabled during play avoids spending Quest GPU time on an invisible panel.
func _build_results_display() -> void:
	var result_size := Vector2i(1024, 720)
	_results_viewport = SubViewport.new()
	_results_viewport.name = "ResultsViewport"
	_results_viewport.size = result_size
	_results_viewport.transparent_bg = true
	_results_viewport.gui_disable_input = true
	_results_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_results_viewport)

	_results_control = MissionResultsScript.new() as MissionResults
	_results_control.name = "MissionResults"
	_results_control.position = Vector2.ZERO
	_results_control.size = Vector2(result_size)
	_results_viewport.add_child(_results_control)

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(1.35, 1.35 * float(result_size.y) / float(result_size.x))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = _results_viewport.get_texture()
	material.render_priority = 100
	quad_mesh.material = material

	_results_display = MeshInstance3D.new()
	_results_display.name = "ResultsDisplay"
	_results_display.position = Vector3(0.0, 0.34, -0.02)
	_results_display.mesh = quad_mesh
	_results_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_results_display.visible = false
	add_child(_results_display)
