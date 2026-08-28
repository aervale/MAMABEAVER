# =============================================================================
# mission_results.gd — shared victory/settlement screen for desktop and XR.
#
# This Control draws only while SpacecraftFlightController is ARRIVED. The
# desktop scene places it over the CanvasLayer; vr_hud_presenter.gd renders a
# second instance into a head-locked SubViewport. Both therefore use exactly
# the same score, wording and visual hierarchy.
#
# Score contract (implemented by spaceship_flight.gd):
#   delivered beavers * 1000 + remaining-fuel bonus (maximum 5000).
# =============================================================================
extends Control
class_name MissionResults

const STATE_ARRIVED := 2
const TITLE := "VICTORY!"
const CYAN := Color(0.25, 0.94, 1.0)
const GREEN := Color(0.4, 1.0, 0.5)
const GOLD := Color(1.0, 0.78, 0.25)
const PANEL := Color(0.015, 0.045, 0.075, 0.97)

var _flight: Node3D
var _director: Node3D
var _reveal := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_scene_nodes()


func _process(delta: float) -> void:
	if _flight == null:
		_find_scene_nodes()
	if is_showing():
		_reveal = minf(_reveal + delta * 2.4, 1.0)
	else:
		_reveal = 0.0
	queue_redraw()


func is_showing() -> bool:
	return _flight != null and int(_flight.get("state")) == STATE_ARRIVED


func get_title() -> String:
	return TITLE


func _draw() -> void:
	if not is_showing() or size.x < 320.0 or size.y < 240.0:
		return
	var eased := 1.0 - pow(1.0 - _reveal, 3.0)
	var alpha := clampf(eased, 0.0, 1.0)
	var font := ThemeDB.fallback_font

	# A dark veil makes the result legible over any planet or starfield while
	# preserving a little of the final destination behind it.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.015, 0.035, 0.78 * alpha))
	var panel_size := Vector2(
		minf(900.0, size.x - 44.0),
		minf(600.0, size.y - 44.0)
	) * lerpf(0.94, 1.0, eased)
	var panel := Rect2((size - panel_size) * 0.5, panel_size)
	draw_rect(panel.grow(12.0), Color(0.1, 0.9, 1.0, 0.09 * alpha))
	draw_rect(panel, Color(PANEL, alpha))
	draw_rect(panel, Color(CYAN, 0.8 * alpha), false, 3.0)
	_draw_corner_marks(panel, alpha)
	_draw_confetti(panel, alpha)

	var top := panel.position.y + 70.0
	draw_string(
		font, Vector2(panel.position.x, top), TITLE,
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 58,
		Color(GREEN, alpha)
	)
	draw_string(
		font, Vector2(panel.position.x, top + 39.0), "MISSION COMPLETE · MIT REACHED",
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 19,
		Color(CYAN, 0.88 * alpha)
	)
	draw_line(
		Vector2(panel.position.x + 70.0, top + 65.0),
		Vector2(panel.end.x - 70.0, top + 65.0),
		Color(CYAN, 0.45 * alpha), 2.0
	)

	var delivered := _delivered_count()
	var fuel_percent := _fuel_percent()
	var rank := _result_rank()
	var cards_y := top + 92.0
	var card_gap := 16.0
	var card_width := (panel.size.x - 140.0 - card_gap * 2.0) / 3.0
	var cards_x := panel.position.x + 70.0
	_draw_stat_card(
		Rect2(cards_x, cards_y, card_width, 105.0),
		"BEAVERS DELIVERED", str(delivered), GREEN, alpha
	)
	_draw_stat_card(
		Rect2(cards_x + card_width + card_gap, cards_y, card_width, 105.0),
		"FUEL REMAINING", "%d%%" % fuel_percent, CYAN, alpha
	)
	_draw_stat_card(
		Rect2(cards_x + (card_width + card_gap) * 2.0, cards_y, card_width, 105.0),
		"MISSION RANK", rank, GOLD, alpha
	)

	var score_y := cards_y + 152.0
	var shown_score := int(round(float(_mission_score()) * eased))
	draw_string(
		font, Vector2(panel.position.x, score_y), "TOTAL SCORE",
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 18,
		Color(0.62, 0.82, 0.9, alpha)
	)
	draw_string(
		font, Vector2(panel.position.x, score_y + 63.0), "%06d" % shown_score,
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 58,
		Color(GOLD, alpha)
	)
	draw_string(
		font, Vector2(panel.position.x, score_y + 98.0),
		"BEAVER BONUS  %d    +    FUEL BONUS  %d" % [_beaver_score(), _fuel_bonus()],
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 16,
		Color(0.65, 0.92, 1.0, 0.9 * alpha)
	)

	var prompt_y := panel.end.y - 35.0
	var pulse := 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.005)
	draw_string(
		font, Vector2(panel.position.x, prompt_y),
		"PRESS A / X  OR  R  TO FLY AGAIN",
		HORIZONTAL_ALIGNMENT_CENTER, panel.size.x, 18,
		Color(0.72, 1.0, 0.82, alpha * pulse)
	)


func _draw_stat_card(
	rect: Rect2,
	label: String,
	value: String,
	accent: Color,
	alpha: float
) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(rect, Color(0.02, 0.11, 0.15, 0.82 * alpha))
	draw_rect(rect, Color(accent, 0.55 * alpha), false, 2.0)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 29.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14,
		Color(0.65, 0.88, 0.92, alpha)
	)
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + 79.0), value,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 40,
		Color(accent, alpha)
	)


func _draw_corner_marks(rect: Rect2, alpha: float) -> void:
	var color := Color(GREEN, 0.9 * alpha)
	var length := 30.0
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var toward_x := 1.0 if corner.x == rect.position.x else -1.0
		var toward_y := 1.0 if corner.y == rect.position.y else -1.0
		draw_line(corner, corner + Vector2(toward_x * length, 0.0), color, 4.0)
		draw_line(corner, corner + Vector2(0.0, toward_y * length), color, 4.0)


func _draw_confetti(rect: Rect2, alpha: float) -> void:
	# Fixed points avoid allocating random values every frame and stop the
	# celebration from flickering in VR.
	var points := [
		Vector2(0.08, 0.15), Vector2(0.14, 0.34), Vector2(0.91, 0.19),
		Vector2(0.86, 0.37), Vector2(0.06, 0.72), Vector2(0.94, 0.68),
		Vector2(0.18, 0.85), Vector2(0.82, 0.88),
	]
	for index in points.size():
		var point: Vector2 = rect.position + points[index] * rect.size
		var color := GREEN if index % 2 == 0 else GOLD
		draw_circle(point, 4.0 + float(index % 3), Color(color, 0.7 * alpha))
		draw_line(point - Vector2(8, 0), point + Vector2(8, 0), Color(color, 0.5 * alpha), 2.0)


func _find_scene_nodes() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_flight = scene.get_node_or_null("XROrigin3D") as Node3D
	_director = scene.get_node_or_null("BeaverExhibit") as Node3D


func _delivered_count() -> int:
	if _director != null and _director.has_method("get_delivered_count"):
		return int(_director.call("get_delivered_count"))
	return 0


func _fuel_percent() -> int:
	if _flight == null:
		return 0
	var maximum := maxf(float(_flight.get("maximum_fuel")), 0.001)
	return int(round(clampf(float(_flight.get("fuel")) / maximum, 0.0, 1.0) * 100.0))


func _mission_score() -> int:
	return int(_flight.call("get_mission_score")) if _flight != null else 0


func _beaver_score() -> int:
	return int(_flight.call("get_beaver_score")) if _flight != null else 0


func _fuel_bonus() -> int:
	return int(_flight.call("get_fuel_score")) if _flight != null else 0


func _result_rank() -> String:
	return String(_flight.call("get_mission_rank")) if _flight != null else "C"
