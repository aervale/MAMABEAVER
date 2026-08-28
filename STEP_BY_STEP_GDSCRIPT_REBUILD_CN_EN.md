# VR at MIT：GDScript 逐步人工重建教程 / Step-by-Step GDScript Rebuild Guide

本文回答一个具体问题：**如果手里只有 `vratmit-manual-rebuild` 文件夹，怎样不直接复制完成版代码，而是从初始模板开始，逐步亲手写出游戏？**

This guide answers one specific question: **if `vratmit-manual-rebuild` is the only folder available, how can the game be rebuilt from the initial template by writing the gameplay code step by step instead of simply copying the finished project?**

---

## 0. “人工重建”到底要不要每行代码都自己写？ / Does a manual rebuild mean writing every line?

学习式人工重建时，下面这些内容应该自己创建或修改：

- 8 个主要游戏脚本：`main.gd`、`desktop_orbit_camera.gd`、`moon_presenter.gd`、`mit_destination.gd`、`black_hole.gd`、`spaceship_flight.gd`、`flight_minimap.gd`、`vr_minimap_presenter.gd`。
- `main.tscn` 中新增的节点、位置、脚本挂载和 Inspector 参数。
- 地板、灯光、HUD、15 个天体以及 MIT 终点的场景配置。

For a learning-oriented manual rebuild, create or modify these items yourself:

- The eight main gameplay scripts listed above.
- The new nodes, transforms, script attachments, and Inspector values in `main.tscn`.
- The floor, lighting, HUD, 15 celestial bodies, and MIT destination scene configuration.

下面这些内容**不需要手写**：

- `.gd.uid`、`.import` 和 `.godot/`：它们由 Godot 自动生成。
- FBX、PNG、GLB、ZIP：它们是导入的模型或纹理资产。
- `addons/godotopenxrvendors` 和 `android/build`：它们是插件或 Android 构建支持文件。
- 初始模板已经提供的 `xr_hands.gd`、`xr_visuals.gd`、`xr_passthrough.gd`、`gdscript_tutorial.gd`：先保留，不必重新输入全部代码。

The following items should **not** be typed manually:

- `.gd.uid`, `.import`, and `.godot/`; Godot generates them.
- FBX, PNG, GLB, and ZIP assets.
- The OpenXR vendor add-on and Android build support files.
- Template-provided XR helper scripts; keep them initially instead of retyping them.

`02_rebuilt_project` 是答案和对照，不是第一步的复制来源。建议每完成一个阶段并测试后，再打开对应完成版脚本对照差异。

`02_rebuilt_project` is the answer key and reference, not the source to copy at the beginning. Compare with it only after completing and testing each stage.

---

## 1. 总体操作顺序 / Overall workflow

### 第一步：创建工作副本 / Step 1: Create a working copy

1. 在 Finder 中复制 `01_initial_template`。
2. 把副本命名为 `vratmit-rebuild-working`。
3. 不要修改原始 `01_initial_template`。

1. Duplicate `01_initial_template` in Finder.
2. Rename the copy to `vratmit-rebuild-working`.
3. Keep the original `01_initial_template` unchanged.

**效果 / Result**

- 中文：得到一个可以随时修改、失败后可以重新开始的独立 Godot 工程。
- English: You now have an independent Godot project that can be edited freely and recreated if a step goes wrong.

### 第二步：导入 Godot 项目 / Step 2: Import the Godot project

1. 启动 Godot 4.7.2 stable。
2. 选择“导入 / Import”。
3. 选择 `vratmit-rebuild-working/project.godot`。
4. 等待 Godot 完成首次导入，不要手动复制 `.godot/`。

**效果 / Result**

- 中文：模板场景能够运行，头显存在时使用 OpenXR，没有头显时暂时可能无法正常预览；后面的 `main.gd` 会补上桌面模式。
- English: The template scene can run with OpenXR. Desktop fallback may not work yet; the rebuilt `main.gd` will add it.

### 第三步：准备输入资产 / Step 3: Prepare input assets

把 `00_inputs` 中的模型解压到工作项目：

```text
vratmit-rebuild-working/
└── source/
    ├── moon.fbx
    ├── moon_color.png
    ├── moon_normal.png
    ├── moon_rough.png
    └── black_hole/
        ├── source/black hole.fbx
        └── textures/...
```

保持黑洞 ZIP 内部的相对路径。把 `obstacle_layout.csv` 放在项目外也可以，因为数据最终录入 `main.tscn`。

Preserve the relative paths inside the black-hole ZIP. The CSV may remain outside the Godot project because its values will be entered into `main.tscn`.

**效果 / Result**

- 中文：Godot 文件系统面板中可以看到并导入 Moon 和 Black Hole 模型。
- English: The Moon and Black Hole models appear and import successfully in Godot's FileSystem panel.

### 第四步：按依赖顺序写脚本 / Step 4: Write scripts in dependency order

推荐顺序：

```text
main.gd
  ↓
desktop_orbit_camera.gd
  ↓
moon_presenter.gd
  ↓
mit_destination.gd
  ↓
black_hole.gd
  ↓
spaceship_flight.gd
  ↓
flight_minimap.gd
  ↓
vr_minimap_presenter.gd
```

先让每个脚本单独产生可见结果，再进入下一个脚本。不要一次写完八个脚本之后才第一次运行。

Make each script produce a visible, testable result before moving to the next one. Do not wait until all eight scripts are written before running the project.

---

## 2. `main.gd`：VR/桌面启动管理 / VR and desktop startup management

脚本挂载位置：`Main` 根节点。

Attach the script to the root `Main` node.

### 第一步：声明运行状态 / Step 1: Declare runtime state

用下面内容替换模板 `main.gd` 的开头：

```gdscript
extends Node3D

signal runtime_mode_changed(is_xr: bool)

var xr_interface: OpenXRInterface
var is_xr_mode := false

@export var target_refresh_rate := 72.0
```

**效果 / Result**

- 中文：主节点可以保存当前是否为 XR 模式，并可向其他节点广播模式变化。
- English: The main node can store whether XR mode is active and broadcast runtime-mode changes to other nodes.

### 第二步：启动时检测 OpenXR / Step 2: Detect OpenXR at startup

```gdscript
func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr_interface != null and xr_interface.is_initialized():
		_start_xr_mode()
	else:
		_start_desktop_mode()
```

不要在这里强制重复调用 `initialize()`；没有安装 XR runtime 的电脑可能因此卡住。

Do not force another `initialize()` call here; a computer without an XR runtime may stall.

**效果 / Result**

- 中文：同一个项目可以根据当前环境自动选择 Quest 或桌面预览。
- English: The same project automatically chooses Quest/XR mode or desktop-preview mode.

### 第三步：实现 XR 模式 / Step 3: Implement XR mode

```gdscript
func _start_xr_mode() -> void:
	is_xr_mode = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_viewport().use_xr = true

	var desktop_camera := get_node_or_null("DesktopCamera") as Camera3D
	if desktop_camera != null:
		desktop_camera.current = false
		desktop_camera.set_process(false)
		desktop_camera.set_process_input(false)

	var desktop_hud := get_node_or_null("DesktopHUD") as CanvasLayer
	if desktop_hud != null:
		desktop_hud.visible = false
	var ship_marker := get_node_or_null("XROrigin3D/ShipMarker") as MeshInstance3D
	if ship_marker != null:
		ship_marker.visible = false
	var flight_hud := get_node_or_null("XROrigin3D/XRCamera3D/FlightHUD") as Label3D
	if flight_hud != null:
		flight_hud.visible = true
	var vr_minimap := get_node_or_null("XROrigin3D/XRCamera3D/VRMiniMap") as Node3D
	if vr_minimap != null:
		vr_minimap.visible = true

	if not xr_interface.session_begun.is_connected(_on_session_begun):
		xr_interface.session_begun.connect(_on_session_begun)
	runtime_mode_changed.emit(true)
```

**效果 / Result**

- 中文：连接头显时关闭桌面摄像机和桌面 HUD，只显示 XRCamera、VR HUD 和 VR 小地图。
- English: With a headset active, the desktop camera and HUD are disabled while the XR camera, VR HUD, and VR minimap are shown.

### 第四步：实现桌面模式 / Step 4: Implement desktop mode

创建 `_start_desktop_mode()`，执行与 XR 模式相反的显示切换：

```gdscript
func _start_desktop_mode() -> void:
	is_xr_mode = false
	get_viewport().use_xr = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 0

	var desktop_camera := get_node_or_null("DesktopCamera") as Camera3D
	if desktop_camera != null:
		desktop_camera.current = true
		desktop_camera.set_process(true)
		desktop_camera.set_process_input(true)

	var desktop_hud := get_node_or_null("DesktopHUD") as CanvasLayer
	if desktop_hud != null:
		desktop_hud.visible = true
	var ship_marker := get_node_or_null("XROrigin3D/ShipMarker") as MeshInstance3D
	if ship_marker != null:
		ship_marker.visible = true
	var flight_hud := get_node_or_null("XROrigin3D/XRCamera3D/FlightHUD") as Label3D
	if flight_hud != null:
		flight_hud.visible = false
	var vr_minimap := get_node_or_null("XROrigin3D/XRCamera3D/VRMiniMap") as Node3D
	if vr_minimap != null:
		vr_minimap.visible = false

	print("Main|INFO: no active headset; starting desktop preview mode")
	runtime_mode_changed.emit(false)
```

**效果 / Result**

- 中文：Mac 上即使没有 Quest，也能直接运行并看到桌面测试画面。
- English: The project can run and display a desktop test view on the Mac even when no Quest headset is connected.

### 第五步：同步头显与物理刷新率 / Step 5: Match display and physics refresh rates

```gdscript
func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("Main|WARN: %s Hz unavailable, runtime offers %s" % [target_refresh_rate, rates])

	var actual: float = xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
```

**效果 / Result**

- 中文：Quest 会优先使用 72 Hz，并让物理更新频率和实际显示刷新率一致。
- English: Quest prefers 72 Hz, and the physics tick rate follows the actual headset refresh rate.

### 本脚本检查点 / Checkpoint

- 不连接 Quest，按 F6，应出现桌面窗口而不是卡在 OpenXR 初始化。
- 连接 Quest 后，应隐藏 `DesktopHUD` 并启用 XR viewport。
- 参考答案：[`02_rebuilt_project/main.gd`](02_rebuilt_project/main.gd)。

---

## 3. `desktop_orbit_camera.gd`：无头显调试摄像机 / No-headset debug camera

先在 `Main` 下创建：

```text
Main
├── SceneViewTarget (Node3D, position = 50, 9, 50)
└── DesktopCamera (Camera3D)
```

把脚本挂到 `DesktopCamera`，再把 `target_path` 指向 `../SceneViewTarget`。

Attach this script to `DesktopCamera`, then set `target_path` to `../SceneViewTarget`.

### 第一步：暴露相机参数 / Step 1: Expose camera parameters

```gdscript
extends Camera3D
class_name DesktopOrbitCamera

@export_node_path("Node3D") var target_path: NodePath
@export_range(1.2, 250.0, 0.1) var distance := 145.0
@export_range(0.1, 2.0, 0.05) var orbit_sensitivity := 0.35
@export_range(0.1, 2.0, 0.05) var keyboard_speed := 0.8
@export var initial_yaw_degrees := 0.0
@export var initial_pitch_degrees := 45.0
@export var use_z_up := false

var _target: Node3D
var _yaw := 0.0
var _pitch := 0.0
var _dragging := false
var _initial_distance := 145.0
```

**效果 / Result**

- 中文：距离、初始角度和控制灵敏度可以直接在 Inspector 调整。
- English: Distance, starting angles, and control sensitivity can be tuned directly in the Inspector.

### 第二步：初始化视角 / Step 2: Initialize the view

```gdscript
func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_initial_distance = distance
	_reset_view()

func _reset_view() -> void:
	_yaw = deg_to_rad(initial_yaw_degrees)
	_pitch = deg_to_rad(initial_pitch_degrees)
	distance = _initial_distance
	_update_camera()
```

**效果 / Result**

- 中文：运行后相机自动围绕场地中心观察整个 140×140 区域。
- English: At runtime the camera automatically frames the 140×140 play area around its center.

### 第三步：添加鼠标和键盘控制 / Step 3: Add mouse and keyboard controls

实现以下输入：左键拖动旋转、滚轮缩放、方向键旋转、`Esc` 退出。

Implement left-drag orbiting, wheel zoom, arrow-key orbiting, and `Esc` to quit.

```gdscript
func _process(delta: float) -> void:
	if not current or _target == null:
		return
	var horizontal := Input.get_axis("ui_left", "ui_right")
	var vertical := Input.get_axis("ui_up", "ui_down")
	if not is_zero_approx(horizontal) or not is_zero_approx(vertical):
		_yaw -= horizontal * keyboard_speed * delta
		_pitch = clampf(_pitch + vertical * keyboard_speed * delta, -1.35, 1.35)
		_update_camera()

func _input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = maxf(1.2, distance * 0.9)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = minf(250.0, distance * 1.1)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= deg_to_rad(event.relative.x * orbit_sensitivity)
		_pitch = clampf(_pitch - deg_to_rad(event.relative.y * orbit_sensitivity), -1.35, 1.35)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
```

**效果 / Result**

- 中文：不戴头显也可以从各个角度检查场景、模型位置和飞船运动。
- English: The scene, model placement, and ship movement can be inspected from multiple angles without wearing a headset.

### 第四步：计算轨道位置 / Step 4: Calculate the orbit position

```gdscript
func _update_camera() -> void:
	if _target == null:
		return
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * distance
	global_position = _target.global_position + offset
	look_at(_target.global_position, Vector3.UP)
```

**效果 / Result**

- 中文：相机始终看向 `SceneViewTarget`，拖动只改变环绕角度，不改变观察中心。
- English: The camera always looks at `SceneViewTarget`; dragging changes the orbit angle without losing the scene center.

### 本脚本检查点 / Checkpoint

- 桌面运行时能够左键拖动和滚轮缩放。
- Inspector 建议值：`distance=145`、`initial_pitch_degrees=45`。
- 参考答案：[`02_rebuilt_project/desktop_orbit_camera.gd`](02_rebuilt_project/desktop_orbit_camera.gd)。

---

## 4. `moon_presenter.gd`：加载、贴图和统一缩放行星 / Load, texture, and normalize planets

在 `Main` 下创建 `MoonExhibit (Node3D)`，再创建一个 `Planet01 (Node3D)`，把新脚本挂到 `Planet01`。

Create `MoonExhibit (Node3D)` under `Main`, then create `Planet01 (Node3D)` and attach the new script to it.

### 第一步：定义可配置资源 / Step 1: Define configurable resources

```gdscript
@tool
extends Node3D
class_name MoonPresenter

@export var model_scene: PackedScene
@export var albedo_texture: Texture2D
@export var normal_texture: Texture2D
@export var roughness_texture: Texture2D
@export_range(0.25, 100.0, 0.05) var target_diameter_meters := 12.0
@export_range(-30.0, 30.0, 0.1) var rotation_speed_degrees := 0.0

var _model_root: Node3D
```

`@tool` 让脚本在编辑器中也能生成预览。`target_diameter_meters` 是直径，不是半径。

`@tool` allows the script to generate a preview in the editor. `target_diameter_meters` is a diameter, not a radius.

**效果 / Result**

- 中文：Inspector 中出现模型、三张 PBR 贴图、目标直径和转速选项。
- English: The Inspector exposes the model, three PBR textures, target diameter, and rotation speed.

### 第二步：实例化外部模型 / Step 2: Instantiate the external model

```gdscript
func _ready() -> void:
	if model_scene == null:
		push_error("MoonPresenter|FATAL: no Moon model scene assigned")
		return
	_model_root = model_scene.instantiate() as Node3D
	if _model_root == null:
		push_error("MoonPresenter|FATAL: Moon model root is not Node3D")
		return
	_model_root.name = "MoonModel"
	add_child(_model_root)
	_apply_pbr_material()
	_normalize_model_size()
```

**效果 / Result**

- 中文：把 `moon.fbx` 拖进 `model_scene` 后，Planet 节点下面会生成 Moon 模型。
- English: After assigning `moon.fbx` to `model_scene`, a Moon model appears under the Planet node.

### 第三步：递归寻找网格 / Step 3: Find meshes recursively

FBX 的根节点通常不是网格，所以要遍历全部子节点：

```gdscript
func _find_mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			result.append(node as MeshInstance3D)
		for child in node.get_children():
			pending.append(child)
	return result
```

**效果 / Result**

- 中文：无论 FBX 内部嵌套多少层，都能找到真正需要赋材质和测尺寸的网格。
- English: Meshes can be found for material assignment and size measurement regardless of FBX nesting depth.

### 第四步：创建 PBR 材质 / Step 4: Create the PBR material

```gdscript
func _apply_pbr_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo_texture
	material.roughness = 1.0
	material.roughness_texture = roughness_texture
	material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	material.normal_enabled = normal_texture != null
	material.normal_texture = normal_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	for mesh_instance in _find_mesh_instances(_model_root):
		for surface in mesh_instance.mesh.get_surface_count():
			mesh_instance.set_surface_override_material(surface, material)
```

**效果 / Result**

- 中文：月球显示颜色、凹凸细节和粗糙度，而不是默认白色模型。
- English: The Moon displays color, normal detail, and roughness instead of appearing as an untextured white model.

### 第五步：根据 AABB 统一模型尺寸 / Step 5: Normalize size from the AABB

```gdscript
func _normalize_model_size() -> void:
	var meshes := _find_mesh_instances(_model_root)
	if meshes.is_empty():
		push_error("MoonPresenter|FATAL: Moon scene contains no MeshInstance3D")
		return

	var inverse_root := _model_root.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for mesh_instance in meshes:
		var relative_transform := inverse_root * mesh_instance.global_transform
		var mesh_bounds := relative_transform * mesh_instance.get_aabb()
		bounds = bounds.merge(mesh_bounds) if has_bounds else mesh_bounds
		has_bounds = true

	var source_diameter := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if source_diameter <= 0.0001:
		return
	var uniform_scale := target_diameter_meters / source_diameter
	_model_root.scale = Vector3.ONE * uniform_scale
	_model_root.position = -bounds.get_center() * uniform_scale
```

**效果 / Result**

- 中文：不管 FBX 原始单位是厘米还是米，行星最终都会严格缩放为指定直径，并以节点原点为球心。
- English: Regardless of the FBX source units, the planet is scaled to the requested diameter and centered on the node origin.

### 第六步：添加可选旋转 / Step 6: Add optional rotation

```gdscript
func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _model_root != null:
		_model_root.rotate_y(deg_to_rad(rotation_speed_degrees) * delta)
```

最终 10 个行星都设 `rotation_speed_degrees = 0`，因为本数据集要求天体静止。

Set `rotation_speed_degrees = 0` on all ten final planets because this dataset requires stationary celestial bodies.

**效果 / Result**

- 中文：脚本支持旋转测试，但最终游戏中行星不会自己移动或旋转。
- English: The script supports rotation tests, while the final game keeps all planets stationary.

### 本脚本检查点 / Checkpoint

- `Planet01` 位置写为 `Vector3(15, 8.4, 20)`，直径写为 `12`。
- 运行后能看到纹理正确、直径约 12 米的球体。
- 参考答案：[`02_rebuilt_project/moon_presenter.gd`](02_rebuilt_project/moon_presenter.gd)。

---

## 5. `mit_destination.gd`：程序化 MIT 终点 / Procedural MIT destination

在 `Main` 下创建 `Destination (Node3D)`：

```text
position = Vector3(100, 0, 100)
rotation_degrees = Vector3(0, 45, 0)
```

把 `mit_destination.gd` 挂到它。这里不用外部建筑模型，而是用 `BoxMesh`、`CylinderMesh` 和 `SphereMesh` 亲手搭建。

Attach `mit_destination.gd` to it. The building is constructed from Godot primitives instead of an imported building model.

### 第一步：创建脚本和辅助变量 / Step 1: Create the script and helper variables

```gdscript
@tool
extends Node3D
class_name MITDestination

var _model_root: Node3D
var _limestone: StandardMaterial3D
var _shadow: StandardMaterial3D
var _glass: StandardMaterial3D
var _mit_red: StandardMaterial3D
var _dome_copper: StandardMaterial3D
var _beacon: StandardMaterial3D

func _ready() -> void:
	_build_model()
```

**效果 / Result**

- 中文：脚本可以在编辑器中立即生成建筑预览，不必等到游戏运行。
- English: The script can generate an editor preview immediately instead of waiting for the game to run.

### 第二步：先写通用网格函数 / Step 2: Write reusable mesh helpers first

```gdscript
func _add_mesh(name_value: String, mesh: Mesh, position_value: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	_model_root.add_child(instance)
	return instance

func _add_box(name_value: String, size_value: Vector3, position_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	mesh.material = material
	return _add_mesh(name_value, mesh, position_value)

func _add_cylinder(name_value: String, radius: float, height: float, position_value: Vector3, material: Material, segments: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 0
	mesh.material = material
	return _add_mesh(name_value, mesh, position_value)
```

**效果 / Result**

- 中文：后续可以用一行代码添加建筑块，避免为几十个 MeshInstance3D 重复写节点创建代码。
- English: Later building pieces can be added in one line without repeating node-construction code for dozens of MeshInstance3D nodes.

### 第三步：创建六种材质 / Step 3: Create six materials

```gdscript
func _create_materials() -> void:
	_limestone = StandardMaterial3D.new()
	_limestone.albedo_color = Color(0.78, 0.75, 0.68)
	_limestone.roughness = 0.78

	_shadow = StandardMaterial3D.new()
	_shadow.albedo_color = Color(0.16, 0.18, 0.2)

	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.025, 0.075, 0.11)
	_glass.metallic = 0.25
	_glass.emission_enabled = true
	_glass.emission = Color(0.01, 0.08, 0.14)

	_mit_red = StandardMaterial3D.new()
	_mit_red.albedo_color = Color(0.55, 0.035, 0.08)
	_mit_red.emission_enabled = true
	_mit_red.emission = Color(0.45, 0.01, 0.035)

	_dome_copper = StandardMaterial3D.new()
	_dome_copper.albedo_color = Color(0.08, 0.42, 0.38)
	_dome_copper.metallic = 0.48

	_beacon = StandardMaterial3D.new()
	_beacon.albedo_color = Color(1.0, 0.12, 0.18)
	_beacon.emission_enabled = true
	_beacon.emission = Color(1.0, 0.02, 0.06)
	_beacon.emission_energy_multiplier = 6.0
```

**效果 / Result**

- 中文：建筑拥有石灰岩主体、深色阴影、蓝色玻璃、MIT 红色饰带、绿色铜穹顶和红色信标。
- English: The building gains a limestone body, dark recesses, blue glass, an MIT-red band, a green copper dome, and a red beacon.

### 第四步：搭建基础和正厅 / Step 4: Build the foundation and main hall

在 `_build_model()` 开头先清理旧预览，然后创建根节点：

```gdscript
func _build_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_create_materials()
	_model_root = Node3D.new()
	_model_root.name = "GeneratedMITModel"
	add_child(_model_root)

	_add_box("LowerPlinth", Vector3(8.2, 0.45, 5.8), Vector3(0, 0.225, 0), _limestone)
	_add_box("UpperPlinth", Vector3(7.6, 0.35, 5.3), Vector3(0, 0.625, 0), _limestone)
	_add_box("MainHall", Vector3(7.0, 4.9, 4.6), Vector3(0, 3.25, 0.15), _shadow)
	_add_box("LeftWing", Vector3(0.75, 4.7, 4.9), Vector3(-3.15, 3.35, 0), _limestone)
	_add_box("RightWing", Vector3(0.75, 4.7, 4.9), Vector3(3.15, 3.35, 0), _limestone)
```

**效果 / Result**

- 中文：场景中出现一个有台基、正厅和左右侧翼的建筑轮廓。
- English: A building silhouette with a plinth, central hall, and side wings appears.

### 第五步：生成十根柱子和屋顶 / Step 5: Generate ten columns and the roof

```gdscript
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.17
	column_mesh.bottom_radius = 0.22
	column_mesh.height = 3.8
	column_mesh.radial_segments = 12
	column_mesh.material = _limestone
	for index in 10:
		var x := lerpf(-2.7, 2.7, float(index) / 9.0)
		_add_mesh("FrontColumn%02d" % index, column_mesh, Vector3(x, 3.15, -2.5))
		_add_box("ColumnBase%02d" % index, Vector3(0.42, 0.16, 0.42), Vector3(x, 1.22, -2.5), _limestone)
		_add_box("ColumnCapital%02d" % index, Vector3(0.46, 0.18, 0.46), Vector3(x, 5.08, -2.5), _limestone)

	_add_box("MITBand", Vector3(5.7, 0.32, 0.12), Vector3(0, 5.82, -2.81), _mit_red)
	_add_box("RoofSlab", Vector3(8.0, 0.38, 5.7), Vector3(0, 6.55, 0), _limestone)
```

**效果 / Result**

- 中文：建筑正面出现古典柱廊、屋顶和不含文字的红色终点标识。
- English: A classical colonnade, roof, and text-free red destination marker appear on the facade.

### 第六步：制作穹顶和终点灯 / Step 6: Build the dome and goal beacon

```gdscript
	_add_cylinder("DrumBase", 2.45, 0.55, Vector3(0, 7.18, 0), _limestone, 32)
	_add_cylinder("DrumShadow", 2.18, 0.48, Vector3(0, 7.65, 0), _glass, 32)

	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 2.15
	dome_mesh.height = 4.3
	dome_mesh.radial_segments = 32
	dome_mesh.rings = 12
	dome_mesh.material = _dome_copper
	var dome := _add_mesh("GreatDome", dome_mesh, Vector3(0, 8.55, 0))
	dome.scale = Vector3(1.0, 0.62, 1.0)

	var goal_light := OmniLight3D.new()
	goal_light.position = Vector3(0, 10.6, 0)
	goal_light.light_color = Color(0.9, 0.12, 0.18)
	goal_light.light_energy = 3.0
	goal_light.omni_range = 8.0
	_model_root.add_child(goal_light)
```

**效果 / Result**

- 中文：远处可以清楚辨认绿色 Great Dome 和红色终点灯，MIT 建筑成为 `(100,100)` 的视觉目标。
- English: The green Great Dome and red goal light are visible from a distance, making the MIT building the visual target at `(100,100)`.

### 本脚本检查点 / Checkpoint

- 建筑只负责视觉；到达判定由 `spaceship_flight.gd` 完成。
- 完整版还包含更多屋顶层、灯笼和信标几何，可在核心结构成功后补齐。
- 参考答案：[`02_rebuilt_project/mit_destination.gd`](02_rebuilt_project/mit_destination.gd)。

---

## 6. `black_hole.gd`：黑洞视觉、引力和吞噬 / Black-hole visuals, gravity, and capture

在 `Main` 下创建 `BlackHoleExhibit (Node3D)`，在里面创建 `BlackHole03 (Node3D)`，挂载脚本。

Create `BlackHoleExhibit (Node3D)` under `Main`, add `BlackHole03 (Node3D)`, and attach the script.

### 第一步：定义模型、物理和视觉参数 / Step 1: Define model, physics, and visual parameters

```gdscript
@tool
extends Node3D
class_name GameplayBlackHole

const DISK_SHADER := preload("res://black_hole_disk.gdshader")

@export_group("Imported model")
@export var model_scene: PackedScene
@export var visual_diameter_meters := 11.0
@export var hide_embedded_planet := true

@export_group("Physics")
@export var gravitational_parameter_mu := 916.6667
@export var gravity_softening_length := 5.5
@export var capture_radius := 5.5
@export var maximum_acceleration := 25.0

@export_group("Visuals")
@export var accretion_disk_radius := 5.5
@export var disk_tilt_degrees := 18.0
@export var disk_roll_degrees := -28.0
@export var disk_rotation_degrees_per_second := 5.0

var _generated_root: Node3D
var _disk_root: Node3D
var _imported_model_root: Node3D
```

**效果 / Result**

- 中文：每一个黑洞可以单独配置尺寸、引力强度、软化长度、吞噬半径和吸积盘外观。
- English: Each black hole can independently configure size, gravity strength, softening length, capture radius, and disk appearance.

### 第二步：先实现纯物理 API / Step 2: Implement the physics API first

```gdscript
func get_gravity_acceleration_at(world_position: Vector3) -> Vector3:
	var to_center := global_position - world_position
	var distance := to_center.length()
	if distance <= 0.0001:
		return Vector3.ZERO
	var denominator := distance * distance + gravity_softening_length * gravity_softening_length
	var magnitude := gravitational_parameter_mu / denominator
	magnitude = minf(magnitude, maximum_acceleration)
	return to_center / distance * magnitude

func captures(world_position: Vector3, body_radius: float = 0.0) -> bool:
	return world_position.distance_to(global_position) <= capture_radius + body_radius
```

使用的是软化平方反比：

```text
a = μ / (distance² + softening²)
```

**效果 / Result**

- 中文：飞船脚本可以向黑洞询问当前位置的三维引力，也可以询问飞船是否进入事件视界。
- English: The flight script can query the black hole's 3D gravity at any position and test whether the spacecraft entered its event horizon.

### 第三步：创建可旋转的视觉根节点 / Step 3: Create a rotating visual root

```gdscript
func _ready() -> void:
	_build_visuals()
	set_process(true)

func _build_visuals() -> void:
	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedBlackHole"
	add_child(_generated_root)

	_disk_root = Node3D.new()
	_disk_root.name = "RotatingVisualRoot"
	_disk_root.rotation_degrees = Vector3(disk_tilt_degrees, 0.0, disk_roll_degrees)
	_generated_root.add_child(_disk_root)

	if model_scene != null:
		_build_imported_visual()
	else:
		_build_procedural_visual()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _disk_root != null:
		_disk_root.rotate_y(deg_to_rad(disk_rotation_degrees_per_second) * delta)
```

**效果 / Result**

- 中文：吸积盘拥有固定倾角，并且只旋转视觉部分；黑洞的世界中心不会移动。
- English: The accretion disk has a fixed tilt and only the visual root rotates; the black hole's world-space center remains stationary.

### 第四步：加载并归一化外部黑洞模型 / Step 4: Load and normalize the imported model

实现方式和 Moon 相同：实例化场景、递归找网格、合并 AABB、计算统一缩放。额外隐藏模型内部名为 `Planet` 的装饰节点。

The process matches the Moon: instantiate the scene, find meshes recursively, merge AABBs, and compute a uniform scale. Additionally, hide the embedded decorative node named `Planet`.

```gdscript
func _build_imported_visual() -> void:
	_imported_model_root = model_scene.instantiate() as Node3D
	if _imported_model_root == null:
		_build_procedural_visual()
		return
	_disk_root.add_child(_imported_model_root)

	var meshes: Array[MeshInstance3D] = []
	var pending: Array[Node] = [_imported_model_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if String(node.name).to_lower() == "planet" and node is Node3D and hide_embedded_planet:
			(node as Node3D).visible = false
		elif node is MeshInstance3D and node.mesh != null:
			meshes.append(node as MeshInstance3D)
		for child in node.get_children():
			pending.append(child)

	# 下一步与 moon_presenter.gd 相同：合并 bounds，按 visual_diameter_meters 缩放并居中。
	# Next: merge bounds, scale to visual_diameter_meters, and center the model.
```

**效果 / Result**

- 中文：Sketchfab 黑洞模型以正确直径显示，原模型中比例不合适的小行星被隐藏。
- English: The Sketchfab black-hole model displays at the correct diameter while its incorrectly scaled embedded planet is hidden.

### 第五步：增加无模型时的程序化后备外观 / Step 5: Add a procedural fallback visual

在 `_build_procedural_visual()` 中创建：

1. 半径为 `capture_radius` 的黑色 `SphereMesh`，代表事件视界。
2. 稍大的半透明 `SphereMesh`，代表光子晕。
3. 使用 `black_hole_disk.gdshader` 的 `PlaneMesh`，代表吸积盘。
4. 两个 `TorusMesh`，代表发光环。

Create an event-horizon sphere, a transparent photon corona, a shader-driven disk plane, and two glowing torus rings.

核心辅助函数：

```gdscript
func _add_mesh(name_value: String, mesh: Mesh, position_value: Vector3, parent: Node3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
```

**效果 / Result**

- 中文：即使外部 FBX 没有成功导入，仍能看到并测试一个具有事件视界和吸积盘的黑洞。
- English: Even if the external FBX fails to import, a testable black hole with an event horizon and accretion disk remains visible.

### 第六步：填写第一个黑洞的 Inspector 参数 / Step 6: Configure the first black hole

`BlackHole03`：

```text
position                      = Vector3(53, 9.3, 23)
visual_diameter_meters        = 11
capture_radius                = 5.5
gravity_softening_length      = 5.5
gravitational_parameter_mu    = 916.6667
accretion_disk_radius         = 5.5
```

这里采用：`μ = (500 / 3) × capture_radius`。

**效果 / Result**

- 中文：编号 03 的红色黑洞出现在逻辑坐标 `(53,23,9.3)`，能够提供引力并吞噬飞船。
- English: Red black hole 03 appears at logical coordinate `(53,23,9.3)`, exerts gravity, and can capture the spacecraft.

### 本脚本检查点 / Checkpoint

- 运行时吸积盘旋转，但 `BlackHole03.global_position` 不变。
- `get_gravity_acceleration_at()` 越靠近黑洞返回值越大，但不超过 `maximum_acceleration`。
- 参考答案：[`02_rebuilt_project/black_hole.gd`](02_rebuilt_project/black_hole.gd)。

---

## 7. `spaceship_flight.gd`：飞船输入、物理、引力和碰撞 / Spacecraft input, physics, gravity, and collision

这是项目最核心的脚本。把它挂到 `XROrigin3D`，因为移动整个 XR Origin 可以移动玩家，同时保留头显在房间范围内的局部追踪。

This is the central gameplay script. Attach it to `XROrigin3D`; moving the XR Origin moves the player while preserving local room-scale headset tracking.

### 第一步：先统一两套坐标 / Step 1: Define the two coordinate systems

游戏数据使用：

```text
logical = (X, Y, altitude Z)
```

Godot 使用 Y 轴作为高度，所以转换为：

```text
world = Vector3(logical X, logical altitude Z, logical Y)
```

先写转换函数：

```gdscript
extends XROrigin3D
class_name SpacecraftFlightController

func _logical_to_world(logical_position: Vector3) -> Vector3:
	return Vector3(logical_position.x, logical_position.z, logical_position.y)
```

**效果 / Result**

- 中文：逻辑起点 `(0,0,10)` 会正确变成 Godot 世界位置 `(0,10,0)`，不会把高度和地图 Y 坐标弄反。
- English: Logical start `(0,0,10)` correctly becomes Godot world position `(0,10,0)`, preventing altitude and map-Y from being swapped.

### 第二步：定义飞行状态 / Step 2: Define flight states

```gdscript
enum FlightState {
	FLYING,
	CRASHED,
	ARRIVED,
}

var state := FlightState.FLYING
var velocity := Vector2.ZERO
var gravity_acceleration := Vector2.ZERO
var crash_message := "COLLISION"
```

飞船只在水平 X/Z 平面运动，因此速度和累计引力用 `Vector2`。

The ship moves only on the horizontal X/Z plane, so velocity and accumulated gravity use `Vector2`.

**效果 / Result**

- 中文：游戏可以明确区分“飞行中”“撞毁”和“到达”，撞毁后物理不会继续推进。
- English: The game can distinguish flying, crashed, and arrived states, and physics can stop after a crash.

### 第三步：暴露场景引用和游戏参数 / Step 3: Expose node references and gameplay parameters

```gdscript
@export_node_path("XRController3D") var left_controller_path: NodePath
@export_node_path("XRController3D") var right_controller_path: NodePath
@export_node_path("XRCamera3D") var flight_camera_path: NodePath
@export_node_path("Node3D") var obstacles_root_path: NodePath
@export_node_path("Node3D") var black_holes_root_path: NodePath
@export_node_path("Label3D") var vr_status_path: NodePath
@export_node_path("Label") var desktop_status_path: NodePath

@export var start_position := Vector3(0.0, 0.0, 10.0)
@export var destination := Vector3(100.0, 100.0, 10.0)
@export var play_area_min := Vector2(-20.0, -20.0)
@export var play_area_max := Vector2(120.0, 120.0)

@export var gravity_constant_c := 1.2
@export var spacecraft_acceleration_a := 12.0
@export var flight_speed := 18.0
@export var linear_drag := 0.18
@export var spacecraft_radius := 0.25
@export var arrival_radius := 3.0
@export var joystick_deadzone := 0.15
@export var maximum_gravity_acceleration := 30.0
```

在 Inspector 中连接：

```text
left_controller_path   = XRControllerLeft
right_controller_path  = XRControllerRight
flight_camera_path     = XRCamera3D
obstacles_root_path    = ../MoonExhibit
black_holes_root_path  = ../BlackHoleExhibit
vr_status_path         = XRCamera3D/FlightHUD
desktop_status_path    = ../DesktopHUD/Panel/Content/Mode
```

**效果 / Result**

- 中文：飞船脚本知道去哪里读取控制器、摄像机、行星、黑洞和两个 HUD。
- English: The flight script knows where to find the controllers, camera, planets, black holes, and both HUD labels.

### 第四步：缓存节点并实现重置 / Step 4: Cache nodes and implement reset

```gdscript
var _left_controller: XRController3D
var _right_controller: XRController3D
var _flight_camera: XRCamera3D
var _obstacles_root: Node3D
var _black_holes_root: Node3D
var _vr_status: Label3D
var _desktop_status: Label

func _ready() -> void:
	_left_controller = get_node_or_null(left_controller_path) as XRController3D
	_right_controller = get_node_or_null(right_controller_path) as XRController3D
	_flight_camera = get_node_or_null(flight_camera_path) as XRCamera3D
	_obstacles_root = get_node_or_null(obstacles_root_path) as Node3D
	_black_holes_root = get_node_or_null(black_holes_root_path) as Node3D
	_vr_status = get_node_or_null(vr_status_path) as Label3D
	_desktop_status = get_node_or_null(desktop_status_path) as Label
	reset_flight()

func reset_flight() -> void:
	state = FlightState.FLYING
	velocity = Vector2.ZERO
	gravity_acceleration = Vector2.ZERO
	crash_message = "COLLISION"
	global_position = _logical_to_world(start_position)
```

**效果 / Result**

- 中文：每次启动或重新开始时，XR Origin 回到世界 `(0,10,0)`，速度和引力清零。
- English: On startup or restart, the XR Origin returns to world `(0,10,0)` with velocity and gravity reset.

### 第五步：先加入 WASD 输入 / Step 5: Add WASD input first

先不连接头显摇杆，用键盘验证移动：

```gdscript
func _get_flight_input() -> Vector2:
	var keyboard := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		keyboard.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		keyboard.x += 1.0
	if Input.is_key_pressed(KEY_S):
		keyboard.y -= 1.0
	if Input.is_key_pressed(KEY_W):
		keyboard.y += 1.0
	return keyboard.normalized() if not keyboard.is_zero_approx() else Vector2.ZERO
```

**效果 / Result**

- 中文：无需 Quest，就可以先用 WASD 验证二维飞行方向和速度。
- English: WASD can validate 2D flight direction and speed before a Quest headset is involved.

### 第六步：建立最小飞行物理循环 / Step 6: Build the minimal flight physics loop

```gdscript
func _physics_process(delta: float) -> void:
	if state != FlightState.FLYING:
		return
	var flight_input := _get_flight_input()
	velocity += flight_input * spacecraft_acceleration_a * delta
	velocity *= exp(-linear_drag * delta)
	if velocity.length() > flight_speed:
		velocity = velocity.normalized() * flight_speed
	_move_spacecraft(delta)

func _move_spacecraft(delta: float) -> void:
	var next_position := global_position + Vector3(velocity.x, 0.0, velocity.y) * delta
	if next_position.x < play_area_min.x or next_position.x > play_area_max.x:
		velocity.x = 0.0
	if next_position.z < play_area_min.y or next_position.z > play_area_max.y:
		velocity.y = 0.0
	global_position = Vector3(
		clampf(next_position.x, play_area_min.x, play_area_max.x),
		start_position.z,
		clampf(next_position.z, play_area_min.y, play_area_max.y)
	)
```

物理公式：

```text
velocity += input × acceleration × delta
velocity *= exp(-drag × delta)
position += velocity × delta
```

**效果 / Result**

- 中文：飞船有加速和惯性，松开按键后因阻力逐渐减速；高度固定为 10，且不会飞出 `-20..120`。
- English: The ship accelerates with inertia, slows gradually from drag, stays at altitude 10, and cannot leave `-20..120`.

### 第七步：加入 Quest 摇杆并转换为头部相对方向 / Step 7: Add Quest sticks and head-relative steering

先读取左右摇杆：

```gdscript
var stick := Vector2.ZERO
if _left_controller != null:
	stick = _left_controller.get_vector2(&"primary")
if stick.length() < joystick_deadzone and _right_controller != null:
	stick = _right_controller.get_vector2(&"primary")
```

然后把摇杆方向转换成头显当前视野方向：

```gdscript
func _head_relative_stick(stick: Vector2) -> Vector2:
	if _flight_camera == null:
		return stick
	var forward := -_flight_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return stick
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var world_direction := right * stick.x + forward * stick.y
	return Vector2(world_direction.x, world_direction.z)
```

把 `_get_flight_input()` 中的返回值改为：有有效摇杆时使用 `_head_relative_stick(stick)`，有键盘时用键盘覆盖。

Update `_get_flight_input()` so a valid stick uses `_head_relative_stick(stick)`, while keyboard input overrides it for desktop testing.

**效果 / Result**

- 中文：玩家转头后，摇杆“向前”仍然表示视野前方，摇杆“向左”仍然表示屏幕左方。
- English: After the player turns their head, stick-forward still means forward in view and stick-left still means screen-left.

### 第八步：实现行星引力 / Step 8: Implement planet gravity

对 `MoonExhibit` 下的每个 Planet 读取直径，计算半径和三维距离：

```gdscript
func _calculate_gravity_acceleration() -> Vector2:
	var total := Vector2.ZERO
	var spacecraft_world_position := get_spacecraft_world_position()

	if _obstacles_root != null and not is_zero_approx(gravity_constant_c):
		for child in _obstacles_root.get_children():
			var planet := child as Node3D
			if planet == null:
				continue
			var diameter: Variant = planet.get("target_diameter_meters")
			if diameter == null:
				continue
			var radius := float(diameter) * 0.5
			var to_center := planet.global_position - spacecraft_world_position
			var distance_to_center := maxf(to_center.length(), 0.01)
			var magnitude := gravity_constant_c * radius ** 3.0 / distance_to_center ** 2.0
			var direction := to_center / distance_to_center
			total += Vector2(direction.x, direction.z) * magnitude

	return total
```

公式：

```text
a_planet = C × radius³ / distance²
C = 1.2
```

距离必须是三维距离；最后只把 X/Z 水平分量施加给固定高度的飞船。

Distance must be measured in 3D; only the horizontal X/Z components are applied to the altitude-locked ship.

**效果 / Result**

- 中文：飞船经过大行星附近时会明显偏航，小行星或远处行星影响较弱。
- English: The spacecraft bends noticeably near large planets, while small or distant planets exert less influence.

### 第九步：叠加黑洞引力并限制总量 / Step 9: Add black-hole gravity and cap the total

继续在 `_calculate_gravity_acceleration()` 的 `return` 前增加：

```gdscript
	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("get_gravity_acceleration_at"):
				continue
			var acceleration: Variant = black_hole.call(
				"get_gravity_acceleration_at",
				spacecraft_world_position
			)
			if acceleration is Vector3:
				total += Vector2(acceleration.x, acceleration.z)

	if total.length() > maximum_gravity_acceleration:
		total = total.normalized() * maximum_gravity_acceleration
	return total
```

再把物理更新改成：

```gdscript
gravity_acceleration = _calculate_gravity_acceleration()
velocity += (flight_input * spacecraft_acceleration_a + gravity_acceleration) * delta
```

**效果 / Result**

- 中文：所有行星和所有黑洞的引力会相加，但异常近距离时总加速度不会超过 30。
- English: Gravity from every planet and black hole is summed, while the total acceleration remains capped at 30 near pathological positions.

### 第十步：使用头显真实水平位置 / Step 10: Use the headset's real horizontal position

```gdscript
func get_spacecraft_world_position() -> Vector3:
	if _flight_camera != null:
		return Vector3(
			_flight_camera.global_position.x,
			start_position.z,
			_flight_camera.global_position.z
		)
	return Vector3(global_position.x, start_position.z, global_position.z)

func get_flight_coordinates() -> Vector3:
	var p := get_spacecraft_world_position()
	return Vector3(p.x, p.z, start_position.z)
```

**效果 / Result**

- 中文：玩家在房间里实际走动时，小地图、引力和碰撞使用头部真实水平位置，而不仅仅是 XROrigin 的中心。
- English: When the player physically walks in the room, the minimap, gravity, and collision use the viewer's true horizontal position rather than only the XROrigin center.

### 第十一步：实现行星碰撞 / Step 11: Implement planet collision

```gdscript
func _check_obstacle_collisions() -> void:
	var ship_position := get_spacecraft_world_position()
	if _obstacles_root != null:
		for child in _obstacles_root.get_children():
			var obstacle := child as Node3D
			if obstacle == null:
				continue
			var diameter: Variant = obstacle.get("target_diameter_meters")
			if diameter == null:
				continue
			var obstacle_radius := float(diameter) * 0.5
			var collision_distance := spacecraft_radius + obstacle_radius
			if ship_position.distance_to(obstacle.global_position) <= collision_distance:
				state = FlightState.CRASHED
				crash_message = "COLLISION · %s" % obstacle.name
				velocity = Vector2.ZERO
				return
```

**效果 / Result**

- 中文：只有飞船到球心的三维距离小于“行星半径 + 0.25”时才撞毁；高度不同的球不会被错误地按二维圆碰撞。
- English: A crash occurs only when the 3D center distance is less than planet radius plus 0.25; spheres at different altitudes are not incorrectly treated as 2D circles.

### 第十二步：实现黑洞吞噬 / Step 12: Implement black-hole capture

在同一函数末尾增加：

```gdscript
	if _black_holes_root != null:
		for child in _black_holes_root.get_children():
			var black_hole := child as Node3D
			if black_hole == null or not black_hole.has_method("captures"):
				continue
			if bool(black_hole.call("captures", ship_position, spacecraft_radius)):
				state = FlightState.CRASHED
				crash_message = "CAPTURED · %s" % black_hole.name
				velocity = Vector2.ZERO
				return
```

**效果 / Result**

- 中文：飞船进入事件视界加自身半径的范围时停止飞行，并显示被对应黑洞捕获。
- English: The ship stops and reports capture when it enters the event-horizon radius plus its own radius.

### 第十三步：实现终点到达 / Step 13: Implement destination arrival

在 `_physics_process()` 完成移动和碰撞后增加：

```gdscript
_check_obstacle_collisions()
if state == FlightState.FLYING:
	var goal_world := _logical_to_world(destination)
	if get_spacecraft_world_position().distance_to(goal_world) <= arrival_radius:
		state = FlightState.ARRIVED
		velocity = Vector2.ZERO
```

**效果 / Result**

- 中文：飞船进入 MIT 终点半径 3 米时显示到达并停止，而不是必须碰到建筑网格。
- English: The ship arrives and stops within 3 meters of the MIT destination without needing to collide with the building mesh.

### 第十四步：加入重启和手柄震动 / Step 14: Add restart and haptics

使用 `R`、A/X 或扳机重新开始；撞毁和到达时调用：

```gdscript
func _pulse_controllers(amplitude: float, duration: float) -> void:
	for controller in [_left_controller, _right_controller]:
		if controller != null:
			controller.trigger_haptic_pulse(&"haptic", 0.0, amplitude, duration, 0.0)
```

注意使用“按下边沿”，不要在按钮持续按住时每个物理帧重复重置。完整版使用 `_restart_was_pressed` 保存上一帧状态。

Use a pressed edge rather than restarting every physics frame while the button is held. The complete version stores the previous state in `_restart_was_pressed`.

**效果 / Result**

- 中文：撞毁时手柄震动，用户按一次按钮即可安全回到起点，不会因持续按键无限重置。
- English: Controllers vibrate on a crash, and one button press returns safely to the start without repeated reset loops.

### 第十五步：更新 HUD 并公开朝向 / Step 15: Update the HUD and expose heading

HUD 至少显示位置、速度、引力、终点距离和当前状态。小地图还需要头部朝向：

```gdscript
func get_view_heading() -> Vector2:
	if _flight_camera == null:
		return Vector2.ZERO
	var forward := -_flight_camera.global_basis.z
	var heading := Vector2(forward.x, forward.z)
	return heading.normalized() if heading.length_squared() > 0.0001 else Vector2.ZERO
```

在 `_update_status()` 中把同一个 `message` 写给 `_vr_status.text` 和 `_desktop_status.text`。

Write the same status `message` to `_vr_status.text` and `_desktop_status.text` in `_update_status()`.

**效果 / Result**

- 中文：桌面和头显都能看到实时坐标、速度、引力和游戏结果，小地图也能画出当前视线方向。
- English: Both desktop and headset views show live coordinates, speed, gravity, and game outcome, while the minimap can draw the current view direction.

### 本脚本检查点 / Checkpoint

按以下顺序测试，不要跳过：

1. 暂时把 `gravity_constant_c=0`，确认 WASD 直线飞行、阻力和边界。
2. 恢复 `gravity_constant_c=1.2`，确认经过 Planet01 时轨迹弯曲。
3. 确认撞 Planet01 后状态停止在 `CRASHED`。
4. 确认接近 BlackHole03 后被吸引并捕获。
5. 暂时移除障碍，确认进入 `(100,100,10)` 半径 3 后到达。
6. 确认 `R` 和 Quest 按钮可以重新开始。

Test in this order: straight flight with gravity disabled, planet deflection, planet collision, black-hole capture, destination arrival, and restart controls.

参考答案：[`02_rebuilt_project/spaceship_flight.gd`](02_rebuilt_project/spaceship_flight.gd)。

---

## 8. `flight_minimap.gd`：桌面二维小地图 / Desktop 2D minimap

在 `DesktopHUD` 下创建右上角 `MiniMapPanel (PanelContainer)`，再添加 `Map (Control)`，把脚本挂到 `Map`。

Create `MiniMapPanel (PanelContainer)` in the upper-right of `DesktopHUD`, add `Map (Control)`, and attach the script to `Map`.

### 第一步：建立绘制循环 / Step 1: Establish the drawing loop

```gdscript
extends Control
class_name FlightMiniMap

@export var map_min := Vector2(-20.0, -20.0)
@export var map_max := Vector2(120.0, 120.0)

var _flight: Node3D
var _obstacles: Node3D
var _black_holes: Node3D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_scene_nodes()
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()
```

**效果 / Result**

- 中文：Map 节点每帧请求重绘，并且不会拦截桌面鼠标输入。
- English: The Map control requests a redraw every frame and does not block desktop mouse input.

### 第二步：发现所需场景节点 / Step 2: Find the required scene nodes

```gdscript
func _find_scene_nodes() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_flight = scene.get_node_or_null("XROrigin3D") as Node3D
	_obstacles = scene.get_node_or_null("MoonExhibit") as Node3D
	_black_holes = scene.get_node_or_null("BlackHoleExhibit") as Node3D
```

**效果 / Result**

- 中文：小地图能取得飞船、全部行星和全部黑洞，不需要为每个天体单独设置 NodePath。
- English: The minimap can access the ship, every planet, and every black hole without assigning a NodePath for each body.

### 第三步：实现世界坐标到屏幕坐标的转换 / Step 3: Convert world coordinates to map pixels

```gdscript
func _world_to_map(world_position: Vector2, map_size: Vector2) -> Vector2:
	var normalized := (world_position - map_min) / (map_max - map_min)
	return Vector2(
		normalized.x * map_size.x,
		(1.0 - normalized.y) * map_size.y
	)
```

Y 需要写成 `1.0 - normalized.y`，因为 Godot 的 Control 屏幕坐标向下为正，而地图逻辑 Y 向上为正。

Y uses `1.0 - normalized.y` because Control coordinates increase downward while logical map Y increases upward.

**效果 / Result**

- 中文：逻辑 `(-20,-20)` 显示在左下角，`(120,120)` 显示在右上角。
- English: Logical `(-20,-20)` appears at the lower-left and `(120,120)` at the upper-right.

### 第四步：绘制背景和网格 / Step 4: Draw the background and grid

```gdscript
func _draw() -> void:
	var map_size := size
	if map_size.x < 2.0 or map_size.y < 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.012, 0.024, 0.055, 0.94))
	_draw_grid(map_size)
	_draw_black_holes(map_size)
	_draw_obstacles(map_size)
	_draw_destination(map_size)
	_draw_spacecraft(map_size)

func _draw_grid(map_size: Vector2) -> void:
	var coordinate := -20.0
	while coordinate <= 120.01:
		var v0 := _world_to_map(Vector2(coordinate, map_min.y), map_size)
		var v1 := _world_to_map(Vector2(coordinate, map_max.y), map_size)
		var h0 := _world_to_map(Vector2(map_min.x, coordinate), map_size)
		var h1 := _world_to_map(Vector2(map_max.x, coordinate), map_size)
		var color := Color(0.2, 0.56, 0.92, 0.75) if is_zero_approx(coordinate) else Color(0.18, 0.32, 0.52, 0.42)
		draw_line(v0, v1, color)
		draw_line(h0, h1, color)
		coordinate += 20.0
```

**效果 / Result**

- 中文：右上角出现深蓝色 `-20..120` 网格，零坐标轴比普通网格更亮。
- English: A dark-blue `-20..120` grid appears in the upper-right, with brighter zero axes.

### 第五步：按飞行高度绘制行星截面 / Step 5: Draw planet cross-sections at flight altitude

不能直接把行星三维半径画成二维圆。飞船固定在高度 10，小地图应该画球体在该高度的水平截面：

```text
horizontal_radius = sqrt(sphere_radius² - vertical_distance²)
```

核心代码：

```gdscript
var planet_radius := float(diameter) * 0.5
var flight_altitude := 10.0
var vertical_distance := absf(flight_altitude - obstacle.global_position.y)
var visual_radius_squared := planet_radius ** 2.0 - vertical_distance ** 2.0
var collision_radius := planet_radius + spacecraft_radius
var collision_radius_squared := collision_radius ** 2.0 - vertical_distance ** 2.0

if visual_radius_squared > 0.0:
	var radius_pixels := sqrt(visual_radius_squared) * pixels_per_meter
	draw_circle(center, radius_pixels, Color(0.08, 0.72, 0.31, 0.48))
if collision_radius_squared > 0.0:
	draw_arc(center, sqrt(collision_radius_squared) * pixels_per_meter, 0.0, TAU, 32, Color(0.72, 1.0, 0.28), 1.5)
```

**效果 / Result**

- 中文：绿色实心区域表示当前高度能看到的行星截面，外圈表示考虑飞船半径后的真实碰撞截面。
- English: The green filled region shows the planet's slice at flight altitude, while the outer ring shows the true collision slice including spacecraft radius.

### 第六步：绘制黑洞截面和影响范围 / Step 6: Draw black-hole slices and influence ranges

读取每个黑洞的：

```text
capture_radius
accretion_disk_radius
gravitational_parameter_mu
gravity_softening_length
```

吞噬截面仍使用三维球切面。可以用红色画吸积盘、黑色画吞噬范围，并标记 `B03` 等编号。

The capture slice still uses a 3D sphere cross-section. Draw the disk in red, capture area in black, and label IDs such as `B03`.

```gdscript
var vertical_distance := absf(flight_altitude - black_hole.global_position.y)
var collision_radius := capture_radius + spacecraft_radius
var radius_squared := collision_radius * collision_radius - vertical_distance * vertical_distance
if radius_squared > 0.0:
	var capture_pixels := sqrt(radius_squared) * pixels_per_meter
	draw_circle(center, capture_pixels, Color(0.0, 0.0, 0.015, 1.0))
	draw_arc(center, capture_pixels, 0.0, TAU, 32, Color(1.0, 0.08, 0.22), 2.0)
```

**效果 / Result**

- 中文：地图上的黑洞尺寸会随其中心高度改变，不会把不相交的三维黑洞误画成可碰撞圆。
- English: Black-hole map size changes with center altitude, avoiding false collision circles for non-intersecting 3D spheres.

### 第七步：绘制飞船、方向和引力箭头 / Step 7: Draw the ship, heading, and gravity arrow

飞船用蓝色十字；崩溃时改为红色。调用 `get_view_heading()` 画青色视线方向，读取 `gravity_acceleration` 画黄色引力方向。

Use a blue cross for the ship and red after a crash. Call `get_view_heading()` for a cyan view direction and read `gravity_acceleration` for a yellow gravity arrow.

```gdscript
var coordinates := _flight.call("get_flight_coordinates") as Vector3
var center := _world_to_map(Vector2(coordinates.x, coordinates.y), map_size)
var heading: Vector2 = _flight.call("get_view_heading")
var screen_heading := Vector2(heading.x, -heading.y)
draw_line(center, center + screen_heading * 16.0, Color(0.45, 0.95, 1.0), 3.0)

var gravity: Vector2 = _flight.get("gravity_acceleration")
if gravity.length() > 0.01:
	var screen_gravity := Vector2(gravity.x, -gravity.y).normalized()
	draw_line(center, center + screen_gravity * 20.0, Color(1.0, 0.72, 0.12), 3.0)
```

**效果 / Result**

- 中文：用户可以同时看到飞船在哪里、头朝哪里以及合力把飞船拉向哪里。
- English: The user can see the ship position, viewing direction, and the direction of the combined gravitational pull.

### 第八步：绘制 MIT 终点和读数 / Step 8: Draw the MIT destination and readout

终点位于逻辑 `(100,100)`，用绿色圆和脉冲外环显示：

```gdscript
var center := _world_to_map(Vector2(100.0, 100.0), map_size)
var pulse := radius_pixels + 4.0 + sin(Time.get_ticks_msec() * 0.006) * 2.0
draw_circle(center, radius_pixels, Color(0.12, 1.0, 0.4, 0.24))
draw_arc(center, pulse, 0.0, TAU, 24, Color(0.12, 1.0, 0.4, 0.8), 2.0)
```

**效果 / Result**

- 中文：地图显示绿色脉冲终点和实时 `XY` 坐标，玩家能够规划避障路线。
- English: The map shows a pulsing green goal and live `XY` coordinates so the player can plan an avoidance route.

### 本脚本检查点 / Checkpoint

- 飞船从 `(0,0)` 开始时应位于地图偏左下区域，而不是正中心。
- Planet 和 BlackHole 的标记位置应与 `obstacle_layout.csv` 一致。
- 上下方向颠倒时，首先检查 `_world_to_map()` 的 `1.0 - normalized.y`。
- 参考答案：[`02_rebuilt_project/flight_minimap.gd`](02_rebuilt_project/flight_minimap.gd)。

---

## 9. `vr_minimap_presenter.gd`：把 2D 地图放进头显 / Put the 2D map in the headset

在 `XRCamera3D` 下创建 `VRMiniMap (Node3D)`，位置设为：

```text
Vector3(0.52, 0.26, -1.5)
```

这样地图固定在视野右上角约 1.5 米处。把脚本挂到 `VRMiniMap`。

This places the head-locked map in the upper-right, about 1.5 meters in front of the viewer. Attach the script to `VRMiniMap`.

### 第一步：预加载同一个小地图脚本 / Step 1: Preload the shared minimap script

```gdscript
extends Node3D
class_name VRMiniMapPresenter

const FlightMiniMapScript = preload("res://flight_minimap.gd")

@export_range(128, 1024, 64) var texture_size := 512
@export_range(0.2, 1.0, 0.05) var display_size_meters := 0.48
```

**效果 / Result**

- 中文：桌面和 VR 将复用同一个地图绘制逻辑，不会出现两套数据不一致。
- English: Desktop and VR reuse the same minimap renderer, preventing two inconsistent map implementations.

### 第二步：创建离屏 SubViewport / Step 2: Create an off-screen SubViewport

```gdscript
func _ready() -> void:
	var viewport := SubViewport.new()
	viewport.name = "MapViewport"
	viewport.size = Vector2i(texture_size, texture_size)
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var minimap := FlightMiniMapScript.new() as Control
	minimap.position = Vector2.ZERO
	minimap.size = Vector2(texture_size, texture_size)
	viewport.add_child(minimap)
```

**效果 / Result**

- 中文：2D 小地图被绘制到一张持续更新的 512×512 纹理中。
- English: The 2D minimap is rendered into a continuously updating 512×512 texture.

### 第三步：把 Viewport 纹理贴到 3D Quad / Step 3: Put the viewport texture on a 3D quad

继续写在 `_ready()` 中：

```gdscript
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(display_size_meters, display_size_meters)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_texture = viewport.get_texture()
	quad_mesh.material = material

	var display := MeshInstance3D.new()
	display.name = "MapDisplay"
	display.mesh = quad_mesh
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
```

**效果 / Result**

- 中文：Quest 视野右上角出现和桌面版本完全相同的小地图，并始终显示在其他三维物体前面。
- English: The same minimap appears in the Quest's upper-right view and remains readable in front of other 3D objects.

### 本脚本检查点 / Checkpoint

- 桌面模式下 `main.gd` 应隐藏 `VRMiniMap`。
- XR 模式下地图不应随世界移动，而应随 XRCamera 一起移动。
- 参考答案：[`02_rebuilt_project/vr_minimap_presenter.gd`](02_rebuilt_project/vr_minimap_presenter.gd)。

---

## 10. 初始模板里已有的 `.gd` 文件怎么处理？ / What about the `.gd` files already in the template?

这些脚本已经存在于 `01_initial_template`，人工重建的第一轮不要删除或从零重写：

These scripts already exist in `01_initial_template`; do not delete or rewrite them during the first rebuild pass.

### `xr_hands.gd`

- 中文作用：读取 OpenXR 手部追踪数据，建立手掌和手指关节的可视化。
- English role: Reads OpenXR hand-tracking data and visualizes palm and finger joints.
- 操作：原样保留并挂在 `XROrigin3D/XRHands`。
- Action: Keep it attached to `XROrigin3D/XRHands`.

### `xr_visuals.gd`

- 中文作用：根据当前追踪状态显示左右 Quest 控制器模型。
- English role: Shows the left and right Quest controller models according to tracking state.
- 操作：保留并确认左右 controller/model NodePath 设置正确。
- Action: Keep it and verify the left/right controller and model assignments.

### `xr_passthrough.gd`

- 中文作用：启用 Quest passthrough，并在透视模式下隐藏指定的虚拟地板。
- English role: Enables Quest passthrough and hides selected virtual-floor nodes in passthrough mode.
- 操作：保留；完成纯 VR 飞行逻辑后再测试 passthrough。
- Action: Keep it; test passthrough after the core VR flight logic works.

### `gdscript_tutorial.gd`

- 中文作用：原始模板的 GDScript 教学示例。
- English role: A GDScript tutorial example from the original template.
- 操作：完成版主场景不挂载它，可以保留但不参与飞船游戏。
- Action: The finished main scene does not attach it; it may remain in the project without participating in gameplay.

### 支持文件 / Supporting files

- `floor_grid.gdshader`：绘制 140×140 地板网格。
- `black_hole_disk.gdshader`：绘制程序化黑洞吸积盘。
- `openxr_action_map.tres`：定义控制器摇杆、按钮和姿态动作。

这些不是普通 `.gd` 文件，但对应功能必须存在。第一轮重建可以从初始模板保留地板 shader，并在实现黑洞阶段参考完成版编写黑洞 shader。

These are not ordinary `.gd` files, but their functions are required. Keep the floor shader from the template and implement the black-hole shader while building the black-hole stage.

---

## 11. 在 Godot 编辑器中组装 `main.tscn` / Assemble `main.tscn` in the Godot editor

不要直接在文本编辑器中手写几百行 `.tscn`。使用 Godot 场景树添加节点、拖拽脚本、填写 Inspector；保存时 Godot 会生成正确的 `.tscn` 文本。

Do not manually type hundreds of `.tscn` lines in a text editor. Add nodes, attach scripts, and fill Inspector values through the Godot editor so it writes valid scene text.

### 第一步：建立最终场景骨架 / Step 1: Build the final scene skeleton

```text
Main (Node3D, main.gd)
├── XROrigin3D (spaceship_flight.gd)
│   ├── XRCamera3D
│   │   ├── FlightHUD (Label3D)
│   │   └── VRMiniMap (Node3D, vr_minimap_presenter.gd)
│   ├── XRControllerLeft
│   ├── XRControllerRight
│   ├── XRVisuals
│   ├── XRHands
│   └── ShipMarker (MeshInstance3D)
├── MoonExhibit (Node3D)
│   └── Planet01 ... Planet14 (moon_presenter.gd)
├── BlackHoleExhibit (Node3D)
│   └── BlackHole03 ... BlackHole15 (black_hole.gd)
├── Destination (Node3D, mit_destination.gd)
├── SceneViewTarget (Node3D)
├── DesktopCamera (Camera3D, desktop_orbit_camera.gd)
├── WorldEnvironment
├── Floor (StaticBody3D)
│   ├── Mesh (MeshInstance3D)
│   └── Collision (CollisionShape3D)
├── SunLight (DirectionalLight3D)
├── Passthrough
└── DesktopHUD (CanvasLayer)
    ├── Panel/Content/Mode (Label)
    └── MiniMapPanel/Map (Control, flight_minimap.gd)
```

**效果 / Result**

- 中文：所有脚本依赖的节点路径都有明确目标，运行时不会因为找不到节点而得到 `null`。
- English: Every script dependency has a clear node path, avoiding `null` references at runtime.

### 第二步：扩大地板 / Step 2: Expand the floor

```text
Floor position              = Vector3(50, 0, 50)
PlaneMesh size              = Vector2(140, 140)
BoxShape3D size             = Vector3(140, 0.2, 140)
Collision local position Y  = -0.1
```

**效果 / Result**

- 中文：地板完整覆盖逻辑地图 `X=-20..120`、`Y=-20..120`。
- English: The floor covers the full logical map from `-20` to `120` on both X and Y.

### 第三步：设置世界和灯光 / Step 3: Configure environment and lighting

1. 给 `WorldEnvironment` 创建深色天空和低强度环境光。
2. 添加 `DirectionalLight3D`，启用阴影。
3. 给 Floor 的 PlaneMesh 使用 `floor_grid.gdshader`。

1. Create a dark sky and low-intensity ambient light in `WorldEnvironment`.
2. Add a shadow-casting `DirectionalLight3D`.
3. Assign `floor_grid.gdshader` to the Floor PlaneMesh.

**效果 / Result**

- 中文：场景呈现深空背景，同时行星、MIT 建筑和地板仍有足够亮度可辨认。
- English: The scene reads as deep space while planets, the MIT building, and the floor remain visible.

### 第四步：录入全部 15 个天体 / Step 4: Enter all 15 celestial bodies

重要：表中的逻辑 `(x,y,z)` 写进 Godot 时必须转换为 `Vector3(x,z,y)`。

Important: Convert logical `(x,y,z)` to Godot `Vector3(x,z,y)`.

| ID | 类型 / Type | 逻辑中心 / Logical center | Godot position | 半径 / Radius | 直径或 μ / Diameter or μ |
|---:|---|---|---|---:|---|
| 01 | Planet | `(15,20,8.4)` | `(15,8.4,20)` | 6.0 | diameter 12.0 |
| 02 | Planet | `(34,14,11.2)` | `(34,11.2,14)` | 8.0 | diameter 16.0 |
| 03 | BlackHole | `(53,23,9.3)` | `(53,9.3,23)` | 5.5 | μ 916.6667 |
| 04 | Planet | `(73,16,10.8)` | `(73,10.8,16)` | 7.0 | diameter 14.0 |
| 05 | Planet | `(91,31,8.9)` | `(91,8.9,31)` | 9.0 | diameter 18.0 |
| 06 | BlackHole | `(19,47,11.6)` | `(19,11.6,47)` | 8.0 | μ 1333.3334 |
| 07 | Planet | `(40,43,9.7)` | `(40,9.7,43)` | 6.5 | diameter 13.0 |
| 08 | Planet | `(62,49,10.3)` | `(62,10.3,49)` | 9.0 | diameter 18.0 |
| 09 | BlackHole | `(83,56,8.2)` | `(83,8.2,56)` | 5.0 | μ 833.3333 |
| 10 | Planet | `(28,70,11.0)` | `(28,11.0,70)` | 7.0 | diameter 14.0 |
| 11 | Planet | `(50,78,9.1)` | `(50,9.1,78)` | 8.5 | diameter 17.0 |
| 12 | BlackHole | `(75,81,10.6)` | `(75,10.6,81)` | 6.0 | μ 1000.0 |
| 13 | Planet | `(-6,59,8.7)` | `(-6,8.7,59)` | 7.5 | diameter 15.0 |
| 14 | Planet | `(108,66,11.8)` | `(108,11.8,66)` | 6.5 | diameter 13.0 |
| 15 | BlackHole | `(60,108,9.8)` | `(60,9.8,108)` | 8.0 | μ 1333.3334 |

每个 Planet：

```text
model_scene             = moon.fbx
albedo_texture          = moon_color.png
normal_texture          = moon_normal.png
roughness_texture       = moon_rough.png
target_diameter_meters  = 2 × radius
rotation_speed_degrees  = 0
```

每个 BlackHole：

```text
visual_diameter_meters    = 2 × radius
capture_radius            = radius
gravity_softening_length  = radius
accretion_disk_radius     = radius
gravitational_parameter_mu = (500 / 3) × radius
```

**效果 / Result**

- 中文：10 个绿色行星和 5 个红色黑洞按照 CSV 的三维中心、高度和半径出现。
- English: Ten green planets and five red black holes appear at the 3D centers, altitudes, and radii defined by the CSV.

### 第五步：配置两个 HUD / Step 5: Configure both HUDs

桌面 HUD 使用 `CanvasLayer + Label + Control`；VR HUD 使用 XRCamera 下的 `Label3D + VRMiniMap`。

The desktop HUD uses `CanvasLayer + Label + Control`; the VR HUD uses `Label3D + VRMiniMap` under the XRCamera.

建议值：

```text
FlightHUD position       = Vector3(0, -0.32, -1.5)
FlightHUD pixel_size     = 0.0018
VRMiniMap position       = Vector3(0.52, 0.26, -1.5)
Map minimum size         = Vector2(280, 280)
```

**效果 / Result**

- 中文：桌面和 Quest 中都能看到相同的飞行状态，小地图位置不会遮挡中央视线。
- English: Desktop and Quest both show the same flight state, and the minimap stays outside the central view.

---

## 12. 分阶段运行验证 / Run and verify in stages

### 阶段 A：只有场景和桌面相机 / Stage A: Scene and desktop camera only

检查：

- `F6` 能启动。
- 鼠标拖动和滚轮工作。
- 地板覆盖整个地图。

**效果 / Result**

- 中文：证明场景、桌面 fallback 和基本渲染没有问题。
- English: Confirms that scene loading, desktop fallback, and basic rendering work.

### 阶段 B：一个行星和一个黑洞 / Stage B: One planet and one black hole

只创建 `Planet01` 和 `BlackHole03`，先检查模型、贴图、缩放和位置，再复制出其余节点。

Create only `Planet01` and `BlackHole03` first. Validate model, textures, scaling, and placement before duplicating the remaining nodes.

**效果 / Result**

- 中文：如果资产路径或缩放有错，只需要调试两个节点，不会在 15 个节点中查找问题。
- English: Asset-path or scale problems can be debugged on two nodes instead of being hidden among fifteen.

### 阶段 C：无引力飞行 / Stage C: Flight without gravity

临时设置：

```text
gravity_constant_c = 0
BlackHoleExhibit 暂时隐藏或移除
```

检查 WASD、速度上限、阻力、固定高度和边界。

**效果 / Result**

- 中文：先证明基础飞行正确，避免把控制问题误判为引力问题。
- English: Proves basic flight before gravity can obscure input or movement bugs.

### 阶段 D：引力和碰撞 / Stage D: Gravity and collision

依次恢复行星引力、黑洞引力、行星碰撞和黑洞吞噬；每恢复一项都重新运行。

Re-enable planet gravity, black-hole gravity, planet collision, and black-hole capture one at a time, rerunning after each change.

**效果 / Result**

- 中文：任何异常都能定位到刚加入的一个功能，而不是整套物理系统。
- English: Any failure can be traced to the one feature just added rather than the entire physics system.

### 阶段 E：桌面和 VR 小地图 / Stage E: Desktop and VR minimaps

先验证桌面小地图，再把同一个 Control 渲染到 VR Quad。

Validate the desktop minimap first, then render the same Control to the VR quad.

**效果 / Result**

- 中文：地图数据问题和 VR 显示问题可以分别排查。
- English: Map-data bugs and VR-display bugs can be diagnosed separately.

### 阶段 F：完整路线 / Stage F: Full route

最终测试：

1. 从 `(0,0,10)` 出发。
2. 观察行星和黑洞引力箭头。
3. 故意撞一次行星并测试重启。
4. 故意进入一次黑洞并测试重启。
5. 绕开天体到达 `(100,100,10)`。

**效果 / Result**

- 中文：飞行、引力、碰撞、终点、HUD 和重新开始形成完整游戏循环。
- English: Flight, gravity, collision, destination, HUD, and restart form a complete gameplay loop.

---

## 13. Quest 3 构建阶段 / Quest 3 build stage

桌面验证全部通过后再做这一阶段：

Only begin this stage after all desktop checks pass:

1. 安装与 Godot 4.7.2 完全匹配的 Android Export Templates。
2. 从 `02_rebuilt_project` 复制 `addons/godotopenxrvendors`；插件不需要手写。
3. 参考完成版 `project.godot` 和 `export_presets.cfg` 启用 Android OpenXR、Meta、ARM64 和 Gradle build。
4. 开启 Quest 3 开发者模式和 USB 调试。
5. 导出 APK，安装后检查 OpenXR session 是否进入 `FOCUSED`。

1. Install Android Export Templates matching Godot 4.7.2 exactly.
2. Copy the OpenXR vendor add-on from `02_rebuilt_project`; do not recreate the plugin manually.
3. Configure Android OpenXR, Meta support, ARM64, and Gradle using the finished project as a reference.
4. Enable Quest 3 developer mode and USB debugging.
5. Export/install the APK and verify that the OpenXR session reaches `FOCUSED`.

**效果 / Result**

- 中文：同一个工作工程从桌面验证版变成可在 Quest 3 运行的 APK。
- English: The same working project progresses from a desktop-verified build to a Quest 3 APK.

---

## 14. 最终文件核对 / Final file checklist

工作项目最终至少应该包含：

```text
project.godot
main.tscn
main.gd
desktop_orbit_camera.gd
moon_presenter.gd
black_hole.gd
black_hole_disk.gdshader
mit_destination.gd
spaceship_flight.gd
flight_minimap.gd
vr_minimap_presenter.gd
floor_grid.gdshader
xr_hands.gd
xr_visuals.gd
xr_passthrough.gd
openxr_action_map.tres
source/moon.fbx
source/moon_color.png
source/moon_normal.png
source/moon_rough.png
source/black_hole/...
```

最终原则：

- `.gd` 负责行为；`.tscn` 负责节点结构和参数；模型/纹理负责外观。
- 每完成一个脚本步骤就运行，不要等全部写完。
- 先桌面测试，再头显测试，最后导出 APK。
- 只在一个工作副本中修改；`01` 保持原样，`02` 只作对照，`03` 是独立 MIT 资源，`04` 是构建结果。

Final principles:

- `.gd` controls behavior, `.tscn` stores node structure and parameters, and imported assets provide appearance.
- Run the project after each script step rather than waiting until everything is written.
- Test on desktop first, then in the headset, and export the APK last.
- Edit only the working copy; keep `01` unchanged, use `02` as reference, treat `03` as standalone MIT assets, and treat `04` as build output.

