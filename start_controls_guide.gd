# =============================================================================
# start_controls_guide.gd — English quick-start card shown only in WAITING.
#
# The same Control is used in the desktop CanvasLayer and in an XR
# SubViewport. It stays on the left side of the start view, disappears as
# soon as B/Y begins the run, and returns after a reset.
# =============================================================================
extends Control
class_name StartControlsGuide

const STATE_WAITING := 3
const CYAN := Color(0.28, 0.93, 1.0)
const GREEN := Color(0.42, 1.0, 0.55)
const GOLD := Color(1.0, 0.76, 0.25)

var _flight: Node3D
var _last_showing := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_flight()
	_last_showing = is_showing()


func _process(_delta: float) -> void:
	if _flight == null:
		_find_flight()
	var showing := is_showing()
	if showing != _last_showing:
		_last_showing = showing
		queue_redraw()


func is_showing() -> bool:
	return _flight != null and int(_flight.get("state")) == STATE_WAITING


func get_guide_language() -> String:
	return "English"


func _draw() -> void:
	if not is_showing() or size.x < 260.0 or size.y < 360.0:
		return
	# Author once at the XR texture's 600x760 design size, then scale the whole
	# card uniformly into the smaller desktop slot. Uniform scaling preserves
	# row spacing and typography instead of crushing only the vertical gaps.
	var canvas_size := Vector2(600.0, 760.0)
	var content_scale := minf(size.x / canvas_size.x, size.y / canvas_size.y)
	var content_offset := (size - canvas_size * content_scale) * 0.5
	draw_set_transform(content_offset, 0.0, Vector2.ONE * content_scale)
	var font := ThemeDB.fallback_font
	var panel := Rect2(Vector2(8, 8), canvas_size - Vector2(16, 16))
	draw_rect(panel.grow(6.0), Color(0.1, 0.9, 1.0, 0.08))
	draw_rect(panel, Color(0.012, 0.045, 0.07, 0.94))
	draw_rect(panel, Color(CYAN, 0.66), false, 2.0)

	var left := panel.position.x + 25.0
	var width := panel.size.x - 50.0
	draw_string(font, Vector2(left, panel.position.y + 48.0), "FLIGHT MANUAL", HORIZONTAL_ALIGNMENT_LEFT, width, 29, GREEN)
	draw_string(font, Vector2(left, panel.position.y + 73.0), "ENGLISH VERSION", HORIZONTAL_ALIGNMENT_LEFT, width, 14, Color(CYAN, 0.8))
	draw_line(Vector2(left, panel.position.y + 91.0), Vector2(left + width, panel.position.y + 91.0), Color(CYAN, 0.35), 2.0)

	var mission := Rect2(left, panel.position.y + 110.0, width, 92.0)
	draw_rect(mission, Color(0.03, 0.13, 0.15, 0.82))
	draw_rect(mission, Color(GOLD, 0.65), false, 2.0)
	draw_string(font, mission.position + Vector2(15, 25), "MISSION", HORIZONTAL_ALIGNMENT_LEFT, mission.size.x - 30.0, 15, GOLD)
	draw_string(font, mission.position + Vector2(15, 50), "COLLECT 20 BEAVERS", HORIZONTAL_ALIGNMENT_LEFT, mission.size.x - 30.0, 18, Color(0.88, 1.0, 0.9))
	draw_string(font, mission.position + Vector2(15, 74), "DELIVER THEM TO MIT", HORIZONTAL_ALIGNMENT_LEFT, mission.size.x - 30.0, 18, Color(0.88, 1.0, 0.9))

	var rows := [
		["B / Y", "START  /  TAKE OFF"],
		["LEFT STICK", "FLY  /  WALK ON PLANETS"],
		["TRIGGER", "FIRE CAPTURE BOLT (LANDED)"],
		["GRIP", "HOLD TO EXPAND MAP"],
		["A / X", "RESTART AFTER CRASH / VICTORY"],
	]
	var row_y := mission.end.y + 28.0
	var available_height := panel.end.y - row_y - 105.0
	var row_height := minf(58.0, available_height / float(rows.size()))
	for index in rows.size():
		var key_width := minf(135.0, width * 0.35)
		var key_rect := Rect2(left, row_y + float(index) * row_height, key_width, row_height - 10.0)
		draw_rect(key_rect, Color(0.04, 0.22, 0.26, 0.92))
		draw_rect(key_rect, Color(CYAN, 0.55), false, 1.5)
		draw_string(font, key_rect.position + Vector2(0, key_rect.size.y * 0.68), String(rows[index][0]), HORIZONTAL_ALIGNMENT_CENTER, key_rect.size.x, 14, CYAN)
		draw_string(font, Vector2(key_rect.end.x + 14.0, key_rect.position.y + key_rect.size.y * 0.68), String(rows[index][1]), HORIZONTAL_ALIGNMENT_LEFT, width - key_width - 14.0, 13, Color(0.78, 0.93, 0.96))

	var tip_y := panel.end.y - 75.0
	draw_string(font, Vector2(left, tip_y), "LAND GENTLY · SAVE FUEL · FOLLOW THE FLOW", HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color(GOLD, 0.9))
	draw_string(font, Vector2(left, panel.end.y - 36.0), "PRESS B OR Y TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, width, 18, GREEN)


func _find_flight() -> void:
	var scene := get_tree().current_scene
	if scene != null:
		_flight = scene.get_node_or_null("XROrigin3D") as Node3D
