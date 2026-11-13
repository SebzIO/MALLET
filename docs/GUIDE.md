# The MALLET guide

MALLET (Mapping And Level Layout Editor Tool) makes surf maps for **SurfsUp** and **Counter-Strike: Source**. This
guide takes you from an empty map to one your friends can play, then covers everything else MALLET can do. Every
key is listed at the end.

- [1. Start](#1-start)
- [2. A first map in ten minutes](#2-a-first-map-in-ten-minutes)
- [3. Ramps](#3-ramps)
- [4. Platforms, stages and zones](#4-platforms-stages-and-zones)
- [5. Playing your map](#5-playing-your-map)
- [6. Build mode: building with cubes](#6-build-mode-building-with-cubes)
- [7. How it looks: materials, the material maker, sky, lights](#7-how-it-looks)
- [8. Working with others: testers and co-editing](#8-working-with-others)
- [9. Exporting](#9-exporting)
- [10. Keys](#10-keys)
- [11. Good to know](#11-good-to-know)

---

## 1. Start

Unzip the whole MALLET folder somewhere and keep `MALLET.exe`, `MALLET.pck` and the `materials` folder together.
Double-click `MALLET.exe`. Windows may say "Windows protected your PC" because the program isn't signed: click
**More info**, then **Run anyway**.

The **welcome screen** offers ready-made maps. Each one is a complete map you can play straight away (P):

| Template | What it shows you |
| --- | --- |
| Blank | Just a start and a finish. |
| First Surf | Five ramps in a big U: a classic surf to take apart. |
| Three Stages | Stages joined by teleports; falling off sends you back to your stage. |
| Aurora Night | Glowing ramps at night and a booster across a big gap. |

**The window.** The middle is four views: **Top**, **Front**, **Side** (flat, 2D) and **3D**. Space makes the view
under the mouse fill the window (Space again: back to four). On the left, the **Outliner** lists everything in the
map, in folders if you like. On the right, the **panel** shows the settings of whatever is selected, or the map's
own settings (sky, sun, fog) when nothing is.

**Moving around.**

| | 2D views | 3D view |
| --- | --- | --- |
| Look around | | right mouse drag (orbit) |
| Fly | | hold right mouse + W A S D, Q / E down / up, Shift faster |
| Pan | middle mouse drag | middle mouse drag |
| Zoom | mouse wheel | mouse wheel |
| Frame the selection | F | F |

**Selecting and moving.** Click an object to select it (Ctrl+click adds or removes one; drag on empty space in a
2D view to box-select); drag it to move it (Shift while dragging: up and down). Arrow keys and
Page Up / Page Down nudge the selection by the grid step. **Snap to grid** (top bar) makes points land on the grid.
Ctrl+Z / Ctrl+Y undo and redo; Ctrl+S saves (`.mallet` files).

## 2. A first map in ten minutes

1. Pick **Blank** on the welcome screen. You get a start platform (green) and a finish (blue).
2. Press **N** for a ramp. It appears in front of the camera. Drag its round points in the Top view to aim it, and
   in the Front or Side view to drop it downhill.
3. Watch the **jump arc** (the dotted line off the end of the ramp): it is where a player at your map's speed would
   fly. Move the next ramp, or the finish, under it.
4. Press **N** again for the next ramp, or select a ramp and use **Edit > Extend ramp** to carry it on.
5. Press **P** to play from the start. Surf it. **Esc** brings you back.
6. **Ctrl+S** to save, then **Export > To SurfsUp…** and type a name. In SurfsUp, open the console (~) and type
   `map <name>`.

## 3. Ramps

Select a ramp to see its settings in the panel.

- **Shape**: a V ramp (surf either side) or a half ramp (one side only); **angle** and **face length** for how steep
  and how wide; **Solid** gives it a flat bottom, **Hollow** leaves it open underneath.
- **Path**: *Straight, rounded at the points* (new ramps: straight runs with a round corner at each point) or
  *Smooth curve through the points* (older maps).
- **Points**: drag them. Click a point and press **L** to lock it so its section keeps its own settings.
  **Edit > Add bend to ramp** adds a point in the middle.
- **Pitch, yaw and roll** turn the whole ramp; roll banks it.
- **Look**: a color, a built-in look (ceramic, grid, neon...), an image of yours, a **material** from the library,
  or your own shader. The texture settings turn, shift, scroll it or make it see-through.

**Generate a ramp shape (R)** builds whole runs (curves, spirals, zig-zags) from a few numbers.

**The ramp creator** (Add menu, or the button in a ramp's panel) shapes a ramp's cross-section: drag points on its
faces, give it a flat top, and shape each end (tapered, rounded, flared, cut diagonally, a lip that launches riders
up, or closed). Orange marks parts too flat to surf. Save designs as **ramp prefabs** (`.malletramp` files) to reuse
and share; eleven come with MALLET.

## 4. Platforms, stages and zones

All in the **Add** menu (or their key).

| Thing | Key | What it does |
| --- | --- | --- |
| Start platform | B | Where runs begin. Players can't leave it faster than 400 u/s. |
| Finish platform | M | Landing in it finishes the run. |
| Stage plate | T | A checkpoint: reaching it makes it the player's respawn and records a split. Give each a number. |
| Teleport | Y | Sends players to a stage plate, or to a **teleport destination**, with the same number. |
| Teleport destination | | Where a teleport set to "A destination" sends players: they keep their speed and look along the arrow, but no stage is reached. |
| Kill zone | K | Touching it sends the player back to their respawn. |
| Booster | J | Pushes players along its arrow: adds to their speed, or sets it. |

Built your own start or finish out of ramps or cubes? **Start / Finish / Stage zone (on your own platform)** adds just
the zone box. Zones can be stretched by the small squares on their sides.

## 5. Playing your map

- **P** plays from the start. In build mode, **Ctrl+P** plays from where you are.
- **R** restarts, **Backspace** goes back to your last stage, **Esc** returns to the editor.
- Your best run is kept with the map as a **ghost**; View > Best run path draws it.

**Practice tools** (they make the run *practice*: the timer says PRACTICE and the finish doesn't count):

| Key | |
| --- | --- |
| hold left / right mouse | turn left / right at a steady speed (turn binds; speed in View > Mouse sensitivity) |
| Q / E | save your position (with speed and view) / go back to it |
| 2-9 | go to that stage (1 restarts, like R) |
| N | noclip: fly through everything (W A S D, Space up, Ctrl down, Shift faster) |
| T | show or hide the zones, teleports, boosters and kill zones |

## 6. Build mode: building with cubes

Press **E** (or **Build** in the top bar). You fly in first person and build with cubes, the way Cube 2:
Sauerbraten's editor works. **F1** shows every key on screen. Each build is a **cube object**: back in the editor
you can move, turn and copy it like anything else (**N** in build mode starts a new one).

The basics:

- Aim at a face and roll the **mouse wheel**: cubes come out of it (or go back in).
- **G + wheel** changes the grid (the cube size). **F + wheel** pushes a face in 1/8 at a time; **Q + wheel** one
  corner. Middle drag selects corners to shape.
- **Left drag** selects faces; **right click** extends the selection; **right drag** moves the selection box
  (with Shift: leaves a copy). **C / V** copy and paste, **Delete** deletes, **Z / I** undo and redo.
- **Y + wheel** changes texture, **Y** picks up the one you aim at, **F2** opens the texture menu, **F3** the texture
  settings (scale, turn, shift, fit to the selection, presets).
- **H** (or hold Alt) is the heightmap: shape hills with the wheel; **B + wheel** sets the brush. **Shift+H** is an
  experimental heightmap that adds random shapes.
- **T** opens the menu for materials (water, lava, glass, clip, death...), fills, replace, and placing kill zones.
- **Tab** places lights, platforms and zones; **1-4 + wheel** changes their settings. **F4** is the light panel.
- **F6** is the geometry menu: spheres, cylinders, cones, ramps, stairs, quarter pipes, halfpipes and more, sized
  and turned with sliders, saved as presets.

## 7. How it looks

**Materials.** A ramp's or block's Look can be a **material**: hundreds of real textures (concrete, metal, wood,
glowing signs...) in the material picker, with a search box. In build mode the texture menu is the same library.
If Counter-Strike: Source is installed, its textures appear too. **+ Your own image…** adds any PNG / JPG / WebP.

**The material maker** makes your own materials or changes existing ones. In the material picker click
**Make / edit a material…**, or right-click any material to start from it.

- Start from a material (or a plain color), then stack **layers**: color changes (hue, saturation, brightness,
  contrast), fills, stripes and lines, rectangles, ellipses, text, images and painting.
- Every layer has a color, opacity and blend (mix, add, multiply, subtract). Move, hide, copy or delete layers any
  time; nothing is final until you save, and even then you can open it again. **Adjust colors** also has **gamma**
  (below 1 lighter, above 1 darker; type any number).
- **Finish** (the ball next to it shows it in 3D): **Brightness x** (how much light it gives back; type 10 or 100 for
  more), **Light of its own** (it shines even in the dark; no upper limit), **Glossiness** (1 = mirror-smooth) and
  **Reflectiveness** (1 = a perfect mirror, like polished chrome). Turn on **Reflections of the map** in the Map panel
  and shiny materials reflect the map itself, not only the sky.
- **Paint**: add a Paint layer, then drag on the picture. Shift+drag paints a straight line, Ctrl+Z undoes a stroke.
- **A line along a ramp's ridge**: click **+ Ridge line**. It turns on **Fit across a ramp**: on ramps the picture
  spans the riding surface once from edge to edge, so the middle is the ridge (the **Ramp guide** shows it). Lines at
  the very left and right run along the ramp's edges.
- Saved materials appear under **Made by you**. **Save** changes it everywhere it's used; **Save as new** keeps both.
- Your materials (and images you added) travel inside the maps that use them, so a map opens the same on a friend's
  PC.

**Moving textures**: a ramp's texture settings (and F3 in build mode) can **scroll** across and along, **spin**
(degrees a second) and **swirl** (twist the middle into a spiral). Each repeat turns around its own middle: use
**Fit to selection** in F3, or a material that fits across a ramp, to turn a whole face as one. Every number box takes
any value you type.

**The map's look** (the panel with nothing selected): the sky (MALLET's own, or your sky shader), sun, fog, Reflections
of the map, and the usual look of build mode's water, lava and glass. Any fill can have its own look instead: in build
mode's **T** menu, Fill tab, pick the look under "Their look" before you fill, so every pool can be different.

**Lights** (U, or Tab in build mode): point lights, spot lights and light strips (neon, tubes), with presets
(torch, campfire, alarm, party...), effects (flicker, pulse, strobe) and color cycles. **Particles**: fire, smoke,
sparks, snow, rain, mist and more. **Text** (X) puts signs on surfaces. **Props** (I) are glTF models.
**Water** (H) is a water block with presets.

**Your own shaders**: View > Your shaders folder… Put Godot `.gdshader` files there: sky shaders show up under the
map's Sky, surface shaders in a Look ("Your own shader"). See `docs/SHADERS.md`.

## 8. Working with others

**Test builds.** Export > Test build for testers… makes a zip you can send to anyone: a test program with no editor
that drops them on your map and records every attempt (time, splits, falls, route) in a "tester runs" folder. Get that
folder back and use Export > Import tester runs…; View > Testers' paths draws their routes.

**Live playtesting.** Export > Playtest session… (leave the code empty) opens a session. Test builds made while it is
open report live: the **Playtest panel** shows who is on, where they are, their attempts and times, and the 3D view
shows each tester as a dot with a trail.

**Co-editing.** Start a session the same way, then **Copy invite** on the Playtest panel and send it. The other
person opens Export > Playtest session…, ticks **Join as a co-editor** and clicks **Paste invite**. From then on both
copies of the map change together: every edit, build mode cubes, materials, the map's sky. You see each other's
camera, mouse and selection. Undo only takes back your own work. The map's owner can remove someone.

## 9. Exporting

- **Export > To SurfsUp…** puts the map into SurfsUp's Maps folder (SurfsUp must be installed). Everything goes in:
  ramps, cubes, materials (yours too), lights, zones, teleports.
- **Export > To Counter-Strike: Source…** writes a `.vmf` and can compile it into a playable `.bsp` (CS:S must be
  installed). Quick compile is for testing, Final compile for the real thing. The map's own sky can become the
  skybox. Note: CS:S teleports stop the player; MALLET warns you where that matters.

Both exports check the map first and tell you about anything missing (no finish, a teleport with nowhere to go...).

## 10. Keys

**Editor**

| Key | | Key | |
| --- | --- | --- | --- |
| N | ramp | Ctrl+Z / Ctrl+Y | undo / redo |
| R | generate a ramp shape | Ctrl+S / Ctrl+O | save / open |
| O / Shift+O | block / draw blocks | Ctrl+C / Ctrl+V / Ctrl+D | copy / paste / duplicate |
| B / M / T | start / finish / stage | Delete | delete |
| Y / K / J | teleport / kill zone / booster | Ctrl+A | select all |
| U / H / I / X | light / water / prop / text | Ctrl+G / Ctrl+Shift+G | group / ungroup |
| L | lock the selected ramp point | [ / ] | turn 15 degrees |
| P | play | arrows, Page Up / Down | nudge |
| E | build mode | F / Space / F11 | frame / one view / fullscreen |

**Build mode**: F1 shows them all on screen. The main ones are in section 6.

**Play mode**: R restart, Backspace last stage, Esc editor, hold left / right mouse to turn, Q / E save / load
position, 2-9 stages, N noclip, T triggers.

## 11. Good to know

- Mouse sensitivity uses Source's numbers, so your CS:S sensitivity feels the same (View > Mouse sensitivity).
- With nothing selected, the panel tells you how heavy the map is (lights, particles, cubes).
- Maps are plain `.mallet` files: back them up like any document. Older SurfForge `.sfmap` maps still open.
- Something broke or felt wrong? Tell whoever sent you MALLET: what you did, what you expected, what happened.
