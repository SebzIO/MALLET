# SurfForge

A surf map editor that does the heavy lifting: shape ramps by dragging, test them, and export straight to SurfsUp.

## Run
Double-click `Run SurfForge.cmd` (uses Godot 4.5.1), or open this folder as a project in Godot and press F5.

## Controls
| Action | How |
|---|---|
| Select a ramp | Left-click it |
| Reshape | Drag the yellow handles (Shift+drag = raise/lower) |
| Add a bend | Double-click the selected ramp where you want it, or **Add Bend** |
| Make longer | **Extend** |
| Camera | Right-drag orbit · middle-drag pan · wheel zoom · right-drag + WASD/QE fly |
| Keys | N new ramp · Del delete point/ramp · Ctrl+D duplicate · F frame · G snap · Ctrl+Z/Y undo/redo · Ctrl+S save |

Maps save as `.sfmap` (plain JSON, engine-neutral so other exporters can be added).

## Layout
- `core/` – engine-agnostic geometry (ramp generation) shared by every exporter
- `editor/` – the editor app
- `tests/` – automated smoke tests (`godot --path . -s res://tests/smoke.gd -- <out_dir>`)

## Roadmap
1. Ramp sandbox ✅
2. Play mode (surf the map in the editor)
3. Map basics + one-click SurfsUp export (start/finish, stages, kill floor)
4. Jump checker + difficulty readout
5. Look & feel: skybox, fog, lighting, materials, textures
6. Templates, tutorial, prop import, CS:S export
