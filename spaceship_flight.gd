extends XROrigin3D
class_name SpacecraftFlightController

## Moves the XR rig like a spacecraft over the XY play field. The spacecraft
## reference point is locked to a constant Z altitude while room-scale head
## tracking remains available inside the rig.

enum FlightState {
	FLYING,
	CRASHED,
	ARRIVED,
}

const RESTART_BUTTONS: Array[StringName] = [
	&"ax_button",
	&"primary_click",
	&"trigger_click",
]

@export_node_path("XRController3D") var left_controller_path: NodePath
@export_node_path("XRController3D") var right_controller_path: NodePath
@export_node_path("XRCamera3D") var flight_camera_path: NodePath
@export_node_path("Node3D") var obstacles_root_path: NodePath
@export_node_path("Node3D") var black_holes_root_path: NodePath
@export_node_path("Label3D") var vr_status_path: NodePath
@export_node_path("Label") var desktop_status_path: NodePath

@export var start_position := Vector3(0.0, 0.0, 10.0)
@export var destination := Vector3(100.0, 100.0, 10.0)
@export var play_area_min := Vector2(-20.0, -20.0)
@export var play_area_max := Vector2(120.0, 120.0)

@export_group("Gameplay constants")
## C in the planet-gravity equation: acceleration = C * radius^3 / distance^2.
@export_range(0.0, 5.0, 0.05) var gravity_constant_c := 1.2
## a: spacecraft acceleration at full joystick input, in world units/s^2.
@export_range(1.0, 40.0, 0.5) var spacecraft_acceleration_a := 12.0

@export_group("Flight physics")
@export_range(1.0, 40.0, 0.5) var flight_speed := 18.0
@export_range(0.0, 3.0, 0.05) var linear_drag := 0.18
@export_range(0.05, 5.0, 0.05) var spacecraft_radius := 0.25
@export_range(0.5, 20.0, 0.5) var arrival_radius := 3.0
@export_range(0.0, 0.9, 0.05) var joystick_deadzone := 0.15

@export_group("Planet gravity")
## Safety cap only affects pathological positions inside a planet.
@export_range(1.0, 100.0, 1.0) var maximum_gravity_acceleration := 30.0

var state := FlightState.FLYING
var velocity := Vector2.ZERO
var gravity_acceleration := Vector2.ZERO
var crash_message := "COLLISION"

var _left_controller: XRController3D
var _right_controller: XRController3D
var _flight_camera: XRCamera3D
var _obstacles_root: Node3D
var _black_holes_root: Node3D
var _vr_status: Label3D
var _desktop_status: Label
var _restart_was_pressed := false


func _ready() -> void:
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_flight_camera = get_node_or_null(flight_camera_path) as XRCamera3D
	_obstacles_root = get_node_or_null(obstacles_root_path) as Node3D
	_black_holes_root = get_node_or_null(black_holes_root_path) as Node3D
	_vr_status = get_node_or_null(vr_status_path) as Label3D
	_desktop_status = get_node_or_null(desktop_status_path) as Label
	for controller in [_left_controller, _right_controller]:
		if controller != null and not controller.button_pressed.is_connected(_on_controller_button_pressed):
			controller.button_pressed.connect(_on_controller_button_pressed)
	reset_flight()


func _physics_process(delta: float) -> void:
	var restart_pressed := _is_restart_pressed()
	if restart_pressed and not _restart_was_pressed and state != FlightState.FLYING:
		reset_flight()
	_restart_was_pressed = restart_pressed

	if state == FlightState.FLYING:
		var flight_input := _get_flight_input()
		if flight_input.length_squared() > 1.0:
			flight_input = flight_input.normalized()

		gravity_acceleration = _calculate_gravity_acceleration()
		velocity += (flight_input * spacecraft_acceleration_a + gravity_acceleration) * delta
		velocity *= exp(-linear_drag * delta)
		if velocity.length() > flight_speed:
			velocity = velocity.normalized() * flight_speed
		_move_spacecraft(delta)

		_check_obstacle_collisions()
		if state == FlightState.FLYING and get_spacecraft_world_position().distance_to(_logical_to_world(destination)) <= arrival_radius:
			state = FlightState.ARRIVED
			velocity = Vector2.ZERO
			_pulse_controllers(0.45, 0.5)
			print("SpacecraftFlight|INFO: destination reached")

	_update_status()


func reset_flight() -> void:
	state = FlightState.FLYING
	velocity = Vector2.ZERO
	gravity_acceleration = Vector2.ZERO
	crash_message = "COLLISION"
	global_position = _logical_to_world(start_position)
	_update_status()
	print("SpacecraftFlight|INFO: flight reset to %s" % start_position)


func _move_spacecraft(delta: float) -> void:
	var next_position := global_position + Vector3(velocity.x, 0.0, velocity.y) * delta
	if next_position.x < play_area_min.x or next_position.x > play_area_max.x:
		velocity.x = 0.0
	if next_position.z < play_area_min.y or next_position.z > play_area_max.y:
		velocity.y = 0.0
	global_position = Vector3(
		clampf(next_position.x, play_area_min.x, play_area_max.x),
		start_position.z,
		clampf(next_position.z, play_area_min.y, play_area_max.y)
	)


func _calculate_gravity_acceleration() -> Vector2:
	var total := Vector2.ZERO
	var spacecraft_world_position := get_spacecraft_world_position()

	if _obstacles_root != null and not is_zero_approx(gravity_constant_c):
		for child in _obstacles_root.get_children():
			var planet := child as Node3D
			if planet == null:
				continue
			var diameter: Variant = planet.get("target_diameter_meters")
			if diameter == null:
				continue

			var radius := float(diameter) * 0.5
			var to_center := planet.global_position - spacecraft_world_position
			var distance_to_center := maxf(to_center.length(), 0.01)
			var acceleration_magnitude := gravity_constant_c * radius ** 3.0 / distance_to_center ** 2.0
			var direction := to_center / distance_to_center
			total += Vector2(direction.x, direction.z) * acceleration_magnitude

	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("get_gravity_acceleration_at"):
				continue
			var black_hole_acceleration: Variant = black_hole.call(
				"get_gravity_acceleration_at",
				spacecraft_world_position
			)
			if black_hole_acceleration is Vector3:
				total += Vector2(black_hole_acceleration.x, black_hole_acceleration.z)

	if total.length() > maximum_gravity_acceleration:
		total = total.normalized() * maximum_gravity_acceleration
	return total


func _get_flight_input() -> Vector2:
	var stick := Vector2.ZERO
	if _left_controller != null:
		stick = _left_controller.get_vector2(&"primary")
	if stick.length() < joystick_deadzone and _right_controller != null:
		stick = _right_controller.get_vector2(&"primary")

	# OpenXR defines +X as right and +Y as up/forward on a thumbstick.
	var result := _head_relative_stick(stick) if stick.length() >= joystick_deadzone else Vector2.ZERO

	# WASD is a desktop-only convenience for testing without a headset.
	var keyboard := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		keyboard.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		keyboard.x += 1.0
	if Input.is_key_pressed(KEY_S):
		keyboard.y -= 1.0
	if Input.is_key_pressed(KEY_W):
		keyboard.y += 1.0
	if not keyboard.is_zero_approx():
		result = keyboard.normalized()
	return result


func _head_relative_stick(stick: Vector2) -> Vector2:
	if _flight_camera == null:
		return stick

	# Rebuild a level, orthogonal control frame from the headset's live view.
	# This deliberately avoids binding stick-left to world -X: after the user
	# turns their head, stick-left follows the new on-screen left direction.
	var forward := -_flight_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return stick
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var world_direction := right * stick.x + forward * stick.y
	return Vector2(world_direction.x, world_direction.z)


func _check_obstacle_collisions() -> void:
	var spacecraft_world_position := get_spacecraft_world_position()

	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var obstacle := child as Node3D
			if obstacle == null:
				continue
			var diameter: Variant = obstacle.get("target_diameter_meters")
			if diameter == null:
				continue
			var obstacle_radius := float(diameter) * 0.5
			var distance_to_center := spacecraft_world_position.distance_to(obstacle.global_position)
			var collision_distance := spacecraft_radius + obstacle_radius
			if distance_to_center <= collision_distance:
				state = FlightState.CRASHED
				crash_message = "COLLISION · %s" % obstacle.name
				velocity = Vector2.ZERO
				_pulse_controllers(1.0, 0.35)
				print(
					"SpacecraftFlight|INFO: collision with %s at distance %.2f (limit %.2f)"
					% [obstacle.name, distance_to_center, collision_distance]
				)
				return

	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("captures"):
				continue
			if bool(black_hole.call("captures", spacecraft_world_position, spacecraft_radius)):
				state = FlightState.CRASHED
				crash_message = "CAPTURED · %s" % black_hole.name
				velocity = Vector2.ZERO
				_pulse_controllers(1.0, 0.5)
				print("SpacecraftFlight|INFO: captured by %s" % black_hole.name)
				return


func _is_restart_pressed() -> bool:
	if Input.is_key_pressed(KEY_R):
		return true
	for controller in [_left_controller, _right_controller]:
		if controller == null:
			continue
		for action in RESTART_BUTTONS:
			if controller.is_button_pressed(action):
				return true
		if controller.get_float(&"trigger") >= 0.75:
			return true
	return false


func _on_controller_button_pressed(action: StringName) -> void:
	if action in RESTART_BUTTONS and state != FlightState.FLYING:
		reset_flight()


func _pulse_controllers(amplitude: float, duration: float) -> void:
	for controller in [_left_controller, _right_controller]:
		if controller != null:
			controller.trigger_haptic_pulse(&"haptic", 0.0, amplitude, duration, 0.0)


func _update_status() -> void:
	var logical_position := get_flight_coordinates()
	var position_2d := Vector2(logical_position.x, logical_position.y)
	var distance_left := position_2d.distance_to(Vector2(destination.x, destination.y))
	var message: String
	match state:
		FlightState.CRASHED:
			message = "%s\nPress A/X or trigger to restart" % crash_message
		FlightState.ARRIVED:
			message = "DESTINATION REACHED\nPress A/X or trigger to fly again"
		_:
			message = "POS %.1f, %.1f   ALT %.0f\nSPD %.1f   GRAV %.2f\nGOAL %.0f, %.0f   DIST %.1f" % [
				logical_position.x,
				logical_position.y,
				logical_position.z,
				velocity.length(),
				gravity_acceleration.length(),
				destination.x,
				destination.y,
				distance_left,
			]
	if _vr_status != null:
		_vr_status.text = message
	if _desktop_status != null:
		_desktop_status.text = message.replace("\n", "  ·  ")


func get_flight_coordinates() -> Vector3:
	# Logical (X, Y, altitude Z) maps to Godot world (X, height Y, depth Z).
	var spacecraft_world_position := get_spacecraft_world_position()
	return Vector3(spacecraft_world_position.x, spacecraft_world_position.z, start_position.z)


func get_spacecraft_world_position() -> Vector3:
	# Use the viewer's horizontal position so the minimap and collision checks
	# match the first-person view. Altitude remains locked to logical Z=10.
	if _flight_camera != null:
		return Vector3(
			_flight_camera.global_position.x,
			start_position.z,
			_flight_camera.global_position.z
		)
	return Vector3(global_position.x, start_position.z, global_position.z)


func get_view_heading() -> Vector2:
	if _flight_camera == null:
		return Vector2.ZERO
	var forward := -_flight_camera.global_basis.z
	var heading := Vector2(forward.x, forward.z)
	return heading.normalized() if heading.length_squared() > 0.0001 else Vector2.ZERO


func _logical_to_world(logical_position: Vector3) -> Vector3:
	return Vector3(logical_position.x, logical_position.z, logical_position.y)
