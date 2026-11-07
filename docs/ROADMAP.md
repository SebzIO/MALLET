# MALLET roadmap to 1.0.0

**MALLET** (Mapping And Level Layout Editor Tool), formerly SurfForge. A mallet is the simple tool anyone can pick up,
next to Source's Hammer: that is the whole idea of this editor.

1.0.0 is reached only when **every** milestone below is done **and the user says so**. Each milestone ships as its
own preview (0.10.0, 0.11.0, …) with a tester zip; fixes in between are 0.x.y. Never 1.0.0 by default.

Where we are: **0.11.0** (2026-11-07): new materials, CS:S textures, glow. Build mode, cube objects, custom zones, SurfsUp + CS:S export all work and
have been tested by the user and a friend.

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

## 0.13.0: Your own skies and shaders
- [ ] A **user shaders folder** (opened from the menu): drop in a Godot `.gdshader` (sky, or surface material) and
      it shows up in MALLET. Its `uniform`s automatically become sliders / color pickers in the panel, so a shader
      writer also makes something non-coders can tweak.
- [ ] Ship a commented **template** for a sky shader and a surface shader, and a short guide (docs/SHADERS.md).
- [ ] Custom **sun / ambient / fog** controls stay alongside a custom sky.
- [ ] Safety: a shader that doesn't compile shows its error and falls back (no white faces, no crash).
- [ ] Export: SurfsUp embeds the shader with the map (as today's built-in looks). CS:S can't run shaders: MALLET
      bakes the custom sky into a 6-sided **skybox** (cubemap → VTF) so CS:S still gets the look; custom surface
      shaders export as their base texture.

## 0.14.0: Ramp creator
- [ ] A dedicated **ramp creator** window: design a ramp's cross-section (any surfable profile, not just the V /
      half ramp) and its **ends**: taper the start / end at an angle, round them, cut them diagonally, flare them,
      add lips or a closed back.
- [ ] Save designs as **ramp prefabs** (a library like the prefab one, with thumbnails; shareable as files).
- [ ] A ramp made from a prefab is still an ordinary ramp: drag its points, stretch, bend, lock sections, change
      width / angle, and the custom profile and ends follow along instead of being lost.
- [ ] The jump checker, fold warnings, solid / hollow, materials and both exports work with custom ramps.
- [ ] Ship a handful of starter ramp prefabs (tapered entry, diagonal cut end, booster lip…).

## 0.15.0: Playtest builds (offline)
Plan in detail: [PLAYTEST.md](PLAYTEST.md), parts 1–2.
- [ ] **Export > Test build**: a small tester program (play mode only) with the map inside, zipped for sharing.
- [ ] Username + clear consent on first launch; map version stamped into every build.
- [ ] Every attempt recorded (route, speed, deaths, splits, finish time / speed, restarts) to a file next to it.
- [ ] **File > Import tester runs** in MALLET.

## 0.16.0: Live playtesting
[PLAYTEST.md](PLAYTEST.md), parts 3–4.
- [ ] Relay server on the user's VPS (Debian 12 + Docker, domain sebz.xyz, TLS through Nginx Proxy Manager: the
      relay runs as a Docker container behind it, e.g. a subdomain): testers and the map maker both connect
      out to it; session codes; per-session secret; untrusted-input checks; runs kept until collected.
- [ ] **Playtest panel**: who's on, live ghosts with names, every route drawn by speed, death / fall markers,
      per-stage times, where people quit; saved with the map.
- [ ] Load test with many testers at once.

## 0.17.0 → 1.0.0: Release candidate
- [ ] Welcome screen, templates and tutorial updated for everything above; docs written for map makers.
- [ ] Full regression clean (fix or explain the three tests that crash on exit), every export checked in SurfsUp
      and CS:S by the user.
- [ ] Testers use a release candidate (0.17.x) with no new features, only fixes.
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
