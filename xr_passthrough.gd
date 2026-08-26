extends Node
class_name XRPassthrough

@export var enabled := false:
	set(value):
		enabled = value
		if _ready_to_apply:
			_apply(value)

@export_node_path("WorldEnvironment") var world_environment: NodePath

## anything that would get drawn over the real room
@export var hide_in_passthrough: Array[NodePath] = []

var _xr: XRInterface = null
var _environment: Environment = null
var _original_background := Environment.BG_SKY

# cached at startup so switching passthrough back off doesnt unhide
# something that was already hidden
var _hidden: Array[Node3D] = []
var _hidden_was_visible: Array[bool] = []

# export setters run during scene load, way before theres an interface to
# talk to. until this flips the setter just stores the value
var _ready_to_apply := false


func _ready() -> void:
	_xr = XRServer.find_interface("OpenXR")
	if _xr == null:
		push_error("XRPassthrough|FATAL: no OpenXR interface, passthrough cannot be switched on")
		return

	var world: WorldEnvironment = get_node_or_null(world_environment)
	if world != null and world.environment != null:
		_environment = world.environment
		_original_background = _environment.background_mode
	else:
		push_warning("XRPassthrough|WARN: no WorldEnvironment assigned, the sky will cover the camera feed")

	for path in hide_in_passthrough:
		var node := get_node_or_null(path) as Node3D
		_hidden.append(node)
		_hidden_was_visible.append(node.visible)

	# blend mode only means anything once the session is actually running
	_xr.session_begun.connect(_on_session_begun)


func _on_session_begun() -> void:
	_ready_to_apply = true
	_apply(enabled)


## Apply the actual switch
func _apply(enable: bool) -> void:
	var mode := XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if enable \
		else XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	_xr.set_environment_blend_mode(mode)
	get_viewport().transparent_bg = enable

	if _environment != null:
		if enable:
			_environment.background_mode = Environment.BG_COLOR
			_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		else:
			_environment.background_mode = _original_background

	# visibility only. a hidden floor still collides, props land on it fine
	for i in _hidden.size():
		_hidden[i].visible = _hidden_was_visible[i] and not enable

	print("XRPassthrough|INFO: passthrough %s" % ("on" if enable else "off"))
