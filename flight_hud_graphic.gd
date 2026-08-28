# =============================================================================
# flight_hud_graphic.gd — the in-headset status display, drawn as GAUGES
# rather than a wall of text. Replaces the old FlightHUD Label3D, which put
# three lines of numbers across the bottom of your view.
#
# Everything here is read straight off SpacecraftFlightController by duck
# typing (the same approach flight_minimap.gd uses), so this Control can be
# dropped into any viewport without wiring.
#
# Layout, left to right:
#   * beaver vessel   — a beaver silhouette that FILLS from the feet up as
#                       you collect them, the way the reference mock does
#   * BEAVERS COLLECTED n/m
#   * SPACECRAFT FUEL — segmented bar plus a large percentage
#   * speed bar       — fills toward the landing threshold; green while slow
#                       enough to land, red once a touchdown would be fatal
#   * state lamp      — cyan flying / amber landed / red crashed / green won
#   * warning chevrons— only when the controller reports an impact warning
#
# Rendered to a texture on a head-locked quad by vr_hud_presenter.gd.
# =============================================================================
extends Control
class_name FlightHUDGraphic

const COLOR_FLYING := Color(0.25, 0.92, 1.0)
const COLOR_LANDED := Color(1.0, 0.72, 0.2)
const COLOR_CRASHED := Color(1.0, 0.26, 0.3)
const COLOR_WON := Color(0.3, 1.0, 0.45)
const COLOR_PANEL := Color(0.01, 0.05, 0.07, 0.72)
const COLOR_FRAME := Color(0.25, 1.0, 0.72, 0.55)

# FlightState ordinals from spaceship_flight.gd (LANDED is appended last).
const STATE_FLYING := 0
const STATE_CRASHED := 1
const STATE_ARRIVED := 2
const STATE_WAITING := 3
const STATE_LANDED := 4

var _flight: Node3D
var _beaver_director: Node3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_scene_nodes()


func _process(_delta: float) -> void:
	if _flight == null:
		_find_scene_nodes()
	queue_redraw()


func _draw() -> void:
	if size.x < 10.0 or size.y < 10.0 or _flight == null:
		return

	var state := int(_flight.get("state"))
	var accent := _state_color(state)
	var warning := String(_flight.get("_impact_warning"))

	# Backing plate with cut corners.
	var plate := Rect2(Vector2(4, 4), size - Vector2(8, 8))
	draw_rect(plate, COLOR_PANEL)
	draw_rect(plate, Color(COLOR_FRAME, 0.5), false, 1.5)

	var font := ThemeDB.fallback_font
	var centre_y := size.y * 0.5
	var cursor := 20.0

	# 1. The filling beaver, the centrepiece of the reference UI.
	_draw_beaver_vessel(Rect2(cursor, centre_y - 40.0, 66.0, 80.0))
	cursor += 82.0

	# 2. Collected tally.
	var collected := 0
	var total := 0
	if _beaver_director != null and _beaver_director.has_method("get_total_count"):
		total = int(_beaver_director.call("get_total_count"))
		collected = int(_beaver_director.call("get_delivered_count")) \
			+ int(_beaver_director.call("get_cargo_count"))
	draw_string(
		font,
		Vector2(cursor, centre_y - 14.0),
		"BEAVERS COLLECTED",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.55, 0.95, 1.0)
	)
	draw_string(
		font,
		Vector2(cursor, centre_y + 16.0),
		"%d/%d" % [collected, total],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, COLOR_FLYING
	)
	cursor += 210.0

	# 3. Segmented fuel bar + big percentage.
	_draw_segmented_fuel(Rect2(cursor, centre_y - 26.0, 250.0, 52.0))
	cursor += 268.0

	# 4. Approach speed against the landing limit.
	_draw_speed_bar(Rect2(cursor, centre_y - 13.0, 118.0, 26.0))
	cursor += 134.0

	_draw_state_lamp(Vector2(cursor + 18.0, centre_y), accent, state)

	if not warning.is_empty():
		_draw_warning()


## Filled circle whose colour alone tells you what the ship is doing; a ring
## of ticks around it pulses while you are waiting to start.
func _draw_state_lamp(centre: Vector2, accent: Color, state: int) -> void:
	draw_circle(centre, 15.0, Color(accent, 0.16))
	draw_arc(centre, 15.0, 0.0, TAU, 28, accent, 2.5)
	if state == STATE_WAITING:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		draw_circle(centre, 5.0 + pulse * 3.0, Color(accent, 0.5 + pulse * 0.5))
	elif state == STATE_LANDED:
		# Three "legs" — a landed lander.
		for i in 3:
			var angle := TAU * float(i) / 3.0 - PI * 0.5
			draw_line(centre, centre + Vector2(cos(angle), sin(angle)) * 9.0, accent, 2.5)
	elif state == STATE_CRASHED:
		draw_line(centre - Vector2(6, 6), centre + Vector2(6, 6), accent, 3.0)
		draw_line(centre - Vector2(6, -6), centre + Vector2(6, -6), accent, 3.0)
	elif state == STATE_ARRIVED:
		draw_line(centre + Vector2(-6, 0), centre + Vector2(-2, 5), accent, 3.0)
		draw_line(centre + Vector2(-2, 5), centre + Vector2(7, -6), accent, 3.0)
	else:
		draw_circle(centre, 5.0, accent)


## Beaver silhouette that fills from the feet up with collection progress:
## a hollow neon outline that becomes solid as the hold fills.
func _draw_beaver_vessel(rect: Rect2) -> void:
	var ratio := 0.0
	if _beaver_director != null and _beaver_director.has_method("get_total_count"):
		var total := maxi(int(_beaver_director.call("get_total_count")), 1)
		var have := int(_beaver_director.call("get_delivered_count")) \
			+ int(_beaver_director.call("get_cargo_count"))
		ratio = clampf(float(have) / float(total), 0.0, 1.0)

	var outline := _beaver_outline(rect)

	# Fill portion: clip the silhouette to the bottom `ratio` of its height
	# by intersecting the polygon with a rising waterline.
	if ratio > 0.001:
		var waterline := rect.position.y + rect.size.y * (1.0 - ratio)
		var filled := PackedVector2Array()
		for i in outline.size():
			var current := outline[i]
			var next := outline[(i + 1) % outline.size()]
			if current.y >= waterline:
				filled.append(current)
			# Cross the waterline: insert the exact intersection point so
			# the fill edge is flat rather than stepped.
			if (current.y >= waterline) != (next.y >= waterline):
				var t := (waterline - current.y) / (next.y - current.y)
				filled.append(current.lerp(next, t))
		if filled.size() >= 3:
			draw_colored_polygon(filled, Color(0.3, 0.95, 1.0, 0.55))

	var loop := outline.duplicate()
	loop.append(outline[0])
	draw_polyline(loop, Color(1.0, 0.3, 0.32, 0.95), 2.0)


## Chunky beaver profile (head, ear, muzzle, body, tail) as a polygon in
## the given rect. Deliberately simple so it reads at HUD scale.
func _beaver_outline(rect: Rect2) -> PackedVector2Array:
	var unit := PackedVector2Array([
		Vector2(0.46, 0.02), Vector2(0.62, 0.06), Vector2(0.72, 0.17),
		Vector2(0.74, 0.28), Vector2(0.88, 0.33), Vector2(0.95, 0.42),
		Vector2(0.86, 0.47), Vector2(0.74, 0.45), Vector2(0.78, 0.60),
		Vector2(0.86, 0.78), Vector2(0.80, 0.95), Vector2(0.55, 1.0),
		Vector2(0.28, 0.98), Vector2(0.14, 0.86), Vector2(0.10, 0.66),
		Vector2(0.18, 0.48), Vector2(0.26, 0.30), Vector2(0.22, 0.16),
		Vector2(0.32, 0.10),
	])
	var points := PackedVector2Array()
	for p in unit:
		points.append(rect.position + Vector2(p.x * rect.size.x, p.y * rect.size.y))
	return points


## Segmented bar + large percentage, matching the reference readout.
func _draw_segmented_fuel(rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var maximum := maxf(float(_flight.get("maximum_fuel")), 0.001)
	var ratio := clampf(float(_flight.get("fuel")) / maximum, 0.0, 1.0)
	var color := COLOR_FLYING
	if ratio < 0.2:
		color = COLOR_CRASHED
	elif ratio < 0.45:
		color = COLOR_LANDED

	draw_string(
		font, rect.position + Vector2(0.0, 12.0), "SPACECRAFT FUEL",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.55, 0.95, 1.0)
	)

	var bar := Rect2(rect.position + Vector2(0.0, 22.0), Vector2(rect.size.x - 74.0, 24.0))
	draw_rect(bar, Color(0.02, 0.1, 0.14, 0.9))
	draw_rect(bar, Color(color, 0.7), false, 1.5)

	# 18 discrete cells rather than a smooth fill.
	var cells := 18
	var cell_width := (bar.size.x - 6.0) / float(cells)
	var lit := int(round(ratio * float(cells)))
	for i in cells:
		var cell := Rect2(
			bar.position + Vector2(3.0 + float(i) * cell_width, 3.0),
			Vector2(cell_width - 2.0, bar.size.y - 6.0)
		)
		draw_rect(cell, Color(color, 0.9) if i < lit else Color(0.1, 0.3, 0.36, 0.5))

	draw_string(
		font, rect.position + Vector2(rect.size.x - 66.0, 44.0),
		"%d%%" % int(round(ratio * 100.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, color
	)


## Sweeping arc gauge: full ring = full tank.
func _draw_fuel_arc(centre: Vector2) -> void:
	var maximum := maxf(float(_flight.get("maximum_fuel")), 0.001)
	var ratio := clampf(float(_flight.get("fuel")) / maximum, 0.0, 1.0)
	var color := COLOR_FLYING
	if ratio < 0.2:
		color = COLOR_CRASHED
	elif ratio < 0.45:
		color = COLOR_LANDED

	var start := PI * 0.75
	var sweep := PI * 1.5
	draw_arc(centre, 19.0, start, start + sweep, 40, Color(0.2, 0.4, 0.5, 0.6), 6.0)
	if ratio > 0.001:
		draw_arc(centre, 19.0, start, start + sweep * ratio, 40, color, 6.0)
	# Droplet mark in the middle reads as "fuel" without a caption.
	draw_circle(centre + Vector2(0, 2.0), 4.0, Color(color, 0.9))
	draw_line(centre + Vector2(0, -6.0), centre + Vector2(0, 0.0), Color(color, 0.9), 2.5)


## Bar that fills toward the landing-speed limit. Green means you can land
## right now; red means a touchdown at this speed kills you.
func _draw_speed_bar(rect: Rect2) -> void:
	var velocity: Variant = _flight.get("velocity")
	var speed := 0.0
	if velocity is Vector2:
		speed = velocity.length()
	var limit := maxf(float(_flight.get("landing_speed_threshold")), 0.001)
	var ratio := clampf(speed / (limit * 2.0), 0.0, 1.0)
	var safe := speed <= limit

	draw_rect(rect, Color(0.03, 0.12, 0.16, 0.85))
	draw_rect(
		Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y)),
		Color(COLOR_WON if safe else COLOR_CRASHED, 0.75)
	)
	draw_rect(rect, Color(COLOR_FRAME, 0.6), false, 1.5)
	# Tick at the landing threshold — the line you must be under to land.
	var mark := rect.position.x + rect.size.x * 0.5
	draw_line(
		Vector2(mark, rect.position.y - 4.0),
		Vector2(mark, rect.position.y + rect.size.y + 4.0),
		Color(1.0, 1.0, 1.0, 0.85),
		2.0
	)
	# Chevrons pointing right = "speed".
	for i in 3:
		var x := rect.position.x + 8.0 + float(i) * 9.0
		var y := rect.position.y + rect.size.y * 0.5
		draw_line(Vector2(x, y - 5.0), Vector2(x + 5.0, y), Color(1, 1, 1, 0.35), 2.0)
		draw_line(Vector2(x + 5.0, y), Vector2(x, y + 5.0), Color(1, 1, 1, 0.35), 2.0)


## Impact alarm: hazard bars along the top and bottom of the strip.
func _draw_warning() -> void:
	var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
	var color := Color(COLOR_CRASHED, blink)
	draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), color, false, 4.0)
	for i in 7:
		var x := size.x * 0.5 + (float(i) - 3.0) * 22.0
		var top := 12.0
		draw_line(Vector2(x, top), Vector2(x + 9.0, top + 9.0), color, 3.0)
		draw_line(Vector2(x + 9.0, top + 9.0), Vector2(x, top + 18.0), color, 3.0)


func _state_color(state: int) -> Color:
	match state:
		STATE_CRASHED:
			return COLOR_CRASHED
		STATE_ARRIVED:
			return COLOR_WON
		STATE_LANDED:
			return COLOR_LANDED
		STATE_WAITING:
			return COLOR_WON
		_:
			return COLOR_FLYING


func _find_scene_nodes() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_flight = scene.get_node_or_null("XROrigin3D") as Node3D
	_beaver_director = scene.get_node_or_null("BeaverExhibit") as Node3D
