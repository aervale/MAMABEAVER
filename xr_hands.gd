extends Node3D
class_name XRHandVisuals
## hand visuals for OpenXR hand tracking

const HAND_TRACKERS: Array[StringName] = [
	&"/user/hand_tracker/left",
	&"/user/hand_tracker/right",
]

const WRIST := 1

## joints per finger, wrist outwards
const FINGER_CHAINS := [
	[2, 3, 4, 5],          # Thumb
	[6, 7, 8, 9, 10],      # Index
	[11, 12, 13, 14, 15],  # Middle
	[16, 17, 18, 19, 20],  # Ring
	[21, 22, 23, 24, 25],  # Pinky
]

## Thickness of the finger models
const FINGER_THICKNESS := 0.7

## On for controller/hand, false for only controller.
@export var enabled := true:
	set = _set_enabled

## Hand tracking color, keep alpha <1 ideally
@export var hand_color := Color(0.55, 0.78, 1.0, 0.35)

## Add any offset needed for the hands here. Keep it zero likely
@export var hand_offset := Vector3.ZERO

var joint_scale := 1.0

var _hands: Array[Node3D] = []
var _joints: Array = []
var _bones: Array = []


func _ready() -> void:
	for hand in HAND_TRACKERS.size():
		_build_hand()

	set_process(enabled)


func _process(_delta: float) -> void:
	for hand in _hands.size():
		var tracker := _find_tracker(hand)
		var root: Node3D = _hands[hand]

		root.visible = _is_tracking_real_hands(tracker)
		if root.visible:
			_update_hand(hand, tracker)


func _is_tracking_real_hands(tracker: XRHandTracker) -> bool:
	if tracker == null or not tracker.get_has_tracking_data():
		return false

	var source := tracker.get_hand_tracking_source()
	return source != XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER \
		and source != XRHandTracker.HAND_TRACKING_SOURCE_NOT_TRACKED


func _update_hand(hand: int, tracker: XRHandTracker) -> void:
	var joints: Array = _joints[hand]

	# tracker hands back raw joint transforms, the camera/controller nodes do
	# this part for you. skip it and the hands sit where the rig isn't
	var reference := XRServer.get_reference_frame()
	var world_scale := XRServer.world_scale
	var offset := hand_offset

	for joint in XRHandTracker.HAND_JOINT_MAX:
		var sphere: MeshInstance3D = joints[joint]
		sphere.position = reference * (tracker.get_hand_joint_transform(joint).origin * world_scale) + offset
		sphere.scale = Vector3.ONE * tracker.get_hand_joint_radius(joint) * world_scale * joint_scale

	for bone in _bones[hand]:
		var cylinder: MeshInstance3D = bone[0]
		var from: Vector3 = reference * (tracker.get_hand_joint_transform(bone[1]).origin * world_scale) + offset
		var to: Vector3 = reference * (tracker.get_hand_joint_transform(bone[2]).origin * world_scale) + offset

		var along := to - from
		var length := along.length()
		cylinder.visible = length > 0.0001
		if not cylinder.visible:
			continue

		var radius := tracker.get_hand_joint_radius(bone[2]) * world_scale * joint_scale * FINGER_THICKNESS
		cylinder.position = from + along * 0.5
		cylinder.quaternion = Quaternion(Vector3.UP, along / length)
		cylinder.scale = Vector3(radius, length, radius)


func _find_tracker(hand: int) -> XRHandTracker:
	return XRServer.get_tracker(HAND_TRACKERS[hand]) as XRHandTracker


## Builds one hand. unit primitives scaled per frame off the joint radii, so
## both hands share the one mesh + material
func _build_hand() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = hand_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.4

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	sphere_mesh.radial_segments = 8
	sphere_mesh.rings = 4
	sphere_mesh.material = material

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 1.0
	cylinder_mesh.bottom_radius = 1.0
	cylinder_mesh.height = 1.0
	cylinder_mesh.radial_segments = 6
	cylinder_mesh.rings = 0
	cylinder_mesh.material = material

	var root := Node3D.new()
	root.name = "Hand%d" % _hands.size()
	root.visible = false
	add_child(root)

	var joints: Array = []
	for joint in XRHandTracker.HAND_JOINT_MAX:
		joints.append(_add_mesh(root, sphere_mesh))

	# wrist to finger base, then down the finger
	var bones: Array = []
	for chain in FINGER_CHAINS:
		bones.append([_add_mesh(root, cylinder_mesh), WRIST, chain[0]])
		for link in chain.size() - 1:
			bones.append([_add_mesh(root, cylinder_mesh), chain[link], chain[link + 1]])

	_hands.append(root)
	_joints.append(joints)
	_bones.append(bones)


func _add_mesh(root: Node3D, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	return instance


func _set_enabled(value: bool) -> void:
	enabled = value
	set_process(value and not _hands.is_empty())

	if not value:
		for hand: Node3D in _hands:
			hand.visible = false
