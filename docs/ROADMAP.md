# MALLET roadmap to 1.0.0

**MALLET** (Mapping And Level Layout Editor Tool), formerly SurfForge. A mallet is the simple tool anyone can pick up,
next to Source's Hammer: that is the whole idea of this editor.

1.0.0 is reached only when **every** milestone below is done **and the user says so**. Each milestone ships as its
own preview (0.10.0, 0.11.0, …) with a tester zip; fixes in between are 0.x.y. Never 1.0.0 by default.

Where we are: **0.18.5** (2026-11-11): build mode's Geometry menu draws nine shapes out of octree cells, every
surface is one cut plane and the preview is built off the main thread; 0.18.0-0.18.5 are published and 0.18.5 is
installed in the live build folder. Under it sit every batch of the 0.17.4 testing list (A-F), co-editing, build
mode's cubes and folding, the ramp creator, lights and particles. Build mode, cube objects, custom zones, SurfsUp +
CS:S export all work and have been tested by the user and a friend.

---

## 0.10.0: SurfForge becomes MALLET ✅ (released 2026-11-06)
Do this first, so every later feature, file and screenshot already carries the new name.
- [x] Rename everywhere the user sees it: window title, welcome screen, About text, version string
      ("MALLET 0.10.0 preview"), menus, status messages, help text, READ ME FIRST, THIRD_PARTY, CHANGELOG heading.
- [x] Program files: `MALLET.exe` / `MALLET.pck`, zip `MALLET-0.10.0-windows.zip`, Godot project name.
- [x] Map files: new extension **`.mallet`**. Open / Save use it; **old `.mallet` maps still open**
      (and are saved as `.mallet`). Templates and prefabs renamed too.
- [x] Your own data moves with you: Godot keeps settings, your own materials and prefabs under the project name, so
      on first start MALLET copies them over from the old SurfForge folder (mouse settings, fly speed, prefabs, own
      materials, export folders).
- [x] Exports: the `made_with` stamp in SurfsUp maps, CS:S file comments, tester build names.
- [x] Code / tests / docs: class names (`MalletVersion` …), launcher `.cmd` files, memory notes, handover.
      (The local folders `D:\SurfForge` and `D:\SurfForge_builds` keep their names: development only.)

## 0.11.0: Materials (0.11.0 released 2026-11-07; the unticked items follow in 0.11.x)
- [x] **Getridou's materials pack** (170 materials incl. his friends' photo textures + 18 by LURKing, glow maps, credit in the picker / THIRD_PARTY / README /
      materials/GETRIDOU.txt).
- [x] **Sauerbraten's materials**: 315 from the ten packs whose licenses allow it (tools/import_sauerbraten.py,
      materials/SAUERBRATEN.txt lists every pack in or out and why; license files ship with them).
- [x] **CS:S materials** from the user's own install (core/css_library.gd reads VPK / VMT / VTF): 2,851 world
      materials in the picker, CS:S exports use them by name, SurfsUp exports copy them in only with the export
      window's switch on (the user's decision 2026-11-06), else a similar MALLET material stands in.
- [x] **Better liquids and glass**: core/shaders water (waves, depth, foam, refraction), lava, glass; presets in
      Look.LIQUIDS / Look.GLASS; block Liquid menu, Map panel looks for build mode; CS:S water per preset.
- [x] Texture browser: categories / search / credits (F2 in build mode is the same picker, search focused on open).

## 0.12.0: Worldbuilding (lights and particles)
- [x] More light types: strip lights (a glowing tube, standing in for area / rectangle lights), flicker / candle /
      pulse / strobe / fluorescent effects, light presets (torch, neon strip, lamp and more), placeable from build mode.
- [x] Particles: an emitter object with presets (fire, smoke, sparks, embers, snow, rain, dust, waterfall mist, magic)
      and simple settings (amount, size, color, speed, area). Visible live in the editor and play mode.
- [x] Export: SurfsUp gets real Godot particles; CS:S gets the nearest stock effect (env_fire, env_smokestack,
      env_spark, env_steam, func_precipitation) or a note that it can't be shown there.
- [x] Check the cost: a map's particle count / lights shown in the info panel, with a warning when it gets heavy.

## 0.13.0: Your own skies and shaders ✅ (2026-11-07)
- [x] A **user shaders folder** (opened from the menu): drop in a Godot `.gdshader` (sky, or surface material) and
      it shows up in MALLET. Its `uniform`s automatically become sliders / color pickers in the panel, so a shader
      writer also makes something non-coders can tweak.
- [x] Ship a commented **template** for a sky shader and a surface shader, and a short guide (docs/SHADERS.md).
- [x] Custom **sun / ambient / fog** controls stay alongside a custom sky.
- [x] Safety: a shader that doesn't compile shows its error and falls back (no white faces, no crash).
- [x] Export: SurfsUp embeds the shader with the map (as today's built-in looks). CS:S can't run shaders: MALLET
      bakes the custom sky into a 6-sided **skybox** (cubemap → VTF) so CS:S still gets the look; custom surface
      shaders export as their base texture.

## 0.14.0: Ramp creator ✅ (2026-11-07)
- [x] A dedicated **ramp creator** window: design a ramp's cross-section (any surfable profile, not just the V /
      half ramp) and its **ends**: taper the start / end at an angle, round them, cut them diagonally, flare them,
      add lips or a closed back.
- [x] Save designs as **ramp prefabs** (a library like the prefab one, with thumbnails; shareable as files).
- [x] A ramp made from a prefab is still an ordinary ramp: drag its points, stretch, bend, lock sections, change
      width / angle, and the custom profile and ends follow along instead of being lost.
- [x] The jump checker, fold warnings, solid / hollow, materials and both exports work with custom ramps.
- [x] Ship a handful of starter ramp prefabs (tapered entry, diagonal cut end, booster lip…).

## 0.15.0: Playtest builds (offline)
Plan in detail: [PLAYTEST.md](PLAYTEST.md), parts 1–2.
- [x] **Export > Test build**: a small tester program (play mode only) with the map inside, zipped for sharing.
- [x] Username + clear consent on first launch; map version stamped into every build.
- [x] Every attempt recorded (route, speed, deaths, splits, finish time / speed, restarts) to a file next to it.
- [x] **Import tester runs** in MALLET (in the Export menu).

## 0.16.0: Live playtesting
[PLAYTEST.md](PLAYTEST.md), parts 3–4.
- [x] Relay server on the user's VPS (Debian 12 + Docker, domain sebz.xyz, TLS through Nginx Proxy Manager: the
      relay runs as a Docker container behind it, e.g. a subdomain): testers and the map maker both connect
      out to it; session codes; per-session secret; untrusted-input checks; runs kept until collected. (Live at
      wss://relay.sebz.xyz/ws since 0.16; a rebuild for kick / map_version is still open.)
- [x] **Playtest panel**: who's on, live ghosts with names, every route drawn by speed, death / fall markers,
      per-stage times, where people quit; saved with the map. (Stage reach, best splits and where unfinished runs
      end were added to the summary in 0.22.0.)
- [ ] Load test with many testers at once.

## 0.17.0: Live co-editing (added 2026-11-08, required for 1.0)
Work on one map together, live. Uses the same relay on the user's VPS as live playtesting (0.16).
- [x] **Invite**: the map owner makes a unique invite code and sends it to someone; they enter it in MALLET to join
      the map being worked on (the owner can see who's in, and remove someone).
- [x] **Every action syncs**, both ways, in real time: adding, moving, reshaping, deleting, materials, the ramp creator,
      build mode cubes, the Map panel, undo / redo of your own actions. Nobody's work is lost when two people touch
      the same thing (a clear rule for conflicts, e.g. the object you're dragging is yours until you let go).
- [x] **See each other in 3D**: the other person's camera as a name tag and a marker showing where they look
      (their field of view), in every view and in build mode.
- [x] **See each other in the 2D views / window**: their mouse cursor with their name, and what they're doing
      (dragging a ramp, painting, building...), plus their selection outlined in their color.
- [x] Joining mid-session gets the whole current map; a dropped connection rejoins without losing anything; the
      owner's saved file stays the one true copy.
- [ ] The goal: working together feels seamless, as if both people were at the same computer.

## 0.20.0: Practice tools (added 2026-11-12)
- [x] Turn binds (hold left / right mouse, cl_yawspeed 210 by default), Q / E save / load position, 1-9 restart / go to
      a stage, N noclip, T show the triggers; practice runs don't count (0.20.0).

## 0.21.0: Material maker (added 2026-11-12)
Make your own textures and materials, or change existing ones, inside MALLET.
- [x] Start from any library texture (or a plain color), stack layers on it: color / brightness / hue changes,
      stripes and lines, shapes, text, images, and a freehand paint layer. Every layer stays editable (0.21.0).
- [x] "Fit across a ramp": the texture spans the riding surface once, so a stripe in the middle is a line on the
      ridge; SurfsUp and CS:S exports line it up too (0.21.0).
- [x] Saved to your own materials library ("Made by you") and copied into each map that uses it (opens the same on
      another PC, reaches co-editors); works on ramps, cubes and blocks, and in both exports (0.21.0).

## 0.23.0: Finish, spin, a look per pool (added 2026-11-12)
- [x] Material finish: brightness and own light without a cap, gloss and reflections up to a mirror; gamma in the
      adjust layer; the map's screen-space reflections; CS:S cubemap reflections (0.23.0).
- [x] Spin and swirl texture motion on ramps and cube faces (CS:S: spin) (0.23.0).
- [x] Water / lava / glass looks per fill ("water:pool" cells), the map's look as the default (0.23.0).

## 0.18.0 → 1.0.0: Release candidate
- [x] **Geometry menu** (0.18.0) and its fixes (0.18.1-0.18.5): nine shapes cut from octree cells, one flat cut face
      per cell, whole cones and cylinders, sliders that keep up, a typed value that sticks, and a preview built on a
      worker thread.
- [ ] **Cubes become ramps** (next feature, not started): a **Make ramp from cubes** command that reads a selected cube
      object's one slope plane back into a ramp - spine points along the slope, width to `style` half, `angle`,
      `face_length`, `solid` + `base_depth`, `detail` - carries the riding surface's material into the ramp's look, and
      is one undo step. A top that is not one plane (a hand-pushed staircase) is refused in plain words, with the
      cubes kept. About a day; the block-to-cube path from 0.17.14 is the precedent.
- [ ] **A ramp material per surface** (top / left / right / ends), so a converted ramp keeps its slope and side
      textures instead of one look for everything. About a day. A third narrow trim material cannot survive: a ramp
      has one material per surface group. Ramps already map u across the face and v in meters along, so nothing
      stretches when one is bent or lengthened.
- [ ] **A prefab that keeps its look**: store `look` in `.malletramp` files (they hold shape only today), then
      optionally a "full ramp" prefab that also stores the path, so a favorite ramp comes back exactly as made.
- [ ] 0.18.x fixes from testing 0.17.4: [ISSUES.md](ISSUES.md) holds the 17 items in seven batches. A (menus,
      buttons, the playtest panel) shipped in 0.17.5;      B shipped in 0.17.6-0.17.8 (U7, picking through a folded face, in 0.17.8). C shipped in 0.17.7 (a new map resets
      the session, map properties sync as they change, undo keeps other people's later work).      D: U9 (one Source
      sensitivity) in 0.17.8, U10's cube half (a small cube's face against a bigger cube's wall) and U11 (the draw
      tool's grid offset) in 0.17.9, U10's decal half (text 1 mm off the surface, brushes too) in 0.17.10 - batch D
      done; E folding (U6, fold back and fold across axes) in 0.17.11 - batch E done. F co-editor avatars in 0.17.12 - batch F done. Next: G, one kind of
      solid (needs the user's decision).
- [x] Welcome screen, templates and tutorial updated for everything above; docs written for map makers (0.22.0:
      docs/GUIDE.md -> GUIDE.html, Help menu, a fifth template "Cube Park", a short READ ME FIRST in dist/).
- [ ] Full regression clean (done in 0.22.0: the three exit crashes were TextNode's uncollected worker tasks, fixed;
      every test passes and exits cleanly), every export checked in SurfsUp
      and CS:S by the user.
- [ ] Testers use a release candidate (0.18.x) with no new features, only fixes.
- [ ] The user declares **1.0.0**.

---

## Decisions (2026-11-06)
- Map files: **`.mallet`**.
- Local folders `D:\SurfForge` / `D:\SurfForge_builds` stay as they are (development only).
- Getridou: credited in the GitHub README (plus the in-app credits above).
- VPS: Debian 12, Docker, domain sebz.xyz with TLS via Nginx Proxy Manager.
- **No code signing**, ever: MALLET and its test builds stay unsigned. READ ME FIRST and the website / GitHub explain
  the Windows SmartScreen warning ("More info" > "Run anyway") so users know what to expect.

## Not planned for now
- F / Q + wheel subtractive editing, stage split times between ticks (declined 2026-11-06).
- C++ (GDExtension) cube core: only if build mode speed becomes a problem again.
- Merging cubes into fewer CS:S brushes.
