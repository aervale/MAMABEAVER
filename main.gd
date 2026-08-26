extends Node3D
var xr_interface: OpenXRInterface

## Preferred refresh rate. Will fallback to what the headset reports
@export var target_refresh_rate := 72.0

## _ready() is called when the node is initialize
func _ready() -> void:
	print(":3")
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface == null:
		push_error("Main|FATAL: OpenXR interface not found. Check Project Settings -> XR")
		return

	if not xr_interface.is_initialized() and not xr_interface.initialize():
		push_error("Main|FATAL: OpenXR failed to initialise, headset connected?")
		return

	print("Main|INFO: OpenXR initialised")

	# XR runtime frame pacing
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	get_viewport().use_xr = true

	xr_interface.session_begun.connect(_on_session_begun)


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
