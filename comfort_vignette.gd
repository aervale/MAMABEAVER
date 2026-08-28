# Head-locked comfort vignette. It measures motion of the XR rig rather than
# the headset, so voluntarily looking around does not darken the view.
extends MeshInstance3D
class_name ComfortVignette

@export_node_path("Node3D") var flight_path: NodePath

@export_group("Surface profile")
## Walking tops out near 2.2 m/s, so the old 12 m/s scale barely reacted.
@export_range(0.0, 2.0, 0.05) var surface_linear_onset := 0.15
@export_range(0.5, 6.0, 0.1) var surface_full_linear_speed := 2.0
@export_range(0.0, 1.0, 0.05) var surface_angular_onset := 0.08
@export_range(0.2, 3.0, 0.05) var surface_full_angular_speed := 0.55
@export_range(0.0, 1.0, 0.05) var surface_maximum_strength := 0.88

@export_group("Flight profile")
@export_range(0.0, 10.0, 0.25) var flight_linear_onset := 1.5
@export_range(2.0, 30.0, 0.5) var flight_full_linear_speed := 10.0
@export_range(0.0, 1.0, 0.05) var flight_angular_onset := 0.15
@export_range(0.2, 5.0, 0.1) var flight_full_angular_speed := 1.1
@export_range(0.0, 1.0, 0.05) var flight_maximum_strength := 0.65

@export_group("Response")
## Below 1.0 makes medium motion clearly visible without waiting for maximum speed.
@export_range(0.25, 2.0, 0.05) var response_curve := 0.6
@export_range(0.1, 20.0, 0.5) var fade_in_speed := 9.0
@export_range(0.1, 20.0, 0.5) var fade_out_speed := 3.0

const STATE_CRASHED := 1
const STATE_ARRIVED := 2
const STATE_WAITING := 3
const STATE_LANDED := 4

var _flight: Node3D
var _material: ShaderMaterial
var _last_position := Vector3.ZERO
var _last_basis := Basis.IDENTITY
var _has_previous_sample := false
var _strength := 0.0


func _ready() -> void:
	_flight = get_node_or_null(flight_path) as Node3D
	if mesh != null:
		_material = mesh.surface_get_material(0) as ShaderMaterial
	_set_strength(0.0)


func _process(delta: float) -> void:
	if _flight == null or _material == null or delta <= 0.0:
		return

	var position_now := _flight.global_position
	var basis_now := _flight.global_basis.orthonormalized()
	if not _has_previous_sample:
		_last_position = position_now
		_last_basis = basis_now
		_has_previous_sample = true
		return

	var linear_speed := position_now.distance_to(_last_position) / delta
	var angular_step := maxf(
		basis_now.y.angle_to(_last_basis.y),
		basis_now.z.angle_to(_last_basis.z)
	)
	var angular_speed := angular_step / delta
	_last_position = position_now
	_last_basis = basis_now

	# Do not leave a dark aperture over menus/end states. During actual Quest
	# rendering viewport.use_xr is true; desktop preview stays unobstructed.
	var flight_state := int(_flight.get("state"))
	var on_surface := flight_state == STATE_LANDED
	var linear_amount := _motion_amount(
		linear_speed,
		surface_linear_onset if on_surface else flight_linear_onset,
		surface_full_linear_speed if on_surface else flight_full_linear_speed
	)
	var angular_amount := _motion_amount(
		angular_speed,
		surface_angular_onset if on_surface else flight_angular_onset,
		surface_full_angular_speed if on_surface else flight_full_angular_speed
	)
	var motion_amount := pow(maxf(linear_amount, angular_amount), response_curve)
	var profile_maximum := (
		surface_maximum_strength if on_surface else flight_maximum_strength
	)
	var target := motion_amount * profile_maximum

	if (
		not get_viewport().use_xr
		or flight_state == STATE_WAITING
		or flight_state == STATE_CRASHED
		or flight_state == STATE_ARRIVED
	):
		target = 0.0

	var rate := fade_in_speed if target > _strength else fade_out_speed
	_set_strength(move_toward(_strength, target, rate * delta))


func _motion_amount(value: float, onset: float, full_value: float) -> float:
	return clampf(inverse_lerp(onset, maxf(full_value, onset + 0.001), value), 0.0, 1.0)


func _set_strength(value: float) -> void:
	_strength = clampf(value, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("strength", _strength)


func get_strength() -> float:
	return _strength
