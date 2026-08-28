# =============================================================================
# deposit_effect.gd — the delivery celebration. Spawned by
# spaceship_flight.gd when cargo is banked at the MIT dome.
#
# One glowing orb per beaver arcs from the ship to the top of the dome along
# a lifted bezier (so they sweep up and over rather than sliding flat),
# staggered so they arrive as a stream instead of a clump. Each arrival pops
# a spark burst and brightens a shared flash light; when the last one lands
# the dome flares, then everything fades and the node frees itself.
#
# Built in code and fully self-contained: spawn it, forget it.
# =============================================================================
extends Node3D
class_name DepositEffect

const SurfaceDustScript = preload("res://surface_dust.gd")

const FLIGHT_SECONDS := 1.15
const STAGGER_SECONDS := 0.12
const ARC_HEIGHT := 9.0

## Set before add_child.
var from_position := Vector3.ZERO
var to_position := Vector3.ZERO
var beaver_count := 1

var _orbs: Array[MeshInstance3D] = []
var _elapsed := 0.0
var _landed := 0
var _flash: OmniLight3D
var _finished := false


func _ready() -> void:
	_flash = OmniLight3D.new()
	_flash.name = "DepositFlash"
	_flash.light_color = Color(0.75, 1.0, 0.85)
	_flash.light_energy = 0.0
	_flash.omni_range = 40.0
	_flash.shadow_enabled = false
	_flash.position = to_position - global_position
	add_child(_flash)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.45)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.7, 0.25)
	material.emission_energy_multiplier = 7.0

	for index in maxi(beaver_count, 1):
		var mesh := SphereMesh.new()
		mesh.radius = 0.4
		mesh.height = 0.8
		mesh.radial_segments = 12
		mesh.rings = 6
		mesh.material = material
		var orb := MeshInstance3D.new()
		orb.name = "DepositOrb%d" % index
		orb.mesh = mesh
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.top_level = true
		orb.extra_cull_margin = 60.0
		# A top-level node has no valid global transform until it enters the
		# scene tree. Adding it first avoids the !is_inside_tree() error and
		# guarantees every orb starts at the ship rather than at world origin.
		add_child(orb)
		orb.global_position = from_position
		_orbs.append(orb)


func _process(delta: float) -> void:
	_elapsed += delta
	var all_done := true

	for index in _orbs.size():
		var orb := _orbs[index]
		if not is_instance_valid(orb):
			continue
		# Stagger departures so the beavers stream out one after another.
		var start := float(index) * STAGGER_SECONDS
		var progress := clampf((_elapsed - start) / FLIGHT_SECONDS, 0.0, 1.0)
		if progress <= 0.0:
			orb.visible = false
			all_done = false
			continue
		orb.visible = true

		# Quadratic bezier through a lifted control point: a soaring arc.
		# Each orb gets its own sideways offset so the stream fans out.
		var lift := (from_position + to_position) * 0.5
		lift.y += ARC_HEIGHT
		var fan := sin(float(index) * 2.4) * 4.0
		lift += Vector3(fan, 0.0, cos(float(index) * 2.4) * 4.0)
		var inverse := 1.0 - progress
		orb.global_position = (
			from_position * inverse * inverse
			+ lift * 2.0 * inverse * progress
			+ to_position * progress * progress
		)
		orb.scale = Vector3.ONE * (0.5 + 0.5 * sin(progress * PI))

		if progress >= 1.0 and orb.visible:
			orb.visible = false
			_landed += 1
			_burst_at(orb.global_position, 22)
		if progress < 1.0:
			all_done = false

	# Flash brightens with each arrival, then decays.
	if _flash != null:
		_flash.light_energy = maxf(
			_flash.light_energy - delta * 6.0,
			float(_landed) * 1.5 * exp(-maxf(_elapsed - FLIGHT_SECONDS, 0.0) * 2.0)
		)

	if all_done and not _finished:
		_finished = true
		_burst_at(to_position, 70)
		# Give the final flare a moment before disappearing.
		get_tree().create_timer(1.2).timeout.connect(queue_free)


func _burst_at(at: Vector3, amount: int) -> void:
	var dust := SurfaceDustScript.new() as SurfaceDust
	dust.surface_normal = Vector3.UP
	dust.burst_amount = amount
	dust.burst_speed = 6.5
	dust.puff_lifetime = 0.7
	dust.puff_size = 0.3
	dust.dust_color = Color(1.0, 0.88, 0.55, 0.55)
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(dust)
	dust.global_position = at
