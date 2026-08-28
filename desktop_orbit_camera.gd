# =============================================================================
# desktop_orbit_camera.gd — mouse/keyboard orbit camera for playing without a
# headset. main.gd makes it `current` only in desktop mode. It orbits
# target_path (the XR rig), so it automatically follows the ship in flight.
# Controls: left-drag orbit, wheel zoom, arrow keys orbit, R reset, Esc quit.
# use_z_up supports map-style scenes whose ground lies on the XY plane.
# =============================================================================
extends Camera3D
class_name DesktopOrbitCamera

## Simple no-headset preview camera. Drag to orbit, scroll to zoom.

@export_node_path("Node3D") var target_path: NodePath
@export_range(1.2, 400.0, 0.1) var distance := 4.0
@export_range(0.1, 2.0, 0.05) var orbit_sensitivity := 0.35
@export_range(0.1, 2.0, 0.05) var keyboard_speed := 0.8
@export var initial_yaw_degrees := 0.0
@export var initial_pitch_degrees := 8.0
@export var use_z_up := false

var _target: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _dragging := false
var _initial_distance := 4.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_initial_distance = distance
	_reset_view()


func _process(delta: float) -> void:
	if not current or _target == null:
		return

	var horizontal := Input.get_axis("ui_left", "ui_right")
	var vertical := Input.get_axis("ui_up", "ui_down")
	if not is_zero_approx(horizontal) or not is_zero_approx(vertical):
		_yaw -= horizontal * keyboard_speed * delta
		_pitch = clampf(_pitch + vertical * keyboard_speed * delta, -1.35, 1.35)
		_update_camera()


func _input(event: InputEvent) -> void:
	if not current:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = maxf(1.2, distance * 0.9)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = minf(400.0, distance * 1.1)
					_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= deg_to_rad(event.relative.x * orbit_sensitivity)
		_pitch = clampf(
			_pitch - deg_to_rad(event.relative.y * orbit_sensitivity),
			-1.35,
			1.35
		)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_reset_view()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _reset_view() -> void:
	_yaw = deg_to_rad(initial_yaw_degrees)
	_pitch = deg_to_rad(initial_pitch_degrees)
	distance = _initial_distance
	_update_camera()


func _update_camera() -> void:
	if _target == null:
		return

	var target_position := _target.global_position
	var offset: Vector3
	var up_direction: Vector3
	if use_z_up:
		# Orbit around the Z axis for scenes whose ground lies on the XY plane.
		offset = Vector3(
			sin(_yaw) * cos(_pitch),
			cos(_yaw) * cos(_pitch),
			sin(_pitch)
		) * distance
		up_direction = Vector3.BACK
	else:
		offset = Vector3(
			sin(_yaw) * cos(_pitch),
			sin(_pitch),
			cos(_yaw) * cos(_pitch)
		) * distance
		up_direction = Vector3.UP
	global_position = target_position + offset
	look_at(target_position, up_direction)
