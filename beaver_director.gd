# =============================================================================
# beaver_director.gd — mission owner for the beaver-collection layer. Lives
# on the root-level "BeaverExhibit" node in main.tscn (a load-bearing name:
# the flight controller and minimap find it by absolute path, same pattern
# as MoonExhibit / BlackHoleExhibit).
#
# At startup it scans MoonExhibit with the project's usual duck-typing
# (children exposing `target_diameter_meters`) and spawns beavers_per_planet
# BeaverCritter instances on each planet, standing on the latitude ring where
# the sphere crosses the flight plane (world Y = flight_altitude) — so every
# beaver is visible and shootable from a landed ship, even on planets whose
# centers are offset above/below the plane (offset clamped to 0.85R).
#
# MODEL: if res://models/beaver/beaver.glb exists (manual download — see
# MODEL_ATTRIBUTION.md), the first imported_model_budget beavers use it
# (17.5k tris each; more than ~6 threatens the Quest frame budget) and the
# rest use beaver.gd's ~15-primitive fallback. No model file -> all fallback.
#
# API consumed by spaceship_flight.gd and flight_minimap.gd (duck-typed):
#   get_total_count / get_cargo_count / get_delivered_count() -> int
#   get_planet_beaver_count(planet: Node3D) -> int      (minimap badges)
#   find_beaver_near(world_pos, radius) -> BeaverCritter|null  (bolt hits)
#   begin_tractor(beaver, flight) -> bool
#   bank_cargo() -> int      (CARGO -> DELIVERED, returns amount banked)
#   reset_all()              (full mission reset, any state -> IDLE at spawn)
# =============================================================================
extends Node3D
class_name BeaverDirector

const BeaverScript = preload("res://beaver.gd")
const MODEL_PATH := "res://models/beaver/beaver.glb"

@export_range(1, 5, 1) var beavers_per_planet := 3
## World-Y of the flight plane; must match the ship's locked altitude.
@export var flight_altitude := 10.0
## How many beavers may use the imported 17.5k-tri model (Quest budget).
@export_range(0, 30, 1) var imported_model_budget := 6
@export var beaver_height_meters := 0.9

var _beavers: Array[BeaverCritter] = []
var _beavers_by_planet := {}
var _cargo := 0
var _delivered := 0


func _ready() -> void:
	var scene := get_tree().current_scene
	var obstacles := scene.get_node_or_null("MoonExhibit") as Node3D
	if obstacles == null:
		push_warning("BeaverDirector|WARN: no MoonExhibit found, no beavers spawned")
		return

	var model: PackedScene = null
	if ResourceLoader.exists(MODEL_PATH):
		model = load(MODEL_PATH) as PackedScene
		print("BeaverDirector|INFO: using imported beaver model")

	var imported_budget_left := imported_model_budget
	for child in obstacles.get_children():
		var planet := child as Node3D
		if planet == null or planet.get("target_diameter_meters") == null:
			continue
		var spawned: Array[BeaverCritter] = []
		var base_azimuth := randf() * TAU
		for index in beavers_per_planet:
			var beaver := BeaverScript.new() as BeaverCritter
			beaver.name = "Beaver_%s_%d" % [planet.name, index]
			beaver.target_height = beaver_height_meters
			if model != null and imported_budget_left > 0:
				beaver.model_scene = model
				imported_budget_left -= 1
			_place_on_planet(beaver, planet, base_azimuth + TAU * float(index) / float(beavers_per_planet))
			beaver.collected.connect(_on_beaver_collected)
			_beavers.append(beaver)
			spawned.append(beaver)
		_beavers_by_planet[planet] = spawned

	print("BeaverDirector|INFO: spawned %d beavers on %d planets" % [
		_beavers.size(), _beavers_by_planet.size()
	])


## Position + orient one beaver on the planet's surface at the latitude ring
## where the sphere crosses the flight plane. All math in the PLANET's local
## frame (planets don't rotate — only their inner MoonModel spins).
func _place_on_planet(beaver: BeaverCritter, planet: Node3D, azimuth: float) -> void:
	var radius := float(planet.get("target_diameter_meters")) * 0.5
	# Vertical offset from planet center to the flight plane, clamped so the
	# ring never degenerates at heavily offset planets.
	var dy := clampf(flight_altitude - planet.global_position.y, -0.85 * radius, 0.85 * radius)
	var ring_radius := sqrt(maxf(radius * radius - dy * dy, 0.01))
	var jitter := randf_range(-0.25, 0.25)
	var local_position := Vector3(
		cos(azimuth + jitter) * ring_radius,
		dy,
		sin(azimuth + jitter) * ring_radius
	)

	# Basis: local +Y = surface normal, +Z faces outward horizontally (the
	# beaver mesh is built face-forward on +Z, so it looks out into space).
	var up := local_position.normalized()
	var forward := Vector3(up.x, 0.0, up.z)
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var right := up.cross(forward).normalized()
	forward = right.cross(up)

	planet.add_child(beaver)
	beaver.transform = Transform3D(Basis(right, up, forward), local_position)


func _on_beaver_collected(_beaver: Node3D) -> void:
	_cargo += 1
	print("BeaverDirector|INFO: beaver aboard, cargo %d" % _cargo)


# --- API for flight controller / bolts / minimap -----------------------------

func get_total_count() -> int:
	return _beavers.size()


func get_cargo_count() -> int:
	return _cargo


func get_delivered_count() -> int:
	return _delivered


func get_planet_beaver_count(planet: Node3D) -> int:
	var remaining := 0
	for beaver in _beavers_by_planet.get(planet, []):
		if beaver.state == BeaverCritter.BeaverState.IDLE:
			remaining += 1
	return remaining


func find_beaver_near(world_position: Vector3, radius: float) -> BeaverCritter:
	var best: BeaverCritter = null
	var best_distance := radius
	for beaver in _beavers:
		if beaver.state != BeaverCritter.BeaverState.IDLE:
			continue
		var distance := beaver.global_position.distance_to(world_position)
		if distance <= best_distance:
			best_distance = distance
			best = beaver
	return best


func begin_tractor(beaver: BeaverCritter, flight: Node3D) -> bool:
	return beaver != null and beaver.begin_tractor(flight)


func bank_cargo() -> int:
	var banked := _cargo
	_delivered += _cargo
	_cargo = 0
	for beaver in _beavers:
		if beaver.state == BeaverCritter.BeaverState.CARGO:
			beaver.mark_delivered()
	if banked > 0:
		print("BeaverDirector|INFO: banked %d, delivered %d/%d" % [
			banked, _delivered, _beavers.size()
		])
	return banked


func reset_all() -> void:
	_cargo = 0
	_delivered = 0
	for beaver in _beavers:
		beaver.reset_to_spawn()
