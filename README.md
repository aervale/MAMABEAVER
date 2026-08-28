# Star Dodge XR: Fuel and ODE Flow Navigation

A Godot 4.7.2 OpenXR/desktop spacecraft game. Fly from logical coordinate
`(0, 0, 10)` to the MIT destination at `(100, 100, 10)` while navigating the
gravity fields and collision volumes of ten planets and five black holes.

## Current gameplay

- Left or right Quest thumbstick: head-relative horizontal thrust.
- WASD: desktop thrust for no-headset testing.
- Quest `B/Y`, or desktop `B/Y`: engage gravity and begin flight from the
  initial waiting state.
- A/X or desktop `R`: restart after collision, capture, or arrival.
- Trigger while landed: fire a magic bolt along the controller's OpenXR aim ray.
- Fuel starts at `100` and full thrust consumes `8` units per second.
- Coasting consumes no fuel; gravity and inertia continue to move the ship.
- The 3D floor mesh and floor collision are removed for an open-space view.
- The logical flight boundary remains `X/Y=-20..120` and is enforced in code.
- The upper-right minimap is shared by desktop and in-headset displays.

At startup and after a reset, the spacecraft is stationary, gravity is not
applied, and the minimap reports `FLOW READY`. Press `B` or `Y` to engage the
gravity field; the live ODE prediction and spacecraft motion then begin.

The minimap shows:

- `FUEL current/maximum` with a green/yellow/red quantity bar.
- A cyan predicted ODE flow, red when impact is predicted and green when the
  destination is predicted.
- Planets (`Pxx`), black holes (`Bxx`), the ship, view heading, total-gravity
  direction, collision cross-sections, and the MIT destination.

## ODE flow prediction

The predictor treats the horizontal spacecraft state as

```text
y = (x, y, vx, vy)
```

and integrates the vector field

```text
d(position)/dt = velocity
d(velocity)/dt = held_thrust + total_gravity(position) - drag * velocity
```

`total_gravity(position)` evaluates all planet and black-hole fields at the
predicted three-dimensional point while altitude remains fixed at logical
`Z=10`. The integration uses fourth-order Runge-Kutta (RK4), a default step of
`0.1 s`, and an `8 s` horizon. It updates every `0.1 s` so both minimaps reuse
one prediction instead of integrating separately.

The removed floor does not define the play area. `spaceship_flight.gd` clamps
real and predicted positions to `(-20,-20)..(120,120)`, while both desktop and
VR minimaps retain the same coordinate range.

By default, the forecast assumes the current head-relative thrust vector is
held. It also predicts fuel depletion; after predicted fuel reaches zero, the
remaining curve follows gravity, velocity, and drag only. The line is a live
forecast, not an autopilot route, so changing the stick or head direction
changes the next flow.

Relevant Inspector parameters on `XROrigin3D`:

```text
Fuel/maximum_fuel                      100
Fuel/fuel_burn_per_second                8
ODE flow prediction/horizon              8 s
ODE flow prediction/time_step            0.1 s
ODE flow prediction/update_interval      0.1 s
ODE flow prediction/holds_current_thrust true
```

## Runtime modes

- **Headset:** OpenXR enables the XR camera, tracked controllers, hands,
  optional passthrough, flight HUD, and head-locked minimap.
- **Desktop:** without an active OpenXR runtime, a normal `Camera3D` is used.
  Drag to orbit, scroll to zoom, use arrow keys to orbit, and press `Esc` to
  quit.

On macOS, OpenXR startup is disabled by a platform override so desktop preview
opens immediately. Android/Quest, Windows, and Linux retain automatic OpenXR
startup.

## Run on a computer

1. Open `project.godot` with Godot 4.7.2 stable.
2. Press F6/F5.
3. Press `B` or `Y`, then use WASD and watch the fuel quantity and predicted
   flow change.

## Run on Meta Quest 3

1. Keep the Godot OpenXR Vendors plugin installed in
   `addons/godotopenxrvendors`.
2. Install matching Godot Android export templates and configure Android
   SDK/JDK.
3. Connect a developer-mode Quest, select the `Meta Quest 3` Android preset,
   and use one-click deploy or export an APK.

## Validation

Run the project headlessly:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 180
```

Run focused fuel/flow checks:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path . \
  --script res://tools/validate_flow_feature.gd
```

The scene should load without `SCRIPT ERROR`, `FATAL`, or missing-resource
messages.

## Model license

The Moon and black-hole models are by Nestaeric and are used under CC BY 4.0.
See [MODEL_ATTRIBUTION.md](MODEL_ATTRIBUTION.md) for source links and required
attribution. The MIT destination is an original procedural model for this
project.
