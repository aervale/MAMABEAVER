# MAMABEAVER — Godot XR spacecraft flight game (hackathon)

Godot **4.7.2** project. One scene (`main.tscn`) that runs on Meta Quest via
OpenXR **and** on desktop with no headset. You fly a spacecraft (which is the
XR rig itself — your head is the ship) through open space, **landing on
planets to collect beavers with magic bolts and delivering them to the MIT
Great Dome** at (200, 200). 10 moon-planets (landable when you touch them
slowly; lethal when fast) and 5 black holes (always lethal) pull you off
course. Fifty beavers are available; delivering any 20 to MIT wins. Play area is (-20, -20) to
(220, 220); the backdrop is a procedural starfield sky
(`starfield_sky.gdshader`) — there is no floor.

## Team conventions (important)

- **Comment thoroughly.** Multiple people are working through AI assistants,
  so every script carries a `# ====` architecture header explaining its role
  and contracts, plus inline comments on non-obvious math. Keep that up in new
  code — assume the next reader is an AI with no other context.
- Log format: `ScriptName|LEVEL: message` (LEVEL ∈ INFO/WARN/FATAL) via
  `print` / `push_warning` / `push_error`.
- GDScript style: typed declarations (`:=`, explicit `-> void`), `_private`
  prefix for internals. New to GDScript? Read `gdscript_tutorial.gd` — a
  Python-vs-GDScript crash course.

## Architecture in one paragraph

`main.gd` (root node) picks HEADSET or DESKTOP mode once at startup and
toggles cameras/HUDs. `spaceship_flight.gd` (on `XROrigin3D`) is the whole
game loop: thumbstick/WASD input, gravity, collision, arrival, restart —
plus a fuel tank (thrust burns fuel; empty = coasting), a WAITING state
(gravity engages only after B/Y so you don't drift into a planet at spawn),
and an RK4 flow predictor that publishes a projected path + SAFE/IMPACT/GOAL
verdict the minimap draws. The beaver layer: `beaver_director.gd` (on the
root `BeaverExhibit` node) spawns 5 `beaver.gd` critters per planet across
each sphere; slow planet
contact = LANDED (snap + refuel), where you can **walk the planet's whole
sphere** (stick/WASD, mapped through the camera so you move where you look;
B/Y launches you back into the flight plane clear of the rock) and the trigger/right-click fires
`magic_bolt.gd` projectiles. Their gravity scale is currently 0.0 so shots go
where you aim. Hit beavers tractor aboard as cargo, and reaching MIT banks
them (ARRIVED after 20 deliveries). `surface_dust.gd` puffs on touchdown and
while walking.
Planets (`moon_presenter.gd`) and black holes (`black_hole.gd`) are
discovered by **duck typing**, not groups: anything under `MoonExhibit` with a
`target_diameter_meters` property is a planet (gravity `a = C·r³/d²`);
anything under `BlackHoleExhibit` with `get_gravity_acceleration_at()` +
`captures()` is a black hole (softened field `a = μ/(d²+s²)`). The minimap
(`flight_minimap.gd`) draws everything with `_draw()` and is reused on desktop
(CanvasLayer) and in VR (rendered to a head-locked quad by
`vr_minimap_presenter.gd`).

## Coordinate system (biggest gotcha)

Gameplay is logically 2D: **(X, Y, altitude Z)**, matching
`Map_Coordinates_and_Radius.png`. Godot is Y-up, so:

| logical | world |
|---|---|
| X | X |
| Y | Z (depth) |
| Z = altitude (fixed at 10) | Y (height) |

`SpacecraftFlightController._logical_to_world()` does the swap. The ship
never changes altitude; minimap circles are sphere cross-sections at that
altitude (`√(R² − dz²)`).

## File map

| File | Role |
|---|---|
| `main.tscn` | The only scene. Node names matter (see below). |
| `main.gd` | Mode selection (XR vs desktop), refresh-rate sync. |
| `spaceship_flight.gd` | Core gameplay: movement, gravity, crash/arrive/restart. |
| `moon_presenter.gd` | Planet visual + `target_diameter_meters` contract. |
| `black_hole.gd` | Black-hole physics contract + procedural/imported visuals. |
| `mit_destination.gd` | Goal landmark: primitives-only MIT dome on an asteroid. Visual only. |
| `flight_minimap.gd` | Neon HUD tactical map (`_draw()`-based): bodies, flow line, fuel bar, beaver counts, expand-mode info cards. |
| `beaver_director.gd` / `beaver.gd` | Beaver spawning/mission state; one collectible critter. |
| `magic_bolt.gd` | Gravity-nudged projectile; airborne shots cannot collect Beavers. |
| `game_sfx.gd` | Original procedural firing, collection, deposit, and victory cues. |
| `mission_results.gd` | Shared desktop/XR `VICTORY!` settlement screen and score presentation. |
| `start_controls_guide.gd` | Large English quick-start controls card centred on the WAITING screen. |
| `surface_dust.gd` | Self-freeing one-shot dust puff (landing + footsteps). |
| `black_hole_lens.gdshader` | Screen-space gravitational lensing shell (layer 1). |
| `black_hole_cloud.gdshader` | Translucent swirling gas cloud (layer 2). |
| `spacecraft_visual.gd` | The ship you fly; XR position-locks its cockpit to the tracked headset (hidden while landed). |
| `flight_hud_graphic.gd` / `vr_hud_presenter.gd` | Graphical in-headset status gauges (replaced the text Label3D). |
| `vr_minimap_presenter.gd` | SubViewport → head-locked quad for VR map. |
| `desktop_orbit_camera.gd` | No-headset orbit camera. |
| `starfield_sky.gdshader` | Procedural deep-space sky (stars + nebula band). |
| `xr_hands.gd` / `xr_visuals.gd` / `xr_passthrough.gd` | Hand tracking, controller models, passthrough. |
| `tools/validate_flow_feature.gd` | Headless validation script for the RK4 flow predictor. |
| `tools/validate_beaver_feature.gd` | Headless end-to-end check of the beaver loop (run it after touching gameplay). |
| `gdscript_tutorial.gd` | Not part of the game — GDScript primer for the team. |
| `source/`, `models/` | CC-BY Sketchfab moon + black hole, Quest controller GLBs. See `MODEL_ATTRIBUTION.md`. |

**Load-bearing node names** (looked up by absolute path — renaming breaks
things silently): `XROrigin3D`, `MoonExhibit`, `BlackHoleExhibit`, `SceneryExhibit`, `BeaverExhibit`,
`DesktopCamera`, `DesktopHUD`, `XROrigin3D/XRCamera3D/FlightHUD`,
`XROrigin3D/XRCamera3D/VRMiniMap`, `XROrigin3D/ShipMarker`.

## Running

- **Desktop:** open in Godot 4.7.2, press F5. B/Y starts the run (and
  launches off planets), WASD flies, slow-touch a planet to land,
  right-click fires magic bolts (capture requires landing), mouse-drag orbits, R restarts,
  Esc quits. macOS never attempts OpenXR (platform override).
- **Quest:** Android preset `Meta Quest 3` in `export_presets.cfg`; needs the
  `addons/godotopenxrvendors` plugin + Android export templates. One-click
  deploy or export APK. In-headset: B/Y starts/launches, trigger fires
  magic bolts in flight or while landed (capture requires landing), A/X restarts.

## Gotchas

- `project.godot`'s `[xr]` section contains a comment line that got mangled
  (whitespace stripped, merged with `openxr/enabled=false`). Prefer editing
  project settings through the Godot editor UI; verify the `[xr]` keys after.
- Tuning knobs are `@export` vars on the scene nodes (gravity constant C,
  ship acceleration a, μ per black hole, radii) — check `main.tscn` values
  before assuming script defaults apply.
- `@tool` scripts (`moon_presenter`, `black_hole`, `mit_destination`) run in
  the editor; a bug in `_ready()`/`_build_*` can break the editor viewport.
- Physics tick rate is re-synced to the headset refresh rate at session
  start (`main.gd`), so don't hardcode 60 Hz assumptions.
- Hazard planets are deliberately offset from the flight altitude (world Y
  ≈ 5.5–13.5 vs the ship's locked Y = 10) for a 3D look, but every offset
  stays ≤ ~55% of the planet's radius so its collision cross-section at the
  flight plane remains meaningful. Keep that constraint when moving planets.
- `SceneryExhibit` holds big background moons far off the flight plane.
  They are **decorative only** — the flight controller and minimap scan just
  `MoonExhibit`/`BlackHoleExhibit` — so never parent a real hazard there.
- Map input: the **grip/squeeze** (`grip` analog = `/input/squeeze/value`,
  or `grip_click`), or TAB on desktop, expands the map while held. It is a
  different finger from the trigger on purpose, so it never fights firing.
  `SpacecraftFlightController.is_map_expanded()` is the contract; the VR
  quad (`vr_minimap_presenter.gd`) and the desktop panel both read it.
- Map distances are labelled `ly` for flavour but are world metres, and the
  per-planet fuel figure is a deliberately pessimistic estimate (ignores
  gravity assists) shown red when you cannot afford it.
- Altitude is locked to `start_position.z` (10) in every state EXCEPT
  `LANDED`, where `get_spacecraft_world_position()` returns the true height
  so you can stand anywhere on a planet. Minimap collision circles always
  use the flight plane, not the walker's height.
- While LANDED the rig is rotated so its up-axis follows the planet's
  surface normal (`_align_rig_up`), which is what makes walking around a
  sphere feel real; `_level_rig()` restores upright on takeoff and reset,
  because flight assumes a horizontal play field.
- Planet touchdown uses swept segment/sphere contact rather than only the
  frame endpoint. Safe-speed passes also get `landing_assist_margin`; the
  assist never enlarges high-speed crash collisions.
- `media/` holds demo stills and GIF clips (regenerate with a capture
  script; there is no ffmpeg on this machine, GIFs are built with Pillow
  using /usr/bin/python3 — the anaconda python has a broken MKL).
- **Transparent shells need a falloff.** A sphere with constant alpha
  renders as a flat disc with a hard rim, not a glow — that bug produced a
  grey bubble over MIT and hard-edged black-hole clouds. Fade by view angle
  (`dot(NORMAL, VIEW)`) or use a radial-gradient billboard instead.
- Wide `pow()` lobes in the sky shader blanket everything: the sun dust veil
  at exponent 3 washed half the sky orange and buried the starfield. It is
  exponent 9 now — keep sun effects tight.
- Each black hole is TWO layers: the opaque lensed core/photon ring plus a
  translucent `black_hole_cloud.gdshader` gas shell at the same position.
- Bolts fly straight (`bolt_gravity_scale = 0`) and ignore the planet the
  shooter stands on, so surface-skimming shots reach beavers; only a shot
  aimed squarely into the ground (dot > 0.85) is refused.
- Black holes are procedural + `black_hole_lens.gdshader`. The shell uses
  `cull_disabled` plus a `FRONT_FACING`/inside test: with normal back-face
  culling the lensing silently vanished whenever the camera was inside the
  shell — which is most of the time it matters.
- `FlightState.LANDED` is deliberately appended LAST in the enum — the
  minimap colors the ship dot by enum ordinal. Never insert states mid-enum.
- Beaver model drop-in: put the CC-BY Sketchfab beaver at
  `models/beaver/beaver.glb`. If it ships an AnimationPlayer, `beaver.gd`
  finds it, prefers a clip named idle/loop, forces LOOP_LINEAR (many glTF
  exports are play-once) and seeks to a random offset so a planet's beavers
  are not in lockstep. The procedural bob is suppressed when a clip plays and the director uses it for the first
  `imported_model_budget` (6) beavers; absent, all beavers use the
  procedural fallback. Don't raise the budget much — it's 17.5k tris each.
- After touching gameplay, run both headless validators in `tools/`.
- **Coordinate footgun**: a `Vector2` ground vector's `.y` is world **Z**,
  while a `Vector3`'s `.y` is altitude. Mixing them silently teleported the
  ship off the planet while walking. Flatten to a `Vector2` once, then stay
  in 2D. Tests that pass zero input can't catch this — assert real motion.
