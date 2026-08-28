extends XROrigin3D
class_name SpacecraftFlightController

## Moves the XR rig like a spacecraft over the XY play field. The spacecraft
## reference point is locked to a constant Z altitude while room-scale head
## tracking remains available inside the rig.

enum FlightState {
	FLYING,
	CRASHED,
	ARRIVED,
	WAITING,
}

const START_BUTTONS: Array[StringName] = [
	&"by_button",
]

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
@export_node_path("Node3D") var rewards_root_path: NodePath
@export_node_path("Label3D") var vr_status_path: NodePath
@export_node_path("Label") var desktop_status_path: NodePath

@export var start_position := Vector3(0.0, 0.0, 10.0)
@export var destination := Vector3(100.0, 100.0, 10.0)
@export var play_area_min := Vector2(-20.0, -20.0)
@export var play_area_max := Vector2(120.0, 120.0)

@export_group("Gameplay constants")
## C in the planet-gravity equation: acceleration = C * radius^3 / distance^2.
@export_range(0.0, 20.0, 0.05) var gravity_constant_c := 1.2
## a: spacecraft acceleration at full joystick input, in world units/s^2.
@export_range(1.0, 40.0, 0.5) var spacecraft_acceleration_a := 12.0

@export_group("Flight physics")
@export_range(1.0, 40.0, 0.5) var flight_speed := 18.0
@export_range(0.0, 3.0, 0.05) var linear_drag := 0.18
@export_range(0.05, 5.0, 0.05) var spacecraft_radius := 0.25
@export_range(0.5, 20.0, 0.5) var arrival_radius := 3.0
@export_range(0.0, 0.9, 0.05) var joystick_deadzone := 0.15

@export_group("Fuel")
@export_range(1.0, 1000.0, 1.0) var maximum_fuel := 100.0
@export_range(0.0, 100.0, 0.5) var fuel_burn_per_second := 8.0

@export_group("Score")
@export_range(0, 5000, 10) var maximum_fuel_bonus := 300

@export_group("Planet gravity")
## Safety cap only affects pathological positions inside a planet.
@export_range(1.0, 100.0, 1.0) var maximum_gravity_acceleration := 30.0

@export_group("ODE flow prediction")
## The predictor integrates d(position)/dt = velocity and
## d(velocity)/dt = thrust + gravity(position) - drag * velocity.
@export_range(1.0, 20.0, 0.5) var prediction_horizon_seconds := 8.0
@export_range(0.02, 0.5, 0.01) var prediction_time_step := 0.1
@export_range(0.05, 1.0, 0.05) var prediction_update_interval := 0.1
@export var prediction_holds_current_thrust := true

var state := FlightState.WAITING
var velocity := Vector2.ZERO
var gravity_acceleration := Vector2.ZERO
var crash_message := "COLLISION"
var fuel := 100.0
var rewards_collected := 0
var reward_score := 0
var final_score := 0

## Logical XY points sampled from the RK4 approximation of the ODE flow.
var predicted_flow_points := PackedVector2Array()
var predicted_flow_result := "SAFE"
var predicted_flow_message := ""
var predicted_flow_duration := 0.0

var _left_controller: XRController3D
var _right_controller: XRController3D
var _flight_camera: XRCamera3D
var _obstacles_root: Node3D
var _black_holes_root: Node3D
var _rewards_root: Node3D
var _vr_status: Label3D
var _desktop_status: Label
var _start_was_pressed := false
var _restart_was_pressed := false
var _last_flight_input := Vector2.ZERO
var _prediction_elapsed := 0.0


func _ready() -> void:
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_flight_camera = get_node_or_null(flight_camera_path) as XRCamera3D
	_obstacles_root = get_node_or_null(obstacles_root_path) as Node3D
	_black_holes_root = get_node_or_null(black_holes_root_path) as Node3D
	_rewards_root = get_node_or_null(rewards_root_path) as Node3D
	_vr_status = get_node_or_null(vr_status_path) as Label3D
	_desktop_status = get_node_or_null(desktop_status_path) as Label
	for controller in [_left_controller, _right_controller]:
		if controller != null and not controller.button_pressed.is_connected(_on_controller_button_pressed):
			controller.button_pressed.connect(_on_controller_button_pressed)
	reset_flight()


func _physics_process(delta: float) -> void:
	var start_pressed := _is_start_pressed()
	if start_pressed and not _start_was_pressed and state == FlightState.WAITING:
		start_flight()
	_start_was_pressed = start_pressed

	var restart_pressed := _is_restart_pressed()
	if restart_pressed and not _restart_was_pressed and state != FlightState.FLYING:
		reset_flight()
	_restart_was_pressed = restart_pressed

	if state == FlightState.FLYING:
		var flight_input := _get_flight_input()
		if flight_input.length_squared() > 1.0:
			flight_input = flight_input.normalized()
		flight_input = _consume_fuel_for_input(flight_input, delta)
		_last_flight_input = flight_input

		gravity_acceleration = _calculate_gravity_acceleration()
		velocity += (flight_input * spacecraft_acceleration_a + gravity_acceleration) * delta
		velocity *= exp(-linear_drag * delta)
		if velocity.length() > flight_speed:
			velocity = velocity.normalized() * flight_speed
		_move_spacecraft(delta)

		_check_reward_collection()
		_check_obstacle_collisions()
		if state == FlightState.FLYING and get_spacecraft_world_position().distance_to(_logical_to_world(destination)) <= arrival_radius:
			state = FlightState.ARRIVED
			velocity = Vector2.ZERO
			final_score = _calculate_final_score()
			_pulse_controllers(0.45, 0.5)
			print("SpacecraftFlight|INFO: destination reached; final score=%d" % final_score)
	else:
		_last_flight_input = Vector2.ZERO

	_prediction_elapsed += delta
	if _prediction_elapsed >= prediction_update_interval:
		_prediction_elapsed = 0.0
		_update_predicted_flow()

	_update_status()


func reset_flight() -> void:
	state = FlightState.WAITING
	velocity = Vector2.ZERO
	gravity_acceleration = Vector2.ZERO
	crash_message = "COLLISION"
	fuel = maximum_fuel
	rewards_collected = 0
	reward_score = 0
	final_score = 0
	_reset_rewards()
	_last_flight_input = Vector2.ZERO
	_prediction_elapsed = 0.0
	global_position = _logical_to_world(start_position)
	_update_predicted_flow()
	_update_status()
	print("SpacecraftFlight|INFO: flight reset to %s; waiting for B/Y" % start_position)


func start_flight() -> void:
	if state != FlightState.WAITING:
		return
	state = FlightState.FLYING
	gravity_acceleration = _calculate_gravity_acceleration()
	_prediction_elapsed = 0.0
	_update_predicted_flow()
	_update_status()
	_pulse_controllers(0.25, 0.12)
	print("SpacecraftFlight|INFO: B/Y engaged the gravity field")


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
	return get_total_gravity_at(get_spacecraft_world_position())


func get_total_gravity_at(world_position: Vector3) -> Vector2:
	var total := Vector2.ZERO

	if _obstacles_root != null and not is_zero_approx(gravity_constant_c):
		for child in _obstacles_root.get_children():
			var planet := child as Node3D
			if planet == null:
				continue
			var diameter: Variant = planet.get("target_diameter_meters")
			if diameter == null:
				continue

			var radius := float(diameter) * 0.5
			var to_center := planet.global_position - world_position
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
				world_position
			)
			if black_hole_acceleration is Vector3:
				total += Vector2(black_hole_acceleration.x, black_hole_acceleration.z)

	if total.length() > maximum_gravity_acceleration:
		total = total.normalized() * maximum_gravity_acceleration
	return total


func _consume_fuel_for_input(flight_input: Vector2, delta: float) -> Vector2:
	if flight_input.is_zero_approx() or is_zero_approx(fuel_burn_per_second):
		return flight_input
	if fuel <= 0.0:
		fuel = 0.0
		return Vector2.ZERO

	var requested_fuel := fuel_burn_per_second * flight_input.length() * delta
	if requested_fuel <= fuel:
		fuel -= requested_fuel
		return flight_input

	var available_fraction := fuel / maxf(requested_fuel, 0.0001)
	fuel = 0.0
	return flight_input * available_fraction


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


func _update_predicted_flow() -> void:
	predicted_flow_points = PackedVector2Array()
	predicted_flow_result = "SAFE"
	predicted_flow_message = ""
	predicted_flow_duration = 0.0

	var world_position := get_spacecraft_world_position()
	var ode_state := Vector4(
		world_position.x,
		world_position.z,
		velocity.x,
		velocity.y
	)
	predicted_flow_points.append(Vector2(ode_state.x, ode_state.y))

	if state == FlightState.WAITING:
		predicted_flow_result = "READY"
		predicted_flow_message = "PRESS B/Y"
		return
	if state != FlightState.FLYING:
		predicted_flow_result = "STOPPED"
		predicted_flow_message = crash_message if state == FlightState.CRASHED else "DESTINATION"
		return

	var held_input := _last_flight_input if prediction_holds_current_thrust else Vector2.ZERO
	var predicted_fuel := fuel
	var step_count := maxi(1, int(ceil(prediction_horizon_seconds / prediction_time_step)))
	var destination_world := _logical_to_world(destination)

	for step_index in step_count:
		var effective_input := held_input
		if not effective_input.is_zero_approx() and not is_zero_approx(fuel_burn_per_second):
			var requested_fuel := fuel_burn_per_second * effective_input.length() * prediction_time_step
			if requested_fuel > predicted_fuel:
				var available_fraction := predicted_fuel / maxf(requested_fuel, 0.0001)
				effective_input *= available_fraction
				predicted_fuel = 0.0
			else:
				predicted_fuel -= requested_fuel

		ode_state = _rk4_flow_step(ode_state, effective_input, prediction_time_step)
		ode_state = _constrain_predicted_state(ode_state)
		var predicted_world := Vector3(ode_state.x, start_position.z, ode_state.y)
		predicted_flow_points.append(Vector2(ode_state.x, ode_state.y))
		predicted_flow_duration = float(step_index + 1) * prediction_time_step

		var collision_message := _get_collision_message_at(predicted_world)
		if not collision_message.is_empty():
			predicted_flow_result = "IMPACT"
			predicted_flow_message = collision_message
			break
		if predicted_world.distance_to(destination_world) <= arrival_radius:
			predicted_flow_result = "GOAL"
			predicted_flow_message = "DESTINATION"
			break


func _flow_derivative(ode_state: Vector4, held_input: Vector2) -> Vector4:
	var position_2d := Vector2(ode_state.x, ode_state.y)
	var velocity_2d := Vector2(ode_state.z, ode_state.w)
	var world_position := Vector3(position_2d.x, start_position.z, position_2d.y)
	var acceleration := (
		held_input * spacecraft_acceleration_a
		+ get_total_gravity_at(world_position)
		- velocity_2d * linear_drag
	)
	return Vector4(velocity_2d.x, velocity_2d.y, acceleration.x, acceleration.y)


func _rk4_flow_step(ode_state: Vector4, held_input: Vector2, step_size: float) -> Vector4:
	var k1 := _flow_derivative(ode_state, held_input)
	var k2 := _flow_derivative(ode_state + k1 * (step_size * 0.5), held_input)
	var k3 := _flow_derivative(ode_state + k2 * (step_size * 0.5), held_input)
	var k4 := _flow_derivative(ode_state + k3 * step_size, held_input)
	return ode_state + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (step_size / 6.0)


func _constrain_predicted_state(ode_state: Vector4) -> Vector4:
	var position_2d := Vector2(ode_state.x, ode_state.y)
	var velocity_2d := Vector2(ode_state.z, ode_state.w)
	if velocity_2d.length() > flight_speed:
		velocity_2d = velocity_2d.normalized() * flight_speed

	if position_2d.x < play_area_min.x or position_2d.x > play_area_max.x:
		position_2d.x = clampf(position_2d.x, play_area_min.x, play_area_max.x)
		velocity_2d.x = 0.0
	if position_2d.y < play_area_min.y or position_2d.y > play_area_max.y:
		position_2d.y = clampf(position_2d.y, play_area_min.y, play_area_max.y)
		velocity_2d.y = 0.0
	return Vector4(position_2d.x, position_2d.y, velocity_2d.x, velocity_2d.y)


func _get_collision_message_at(world_position: Vector3) -> String:
	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var obstacle := child as Node3D
			if obstacle == null:
				continue
			var diameter: Variant = obstacle.get("target_diameter_meters")
			if diameter == null:
				continue
			var collision_distance := float(diameter) * 0.5 + spacecraft_radius
			if world_position.distance_to(obstacle.global_position) <= collision_distance:
				return "COLLISION · %s" % obstacle.name

	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("captures"):
				continue
			if bool(black_hole.call("captures", world_position, spacecraft_radius)):
				return "CAPTURED · %s" % black_hole.name
	return ""


func _check_obstacle_collisions() -> void:
	var spacecraft_world_position := get_spacecraft_world_position()
	var collision_message := _get_collision_message_at(spacecraft_world_position)
	if collision_message.is_empty():
		return

	state = FlightState.CRASHED
	crash_message = collision_message
	velocity = Vector2.ZERO
	var captured := collision_message.begins_with("CAPTURED")
	_pulse_controllers(1.0, 0.5 if captured else 0.35)
	print("SpacecraftFlight|INFO: %s" % collision_message)


func _check_reward_collection() -> void:
	if _rewards_root == null:
		return
	var ship_position := get_spacecraft_world_position()
	for child in _rewards_root.get_children():
		var reward := child as Node3D
		if reward == null or not reward.has_method("collect") or bool(reward.get("is_collected")):
			continue
		var detection_radius := float(reward.get("detection_radius"))
		if ship_position.distance_to(reward.global_position) > detection_radius + spacecraft_radius:
			continue
		var points := int(reward.call("collect"))
		if points <= 0:
			continue
		rewards_collected += 1
		reward_score += points
		_pulse_controllers(0.55, 0.16)
		print(
			"SpacecraftFlight|INFO: collected %s (%d/%d, score=%d)"
			% [reward.name, rewards_collected, get_total_reward_count(), reward_score]
		)


func _reset_rewards() -> void:
	if _rewards_root == null:
		return
	for child in _rewards_root.get_children():
		if child.has_method("reset_reward"):
			child.call("reset_reward")


func _calculate_final_score() -> int:
	return reward_score + roundi(get_fuel_ratio() * float(maximum_fuel_bonus))


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


func _is_start_pressed() -> bool:
	if Input.is_key_pressed(KEY_B) or Input.is_key_pressed(KEY_Y):
		return true
	for controller in [_left_controller, _right_controller]:
		if controller == null:
			continue
		for action in START_BUTTONS:
			if controller.is_button_pressed(action):
				return true
	return false


func _on_controller_button_pressed(action: StringName) -> void:
	if action in START_BUTTONS and state == FlightState.WAITING:
		start_flight()
	elif action in RESTART_BUTTONS and state != FlightState.FLYING:
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
		FlightState.WAITING:
			message = "GRAVITY FIELD DISENGAGED\nREWARD %d/%d · Press B or Y to start" % [
				rewards_collected,
				get_total_reward_count(),
			]
		FlightState.CRASHED:
			message = "%s\nREWARD %d/%d · Press A/X or trigger to restart" % [
				crash_message,
				rewards_collected,
				get_total_reward_count(),
			]
		FlightState.ARRIVED:
			message = "DESTINATION REACHED · SCORE %d\nREWARD %d/%d · FUEL %.0f/%.0f\nPress A/X or trigger to fly again" % [
				final_score,
				rewards_collected,
				get_total_reward_count(),
				fuel,
				maximum_fuel,
			]
		_:
			message = "POS %.1f, %.1f   ALT %.0f\nSPD %.1f   GRAV %.2f\nFUEL %.0f/%.0f   REWARD %d/%d   SCORE %d\nGOAL %.0f, %.0f   DIST %.1f" % [
				logical_position.x,
				logical_position.y,
				logical_position.z,
				velocity.length(),
				gravity_acceleration.length(),
				fuel,
				maximum_fuel,
				rewards_collected,
				get_total_reward_count(),
				reward_score,
				destination.x,
				destination.y,
				distance_left,
			]
	if _vr_status != null:
		_vr_status.text = message
	if _desktop_status != null:
		_desktop_status.text = message


func get_fuel_ratio() -> float:
	return clampf(fuel / maxf(maximum_fuel, 0.0001), 0.0, 1.0)


func get_total_reward_count() -> int:
	return _rewards_root.get_child_count() if _rewards_root != null else 0


func get_rewards_collected() -> int:
	return rewards_collected


func get_display_score() -> int:
	return final_score if state == FlightState.ARRIVED else reward_score


func is_waiting_to_start() -> bool:
	return state == FlightState.WAITING


func get_predicted_flow_points() -> PackedVector2Array:
	return predicted_flow_points


func get_predicted_flow_result() -> String:
	return predicted_flow_result


func get_predicted_flow_message() -> String:
	return predicted_flow_message


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
