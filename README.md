# SurfForge

A surf map editor that does the heavy lifting: shape ramps by dragging, test them, and export straight to SurfsUp.

## Run
Double-click `Run SurfForge.cmd` (uses Godot 4.5.1), or open this folder as a project in Godot and press F5.

## Controls
| Action | How |
|---|---|
| Views | Perspective + Top / Front / Side like Hammer · **Space** maximises the view under the mouse (again to restore) · **V** toggles one big 3D view |
| Select | Left-click a ramp or platform in any view |
| Reshape a ramp | Drag its yellow handles (in 3D: Shift+drag = up/down; ortho views move along what you see) |
| Move anything | Drag the object itself · arrows / PgUp PgDn nudge by the snap step · **[ ]** rotate 15° |
| Add a bend | Double-click the selected ramp, or **Add Bend** · **Extend** makes it longer |
| Ramp style | Hollow (open V) or Solid (flat bottom, optional base depth) · width, height, smoothness, tilt, colour |
| Platforms | **B** start platform (green: spawn + timer start, arrow = facing) · **M** finish platform (blue) |
| Zones | **K** kill zone (red: touching it respawns you) · **J** booster (yellow: arrow = push direction; strength in u/s; Add or Set speed) · an automatic kill floor sits 60 m below the map |
| Stages | **T** stage plate (purple, auto-numbered 2, 3…: checkpoint + split) · **Y** teleport (sends you to a stage plate; keep speed or stop) · labels in every view, dashed line from a selected teleport to its plate · play mode: falls/kills return you to your stage, Backspace = back to stage, R = restart run, finish needs every stage |
| Play | **P**: spawn on the start platform; the timer runs from leaving the start to landing on the finish · speed is capped at 400 u/s in the start zone (SurfsUp default: no prespeed) · R restart · Esc back |
| Camera | 3D: right-drag orbit · middle-drag pan · wheel zoom · right-drag + WASD/QE fly · ortho: right/middle-drag pan, wheel zoom |
| Look & feel | Nothing selected → **Map** panel: sky preset (Clear day, Sunset, Overcast, Night, Aurora, Deep space) and every colour, sun direction/height/colour/brightness, stars, aurora, nebula, fog. Ramp panel → **Look**: plain colour, glazed ceramic, brushed steel, dev grid, aurora (animated), nebula, neon edges, or your own image (PNG/JPG/WebP, size along the ramp in metres). Everything is embedded in the exported map. |
| Jump checker | Select a ramp: arcs show where riders fly off its end at full speed (solid) and at 85% speed (dashed): **green** = lands on a ramp, platform, teleport or booster, **red** = falls to a kill zone or the kill floor. The ramp panel shows the exit speed and the outcome. Toolbar **Jump arcs: all ramps** shows every jump at once. Speed comes from the drop since the start/stage plate (from 400 u/s); arcs assume no air strafing. |
| Export | **Export to SurfsUp**: writes `<name>.pck` into SurfsUp's Maps folder (auto-detected, remembered); in game press ~ and type `map <name>`. Restart SurfsUp before reloading a map you replaced. |
| Keys | N ramp · R generate a ramp shape · Del delete point/object · Ctrl+D duplicate · F frame · G snap · Ctrl+Z/Y undo/redo · Ctrl+S save |

Maps save as `.sfmap` (plain JSON, engine-neutral so other exporters can be added).

## Credits
Play mode uses SUCC by Mark Arneman (MIT): see `THIRD_PARTY.md`.

## Layout
- `core/` – engine-agnostic geometry (ramp generation) and exporters (`surfsup_exporter.gd`)
- `editor/` – the editor app
- `tests/` – automated tests: `editor_test.gd`, `play_test.gd`, `surf_physics.gd` (`godot --path . -s res://tests/<name>.gd -- <out_dir>`)

## Roadmap
1. Ramp sandbox ✅
2. Play mode ✅ (SUCC, SurfsUp's own movement code)
3. Map basics: start/finish platforms + timed runs ✅ · one-click SurfsUp export ✅ · kill zones + boosters ✅ · stages ✅
4. Jump checker ✅ (arcs matched the real controller's landing within 1 m) · difficulty readout
5. Look & feel ✅ sky presets + custom sky, sun, fog, 8 ramp looks incl. animated shaders and custom images
6. Templates ✅ welcome screen with 4 ready-made, jump-checked maps (Blank, First Surf, Three Stages, Aurora Night)
7. Ramp generators ✅ (R) spiral, S-curve, rollers, corkscrew with live preview; "continue from the selected ramp"
   places the new one where the jump lands (aimed so 85% speed still makes it); ramps gain a "twist along the ramp"
8. Ghost replay · prop import (glTF) · CS:S export

Templates live in `templates/` and are rebuilt (with every jump re-proven and fresh thumbnails) by
`godot --path . --resolution 1600x900 -s res://tools/make_templates.gd`.
