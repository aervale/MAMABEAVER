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

@export var texture_size := Vector2i(768, 128)
## Metres wide in front of the player; height follows the texture's ratio.
@export_range(0.3, 2.0, 0.05) var display_width_meters := 0.85


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

	var display := MeshInstance3D.new()
	display.name = "HUDDisplay"
	display.mesh = quad_mesh
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
