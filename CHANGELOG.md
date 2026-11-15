# Changelog

Versions: 0.x are previews. The middle number goes up with each batch of new features, the last with bug-fix
releases. 1.0 is the first release we call complete (the MVP). The version lives in `core/version.gd`.

## 0.30.3 preview — 2026-11-14: Clean ramps in CS:S

- **No more cracks or black lines between a ramp's pieces in CS:S.** The steps that stop the ramp bug (0.30.1)
  left see-through slits where pieces met (vbsp drops a face that lies on its neighbor's plane), and the edges of
  every piece had black lightmap texels where they touched the next one (there since CS:S export began). A ramp now
  goes to CS:S twice: the ramp you see, smooth and flush, as a non-solid func_illusionary (its faces light
  cleanly), and the ramp you ride, invisible (nodraw) with the seam steps, as func_detail. In a tester's map 156 of
  157 lit ramp faces had black edges; now the only dark texels left are real shadows.
- **Fewer pieces**: a ramp piece now runs as long as the ramp stays within 1 unit of a straight piece (up to 32 m)
  instead of a fixed 2 m, so straight stretches are one piece and bends keep as many as they need. The same map
  went from 59% of Source's brush planes to 51%, with both copies.
- docs/KNOWN_ISSUES.md lists what we know isn't right yet (first entry: ramp textures run at an angle in CS:S).

## 0.30.2 preview — 2026-11-14: Real textures in CS:S

- **MALLET's materials show up in CS:S** instead of rainbow static. The CS:S export compressed each texture with
  Godot's DXT compressor, which only exists in the editor build: MALLET.exe (the exported program) left the pixels
  raw under a DXT header, and Source read them as noise. Textures are now written uncompressed (BGR888, or BGRA8888
  when the material glows), which needs no compressor and looks sharper; each texture is about 1 MB (1.4 MB with
  glow) inside the map. CS:S's own materials and the skybox were never affected.
- New test: css_vtf_test (reads every texture file back: format, size, mip levels and the picture's pixels; run it
  with the exported MALLET.exe too). Checked with CS:S's own vtf2tga.

## 0.30.1 preview — 2026-11-14: Smooth curved ramps in CS:S

- **Curved ramps no longer stop you in CS:S.** A ramp goes to CS:S as a row of pieces about 2 m long. On a bend,
  the next piece's face tilted up against the one being ridden (a slight valley at the seam, on the inside of the
  bend, made worse because each piece was the convex hull of its two ends). Source's player box rides a hair above
  the face, so it was already inside the next face's plane when it reached that piece, hit its front, and stopped
  dead: a "ramp bug" at seams all along every curved ramp. Now, wherever a seam would form a valley, the next piece
  starts a small step lower (the least that keeps its face below the ridden one under the whole player box, mostly
  1-4 units, never more than 8), so you drop onto it instead of running into it. Each piece still ends at its true
  height, so the steps never add up, and pieces on tight bends are made shorter so their steps stay small. A
  straight ramp is unchanged. The end slabs that close a ramp's ends sit outside the ramp now (half of each used to
  overlap the last piece). If a bend is still too sharp, the export says so.
- Checked with a re-implementation of Source's player movement (the CS:S box, Source 2013's brush collision with
  vbsp's bevel planes, TryPlayerMove, air strafing into the ramp), now `tools/css_ramp_ride.py`: on a tester's map
  about 1 ride in 10 along the ramps hit a seam and lost most of its speed; on a test S-curve 88 of 708 rides did
  before and none after, and on a 90° bend none of 730.
- **The CS:S export window says which ramps CS:S can't texture**: a ramp keeps its look in CS:S only with the
  Material look (or one of your shaders MALLET can turn into a texture); Color, Ceramic, Steel, Grid, Aurora, Nebula
  and Neon come out as Source's gray developer texture, and the window now says how many ramps that is and what to do.
- New test: css_seam_test (no steps on a straight ramp, steps on curves that cover every valley, no warning on
  ordinary bends, the maps compile with vbsp / vvis / vrad).

## 0.30.0 preview — 2026-11-14: Camera shots and Render video

- **Camera shots** (View > Camera shots): a strip under the views where you make named shots from camera keys. **Add
  key here** takes the 3D view's camera (position, angle, field of view); the number fields fine-tune each key (X Y Z,
  yaw, pitch, roll, FOV, time to the next key, ease in / out); keys can be reordered, deleted, looked through, set
  from the view, and dragged in every view, where the path and a small camera per key are drawn.
- **A smooth path**: centripetal Catmull-Rom through every key (no loops between close keys), rotation by spherical
  cubic quaternion interpolation (the short way round: no flips), a Curve slider from smooth to straight, timed keys
  or even speed over the whole shot (arc-length), per-key ease, and a look-at point or object.
- **Preview**: Play and a time bar in the 3D view, with the video's 16:9 frame drawn over it.
- **Render video** (File > Render video…): one shot or all, any folder, 720p to 4K (and vertical / square), 24 to
  120 fps, AVI (Motion JPEG), PNG pictures, or MP4 when your own ffmpeg is found (MALLET doesn't ship it). A second
  MALLET draws each shot under Godot's Movie Maker, so the timing is exact whatever the machine does; its window is
  the live preview, the progress bar shows each stage (starting, loading the map, warming up shaders, frame N of M,
  writing the file) and Cancel stops it. Every frame is exactly the size picked, whatever the screen, taskbar or
  title bar (older trailer clips came out 1920 x 1061); 4K works on a 1080p screen. The window says plainly that
  without ffmpeg the video is AVI (or PNG), that bigger sizes and frame rates take longer, and, after a first
  render of 30 frames or more, about how long the next one will take (measured, not guessed). Works in the exported
  MALLET.exe.
- Shots are saved with the map (key `shots`), undoable, synced to co-editors, and never written into either export.
- New tests: camera_path_test (through every key, no flips, constant speed, ease, tension, look-at), shots_test
  (keys, fields, drag, undo, save / open, co-editing, both exporters ignore shots), shot_render_test (real renders:
  AVI and PNG at 320 x 180, 1920 x 1080 with a taskbar on a 1080p screen and 2560 x 1440: exact frame size, rate
  and count, no marker frame, the speed measured for the estimate, Cancel).

## 0.29.1 preview — 2026-11-14: Sky fixes from a tester

- **2D skies**: a `shader_type canvas_item;` shader is a sky now. MALLET draws it as a flat 2048 x 1024 picture and
  wraps it around the world (UV.x once around, UV.y from straight up to straight down); TIME animates it and its
  settings get controls. Limits: no EYEDIR or sun, a seam in the south if the picture's edges don't match, a
  still picture in the SurfsUp export, and screen effects (hint_screen_texture) are refused with why.
- **New shader files show up without restarting**: MALLET looks at the shaders folder every couple of seconds and
  whenever a shader list opens, not only when it gets the focus back. A shader saved without `.gdshader` ("n64",
  "n64.txt") and a shader type MALLET can't use are listed grayed out, saying what to do.
- **Every sky keeps its own settings**: change one sky, switch to another and back, and the first one's settings
  are still there (saved with the map, undoable; a sky preset keeps them too).
- **Play mode hides the editor's grid**: the 3D ground grid and the lights' bulbs hide while you play and come back
  as they were.
- New test: sky_fixes_test (clicks in the sky list, new and misnamed files, 2D skies live / in exports / in the CS:S
  skybox, per-sky settings with undo and save, the grid in play mode).

## 0.29.0 preview — 2026-11-14: Move, rotate and scale gizmos

- **The selected object carries a gizmo** in the usual colors (X red, Y green and up, Z blue), the same size on screen
  however far away it is, and the handle under the mouse lights up. Pick the mode on the top bar (Move / Rotate /
  Scale), with **1 / 2 / 3**, or switch with **W** (E and R stay build mode and Generate).
- **Move**: an arrow slides along one axis, a small square across two (the green one along the ground), the white
  dot is the old free drag. With a ramp point picked, it moves that point.
- **Rotate**: a see-through ball with a ring per axis the object can turn about, and an outer ring that turns about
  your line of sight. Blocks and text turn every way; ramps, platforms, zones, props, particles and cube objects
  turn about the vertical; spot lights, light strips and boosters also tilt. 15° steps while snap is on.
- **Scale**: axis lines with cube heads, squares for two axes and a middle square for all three, about the object's
  middle. Blocks and zones scale on the grid; ramps stretch their points (the middle square also widens the faces);
  props and text scale evenly; lights reach further (a strip's X cube makes it longer). Cube objects are resized in
  build mode, and Scale works on one object at a time.
- The flat views show only what works in them (two arrows, or the ring about the axis they look along). The yellow
  side squares on blocks, zones and particle areas are now part of Scale; the old yellow move square is the gizmo's
  dot. Locked objects have no gizmo, and every drag is one undo step.
- New test: gizmo_test (every handle on every kind of object, undo, the keys, hover, the flat views, locks and
  several objects at once).

## 0.28.0 preview — 2026-11-13: Even ramps (work order 2, batch 5)

- **New ramps use an "even" path.** The spine runs exactly along the straight line between two points - points in a
  line (sharing an X or a Z) give a spine on that line, with no dip or bulge below it - and turns at each point in
  one circular arc, the same curvature all the way round, tangent to both stretches. Each arc uses at most half of a
  stretch it shares with the next corner (or a whole end stretch), so arcs never overlap and moving a point only
  reshapes the corners next to it. Corner rounding sets how much of that room the arcs use.
- **Ramps already on maps keep their path** ("Straight, rounded at the points" or "Smooth curve"); the Path menu
  offers all three if you want to switch one.
- New test: ramp_even_test (a line stays a line, points sharing a Z stay on it from above, the arc's radius is the
  same everywhere, moving a point leaves the rest alone, old ramps unchanged).

## 0.27.3 preview — 2026-11-13: Ramp point alignment (work order 2, batch 4)

- The line between two neighboring points of the selected ramp turns **green** when it runs at an exact 45° step in
  that view (level, upright or diagonal - so also when the points share an X or a Z), and both its points get a
  green ring. Each view checks its own plane (top: X / Z, front: Z / Y, side: X / Y; the 3D view from above), and it
  follows the points live as you drag them. Snap to grid makes it easy to land on.
- New test: ramp_align_test.

## 0.27.2 preview — 2026-11-13: Build mode's light and texture settings in the side panel (work order 2, batch 3)

- A selected light's side panel has everything build mode's F4 has: the **color cycle** (more colors with + / -, each
  a color picker, seconds per color, random order) and **your presets** (apply, delete, save - the same presets as
  F4's).
- A selected cube object's side panel has **texture settings** like F3 for all its faces: scale, shift, scroll, spin,
  swirl, see-through, turn, color and Stop moving. Each face keeps its own texture; only the setting you touch
  changes. Undo works.
- New test: side_panel_test.

## 0.27.1 preview — 2026-11-13: Side panel sections (work order 2, batch 2)

- The side panel is split into titled sections for the map and for every kind of object: Position; for a ramp
  Direction and sections, Shape, Path and turning, Look; for a block Shape and size, Material, Look, Liquid; for a
  light Kind and effect, Brightness and reach; for the map Sky, Build mode water / lava / glass, Sun and light, Fog and
  reflections; and the same for zones, teleports, boosters, cube objects, text, props and particles.

## 0.27.0 preview — 2026-11-13: New menus (work order 2, batch 1)

- The toolbar is grouped: **File** | Add, Edit, View | Undo, Redo | Build, Play | **Playtest** | **Options**, Help.
- **File**: New, Open, Save, and **Export**, which opens a menu beside it on hover (To SurfsUp, To Counter-Strike:
  Source), as in most programs.
- **Playtest**: Playtest session, Copy invite, Leave the session, Test build for testers, Import tester runs (they
  were under Export).
- **Options**: Fullscreen (F11), Mouse sensitivity, Your shaders folder (they were under View).
- The playtest panel is shown and hidden from **View > Playtest panel** (the toolbar button is gone), and the panel
  has a close button next to its minimize button.

## 0.26.0 preview — 2026-11-13: Every shader setting

- **The aurora's colors**: the Map panel has Aurora color 1 and 2 (and the nebula's color and the sun's size), and
  the Aurora ramp / block look has a **Second color** next to its Color.
- **Every setting of every built-in shader is yours to change.** Water and lava blocks show their liquid's other
  settings under the preset (water: deep color, waves, foam, flow, refraction, glow; lava: hottest color, crust color,
  crust amount, glow, flow, blob size); the Map panel shows the same for build mode's water, lava and glass (glass
  color, clarity, frost, refraction). A preset sets them; change any one; "Back to the preset's values" undoes it.
- **None can go missing again**: MALLET reads its own shaders' settings the way it reads yours, so a setting added to
  a built-in shader gets a control without anyone remembering to. Each setting that already has its own control (or
  is internal, like the picture behind the water) is listed with where or why, and the new test
  shader_coverage_test fails if a shipped shader has a setting in neither place.
- **Your own shaders**: whole-number vectors (ivec2 / ivec3 / ivec4) get controls now, and settings MALLET has no
  control for (a matrix, an array, a cubemap) are listed under the controls as "Not shown", with why.
- Settings save with the map, undo, reach co-editors and go into the SurfsUp export (and CS:S skyboxes).

## 0.25.0 preview — 2026-11-13: Performance

Measured on a tester's map (3 cube objects, 30,000 cubes, 34 shadowed lights), frame times with vsync off:

| | before | now |
| --- | --- | --- |
| the four views | 101 ms (10 fps) | 10 ms (96 fps) |
| one 3D view | 58 ms (17 fps) | 6 ms (162 fps) |
| build mode (E) | 27 ms (37 fps) | 3.6 ms (276 fps) |
| play mode, the busiest spot | 31 ms (32 fps) | 5-6 ms (160-200 fps) |
| draw calls, four views | 111,000 | 3,900 |

With 150 more shadowed, pulsing lights the four views still run at 73 fps and play mode at 130-160 fps.

- **Cube objects draw in far fewer pieces.** A big cube object was thousands of small meshes, each drawn on its own,
  in every view and every shadow. Once a 64 m region of it hasn't been edited for a moment, its pieces are drawn as
  one mesh per material; editing there shows the small pieces again at once, so edits are as quick as before. (The
  biggest object in the tester's map: 4,203 draws -> 245.) The **SurfsUp export** draws cube objects the same way, so
  players get the speed-up too; collision is unchanged.
- **Shadows only near the camera.** A shadowed light redraws its shadows whenever anything moves (or it pulses) in
  its reach - a 2000 m light redrew the whole map every frame, in each of the four views. Now a light draws shadows
  while the camera is within 60 m of it and still lights everything beyond. The flat views (top, front, side) draw
  no light shadows at all. Exported maps get this too.
- **The Outliner** checked for changes in a way that grew with the square of the objects: 8.5 ms a frame with 230
  of them, now 0.6 ms.
- New test: batching_test. The measuring script is tools/perf_probe.gd.

## 0.24.3 preview — 2026-11-13: A warning for teleports SurfsUp may miss

- A teleport that is thin (under 6 m across in some direction) and whose box touches solid geometry is flagged: it
  turns red, its tag in every view reads "⚠ ... may be missed at speed", its info panel says why, and the SurfsUp
  export window lists it. In SurfsUp a fast player (2000+ u/s) can hit that wall before the teleport fires and arrive
  standing still; MALLET's play mode catches it since 0.24.2. Make it 6 m deep or more, or move it off the wall.

## 0.24.2 preview — 2026-11-13: Teleports at speed (fix)

- Fixed: going through a thin teleport whose box runs into a wall at high speed (about 2000+ u/s, depending on the
  gap) sent you on standing still. Play mode checked the teleport where you stood *before* each tick's move; at speed
  the move hit the wall first and zeroed your velocity, and the teleport then carried that zero over. Now this tick's
  move counts: your body (not just its middle) touching the teleport on the way sends you on at full speed. A
  teleport behind a wall still can't be reached through it. Boosters get the same check, so a thin one is felt at
  any speed.
- New test: tp_speed_test (a 3 m teleport into a wall, 1000-6000 u/s; the old code stopped you from 2600 u/s).

## 0.24.1 preview — 2026-11-12: The padlock takes a left click (fix)

- Fixed: the Outliner's padlock only reacted to a right click. The Outliner handles left clicks itself (selecting,
  dragging) and only let the eye's column through to its buttons; now the padlock's does too. The test clicks it
  with a real left click now.

## 0.24.0 preview — 2026-11-12: Locking

- **Lock things so they stay put**: every object in the Outliner has a **padlock** next to its eye (right-click >
  Lock / Unlock does the same for a selection). A locked object can't be moved, edited or deleted: it can't be
  dragged, nudged with the arrows, turned, extended or bent, its panel and handles are off, and clicks in the views
  go straight through it (box select and Select all leave it out too). In build mode its cubes can't be changed and
  a locked light or zone can't be grabbed.
- **Lock a folder** and everything in it is locked, folders inside it too.
- Selected in the Outliner, a locked object is outlined in amber and the side panel says it's locked, with
  **Unlock** (which also unlocks the folder that locks it). It can still be copied (the copy isn't locked), hidden,
  renamed and filed.
- Locks save with the map, undo like any change, and reach co-editors.
- New test: lock_objects_test.

## 0.23.3 preview — 2026-11-12: Particle areas (fixes)

- Fixed: changing a particle effect (Sparks to Rain...) put its area back to the new effect's own and dropped your
  own color. Now only the effect changes; the area you made and your color stay.
- Particle effects have **side squares** like zones and blocks: drag one in any view to stretch or shrink the area
  from that side (the opposite side stays put; snap applies; 0.1 m at the smallest).
- New test: particle_area_test.

## 0.23.2 preview — 2026-11-12: Typing boxes behave (fixes)

- Fixed: clicking off a box you were typing in (a booster's "Push angle above horizontal", and every box like it)
  left you typing in it. Now a click anywhere else ends the typing and takes the value you typed (a value that
  isn't a number goes back to what it was). Everywhere: the side panel, build mode's panels, the material maker.
- Number boxes only take numbers: letters never get in (a comma becomes a point). Text boxes - names, search, a
  sign's words - still take anything.
- New test: field_guard_test.

## 0.23.1 preview — 2026-11-12: Spin back to 0, type any value (fixes)

- Fixed: the **Spin** slider in build mode's texture settings (F3) couldn't land on 0 - over -360 to 360 a short
  slider jumped from about -3 to +3 - so a face kept turning, and so did every texture put on it afterwards (a
  face keeps its texture settings when its texture changes). The scroll, spin and swirl sliders now land on 0 near
  their middle, on ramps too, and F3 has **Stop moving** (scroll, spin and swirl back to 0).
- **Every F3 setting has a box to type a value in** (scale, shift, scroll, spin, swirl, see-through); scale, shift,
  scroll, spin and swirl take any number. Each setting sits on one row with its slider, so the panel fits on a
  768-pixel-tall screen again; hover a name for what it does.

## 0.23.0 preview — 2026-11-12: Shine, spin and a look for every pool

- **A material's finish** (material maker > Finish, with a turning ball that shows it): **Brightness x** and **Light of
  its own** with no upper limit (type any number), **Glossiness** up to mirror-smooth and **Reflectiveness** up to a
  perfect mirror. It follows the material everywhere: ramps, blocks, cubes, the SurfsUp export, and CS:S (reflections
  as the map's cubemap, brightness as $color, its own light as self-illumination; the export now places an
  env_cubemap at each spawn - run buildcubemaps once).
- **Gamma** in the material maker's Adjust colors layer (type any number).
- **Reflections of the map** (Map panel): shiny materials reflect the map itself (screen-space), not only the sky.
- **Spin and swirl**: a ramp's texture settings and build mode's F3 can turn the texture (degrees a second) and twist
  its middle into a spiral, on top of scrolling. Each repeat turns around its own middle (Fit to selection turns a
  whole face as one). CS:S spins it too; it can't swirl. Their number boxes take any value.
- **A look for every pool**: build mode's T menu, Fill tab, has "Their look" for water, lava and glass. "The map's
  look" follows the Map panel as before; any other look belongs to that fill, so each pool can differ (water blocks
  already had their own). It is still water / lava / glass for playing and exporting.
- New test: finish_test.

## 0.22.0 preview — 2026-11-12: The guide (1.0 checklist)

- **The MALLET guide**: a first map in ten minutes, then ramps, zones, playing and practice, build mode, materials and
  the material maker, testing with others, exporting, and every key. It opens in your browser from the new **Help**
  menu (also: What's new, every version) and from **New here? Read the guide** on the welcome screen. It ships as
  `docs/GUIDE.html`; READ ME FIRST is short again and points to it.
- **A fifth template, Cube Park**: built in build mode from the Geometry menu, two V ramps of cubes joined by a
  teleport to a destination that keeps your speed. The welcome screen shows three templates a row and says what's
  new.
- **Playtest summary**: for each stage, how many attempts reached it and the best split (by whom), and where the
  runs that didn't finish ended - where people give up or keep falling.
- Fixed: **closing MALLET could crash** once a text sign had been made (its letters are worked out on a worker
  thread, and the finished task was never collected; Godot freed it after the scripts at shutdown). The three tests
  that crashed on exit (handling, text, world) were this and now exit cleanly.
- Fixed: the Geometry menu's **triangular prism ignored its Length** and was always 4 cells long.

## 0.21.0 preview — 2026-11-12: The material maker

- **Make your own materials, or change existing ones**: in the material picker, **Make / edit a material…** (or
  right-click any material to start from it). Start from a library material or a plain color and stack layers on
  top: **color changes** (hue, saturation, brightness, contrast), **fills**, **stripes / lines**, **rectangles**,
  **ellipses**, **text**, **images** of your own and a **paint** layer you draw on with a brush (eraser, Shift+drag
  for a straight line, Ctrl+Z). Every layer has a color, opacity and blend (mix, add, multiply, subtract), can be
  moved, hidden, copied or deleted, and stays editable. Shapes wrap at the edges, so the texture still tiles; a
  tiled 2 x 2 view shows it repeating.
- **A line on a ramp's ridge**: **+ Ridge line** adds a black stripe down the middle and turns on **Fit across a
  ramp**: on ramps the picture then spans the riding surface once from edge to edge, so the middle is the ridge
  (the **Ramp guide** shows where). The SurfsUp and CS:S exports line it up the same way.
- Saved materials join **Made by you** in the picker and keep the starting material's surface detail (normal,
  roughness, metal and glow maps). **Save** changes one of yours everywhere it's used; **Save as new** keeps both.
- **Your materials travel with your maps**: a saved map carries the ones it uses (your added images too), and opening
  it on another PC puts them in that library. Co-editors get a material as soon as it's saved.
- New test: material_maker_test.

## 0.20.0 preview — 2026-11-12: Practice tools in play mode

- **Turn binds**: hold the left mouse button to turn left, the right one to turn right, at a steady speed (View >
  Mouse sensitivity: 210 degrees a second to start, Source's cl_yawspeed default).
- **Q / E**: save your position (with your speed and where you look) and go back to it.
- **2-9**: go to that stage's plate; **1** restarts, like R.
- **N**: noclip - fly through everything (W A S D, Space up, Ctrl down, Shift faster).
- **T**: show or hide the zones, teleports, boosters and kill zones. They're hidden in play mode now, as in the game.
- Loading a position, a stage jump or noclip make the run **practice**: the timer says PRACTICE and a finish doesn't
  count towards your best time, ghost or tester data. R starts a real run again.
- New test: practice_test.

## 0.19.9 preview — 2026-11-11: Teleports that just move you on

- **Teleport destinations** (Add > Teleport destination, or T > Platforms & zones in build mode): a spot where the
  player's feet land and an arrow for the way they look. A teleport's new **Goes to** setting sends players to a
  stage, as before, or to a destination: they keep their speed (its direction too, as SurfsUp's point teleport does)
  and look along the arrow, but no stage is reached and their respawn stays where it was - fail after it and they go
  back to the start (or the last stage they really reached).
- Exports: SurfsUp gets a point teleport to a marker; CS:S a trigger_teleport to an info_teleport_destination (CS:S
  teleports stop the player, as the export already warns). A teleport to a destination that isn't there is flagged.
- The editor draws a dashed line from a teleport to its destination, like it does to a stage.
- New test: tp_dest_test.

## 0.19.8 preview — 2026-11-11: The Geometry menu grows up (pre-1.0 batch 9, the last)

- **Yaw, Pitch and Roll** for every shape but spheres and stairs: the shape's planes are turned before it's cut into
  cubes, so a turned shape is exact octree cubes (a box turned 30 degrees has exactly the surface it had).
- **The octree's own test**: after a shape is cut into cubes, points spread through the true shape must all land in
  a cube. A shape the octree can't make whole at your grid and detail isn't shown or placed, and the menu says what
  to change. Thin slabs and many-sided cones pass (cut cubes hold them exactly).
- **New shapes: Quarter pipe and Halfpipe** (length, radius, floor under it, deck behind / flat bottom), concave and
  smooth, built from cut cubes like every other shape.
- **Shape presets**: save the shape you've set up (its values, turn and detail) under a name and bring it back.
- (Bigger cubes: since 0.19.0 a placed shape's solid inside merges into the biggest cubes it can.)
- Ramp fixes to 0.19.6: locking a ramp with the straight-with-rounded-corners path no longer moves it (the path is
  now worked out once over all the points); a steep stretch starts turning with the spine at 60 degrees, not 40, so
  every ramp up to 60 degrees keeps its upright cross-section.
- New test: geo_gen_test.

## 0.19.7 preview — 2026-11-11: An experimental heightmap (pre-1.0 batch 8)

- **Shift+H** in build mode turns on the experimental heightmap: each stroke is shaped at random (every corner's
  push is scaled by a noise value there), so the same brush no longer stamps the same shape over and over. Every
  face stays joined: a heightmap is corner heights its columns share, so whatever height a corner gets, every face
  that meets there meets there. H alone is the normal heightmap, unchanged. The bottom bar says which is on.
- New test: hmap_rough_test (drops rays 25 cm apart onto the terrain: no cracks or pits in either mode).

## 0.19.6 preview — 2026-11-11: Ramps that follow your lines (pre-1.0 batch 7)

- **New ramps run straight from point to point**, rounded only near each point (Path: "Straight, rounded at the
  points", with a Corner rounding setting). The smooth curve sagged under the lines you set and flared up at the end;
  it's still there as "Smooth curve through the points", and ramps in maps made before keep it, so nothing you've
  built changes shape.
- **Steep drops keep their shape**: from 40 to 75 degrees the cross-section turns to stand square to the spine, so a
  point dragged right under the one before it makes a bend that follows the spine instead of flattening. Ramps under
  40 degrees are exactly as before (surf speed on the reference ramp is unchanged).
- **Pitch, Yaw and Roll** for a selected ramp (sliders and boxes): pitch and yaw turn the whole ramp around its
  middle, roll banks its cross-section around the spine.
- The ramp creator starts with a straight ramp (it started curved).
- New test: ramp_path_test.

## 0.19.5 preview — 2026-11-11: The 2D editor (pre-1.0 batch 6)

- A selected object behind another one is still the one you grab and drag; a click where no selected object is picks
  the one in front, as before.
- Zones, kill zones, boosters, teleports and platforms stretch and shrink by squares on their sides in the 2D views,
  like blocks (the other side stays put).
- **Draw blocks is Shift+O** (it was D, which is for flying); O still adds a block.
- Ramp textures get build mode's texture settings: turn and flip, shift across and along, scroll, and see-through,
  in the ramp's properties under its material. They show the same in SurfsUp.
- (Re-checked: the draw tool starts on the grid point you aim at since 0.17.9, and drawn blocks become build-mode
  cubes the first time you edit them since 0.17.14; both have tests.)
- New test: editor2d_test.

## 0.19.4 preview — 2026-11-11: Lights you can handle, color cycles, soft light (pre-1.0 batch 5)

- Build mode: a light is an invisible handle: its bulb hides and a box shows where it is, blue, with the face you
  aim at in orange. Aiming picks the light alone, even with a cube right behind it.
- Clicking a light no longer moves it. Dragging it moves it freely, off the grid, across the plane of the face you
  grabbed (grab a side to move it up and down, the top to move it around).
- Copying a light copies just the light; pasting puts it on the middle of the face you aim at.
- A light's reach goes up to 2,000 m (was 200 in build mode, 400 in the editor).
- **Color cycles** (F4, with Slow pulse or Flicker): add colors with +, take them off with −, set the seconds per
  color. Pulse flows through them; Flicker jumps between them, in order or at random. They play in SurfsUp too.
- **Softer light on slopes**: where cube faces meet at less than 44 degrees (Sauerbraten's lerpangle), light rolls
  smoothly across them instead of stepping at every triangle; a cube's sharp edges stay sharp.
- New test: lights_test.

## 0.19.3 preview — 2026-11-11: Clean fills, a Fill tab and presets (pre-1.0 batch 4)

- Fills (glass, water, lava...) poured over blocks no longer flicker: no fill face is drawn where a cube's face is
  already there, whether the cube is in the fill's own cell or beside it, and over a pushed-in face only the part
  it leaves open is drawn, cut exactly to its shape.
- The T menu has a **Fill** tab of its own (it was part of Session), and its title bar stays where it is when you
  switch tabs (it moved as the menu changed size).
- **Presets** for light settings (F4) and texture settings (F3): save what's set under a name, apply it to any
  other light or faces, delete the ones you don't need. A light preset keeps everything but where the light is and
  which way it points; a texture preset keeps the settings, not the texture. They work in every map.
- New test: presets_test (and fill_test checks the new cases).

## 0.19.2 preview — 2026-11-11: Selecting as in Sauerbraten (pre-1.0 batch 3)

- The selected face is drawn as its whole square, however much of the geometry in it is pushed in, and outlines sit
  right on the blocks (no gap at small grid sizes: they used to float 1 cm off the face).
- The red box is Sauerbraten's origin marker: one small box at the selection's lowest corner, the same size whatever
  you select (it was the paste box, as big as what you copied).
- Picking always goes by the real geometry: aiming at pushed-in faces picks those cubes, never the air in front of
  them. Holding Ctrl for this is gone (it's how it always works now).
- A big grid over smaller cubes shows the one grid cell, never the small cubes' faces.
- Right-pressing a face of the selection turns it to that face, then a drag moves it across that face's plane only.
  Any face of a selection can be right-clicked, even where it holds only air.
- The bottom bar shows how many blocks are selected.
- A paste is the whole copied box: the air in what you copied is air where you paste it, so what was there doesn't
  show through its holes (as in Sauerbraten).
- A kill zone placed from the T menu fills the selection exactly.
- New test: selection_test.

## 0.19.1 preview — 2026-11-11: Play mode as in SurfsUp (pre-1.0 batch 2)

- No sprint in play mode, as in SurfsUp (Shift does nothing there; build mode keeps Shift to fly fast). You leave
  the start platform at 400 u/s at most, as before.
- Build mode: **P is Play (Start)**, a proper run from the start platform, and **Ctrl+P is Play (Current
  Position)**, from where you are. Both are in the bar at the bottom, next to E for the editor, and in F1's keys.
- Start, finish and stage platforms show their zone as an outline in the platform's color instead of a colored
  see-through box.
- A co-editor in build mode is a person: legs with feet pointing forward, a body, arms, a head with the glowing
  visor, all facing where they look (the head tilts up and down with their view).
- (Already in 0.18.17: strafing away from a ramp no longer drops you.)

## 0.19.0 preview — 2026-11-11: Big maps stay quick (pre-1.0 batch 1: performance)

Measured on a tester's 76,000-cube map:

- **Undo and redo: 18 s each, now 0.01 s.** A step used to reload and re-mesh the whole map; now only what the
  step changed is touched, down to the single cubes of a cube object, and everything else stays exactly as it is.
- **Opening it: 20 s, now about 6 s, and MALLET keeps running while it draws in.** Cube objects are drawn on every
  core, the nearest pieces first, and play mode waits only if you press P before it has finished.
- **Cubes merge**: wherever 8 cubes of a bigger cell are the same full cube (same textures, nothing folded, cut or
  painted, the same fill around them) they become that one bigger cube, level after level, like Sauerbraten's remip.
  Maps are merged as they open, and so are shapes from the Geometry menu (F6). Nothing looks or plays differently;
  there are just far fewer cubes to load, draw, save and edit (a test scene went from 2,960 cubes to 867).
- **Fills are quick and one thing**: filling a big selection with water, lava, glass or another fill scanned every
  fill cell for each cell it filled; 8,192 small cells took 15 s, now 1 s, and become 16 big cells.
- Fill surfaces are worked out piece by piece where cells of different sizes meet, so no fill face shows against
  solid cubes, however small, and no inside faces appear.
- New tests: undo_diff_test, fill_test, merge_test.

## 0.18.18 preview — 2026-11-11: Co-editing keeps up with big pastes, and small grids stay smooth

- Co-editing: a paste of more than 8 objects only sent the first 8 to the others; the rest were dropped for good.
  Deleting several objects removed only every other one on the others' side. Both fixed.
- Co-editing: a change to a cube object over 200 KB (most real builds: the cube objects on the map that showed this
  are 3.5 MB and 1.7 MB) was never sent, so build-mode work on it, including copy and paste inside it, never
  reached the others until they rejoined. Edits to a cube object now go as just the cubes that changed (and where
  it is, its name and folder), and anything still too big for one message (a pasted big cube object) goes in parts.
  If a copy has drifted apart, it notices and gets the whole object again.
- Build mode: at a small grid (0.125 m), aiming at a big cube object with lava or glass in it could take up to 0.4 s
  a frame. Every empty cell along the line of sight checked every material cell in the object; that check is now
  instant, and the aim jumps over empty space instead of crossing it cell by cell. Aiming finds exactly the same
  cell as before.
- New tests: aim_skip_test, co_sync_test (two MALLETs on a real relay).

## 0.18.17 preview — 2026-11-11: No more being thrown down the ramp

- Play mode: flicking away from a ramp mid-surf (a j-turn) could throw you down the ramp and end the run. The
  movement code (SUCC) tilted your air strafe to follow the ramp's face, so a flick away from the ramp pointed down
  the slope; if you were still moving up at that moment, one tick could take away all of your climb (9 m/s in one
  tick at 10 m/s up a 60-degree ramp). Strafing into a ramp while falling did the opposite and canceled the fall. Air
  strafing is now horizontal, as in Source and SurfsUp; a ramp only redirects your speed along its face. A flick now
  costs nothing but gravity, and strafing into a ramp gives exactly what Source gives.
- Straight surfing is unchanged (2,137 u/s after a 76 m drop; SurfsUp measured about 2,200), and the physics tick
  rate makes no difference to it.
- New test: surf_flick_test.

## 0.18.16 preview — 2026-11-11: Export button back

- The Export to SurfsUp and Export to Counter-Strike: Source dialogs grew taller than the screen, so their Export
  button was off the bottom. Their wrapped text was measured before it had a width (one word a line) and the dialog
  kept that size. They now open at the right size every time.
- New test: dialog_fit_test (every dialog fits a 1600 x 900 screen with its buttons showing).

## 0.18.15 preview — 2026-11-11: Maps of big blocks are fast again

- Maps built from big cubes (made before 0.18.12) ran slowly when you looked toward the build, and in play mode the
  player couldn't move. 0.18.12 cut every cube object into 4 m pieces so big edits redraw quickly, but a cube goes in
  the piece it starts in, so a map of spread-out big blocks became one piece per block: a 76,000-cube map made
  14,700 pieces (about 7 fps), more physics bodies than the physics engine allows, and the player was never created
  properly. Pieces now come in two sizes by cube size: cubes of 0.5 m or less (generated shapes, detail) in 4 m
  pieces, bigger cubes in 16 m pieces. That map is now 850 pieces at about 100 fps, and big edits stay smooth.
- The physics engine now allows 65,536 bodies (it was 10,240), so a very big map can't stop the player again.
- Lava and death material inside cube objects kills in play mode again (it was dropped with an error).
- New test: chunk_budget_test.

## 0.18.14 preview — 2026-11-11: Release of the 0.18.6-0.18.13 fixes

- Framing the 3D view on a course no longer fails on maps with blocks, cube objects, lights or other scenery (it looks
  at the ramps and platforms only).

## 0.18.13 preview — 2026-11-11: A trail for crashes

- MALLET keeps a short trail of what you just did in build mode (keys, clicks with Shift / Ctrl / Alt, each cube edit,
  background redraws) in its logs folder (actions.log, and actions_previous.log for the session before), written
  line by line so a crash can't lose it. Godot now keeps 30 log files instead of 5. If MALLET ever closes on its own,
  those files say what it was doing.

## 0.18.12 preview — 2026-11-11: Big edits without the hitch

- Deleting or pushing away lots of cubes at once no longer freezes MALLET. On a 32,000-cube sphere, pushing an 8 x 8
  layer used to stall for about 4 seconds; now the cubes change in about 15 ms and the redraw happens in the
  background, a few pieces a frame, so MALLET stays smooth (no frame over about 10 ms) while it catches up.
- Clearing cells found their cubes by checking every cube in a 64 m area; it now goes straight to them.
- Cube objects are drawn in 4 m pieces instead of 16 m ones, so an edit redraws only what's near it. Small edits are
  still redrawn instantly.

## 0.18.11 preview — 2026-11-11: Template pictures in the installed program

- The welcome screen's template pictures show in the installed MALLET. They were only working in the development
  version: the screen read the raw PNG files, which an exported build doesn't have.

## 0.18.10 preview — 2026-11-11: Instant outlines

- Build mode's 7 (outlines) is instant. It used to rebuild every cube object each time; the outlines are now made along
  with the mesh, and 7 only shows or hides them.

## 0.18.9 preview — 2026-11-11: Smooth hovering over big shapes

- Build mode stays smooth while you aim at a big shape with a large grid. The highlight used to outline every small
  cube inside the hovered grid cell, every frame (264 ms a frame at an 8 m grid, now under 0.3 ms). A cell holding
  more than 8 small cubes is now highlighted as its plain square.

## 0.18.8 preview — 2026-11-11: Big generated shapes draw faster

- Drawing a big generated shape is more than three times faster (a 36,000-cube cone: 9.2 s down to 2.8 s). Each cut
  cube's faces are found by clipping instead of trying every combination of planes, and the work is spread across
  the CPU's cores.
- The same cone has 77% fewer triangles (230,000 down to 52,700): walls between cubes that nobody can see are no longer
  drawn, which also makes the map lighter to render and to collide with.
- Neighboring pieces overlap by half a millimeter when drawn, so no pinholes show where those walls used to be.

## 0.18.7 preview — 2026-11-11: Instant play mode with big cube objects

- Pressing P and Esc no longer stalls after placing a big shape (9.5 seconds each way on a large cone, now a few
  milliseconds). Entering and leaving play mode redrew every cube object in full just to hide or show invisible
  materials; now only the chunks that hold them are redrawn.

## 0.18.6 preview — 2026-11-11: No more holes in cones

- Generated shapes no longer have see-through pits. Along the seams of a many-sided cone or cylinder, cubes cut by two
  nearly parallel planes lost a face to rounding error: up to a fifth of a 64-sided cone's surface was missing, in its
  collision too. Cut cubes are now worked out at full precision.
- CS:S: cut cubes are written from their exact planes, corners a few millimeters apart are merged and slivers too thin
  to be a brush are left out, so the compiler handles these shapes without crashing.

## 0.18.5 preview - 2026-11-11: Heavy shapes stop hitching

- The preview is now built on a worker thread, so a slider never waits for it. One rebuild runs at a time and the
  shape catches up as each lands, always with the newest values. Before, the work ran inside the frame, so every
  shape past a certain size - a wide cone, many sides, fine detail - stalled the editor for a tenth of a second up to
  several seconds. On a cone at the default grid (radius 13, height 4, 24 sides, detail 2, 18,732 cells) a rebuild
  took 1.6 s of frozen frame; that cost is now off the main thread and dragging stays smooth. Shapes that build in
  under 40 ms (a box, a ramp, a small cone) still rebuild in the frame itself, with no delay at all.
- A cut face a plane cannot reach is no longer rebuilt: the polygon clipper returns it as it is. A 64-sided cone's
  preview went from 85 ms to 75 ms, and the shape it draws is unchanged.
- Placing still builds the exact shape on the spot, and it can never place the quick preview.

## 0.18.4 preview - 2026-11-11: A geometry menu that keeps up, and numbers that stick

- Dragging a slider used to stall the editor: every tick of the slider rebuilt the whole preview through a
  `CubeWorld` and its render chunks, which cost over a second on a cone. The preview and the placing ghost are now
  meshed straight from the generated cells - one surface, no textures, faces with a cell behind them dropped - and
  rebuilds are coalesced to one per frame. While a value is still moving the shape is drawn at grid detail (cheap
  enough to follow the slider); the exact detail follows 0.15 s after it stops. A 25-sided cone, radius 4, height 4:
  1,150 ms per tick became 33 ms while dragging and 316 ms for the single exact pass at the end.
- Generating a shape is quicker too: for cones, cylinders, prisms and pyramids, "is this cell wholly inside, wholly
  outside, or cut" is now decided from the cell's middle and its reach along each plane instead of eight corners
  against every side.
- A typed value now stays: the number field was repainted with the old value the moment the new one was taken, so
  width 6.5 looked ignored even though the shape had changed. Pressing Enter now shows the value that was taken
  (clamped and rounded as it really is), and dragging a number field changes the shape, which it never did before.

## 0.18.3 preview - 2026-11-10: A whole cone, not a quarter of one

- The cone and the cylinder were only a quarter present: their planes stood the shape around `(r, 0, r)`, but the
  cells are laid out from `(0, 0, 0)`, so only the `+x+z` quarter fell inside the box (the offset that looked wrong
  was in fact compensating for that center). Both now fill their whole box: a radius 4, height 4 cone at 0.25 m
  detail is 2,908 cells, and sampled points in all four quadrants land in a cube.
- The sphere, the ramp and the flat-sided shapes are unchanged.

## 0.18.2 preview - 2026-11-10: Round shapes are round

- A cone and a cylinder were wrong twice over: their side planes sat at `r + r cos a + r sin a` instead of `r`, which
  ballooned the shape and then clipped it against its own box, and the cells around it had their corners pulled
  toward each cell's middle, so neighbors stopped sharing corners and the surface broke into scattered cubes.
- Every shape is now built the same way as the ramp: full cubes inside, and where the surface crosses a cell, that
  cell keeps the shape's own plane as its cut. A cone is a cone (262 cells at a 0.25 m detail), a cylinder is a
  cylinder (484), and the sphere is faceted by planes that touch it. No corners are pulled anywhere, so there are no
  gaps at cell boundaries.
- The corner-trimming code this replaced is gone.

## 0.18.1 preview - 2026-11-10: A ramp with a flat face

- A ramp is no longer a staircase of corner steps. Each cell carries the slope as its own **cut plane** - the exact
  form the octree already keeps for a pushed face - so the whole face is one flat plane. A 16 x 8 m ramp on a 1 m
  grid is 48 cells, and CS:S gets one slanted brush face instead of a stair of cubes.
- The other shapes stop filling a whole cube where the surface only clips a cell: the cell becomes the biggest box
  that is genuinely inside the shape, so a sphere, cone or pyramid has no 10-20 cm block sticking out of it.
- The ramp test now checks the face itself: every cell the slope runs through must sit on the same plane.

## 0.18.0 preview - 2026-11-10: A geometry menu in build mode

- **Geometry (F6)**: pick a shape - box, sphere, cylinder, cone, pyramid, triangular prism, rhomboid, stairs or
  ramp - set its sizes in **grid units**, and place it. Every shape is made of octree cubes, so it stays fully
  editable with the tools you already know (push faces, corners, heightmap, materials, copy/paste, export).
- **Detail** says how many levels finer than the grid the surface may be cut. Cells wholly inside the shape stay
  as big cubes; the ones the surface passes through are split, and the corners outside the shape are pulled onto
  it. A ramp is a real slope and a sphere is round, without thousands of cubes in the middle.
- The menu shows a **3D preview** you can turn (drag) and zoom (wheel), its size in meters, the cube count, and the
  finest cube used.
- **Place in map** turns it into a ghost: it follows where you look, snapped to the build grid, moves a cell at a
  time with right-drag, and **Enter** builds it (**Esc** goes back to the menu). A placed shape is one cube object
  and one undo step.
- A shape that cannot be built says why instead (too many cubes, a zero size), and anything the octree cannot cut
  cleanly is filled rather than left with a hole.

## 0.17.15 preview — 2026-11-09: A co-editor's view cone comes out of their eyes

- Another editor's dot, facing arrow and field-of-view cone used to start at their feet, because their cursor
  message carries their **camera** position while the body stood its feet there - so the body floated an eye
  height up and the cone left its shoes. The body now stands one eye height lower (`CoAvatar.EYE_AT`, 1.65 m), so
  the visor band is exactly at their camera and the cone comes out of their face.
- playtest_test checks the new rule: the body stands an eye height below the reported camera, so the visor is at
  the eye point the overlay draws from.

## 0.17.14 preview — 2026-11-09: A block becomes a cube the first time you edit it (U12, batch G)

- **A block drawn in the 2D views is no longer a solid build mode can pick but not change.** The first push, pull
  or paint on it turns it into a cube object (`editor.block_to_cube()`): a plain, solid box that is 1, 2, 4 or 8 m
  on every side and turned in 90 degree steps becomes one full cell of a new `CubeModelNode`, standing on the
  block's own base, with the block's material, name, folder, group and hidden flag, so it keeps its place in the
  Outliner. It is one undo step, and the status bar says it happened.
- Build mode converts the block under the crosshair before its first wheel edit (`build_mode._convert_target_block`,
  fed by `update_target`'s new `target["block"]`), so a push on a block does something instead of nothing.
- Anything without a one-cell cube is refused in plain words rather than quietly rounded: a cutter, a water volume,
  a hollow or shaped block, a box that isn't 1, 2, 4 or 8 m a side, or one turned off the 90 degree steps.
  Retiring `BlockNode` for solids outright (batch G's option 2) is a 0.18 decision.
- editor_test grew seven checks: a 4 m block becomes one 4 m cell that keeps its name and leaves the Outliner's
  block list, build mode converts the block it aims at, a +X face push moves that face in one notch with the cell
  still one solid, water and odd sizes are refused with a reason, and undo brings the block back. Batch G's pass
  (editor_test, build_test, export_test, vmf_test) is clean.

## 0.17.13 preview — 2026-11-09: The co-editor body reads clearly

- U17's body was looked at on screen and tuned: the head is a 0.46 m sphere on a short neck (it used to float above
  the capsule), the visor is a glowing band in the peer's own color inside a dark frame at eye level instead of a
  small white rectangle buried in the skull, and the name above the head is bigger with a black outline, so it reads
  against sky or concrete. `tools/shoot_avatar.gd` renders the body from the front, side, back and close up for the
  next look; the pictures are `tests/out/avatar*.png`.

## 0.17.12 preview — 2026-11-09: You can see the other editors (U17, batch F)

- **Co-editors have a body in build mode.** `editor/_co_avatar.gd` (`CoAvatar`) is a capsule about 1.8 m tall with a
  head and a bright visor across the face. The editor keeps one per peer under `co_avatars_root` in the shared world,
  so the perspective view, the 2D views and build mode see the same body. It stands where their cursor is, turns to
  face where they look (yaw from the aim's X/Z), and its head follows the aim up and down but stops at 40 degrees, so
  the body always shows the compass direction.
- Hidden while the peer works in a 2D view rather than build mode, while `View > Co-editors` is off, and outside a
  session; freed when they leave and when the session ends.
- playtest_test grew six checks (a body where they are, facing the way they look, the 40 degree head clamp, none in
  a 2D view, none with the View item off, and freed when they leave) and passes.

## 0.17.11 preview — 2026-11-09: Folding always comes back (U6, batch E)

- **A folded face can always be pulled back, and a shaped cube still shapes.** `CubeWorld._shape_leaf` moves one
  face a notch at a time; when a step back can't move (the corners would cross, or the shape refuses it) it unfolds
  the picked corners to the cube's own side, so the 8/8 limit is a limit and not a dead end. A cube already folded
  on one axis still folds from another (a 4/8 top pushed in from the side gives one cube at 4/8 on both axes), and a
  cell holding smaller cubes is shaped cube by cube instead of being skipped, so fold → turn → fold no longer loses
  the cube. A push the shape refuses no longer half-applies anything: the cube stays exactly as it was and build
  mode says why ("can't go further here - the cube would fold into itself").
- cube_test grew five checks for those rules (fold 4/8 and pull back to the cube it was, a dented corner pulled
  back, a refused push kept and explained, two-axis folding, a cell of smaller cubes shaped); batch E's pass
  (cube_test, split_accuracy_test, build_test, export_test, vmf_test) is clean.

## 0.17.10 preview — 2026-11-09: Signs sit 1 mm off the wall (U10 done)

- **Text no longer fights the surface it's on** (batch D, U10's decal half). A sign's letters and the brushes they
  export as now sit 1 mm (`TextShape.DECAL_LIFT`) proud of the surface, so a flat sign placed exactly on a wall face
  neither flickers nor exports a degenerate brush - that used to come back from VBSP as "duplicate plane": the same
  test map compiled with 365 brushes and one duplicate-plane brush before, 321 brushes and no brush problem after.
  A prop is left alone: a prop has no surface placement to anchor to (it stands on its position), so a prop pushed
  into a wall stays the mapper's own choice.

## 0.17.9 preview — 2026-11-09: Steady walls, a draw tool that starts where you click

- **Walls between cubes of different sizes stop flickering** (batch D, U10, the cube half). A cube's face against a
  bigger cube's face was drawn twice, in the same place; now the bigger cube's wall is the only one drawn, so a 2 m
  cube next to 1 m cubes has one wall, not two fighting over the same pixels. (Text and prop surfaces sitting exactly
  on a wall still get their own pass: that needs a 1 mm lift and an eye on it.)
- **The draw tool starts on the grid point you aim at** (batch D, U11). A block's position is its center while a drag
  works in corners; that conversion now happens in one place (`editor._draw_box`), including the axis the view looks
  along, so a block drawn from one grid point to another is the size you dragged and sits where you started instead
  of a couple of steps off.

## 0.17.8 preview — 2026-11-09: Picking through air, one mouse sensitivity

- **A pick looks through the air a folded face leaves** (the last item of batch B). Build mode now clips the aiming ray
  against each cube's real shape, not its cell box, and walks every cube object along the line of sight, so the block
  you can see behind a folded cell is the one you select - and a pushed-in cube still counts as a whole block when you
  aim at it. Ctrl keeps the old "this object, at its own size" picking.
- **One mouse sensitivity for build and play** (batch D, U9). Build mode now uses the same Source number as play mode
  (`0.022°` per count) instead of its own scale, and View > Mouse sensitivity has one slider for both; the editor's
  orbit camera keeps its own multiplier.

## 0.17.7 preview — 2026-11-09: The session keeps up

- **A new map resets the session.** File > New, a template or an opened map is handed to every co-editor, who loads
  it whole (their undo history starts fresh), instead of each person quietly building on the map that just went away.
- **Map properties sync as you change them.** Sky, sun, fog, water, lava and glass used to reach the others only on
  the next unrelated change; the Map panel's setters send them now, so the sky changes under everyone at once.
- **Undo takes back only your own last action.** Objects another editor changed after your step keep their work when
  you undo (and redo); your own step still goes back and still goes out to them.

## 0.17.6 preview — 2026-11-09: Faces you can see, a light panel, a wider texture picker

- **Build mode's selection reads like Sauerbraten's**: the selected cube is outlined in blue, the face you selected is
  outlined in white - that face only, following its real pushed / sloped shape - and a face you look at while
  something else is selected gets a thin white outline. The old amber face selector is gone, and the folding (F/Q)
  outline is the same white one, so what you see is what a push will move.
- **Light settings in build mode (F4)**: kind, color, brightness, reach, spot width, strip length, effect and shadows
  as real controls (also from the T menu's Lights tab), one undo step per change and synced like any other edit.
- **A push counter**: a single selected block shows `face push 3/4`, how far that face has been folded in.
- **The F2 texture picker is 780 px wide, five thumbnails a row, and never scrolls sideways.**

## 0.17.5 preview — 2026-11-09: One look for the menus, lights where they belong

- **Lights moved to the entity menu**: the Tab menu now places world pieces only (platforms, zones, teleport,
  booster, text, particles); point, spot and strip lights are on the **T** menu's Lights tab.
- **The T menu is a panel with tabs** (Lights, Platforms & zones, Text & particles, Session): hover a tab to look at
  it, click to keep it. Materials, the texture tools and the selection commands live in Session.
- **One theme for every menu, panel and button** (editor/ui_theme.gd, installed on the window): a visible 1 px
  outline, clear hover and pressed states, section headers and roomier menu rows. The playtest panel, the ramp
  creator, the welcome screen, the outliner and build mode's panels inherit it instead of each hand-rolling colors.
- **The playtest panel has its own toolbar button** (it is gone from the Export menu) and a **−** that collapses it
  to its title row; it remembers being collapsed.

## 0.17.4 preview — 2026-11-09: Seeing each other in build mode

- **Co-editors now show up in build mode (E) too**: their camera, the way they are looking, their mouse and what
  they have selected are drawn over the first-person view in their own color, with their name and what they are
  doing. Build mode has a camera of its own and hides the editor's views, so nothing was drawn there; it also told
  the session it was looking from the hidden editor view, not from where the builder really was.
- A session now also says which view each person is in (perspective, top, front, side, build).

## 0.17.3 preview — 2026-11-09: Objects keep their own names

- **Moving several objects now syncs all of them.** Each MALLET used to invent its own name for every object it
  already had, and a change was matched to the nearest object of the same kind: with ramps close together the same
  ramp could take every change, and the rest never moved. The maker now sends each object's name with the map, so
  both copies agree from the first tick.
- **A change for an object this copy doesn't know is dropped** (with a status line) instead of landing on a
  neighbor, which could also make one object appear to move twice and others not at all.
- **The other person's mouse lands where it really is**: the point under their pointer on the surface they are
  aiming at, instead of the ground plane, so it no longer sits low when they point at a ramp above the floor.

## 0.17.2 preview — 2026-11-09: Joining with a pasted invite

- **"Paste invite" in Export > Playtest session…**: fills in the relay address, the session code and the secret from
  the line the maker's panel copied, so the 32-character secret is never retyped (a typo is refused with "that
  session's secret doesn't match"). Pasting the whole line into the Session code field does the same.
- The refusal now says what to do (copy the invite again, don't retype it) instead of only that it doesn't match.

## 0.17.1 preview — 2026-11-09: The invite, in one line

- **Co-editing's invite is shown and copies as one line.** The playtest panel now displays the relay address, the
  session code and its secret in a read-only field, and "Copy invite" puts all of it on the clipboard. Before, only
  the code could be copied and the secret was never shown anywhere, so nobody could be invited.
- A co-editor (who was given the code and secret) sees the same line without the secret, to confirm which session
  they are in.

## 0.17.0 preview — 2026-11-09: Co-editing

- **Join as a co-editor**: Export > Playtest session… has a "Join as a co-editor" tick. Given a session's code and
  secret (the maker shares both), the second MALLET joins it as an editor rather than as the map's owner, and it
  doesn't file testers' runs into its own copy.
- **See where the others are looking**: a co-editor is a dot in their own color with a line along where they look,
  their name and what they have selected; the object they have selected is outlined in that color in your copy of
  the map. View > Co-editors hides it.
- **Your camera and selection go out the same way**, ten times a second, so it works both ways at once.
- **Edits travel**: drag a ramp point, move a block, change a property in a panel and the other MALLET's copy
  changes too. Four objects a tick at most, so a long drag can't flood the relay. A change from the other side
  never lands in your undo history, and is never sent back out again.
- **New objects and deletions travel too**: anything that appears in the map (a ramp, a block, an entity, a prop,
  a pasted group, a build) shows up on the other side, and deleting something removes it there as well. Neither
  lands in the other side's undo history.
- **Join a session that already has work in it**: the newcomer asks the session's owner for the map it has now
  and gets it in pieces, so both copies match from the first tick instead of the joiner keeping whatever it had
  open. An editor with unsaved changes is asked first ("Load their map" / "Stay with mine"), and taking their map
  is not an undo step.
- **Undo and redo follow**: step back in one MALLET and the other copy steps back with it. Your undo goes out as
  the change it made (that object in its earlier shape), never as an instruction to undo something of theirs, so
  nobody's work disappears from under them.
- **Renames, hidden and folders travel too**: a name typed in the outliner, an eye click, a drop into a folder or
  a new or renamed folder reaches the other side.
- **A dropped connection gets back in**: MALLET retries the session by itself (a second, two, four… up to thirty),
  and rejoins the same one. The map's owner collects the testers' runs filed while it was away; an editor asks for
  the map again, so whatever changed in between arrives with it.
- **You can see each other**: their mouse in every view with their name, and what they are doing (dragging,
  painting, building); in 3D a marker with their name, where they look and the cone they see.
- **Build mode travels too**: cubes you put, paint or shape go to the other copy as you work, and so does the ramp
  the ramp creator is making. While you have something in hand, their edits to it wait until you let go, so two
  people can't drag the same thing back and forth.
- **The map's owner can remove someone**: pick them in the playtest panel and they are put out of the session.
  The code still works, so they can join again if you let them.
- **The map's look travels**: a sky preset, colors, stars or water change reaches the other copy as it changes.
- Not yet: a whole cube object over 200 KB is left for you to copy over by hand.

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

## 0.10.0 preview — 2026-11-06: The name MALLET

- The editor is **MALLET**, Mapping And Level Layout Editor Tool. (Hammer is Source's editor; a mallet is the simpler
  tool anyone can pick up.) The window, welcome screen, menus and messages, the program (`MALLET.exe`) and the tester
  zip carry the name.
- Maps are saved as **`.mallet`**, prefabs as `.malletprefab`.
- CS:S exports put the map's textures in `materials/mallet`.

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
