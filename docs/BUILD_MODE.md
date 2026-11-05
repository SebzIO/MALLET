# Build mode (0.6): Sauerbraten-style building in SurfForge

Build mode (press **E** in the editor) lets you fly around the map in first person and build with cubes in real
time: point at a face, roll the mouse wheel, and cubes come out of it. It is modelled on the in-game editor of
**Cube 2: Sauerbraten** (source: <https://github.com/embeddedc/sauerbraten>). SurfForge re-implements the ideas in
GDScript; no Sauerbraten code is copied.

## What Sauerbraten's editor does (from reading its source)

**The world is an octree of cubes** (`src/engine/octa.h`). Each cube is either split into 8 children or is a leaf.
A leaf stores:

- `edges[12]`: one byte per cube edge (4 edges per axis). Each byte holds two 4-bit numbers from 0 to 8: where the
  edge starts and ends along its axis. A full cube is (0, 8) on every edge; an empty one is (0, 0).
  `gencubevert` builds corner *n* (bits x, y, z) from the three edges that meet there. Its x comes from the X-edge at
  (y, z), using the low or high nibble depending on x. So the 12 edges are the same 24 numbers as 8 corners × 3
  coordinates.
- `texture[6]`: one texture per face direction (`O_LEFT, O_RIGHT, O_BACK, O_FRONT, O_BOTTOM, O_TOP`).
- `material`: what the empty space is (air, water, lava, glass, clip, noclip, death, alpha...).

A cube must stay **convex** (`isvalidcube` checks every corner against every face plane). Faces that aren't flat
are drawn as two triangles. `subdividecube` splits a cube into 8 by sampling its edges at corners, midpoints and
centre. `remip` merges 8 children back into one when nothing would change.

**Editing** (`src/engine/octaedit.cpp`):

- `rendereditcursor` casts a ray from the player. It snaps the hit to the grid (`gridpower`, so cells are
  2^gridpower units) and records the hit face (`orient`) and the corner nearest the crosshair (`sel.corner`). It
  draws the face box and the white selection box. Dragging makes a box of cells (`selinfo`: origin, size, grid,
  orient).
- `editface(dir, mode)` is the wheel:
  - mode 1 fills or empties a layer of cubes in front of or behind the selected faces;
  - mode 0 pushes all four corners of the face 1/8 (`pushedge` / `linkedpush`);
  - mode 2 pushes just the corner under the cursor.
  - `invalidcubeguard` rejects edits that would make a cube concave.
- `edittex` cycles textures from a most-recently-used list. `allfaces` textures all six faces.
- `flip`, `rotate`, `copy` and `paste`. `paste` stamps the copied block into the selection.
- `makeundo` / `swapundo`: before every edit the affected block is copied onto an undo list.

**Controls** (`data/defaults.cfg`): the wheel is `universaldelta`. Holding a key changes what the wheel does:

| Key | Wheel action |
| --- | --- |
| none | fill / empty |
| G | grid |
| F | push face |
| Q | push corner |
| Y | texture |
| R | rotate |

Other bindings: Space cancels the selection, X flips, C/V copy and paste, Z/U undo, I redo, 0 toggles `allfaces`,
F2 opens the texture menu. Left drag selects, right click extends the selection, middle click selects corners.

## How it maps onto SurfForge

A Sauerbraten cube with pushed corners is **always a convex solid with 8 corners**. That is exactly what a SurfForge
block piece and a CS:S brush are, so build mode needs no translation layer:

| Sauerbraten | SurfForge |
| --- | --- |
| octree leaf with 12 edges | `CubeWorld` leaf: 8 corners × 3 coordinates (0..8), plus 6 texture ids |
| `gridpower` (units) | grid power p: cubes are 2^p m, from 0.125 m to 64 m (default 1 m) |
| `subdividecube` / `remip` | `child_corners` / `_merge_up`: 8 equal full cubes merge into one |
| `isvalidcube` + `invalidcubeguard` | `is_valid_shape`: edits that would dent a cube are refused |
| `editface` modes 1 / 0 / 2 | `pull` / `push`, `push_face`, `push_face(..., corner)` |
| `edittex`, `allfaces` | `set_texture` with the 19-material library (and your own images) |
| `flip`, `rotate`, `copy`, `paste`, undo lists | the same, in `CubeWorld` |
| texture slots | the material library (same textures as blocks, packed into CS:S exports) |
| rendering | 16 m chunks; hidden faces between cubes are skipped; one mesh surface per texture |
| collision | per-chunk triangle mesh in the editor, an exact convex shape per cube in SurfsUp |
| CS:S | one brush per cube, each side with its own material |

**Differences from Sauerbraten, made on purpose:**

- **Building in mid-air.** In Sauerbraten you pull cubes out of existing ones. SurfForge maps start empty, so
  when you aim at nothing, the wheel builds where you're looking.
- **Building on anything.** You can also pull cubes out of blocks, ramps and platforms.
- **Pasting.** With nothing selected, V pastes on top of the face you aim at.
- **Undo.** Build mode has its own undo (Z/U and I). Back in the editor, one Ctrl+Z takes back the whole build
  session.

## Done in 0.6

- Toggle with E (or the Build toolbar button); E or Esc to return. You fly with WASD and mouse look.
- Wheel to pull cubes out and push them in, with or without a drag selection.
- F + wheel and Q + wheel push faces and corners in 1/8 steps, for slopes and bevels. Pulling a face that's
  already at its side starts a thin new cube.
- G + wheel changes the grid, from 0.125 m to 64 m.
- Y + wheel and F2 for textures, 0 to texture all faces.
- R + wheel rotates, X flips.
- C / V copy and paste, Delete removes, Z/U and I undo and redo.
- Cubes save with the map, play-test (you can stand and surf on them), and export to both SurfsUp and CS:S.

## Next (Sauerbraten features not in yet)

- **Materials for cubes:** water, lava, glass, clip, noclip, death. SurfsUp and CS:S both have equivalents.
- **Texture placement per face:** Sauerbraten's `vscale`, `voffset` and `vrotate` (O / P + wheel).
- **Heightmap mode** (H / LAlt): brush-based terrain sculpting.
- **Corner selection** with the middle mouse button.
- **Placing entities from first person:** lights, props, start / finish and stage plates where you aim.
- **Play from here:** jump into play mode at the camera.
- **Fewer CS:S brushes:** merge neighbouring cubes with the same textures into bigger brushes before export.
- **Saved cube brushes:** Sauerbraten's `savebrush` / `pastebrush`, tied into prefabs.
