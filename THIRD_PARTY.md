# Third-party components

## SUCC — SurfsUp Character Controller
- Author: Mark Arneman (creator of SurfsUp) — https://github.com/bearlikelion/SUCC
- License: MIT (full text in `addons/SUCC/LICENSE`)
- Used for: play mode. It is SurfsUp's own movement code (ported from the game), so surfing in MALLET
  matches surfing in SurfsUp. Unmodified; the demo level was not included.

## Material library (materials/)

Textures from ambientCG (https://ambientcg.com), CC0 1.0 Universal (public domain dedication). Thanks to Lennart
Demes and contributors.

## Getridou's and LURKing's textures (materials/getridou_*, materials/lurking_*)

Made by **Getridou** (https://www.instagram.com/getridou/, Discord: Getridou; a few from photos by his friends
arcabal, azzie and cynthia) and by his friend **LURKing** (Discord: TheBlackBigFoot), shipped with their permission,
with credit. His pack's terms: royalty free as long as no profit is made (CC-BY-SA); MALLET is free. Converted from
Sauerbraten's format; details and what was left out in `materials/GETRIDOU.txt`.

## Counter-Strike: Source materials (not included)

MALLET doesn't ship any of Valve's textures. When CS:S is installed, MALLET reads its world materials from that
install (the VPK archives) to show them in the editor; CS:S exports refer to them by name. A SurfsUp export copies
them into the map only if the map maker turns that on; they remain Valve's.

## Inspiration: Cube 2: Sauerbraten

Build mode is modelled on the in-game editor of Cube 2: Sauerbraten (http://sauerbraten.org,
https://github.com/embeddedc/sauerbraten; engine source under the zlib license, by Wouter van Oortmerssen, Lee Salzman
and contributors). MALLET re-implements its editing ideas (cubes with 1/8-step corners, wheel editing, grid power,
key layout) in its own GDScript; no Sauerbraten code or assets are included.
