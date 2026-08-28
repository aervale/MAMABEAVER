# Moon XR / Desktop Viewer

A Godot 4.7.2 project that presents a textured Moon model in both OpenXR
headsets and a normal desktop window.

## Runtime modes

- **Headset:** when OpenXR initializes successfully, the XR camera, tracked
  controllers, hand tracking and optional passthrough support are enabled. The
  Moon appears about three meters in front of the tracking origin at eye level.
- **Desktop:** when no OpenXR runtime/headset is available, the project falls
  back to a normal `Camera3D`. Drag with the left mouse button to orbit, use the
  mouse wheel to zoom, arrow keys to orbit, `R` to reset, and `Esc` to quit.

The Moon is normalized to a 1.6-meter display diameter at runtime, so changes
in FBX source units do not make the model disappear or become enormous.
The presenter also runs as an editor tool, making the Moon visible directly in
the main scene's 3D viewport before the project is launched.

## Run on a computer

1. Open `project.godot` with Godot 4.7.2 stable or a compatible newer 4.x
   release.
2. Press **F6/F5**. With no active headset, desktop preview starts
   automatically.

On macOS, OpenXR startup is disabled by a platform override so desktop preview
opens immediately instead of waiting for a missing runtime. Android/Quest,
Windows and Linux keep automatic OpenXR startup enabled.

## Run on Meta Quest

1. Keep the Godot OpenXR Vendors plugin installed in
   `addons/godotopenxrvendors`.
2. Install the matching Godot Android export templates and configure the
   Android SDK/JDK.
3. Connect a developer-mode Quest, select the `Meta Quest 3` Android preset,
   then use one-click deploy or export an APK.

## Model license

The Moon model is by Nestaeric and is used under CC BY 4.0. See
[MODEL_ATTRIBUTION.md](MODEL_ATTRIBUTION.md) for the source link, license, and
required attribution.
