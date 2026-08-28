# =============================================================================
# spaceship_flight.gd — THE core gameplay script. Attached to XROrigin3D in
# main.tscn, so "moving the spacecraft" literally means flying the whole XR
# rig (player head + controllers) through the world.
#
# COORDINATE SYSTEM (important — this trips everyone up):
#   Gameplay is 2D. Logical coordinates are (X, Y, altitude Z), matching
#   Map_Coordinates_and_Radius.png. Godot worlds are Y-up, so:
#       logical X            -> world X
#       logical Y            -> world Z (depth)
#       logical Z (altitude) -> world Y (height, LOCKED to start_position.z)
#   _logical_to_world() performs that swap. The ship never changes altitude.
#
# WHO IS "THE SHIP": the XROrigin3D itself. The tracked camera can move a
# little inside that rig without changing the physics anchor. Collision,
# arrival, surface walking, the visible hull and the minimap therefore agree
# on one position instead of slowly separating through room-scale offsets.
#
# DISCOVERING HAZARDS (duck typing — no groups, no signals):
#   * Planets = children of MoonExhibit exposing a `target_diameter_meters`
#     property (moon_presenter.gd does). Gravity uses the hackathon formula
#     a = C * r^3 / d^2 toward the planet center; collision is sphere-vs-point
#     using that same diameter.
#   * Black holes = children of BlackHoleExhibit implementing
#     get_gravity_acceleration_at(pos) and captures(pos, radius)
#     (black_hole.gd does). Their field is softened: a = mu / (d^2 + s^2).
#   To add a new hazard type, match either contract — no edits needed here.
#
# INPUT: left thumbstick (falls back to right), HEAD-RELATIVE — stick-forward
# is wherever you are looking, flattened to the horizon. WASD is a
# desktop-testing convenience. B/Y engages the gravity field (starts
# flight) and, while LANDED, launches you off the planet. TRIGGER fires a
# magic bolt (only while LANDED); it is deliberately NOT a restart button
# anymore — restart is A/X or the R key. Desktop fire = right-click (left
# is the orbit drag). Thrust burns FUEL (fuel_burn_per_second, scaled by
# stick deflection); an empty tank leaves only gravity, drag, and momentum.
#
# STATE MACHINE: WAITING (spawn/reset; gravity disengaged so you can't
# drift into a planet while reading the HUD) -> FLYING on B/Y -> then:
#   * touch a planet SLOWER than landing_speed_threshold -> LANDED: snapped
#     to the surface, tank refueled, trigger armed. While landed you walk
#     the planet's FULL SPHERE (the altitude lock is lifted only in this
#     state), and B/Y launches you back into the flight plane at a point
#     clear of the planet, with a short grace window so you don't
#     immediately re-collide.
#   * approaching a planet faster than you could land triggers a loud HUD
#     warning (see _update_impact_warning) before you hit it.
#   * touch a planet faster, or any black hole capture -> CRASHED.
#   * reach MIT: cargo is BANKED (run continues); ARRIVED (win) only when
#     every beaver is delivered — see beaver_director.gd. Without a
#     BeaverExhibit in the scene, arrival = win, like the pre-beaver game.
# End states zero velocity, pulse haptics, and wait for restart (A/X, R).
#
# BEAVER COLLECTION: while LANDED, trigger/right-click fires a MagicBolt
# (see magic_bolt.gd) curved by this controller's own gravity field. Bolt
# hits hand beavers to the BeaverDirector, which tractors them aboard.
#
# FLOW PREDICTION: a few times per second, _update_predicted_flow() runs an
# RK4 integration of the flight ODE (thrust held + gravity - drag) for
# prediction_horizon_seconds ahead and publishes the sampled logical-XY path
# plus a verdict (SAFE / IMPACT / GOAL / ...). The minimap draws it as a
# course-projection line. Tools: tools/validate_flow_feature.gd.
# =============================================================================
extends XROrigin3D
class_name SpacecraftFlightController

const MagicBoltScript = preload("res://magic_bolt.gd")
const SurfaceDustScript = preload("res://surface_dust.gd")
const DepositEffectScript = preload("res://deposit_effect.gd")

## Moves the XR rig like a spacecraft over the XY play field. The spacecraft
## reference point is locked to a constant Z altitude while room-scale head
## tracking remains available inside the rig.

enum FlightState {
	FLYING,
	CRASHED,
	ARRIVED,
	WAITING,
	# Appended last on purpose: the minimap colors states by enum ordinal.
	LANDED,
}

const START_BUTTONS: Array[StringName] = [
	&"by_button",
]

# Trigger is deliberately NOT here anymore: it fires magic bolts now.
const RESTART_BUTTONS: Array[StringName] = [
	&"ax_button",
	&"primary_click",
]

const FIRE_BUTTONS: Array[StringName] = [
	&"trigger_click",
]

## The grip/squeeze — a different finger from the trigger, so expanding the
## map never fights firing. In the action map "grip" is the analog value of
## /input/squeeze/value; "grip_click" is its digital sibling.
const MAP_EXPAND_BUTTONS: Array[StringName] = [
	&"grip_click",
]

@export_node_path("XRController3D") var left_controller_path: NodePath
@export_node_path("XRController3D") var right_controller_path: NodePath
@export_node_path("XRCamera3D") var flight_camera_path: NodePath
@export_node_path("Node3D") var obstacles_root_path: NodePath
@export_node_path("Node3D") var black_holes_root_path: NodePath
@export_node_path("Label3D") var vr_status_path: NodePath
@export_node_path("Label") var desktop_status_path: NodePath

@export var start_position := Vector3(0.0, 0.0, 10.0)
@export var destination := Vector3(200.0, 200.0, 10.0)
@export var play_area_min := Vector2(-20.0, -20.0)
@export var play_area_max := Vector2(220.0, 220.0)

@export_group("Gameplay constants")
## C in the planet-gravity equation: acceleration = C * radius^3 / distance^2.
@export_range(0.0, 5.0, 0.05) var gravity_constant_c := 1.2
## a: spacecraft acceleration at full joystick input, in world units/s^2.
@export_range(1.0, 40.0, 0.5) var spacecraft_acceleration_a := 12.0

@export_group("Flight physics")
@export_range(1.0, 40.0, 0.5) var flight_speed := 18.0
@export_range(0.0, 3.0, 0.05) var linear_drag := 0.18
@export_range(0.05, 5.0, 0.05) var spacecraft_radius := 0.25
@export_range(0.5, 20.0, 0.5) var arrival_radius := 5.0
@export_range(0.0, 0.9, 0.05) var joystick_deadzone := 0.15

@export_group("Fuel")
@export_range(1.0, 1000.0, 1.0) var maximum_fuel := 100.0
@export_range(0.0, 100.0, 0.5) var fuel_burn_per_second := 8.0

@export_group("Landing & beavers")
## Touch a planet below this speed to land instead of crash.
@export_range(0.5, 15.0, 0.5) var landing_speed_threshold := 8.0
@export_range(1.0, 15.0, 0.5) var takeoff_speed := 5.0
## Extra horizontal distance beyond the planet collision cross-section.
## A generous gap prevents strong gravity from pulling the ship straight
## back into the surface as soon as the takeoff grace period ends.
@export_range(0.5, 10.0, 0.25) var takeoff_clearance_margin := 3.0
## After takeoff, the departed planet is ignored this long (no re-collide).
@export_range(0.1, 3.0, 0.05) var takeoff_grace_seconds := 0.75
@export_range(5.0, 60.0, 1.0) var bolt_speed := 36.0
@export_range(0.5, 5.0, 0.1) var bolt_hit_radius := 2.0
## How much of the gravity field bends a bolt. Low = straight shots that
## still visibly curve near planets; 1.0 made close-range aiming a lottery.
## 0 = perfectly straight shots. Gravity-curved bolts made close-range
## aiming feel arbitrary, so the field no longer touches them.
@export_range(0.0, 1.0, 0.05) var bolt_gravity_scale := 0.0
@export_range(1, 8, 1) var max_live_bolts := 3
## Speed you stroll around a planet's surface while landed.
## Deliberately unhurried: a brisk stroll around a small sphere swings the
## horizon fast enough to be unpleasant in a headset.
@export_range(0.5, 12.0, 0.5) var surface_walk_speed := 2.2
## How long the touchdown glide takes. Snapping straight onto the surface
## was the disorienting part of landing, so the ship now eases in.
@export_range(0.0, 4.0, 0.1) var landing_animation_seconds := 1.4
## Warn when a planet is this many seconds away at the current closing speed.
@export_range(0.5, 8.0, 0.25) var impact_warning_seconds := 2.5
@export_node_path("Node3D") var beaver_director_path: NodePath

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
var _vr_status: Label3D
var _desktop_status: Label
var _start_was_pressed := false
var _restart_was_pressed := false
var _fire_was_pressed := [false, false]
var _landed_planet: Node3D = null
var _takeoff_grace := 0.0
var _beaver_director: Node3D = null
var _live_bolts: Array[Node3D] = []
var _inside_arrival_zone := false
var _banner_text := ""
var _banner_time_left := 0.0
var _walk_dust_cooldown := 0.0
## Last reliable forward tangent while walking. Looking directly into or out
## of the surface collapses the projected view direction; retaining this
## tangent prevents the controls from flipping abruptly near that singularity.
var _surface_walk_forward := Vector3.ZERO
var _impact_warning := ""
var _warning_haptic_cooldown := 0.0
var _landing_from := Vector3.ZERO
var _landing_to := Vector3.ZERO
var _landing_elapsed := -1.0
var _map_expanded := false
var _last_flight_input := Vector2.ZERO
var _prediction_elapsed := 0.0


func _ready() -> void:
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_flight_camera = get_node_or_null(flight_camera_path) as XRCamera3D
	_obstacles_root = get_node_or_null(obstacles_root_path) as Node3D
	_black_holes_root = get_node_or_null(black_holes_root_path) as Node3D
	_vr_status = get_node_or_null(vr_status_path) as Label3D
	_desktop_status = get_node_or_null(desktop_status_path) as Label
	_beaver_director = get_node_or_null(beaver_director_path) as Node3D
	for controller in [_left_controller, _right_controller]:
		if controller != null and not controller.button_pressed.is_connected(_on_controller_button_pressed):
			controller.button_pressed.connect(_on_controller_button_pressed)
	reset_flight()


func _physics_process(delta: float) -> void:
	var start_pressed := _is_start_pressed()
	if start_pressed and not _start_was_pressed:
		if state == FlightState.WAITING:
			start_flight()
		elif state == FlightState.LANDED:
			take_off()
	_start_was_pressed = start_pressed

	# Restart only from true end states — NOT from LANDED, or players would
	# wipe their run reaching for the wrong button on a planet.
	var restart_pressed := _is_restart_pressed()
	if (
		restart_pressed and not _restart_was_pressed
		and (state == FlightState.CRASHED or state == FlightState.ARRIVED)
	):
		reset_flight()
	_restart_was_pressed = restart_pressed

	_poll_vr_fire()
	_poll_map_expand()
	_update_impact_warning(delta)
	if _takeoff_grace > 0.0:
		_takeoff_grace -= delta
		if _takeoff_grace <= 0.0:
			_landed_planet = null
	if _banner_time_left > 0.0:
		_banner_time_left -= delta

	if state == FlightState.FLYING:
		var flight_input := _get_flight_input()
		if flight_input.length_squared() > 1.0:
			flight_input = flight_input.normalized()
		flight_input = _consume_fuel_for_input(flight_input, delta)
		_last_flight_input = flight_input

		gravity_acceleration = _calculate_gravity_acceleration()
		velocity += (flight_input * spacecraft_acceleration_a + gravity_acceleration) * delta
		# Exponential decay keeps drag frame-rate independent.
		velocity *= exp(-linear_drag * delta)
		if velocity.length() > flight_speed:
			velocity = velocity.normalized() * flight_speed
		_move_spacecraft(delta)

		_check_obstacle_collisions()
		if state == FlightState.FLYING:
			var at_destination := get_spacecraft_world_position().distance_to(_logical_to_world(destination)) <= arrival_radius
			if at_destination:
				_handle_arrival_zone()
			else:
				# Re-arm banking only after leaving the zone, so hovering at
				# MIT doesn't re-trigger the banner every frame.
				_inside_arrival_zone = false
	elif state == FlightState.LANDED:
		_last_flight_input = Vector2.ZERO
		if _landing_elapsed >= 0.0:
			_advance_landing(delta)
		else:
			_walk_on_surface(delta, _get_walk_input())
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
	_last_flight_input = Vector2.ZERO
	_prediction_elapsed = 0.0
	_landed_planet = null
	_takeoff_grace = 0.0
	_surface_walk_forward = Vector3.ZERO
	_landing_elapsed = -1.0
	_level_rig()
	_inside_arrival_zone = false
	_banner_time_left = 0.0
	for bolt in _live_bolts:
		if is_instance_valid(bolt):
			bolt.queue_free()
	_live_bolts.clear()
	# Beavers ride along on a reset: everyone back to their spawn points.
	if _beaver_director != null and _beaver_director.has_method("reset_all"):
		_beaver_director.call("reset_all")
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
	# velocity is logical (x, y) -> world (x, z); altitude (world Y) stays locked.
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


## Raw stick / WASD, NOT converted to world space: walking maps it through
## the camera basis itself (see _walk_on_surface). x = strafe, y = forward.
func _get_walk_input() -> Vector2:
	var stick := Vector2.ZERO
	if _left_controller != null:
		stick = _left_controller.get_vector2(&"primary")
	if stick.length() < joystick_deadzone and _right_controller != null:
		stick = _right_controller.get_vector2(&"primary")
	var result := stick if stick.length() >= joystick_deadzone else Vector2.ZERO

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
	if state == FlightState.LANDED:
		# Never integrate from inside the collision sphere — it would report
		# an instant IMPACT and flash the minimap red while parked.
		predicted_flow_result = "LANDED"
		predicted_flow_message = "B/Y TO LAUNCH"
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

	# Planets: approach speed decides landing vs crash.
	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var obstacle := child as Node3D
			if obstacle == null:
				continue
			# Just took off from this one — give it a moment to get clear.
			if obstacle == _landed_planet and _takeoff_grace > 0.0:
				continue
			var diameter: Variant = obstacle.get("target_diameter_meters")
			if diameter == null:
				continue
			var collision_distance := float(diameter) * 0.5 + spacecraft_radius
			if spacecraft_world_position.distance_to(obstacle.global_position) <= collision_distance:
				if velocity.length() < landing_speed_threshold:
					_land_on(obstacle, collision_distance, velocity.length())
				else:
					_crash("COLLISION · %s" % obstacle.name, 0.35)
				return

	# Black holes: no landing on those, ever.
	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("captures"):
				continue
			if bool(black_hole.call("captures", spacecraft_world_position, spacecraft_radius)):
				_crash("CAPTURED · %s" % black_hole.name, 0.5)
				return


func _crash(message: String, haptic_duration: float) -> void:
	state = FlightState.CRASHED
	crash_message = message
	velocity = Vector2.ZERO
	_pulse_controllers(1.0, haptic_duration)
	print("SpacecraftFlight|INFO: %s" % message)


func _land_on(planet: Node3D, collision_distance: float, impact_speed: float) -> void:
	state = FlightState.LANDED
	_landed_planet = planet
	_surface_walk_forward = Vector3.ZERO
	velocity = Vector2.ZERO
	fuel = maximum_fuel

	# Snap the rig so the CAMERA's XZ sits just outside the planet's contact
	# circle at the flight plane: radius = sqrt((R+r)^2 - dy^2), guaranteed
	# real because a contact just happened. Move the rig by the camera's
	# delta so room-scale offset is respected.
	var camera_position := get_spacecraft_world_position()
	var camera_xz := Vector2(camera_position.x, camera_position.z)
	var planet_xz := Vector2(planet.global_position.x, planet.global_position.z)
	var dy := start_position.z - planet.global_position.y
	var ring_radius := sqrt(maxf(collision_distance * collision_distance - dy * dy, 0.01)) + 0.05
	var away := camera_xz - planet_xz
	away = away.normalized() if away.length() > 0.001 else Vector2.RIGHT
	var target_xz := planet_xz + away * ring_radius

	# Glide in over landing_animation_seconds rather than teleporting.
	# _physics_process advances this; snapping was the disorienting part of
	# a touchdown, so the rig now travels the last stretch under animation.
	_landing_from = global_position
	_landing_to = global_position + Vector3(
		target_xz.x - camera_xz.x,
		0.0,
		target_xz.y - camera_xz.y
	)
	_landing_elapsed = 0.0
	if landing_animation_seconds <= 0.0:
		global_position = _landing_to
		_landing_elapsed = -1.0

	_pulse_controllers(0.3, 0.2)
	# Touchdown dust: bigger burst for a harder landing.
	_spawn_dust(
		get_spacecraft_world_position(),
		planet,
		int(lerpf(12.0, 26.0, clampf(impact_speed / landing_speed_threshold, 0.0, 1.0))),
		lerpf(1.6, 3.2, clampf(impact_speed / landing_speed_threshold, 0.0, 1.0)),
		0.8
	)
	_update_predicted_flow()
	_update_status()
	print("SpacecraftFlight|INFO: landed on %s at %.1f m/s, refueled" % [planet.name, impact_speed])


## While landed you walk the planet's whole sphere. `input` is raw
## stick/WASD (x = strafe, y = forward) and is mapped through the ACTIVE
## camera's basis, so you always move where you are looking — including up
## and over the poles.
##
## The move is done in 3D and then re-projected onto the sphere, which keeps
## your distance from the planet's centre exactly constant no matter how the
## steps accumulate.
func _walk_on_surface(delta: float, input: Vector2) -> void:
	if _walk_dust_cooldown > 0.0:
		_walk_dust_cooldown -= delta
	if _landed_planet == null:
		return

	var position_now := get_spacecraft_world_position()
	var center := _landed_planet.global_position
	var to_surface := position_now - center
	var surface_radius := to_surface.length()
	if surface_radius < 0.01:
		return
	var normal := to_surface / surface_radius

	# Settle upright relative to the surface whether or not you are moving,
	# so the planet always reads as "down" underfoot. This sits before the
	# input check on purpose: standing still must still level you out.
	_align_rig_up(normal, delta * 2.0)
	if input.is_zero_approx():
		return

	# Build one ORTHOGONAL walking frame from the active camera. Projecting and
	# normalizing forward/right independently makes them non-perpendicular on
	# a curved surface, which distorts diagonals and feels like sideways drift.
	var view := get_viewport().get_camera_3d()
	var view_basis := view.global_basis if view != null else global_basis
	var projected_view_forward := -view_basis.z
	projected_view_forward -= normal * projected_view_forward.dot(normal)
	var forward := projected_view_forward
	if forward.length() < 0.08:
		# Parallel-transport the previous tangent instead of switching suddenly
		# to camera-up when the player looks along the surface normal.
		forward = _surface_walk_forward - normal * _surface_walk_forward.dot(normal)
	if forward.length() < 0.08:
		var reference := Vector3.UP if absf(normal.y) < 0.9 else Vector3.FORWARD
		forward = reference - normal * reference.dot(normal)
	if forward.length() < 0.001:
		return
	forward = forward.normalized()
	_surface_walk_forward = forward
	var right := forward.cross(normal).normalized()

	var input_strength := clampf(input.length(), 0.0, 1.0)
	var input_direction := input / input_strength
	var move := right * input_direction.x + forward * input_direction.y
	if move.length() < 0.001:
		return

	# Preserve analog magnitude: a gentle stick push walks slowly instead of
	# jumping immediately to full surface_walk_speed.
	var stepped := position_now + move.normalized() * surface_walk_speed * input_strength * delta
	var target := center + (stepped - center).normalized() * surface_radius
	global_position += target - position_now

	if _walk_dust_cooldown <= 0.0:
		_walk_dust_cooldown = 0.22
		_spawn_dust(get_spacecraft_world_position(), _landed_planet, 3, 0.8, 0.45)


## Smooth touchdown glide. Walking is suspended until it finishes, so the
## player is never fighting the animation for control.
func _advance_landing(delta: float) -> void:
	_landing_elapsed += delta
	var progress := clampf(_landing_elapsed / maxf(landing_animation_seconds, 0.001), 0.0, 1.0)
	# Ease-out: close the gap quickly, then settle slowly.
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	global_position = _landing_from.lerp(_landing_to, eased)

	if _landed_planet != null:
		var normal := get_spacecraft_world_position() - _landed_planet.global_position
		if normal.length() > 0.01:
			_align_rig_up(normal.normalized(), delta * 2.0)

	if progress >= 1.0:
		_landing_elapsed = -1.0


## Rotate the whole rig so its up-axis leans toward `target_up`. Walking
## around a sphere without this leaves you sideways (and eventually upside
## down) on the far side; with it, the horizon tips exactly as it would if
## you really were strolling around the little world.
## Rotation is applied about the rig origin, so your position is unchanged.
func _align_rig_up(target_up: Vector3, weight: float) -> void:
	var current_up := global_basis.y.normalized()
	var goal := target_up.normalized()
	var axis := current_up.cross(goal)
	if axis.length() < 0.00001:
		return
	var angle := current_up.angle_to(goal) * clampf(weight, 0.0, 1.0)
	if absf(angle) < 0.00001:
		return
	var pivot := global_position
	global_basis = Basis(axis.normalized(), angle) * global_basis
	global_position = pivot


## Snap back to world-upright, keeping whichever way you were facing.
func _level_rig() -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	var pivot := global_position
	global_basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	global_position = pivot


## Puff of surface dust, thrown along the planet's outward normal.
func _spawn_dust(
	at: Vector3,
	planet: Node3D,
	amount: int,
	speed: float,
	lifetime: float
) -> void:
	var dust := SurfaceDustScript.new() as SurfaceDust
	var normal := at - planet.global_position
	dust.surface_normal = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	dust.burst_amount = amount
	dust.burst_speed = speed
	dust.puff_lifetime = lifetime
	get_tree().current_scene.add_child(dust)
	# Sit the puff just inside the contact point so it looks like it comes
	# off the ground rather than out of the player's face.
	dust.global_position = at - dust.surface_normal * 0.4


## Launch back into the plane the planets fly in. You may be standing
## anywhere on the sphere (including a pole, directly above the plane), so
## this drops you to the flight altitude AND pushes you out past the
## planet's cross-section there — otherwise "up" would launch you straight
## into the rock.
func take_off() -> void:
	if state != FlightState.LANDED:
		return
	var launch_from := get_spacecraft_world_position()
	var away := Vector2.RIGHT
	if _landed_planet != null:
		var center := _landed_planet.global_position
		var horizontal := Vector2(launch_from.x - center.x, launch_from.z - center.z)
		# Standing on a pole gives no horizontal direction; pick one.
		if horizontal.length() > 0.001:
			away = horizontal.normalized()

		var diameter: Variant = _landed_planet.get("target_diameter_meters")
		if diameter != null:
			var contact := float(diameter) * 0.5 + spacecraft_radius
			var dy := start_position.z - center.y
			# Cross-section radius of the planet at the flight altitude.
			var clear_radius := (
				sqrt(maxf(contact * contact - dy * dy, 0.01))
				+ takeoff_clearance_margin
			)
			var target := Vector2(center.x, center.z) + away * clear_radius
			global_position += Vector3(
				target.x - launch_from.x,
				start_position.z - launch_from.y,
				target.y - launch_from.z
			)

	# Flight assumes an upright rig (the play field is a horizontal plane),
	# so undo whatever tilt walking the sphere left behind.
	_level_rig()
	_surface_walk_forward = Vector3.ZERO
	_landing_elapsed = -1.0
	state = FlightState.FLYING
	velocity = away * takeoff_speed
	_takeoff_grace = takeoff_grace_seconds
	_prediction_elapsed = 0.0
	_pulse_controllers(0.25, 0.15)
	_spawn_dust(launch_from, _landed_planet, 18, 2.6, 0.7)
	print("SpacecraftFlight|INFO: launched from %s back into the flight plane" % (
		_landed_planet.name if _landed_planet != null else "?"
	))


func _handle_arrival_zone() -> void:
	if _inside_arrival_zone:
		return
	_inside_arrival_zone = true

	# No beaver layer in the scene: behave like the pre-beaver game.
	if _beaver_director == null or not _beaver_director.has_method("bank_cargo"):
		state = FlightState.ARRIVED
		velocity = Vector2.ZERO
		_pulse_controllers(0.45, 0.5)
		print("SpacecraftFlight|INFO: destination reached")
		return

	var banked := int(_beaver_director.call("bank_cargo"))
	var delivered := int(_beaver_director.call("get_delivered_count"))
	var total := int(_beaver_director.call("get_total_count"))
	if total > 0 and delivered >= total:
		state = FlightState.ARRIVED
		velocity = Vector2.ZERO
		_pulse_controllers(0.45, 0.5)
		# Final delivery gets the biggest send-off.
		_play_deposit_effect(maxi(banked, 1))
		print("SpacecraftFlight|INFO: all %d beavers delivered — mission complete" % total)
	elif banked > 0:
		_set_banner("BANKED %d BEAVER%s · %d TO GO" % [
			banked, "" if banked == 1 else "S", total - delivered
		], 3.0)
		_pulse_controllers(0.3, 0.25)
		_play_deposit_effect(banked)
	else:
		_set_banner("NO CARGO · SHOOT BEAVERS ON PLANETS", 2.5)


## Loud warning when a planet is closing faster than you could survive.
## Uses time-to-surface rather than raw distance, so a fast approach warns
## from far away and a slow drift never nags.
func _update_impact_warning(delta: float) -> void:
	if _warning_haptic_cooldown > 0.0:
		_warning_haptic_cooldown -= delta
	_impact_warning = ""
	if state != FlightState.FLYING or _obstacles_root == null:
		return
	var speed := velocity.length()
	if speed <= landing_speed_threshold:
		return  # slow enough to land; nothing to warn about

	var position_now := get_spacecraft_world_position()
	var soonest := INF
	var soonest_name := ""
	for child in _obstacles_root.get_children():
		var planet := child as Node3D
		if planet == null:
			continue
		var diameter: Variant = planet.get("target_diameter_meters")
		if diameter == null:
			continue
		var to_center := Vector2(
			planet.global_position.x - position_now.x,
			planet.global_position.z - position_now.z
		)
		var gap := to_center.length() - (float(diameter) * 0.5 + spacecraft_radius)
		if gap <= 0.0:
			continue
		# Only the component of travel aimed AT the planet counts.
		var closing := velocity.dot(to_center.normalized())
		if closing <= landing_speed_threshold:
			continue
		var seconds_left := gap / closing
		if seconds_left < soonest:
			soonest = seconds_left
			soonest_name = planet.name

	if soonest <= impact_warning_seconds:
		_impact_warning = ">>> TOO FAST — %s IN %.1fs — BRAKE BELOW %.0f <<<" % [
			soonest_name, soonest, landing_speed_threshold
		]
		if _warning_haptic_cooldown <= 0.0:
			_warning_haptic_cooldown = 0.35
			_pulse_controllers(0.5, 0.12)


## Stream the delivered beavers out of the hold and into the dome.
func _play_deposit_effect(count: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var effect: Node3D = DepositEffectScript.new()
	effect.from_position = get_spacecraft_world_position()
	# Aim for the top of the dome rather than its base.
	effect.to_position = _logical_to_world(destination) + Vector3(0.0, 11.0, 0.0)
	effect.beaver_count = clampi(count, 1, 24)
	scene.add_child(effect)
	effect.global_position = Vector3.ZERO


func _set_banner(text: String, seconds: float) -> void:
	_banner_text = text
	_banner_time_left = seconds


func _is_restart_pressed() -> bool:
	if Input.is_key_pressed(KEY_R):
		return true
	for controller in [_left_controller, _right_controller]:
		if controller == null:
			continue
		for action in RESTART_BUTTONS:
			if controller.is_button_pressed(action):
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
	elif action in START_BUTTONS and state == FlightState.LANDED:
		take_off()
	elif (
		action in RESTART_BUTTONS
		and (state == FlightState.CRASHED or state == FlightState.ARRIVED)
	):
		reset_flight()


# --- magic bolt firing -------------------------------------------------------

## VR fire: edge-detect the trigger per hand so the firing hand's pose aims
## the bolt. (The trigger_click signal path also exists, but polling gives
## us the analog fallback below 'click' pressure.)
func _poll_vr_fire() -> void:
	var controllers := [_left_controller, _right_controller]
	for index in controllers.size():
		var controller: XRController3D = controllers[index]
		if controller == null:
			continue
		# Quest exposes the trigger as an analogue value. A lower engagement
		# threshold makes a normal pull reliable; release must still cross 0.2
		# before the next shot, which prevents noisy values from double-firing.
		var trigger_value := controller.get_float(&"trigger")
		var pressed := trigger_value >= (0.2 if _fire_was_pressed[index] else 0.35)
		for action in FIRE_BUTTONS:
			pressed = pressed or controller.is_button_pressed(action)
		if pressed and not _fire_was_pressed[index]:
			# The controller nodes use OpenXR's calibrated aim pose, so -Z is
			# the actual pointing ray instead of the palm-oriented grip axis.
			_try_fire(
				controller.global_position - controller.global_basis.z * 0.2,
				-controller.global_basis.z
			)
		_fire_was_pressed[index] = pressed


## Squeeze the grip (or hold TAB on desktop) to expand the tactical map.
## Held, not toggled: you get the big map exactly while you ask for it, and
## it never gets left open covering the view.
func _poll_map_expand() -> void:
	var expanded := Input.is_key_pressed(KEY_TAB)
	for controller in [_left_controller, _right_controller]:
		if controller == null:
			continue
		for action in MAP_EXPAND_BUTTONS:
			if controller.is_button_pressed(action):
				expanded = true
		if controller.get_float(&"grip") >= 0.55:
			expanded = true
	if expanded != _map_expanded:
		_map_expanded = expanded
		_pulse_controllers(0.12, 0.05)


func is_map_expanded() -> bool:
	return _map_expanded


## Desktop fire: right-click (left is the orbit-camera drag).
## The desktop camera orbits tens of metres from the ship, so firing FROM
## the camera would spawn the bolt way out in space (and it would expire
## before arriving). Instead: intersect the mouse ray with the flight plane
## and shoot from the SHIP toward that point — right-click where you want
## the bolt to go.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin := camera.project_ray_origin(event.position)
	var ray_normal := camera.project_ray_normal(event.position)
	if absf(ray_normal.y) < 0.0001:
		return  # looking along the plane; no aim point
	var distance_to_plane := (start_position.z - ray_origin.y) / ray_normal.y
	if distance_to_plane <= 0.0:
		return  # clicked the sky, above the horizon
	var aim_point := ray_origin + ray_normal * distance_to_plane

	var ship := get_spacecraft_world_position()
	var direction := aim_point - ship
	direction.y = 0.0
	if direction.length() < 0.01:
		return
	direction = direction.normalized()
	_try_fire(ship + direction * 0.6, direction)


func _try_fire(origin: Vector3, direction: Vector3) -> void:
	# Bolts are a landed-only tool: collection happens ON planets, per spec.
	if state != FlightState.LANDED:
		# Silent failure reads as a broken button; say why.
		if state == FlightState.FLYING:
			_set_banner("LAND ON A PLANET TO FIRE", 1.5)
		return
	_live_bolts = _live_bolts.filter(func(bolt): return is_instance_valid(bolt))
	if _live_bolts.size() >= max_live_bolts:
		var oldest: Node3D = _live_bolts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	# You stand ON a planet to shoot, and the beavers stand on it too, so a
	# bolt skimming the surface must NOT be swallowed by that planet — only
	# a shot aimed squarely into the ground counts as hitting it.
	if _landed_planet != null:
		var into_surface := (_landed_planet.global_position - origin).normalized()
		if direction.normalized().dot(into_surface) > 0.85:
			_set_banner("AIMED INTO THE SURFACE", 1.2)
			return

	var bolt := MagicBoltScript.new() as MagicBolt
	bolt.velocity = direction.normalized() * bolt_speed
	bolt.hit_radius = bolt_hit_radius
	bolt.gravity_scale = bolt_gravity_scale
	bolt.ignored_planet = _landed_planet
	bolt.setup(self, _beaver_director, _obstacles_root, _black_holes_root, play_area_min, play_area_max)
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = origin
	_live_bolts.append(bolt)
	_pulse_controllers(0.15, 0.08)


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
			message = "GRAVITY FIELD DISENGAGED\nPress B or Y to start"
		FlightState.LANDED:
			message = "LANDED · %s · REFUELED\nWASD/stick: walk   TRIGGER: bolt   B/Y: launch" % (
				_landed_planet.name if _landed_planet != null else "?"
			)
		FlightState.CRASHED:
			message = "%s\nPress A/X or R to restart" % crash_message
		FlightState.ARRIVED:
			message = _arrival_message()
		_:
			message = "POS %.1f, %.1f   ALT %.0f\nSPD %.1f   GRAV %.2f   FUEL %.0f/%.0f\nGOAL %.0f, %.0f   DIST %.1f" % [
				logical_position.x,
				logical_position.y,
				logical_position.z,
				velocity.length(),
				gravity_acceleration.length(),
				fuel,
				maximum_fuel,
				destination.x,
				destination.y,
				distance_left,
			]
			message += _beaver_status_line()
	if _banner_time_left > 0.0:
		message += "\n%s" % _banner_text
	if not _impact_warning.is_empty():
		message = "%s\n%s" % [_impact_warning, message]

	# Colour is the loud part: the whole readout goes red on a bad approach.
	var alarm := not _impact_warning.is_empty()
	if _vr_status != null:
		_vr_status.text = message
		_vr_status.modulate = Color(1.0, 0.25, 0.2, 1.0) if alarm else Color(0.7, 0.9, 1.0, 0.9)
	if _desktop_status != null:
		_desktop_status.text = message.replace("\n", "  ·  ")
		_desktop_status.add_theme_color_override(
			"font_color",
			Color(1.0, 0.3, 0.25) if alarm else Color(0.86, 0.9, 1.0)
		)


func _beaver_status_line() -> String:
	if _beaver_director == null or not _beaver_director.has_method("get_total_count"):
		return ""
	return "\nBVR %d/%d   CARGO %d" % [
		int(_beaver_director.call("get_delivered_count")),
		int(_beaver_director.call("get_total_count")),
		int(_beaver_director.call("get_cargo_count")),
	]


func _arrival_message() -> String:
	if _beaver_director != null and _beaver_director.has_method("get_total_count"):
		return "ALL %d BEAVERS DELIVERED TO MIT\nPress A/X or R to fly again" % int(
			_beaver_director.call("get_total_count")
		)
	return "DESTINATION REACHED\nPress A/X or R to fly again"


func get_fuel_ratio() -> float:
	return clampf(fuel / maxf(maximum_fuel, 0.0001), 0.0, 1.0)


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
	# Altitude is the real height so the HUD tells the truth while you are
	# standing on top of a planet.
	var spacecraft_world_position := get_spacecraft_world_position()
	return Vector3(
		spacecraft_world_position.x,
		spacecraft_world_position.z,
		spacecraft_world_position.y
	)


func get_spacecraft_world_position() -> Vector3:
	# The rig origin is the ship's authoritative anchor. Head tracking remains
	# free inside the cockpit, but leaning or room-scale motion cannot make the
	# physics position drift away from the visible hull.
	if state == FlightState.LANDED:
		return global_position
	return Vector3(global_position.x, start_position.z, global_position.z)


func get_view_heading() -> Vector2:
	if _flight_camera == null:
		return Vector2.ZERO
	var forward := -_flight_camera.global_basis.z
	var heading := Vector2(forward.x, forward.z)
	return heading.normalized() if heading.length_squared() > 0.0001 else Vector2.ZERO


func _logical_to_world(logical_position: Vector3) -> Vector3:
	return Vector3(logical_position.x, logical_position.z, logical_position.y)
