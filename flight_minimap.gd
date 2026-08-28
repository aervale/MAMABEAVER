extends Control
class_name FlightMiniMap

## XY overview shared by the desktop HUD and the in-headset display.

@export var map_min := Vector2(-20.0, -20.0)
@export var map_max := Vector2(120.0, 120.0)

var _flight: Node3D
var _obstacles: Node3D
var _black_holes: Node3D
var _rewards: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_scene_nodes()
	queue_redraw()


func _process(_delta: float) -> void:
	if _flight == null or _obstacles == null or _black_holes == null or _rewards == null:
		_find_scene_nodes()
	queue_redraw()


func _draw() -> void:
	var map_size := size
	if map_size.x < 2.0 or map_size.y < 2.0:
		return

	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.012, 0.024, 0.055, 0.94))
	_draw_grid(map_size)
	_draw_predicted_flow(map_size)
	_draw_black_holes(map_size)
	_draw_obstacles(map_size)
	_draw_rewards(map_size)
	_draw_destination(map_size)
	_draw_spacecraft(map_size)
	draw_rect(Rect2(Vector2.ONE, map_size - Vector2.ONE * 2.0), Color(0.28, 0.62, 0.96, 0.9), false, 2.0)
	_draw_readout(map_size)


func _draw_grid(map_size: Vector2) -> void:
	var coordinate := -20.0
	while coordinate <= 120.01:
		var vertical_from := _world_to_map(Vector2(coordinate, map_min.y), map_size)
		var vertical_to := _world_to_map(Vector2(coordinate, map_max.y), map_size)
		var horizontal_from := _world_to_map(Vector2(map_min.x, coordinate), map_size)
		var horizontal_to := _world_to_map(Vector2(map_max.x, coordinate), map_size)
		var is_axis := is_zero_approx(coordinate)
		var color := Color(0.2, 0.56, 0.92, 0.75) if is_axis else Color(0.18, 0.32, 0.52, 0.42)
		var width := 2.0 if is_axis else 1.0
		draw_line(vertical_from, vertical_to, color, width)
		draw_line(horizontal_from, horizontal_to, color, width)
		coordinate += 20.0


func _draw_predicted_flow(map_size: Vector2) -> void:
	if _flight == null or not _flight.has_method("get_predicted_flow_points"):
		return
	var flow_points: PackedVector2Array = _flight.call("get_predicted_flow_points")
	if flow_points.size() < 2:
		return

	var map_points := PackedVector2Array()
	for point in flow_points:
		map_points.append(_world_to_map(point, map_size))

	var flow_result := "SAFE"
	if _flight.has_method("get_predicted_flow_result"):
		flow_result = String(_flight.call("get_predicted_flow_result"))
	var flow_color := Color(0.18, 0.82, 1.0, 0.95)
	match flow_result:
		"IMPACT":
			flow_color = Color(1.0, 0.18, 0.16, 0.98)
		"GOAL":
			flow_color = Color(0.16, 1.0, 0.42, 0.98)
		"STOPPED":
			flow_color = Color(0.58, 0.64, 0.72, 0.78)

	# A dark underlay keeps the ODE flow visible across grid lines and bodies.
	draw_polyline(map_points, Color(0.0, 0.015, 0.04, 0.9), 5.5, true)
	draw_polyline(map_points, flow_color, 2.2, true)
	draw_circle(map_points[map_points.size() - 1], 3.2, flow_color)


func _draw_obstacles(map_size: Vector2) -> void:
	if _obstacles == null:
		return
	var pixels_per_meter := minf(
		map_size.x / (map_max.x - map_min.x),
		map_size.y / (map_max.y - map_min.y)
	)
	for child in _obstacles.get_children():
		var obstacle := child as Node3D
		if obstacle == null:
			continue
		var diameter: Variant = obstacle.get("target_diameter_meters")
		if diameter == null:
			continue
		var planet_radius := float(diameter) * 0.5
		var flight_altitude := 10.0
		var spacecraft_radius := 0.25
		if _flight != null:
			var coordinates := _get_flight_coordinates()
			flight_altitude = coordinates.z
			var spacecraft_radius_value: Variant = _flight.get("spacecraft_radius")
			if spacecraft_radius_value != null:
				spacecraft_radius = float(spacecraft_radius_value)
		var vertical_distance := absf(flight_altitude - obstacle.global_position.y)
		var visual_radius_squared := planet_radius ** 2.0 - vertical_distance ** 2.0
		var collision_radius := planet_radius + spacecraft_radius
		var collision_radius_squared := collision_radius ** 2.0 - vertical_distance ** 2.0
		var center := _world_to_map(Vector2(obstacle.global_position.x, obstacle.global_position.z), map_size)
		if visual_radius_squared > 0.0:
			var visual_radius_pixels := sqrt(visual_radius_squared) * pixels_per_meter
			draw_circle(center, visual_radius_pixels, Color(0.08, 0.72, 0.31, 0.48))
			draw_arc(center, visual_radius_pixels, 0.0, TAU, 32, Color(0.2, 1.0, 0.5, 0.95), 2.0)
		if collision_radius_squared > 0.0:
			var collision_radius_pixels := sqrt(collision_radius_squared) * pixels_per_meter
			draw_arc(center, collision_radius_pixels, 0.0, TAU, 32, Color(0.72, 1.0, 0.28, 0.95), 1.5)
		_draw_body_id(center, String(obstacle.name).trim_prefix("Planet"), Color(0.55, 1.0, 0.67))


func _draw_black_holes(map_size: Vector2) -> void:
	if _black_holes == null:
		return
	var pixels_per_meter := minf(
		map_size.x / (map_max.x - map_min.x),
		map_size.y / (map_max.y - map_min.y)
	)
	var flight_altitude := 10.0
	var spacecraft_radius := 0.25
	if _flight != null:
		flight_altitude = _get_flight_coordinates().z
		spacecraft_radius = float(_flight.get("spacecraft_radius"))

	for child in _black_holes.get_children():
		var black_hole := child as Node3D
		if black_hole == null:
			continue
		var center := _world_to_map(
			Vector2(black_hole.global_position.x, black_hole.global_position.z),
			map_size
		)
		var capture_radius := float(black_hole.get("capture_radius"))
		var disk_radius := float(black_hole.get("accretion_disk_radius"))
		var mu := float(black_hole.get("gravitational_parameter_mu"))
		var softening := float(black_hole.get("gravity_softening_length"))
		var vertical_distance := absf(flight_altitude - black_hole.global_position.y)

		# Both rings are horizontal cross-sections at the ship's fixed altitude.
		var influence_radius_squared := mu - softening * softening - vertical_distance * vertical_distance
		if influence_radius_squared > 0.0:
			draw_arc(
				center,
				sqrt(influence_radius_squared) * pixels_per_meter,
				0.0,
				TAU,
				48,
				Color(0.72, 0.12, 0.22, 0.34),
				1.2
			)
		draw_circle(center, disk_radius * pixels_per_meter, Color(0.72, 0.015, 0.035, 0.16))
		draw_arc(center, disk_radius * pixels_per_meter, 0.0, TAU, 40, Color(1.0, 0.12, 0.18, 0.9), 2.0)
		var collision_radius := capture_radius + spacecraft_radius
		var collision_radius_squared := collision_radius * collision_radius - vertical_distance * vertical_distance
		if collision_radius_squared > 0.0:
			var capture_pixels := sqrt(collision_radius_squared) * pixels_per_meter
			draw_circle(center, capture_pixels, Color(0.0, 0.0, 0.015, 1.0))
			draw_arc(center, capture_pixels, 0.0, TAU, 32, Color(1.0, 0.08, 0.22, 1.0), 2.0)
		_draw_body_id(center, String(black_hole.name).trim_prefix("BlackHole"), Color(1.0, 0.5, 0.52))


func _draw_rewards(map_size: Vector2) -> void:
	if _rewards == null:
		return
	var pixels_per_meter := minf(
		map_size.x / (map_max.x - map_min.x),
		map_size.y / (map_max.y - map_min.y)
	)
	for child in _rewards.get_children():
		var reward := child as Node3D
		if reward == null or bool(reward.get("is_collected")):
			continue
		var center := _world_to_map(Vector2(reward.global_position.x, reward.global_position.z), map_size)
		var radius_pixels := maxf(4.0, float(reward.get("detection_radius")) * pixels_per_meter)
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006 + float(String(reward.name).hash() % 10)) * 0.12
		draw_circle(center, radius_pixels, Color(0.08, 1.0, 0.3, 0.14))
		draw_arc(center, radius_pixels * pulse, 0.0, TAU, 24, Color(0.16, 1.0, 0.38, 0.96), 1.8)
		draw_circle(center, 2.8, Color(0.7, 1.0, 0.76, 1.0))
		_draw_body_id(center, String(reward.name), Color(0.48, 1.0, 0.58))


func _draw_body_id(center: Vector2, body_id: String, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, center + Vector2(5.0, -5.0), body_id, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)


func _draw_destination(map_size: Vector2) -> void:
	var destination := Vector3(100.0, 100.0, 10.0)
	var arrival_radius := 3.0
	if _flight != null:
		var value: Variant = _flight.get("destination")
		if value is Vector3:
			destination = value
		var radius_value: Variant = _flight.get("arrival_radius")
		if radius_value != null:
			arrival_radius = float(radius_value)
	var center := _world_to_map(Vector2(destination.x, destination.y), map_size)
	var pixels_per_meter := minf(
		map_size.x / (map_max.x - map_min.x),
		map_size.y / (map_max.y - map_min.y)
	)
	var radius_pixels := maxf(4.0, arrival_radius * pixels_per_meter)
	var pulse := radius_pixels + 4.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
	draw_circle(center, radius_pixels, Color(0.12, 1.0, 0.4, 0.24))
	draw_arc(center, radius_pixels, 0.0, TAU, 32, Color(0.12, 1.0, 0.4, 0.95), 2.0)
	draw_circle(center, 4.0, Color(0.12, 1.0, 0.4, 0.9))
	draw_arc(center, pulse, 0.0, TAU, 24, Color(0.12, 1.0, 0.4, 0.8), 2.0)


func _draw_spacecraft(map_size: Vector2) -> void:
	if _flight == null:
		return
	var coordinates := _get_flight_coordinates()
	var center := _world_to_map(Vector2(coordinates.x, coordinates.y), map_size)
	if _flight.has_method("get_view_heading"):
		var heading: Vector2 = _flight.call("get_view_heading")
		if not heading.is_zero_approx():
			var screen_heading := Vector2(heading.x, -heading.y)
			var heading_end := center + screen_heading * 16.0
			draw_line(center, heading_end, Color(0.45, 0.95, 1.0, 0.95), 3.0)
			draw_circle(heading_end, 2.5, Color(0.72, 1.0, 1.0, 1.0))
	var gravity_value: Variant = _flight.get("gravity_acceleration")
	if gravity_value is Vector2 and gravity_value.length() > 0.01:
		var screen_gravity := Vector2(gravity_value.x, -gravity_value.y)
		var arrow_length := minf(28.0, 7.0 + gravity_value.length() * 5.0)
		var arrow_end := center + screen_gravity.normalized() * arrow_length
		draw_line(center, arrow_end, Color(1.0, 0.72, 0.12, 0.95), 3.0)
		draw_circle(arrow_end, 3.0, Color(1.0, 0.8, 0.22, 1.0))
	var ship_color := Color(1.0, 0.22, 0.16, 1.0) if int(_flight.get("state")) == 1 else Color(0.05, 0.78, 1.0, 1.0)
	draw_circle(center, 3.0, ship_color)
	draw_line(center + Vector2(-6, 0), center + Vector2(6, 0), Color(0.75, 0.95, 1.0), 1.5)
	draw_line(center + Vector2(0, -6), center + Vector2(0, 6), Color(0.75, 0.95, 1.0), 1.5)


func _draw_readout(map_size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var font_size := maxi(13, int(minf(map_size.x, map_size.y) * 0.045))
	var coordinate_text := "XY  --, --"
	var fuel_value := 0.0
	var maximum_fuel_value := 0.0
	var fuel_ratio := 0.0
	var flow_text := "FLOW  --"
	var rewards_text := "R --/--"
	if _flight != null:
		var coordinates := _get_flight_coordinates()
		coordinate_text = "XY  %.1f, %.1f" % [coordinates.x, coordinates.y]
		fuel_value = float(_flight.get("fuel"))
		maximum_fuel_value = float(_flight.get("maximum_fuel"))
		if _flight.has_method("get_fuel_ratio"):
			fuel_ratio = float(_flight.call("get_fuel_ratio"))
		if _flight.has_method("get_predicted_flow_result"):
			flow_text = "FLOW φ(t) · %s" % String(_flight.call("get_predicted_flow_result"))
		if _flight.has_method("get_rewards_collected") and _flight.has_method("get_total_reward_count"):
			rewards_text = "R %d/%d" % [
				int(_flight.call("get_rewards_collected")),
				int(_flight.call("get_total_reward_count")),
			]

	var readout_height := float(font_size + 10)
	var left_width := map_size.x * 0.52 - 9.0
	var right_x := map_size.x * 0.52 + 3.0
	var right_width := map_size.x - right_x - 6.0
	draw_rect(Rect2(6, 6, left_width, readout_height), Color(0.01, 0.02, 0.05, 0.86))
	draw_string(font, Vector2(12, font_size + 7), coordinate_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.76, 0.93, 1.0))

	var fuel_color := Color(0.2, 1.0, 0.5, 0.92)
	if fuel_ratio < 0.2:
		fuel_color = Color(1.0, 0.16, 0.12, 0.96)
	elif fuel_ratio < 0.5:
		fuel_color = Color(1.0, 0.72, 0.12, 0.95)
	var fuel_rect := Rect2(right_x, 6, right_width, readout_height)
	draw_rect(fuel_rect, Color(0.01, 0.02, 0.05, 0.9))
	draw_rect(
		Rect2(right_x + 2.0, 8.0, maxf(0.0, (right_width - 4.0) * fuel_ratio), readout_height - 4.0),
		Color(fuel_color.r, fuel_color.g, fuel_color.b, 0.24)
	)
	draw_string(
		font,
		Vector2(right_x + 6.0, font_size + 7),
		"FUEL %.0f/%.0f" % [fuel_value, maximum_fuel_value],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		fuel_color
	)

	var flow_result := ""
	if _flight != null and _flight.has_method("get_predicted_flow_result"):
		flow_result = String(_flight.call("get_predicted_flow_result"))
	var flow_color := Color(0.35, 0.86, 1.0, 0.95)
	if flow_result == "IMPACT":
		flow_color = Color(1.0, 0.28, 0.24, 0.98)
	elif flow_result == "GOAL":
		flow_color = Color(0.22, 1.0, 0.48, 0.98)
	var status_text := "%s · %s" % [rewards_text, flow_text]
	draw_rect(Rect2(6, map_size.y - font_size - 18.0, map_size.x - 48.0, font_size + 10.0), Color(0.01, 0.02, 0.05, 0.82))
	draw_string(font, Vector2(12, map_size.y - 10.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, flow_color)
	draw_string(font, Vector2(map_size.x - 32, map_size.y - 8), "X", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.45, 0.76, 1.0))
	draw_string(font, Vector2(8, font_size * 2.5), "Y", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.45, 0.76, 1.0))


func _world_to_map(world_position: Vector2, map_size: Vector2) -> Vector2:
	var normalized := (world_position - map_min) / (map_max - map_min)
	return Vector2(normalized.x * map_size.x, (1.0 - normalized.y) * map_size.y)


func _get_flight_coordinates() -> Vector3:
	if _flight != null and _flight.has_method("get_flight_coordinates"):
		return _flight.call("get_flight_coordinates") as Vector3
	if _flight != null:
		return Vector3(_flight.global_position.x, _flight.global_position.z, _flight.global_position.y)
	return Vector3.ZERO


func _find_scene_nodes() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_flight = scene.get_node_or_null("XROrigin3D") as Node3D
	_obstacles = scene.get_node_or_null("MoonExhibit") as Node3D
	_black_holes = scene.get_node_or_null("BlackHoleExhibit") as Node3D
	_rewards = scene.get_node_or_null("RewardPoints") as Node3D
