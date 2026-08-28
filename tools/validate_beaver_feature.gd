# =============================================================================
# tools/validate_beaver_feature.gd — headless end-to-end check of the beaver
# collection loop (landing, refuel, takeoff, tractor, banking, reset).
#
# Run:  godot --headless --script tools/validate_beaver_feature.gd --path .
# Same style as validate_flow_feature.gd: instantiate main.tscn for real,
# drive the flight controller by teleporting the rig, assert state
# transitions, exit 0 on pass / 1 on fail.
# =============================================================================
extends SceneTree

# FlightState ordinals (enum lives in spaceship_flight.gd; LANDED is last).
const STATE_FLYING := 0
const STATE_CRASHED := 1
const STATE_ARRIVED := 2
const STATE_WAITING := 3
const STATE_LANDED := 4

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
	var director := scene.get_node_or_null("BeaverExhibit")
	var planet := scene.get_node_or_null("MoonExhibit/Planet01") as Node3D
	_check(flight != null, "XROrigin3D must exist")
	_check(director != null, "BeaverExhibit must exist")
	_check(planet != null, "Planet01 must exist")
	if flight == null or director == null or planet == null:
		_finish()
		return

	# --- spawning ---
	var total := int(director.call("get_total_count"))
	_check(total == 30, "director spawns 3 beavers on each of 10 planets (got %d)" % total)
	_check(int(director.call("get_planet_beaver_count", planet)) == 3, "Planet01 hosts 3 beavers")

	# --- slow contact = landing + refuel ---
	# Planet01: center (30, 12.5, 22), diameter 12 -> collision radius 6.25.
	# Park the camera 5.7 m out in XZ: 3D distance sqrt(5.7^2+2.5^2)=6.22 < 6.25.
	flight.call("start_flight")
	flight.set("fuel", 10.0)
	_teleport(flight, planet.global_position + Vector3(-5.7, 0.0, 0.0), Vector2(1.0, 0.0))
	await physics_frame
	await physics_frame
	_check(int(flight.get("state")) == STATE_LANDED, "slow planet contact lands (state=%d)" % int(flight.get("state")))
	_check(
		is_equal_approx(float(flight.get("fuel")), float(flight.get("maximum_fuel"))),
		"landing refuels the tank"
	)
	_check(String(flight.call("get_predicted_flow_result")) == "LANDED", "predictor reports LANDED")

	# --- firing is landed-only, capped, and spawns MagicBolt nodes ---
	flight.call("_try_fire", flight.call("get_spacecraft_world_position"), Vector3(1, 0, 0))
	_check(_count_bolts(scene) == 1, "trigger fires exactly one bolt while landed")

	# --- takeoff + grace ---
	flight.call("take_off")
	_check(int(flight.get("state")) == STATE_FLYING, "B/Y takes off")
	await physics_frame
	_check(int(flight.get("state")) == STATE_FLYING, "takeoff grace prevents instant re-collision")
	flight.call("_try_fire", Vector3.ZERO, Vector3(1, 0, 0))
	_check(_count_bolts(scene) <= 1, "cannot fire while flying")

	# --- fast contact = crash ---
	flight.call("reset_flight")
	flight.call("start_flight")
	_teleport(flight, planet.global_position + Vector3(-5.7, 0.0, 0.0), Vector2(10.0, 0.0))
	await physics_frame
	await physics_frame
	_check(int(flight.get("state")) == STATE_CRASHED, "fast planet contact still crashes")

	# --- tractor -> cargo ---
	flight.call("reset_flight")
	flight.call("start_flight")
	var beaver: Node3D = director.call("find_beaver_near", planet.global_position, 20.0)
	_check(beaver != null, "find_beaver_near locates an idle beaver")
	if beaver != null:
		director.call("begin_tractor", beaver, flight)
		# Headless frames run uncapped, so wait on wall-clock time (the
		# tractor takes TRACTOR_DURATION = 1.5 s of _process delta).
		var deadline := create_timer(3.0)
		while int(director.call("get_cargo_count")) == 0 and deadline.time_left > 0.0:
			await process_frame
		_check(int(director.call("get_cargo_count")) == 1, "tractored beaver becomes cargo")
		_check(int(director.call("get_planet_beaver_count", planet)) == 2, "planet badge count drops")

	# --- banking at MIT (not a win while beavers remain) ---
	var destination: Vector3 = flight.get("destination")
	_teleport(flight, Vector3(destination.x, 10.0, destination.y), Vector2.ZERO)
	await physics_frame
	await physics_frame
	_check(int(flight.get("state")) == STATE_FLYING, "arriving with 29 undelivered beavers is not a win")
	_check(int(director.call("get_delivered_count")) == 1, "cargo banks on arrival")
	_check(int(director.call("get_cargo_count")) == 0, "cargo empties after banking")

	# --- reset restores everything ---
	flight.call("reset_flight")
	_check(int(director.call("get_delivered_count")) == 0, "reset clears delivered")
	_check(int(director.call("get_total_count")) == 30, "reset keeps all beavers")
	_check(int(director.call("get_planet_beaver_count", planet)) == 3, "reset returns beavers to their planets")
	_check(_count_bolts(scene) == 0, "reset clears live bolts")

	_finish()


func _teleport(flight: Node, world_position: Vector3, logical_velocity: Vector2) -> void:
	(flight as Node3D).global_position = Vector3(world_position.x, 10.0, world_position.z)
	flight.set("velocity", logical_velocity)


func _count_bolts(scene: Node) -> int:
	var count := 0
	for child in scene.get_children():
		if child is MagicBolt:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error("BeaverFeature|FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("BeaverFeature|PASS")
		quit(0)
	else:
		print("BeaverFeature|FAIL: %d checks failed" % _failures.size())
		quit(1)
