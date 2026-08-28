# Third-party model attribution

## Moon

- Model: [Moon](https://sketchfab.com/3d-models/moon-e6d36bb905ed42049a234e7be571d8a3)
- Author: [Nestaeric](https://sketchfab.com/Nestaeric)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Local files: `source/moon.fbx`, `source/moon_color.png`, `source/moon_normal.png`, `source/moon_rough.png`
- Project-side changes: runtime scale normalization and Godot PBR material binding; the source mesh and textures are otherwise unmodified.

The model may be shared and adapted, including commercially, provided that the
author is credited and changes are indicated as required by CC BY 4.0.

## Black Hole

- Model: [Black Hole](https://sketchfab.com/3d-models/black-hole-e410da98b1e5445eae2acafaaa53587d)
- Author: [Nestaeric](https://sketchfab.com/Nestaeric)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Local files: `source/black_hole/source/black hole.fbx` and `source/black_hole/textures/`
- **Currently unused in `main.tscn`.** The black holes are now drawn
  procedurally with a screen-space gravitational-lensing shader
  (`black_hole_lens.gdshader`), because a static mesh cannot bend the
  starfield behind it. The files and this credit are kept because
  `black_hole.gd` still supports assigning `model_scene`.
- Project-side changes: runtime scale normalization, continuous visual rotation, and the source scene's very small embedded `Planet` mesh is hidden. A separate, stationary Moon-model planet is used as the gameplay obstacle so its radius and position match the physics simulation.

The archive was supplied locally as `black-hole.zip`. The imported model and
textures remain attributed to Nestaeric under CC BY 4.0.

## Beaver (pending download)

- Model: [Beaver Inc, Global Game Jam 2020](https://sketchfab.com/3d-models/beaver-inc-global-game-jam-2020-4f9358a91d284c5ea66b3169a485bc9c)
- Author: [Edriviel](https://sketchfab.com/Edriviel)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Expected local file: `models/beaver/beaver.glb` (manual download from
  Sketchfab; the game falls back to a procedural primitive beaver until the
  file exists).
- Project-side changes: runtime height normalization to ~0.9 m and instance
  budgeting for Quest performance.
