# Known issues

Things we know about and haven't fixed yet. If you hit something that isn't here, please open an issue on GitHub
with what you did, what you expected and what happened (a screenshot and the `.mallet` file help a lot).

## Counter-Strike: Source export

- **Ramp textures run at an angle in CS:S.** In MALLET and in SurfsUp a ramp's texture follows the ramp, but the
  CS:S export projects textures the way Hammer does by default (lined up with the map's X / Y / Z axes). On a ramp
  that doesn't run along an axis, bricks, planks and stripes go diagonally across it instead of along it. Materials
  marked "fit across a ramp" (in the material maker) are the exception: they follow the ramp in CS:S too.
- **Only the Material look reaches CS:S on ramps.** Color, Ceramic, Steel, Grid, Aurora, Nebula and Neon need
  MALLET's own shaders, which Source can't run, so those ramps come out in Source's gray developer texture. The
  export window says how many ramps that affects.
- **Big, curvy maps can run out of brush planes.** Source allows 65,536 planes per map; every curved ramp piece and
  its collision copy use some. A very long or very curvy map may fail to compile ("MAX_MAP_PLANES" in the compile
  log). Straight stretches cost little; tight bends cost the most.
- **The seam steps on curves.** To keep Source's "ramp bug" from stopping you on a bend, the invisible surface you ride
  drops by a few units at each seam on the inside of a bend (you can't see it, and you don't feel it at speed).
  Riding a bend backwards, against the ramp's direction, can still catch on these steps.
- **Props aren't exported** (Source needs compiled `.mdl` models), and CS:S teleports stop the player instead of keeping
  their speed.

## Videos (Render video)

- **MP4 needs your own ffmpeg** (on your PATH or next to `MALLET.exe`); without it the choices are AVI and PNG
  pictures.
