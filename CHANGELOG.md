# Changelog

Versions: 0.x are previews. The middle number goes up with each batch of new features, the last with bug-fix
releases. 1.0 is the first release we call complete (the MVP). The version lives in `core/version.gd`.

## Unreleased

- Build mode: editing a sloped or bent cube at a smaller grid no longer changes the rest of its shape, for any
  slope at any depth (0.8.8 only fixed slopes that lined up with the smaller grid). Pieces that their own 8 corners
  can't show exactly now keep the original's exact surface, so the slope stays one flat face with clean holes.
  They draw, collide, save, rotate, flip, copy and export to SurfsUp and CS:S exactly. Pushing a face or corner of
  one of those small pieces turns it back into an ordinary 8-corner cube.
- Maps saved with this version can't be opened properly by 0.8.8 or older (cube data format 3). Cubes already
  distorted by an older version keep their distorted shape.

## 0.8.8 preview — 2026-11-06: finish speed; sloped cubes split cleanly

- Play mode: the bottom line now also shows your finish speed, meaning how fast you were going when you entered the
  finish on your last completed run. It stays there through restarts and later play sessions until you open another
  map, and the editor's status line repeats it when you go back.
- Build mode: pushing a smaller cube out of a sloped one no longer tears the slope into gaps and odd angles. When
  a cube splits into smaller ones, each new corner now slides along the cube's own edges onto the slope, so
  neighbouring pieces still meet. Slopes that step by 1, 2, 4 or 8 eighths (like a half-45 ramp) now come out
  exactly; others stay within the 1/8 step the smaller cubes can show (overall error 3.5% -> 1.0%).

## 0.8.7 preview — 2026-11-05: fixes to 0.8.6

- Mouse sensitivity is kept in its own file (preferences.cfg): sharing settings.cfg with the export dialogs could
  wipe out remembered export folders.
- The play screen's text is centred right after it changes too (it could sit off-centre for a moment).
- The test suite no longer overwrites your remembered export folders.

## 0.8.6 preview — 2026-11-05: mouse sensitivity

- View > Mouse sensitivity: a slider each for the editor's 3D view, build mode and play mode, plus invert up /
  down. Play mode uses the same number as SurfsUp / CS:S (Source-style), so your usual sensitivity carries over.
  Changes apply straight away (even while playing) and are kept for next time.

## 0.8.5 preview — 2026-11-05: no more jagged pieces; aim at pushed-in cubes; blue corner grid

- Editing a small piece of a big sloped cube no longer wrecks it (the "jagged piece"). Splitting a cube into
  smaller ones now places each small cube's corners on the big cube's actual solid, so the pieces follow its
  slopes: half the shape error of before, and never an inside-out cube (the old split made up to 54 of them).
- Heightmap edits only move the tops of the cubes that are there, so bevels and slopes on the sides stay;
  raising builds on top, lowering digs into the cube below. A banner across the top shows when heightmap mode
  (or blend painting) is on - easy to leave on by accident.
- A grid cell with anything in it - part of a cube, or a material - counts as a whole block when you aim:
  you can aim at (and middle-drag the corners of) a cube whose face is pushed in, from the cell's own face.
- Corner selection (middle drag) picks half-cell squares, one per corner (Sauerbraten's corner selection), shown
  on a blue half-size grid over the selected cubes with the chosen squares filled in.

## 0.8.4 preview — 2026-11-05: corner selection only shapes

- Middle drag + wheel (corner selection) now only shapes cubes that are already there: it never creates a cube,
  never grows one past its own side, and leaves empty spots empty. The selection runs exactly from the cube you
  started on to the cube you end on (it used to take in the neighbours around it), it only changes the selected
  cubes, and dragging onto another cube - even one at a different height - still adds it. It can't start in empty
  space.

## 0.8.3 preview — 2026-11-05: Outliner rename fix

- Double-clicking a row renames that row (it could open the name box on another row - the list's keyboard cursor
  wasn't moved with the click). + Folder's name box also opens on the new folder reliably, and the list no longer
  rebuilds or re-highlights itself while you're typing a name.

## 0.8.2 preview — 2026-11-05: play HUD centred, Outliner clicks and drops like Windows

- Play mode: the timer, speed and keys line (and the crosshair) are centred in the view at any window size.
- Outliner clicks work like Windows lists: click selects one, Shift+click selects everything from the last clicked
  row to this one, Ctrl+click adds / removes one (Ctrl+Shift adds a range), double-click renames; pressing on an
  already-selected row keeps the selection so several rows drag together.
- Dropping onto a folder works the first time, every time, and shows where it'll land: a box around the folder
  means into it, a line means between rows (Godot switched the drop modes off after each drop).

## 0.8.1 preview — 2026-11-05: exact run times

- The run timer now times the exact moment you cross the start and finish zone edges, between physics ticks.
  Before, every time was a whole number of 1/60 s steps (6.383, 6.400, 6.417...), so a best run often looked
  rounded (6.400 is exactly 384 steps). Times are now accurate to well under a millisecond.

## 0.8.0 preview — 2026-11-05: the Outliner

- The Outliner (left of the views; View > Outliner to hide it): every object in the map by name - ramps,
  platforms, zones, blocks, text, lights, props, cube objects. Double-click to rename (the name shows in the
  properties panel too); + Folder puts the selection in a new folder; folders can hold folders; drag items onto a
  folder to file them. Click an object to select it, click a folder to select everything in it - then drag in any
  view to move the lot. The eye hides things in the editor views (and clicks go through them); right-click for
  more; "Find by name" filters the list.
- Names, folders and hidden-ness save with the map and travel with copy / paste and prefabs; a placed prefab lands
  in a folder named after it.

## 0.7.0 preview — 2026-11-05: cube objects, and the rest of Sauerbraten's editor

- Cube objects: every build is an object. In the editor views you select it, drag it, turn it (Turn ±90° or [ ]),
  copy, duplicate, group and save it as a prefab; in build mode it's edited cube by cube wherever it's been moved
  to. N in build mode starts a new object. 0.6.0 maps load their cubes as one object.
- Materials (T in build mode): water, lava, glass, clip, noclip, gameclip, death, alpha - drawn in build mode (M
  hides the invisible ones), they work in play mode (lava / death send you back, glass / clip block, noclip lets you
  through) and export: SurfsUp (walls, kill zones) and CS:S (real water, player clip, trigger_teleports, see-through
  glass, func_illusionary for noclip).
- Texture settings per face (F3): scale, turn / flip, shift (also O / P + wheel), scroll, colour, see-through, and a
  blend layer; Y alone picks up the texture you aim at; Y + wheel cycles most recently used first; replace /
  replace in selection / reset (T). CS:S gets them as texture alignment and extra material files (colour,
  see-through, scrolling).
- Middle-drag selects corners (on every cube sharing them) and the wheel pushes just those; Ctrl aims at the cube
  itself (passthrough); right click on the selection turns it to that face (reorient); Shift + drag moves the
  selected cubes (editcut); J goes to the selection.
- Heightmap mode (H, or hold Alt): sculpt the tops of cubes as terrain with brushes (B + wheel: point, round,
  square... and smooth); raising and lowering builds and digs cubes as needed.
- Blend painting (keypad 1-5, 0 off, 8 / 9 brush size): paint a face's blend layer in and out (SurfsUp; CS:S
  brushes can't blend, so they keep the base texture).
- Entities from first person: Tab places a light, spot light, start, finish, stage, teleport, kill zone, booster or
  text where you aim; click to select, drag to move (Shift: up / down, 6 toggles grid snap), 1-4 + wheel change its
  settings (a light's reach and red / green / blue, like Sauerbraten), R + wheel turns it, X flips, Delete; keypad
  Enter selects the entities inside the cube selection so C / V copy them along.
- P plays from where you are and comes back to build mode; 5 hides the HUD, 7 cube outlines, 8 wireframe,
  L fullbright, F5 saves, F9 names the texture you aim at, K (calclight) - lighting is live anyway.

## 0.6.0 preview — 2026-11-05: build mode (Sauerbraten-style)

- Build mode (E, or Build in the toolbar): fly around in first person and build with cubes in real time, the way
  Cube 2: Sauerbraten's editor works (its ideas re-implemented; see docs/BUILD_MODE.md for what its code does and how
  it maps here). Mouse wheel pulls cubes out of the face you aim at (or out of thin air) and pushes them back in;
  F / Q + wheel push a face or a corner 1/8 at a time for slopes and bevels; G + wheel grid (0.125 - 64 m); Y + wheel
  and F2 textures (the material library), 0 all faces; R + wheel rotate, X flip; drag to select, right click to
  extend, C / V copy / paste, Delete, Z / U undo, I redo. E or Esc back to the editor (Ctrl+Z there undoes the
  whole session).
- Cubes are convex like Source brushes: they save with the map, you can stand and surf on them in play mode, and
  they export to SurfsUp (exact collision per cube) and CS:S (a brush per cube, textured per side).
- A map can be built from blocks or cubes alone: the exporters no longer insist on a ramp.

## 0.5.4 preview — 2026-11-05: handling fixes

- Text updates instantly while typing and while changing its size (was 0.3 - 0.5 s a keystroke): letter shapes
  are split into convex pieces about 10x faster, cached independent of size, and worked out on a worker thread
  (a box stands in for clicking until they're ready).
- Text on a block face stays on it while dragged - in the 3D view and the 2D views - and can't be dragged past the
  face's edges; it still snaps to the face's centre lines.
- Block top and bottom handles work in the 3D view (they were dragged on a level plane, so they couldn't move).
- Position fields in the panel for whatever is selected: drag a number left / right to move it as far as you like
  (Shift: fine, Ctrl: fast), or click to type. For text on a face they're Across / Up from the face's centre, so
  typing 0 centres it.
- "Letter height" is now "Text size (letter height, m)".

## 0.5.3 preview — 2026-11-05: multi-line text, centring; engraving removed

- Multi-line text: the text box takes Enter for a new line; left / centre / right alignment applies per line.
- Centring text on a surface: drag text along a block's face (or place it with "Place on a surface") and it snaps
  to the face's centre lines - left-to-right and top-to-bottom on their own, both together = dead centre. Drag
  further and it lets go.
- Engraving text into blocks is gone. As convex brushes (what CS:S needs) one word meant hundreds of pieces,
  visible seams and a slow editor. Old engraved text now loads as 3D letters (raised from the surface instead).

## 0.5.2 preview — 2026-11-05: engraving spike fix

- Engraving into a block could leave a piece shooting far out of the block (a tall spike). A speed-up in 0.5.1
  dropped planes it thought were unused; it now only drops them when the piece is provably unchanged.

## 0.5.1 preview — 2026-11-05: engraving speed fix

- Engraving text into a block froze the editor for 30 s or more. It now takes about half a second: corner points
  are no longer repeated dozens of times (a carved block was 3 million vertices, now ~65 000), texture tangents are
  worked out per face instead of by a slow general routine, and cuts skip pieces they can't reach.
- Carved blocks drop paper-thin sliver pieces (under 2 cm), which the physics engine couldn't use anyway.

## 0.5.0 preview — 2026-11-05: lights, water, prefabs

- Lights (Add > Light, U; Add > Spot light): colour, brightness, reach, shadows; spot lights get a cone width, facing
  and tilt. They light the editor view straight away. SurfsUp: real lights. CS:S: light / light_spot entities
  (baked when the map compiles).
- Water (Add > Water, H): a block you can resize like any other, with a moving see-through surface, a colour and a
  clarity. Tick Deadly for lava or acid: touching it sends players back. SurfsUp has no swimming, so water there is
  scenery (deadly water is a kill zone); in CS:S it's real water (deadly water is a trigger_teleport).
- Glow on blocks (neon, lamps): the block's surfaces shine; in CS:S its materials get self-illumination.
- Prefabs: Add > Prefab drops a ready-made piece into the middle of the view - 7 starters (small house, tower,
  gateway, lamp post, pool, lava pit, stage sign). Edit > Save selection as prefab keeps your own for any map.
- CS:S export: paper-thin sliver brushes (left over from cuts) are now left out instead of failing the compile.

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
