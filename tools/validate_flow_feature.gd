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
		flight.get("play_area_max") == Vector2(220.0, 220.0),
		"flight maximum boundary remains 220,220"
	)
	var desktop_map := scene.get_node_or_null("DesktopHUD/MiniMapPanel/Map")
	_check(desktop_map != null, "desktop minimap must exist")
	if desktop_map != null:
		_check(desktop_map.get("map_min") == Vector2(-20.0, -20.0), "map minimum remains -20,-20")
		_check(desktop_map.get("map_max") == Vector2(220.0, 220.0), "map maximum remains 220,220")

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
