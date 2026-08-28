# Head-locked comfort vignette. It measures motion of the XR rig rather than
# the headset, so voluntarily looking around does not darken the view.
extends MeshInstance3D
class_name ComfortVignette

@export_node_path("Node3D") var flight_path: NodePath
@export_range(1.0, 30.0, 0.5) var full_linear_speed := 12.0
@export_range(0.2, 5.0, 0.1) var full_angular_speed := 1.2
@export_range(0.0, 1.0, 0.05) var maximum_strength := 0.75
@export_range(0.1, 20.0, 0.5) var fade_in_speed := 7.0
@export_range(0.1, 20.0, 0.5) var fade_out_speed := 2.5

const STATE_CRASHED := 1
const STATE_ARRIVED := 2
const STATE_WAITING := 3

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

	var linear_amount := clampf(linear_speed / full_linear_speed, 0.0, 1.0)
	var angular_amount := clampf(angular_speed / full_angular_speed, 0.0, 1.0)
	var target := maxf(linear_amount, angular_amount) * maximum_strength

	# Do not leave a dark aperture over menus/end states. During actual Quest
	# rendering viewport.use_xr is true; desktop preview stays unobstructed.
	var flight_state := int(_flight.get("state"))
	if (
		not get_viewport().use_xr
		or flight_state == STATE_WAITING
		or flight_state == STATE_CRASHED
		or flight_state == STATE_ARRIVED
	):
		target = 0.0

	var rate := fade_in_speed if target > _strength else fade_out_speed
	_set_strength(move_toward(_strength, target, rate * delta))


func _set_strength(value: float) -> void:
	_strength = clampf(value, 0.0, maximum_strength)
	if _material != null:
		_material.set_shader_parameter("strength", _strength)


func get_strength() -> float:
	return _strength
