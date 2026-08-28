# =============================================================================
# flight_minimap.gd — the tactical map, drawn entirely with Control._draw()
# (no child nodes). Used in two places:
#   1. directly inside DesktopHUD (desktop mode), and
#   2. rendered into a texture on a head-locked quad by
#      vr_minimap_presenter.gd (headset mode).
#
# LOOK: neon sci-fi HUD — dark starfield plate, cyan grid, notched corner
# brackets, glowing bodies, and a fuel bar along the bottom. Colour carries
# meaning, not just mood:
#   cyan   = planet that still has beavers on it
#   green  = planet you have cleared (and the MIT destination)
#   red    = black hole, or a fuel figure you cannot currently afford
#
# TWO SIZES: squeeze the controller grip (or hold TAB on desktop) and the
# map expands — in VR the quad grows and swings in front of you, on desktop
# the panel doubles. Expanding also switches on per-planet info cards
# (beavers / distance / fuel needed), which are far too dense to show on the
# small map.
#
# It locates the world by ABSOLUTE node names in the current scene:
#   XROrigin3D (flight controller), MoonExhibit, BlackHoleExhibit,
#   BeaverExhibit. Rename those and the map silently goes blank. All body
#   data is read duck-typed (target_diameter_meters, capture_radius, ...),
#   the same contracts spaceship_flight.gd uses.
#
# GEOMETRY NOTE: the ship flies at a fixed altitude, so every body circle is
# a sphere's HORIZONTAL CROSS-SECTION at that altitude, not its full radius:
#   r_drawn = sqrt(R^2 - dz^2),  dz = |flight altitude - body centre height|.
# Screen Y is flipped when drawing because logical Y points up while pixels
# grow downward.
# =============================================================================
extends Control
class_name FlightMiniMap

@export var map_min := Vector2(-20.0, -20.0)
@export var map_max := Vector2(220.0, 220.0)

const COLOR_BACKDROP := Color(0.012, 0.035, 0.045, 0.96)
const COLOR_GRID := Color(0.15, 0.62, 0.6, 0.22)
const COLOR_FRAME := Color(0.25, 1.0, 0.72, 0.9)
const COLOR_ACTIVE := Color(0.25, 0.92, 1.0, 1.0)
const COLOR_CLEARED := Color(0.3, 1.0, 0.42, 1.0)
const COLOR_DANGER := Color(1.0, 0.24, 0.3, 1.0)
const COLOR_TEXT := Color(0.72, 0.98, 1.0, 1.0)
const COLOR_DIM := Color(0.45, 0.78, 0.82, 0.9)

## Flavour label for map distances. The underlying units are world metres.
const DISTANCE_UNIT := "ly"

var _flight: Node3D
var _obstacles: Node3D
var _black_holes: Node3D
var _beaver_director: Node3D
var _expanded := false
var _stars: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fixed star plate: generated once from a seeded RNG so the backdrop is
	# stable frame to frame instead of shimmering.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	for i in 90:
		_stars.append(Vector2(rng.randf(), rng.randf()))
	_find_scene_nodes()
	queue_redraw()


func _process(_delta: float) -> void:
	if _flight == null or _obstacles == null or _black_holes == null:
		_find_scene_nodes()
	if _flight != null and _flight.has_method("is_map_expanded"):
		_expanded = bool(_flight.call("is_map_expanded"))
	_sync_desktop_panel()
	queue_redraw()


## Desktop only: grow the HUD panel this map lives in. In VR the quad is
## scaled by vr_minimap_presenter.gd instead.
func _sync_desktop_panel() -> void:
	var panel := get_parent() as PanelContainer
	if panel == null or panel.name != &"MiniMapPanel":
		return
	var target_size := 620.0 if _expanded else 316.0
	var current := -panel.offset_left
	if absf(current - target_size) < 0.5:
		return
	var eased := lerpf(current, target_size, 0.25)
	panel.offset_left = -eased
	panel.offset_bottom = eased + 24.0
	custom_minimum_size = Vector2(eased - 36.0, eased - 36.0)


func _draw() -> void:
	var map_size := size
	if map_size.x < 2.0 or map_size.y < 2.0:
		return

	# The bottom strip is reserved for the fuel readout.
	var footer := 46.0 if _expanded else 30.0
	var plate := Vector2(map_size.x, map_size.y - footer)

	draw_rect(Rect2(Vector2.ZERO, map_size), COLOR_BACKDROP)
	_draw_stars(plate)
	_draw_grid(plate)
	_draw_predicted_flow(plate)
	_draw_black_holes(plate)
	_draw_obstacles(plate)
	_draw_destination(plate)
	if _expanded:
		_draw_info_cards(plate)
	# Last, so no info card can ever hide the player.
	_draw_spacecraft(plate)
	_draw_fuel_bar(map_size, footer)
	_draw_frame(map_size)


# --- backdrop ---------------------------------------------------------------

func _draw_stars(plate: Vector2) -> void:
	for star in _stars:
		var point := Vector2(star.x * plate.x, star.y * plate.y)
		# The fractional part doubles as a per-star brightness.
		var brightness := 0.25 + fmod(star.x * 37.0 + star.y * 91.0, 1.0) * 0.5
		draw_circle(point, 1.0, Color(0.75, 0.95, 1.0, brightness))


func _draw_grid(plate: Vector2) -> void:
	# Derive lines from the configured bounds so the grid follows play-area
	# changes; a wider pitch keeps big fields readable on a small map.
	var step := 20.0 if (map_max.x - map_min.x) <= 160.0 else 40.0
	var coordinate := ceilf(minf(map_min.x, map_min.y) / step) * step
	while coordinate <= maxf(map_max.x, map_max.y) + 0.01:
		var is_axis := is_zero_approx(coordinate)
		var color := Color(0.2, 0.85, 0.8, 0.4) if is_axis else COLOR_GRID
		var width := 1.5 if is_axis else 1.0
		draw_line(
			_world_to_map(Vector2(coordinate, map_min.y), plate),
			_world_to_map(Vector2(coordinate, map_max.y), plate),
			color,
			width
		)
		draw_line(
			_world_to_map(Vector2(map_min.x, coordinate), plate),
			_world_to_map(Vector2(map_max.x, coordinate), plate),
			color,
			width
		)
		coordinate += step


## Neon border with cut corner brackets and edge ticks.
func _draw_frame(map_size: Vector2) -> void:
	var inset := 3.0
	var rect := Rect2(Vector2(inset, inset), map_size - Vector2(inset, inset) * 2.0)
	draw_rect(rect, Color(COLOR_FRAME, 0.35), false, 1.0)

	var arm := minf(34.0, minf(map_size.x, map_size.y) * 0.12)
	var corners := [
		[rect.position, Vector2(1, 0), Vector2(0, 1)],
		[rect.position + Vector2(rect.size.x, 0), Vector2(-1, 0), Vector2(0, 1)],
		[rect.position + Vector2(0, rect.size.y), Vector2(1, 0), Vector2(0, -1)],
		[rect.position + rect.size, Vector2(-1, 0), Vector2(0, -1)],
	]
	for corner in corners:
		var origin: Vector2 = corner[0]
		draw_line(origin, origin + (corner[1] as Vector2) * arm, COLOR_FRAME, 2.5)
		draw_line(origin, origin + (corner[2] as Vector2) * arm, COLOR_FRAME, 2.5)

	# Dashed ticks along the top and bottom edges.
	var ticks := 26
	for i in ticks:
		if i % 3 == 0:
			continue
		var x := rect.position.x + rect.size.x * float(i) / float(ticks - 1)
		draw_line(Vector2(x, inset), Vector2(x, inset + 5.0), Color(COLOR_FRAME, 0.5), 1.0)


# --- bodies -----------------------------------------------------------------

## Soft neon disc: a filled core plus a few fading rings.
func _draw_glow_body(centre: Vector2, radius: float, color: Color) -> void:
	for i in 3:
		var ring := radius * (1.0 + 0.28 * float(i + 1))
		draw_circle(centre, ring, Color(color, 0.06 - 0.015 * float(i)))
	draw_circle(centre, radius, Color(color, 0.22))
	draw_arc(centre, radius, 0.0, TAU, 40, color, 2.0)


func _draw_obstacles(plate: Vector2) -> void:
	if _obstacles == null:
		return
	var pixels_per_meter := _pixels_per_meter(plate)
	for child in _obstacles.get_children():
		var obstacle := child as Node3D
		if obstacle == null:
			continue
		var diameter: Variant = obstacle.get("target_diameter_meters")
		if diameter == null:
			continue
		var planet_radius := float(diameter) * 0.5
		var vertical_distance := absf(_flight_altitude() - obstacle.global_position.y)
		var visual_radius_squared := planet_radius ** 2.0 - vertical_distance ** 2.0
		var centre := _world_to_map(
			Vector2(obstacle.global_position.x, obstacle.global_position.z),
			plate
		)
		var remaining := _beavers_left(obstacle)
		var color := COLOR_ACTIVE if remaining > 0 else COLOR_CLEARED
		if visual_radius_squared > 0.0:
			_draw_glow_body(centre, sqrt(visual_radius_squared) * pixels_per_meter, color)
		else:
			_draw_glow_body(centre, 3.0, color)

		var label := "P" + String(obstacle.name).trim_prefix("Planet")
		_draw_label(centre + Vector2(6.0, -6.0), label, Color(color, 0.95), 10)
		if _beaver_total_for(obstacle) > 0 and not _expanded:
			_draw_label(
				centre + Vector2(6.0, 6.0),
				"%d/%d" % [remaining, _beaver_total_for(obstacle)],
				Color(1.0, 0.78, 0.3) if remaining > 0 else COLOR_CLEARED,
				10
			)


func _draw_black_holes(plate: Vector2) -> void:
	if _black_holes == null:
		return
	var pixels_per_meter := _pixels_per_meter(plate)
	var flight_altitude := _flight_altitude()
	var spacecraft_radius := 0.25
	if _flight != null:
		spacecraft_radius = float(_flight.get("spacecraft_radius"))

	for child in _black_holes.get_children():
		var black_hole := child as Node3D
		if black_hole == null:
			continue
		var centre := _world_to_map(
			Vector2(black_hole.global_position.x, black_hole.global_position.z),
			plate
		)
		var capture_radius := float(black_hole.get("capture_radius"))
		var mu := float(black_hole.get("gravitational_parameter_mu"))
		var softening := float(black_hole.get("gravity_softening_length"))
		var vertical_distance := absf(flight_altitude - black_hole.global_position.y)

		# Ring where pull ~= 1 m/s^2: mu / (d^2 + s^2) = 1  =>  d^2 = mu - s^2,
		# then reduced to the cross-section at our flight altitude.
		var influence_radius_squared := mu - softening * softening - vertical_distance * vertical_distance
		if influence_radius_squared > 0.0:
			draw_arc(
				centre,
				sqrt(influence_radius_squared) * pixels_per_meter,
				0.0,
				TAU,
				48,
				Color(COLOR_DANGER, 0.22),
				1.2
			)
		var collision_radius := capture_radius + spacecraft_radius
		var collision_radius_squared := collision_radius ** 2.0 - vertical_distance ** 2.0
		if collision_radius_squared > 0.0:
			var capture_pixels := sqrt(collision_radius_squared) * pixels_per_meter
			draw_circle(centre, capture_pixels, Color(0.0, 0.0, 0.02, 1.0))
			draw_arc(centre, capture_pixels, 0.0, TAU, 32, COLOR_DANGER, 2.0)
			draw_arc(centre, capture_pixels * 1.35, 0.0, TAU, 32, Color(COLOR_DANGER, 0.3), 1.0)
		_draw_label(
			centre + Vector2(6.0, -6.0),
			"B" + String(black_hole.name).trim_prefix("BlackHole"),
			Color(1.0, 0.5, 0.55),
			10
		)


func _draw_destination(plate: Vector2) -> void:
	var destination := Vector3(200.0, 200.0, 10.0)
	var arrival_radius := 3.0
	if _flight != null:
		var value: Variant = _flight.get("destination")
		if value is Vector3:
			destination = value
		var radius_value: Variant = _flight.get("arrival_radius")
		if radius_value != null:
			arrival_radius = float(radius_value)
	var centre := _world_to_map(Vector2(destination.x, destination.y), plate)
	var radius_pixels := maxf(5.0, arrival_radius * _pixels_per_meter(plate))
	var pulse := radius_pixels + 5.0 + sin(Time.get_ticks_msec() * 0.006) * 2.5
	# Layered halo so the destination glows rather than sitting flat.
	for i in 4:
		draw_circle(
			centre,
			radius_pixels * (1.6 + 0.75 * float(i)),
			Color(0.75, 1.0, 0.85, 0.05 - 0.008 * float(i))
		)
	draw_circle(centre, radius_pixels * 1.3, Color(0.85, 1.0, 0.9, 0.16))
	draw_circle(centre, radius_pixels, Color(COLOR_CLEARED, 0.22))
	draw_arc(centre, radius_pixels, 0.0, TAU, 32, COLOR_CLEARED, 2.0)
	draw_arc(centre, pulse, 0.0, TAU, 24, Color(COLOR_CLEARED, 0.55), 1.5)
	# Cross-hair marks the delivery point.
	draw_line(centre - Vector2(radius_pixels + 6.0, 0), centre - Vector2(radius_pixels + 1.0, 0), COLOR_CLEARED, 1.5)
	draw_line(centre + Vector2(radius_pixels + 1.0, 0), centre + Vector2(radius_pixels + 6.0, 0), COLOR_CLEARED, 1.5)
	_draw_label(centre + Vector2(8.0, -8.0), "MIT", COLOR_CLEARED, 11)


func _draw_predicted_flow(plate: Vector2) -> void:
	if _flight == null or not _flight.has_method("get_predicted_flow_points"):
		return
	var flow_points: PackedVector2Array = _flight.call("get_predicted_flow_points")
	if flow_points.size() < 2:
		return

	var map_points := PackedVector2Array()
	for point in flow_points:
		map_points.append(_world_to_map(point, plate))

	var flow_result := "SAFE"
	if _flight.has_method("get_predicted_flow_result"):
		flow_result = String(_flight.call("get_predicted_flow_result"))
	var flow_color := COLOR_ACTIVE
	match flow_result:
		"IMPACT":
			flow_color = COLOR_DANGER
		"GOAL":
			flow_color = COLOR_CLEARED
		"LANDED":
			flow_color = Color(1.0, 0.72, 0.2, 0.95)
		"STOPPED":
			flow_color = Color(0.58, 0.64, 0.72, 0.78)

	# A dark underlay keeps the ODE flow visible across grid lines and bodies.
	draw_polyline(map_points, Color(0.0, 0.02, 0.03, 0.9), 5.0, true)
	draw_polyline(map_points, flow_color, 2.0, true)
	draw_circle(map_points[map_points.size() - 1], 3.0, flow_color)


func _draw_spacecraft(plate: Vector2) -> void:
	if _flight == null:
		return
	var coordinates := _get_flight_coordinates()
	var centre := _world_to_map(Vector2(coordinates.x, coordinates.y), plate)
	if _flight.has_method("get_view_heading"):
		var heading: Vector2 = _flight.call("get_view_heading")
		if not heading.is_zero_approx():
			var screen_heading := Vector2(heading.x, -heading.y)
			var tip := centre + screen_heading * 17.0
			draw_line(centre, tip, Color(0.55, 1.0, 1.0, 0.95), 3.0)
			draw_circle(tip, 2.5, Color(0.8, 1.0, 1.0))
	var gravity_value: Variant = _flight.get("gravity_acceleration")
	if gravity_value is Vector2 and gravity_value.length() > 0.01:
		var screen_gravity := Vector2(gravity_value.x, -gravity_value.y)
		var arrow_length := minf(28.0, 7.0 + gravity_value.length() * 5.0)
		var arrow_end := centre + screen_gravity.normalized() * arrow_length
		draw_line(centre, arrow_end, Color(1.0, 0.72, 0.12, 0.95), 2.5)
		draw_circle(arrow_end, 3.0, Color(1.0, 0.8, 0.22, 1.0))

	var flight_state := int(_flight.get("state"))
	var ship_color := COLOR_ACTIVE
	if flight_state == 1:  # CRASHED
		ship_color = COLOR_DANGER
	elif flight_state == 4:  # LANDED (appended last in FlightState)
		ship_color = Color(1.0, 0.72, 0.2, 1.0)
	draw_circle(centre, 4.0, ship_color)
	draw_arc(centre, 8.0, 0.0, TAU, 20, Color(ship_color, 0.55), 1.5)


# --- readouts ---------------------------------------------------------------

## Expanded mode only: cards for the nearest planets that still hold beavers,
## matching the reference HUD (beavers / distance / fuel needed).
func _draw_info_cards(plate: Vector2) -> void:
	if _obstacles == null or _flight == null:
		return
	var ship := _get_flight_coordinates()
	var ship_2d := Vector2(ship.x, ship.y)

	var candidates: Array = []
	for child in _obstacles.get_children():
		var planet := child as Node3D
		if planet == null or planet.get("target_diameter_meters") == null:
			continue
		var planet_2d := Vector2(planet.global_position.x, planet.global_position.z)
		candidates.append({
			"planet": planet,
			"distance": ship_2d.distance_to(planet_2d),
			"remaining": _beavers_left(planet),
		})
	candidates.sort_custom(func(a, b): return a["distance"] < b["distance"])

	var fuel_left := _fuel_percent()
	var placed: Array[Rect2] = []
	var shown := 0
	for entry in candidates:
		if shown >= 4:
			break
		if int(entry["remaining"]) <= 0:
			continue  # cleared planets do not need a card
		shown += 1
		var planet: Node3D = entry["planet"]
		var distance: float = entry["distance"]
		var needed := _fuel_percent_needed(distance)
		var centre := _world_to_map(
			Vector2(planet.global_position.x, planet.global_position.z),
			plate
		)
		var lines := [
			"%d/%d Beavers" % [int(entry["remaining"]), _beaver_total_for(planet)],
			"Distance: %.1f %s" % [distance, DISTANCE_UNIT],
			"Fuel: %d%%" % int(round(needed)),
		]
		# Requirements you cannot currently afford turn red, exactly as in
		# the reference HUD.
		var colors := [
			COLOR_TEXT,
			COLOR_DIM,
			COLOR_DANGER if needed > fuel_left else COLOR_ACTIVE,
		]
		placed.append(_draw_card(centre, lines, colors, plate, placed))


## Draws one card and returns the rect it occupied, so later cards can
## avoid it — with real planet positions, several cards routinely want the
## same patch of screen.
func _draw_card(
	anchor: Vector2,
	lines: Array,
	colors: Array,
	plate: Vector2,
	placed: Array[Rect2]
) -> Rect2:
	var font := ThemeDB.fallback_font
	var font_size := 12
	var padding := 7.0
	var line_height := float(font_size) + 4.0
	var width := 0.0
	for line in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x)
	var card := Vector2(width + padding * 2.0, line_height * lines.size() + padding * 2.0)

	# Sit the card beside its planet, flipped/clamped to stay on the plate.
	var origin := anchor + Vector2(14.0, -card.y * 0.5)
	if origin.x + card.x > plate.x - 4.0:
		origin.x = anchor.x - 14.0 - card.x
	origin.x = clampf(origin.x, 4.0, maxf(4.0, plate.x - card.x - 4.0))
	origin.y = clampf(origin.y, 4.0, maxf(4.0, plate.y - card.y - 4.0))

	# Slide clear of cards already on screen: try downward first, then
	# upward if we would fall off the plate.
	var gap := 5.0
	for attempt in 12:
		var overlapped := false
		for taken in placed:
			if taken.grow(gap).intersects(Rect2(origin, card)):
				var below := taken.position.y + taken.size.y + gap
				var above := taken.position.y - card.y - gap
				origin.y = below if below + card.y <= plate.y - 4.0 else above
				origin.y = clampf(origin.y, 4.0, maxf(4.0, plate.y - card.y - 4.0))
				overlapped = true
				break
		if not overlapped:
			break

	# Notched-corner panel, drawn as a polygon.
	var notch := 7.0
	var points := PackedVector2Array([
		origin + Vector2(notch, 0),
		origin + Vector2(card.x - notch, 0),
		origin + Vector2(card.x, notch),
		origin + Vector2(card.x, card.y - notch),
		origin + Vector2(card.x - notch, card.y),
		origin + Vector2(notch, card.y),
		origin + Vector2(0, card.y - notch),
		origin + Vector2(0, notch),
	])
	draw_colored_polygon(points, Color(0.01, 0.06, 0.07, 0.92))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(COLOR_ACTIVE, 0.75), 1.5)

	# Leader line from the planet to the card.
	draw_line(anchor, Vector2(origin.x, origin.y + card.y * 0.5), Color(COLOR_ACTIVE, 0.4), 1.0)

	for i in lines.size():
		draw_string(
			font,
			origin + Vector2(padding, padding + line_height * float(i + 1) - 4.0),
			lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			colors[i]
		)
	return Rect2(origin, card)


func _draw_fuel_bar(map_size: Vector2, footer: float) -> void:
	var font := ThemeDB.fallback_font
	var top := map_size.y - footer + 2.0
	var font_size := 13 if _expanded else 11
	var margin := 10.0
	var fuel_left := _fuel_percent()

	draw_rect(
		Rect2(margin, top, map_size.x - margin * 2.0, footer - 8.0),
		Color(0.01, 0.06, 0.07, 0.9)
	)
	draw_rect(
		Rect2(margin, top, map_size.x - margin * 2.0, footer - 8.0),
		Color(COLOR_FRAME, 0.5),
		false,
		1.0
	)

	var label := "SPACECRAFT FUEL"
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var bar_left := margin + 12.0 + (label_width + 10.0 if _expanded else 0.0)
	var big_width := 58.0 if _expanded else 40.0
	var bar := Rect2(
		bar_left,
		top + 8.0,
		maxf(20.0, map_size.x - margin - bar_left - big_width - 16.0),
		footer - 22.0
	)
	if _expanded:
		draw_string(
			font,
			Vector2(margin + 12.0, top + footer * 0.5 + 2.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			COLOR_TEXT
		)

	var fill_color := COLOR_ACTIVE
	if fuel_left < 20.0:
		fill_color = COLOR_DANGER
	elif fuel_left < 45.0:
		fill_color = Color(1.0, 0.72, 0.2)
	draw_rect(bar, Color(0.03, 0.14, 0.16, 0.9))
	draw_rect(
		Rect2(bar.position, Vector2(bar.size.x * clampf(fuel_left / 100.0, 0.0, 1.0), bar.size.y)),
		Color(fill_color, 0.75)
	)
	draw_rect(bar, Color(fill_color, 0.8), false, 1.0)
	draw_string(
		font,
		Vector2(bar.position.x + bar.size.x + 8.0, top + footer * 0.5 + 3.0),
		"%d%%" % int(round(fuel_left)),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size + (5 if _expanded else 1),
		fill_color
	)

	# Mission tally and the position readout ride above the bar.
	var header_y := top - 6.0
	if _beaver_director != null and _beaver_director.has_method("get_total_count"):
		draw_string(
			font,
			Vector2(margin + 2.0, header_y),
			"BVR %d/%d  CARGO %d" % [
				int(_beaver_director.call("get_delivered_count")),
				int(_beaver_director.call("get_total_count")),
				int(_beaver_director.call("get_cargo_count")),
			],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			Color(1.0, 0.78, 0.35)
		)
	if _flight != null:
		var coordinates := _get_flight_coordinates()
		draw_string(
			font,
			Vector2(map_size.x - margin - 108.0, header_y),
			"XY %.0f, %.0f" % [coordinates.x, coordinates.y],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size,
			COLOR_DIM
		)
	if not _expanded:
		draw_string(
			font,
			Vector2(margin + 2.0, header_y - float(font_size) - 2.0),
			"SQUEEZE / TAB — EXPAND",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			font_size - 1,
			Color(COLOR_FRAME, 0.55)
		)


func _draw_label(at: Vector2, text: String, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


# --- helpers ----------------------------------------------------------------

func _pixels_per_meter(plate: Vector2) -> float:
	return minf(
		plate.x / (map_max.x - map_min.x),
		plate.y / (map_max.y - map_min.y)
	)


## Always the flight plane, never the walker's live height: these circles
## show where you can collide while FLYING.
func _flight_altitude() -> float:
	if _flight != null:
		var start: Variant = _flight.get("start_position")
		if start is Vector3:
			return start.z
	return 10.0


func _beavers_left(planet: Node3D) -> int:
	if _beaver_director == null or not _beaver_director.has_method("get_planet_beaver_count"):
		return 0
	return int(_beaver_director.call("get_planet_beaver_count", planet))


func _beaver_total_for(_planet: Node3D) -> int:
	if _beaver_director == null:
		return 0
	var per_planet: Variant = _beaver_director.get("beavers_per_planet")
	return int(per_planet) if per_planet != null else 0


func _fuel_percent() -> float:
	if _flight == null:
		return 0.0
	var maximum := float(_flight.get("maximum_fuel"))
	if maximum <= 0.0:
		return 0.0
	return clampf(float(_flight.get("fuel")) / maximum * 100.0, 0.0, 100.0)


## Rough cost of flying `distance` at cruise: time on thrust times burn rate,
## as a percentage of a full tank. Deliberately pessimistic — it ignores any
## help you get from gravity, so the number is a floor, not a promise.
func _fuel_percent_needed(distance: float) -> float:
	if _flight == null:
		return 0.0
	var cruise := maxf(float(_flight.get("flight_speed")), 0.001)
	var burn := float(_flight.get("fuel_burn_per_second"))
	var maximum := maxf(float(_flight.get("maximum_fuel")), 0.001)
	return distance / cruise * burn / maximum * 100.0


func _world_to_map(world_position: Vector2, plate: Vector2) -> Vector2:
	var normalized := (world_position - map_min) / (map_max - map_min)
	return Vector2(normalized.x * plate.x, (1.0 - normalized.y) * plate.y)


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
	_beaver_director = scene.get_node_or_null("BeaverExhibit") as Node3D
