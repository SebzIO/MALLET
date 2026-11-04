# SurfForge

A surf map editor that does the heavy lifting: shape ramps by dragging, test them, and export straight to SurfsUp.

## Run
Double-click `Run SurfForge.cmd` (uses Godot 4.5.1), or open this folder as a project in Godot and press F5.

## Controls
| Action | How |
|---|---|
| Views | Perspective + Top / Front / Side like Hammer · **V** toggles one big 3D view |
| Select | Left-click a ramp or platform in any view |
| Reshape a ramp | Drag its yellow handles (in 3D: Shift+drag = up/down; ortho views move along what you see) |
| Move anything | Drag the object itself · arrows / PgUp PgDn nudge by the snap step · **[ ]** rotate 15° |
| Add a bend | Double-click the selected ramp, or **Add Bend** · **Extend** makes it longer |
| Ramp style | Hollow (open V) or Solid (flat bottom, optional base depth) · width, height, smoothness, tilt, colour |
| Platforms | **B** start platform (spawn + timer start, arrow = facing) · **M** finish platform |
| Play | **P**: spawn on the start platform; the timer runs from leaving the start to landing on the finish · R restart · Esc back |
| Camera | 3D: right-drag orbit · middle-drag pan · wheel zoom · right-drag + WASD/QE fly · ortho: right/middle-drag pan, wheel zoom |
| Keys | N ramp · Del delete point/object · Ctrl+D duplicate · F frame · G snap · Ctrl+Z/Y undo/redo · Ctrl+S save |

Maps save as `.sfmap` (plain JSON, engine-neutral so other exporters can be added).

## Credits
Play mode uses SUCC by Mark Arneman (MIT): see `THIRD_PARTY.md`.

## Layout
- `core/` – engine-agnostic geometry (ramp generation) shared by every exporter
- `editor/` – the editor app
- `tests/` – automated tests: `editor_test.gd`, `play_test.gd`, `surf_physics.gd` (`godot --path . -s res://tests/<name>.gd -- <out_dir>`)

## Roadmap
1. Ramp sandbox ✅
2. Play mode ✅ (SUCC, SurfsUp's own movement code)
3. Map basics: start/finish platforms + timed runs ✅ · stages, kill floor, one-click SurfsUp export
4. Jump checker + difficulty readout
5. Look & feel: skybox, fog, lighting, materials, textures
6. Templates, tutorial, prop import, CS:S export
