extends Node3D

signal runtime_mode_changed(is_xr: bool)

var xr_interface: OpenXRInterface
var is_xr_mode := false

## Preferred refresh rate. Will fallback to what the headset reports
@export var target_refresh_rate := 72.0


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	# OpenXR is requested in project.godot, so Godot initializes it before the
	# main scene. Retrying initialize() here can block desktop startup when no
	# runtime is installed.
	if xr_interface != null and xr_interface.is_initialized():
		_start_xr_mode()
	else:
		_start_desktop_mode()


func _start_xr_mode() -> void:
	is_xr_mode = true
	print("Main|INFO: OpenXR initialised; starting headset mode")

	# XR runtime frame pacing
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_viewport().use_xr = true

	var desktop_camera := get_node_or_null("DesktopCamera") as Camera3D
	if desktop_camera != null:
		desktop_camera.current = false
		desktop_camera.set_process(false)
		desktop_camera.set_process_input(false)

	var desktop_hud := get_node_or_null("DesktopHUD") as CanvasLayer
	if desktop_hud != null:
		desktop_hud.visible = false
	var ship_marker := get_node_or_null("XROrigin3D/ShipMarker") as MeshInstance3D
	if ship_marker != null:
		ship_marker.visible = false
	var flight_hud := get_node_or_null("XROrigin3D/XRCamera3D/FlightHUD") as Label3D
	if flight_hud != null:
		flight_hud.visible = true
	var vr_minimap := get_node_or_null("XROrigin3D/XRCamera3D/VRMiniMap") as Node3D
	if vr_minimap != null:
		vr_minimap.visible = true

	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)
	runtime_mode_changed.emit(true)


func _start_desktop_mode() -> void:
	is_xr_mode = false
	get_viewport().use_xr = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0

	var desktop_camera := get_node_or_null("DesktopCamera") as Camera3D
	if desktop_camera != null:
		desktop_camera.current = true
		desktop_camera.set_process(true)
		desktop_camera.set_process_input(true)

	var desktop_hud := get_node_or_null("DesktopHUD") as CanvasLayer
	if desktop_hud != null:
		desktop_hud.visible = true
	var ship_marker := get_node_or_null("XROrigin3D/ShipMarker") as MeshInstance3D
	if ship_marker != null:
		ship_marker.visible = true
	var flight_hud := get_node_or_null("XROrigin3D/XRCamera3D/FlightHUD") as Label3D
	if flight_hud != null:
		flight_hud.visible = false
	var vr_minimap := get_node_or_null("XROrigin3D/XRCamera3D/VRMiniMap") as Node3D
	if vr_minimap != null:
		vr_minimap.visible = false

	print("Main|INFO: no active headset; starting desktop preview mode")
	runtime_mode_changed.emit(false)


func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("Main|WARN: %s Hz unavailable, runtime offers %s" % [target_refresh_rate, rates])

	# Match physics to the actual rate.
	var actual: float = xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
	print("Main|INFO: running at %s Hz" % Engine.physics_ticks_per_second)
