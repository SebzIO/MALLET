# Changelog

Versions: 0.x are previews. The middle number goes up with each batch of new features, the last with bug-fix
releases. 1.0 is the first release we call complete (the MVP). The version lives in `core/version.gd`.

## 0.16.0 preview — 2026-11-09: Live playtesting

- **Export > Playtest session…**: start a session through a small relay server (docs/RELAY.md) and you get a
  6-letter code, or join one you made with its code and secret. Test builds made while it is open carry the
  session, so their **live positions and every attempt** arrive in MALLET while they play. Their runs file is
  still written, so a lost connection loses nothing.
- **Export > Playtest panel**: who is on right now, where they are (stage, speed), each tester's attempts, best
  time and finish speed, and the running summary. Their runs are kept with the map, like imported ones.
- **In the 3D views**: every tester is a dot in their own color with a short fading trail, their name, speed and
  stage; their finished routes are drawn as paths in that color with an × where they fell. View > Testers' paths
  turns the runs off.
- **The relay on the VPS**: `wss://relay.sebz.xyz/ws` is the default address in Settings, so a maker only types a
  name. It runs in Docker behind Nginx Proxy Manager (relay/README.md has the steps) and was tried end to end
  through it: a session opened, a tester joined, live positions and a run arrived, and a run filed while the
  editor was away was collected on rejoining.
- Fixed: a second message box (rejoining a session while the previous one was still up) no longer errors.

## 0.15.0 preview — 2026-11-08: Playtest builds (offline)

- **Export > Test build for testers…**: makes a zip with MALLET (renamed "Play <map>.exe"), the map, only the
  materials it uses, a tester.cfg and a READ ME. Each build is stamped with the map's test version (1, 2, 3…).
- Started from that folder it is a **tester program**: no editor, it asks once for a name and consent (nothing is sent
  anywhere), then goes straight into play mode. Esc pauses: keep playing or quit.
- **Every attempt is recorded** into a "tester runs" file next to it: finish / restart / fall / quit, time, stage
  splits, where they fell, finish and top speed, and the route (10 points a second).
- **Export > Import tester runs…**: brings those files back (checked, duplicates skipped), keeps them with the map
  and sums them up (testers, attempts, finishes, falls, quits, the fastest time).

## 0.14.1 preview — 2026-11-07: Looks stay straight on shaped ends

- Every ramp look (ceramic rims, dev grid, neon edges, images, library materials, your own shaders) stays straight
  where a ramp tapers, rounds off or flares. Before, the texture bent into steps there: each piece of the ramp between
  two cross-sections of different widths was drawn as two triangles, which bend a texture along their diagonal. Those
  pieces are now cut into thin strips along the true lines across the face (the bend stays under 3 cm), so it also
  holds for anything added later. Plain ramps are drawn exactly as before.
- Textures no longer smear at a diagonal cut: each point there uses its own distance along the ramp.

## 0.14.0 preview — 2026-11-07: The ramp creator

- **Ramp creator** (Add > Ramp creator…, or Ramp creator… in a ramp's panel): design a ramp's shape with a live 3D
  preview.
  - **Cross-section**: drag points on the faces (double-click a face to add one, right-click to remove), pick a face
    shape to start from (curved in, bulged out, two-step, lip near the edge), give it a flat top, make the two faces
    differ, and set the style, body, angle and face length. Parts too flat to surf (under 45.6°) show orange.
  - **Ends**, each on its own: tapered (grows from a point), rounded or flared, over as many meters as you like; a
    diagonal cut; a lip that curls the ramp up (or down) at the end; closed ends for hollow ramps.
- **Ramp prefabs**: save a design with a thumbnail, load it with a click, share it as a `.malletramp` file
  (Share… / Import…). Eleven starters: plain V, tapered entry, diagonal cut end, booster lip, rounded ends, curved
  faces, bulged faces, flat top, flared exit, closed ends, two-step face.
- **A designed ramp is still an ordinary ramp**: Apply keeps its points; drag, stretch, bend, change its angle or face
  length and the cross-section and ends follow (ends are measured in meters from each end, face points as a share
  of the face). "Plain again" removes the design. Locked ramps have to be unlocked first.
- The jump checker, fold warnings, solid / hollow, looks and both exports (SurfsUp and CS:S, including closed ends
  and cuts as brushes) all work with designed ramps; the jump checker launches from a lip's raised end.

## 0.13.0 preview — 2026-11-07: Your own skies and shaders

- **Your shaders folder** (View > Your shaders folder…, or the Folder… button beside a shader list): put Godot
  `.gdshader` files in it and they show up in MALLET. `shader_type sky;` files are skies (Map panel > Sky),
  `shader_type spatial;` files are surfaces (a ramp's or block's Look > Your own shader). Save a file and switch back
  to MALLET: it reloads on its own.
- **Every setting becomes a control**: each uniform in the shader turns into a slider, color picker, switch, number
  boxes or an image chooser, with the uniform's comment as its tooltip. "Back to the shader's own values" resets them.
- **Two commented examples** come in the folder: a cloudy sky with a sun, and a surface with glowing, sliding stripes
  and an optional image. The guide is docs/SHADERS.md.
- The sky preset, sun, shadow fill and fog settings keep working with your own sky.
- **Safe**: a shader with an error is never used. The panel shows the line and the message, and MALLET keeps the
  built-in sky or a plain color until it's fixed.
- **Maps carry their shaders**: a saved map holds the code of the shaders it uses, so it looks the same on someone
  else's computer, and a deleted shader file doesn't break the open map.
- **SurfsUp** exports embed the shaders in the map. **CS:S** exports can make the map's own sky (built-in or yours)
  into a real 6-sided skybox packed into the map ("This map's sky" in the export window, picked automatically for
  your own sky); surface shaders export as their first image, else their first color.
- Fixed: picking "Library material" in a block's Look list chose the image look instead.

## 0.12.2 preview — 2026-11-07: Outliner menu fixes

- The Outliner's right-click menu opens where you click (it used to open off to the right, shifted by where the
  MALLET window sits on the screen), and stays inside the window near its edges.
- The Outliner's right-click menu has Duplicate (Ctrl+D) and Delete (Del).

## 0.12.1 preview — 2026-11-07: Fixes for particles and the mouse

- A fire (and smoke, sparks, embers, mist, magic) can be clicked and dragged by its flames, not only by the small box
  at its base.
- Build mode can select, drag and change particle effects (clicking one used to pick nothing).
- The mouse can't get stuck any more: a view that holds the mouse while you orbit / fly lets go as soon as the button
  is really up, and coming back from build or play mode clears any click the editor missed. Before, clicks in the
  Outliner and elsewhere could stop working until you alt-tabbed out and back.

## 0.12.0 preview — 2026-11-07: Lights and particles

- **Light presets**: lamp, torch, candle, campfire, spotlight, pink and cyan neon strips, fluorescent tube, red alarm
  strobe, purple party pulse. Everything stays editable after picking one.
- **Light effects**: steady, flicker (fire), candle, slow pulse, strobe, fluorescent buzz. They play live in the editor,
  in play mode and in SurfsUp (as an animation, since SurfsUp maps can't hold scripts); CS:S gets Source's own light
  styles.
- **Light strips**: a glowing tube that lights along its length (neon signs, fluorescent tubes). CS:S gets a light
  every few meters along it.
- **Particles**: fire, smoke, sparks, embers, snow, rain, floating dust, mist / waterfall spray and magic sparkles,
  from a box-shaped area, with amount, size, speed, area and an optional own color. Add > Particles, or Tab in build
  mode (1-4 + wheel: effect, amount, size, area). SurfsUp gets the same particles; CS:S gets the nearest stock effect
  (env_fire, env_smokestack, env_spark, env_steam, rain / snow as func_precipitation). Dust and magic sparkles have
  no CS:S match and are left out with a note.
- **Map weight**: with nothing selected, the info panel counts the map's lights, how many cast shadows, and how many
  particles are alive at a time, and warns when it gets heavy for slower computers.
- Build mode's Tab menu can also place a light strip.

## 0.11.2 preview — 2026-11-07: Sauerbraten textures, better water, lava and glass

- **Sauerbraten's textures**: 315 materials from the ten Cube 2: Sauerbraten texture packs whose own licenses allow
  shipping them (aard, cloward, drakker, trak5, sheik, tomek, painkillah, g_pack, ik2k, rorschach), each credited with
  its artist and license in the picker. Every pack was checked by hand; the ones left out and why are in
  materials/SAUERBRATEN.txt.
- The material picker's search box is ready to type in as soon as it opens (F2 in build mode too).
- **Better water, lava and glass.** Water has moving waves, shows what's beneath (bent by the waves), gets darker where
  it's deep, foams where it meets walls and the shore, and reflects the sky at shallow angles. Lava is a dark crust
  drifting over glowing cracks. Glass reflects at its edges, bends what's behind it, and can be tinted or frosted.
  Presets: clear water, swimming pool, tropical sea, dark lake, murky swamp, flowing river, toxic acid, lava, magma,
  plasma; glass clear, blue, bottle green, frosted, smoked. A water block's panel has a Liquid menu (lava, acid and
  the other deadly ones turn Deadly on); build mode's water, lava and glass take their looks from the Map panel.
  CS:S gets the matching CS:S water for each water preset, lava as a glowing surface you pass through, glass tinted.

## 0.11.1 preview — 2026-11-07: Sauerbraten-style selection moving

- Build mode, Sauerbraten-style selection moving (asked for by a Sauerbraten player): hold the right mouse button
  inside the selection and drag to move the selection box (the cubes stay; V then pastes there). With Shift held when
  you let go, a copy of the cubes it started on is left there (copy + paste in one go). A plain right click still
  extends the selection or turns it to a face.
- Build mode: after C, a red box shows where V will paste. Pasting onto a face you aim at now grows away from that
  face whichever way it faces (on a -x / -y / -z face it used to grow back into the cubes).
- (Checked: a copy pasted after making the grid smaller keeps its exact shape, made of cubes at the new grid size.)

## 0.11.0 preview — 2026-11-07: materials (Getridou, LURKing, CS:S), glow, texture placing

- **Getridou's materials**: 170 materials made by Getridou (a few from photos his friends sent him), shipped with his
  permission (thank you!). They have their own "Getridou" section in the material picker with his credit, and "by
  Getridou" on each one. Converted from Tesseract's format with its own texture scale (most repeat every 8 m, as
  Getridou made them); color, surface detail, shininess and glow.
- **LURKing's materials**: 18 more from Getridou's friend LURKing, in their own "LURKing" section, with credit.
- Materials can **glow**: lit windows, lamps, signs and flames shine by themselves, in the editor, in SurfsUp, and in
  CS:S (self-illuminated). A gray glow mask glows in the texture's own colors.
- The material picker has a **search** box (name, surface, category, "glow").
- Build mode F3: **Center on selection** puts a texture's middle in the middle of the selected faces (a lamp
  texture's lamp lands on the cube you picked), **Fit to selection** also sizes it so one repeat spans them. The
  texture scale can now go down to 0.05.
- CS:S exports: a cube object's textures line up exactly as in the editor even when the object was moved off the
  texture's grid, and small texture scales are written precisely (they used to slide across faces far from the map's
  middle).
- **CS:S's own materials**: with Counter-Strike: Source installed, its 2,851 world materials (brick, concrete, metal,
  de_dust, cs_italy...) appear in the picker, read straight from your CS:S install (MALLET doesn't ship them). One
  row per folder, opened on click; search finds them too. CS:S exports use them as they are: the game's own
  materials at the game's texture scale, nothing to pack. SurfsUp exports get a switch, "Copy CS:S textures into the
  map" (remembered): on copies the real textures in; off swaps in a similar MALLET material (brick, wood, metal...).

## 0.10.0 preview — 2026-11-06: SurfForge is now MALLET

- The editor has a new name: **MALLET**, Mapping And Level Layout Editor Tool. (Hammer is Source's editor; a mallet is
  the simpler tool anyone can pick up.) Everything is renamed: the window, welcome screen, menus and messages, the
  program (`MALLET.exe`) and the tester zip.
- Maps are saved as **`.mallet`**, prefabs as `.malletprefab`. Maps and prefabs from SurfForge (`.sfmap`,
  `.sfprefab`) still open, and saving an old map writes a `.mallet` beside it. Objects copied in SurfForge still paste.
- On its first start MALLET copies your SurfForge settings (mouse, fly speed, grid, export folders), your own
  materials and your prefabs across, once, never overwriting anything.
- CS:S exports put the map's textures in `materials/mallet` (was `materials/surfforge`).
- Everything below this line was released under the SurfForge name.

## 0.9.3 preview — 2026-11-06: square grid on blocks and cubes

- Blocks and untextured cubes show the Dev grid as even 1 m squares. They borrowed the ramp's grid, which is
  stretched on purpose (lines every 1/8 across a ramp, every 1/4 along it) and drew 0.5 x 1 m rectangles on them.
  Ramps keep their own grid.

## 0.9.2 preview — 2026-11-06: no shortcuts while flying, for real

- Flying with right mouse + WASD no longer sets off D (Draw blocks), N, B, O or any other menu key: the menus ran
  their own copies of the shortcuts before the editor could tell you were flying. The menus now only show the keys.

## 0.9.1 preview — 2026-11-06: the mouse stays put while you look around

- Right-drag (orbit / fly with WASD) and middle-drag (pan) in any view hold on to the mouse: the cursor is hidden
  and can't run into the edge of the screen or onto another display, and it comes back where you pressed when you
  let go.

## 0.9.0 preview — 2026-11-06: custom zones, smooth dragging, faster building

- Custom zones: Add > Start / Finish / Stage zone (on your own platform), or tick "Zone only" on a plate. No
  built-in platform, just a see-through zone box you size and place on a platform you built. Several boxes of one
  kind (and stage number) make one zone of any shape. Works in play mode, SurfsUp and CS:S export.
- Dragging is smooth for every object (cube objects, ramps, blocks, platforms...): the jump arcs re-read every cube
  of every cube object on each mouse move, and objects were rebuilt from scratch while dragged. ~100 ms a move on
  a busy map -> a few ms.
- F3 texture settings work: color, see-through and scrolling show the texture (a shader error turned the faces
  plain white).
- Build mode: from inside cubes you aim at the face you look out through; the yellow aimed-face outline sits on
  the cubes' real face (pushed in, sloped, cut); the selected face is filled blue and stands out from the
  selection box; outlines (7) are bright cyan and drawn in front of the faces.
- Faces fully covered by smaller cubes aren't drawn any more (you could see them from inside solid terrain).
- Deep space sky: the nebula is soft clouds, no more sharp shards.
- Right mouse + wheel changes the fly speed in the 3D view (remembered; the wheel alone still zooms).
- View > Ground grid (3D view) hides the grid plane. Map panel: Clear best run.
- F in the Outliner frames the selection. Letter shortcuts are ignored while flying (D no longer toggles Draw
  blocks while you fly with WASD, E no longer opens build mode); D only toggles Draw blocks over a 2D view.
- Closing the window with unsaved changes (or a map never saved) asks: Save, Don't save or Cancel.
- Build mode: Ctrl+P plays a proper run from the map's start plate, like Play in the editor (P still plays from
  where you stand). Esc in play mode brings you back to build mode where you were.
- Editor: a selected cube object's yellow move handle is drawn in the middle of its cubes (it was at the object's
  internal origin, which can be far away), matching its X / Y / Z boxes and where dragging moves it from.
- Build mode heightmap: raising or lowering terrain no longer leaves floating sheets, overhangs or hidden gaps.
  Like Sauerbraten, each column's corners are kept within one layer of cubes (one corner may reach diagonally
  into the next), a change spreads out to the neighboring columns, a cube on a slope only covers the part that's
  solid underneath, and the cubes under a raised part are made whole again. Hills now rise in Sauerbraten's
  stepped way: pulling one spot up past a layer lifts the ground around it to that layer too.
- Build mode is faster with big builds: a heightmap stroke with the big brush takes about 50 ms instead of about
  270 ms (finding a cube no longer scans a whole 64 m area, and hidden-face checks skip work that can't matter).
  Any edit's mesh update benefits too.
- Build mode: the mouse wheel on a big selection is close to instant, even at the 0.125 m grid. Notches that
  arrive in the same frame become one edit laid down as the biggest cubes that fit (8 notches on an 8 m face:
  ~20 ms, was ~7 s), and flat faces side by side are drawn as one rectangle (a pulled 8 m floor of 0.125 m cubes
  is 2 triangles, not 8192) - it looks exactly the same. A single notch on an 8 m face at 0.125 m: ~100-200 ms,
  was ~400-900 ms. A fast spin is one undo step per frame.

## 0.8.9 preview — 2026-11-06: exact cube splits

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
  neighboring pieces still meet. Slopes that step by 1, 2, 4 or 8 eighths (like a half-45 ramp) now come out
  exactly; others stay within the 1/8 step the smaller cubes can show (overall error 3.5% -> 1.0%).

## 0.8.7 preview — 2026-11-05: fixes to 0.8.6

- Mouse sensitivity is kept in its own file (preferences.cfg): sharing settings.cfg with the export dialogs could
  wipe out remembered export folders.
- The play screen's text is centered right after it changes too (it could sit off-center for a moment).
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
  started on to the cube you end on (it used to take in the neighbors around it), it only changes the selected
  cubes, and dragging onto another cube - even one at a different height - still adds it. It can't start in empty
  space.

## 0.8.3 preview — 2026-11-05: Outliner rename fix

- Double-clicking a row renames that row (it could open the name box on another row - the list's keyboard cursor
  wasn't moved with the click). + Folder's name box also opens on the new folder reliably, and the list no longer
  rebuilds or re-highlights itself while you're typing a name.

## 0.8.2 preview — 2026-11-05: play HUD centered, Outliner clicks and drops like Windows

- Play mode: the timer, speed and keys line (and the crosshair) are centered in the view at any window size.
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
- Texture settings per face (F3): scale, turn / flip, shift (also O / P + wheel), scroll, color, see-through, and a
  blend layer; Y alone picks up the texture you aim at; Y + wheel cycles most recently used first; replace /
  replace in selection / reset (T). CS:S gets them as texture alignment and extra material files (color,
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
  face's edges; it still snaps to the face's center lines.
- Block top and bottom handles work in the 3D view (they were dragged on a level plane, so they couldn't move).
- Position fields in the panel for whatever is selected: drag a number left / right to move it as far as you like
  (Shift: fine, Ctrl: fast), or click to type. For text on a face they're Across / Up from the face's center, so
  typing 0 centers it.
- "Letter height" is now "Text size (letter height, m)".

## 0.5.3 preview — 2026-11-05: multi-line text, centering; engraving removed

- Multi-line text: the text box takes Enter for a new line; left / center / right alignment applies per line.
- Centering text on a surface: drag text along a block's face (or place it with "Place on a surface") and it snaps
  to the face's center lines - left-to-right and top-to-bottom on their own, both together = dead center. Drag
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

- Lights (Add > Light, U; Add > Spot light): color, brightness, reach, shadows; spot lights get a cone width, facing
  and tilt. They light the editor view straight away. SurfsUp: real lights. CS:S: light / light_spot entities
  (baked when the map compiles).
- Water (Add > Water, H): a block you can resize like any other, with a moving see-through surface, a color and a
  clarity. Tick Deadly for lava or acid: touching it sends players back. SurfsUp has no swimming, so water there is
  scenery (deadly water is a kill zone); in CS:S it's real water (deadly water is a trigger_teleport).
- Glow on blocks (neon, lamps): the block's surfaces shine; in CS:S its materials get self-illumination.
- Prefabs: Add > Prefab drops a ready-made piece into the middle of the view - 7 starters (small house, tower,
  gateway, lamp post, pool, lava pit, stage sign). Edit > Save selection as prefab keeps your own for any map.
- CS:S export: paper-thin sliver brushes (left over from cuts) are now left out instead of failing the compile.

## 0.4.0 preview — 2026-11-05: text

- Text (Add > Text, X): flat signs you pass through, solid 3D letters you can stand on, and engravings cut into the
  blocks they overlap (live). Any installed font by name, or a font file (.ttf / .otf / .woff).
- Letter height, depth, alignment, facing and tilt; a library material or a color; glow.
- "Place on a surface": click a face and the text sits flush on it (embossed), facing out.
- Exports: smooth letters with exact collision in SurfsUp; brushes in CS:S (func_detail for solid letters,
  func_illusionary for signs), engravings carve the blocks' brushes.

## 0.3.0 preview — 2026-11-05: materials

- Material library: 19 starter materials (CC0, from ambientCG) in 7 categories, each with color, surface detail
  (normal map), roughness and, for metals, metalness; plus your own images ("+ Your own image" in the picker).
- Materials on blocks: whole block, or any side on its own (top, bottom, front, back, left, right), with texture
  size, shift and turn; textures line up across neighboring blocks. Alt+click a face to paint it with the last
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
  named like Hammer's (Space maximizes the one under the mouse), move / rotate / nudge / snap to grid, undo.
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
- Ghost replay: race your best run; its path drawn in the editor colored by speed.

**Look**
- Sky presets (day, sunset, overcast, night, aurora, deep space) and custom colors, sun, fog.
- Ramp looks: plain, glazed ceramic, brushed steel, dev grid, aurora, nebula, neon edges, your own image.

**Export**
- SurfsUp: one click to a .pck in the Maps folder.
- Counter-Strike: Source: Hammer .vmf, optionally compiled with CS:S's own vbsp / vvis / vrad into cstrike/maps.
