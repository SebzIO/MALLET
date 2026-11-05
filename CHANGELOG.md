# Changelog

Versions: 0.x are previews. The middle number goes up with each batch of new features, the last with bug-fix
releases. 1.0 is the first release we call complete (the MVP). The version lives in `core/version.gd`.

## 0.4.0 preview — 2026-11-05: text

- Text (Add > Text, X): flat signs you pass through, solid 3D letters you can stand on, and engravings cut into the
  blocks they overlap (live). Any installed font by name, or a font file (.ttf / .otf / .woff).
- Letter height, depth, alignment, facing and tilt; a library material or a colour; glow.
- "Place on a surface": click a face and the text sits flush on it (embossed), facing out.
- Exports: smooth letters with exact collision in SurfsUp; brushes in CS:S (func_detail for solid letters,
  func_illusionary for signs), engravings carve the blocks' brushes.

## 0.3.0 preview — 2026-11-05: materials

- Material library: 19 starter materials (CC0, from ambientCG) in 7 categories, each with colour, surface detail
  (normal map), roughness and, for metals, metalness; plus your own images ("+ Your own image" in the picker).
- Materials on blocks: whole block, or any side on its own (top, bottom, front, back, left, right), with texture
  size, shift and turn; textures line up across neighbouring blocks. Alt+click a face to paint it with the last
  material picked.
- Ramps can wear library materials too ("Library material" look).
- SurfsUp export carries the textures inside the map; CS:S export converts the materials used to VTF / VMT with the
  right surface sounds, compiles with them and packs them into the .bsp.

## 0.2.0 preview — 2026-11-05: structures

- Blocks: box, wedge, cylinder, stairs; + Block (O) or Draw block (D) - drag a rectangle in a 2D view, Hammer style;
  resize by dragging the squares on a block's sides; move, turn, nudge, duplicate, undo.
- Hollow blocks (rooms) with a wall thickness.
- Cutters: a block that cuts its shape out of every block it overlaps (doorways, windows, tunnels), live.
- Built from convex pieces: exact collision in SurfsUp, one Source brush per piece in CS:S (cuts use Hammer's carve).
- More shapes: arch (doorway), pyramid, cone, sphere; blocks tilt on any axis (forward / back, sideways).
- Multi-select: Ctrl+click, or drag a box on empty space in a 2D view; move, turn ([ ]), nudge, delete, duplicate
  the whole selection. Groups (Ctrl+G / Ctrl+Shift+G): clicking one member selects the group; saved with the map.
- Copy / paste (Ctrl+C / Ctrl+V) through the system clipboard, so it works between maps.
- Toolbar on one row: Add, Edit, View and Export menus that show every shortcut.
- Movie-quality demo tools: trained surf bot, director, Render demo.cmd.

## 0.1.0 preview — 2026-11-04

The first tagged version.

**Building**
- Ramps you drag into shape: spline control points, bends, extend, smoothness (polygon count), quad views
  named like Hammer's (Space maximises the one under the mouse), move / rotate / nudge / snap to grid, undo.
- Ramp profile rules: upright cross-section that never tilts or rolls, slope angle + face length (56° default),
  V ramps and half ramps, hollow or solid with a base, too-tight bends marked red, Freeform for uneven faces.
- Ramp generators: spiral, S-curve, rollers, with live preview; "continue from the selected ramp" places the
  new one where the jump lands.
- Keypoint locking: freeze a ramp up to a point and keep shaping the rest as a new section, with a smooth seam.
- Direction arrows and Flip direction.
- Start / finish platforms, stages and teleports, kill zones, boosters.
- Props: glTF models (.glb / .gltf) as scenery, solid or decoration.
- Templates: Blank, First Surf, Three Stages, Aurora Night, every jump proven.

**Checking**
- Jump checker: every ramp's jump arc at full and 85% speed, live as you drag.
- Play mode with SurfsUp's own movement code (SUCC): timer, 400 u/s prespeed cap, stages, checkpoints.
- Ghost replay: race your best run; its path drawn in the editor coloured by speed.

**Look**
- Sky presets (day, sunset, overcast, night, aurora, deep space) and custom colours, sun, fog.
- Ramp looks: plain, glazed ceramic, brushed steel, dev grid, aurora, nebula, neon edges, your own image.

**Export**
- SurfsUp: one click to a .pck in the Maps folder.
- Counter-Strike: Source: Hammer .vmf, optionally compiled with CS:S's own vbsp / vvis / vrad into cstrike/maps.
