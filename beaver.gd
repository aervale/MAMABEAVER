# =============================================================================
# beaver.gd — one collectible beaver (Tim's army). Spawned at runtime by
# beaver_director.gd as a child of a hazard planet, standing on the surface
# near the flight plane.
#
# STATES: IDLE (standing on its planet, bobbing) -> TRACTORED (hit by a magic
# bolt; eases to the ship over ~1.5s, shrinking and spinning) -> CARGO
# (invisible, riding in the ship, counted by the director) -> DELIVERED
# (banked at MIT). reset_to_spawn() returns it to IDLE at its spawn point
# from ANY state — including mid-tractor.
#
# VISUAL: if the director injects `model_scene` (the CC-BY Sketchfab "Beaver
# Inc" model, see MODEL_ATTRIBUTION.md), it's normalized to target_height
# via the same merged-AABB rescale pattern as moon_presenter.gd. Otherwise a
# procedural ~15-primitive beaver is built in code (mit_destination.gd
# style): brown body, flat tail, buck teeth. No lights, no shadows — up to
# ~30 of these exist at once on Quest.
#
# The director orients the node so local +Y is the planet's surface normal
# and local +Z faces outward; the visual is built face-forward on +Z.
# =============================================================================
extends Node3D
class_name BeaverCritter

signal collected(beaver: Node3D)

enum BeaverState {
	IDLE,
	TRACTORED,
	CARGO,
	DELIVERED,
}

## Beyond this distance from the viewer a beaver stops animating. Fifty
## skinned meshes each running an AnimationPlayer is what made the scene
## crawl; you cannot see a 1.2 m animation loop from 70 m away anyway.
const ANIMATION_DISTANCE := 70.0
const ANIMATION_CHECK_SECONDS := 0.5

const TRACTOR_DURATION := 1.5
const BOB_HEIGHT := 0.06
const BOB_SPEED := 2.2

## Injected by the director BEFORE add_child (so _ready sees them).
var model_scene: PackedScene = null
var target_height := 0.9

var state := BeaverState.IDLE

var _visual_root: Node3D
## AnimationPlayer from the imported model, if it ships with one.
var _animator: AnimationPlayer
var _idle_clip := ""
var _animation_check := 0.0
var _animation_awake := true
var _flight: Node3D
var _home_parent: Node3D
var _home_transform: Transform3D
var _tractor_from := Vector3.ZERO
var _tractor_elapsed := 0.0
var _bob_phase := 0.0


func _ready() -> void:
	mark_home()
	_bob_phase = randf() * TAU
	_build_visual()


## Records the current parent + local transform as the spawn point that
## reset_to_spawn() restores.
## FOOTGUN: add_child() runs _ready() immediately, so at that moment the
## director has NOT applied the placement transform yet. The director calls
## this again right after placing the beaver — without that second call
## every reset would teleport all beavers to their planet's centre (i.e.
## inside the moon, where they look like they vanished).
func mark_home() -> void:
	_home_parent = get_parent() as Node3D
	_home_transform = transform


func _process(delta: float) -> void:
	match state:
		BeaverState.IDLE:
			# The imported model animates itself; the hand-rolled bob is only
			# for the procedural fallback, and running both looks wrong.
			if _animator != null:
				_update_animation_distance(delta)
				return
			# Gentle bob sells "alive" for the cost of one sine per frame.
			_bob_phase += delta * BOB_SPEED
			if _visual_root != null:
				_visual_root.position.y = absf(sin(_bob_phase)) * BOB_HEIGHT
		BeaverState.TRACTORED:
			_advance_tractor(delta)


## Called by the director when a magic bolt connects. Reparents to the scene
## root (so the beaver's flight isn't dragged around by its planet's frame)
## and starts easing toward the ship.
func begin_tractor(flight: Node3D) -> bool:
	if state != BeaverState.IDLE:
		return false
	state = BeaverState.TRACTORED
	_flight = flight
	_tractor_elapsed = 0.0
	_play_clip(TRACTOR_CLIP)
	var keep_transform := global_transform
	var scene_root := get_tree().current_scene
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_transform = keep_transform
	_tractor_from = global_position
	return true


func _advance_tractor(delta: float) -> void:
	_tractor_elapsed += delta
	var progress := clampf(_tractor_elapsed / TRACTOR_DURATION, 0.0, 1.0)
	# Ease-in toward the ship's LIVE position — the player may still move.
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var target := global_position
	if _flight != null and _flight.has_method("get_spacecraft_world_position"):
		target = _flight.call("get_spacecraft_world_position")
	global_position = _tractor_from.lerp(target, eased)
	scale = Vector3.ONE * (1.0 - 0.4 * eased)
	rotate_y(delta * 9.0)

	if progress >= 1.0:
		state = BeaverState.CARGO
		visible = false
		if _animator != null:
			_animator.stop()
		collected.emit(self)


## Full restore to the spawn point, from any state (incl. mid-tractor).
func reset_to_spawn() -> void:
	if get_parent() != _home_parent and _home_parent != null:
		get_parent().remove_child(self)
		_home_parent.add_child(self)
	transform = _home_transform
	scale = Vector3.ONE
	visible = true
	state = BeaverState.IDLE
	_tractor_elapsed = 0.0
	# Back on the surface: return to the idle clip, not the swim.
	if _animator != null and not _idle_clip.is_empty():
		_play_clip(_idle_clip)


func mark_delivered() -> void:
	state = BeaverState.DELIVERED


# --- visuals -----------------------------------------------------------------

func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BeaverVisual"
	add_child(_visual_root)

	if model_scene != null:
		_build_imported_visual()
	else:
		_build_procedural_visual()


func _build_imported_visual() -> void:
	var imported := model_scene.instantiate() as Node3D
	if imported == null:
		push_warning("BeaverCritter|WARN: model root is not Node3D, using fallback")
		_build_procedural_visual()
		return
	_visual_root.add_child(imported)

	# Same merged-AABB normalization as moon_presenter.gd, but height-based
	# (beavers should be target_height tall regardless of source units).
	var bounds := AABB()
	var has_bounds := false
	var pending: Array[Node] = [imported]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_instance := node as MeshInstance3D
			var relative := imported.global_transform.affine_inverse() * mesh_instance.global_transform
			var mesh_bounds := relative * mesh_instance.get_aabb()
			bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
			has_bounds = true
		for child in node.get_children():
			pending.append(child)

	if not has_bounds or bounds.size.y <= 0.0001:
		push_warning("BeaverCritter|WARN: model has no usable bounds, using fallback")
		imported.queue_free()
		_build_procedural_visual()
		return

	# Skinned meshes are culled against their BIND-POSE bounds, and a small
	# or stale AABB makes Godot skip the skeleton update — the beaver keeps
	# "playing" but stops visibly moving once it is far away or near the
	# edge of view. A generous cull margin keeps them animating.
	for node in _all_nodes(imported):
		if node is MeshInstance3D:
			(node as MeshInstance3D).extra_cull_margin = 8.0
		elif node is Skeleton3D:
			# Keep posing the skeleton even when the mesh is off-screen.
			(node as Skeleton3D).motion_scale = 1.0

	var uniform_scale := target_height / bounds.size.y
	imported.scale = Vector3.ONE * uniform_scale
	# Feet on the surface: lift so the bounds' bottom sits at local y = 0.
	imported.position = Vector3(0.0, -bounds.position.y * uniform_scale, 0.0)
	_start_model_animation(imported)


## Animation clips shipped ALONGSIDE the mesh rather than inside it. The
## Sketchfab beaver splits every action into its own FBX, so the mesh file
## only carries a bind pose ("Take 001") and the real motion has to be
## merged onto its AnimationPlayer at runtime.
const EXTRA_ANIMATIONS := [
	"res://models/beaver/animations/Idle_Walk.fbx",
	"res://models/beaver/animations/Walk.fbx",
	"res://models/beaver/animations/Swim.fbx",
]

## Clip played while a beaver is being tractored through space — it is
## swimming up to the ship, which is exactly what the archive's Swim clip
## looks like.
const TRACTOR_CLIP := "Swim"


## Clips harvested from the standalone animation files, loaded ONCE and
## shared by every beaver.
##
## This cache is not an optimisation, it is a fix: harvesting meant
## instantiating each donor FBX to reach its AnimationPlayer, and doing
## that per beaver meant thirty beavers instantiated ninety extra skinned
## scenes at load. Scene build time went from minutes back to instant.
static var _shared_clips: Dictionary = {}
static var _shared_clips_ready := false


static func _load_shared_clips() -> void:
	if _shared_clips_ready:
		return
	_shared_clips_ready = true
	for path in EXTRA_ANIMATIONS:
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var temporary := packed.instantiate()
		var pending: Array[Node] = [temporary]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			if node is AnimationPlayer:
				var source := node as AnimationPlayer
				for clip_name in source.get_animation_list():
					var clip := source.get_animation(clip_name)
					if clip != null and not _shared_clips.has(clip_name):
						_shared_clips[clip_name] = clip
				break
			for child in node.get_children():
				pending.append(child)
		temporary.free()


## Attach the shared clips to this beaver's own player. The files are all
## exported from the same rig, so the track paths line up.
func _merge_external_animations() -> void:
	if _animator == null:
		return
	_load_shared_clips()
	var library := _animator.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		_animator.add_animation_library("", library)
	for clip_name in _shared_clips:
		if not library.has_animation(clip_name):
			library.add_animation(clip_name, _shared_clips[clip_name])


## Pause the animation for beavers too far away to see moving. Every
## beaver keeps its real model — capping the model count instead would have
## brought back the exact "only some planets have proper beavers" problem —
## so the saving comes from the mixer, not the mesh.
## Checks are staggered and throttled, so this costs almost nothing.
func _update_animation_distance(delta: float) -> void:
	_animation_check -= delta
	if _animation_check > 0.0:
		return
	# Stagger so fifty beavers never test on the same frame.
	_animation_check = ANIMATION_CHECK_SECONDS * (0.75 + randf() * 0.5)

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var near := global_position.distance_to(camera.global_position) <= ANIMATION_DISTANCE
	if near == _animation_awake:
		return
	_animation_awake = near
	if near:
		_animator.play(_idle_clip if not _idle_clip.is_empty() else _animator.assigned_animation)
	else:
		_animator.pause()


## Switch clips if the model actually has the requested one; silently do
## nothing for the procedural fallback, which has no animator at all.
func _play_clip(clip_name: String) -> void:
	if _animator == null or not _animator.has_animation(clip_name):
		return
	var clip := _animator.get_animation(clip_name)
	if clip != null:
		clip.loop_mode = Animation.LOOP_LINEAR
	_animator.play(clip_name)


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		out.append(node)
		for child in node.get_children():
			pending.append(child)
	return out


func _find_animation_player(root: Node) -> AnimationPlayer:
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is AnimationPlayer:
			return node as AnimationPlayer
		for child in node.get_children():
			pending.append(child)
	return null


## Play the imported model's idle animation on a loop, if it has one.
##
## Exports name their clips whatever the original rig used, so rather than
## hardcoding a name we prefer anything that looks like an idle and
## otherwise fall back to the first clip. The loop mode is forced on: many
## exports ship clips set to play once, which would leave the beaver frozen
## on its last frame after a second or two.
func _start_model_animation(model_root: Node) -> void:
	_animator = _find_animation_player(model_root)
	if _animator == null:
		return
	_merge_external_animations()

	var clips := _animator.get_animation_list()
	if clips.is_empty():
		_animator = null
		return

	# "Take 001" is the FBX bind pose, not motion — never pick it if a real
	# clip is available.
	var chosen: String = clips[0]
	for clip in clips:
		var lowered := String(clip).to_lower()
		if lowered.contains("idle") or lowered.contains("loop"):
			chosen = clip
			break
		if chosen.to_lower().begins_with("take") and not lowered.begins_with("take"):
			chosen = clip

	var animation := _animator.get_animation(chosen)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	# Stagger playback so a planet's worth of beavers is not in lockstep.
	_idle_clip = chosen
	# Without this the mixer stops advancing whenever the node tree decides
	# the beaver is not visible, which is what froze the distant ones.
	_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_animator.play(chosen)
	_animator.seek(randf() * maxf(animation.length if animation != null else 1.0, 0.01), true)
	print("BeaverCritter|INFO: playing imported animation '%s'" % chosen)


func _build_procedural_visual() -> void:
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.42, 0.27, 0.16)
	fur.roughness = 0.9

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.24, 0.14, 0.09)
	dark.roughness = 0.95

	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.93, 0.85)
	white.roughness = 0.4

	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.05, 0.04, 0.04)
	black.roughness = 0.3

	# Chunky hunched body reads as "beaver" even at 20 m.
	var body := SphereMesh.new()
	body.radius = 0.28
	body.height = 0.56
	body.radial_segments = 24
	body.rings = 14
	body.material = fur
	_add_part(body, Vector3(0.0, 0.3, 0.0)).scale = Vector3(1.0, 1.0, 1.2)

	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	head.radial_segments = 20
	head.rings = 12
	head.material = fur
	_add_part(head, Vector3(0.0, 0.56, 0.2))

	var muzzle := SphereMesh.new()
	muzzle.radius = 0.09
	muzzle.height = 0.18
	muzzle.radial_segments = 16
	muzzle.rings = 10
	muzzle.material = dark
	_add_part(muzzle, Vector3(0.0, 0.5, 0.34))

	# The famous teeth — the single most identifying beaver feature.
	var tooth := BoxMesh.new()
	tooth.size = Vector3(0.035, 0.06, 0.02)
	tooth.material = white
	_add_part(tooth, Vector3(-0.022, 0.43, 0.4))
	_add_part(tooth, Vector3(0.022, 0.43, 0.4))

	var eye := SphereMesh.new()
	eye.radius = 0.028
	eye.height = 0.056
	eye.radial_segments = 12
	eye.rings = 8
	eye.material = black
	_add_part(eye, Vector3(-0.07, 0.62, 0.32))
	_add_part(eye, Vector3(0.07, 0.62, 0.32))

	var ear := SphereMesh.new()
	ear.radius = 0.04
	ear.height = 0.08
	ear.radial_segments = 14
	ear.rings = 8
	ear.material = dark
	_add_part(ear, Vector3(-0.1, 0.7, 0.14))
	_add_part(ear, Vector3(0.1, 0.7, 0.14))

	# Flat paddle tail, slightly tilted onto the ground behind it.
	var tail := BoxMesh.new()
	tail.size = Vector3(0.22, 0.05, 0.34)
	tail.material = dark
	var tail_part := _add_part(tail, Vector3(0.0, 0.08, -0.4))
	tail_part.rotation_degrees = Vector3(-12.0, 0.0, 0.0)

	# Rounded feet and stubby arms: the boxy silhouette read as low-poly
	# even at distance, and these are cheap to add.
	var foot := SphereMesh.new()
	foot.radius = 0.075
	foot.height = 0.15
	foot.radial_segments = 14
	foot.rings = 8
	foot.material = dark
	_add_part(foot, Vector3(-0.13, 0.06, 0.1)).scale = Vector3(0.85, 0.6, 1.4)
	_add_part(foot, Vector3(0.13, 0.06, 0.1)).scale = Vector3(0.85, 0.6, 1.4)

	var arm := SphereMesh.new()
	arm.radius = 0.07
	arm.height = 0.14
	arm.radial_segments = 12
	arm.rings = 8
	arm.material = fur
	_add_part(arm, Vector3(-0.24, 0.34, 0.12)).scale = Vector3(0.8, 1.5, 0.8)
	_add_part(arm, Vector3(0.24, 0.34, 0.12)).scale = Vector3(0.8, 1.5, 0.8)

	# Rounded haunches blend the body into the tail.
	var haunch := SphereMesh.new()
	haunch.radius = 0.15
	haunch.height = 0.3
	haunch.radial_segments = 16
	haunch.rings = 10
	haunch.material = fur
	_add_part(haunch, Vector3(-0.17, 0.17, -0.14)).scale = Vector3(1.0, 0.85, 1.2)
	_add_part(haunch, Vector3(0.17, 0.17, -0.14)).scale = Vector3(1.0, 0.85, 1.2)


func _add_part(mesh: Mesh, at: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual_root.add_child(instance)
	return instance
