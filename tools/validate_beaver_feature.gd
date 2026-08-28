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
	var game_sfx := scene.get_node_or_null("GameSFX")
	var planet := scene.get_node_or_null("MoonExhibit/Planet01") as Node3D
	var background_music := scene.get_node_or_null("BackgroundMusic") as AudioStreamPlayer
	var xr_camera := scene.get_node_or_null("XROrigin3D/XRCamera3D") as XRCamera3D
	var comfort_vignette := scene.get_node_or_null("XROrigin3D/XRCamera3D/ComfortVignette")
	var ship_visual := scene.get_node_or_null("XROrigin3D/Spacecraft") as Node3D
	var left_controller := scene.get_node_or_null("XROrigin3D/XRControllerLeft") as XRController3D
	var right_controller := scene.get_node_or_null("XROrigin3D/XRControllerRight") as XRController3D
	var desktop_results := scene.get_node_or_null("DesktopHUD/MissionResults")
	var vr_results := scene.get_node_or_null(
		"XROrigin3D/XRCamera3D/FlightHUD/ResultsViewport/MissionResults"
	)
	_check(flight != null, "XROrigin3D must exist")
	_check(director != null, "BeaverExhibit must exist")
	_check(
		game_sfx != null
		and game_sfx.has_method("has_all_sounds")
		and bool(game_sfx.call("has_all_sounds")),
		"four original one-shot sound streams are generated at startup"
	)
	_check(planet != null, "Planet01 must exist")
	_check(
		background_music != null
		and background_music.stream is AudioStreamWAV
		and (background_music.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		and background_music.playing,
		"background music loads, plays, and loops"
	)
	_check(ship_visual != null, "visible spacecraft must exist")
	_check(
		desktop_results != null and vr_results != null
		and desktop_results.has_method("is_showing")
		and String(desktop_results.call("get_title")) == "VICTORY!",
		"desktop and XR settlement screens share the VICTORY presentation"
	)
	_check(
		comfort_vignette != null and comfort_vignette.has_method("get_strength"),
		"head-locked dynamic comfort vignette exists"
	)
	_check(
		is_instance_valid(flight.get("_prewarmed_bolt"))
		and (flight.get("_prewarmed_bolt") as Node3D).visible
		and (flight.get("_prewarmed_bolt") as Node3D).scale.x < 0.001,
		"first magic bolt enters the render queue at sub-pixel scale during loading"
	)
	# Hidden instances do not compile render pipelines. Let the startup copy be
	# drawn for its configured eight frames, then verify it becomes dormant.
	for frame in 10:
		await process_frame
	_check(
		is_instance_valid(flight.get("_prewarmed_bolt"))
		and not (flight.get("_prewarmed_bolt") as Node3D).visible
		and bool(flight.get("_bolt_render_prewarm_complete")),
		"first-shot opaque, transparent and particle pipelines finish prewarming"
	)
	_check(
		left_controller != null and right_controller != null
		and left_controller.pose == &"aim" and right_controller.pose == &"aim",
		"trigger firing uses calibrated OpenXR aim poses (left=%s right=%s)" % [
			left_controller.pose if left_controller != null else &"missing",
			right_controller.pose if right_controller != null else &"missing",
		]
	)
	if flight == null or director == null or planet == null:
		_finish()
		return
	_check(is_equal_approx(float(flight.get("arrival_radius")), 5.0), "MIT arrival radius is 5 m")

	# Room-scale head movement must not alter the ship's physics anchor. The
	# hull, minimap, landing and surface walking all follow XROrigin3D.
	if xr_camera != null:
		xr_camera.position = Vector3(1.2, 0.3, -0.8)
		var anchored: Vector3 = flight.call("get_spacecraft_world_position")
		_check(
			anchored.distance_to((flight as Node3D).global_position) < 0.01,
			"headset room-scale offset cannot separate the player from the ship"
		)

	# --- spawning ---
	var total := int(director.call("get_total_count"))
	var per_planet := int(director.get("beavers_per_planet"))
	_check(
		director.has_method("get_required_count")
		and int(director.call("get_required_count")) == 20,
		"mission success target is 20 delivered beavers"
	)
	_check(total == per_planet * 10, "director spawns %d beavers on each of 10 planets (got %d)" % [per_planet, total])
	_check(int(director.call("get_planet_beaver_count", planet)) == per_planet, "Planet01 hosts them all")
	# Full-sphere spread: beavers must exist well above AND below the plane.
	var highest := -INF
	var lowest := INF
	for c in planet.get_children():
		if c.name.begins_with("Beaver"):
			highest = maxf(highest, (c as Node3D).global_position.y)
			lowest = minf(lowest, (c as Node3D).global_position.y)
	_check(
		highest > planet.global_position.y + 2.0 and lowest < planet.global_position.y - 2.0,
		"beavers cover the whole sphere, not just the flight-plane ring (y %.1f..%.1f)" % [lowest, highest]
	)

	# Remember a beaver's real spawn point: reset must restore POSITION, not
	# just state. (An earlier bug parked every beaver at the planet centre
	# after a death and this suite passed anyway — hence this check.)
	var probe: Node3D = director.call("find_beaver_near", planet.global_position, 20.0)
	var probe_home := probe.global_position if probe != null else Vector3.ZERO
	_check(
		probe != null and probe_home.distance_to(planet.global_position) > 1.0,
		"beavers spawn on the surface, not inside the planet"
	)

	# --- desktop firing: bolt must leave from the SHIP, not the orbit camera ---
	var camera := scene.get_node_or_null("DesktopCamera") as Camera3D
	_check(camera != null and camera.current, "DesktopCamera is active in desktop mode")
	# The map reads this by duck typing; losing it blanks the expand feature.
	_check(flight.has_method("is_map_expanded"), "flight exposes is_map_expanded for the tactical map")
	_check(not bool(flight.call("is_map_expanded")), "map starts compact")

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
	# Tangential shot along the surface: this is the normal case, and the
	# planet you stand on must not swallow it.
	var muzzle: Vector3 = flight.call("get_spacecraft_world_position")
	var prewarmed_bolt: Node3D = flight.get("_prewarmed_bolt") as Node3D
	var shot_sounds_before := int(game_sfx.call("get_play_count", &"trigger_shot"))
	flight.call("_try_fire", muzzle, Vector3(0, 0, 1))
	_check(_count_bolts(scene) == 1, "a surface-skimming shot fires while landed")
	var skimmer: Node3D = null
	for child in scene.get_children():
		if child is MagicBolt:
			skimmer = child
	_check(
		skimmer != null and (skimmer as MagicBolt).ignored_planet == planet,
		"the bolt ignores the planet the player is standing on"
	)
	_check(
		skimmer == prewarmed_bolt and flight.get("_prewarmed_bolt") == null,
		"first trigger pull reuses the prewarmed bolt without construction"
	)
	_check(
		int(game_sfx.call("get_play_count", &"trigger_shot")) == shot_sounds_before + 1,
		"a successful trigger shot plays its firing sound"
	)
	# Straight down into the rock is the one aim that gets refused.
	var into := (planet.global_position - muzzle).normalized()
	flight.call("_try_fire", muzzle, into)
	_check(_count_bolts(scene) == 1, "aiming into the surface is refused, not absorbed")

	# Simulate a real desktop right-click through _unhandled_input.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(root.size) * 0.5
	flight.call("_unhandled_input", click)
	var ship_now: Vector3 = flight.call("get_spacecraft_world_position")
	var spawned_near_ship := true
	for child in scene.get_children():
		if child is MagicBolt:
			spawned_near_ship = spawned_near_ship and (child as Node3D).global_position.distance_to(ship_now) < 3.0
	_check(spawned_near_ship, "right-click bolts spawn at the ship, not at the orbit camera")

	# --- walking around the planet while landed ---
	var before_walk: Vector3 = flight.call("get_spacecraft_world_position")
	var radius_before := Vector2(before_walk.x, before_walk.z).distance_to(
		Vector2(planet.global_position.x, planet.global_position.z))
	# Two seconds of "stick held forward" — enough to climb off the ring.
	for i in 120:
		flight.call("_walk_on_surface", 1.0 / 60.0, Vector2(0.0, 1.0))
	var after_walk: Vector3 = flight.call("get_spacecraft_world_position")
	# The rig must tip so the planet stays "down" underfoot — this is what
	# makes walking around the sphere feel like walking, not sliding.
	var rig_up := (flight as Node3D).global_basis.y
	var surface_up := (after_walk - planet.global_position).normalized()
	_check(
		rig_up.dot(surface_up) > 0.9,
		"walking reorients the rig to the surface normal (dot=%.2f)" % rig_up.dot(surface_up)
	)

	var walked := before_walk.distance_to(after_walk)
	_check(walked > 1.0, "walking actually moves the ship over the planet (%.2f m)" % walked)
	# The rock is lumpy and the player now follows it, so a CONSTANT radius
	# is no longer the contract: what must hold is that you stand on the
	# sampled surface, at the beavers' level.
	var out_dir := (after_walk - planet.global_position).normalized()
	var expected := float(flight.call("_stand_radius", planet, out_dir))
	var actual := after_walk.distance_to(planet.global_position)
	_check(
		absf(actual - expected) < 0.35,
		"walking keeps the player on the sampled surface (%.2f vs %.2f)" % [actual, expected]
	)
	var beaver_probe: Node3D = director.call("find_beaver_near", planet.global_position, 30.0)
	if beaver_probe != null:
		var beaver_r := beaver_probe.global_position.distance_to(planet.global_position)
		_check(
			absf(actual - beaver_r) < 2.5,
			"player walks at the beavers' level (player %.2f, beaver %.2f)" % [actual, beaver_r]
		)
	_check(
		absf(after_walk.y - 10.0) > 0.5,
		"walking leaves the flight plane — you can climb the sphere (y=%.2f)" % after_walk.y
	)
	_check(int(flight.get("state")) == STATE_LANDED, "walking does not leave the LANDED state")

	# Analog input must stay analog. The former implementation normalized
	# every non-zero move, making a gentle push travel at full walking speed.
	var saved_rig_transform := (flight as Node3D).global_transform
	flight.set("_surface_walk_forward", Vector3.ZERO)
	var gentle_start: Vector3 = flight.call("get_spacecraft_world_position")
	flight.call("_walk_on_surface", 0.1, Vector2(0.0, 0.25))
	var gentle_distance := gentle_start.distance_to(flight.call("get_spacecraft_world_position"))
	(flight as Node3D).global_transform = saved_rig_transform
	flight.set("_surface_walk_forward", Vector3.ZERO)
	var full_start: Vector3 = flight.call("get_spacecraft_world_position")
	flight.call("_walk_on_surface", 0.1, Vector2(0.0, 1.0))
	var full_distance := full_start.distance_to(flight.call("get_spacecraft_world_position"))
	_check(
		full_distance > gentle_distance * 3.5,
		"surface walking preserves stick magnitude (gentle %.3f, full %.3f)" % [gentle_distance, full_distance]
	)

	# Walking in every direction must never break the sphere constraint.
	for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0.7, 0.7)]:
		for i in 30:
			flight.call("_walk_on_surface", 1.0 / 60.0, dir)
	var after_roam: Vector3 = flight.call("get_spacecraft_world_position")
	var roam_dir := (after_roam - planet.global_position).normalized()
	_check(
		absf(
			after_roam.distance_to(planet.global_position)
			- float(flight.call("_stand_radius", planet, roam_dir))
		) < 0.35,
		"walking any direction never burrows into or floats off the surface"
	)

	# --- takeoff + grace ---
	# Give the headset a yaw relative to the already tilted surface rig. The
	# same WORLD heading must survive leveling; preserving only rig.forward
	# used to reverse the view after some takeoffs.
	var view_heading_before_takeoff := Vector2.ZERO
	if xr_camera != null:
		xr_camera.rotation = Vector3(0.0, deg_to_rad(63.0), 0.0)
		view_heading_before_takeoff = flight.call("get_view_heading")
	var takeoff_start: Vector3 = flight.call("get_spacecraft_world_position")
	flight.call("take_off")
	_check(
		int(flight.get("state")) == STATE_LANDED
		and bool(flight.call("is_takeoff_animating")),
		"B/Y begins a protected continuous takeoff"
	)
	var takeoff_target: Vector3 = flight.get("_takeoff_to")
	await physics_frame
	var takeoff_first_step: Vector3 = flight.call("get_spacecraft_world_position")
	_check(
		takeoff_first_step.distance_to(takeoff_start) > 0.0001
		and takeoff_first_step.distance_to(takeoff_target) > 0.01,
		"takeoff moves through intermediate positions instead of teleporting"
	)
	var takeoff_frames_left := int(ceil(
		float(flight.get("takeoff_animation_seconds")) * Engine.physics_ticks_per_second
	)) + 10
	while bool(flight.call("is_takeoff_animating")) and takeoff_frames_left > 0:
		await physics_frame
		takeoff_frames_left -= 1
	_check(int(flight.get("state")) == STATE_FLYING, "continuous takeoff completes into FLYING")
	_check(
		(flight as Node3D).global_basis.y.dot(Vector3.UP) > 0.999,
		"takeoff levels the rig back upright for flight"
	)
	if xr_camera != null:
		var view_heading_after_takeoff: Vector2 = flight.call("get_view_heading")
		_check(
			view_heading_before_takeoff.dot(view_heading_after_takeoff) > 0.9999,
			"takeoff preserves the headset's world-facing direction"
		)
		# Repeat the hard part with several unrelated surface normals and tracked
		# head rotations. This catches the accumulated yaw reversal that only
		# appeared after visiting multiple planets in the headset.
		var cycle_normals := [
			Vector3(0.72, 0.42, -0.55).normalized(),
			Vector3(-0.61, -0.24, 0.75).normalized(),
			Vector3(0.18, -0.91, -0.37).normalized(),
		]
		var cycle_rotations := [
			Vector3(deg_to_rad(14.0), deg_to_rad(-82.0), deg_to_rad(8.0)),
			Vector3(deg_to_rad(-21.0), deg_to_rad(137.0), deg_to_rad(-11.0)),
			Vector3(deg_to_rad(9.0), deg_to_rad(38.0), deg_to_rad(16.0)),
		]
		var all_cycles_preserved := true
		for cycle in cycle_normals.size():
			flight.call("_align_rig_up", cycle_normals[cycle], 1.0)
			xr_camera.rotation = cycle_rotations[cycle]
			var heading_before: Vector2 = flight.call("get_view_heading")
			(flight as Node3D).global_basis = flight.call("_get_level_basis", heading_before)
			flight.call("_correct_view_heading", heading_before)
			var heading_after: Vector2 = flight.call("get_view_heading")
			all_cycles_preserved = (
				all_cycles_preserved
				and heading_before.dot(heading_after) > 0.9999
				and (flight as Node3D).global_basis.y.dot(Vector3.UP) > 0.999
			)
		_check(all_cycles_preserved, "view heading remains stable after repeated landing cycles")
		xr_camera.rotation = Vector3.ZERO
		flight.call("_level_rig")
	var launched: Vector3 = flight.call("get_spacecraft_world_position")
	_check(absf(launched.y - 10.0) < 0.01, "takeoff returns to the flight plane (y=%.2f)" % launched.y)
	var clearance := Vector2(launched.x, launched.z).distance_to(
		Vector2(planet.global_position.x, planet.global_position.z))
	var contact_radius := float(planet.get("target_diameter_meters")) * 0.5 + float(flight.get("spacecraft_radius"))
	var height_delta := float(flight.get("start_position").z) - planet.global_position.y
	var expected_clearance := (
		sqrt(maxf(contact_radius * contact_radius - height_delta * height_delta, 0.01))
		+ float(flight.get("takeoff_clearance_margin"))
	)
	_check(
		clearance >= expected_clearance - 0.01,
		"takeoff includes the full safety margin (%.2f / %.2f m)" % [clearance, expected_clearance]
	)
	if ship_visual != null:
		# A single update must align exactly with VELOCITY. A smoothed turn can
		# lag toward the former heading and be mistaken for acceleration-following.
		var test_velocity := Vector2(3.0, -4.0)
		ship_visual.call("_update_heading", test_velocity)
		var ship_forward := -(ship_visual as Node3D).global_basis.z.normalized()
		var expected_forward := Vector3(test_velocity.x, 0.0, test_velocity.y).normalized()
		_check(
			ship_forward.dot(expected_forward) > 0.9999,
			"visible ship heading exactly matches velocity, without acceleration-like lag"
		)
	# Continue beyond the grace window: the farther spawn must keep the ship
	# clear even after collision with the departed planet is re-enabled.
	var safety_frames := int(ceil(
		(float(flight.get("takeoff_grace_seconds")) + 0.5)
		* Engine.physics_ticks_per_second
	))
	for frame in safety_frames:
		await physics_frame
	_check(
		int(flight.get("state")) == STATE_FLYING,
		"takeoff remains clear after the grace period"
	)
	# Firing in flight is now allowed, so a shot here must ADD a bolt.
	var bolts_before := _count_bolts(scene)
	flight.call("_try_fire", flight.call("get_spacecraft_world_position"), Vector3(0, 0, 1))
	_check(_count_bolts(scene) == bolts_before + 1, "can fire while flying")

	# --- impact warning fires on a fast approach, stays quiet on a slow one ---
	flight.call("reset_flight")
	flight.call("start_flight")
	_teleport(flight, planet.global_position + Vector3(-30.0, 0.0, 0.0), Vector2(14.0, 0.0))
	flight.call("_update_impact_warning", 0.016)
	_check(not String(flight.get("_impact_warning")).is_empty(), "fast approach raises the impact warning")
	flight.set("velocity", Vector2(2.0, 0.0))
	flight.call("_update_impact_warning", 0.016)
	_check(String(flight.get("_impact_warning")).is_empty(), "a landable approach speed does not warn")
	_teleport(flight, planet.global_position + Vector3(-30.0, 0.0, 0.0), Vector2(-14.0, 0.0))
	flight.call("_update_impact_warning", 0.016)
	_check(String(flight.get("_impact_warning")).is_empty(), "flying AWAY from a planet does not warn")

	# --- fast contact = crash ---
	flight.call("reset_flight")
	flight.call("start_flight")
	_teleport(flight, planet.global_position + Vector3(-5.7, 0.0, 0.0), Vector2(10.0, 0.0))
	await physics_frame
	await physics_frame
	_check(int(flight.get("state")) == STATE_CRASHED, "fast planet contact still crashes")
	# B/Y must revive the run too: it is the button players reach for.
	flight.call("_on_controller_button_pressed", &"by_button")
	_check(int(flight.get("state")) == STATE_WAITING, "B/Y restarts after a crash")
	flight.call("start_flight")

	# --- tractor -> cargo ---
	flight.call("reset_flight")
	flight.call("start_flight")
	var beaver: Node3D = director.call("find_beaver_near", planet.global_position, 20.0)
	_check(beaver != null, "find_beaver_near locates an idle beaver")
	if beaver != null:
		var caught_sounds_before := int(game_sfx.call("get_play_count", &"beaver_caught"))
		director.call("begin_tractor", beaver, flight)
		# Headless frames run uncapped, so wait on wall-clock time (the
		# tractor takes TRACTOR_DURATION = 1.5 s of _process delta).
		var deadline := create_timer(3.0)
		while int(director.call("get_cargo_count")) == 0 and deadline.time_left > 0.0:
			await process_frame
		_check(int(director.call("get_cargo_count")) == 1, "tractored beaver becomes cargo")
		_check(
			int(game_sfx.call("get_play_count", &"beaver_caught")) == caught_sounds_before + 1,
			"beaver entering cargo plays the caught sound"
		)
		_check(int(director.call("get_planet_beaver_count", planet)) == per_planet - 1, "planet badge count drops")

	# --- banking at MIT (not a win while beavers remain) ---
	var destination: Vector3 = flight.get("destination")
	var deposit_sounds_before := int(game_sfx.call("get_play_count", &"mit_deposit"))
	_teleport(flight, Vector3(destination.x, 10.0, destination.y), Vector2.ZERO)
	await physics_frame
	await physics_frame
	_check(int(flight.get("state")) == STATE_FLYING, "arriving with beavers still out there is not a win")
	_check(int(director.call("get_delivered_count")) == 1, "cargo banks on arrival")
	_check(int(director.call("get_cargo_count")) == 0, "cargo empties after banking")
	_check(
		int(game_sfx.call("get_play_count", &"mit_deposit")) == deposit_sounds_before + 1,
		"banking cargo at MIT plays the deposit sound"
	)

	# --- the twentieth delivery wins and plays a delayed fanfare ---
	var required := int(director.call("get_required_count"))
	director.set("_delivered", required - 1)
	director.set("_cargo", 1)
	flight.set("_inside_arrival_zone", false)
	var final_deposit_before := int(game_sfx.call("get_play_count", &"mit_deposit"))
	var victory_sounds_before := int(game_sfx.call("get_play_count", &"victory"))
	flight.call("_handle_arrival_zone")
	_check(int(flight.get("state")) == STATE_ARRIVED, "delivery 20 completes the mission")
	await process_frame
	_check(
		bool(desktop_results.call("is_showing")) and bool(vr_results.call("is_showing")),
		"VICTORY settlement screen appears in both desktop and XR presenters"
	)
	_check(
		int(flight.call("get_beaver_score")) == required * 1000
		and int(flight.call("get_mission_score"))
			== int(flight.call("get_beaver_score")) + int(flight.call("get_fuel_score")),
		"settlement score combines delivered beavers and remaining fuel"
	)
	_check(
		int(game_sfx.call("get_play_count", &"mit_deposit")) == final_deposit_before + 1,
		"final MIT delivery still plays its cargo-release sound"
	)
	await create_timer(0.8).timeout
	_check(
		int(game_sfx.call("get_play_count", &"victory")) == victory_sounds_before + 1,
		"mission completion plays the victory fanfare after the deposit"
	)

	# --- reset restores everything ---
	flight.call("reset_flight")
	await process_frame
	_check(not bool(desktop_results.call("is_showing")), "reset closes the VICTORY settlement screen")
	_check(int(director.call("get_delivered_count")) == 0, "reset clears delivered")
	_check(int(director.call("get_total_count")) == total, "reset keeps all beavers")
	_check(int(director.call("get_planet_beaver_count", planet)) == per_planet, "reset returns beavers to their planets")
	if probe != null:
		_check(
			probe.global_position.distance_to(probe_home) < 0.01,
			"reset restores each beaver's surface position (was: teleported into the planet core)"
		)
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
