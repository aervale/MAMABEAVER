# =============================================================================
# beaver_director.gd — mission owner for the beaver-collection layer. Lives
# on the root-level "BeaverExhibit" node in main.tscn (a load-bearing name:
# the flight controller and minimap find it by absolute path, same pattern
# as MoonExhibit / BlackHoleExhibit).
#
# At startup it scans MoonExhibit with the project's usual duck-typing
# (children exposing `target_diameter_meters`) and spawns beavers_per_planet
# BeaverCritter instances spread over the planet's ENTIRE sphere using a
# Fibonacci (golden-angle) lattice, which spaces them near-evenly instead of
# clustering the way uniform random angles do. The player can walk the whole
# surface while landed, so no point is unreachable.
#
# MODEL: if res://models/beaver/beaver.glb exists (manual download — see
# MODEL_ATTRIBUTION.md), the first imported_model_budget beavers use it
# (17.5k tris each; more than ~6 threatens the Quest frame budget) and the
# rest use beaver.gd's ~15-primitive fallback. No model file -> all fallback.
#
# API consumed by spaceship_flight.gd and flight_minimap.gd (duck-typed):
#   get_total_count / get_required_count / get_cargo_count /
#   get_delivered_count() -> int
#   get_planet_beaver_count(planet: Node3D) -> int      (minimap badges)
#   find_beaver_near(world_pos, radius) -> BeaverCritter|null  (bolt hits)
#   begin_tractor(beaver, flight) -> bool
#   bank_cargo() -> int      (CARGO -> DELIVERED, returns amount banked)
#   reset_all()              (full mission reset, any state -> IDLE at spawn)
# =============================================================================
extends Node3D
class_name BeaverDirector

signal beaver_caught(beaver: Node3D)

const BeaverScript = preload("res://beaver.gd")
const MODEL_PATH := "res://models/beaver/Beaver.fbx"

## 3 rather than 5: every beaver keeps the real imported model (capping the
## model count instead reintroduced the "only some planets look right"
## problem), so the saving has to come from the total, and 30 skinned
## meshes load and run comfortably where 50 did not.
@export_range(1, 12, 1) var beavers_per_planet := 3
## Delivering this many ends the mission; extra spawned beavers preserve route choice.
@export_range(1, 100, 1) var required_deliveries := 20
## How many beavers may use the imported model. 0 means "no limit", which
## is the default: capping it left most planets showing the procedural
## fallback while a lucky few got the real beaver, which read as a bug.
## Lower this if the Quest struggles — each imported beaver is a skinned
## ~17.5k-tri mesh with its own AnimationPlayer.
@export_range(0, 120, 1) var imported_model_budget := 0
@export var beaver_height_meters := 1.2

var _beavers: Array[BeaverCritter] = []
var _beavers_by_planet := {}
## planet -> PackedVector3Array of local-space surface samples.
var _surface_cache := {}
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
		var lattice_spin := randf() * TAU
		for index in beavers_per_planet:
			var beaver := BeaverScript.new() as BeaverCritter
			beaver.name = "Beaver_%s_%d" % [planet.name, index]
			beaver.target_height = beaver_height_meters
			if model != null and (imported_model_budget <= 0 or imported_budget_left > 0):
				beaver.model_scene = model
				imported_budget_left -= 1
			_place_on_planet(beaver, planet, index, beavers_per_planet, lattice_spin)
			beaver.collected.connect(_on_beaver_collected)
			_beavers.append(beaver)
			spawned.append(beaver)
		_beavers_by_planet[planet] = spawned

	print("BeaverDirector|INFO: spawned %d beavers on %d planets" % [
		_beavers.size(), _beavers_by_planet.size()
	])


## Position + orient one beaver anywhere on the planet's sphere. All math in
## the PLANET's local frame (planets don't rotate — only their inner
## MoonModel spins).
func _place_on_planet(
	beaver: BeaverCritter,
	planet: Node3D,
	index: int,
	count: int,
	spin: float
) -> void:
	var radius := float(planet.get("target_diameter_meters")) * 0.5

	# Fibonacci sphere: step evenly through heights while advancing the
	# azimuth by the golden angle. `spin` rotates each planet's lattice so
	# no two planets get an identical layout.
	var k := float(index) + 0.5
	var cos_phi := 1.0 - 2.0 * k / float(count)
	var sin_phi := sqrt(maxf(1.0 - cos_phi * cos_phi, 0.0))
	var theta := PI * (1.0 + sqrt(5.0)) * k + spin
	var up := Vector3(sin_phi * cos(theta), cos_phi, sin_phi * sin(theta))

	# Sit on the REAL surface. The moon mesh is a scanned, lumpy rock
	# normalized by its largest dimension, so a fixed fraction of `radius`
	# left beavers hovering over the narrow parts and buried in the wide
	# ones. Sampling the actual geometry along this direction fixes both.
	var surface := _surface_radius_along(planet, up, radius)
	var local_position := up * (surface - beaver_height_meters * 0.12)

	# Basis: local +Y = surface normal; +Z is any consistent tangent (the
	# beaver mesh is built facing +Z). The reference axis is chosen so it is
	# never parallel to `up`, which would collapse the cross product.
	var reference := Vector3.UP if absf(up.y) < 0.9 else Vector3.FORWARD
	var right := reference.cross(up).normalized()
	var forward := right.cross(up)

	planet.add_child(beaver)
	beaver.transform = Transform3D(Basis(right, up, forward), local_position)
	# Must run AFTER the transform above: add_child() already fired the
	# beaver's _ready(), which recorded an identity spawn point.
	beaver.mark_home()


## Public wrapper: distance from a planet's centre to its real mesh surface
## along `direction`. The flight controller uses this so the player walks at
## the beavers' level instead of floating on the collision radius.
func get_surface_radius(planet: Node3D, direction: Vector3, fallback: float) -> float:
	return _surface_radius_along(planet, direction, fallback)


## Distance from a planet's centre to its mesh surface along `direction`.
##
## Vertices are cached per planet on first use and subsampled (the moon mesh
## has far more detail than placement needs), so this costs a few thousand
## dot products per planet once at startup rather than per frame.
func _surface_radius_along(planet: Node3D, direction: Vector3, fallback: float) -> float:
	var samples: PackedVector3Array = _surface_cache.get(planet, PackedVector3Array())
	if samples.is_empty():
		samples = _collect_surface_samples(planet)
		_surface_cache[planet] = samples
	if samples.is_empty():
		return fallback

	# Nearest sample by ANGLE, then use its distance from the centre.
	var best_dot := -2.0
	var best_length := fallback
	for point in samples:
		var length := point.length()
		if length < 0.0001:
			continue
		var alignment := point.dot(direction) / length
		if alignment > best_dot:
			best_dot = alignment
			best_length = length
	return best_length


## Every mesh vertex under the planet, in the PLANET's local space,
## subsampled to keep startup cheap.
func _collect_surface_samples(planet: Node3D) -> PackedVector3Array:
	var samples := PackedVector3Array()
	var pending: Array[Node] = [planet]
	var to_planet := planet.global_transform.affine_inverse()
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		# Never sample the beavers themselves.
		if node is BeaverCritter:
			continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_instance := node as MeshInstance3D
			var to_local := to_planet * mesh_instance.global_transform
			var faces := mesh_instance.mesh.get_faces()
			# Stride: placement needs shape, not every triangle corner.
			var stride := maxi(1, faces.size() / 3000)
			var index := 0
			while index < faces.size():
				samples.append(to_local * faces[index])
				index += stride
		for child in node.get_children():
			pending.append(child)
	return samples


func _on_beaver_collected(beaver: Node3D) -> void:
	_cargo += 1
	beaver_caught.emit(beaver)
	print("BeaverDirector|INFO: beaver aboard, cargo %d" % _cargo)


# --- API for flight controller / bolts / minimap -----------------------------

func get_total_count() -> int:
	return _beavers.size()


func get_required_count() -> int:
	return mini(required_deliveries, _beavers.size())


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
