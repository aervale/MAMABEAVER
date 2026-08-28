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
const StartGuideScript = preload("res://start_controls_guide.gd")

@export var texture_size := Vector2i(1024, 160)
## Metres wide in front of the player; height follows the texture's ratio.
@export_range(0.3, 2.0, 0.05) var display_width_meters := 0.95

var _hud_display: MeshInstance3D
var _results_display: MeshInstance3D
var _results_viewport: SubViewport
var _results_control: MissionResults
var _guide_display: MeshInstance3D
var _guide_viewport: SubViewport
var _guide_control: StartControlsGuide
var _guide_was_showing := false


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
	_build_start_guide()


func _process(_delta: float) -> void:
	if _results_control == null or _guide_control == null:
		return
	var results_showing := _results_control.is_showing()
	_results_display.visible = results_showing
	_results_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if results_showing else SubViewport.UPDATE_DISABLED
	)
	var guide_showing := _guide_control.is_showing() and not results_showing
	# On the start screen the large centred manual replaces the narrow status
	# strip, avoiding overlapping text and improving headset readability.
	_hud_display.visible = not results_showing and not guide_showing
	_guide_display.visible = guide_showing
	if guide_showing and not _guide_was_showing:
		_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_guide_was_showing = guide_showing


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


## English instructions sit directly in the centre view on the start screen.
## The texture is static and updates once per appearance, keeping its normal
## in-game Quest rendering cost at zero.
func _build_start_guide() -> void:
	var guide_size := Vector2i(600, 760)
	_guide_viewport = SubViewport.new()
	_guide_viewport.name = "GuideViewport"
	_guide_viewport.size = guide_size
	_guide_viewport.transparent_bg = true
	_guide_viewport.gui_disable_input = true
	_guide_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_guide_viewport)

	_guide_control = StartGuideScript.new() as StartControlsGuide
	_guide_control.name = "StartControlsGuide"
	_guide_control.position = Vector2.ZERO
	_guide_control.size = Vector2(guide_size)
	_guide_viewport.add_child(_guide_control)

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.78, 0.78 * float(guide_size.y) / float(guide_size.x))
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = _guide_viewport.get_texture()
	material.render_priority = 80
	quad_mesh.material = material

	_guide_display = MeshInstance3D.new()
	_guide_display.name = "StartGuideDisplay"
	_guide_display.position = Vector3(0.0, 0.34, -0.04)
	_guide_display.mesh = quad_mesh
	_guide_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide_display)
	_guide_was_showing = true
