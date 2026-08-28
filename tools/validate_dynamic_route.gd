extends SceneTree

const MAP_MIN := Vector2(-20.0, -20.0)
const CELL_SIZE := 2.0
const GRID_SIDE := 71


func _initialize() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	call_deferred("_run", scene)


func _run(scene: Node) -> void:
	await process_frame
	await physics_frame
	var flight := scene.get_node("XROrigin3D")
	var path := _build_geometric_path(flight)
	if path.is_empty():
		push_error("DynamicRoute|FAIL: no geometric path")
		quit(1)
		return

	var test_parameters := [
		Vector2(7.0, 0.7),
		Vector2(8.0, 0.8),
		Vector2(9.0, 0.9),
		Vector2(10.0, 1.0),
		Vector2(11.0, 1.1),
	]
	for parameters in test_parameters:
		var result := _simulate(flight, path, parameters.x, parameters.y)
		print(
			"DynamicRoute|INFO: speed=%.1f gain=%.1f result=%s time=%.1f fuel=%.1f rewards=%d"
			% [parameters.x, parameters.y, result.status, result.time, result.fuel, result.rewards]
		)
		if result.status == "GOAL":
			print("DynamicRoute|PASS: %d waypoints" % path.size())
			quit(0)
			return
	push_error("DynamicRoute|FAIL: no tested controller reached the goal")
	quit(1)


func _build_geometric_path(flight: Node) -> PackedVector2Array:
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, GRID_SIDE, GRID_SIDE)
	grid.cell_size = Vector2.ONE * CELL_SIZE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	grid.update()
	for x_index in GRID_SIDE:
		for y_index in GRID_SIDE:
			var logical := MAP_MIN + Vector2(x_index, y_index) * CELL_SIZE
			var world := Vector3(logical.x, 10.0, logical.y)
			if not _has_clearance(flight, world, 3.0):
				grid.set_point_solid(Vector2i(x_index, y_index), true)

	var start_id := _logical_to_id(Vector2(0.0, 0.0))
	var goal_id := _logical_to_id(Vector2(100.0, 100.0))
	grid.set_point_solid(start_id, false)
	grid.set_point_solid(goal_id, false)
	var id_path := grid.get_id_path(start_id, goal_id)
	var result := PackedVector2Array()
	for path_index in id_path.size():
		result.append(_id_to_logical(id_path[path_index]))
	if result.is_empty() or result[result.size() - 1].distance_to(Vector2(100.0, 100.0)) > 0.1:
		result.append(Vector2(100.0, 100.0))
	return _smooth_path(flight, result)


func _has_clearance(flight: Node, world_position: Vector3, margin: float) -> bool:
	var ship_radius := float(flight.get("spacecraft_radius"))
	for planet in current_scene.get_node("MoonExhibit").get_children():
		var radius := float(planet.get("target_diameter_meters")) * 0.5 + ship_radius + margin
		if world_position.distance_to(planet.global_position) <= radius:
			return false
	for black_hole in current_scene.get_node("BlackHoleExhibit").get_children():
		var radius := float(black_hole.get("capture_radius")) + ship_radius + margin
		if world_position.distance_to(black_hole.global_position) <= radius:
			return false
	return true


func _smooth_path(flight: Node, raw_path: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array([raw_path[0]])
	var anchor_index := 0
	while anchor_index < raw_path.size() - 1:
		var selected_index := anchor_index + 1
		for candidate_index in range(raw_path.size() - 1, anchor_index, -1):
			if _segment_has_clearance(flight, raw_path[anchor_index], raw_path[candidate_index], 2.0):
				selected_index = candidate_index
				break
		result.append(raw_path[selected_index])
		anchor_index = selected_index
	return result


func _segment_has_clearance(flight: Node, from: Vector2, to: Vector2, margin: float) -> bool:
	var distance := from.distance_to(to)
	var sample_count := maxi(1, ceili(distance))
	for sample_index in sample_count + 1:
		var point := from.lerp(to, float(sample_index) / float(sample_count))
		if not _has_clearance(flight, Vector3(point.x, 10.0, point.y), margin):
			return false
	return true


func _simulate(flight: Node, path: PackedVector2Array, desired_speed: float, gain: float) -> Dictionary:
	var ode_state := Vector4(0.0, 0.0, 0.0, 0.0)
	var fuel := 100.0
	var waypoint_index := 1
	var elapsed := 0.0
	var collected: Dictionary = {}
	var rewards := current_scene.get_node("RewardPoints")
	var step_size := 1.0 / 72.0
	while elapsed < 90.0:
		var position := Vector2(ode_state.x, ode_state.y)
		var velocity := Vector2(ode_state.z, ode_state.w)
		while waypoint_index < path.size() - 1 and position.distance_to(path[waypoint_index]) < 3.0:
			waypoint_index += 1
		var target := path[waypoint_index]
		var to_target := target - position
		var target_speed := minf(desired_speed, maxf(2.0, sqrt(to_target.length()) * 2.2))
		var desired_velocity := to_target.normalized() * target_speed if to_target.length() > 0.01 else Vector2.ZERO
		var gravity: Vector2 = flight.call("get_total_gravity_at", Vector3(position.x, 10.0, position.y))
		var requested_acceleration := (desired_velocity - velocity) * gain - gravity + velocity * float(flight.get("linear_drag"))
		var flight_input := requested_acceleration / float(flight.get("spacecraft_acceleration_a"))
		if flight_input.length() > 1.0:
			flight_input = flight_input.normalized()
		var requested_fuel := float(flight.get("fuel_burn_per_second")) * flight_input.length() * step_size
		if requested_fuel > fuel:
			flight_input *= fuel / maxf(requested_fuel, 0.0001)
			fuel = 0.0
		else:
			fuel -= requested_fuel

		ode_state = flight.call("_rk4_flow_step", ode_state, flight_input, step_size)
		ode_state = flight.call("_constrain_predicted_state", ode_state)
		position = Vector2(ode_state.x, ode_state.y)
		var world_position := Vector3(position.x, 10.0, position.y)
		var collision := String(flight.call("_get_collision_message_at", world_position))
		if not collision.is_empty():
			return {"status": collision, "time": elapsed, "fuel": fuel, "rewards": collected.size()}
		for reward in rewards.get_children():
			if collected.has(reward.name):
				continue
			var collect_distance := float(reward.get("detection_radius")) + float(flight.get("spacecraft_radius"))
			if world_position.distance_to(reward.global_position) <= collect_distance:
				collected[reward.name] = true
		if position.distance_to(Vector2(100.0, 100.0)) <= float(flight.get("arrival_radius")):
			return {"status": "GOAL", "time": elapsed, "fuel": fuel, "rewards": collected.size()}
		elapsed += step_size
	return {"status": "TIMEOUT", "time": elapsed, "fuel": fuel, "rewards": collected.size()}


func _logical_to_id(position: Vector2) -> Vector2i:
	return Vector2i(roundi((position.x - MAP_MIN.x) / CELL_SIZE), roundi((position.y - MAP_MIN.y) / CELL_SIZE))


func _id_to_logical(id: Vector2i) -> Vector2:
	return MAP_MIN + Vector2(id) * CELL_SIZE
