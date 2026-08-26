extends Node3D
class_name XRControllerVisuals

## Controller visuals for OpenXR

const EXPECTED_POSE := &"grip"

@export_node_path("XRController3D") var left_controller: NodePath
@export_node_path("XRController3D") var right_controller: NodePath

@export var left_model: PackedScene
@export var right_model: PackedScene

@export_group("Fine tuning")
@export var model_offset := Vector3.ZERO
@export var model_rotation := Vector3.ZERO


func _ready() -> void:
	_attach(left_controller, left_model)
	_attach(right_controller, right_model)


func _attach(controller_path: NodePath, model: PackedScene) -> void:
	var controller := get_node_or_null(controller_path) as XRController3D

	var instance := model.instantiate() as Node3D

	instance.name = "ControllerModel"
	instance.position = model_offset
	instance.rotation_degrees = model_rotation
	controller.add_child(instance)
