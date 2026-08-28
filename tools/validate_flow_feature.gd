extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	var packed_scene := load("res://main.tscn") as PackedScene
	_check(packed_scene != null, "main.tscn must load")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	call_deferred("_run_checks", scene)


func _run_checks(scene: Node) -> void:
	await process_frame
	await physics_frame

	var flight := scene.get_node_or_null("XROrigin3D")
	_check(flight != null, "XROrigin3D must exist")
	_check(scene.get_node_or_null("Floor") == null, "3D Floor node must be removed")
	if flight == null:
		_finish()
		return
	_check(
		flight.get("play_area_min") == Vector2(-20.0, -20.0),
		"flight minimum boundary remains -20,-20"
	)
	_check(
		flight.get("play_area_max") == Vector2(120.0, 120.0),
		"flight maximum boundary remains 120,120"
	)
	var desktop_map := scene.get_node_or_null("DesktopHUD/MiniMapPanel/Map")
	_check(desktop_map != null, "desktop minimap must exist")
	if desktop_map != null:
		_check(desktop_map.get("map_min") == Vector2(-20.0, -20.0), "map minimum remains -20,-20")
		_check(desktop_map.get("map_max") == Vector2(120.0, 120.0), "map maximum remains 120,120")
	var planets := scene.get_node_or_null("MoonExhibit")
	var black_holes := scene.get_node_or_null("BlackHoleExhibit")
	var rewards := scene.get_node_or_null("RewardPoints")
	_check(planets != null and planets.get_child_count() == 12, "layout contains 12 green planets")
	_check(black_holes != null and black_holes.get_child_count() == 6, "layout contains 6 red black holes")
	_check(rewards != null and rewards.get_child_count() == 12, "layout contains 12 rewards")
	_check(is_equal_approx(float(flight.get("gravity_constant_c")), 8.0), "C compensates for smaller planet radii")
	_check(is_equal_approx(float(flight.get("spacecraft_radius")), 0.9), "ship collision radius is 0.9")
	if planets != null:
		for planet in planets.get_children():
			var radius := float(planet.get("target_diameter_meters")) * 0.5
			_check(radius >= 2.0 and radius <= 5.0, "%s radius stays within 2..5" % planet.name)
	if black_holes != null:
		for black_hole in black_holes.get_children():
			var radius := float(black_hole.get("capture_radius"))
			_check(radius >= 2.0 and radius <= 5.0, "%s radius stays within 2..5" % black_hole.name)
			_check(
				is_equal_approx(float(black_hole.get("visual_diameter_meters")), radius * 2.0),
				"%s visual diameter matches collision radius" % black_hole.name
			)
	if rewards != null:
		for reward in rewards.get_children():
			_check(is_equal_approx(float(reward.get("detection_radius")), 3.0), "%s detection radius is 3" % reward.name)
			_check(not bool(reward.get("is_collected")), "%s begins uncollected" % reward.name)
	_validate_layout_clearance(planets, black_holes, rewards)

	_check(flight.has_method("get_total_gravity_at"), "flight exposes the vector field")
	_check(flight.has_method("get_predicted_flow_points"), "flight exposes ODE flow samples")
	_check(flight.has_method("get_fuel_ratio"), "flight exposes fuel ratio")
	_check(flight.has_method("is_waiting_to_start"), "flight exposes its initial waiting state")
	_check(bool(flight.call("is_waiting_to_start")), "flight initially waits for B/Y")
	_check(flight.get("velocity") == Vector2.ZERO, "ship is stationary before B/Y")
	_check(flight.get("gravity_acceleration") == Vector2.ZERO, "gravity is disengaged before B/Y")
	_check(
		String(flight.call("get_predicted_flow_result")) == "READY",
		"minimap reports READY before B/Y"
	)

	var gravity: Vector2 = flight.call("get_total_gravity_at", Vector3(0.0, 10.0, 0.0))
	_check(is_finite(gravity.x) and is_finite(gravity.y), "gravity field is finite")

	flight.call("start_flight")
	_check(not bool(flight.call("is_waiting_to_start")), "B/Y start transition activates flight")
	_check(
		flight.get("gravity_acceleration") is Vector2
		and (flight.get("gravity_acceleration") as Vector2).length() > 0.0,
		"starting engages the gravity field"
	)

	var flow_points: PackedVector2Array = flight.call("get_predicted_flow_points")
	_check(flow_points.size() >= 2, "RK4 flow contains at least two samples")
	for point in flow_points:
		_check(is_finite(point.x) and is_finite(point.y), "all RK4 flow samples are finite")

	if rewards != null and not rewards.get_children().is_empty():
		var first_reward := rewards.get_child(0) as Node3D
		flight.global_position = Vector3(first_reward.global_position.x, 10.0, first_reward.global_position.z)
		flight.call("_check_reward_collection")
		_check(int(flight.call("get_rewards_collected")) == 1, "entering a reward radius collects one reward")
		_check(int(flight.call("get_display_score")) == 100, "one reward adds 100 points")
		flight.set("fuel", 50.0)
		_check(int(flight.call("_calculate_final_score")) == 250, "50 fuel adds a 150-point completion bonus")

	var initial_fuel := float(flight.get("fuel"))
	var burn_rate := float(flight.get("fuel_burn_per_second"))
	flight.call("_consume_fuel_for_input", Vector2.RIGHT, 1.0)
	var remaining_fuel := float(flight.get("fuel"))
	_check(
		is_equal_approx(remaining_fuel, initial_fuel - burn_rate),
		"full thrust burns the configured fuel amount"
	)
	flight.call("reset_flight")
	_check(
		is_equal_approx(float(flight.get("fuel")), float(flight.get("maximum_fuel"))),
		"reset refills fuel"
	)
	_check(bool(flight.call("is_waiting_to_start")), "reset returns to B/Y waiting state")
	_check(int(flight.call("get_rewards_collected")) == 0, "reset clears the reward count")
	if rewards != null and not rewards.get_children().is_empty():
		_check(not bool(rewards.get_child(0).get("is_collected")), "reset restores collected rewards")

	print(
		"FlowFeature|INFO: %d RK4 samples, field=(%.3f, %.3f), result=%s"
		% [
			flow_points.size(),
			gravity.x,
			gravity.y,
			String(flight.call("get_predicted_flow_result")),
		]
	)
	_finish()


func _validate_layout_clearance(planets: Node, black_holes: Node, rewards: Node) -> void:
	if planets == null or black_holes == null or rewards == null:
		return
	var bodies: Array[Node3D] = []
	var body_radii: Array[float] = []
	for planet in planets.get_children():
		bodies.append(planet as Node3D)
		body_radii.append(float(planet.get("target_diameter_meters")) * 0.5)
	for black_hole in black_holes.get_children():
		bodies.append(black_hole as Node3D)
		body_radii.append(float(black_hole.get("capture_radius")))

	var minimum_body_clearance := INF
	for first_index in bodies.size():
		for second_index in range(first_index + 1, bodies.size()):
			var first_position := Vector2(bodies[first_index].global_position.x, bodies[first_index].global_position.z)
			var second_position := Vector2(bodies[second_index].global_position.x, bodies[second_index].global_position.z)
			var clearance := first_position.distance_to(second_position) - body_radii[first_index] - body_radii[second_index]
			minimum_body_clearance = minf(minimum_body_clearance, clearance)
			_check(clearance > 0.0, "%s and %s do not overlap" % [bodies[first_index].name, bodies[second_index].name])

	var minimum_reward_clearance := INF
	for reward in rewards.get_children():
		var reward_position := Vector2(reward.global_position.x, reward.global_position.z)
		var reward_radius := float(reward.get("detection_radius"))
		for body_index in bodies.size():
			var body_position := Vector2(bodies[body_index].global_position.x, bodies[body_index].global_position.z)
			var clearance := reward_position.distance_to(body_position) - reward_radius - body_radii[body_index]
			minimum_reward_clearance = minf(minimum_reward_clearance, clearance)
			_check(clearance > 0.0, "%s collection radius does not overlap %s" % [reward.name, bodies[body_index].name])
	print(
		"FlowFeature|INFO: minimum body clearance=%.2f, reward clearance=%.2f"
		% [minimum_body_clearance, minimum_reward_clearance]
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("FlowFeature|FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("FlowFeature|PASS")
		quit(0)
	else:
		print("FlowFeature|FAIL: %d checks failed" % _failures.size())
		quit(1)
