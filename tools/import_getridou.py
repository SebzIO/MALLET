"""Import Getridou's texture pack (Tesseract .tex materials; Tesseract is the Sauerbraten fork he made them for) into
MALLET's material library.

Getridou confirmed (2026-11-06): every texture in the folder is original work. The arcabal_ / azzie_ / cynthia_ ones
are his, made from photos those friends sent him, and the unprefixed ones are his too. The lurking_ ones are by his
friend LURKing, who is fine with them being used with credit: they get their own "LURKing" category and credit.
See materials/GETRIDOU.txt.

    python tools/import_getridou.py <getridou folder> [materials folder]

For each material (its .tex file says which images it uses):
  diffuse  -> color.jpg            (largest side capped at 1024 px, like the rest of the library)
  normal   -> normal.jpg
  specular -> roughness.jpg        (roughness = 1 - 0.75 x specular x specscale; no specular = matte)
  glow     -> glow.jpg             (only when the .tex shader glows and its glowcolor isn't black; a grey glow
                                    mask takes the colour texture's colours, so a green lamp glows green)
  preview.jpg (128 px) for the texture browser
Size (metres one repeat covers) follows Tesseract exactly: TEX_SCALE 16 (Sauerbraten's was 8), one Tesseract /
Sauerbraten unit = one MALLET tick (0.125 m), so size = width_px x texscale / 128 (a 1024 px texture repeats every
8 m). (Getridou, 2026-11-06: the .tex files are Tesseract's; Sauerbraten itself used one .cfg per map.)
Height (displacement), ambient occlusion and environment-map settings aren't used (MALLET has no parallax yet).
"""
import json
import os
import re
import sys

from PIL import Image

MAX = 1024
EXCLUDE = ()                    # nothing left out (LURKing cleared 2026-11-06)
ARTISTS = {"lurking": "LURKing"}   # name prefix -> its own artist (category + credit); everything else is Getridou's
FRIENDS = {"arcabal": "arcabal", "azzie": "azzie", "cynthia": "cynthia"}   # friends whose photos Getridou made into textures
SURFACES = [  # (words in the name, CS:S $surfaceprop) - first match wins
    (("glass", "window"), "glass"),
    (("steel", "metal", "iron", "chrome", "plate", "grate", "pipe", "rust", "shutter", "transmission", "copper"), "metal"),
    (("wood", "bark", "plank", "crate", "timber"), "wood"),
    (("grass", "fauna", "moss", "hedge", "leaf", "leaves", "foliage"), "grass"),
    (("dirt", "mud", "soil", "sand"), "dirt"),
    (("gravel", "pebble"), "gravel"),
    (("tile", "ceramic", "hex"), "tile"),
    (("brick",), "brick"),
    (("carpet", "fabric", "knit", "cloth", "rug"), "carpet"),
    (("plaster", "stucco"), "plaster"),
    (("plastic", "rubber"), "plastic"),
    (("rock", "stone", "marble", "granite", "pearlite", "cliff"), "rock"),
]


def parse_tex(path):
    maps, shader, texscale, glowcolor, specscale = {}, "", 1.0, None, 1.0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        m = re.match(r'texture\s+(\S+)\s+"([^"]+)"', line)
        if m:
            maps.setdefault(m.group(1), os.path.basename(m.group(2)))
            continue
        m = re.match(r'setshader\s+"([^"]+)"', line) or re.search(r'setshader\s+"([^"]+)"', line)
        if m:
            shader = m.group(1)
        m = re.match(r'texscale\s+([\d.]+)', line)
        if m:
            texscale = float(m.group(1))
        m = re.search(r'"glowcolor"\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', line)
        if m:
            glowcolor = tuple(float(x) for x in m.groups())
        m = re.search(r'"specscale"\s+([\d.]+)', line)
        if m:
            specscale = float(m.group(1))
    return {"maps": maps, "shader": shader, "texscale": texscale, "glowcolor": glowcolor, "specscale": specscale}


def capped(img):
    w, h = img.size
    if max(w, h) > MAX:
        k = MAX / max(w, h)
        img = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    return img


def grey(img):
    """Is a glow map a plain grey mask (no colour of its own)?"""
    small = img.resize((64, 64))
    return max(max(r, g, b) - min(r, g, b) for r, g, b in small.getdata()) < 24


def artist_of(name):
    return next((a for p, a in ARTISTS.items() if name.lower().startswith(p)), "Getridou")


def mat_id(name):
    """MALLET's id: getridou_<name> or lurking_<name> (Getridou's friends' photo textures and unnamed ones get getridou_)."""
    n = name.lower().replace("-", "_")
    return n if n.startswith(("getridou_", "lurking_")) else "getridou_" + n


def nice_name(source):
    s = source.lower().replace("-", "_")
    for p in ["getridou_", "lurking_"] + [f + "_" for f in FRIENDS]:
        if s.startswith(p):
            s = s[len(p):]
    s = s.replace("_", " ")
    s = re.sub(r"(\D)0*(\d+)$", r"\1 \2", s)
    return s[:1].upper() + s[1:]


def surface_of(name):
    low = name.lower()
    for words, surf in SURFACES:
        if any(w in low for w in words):
            return surf
    return "concrete"


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
    out_root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "materials")
    files = set(os.listdir(src))
    found = {}
    for f in sorted(files):                              # every .tex (Getridou's, and his friends' photos)
        if f.endswith(".tex") and not (EXCLUDE and f.lower().startswith(EXCLUDE)):
            found[f[:-4]] = parse_tex(os.path.join(src, f))
    used = {v for t in found.values() for v in t["maps"].values()}
    for f in sorted(files):                              # image sets with no .tex: default settings
        m = re.match(r"(.+?)([-_])diffuse\.png$", f)
        if not m or f in used or (EXCLUDE and m.group(1).lower().startswith(EXCLUDE)) or m.group(1) in found:
            continue
        base, sep = m.group(1), m.group(2)
        maps = {"0": f}
        for key, kind in (("n", "normal"), ("s", "specular"), ("g", "glow")):
            if f"{base}{sep}{kind}.png" in files:
                maps[key] = f"{base}{sep}{kind}.png"
        found[base] = {"maps": maps, "shader": "bumpspecmapworld", "texscale": 1.0, "glowcolor": None, "specscale": 1.0,
                       "orphan": True}
    # older copies of the same picture (no .tex, or no getridou_ name): dropped when they match one of his named ones.
    # His named materials (getridou_*.tex) are always kept, even when two look alike.
    def sig(name):
        return Image.open(os.path.join(src, found[name]["maps"]["0"])).convert("RGB").resize((64, 64), Image.BILINEAR).tobytes()

    def same(a, b):
        return sum(abs(x - y) for x, y in zip(a, b)) / len(a) < 2.0

    keepers = {n: sig(n) for n in found if n.lower().startswith(("getridou_", "lurking_")) and not found[n].get("orphan")}
    dupes = []
    for name in sorted(n for n in found if n not in keepers):
        if found[name]["maps"].get("0") not in files:
            continue
        s = sig(name)
        twin = next((k for k, ks in keepers.items() if same(s, ks)), None)
        if twin:
            dupes.append(f"{name} (= {twin})")
            del found[name]
        else:
            keepers[name] = s
    print("duplicates skipped:", dupes)
    ided = {}
    for n in sorted(found, key=lambda n: (found[n].get("orphan", False), n)):   # .tex ones keep the plain id
        mid = mat_id(n)
        k = 2
        while mid in ided:                               # (two different pictures with one name: lurking_srbice)
            mid = "%s_%d" % (mat_id(n), k)
            k += 1
        ided[mid] = found[n] | {"source_name": n}
    found = ided
    entries, skipped = [], []
    names = set()
    for mid, t in sorted(found.items(), key=lambda kv: (kv[1].get("orphan", False), kv[0])):   # (.tex ones name first)
        maps = t["maps"]
        if "0" not in maps or maps["0"] not in files:
            skipped.append(mid)
            continue
        d = os.path.join(out_root, mid)
        os.makedirs(d, exist_ok=True)
        color = capped(Image.open(os.path.join(src, maps["0"])).convert("RGB"))
        color.save(os.path.join(d, "color.jpg"), quality=88, optimize=True)
        prev = color.copy()
        prev.thumbnail((128, 128), Image.LANCZOS)
        prev.save(os.path.join(d, "preview.jpg"), quality=85, optimize=True)
        e_maps = {"color": "color.jpg"}
        if maps.get("n") in files:
            n = capped(Image.open(os.path.join(src, maps["n"])).convert("RGB"))
            n.save(os.path.join(d, "normal.jpg"), quality=90, optimize=True)
            e_maps["normal"] = "normal.jpg"
        if maps.get("s") in files and "spec" in t["shader"] and t["specscale"] > 0:
            s = capped(Image.open(os.path.join(src, maps["s"])).convert("L"))
            k = 0.75 * min(t["specscale"], 1.5)
            r = s.point(lambda v: int(round(255 * max(0.2, min(1.0, 1.0 - k * v / 255.0)))))
            r.save(os.path.join(d, "roughness.jpg"), quality=85, optimize=True)
            e_maps["roughness"] = "roughness.jpg"
        gc = t["glowcolor"]
        if maps.get("g") in files and "glow" in t["shader"] and (gc is None or max(gc) > 0):
            g = capped(Image.open(os.path.join(src, maps["g"])).convert("RGB"))
            if grey(g):                                  # a grey mask: the lit parts shine in the texture's own colour
                c = color.resize(g.size, Image.LANCZOS)
                g = Image.composite(c, Image.new("RGB", c.size), g.convert("L"))   # colour where the mask is lit
            if gc is not None and gc != (1.0, 1.0, 1.0):
                g = Image.merge("RGB", [ch.point(lambda v, k=k: int(min(255, v * k))) for ch, k in zip(g.split(), gc)])
            g.save(os.path.join(d, "glow.jpg"), quality=88, optimize=True)
            e_maps["glow"] = "glow.jpg"
            if "pulse" in t["shader"]:
                e_maps["glow_pulse"] = True
        width = Image.open(os.path.join(src, maps["0"])).size[0]
        name = nice_name(t["source_name"])
        if name in names:                                # (two different pictures with the same name)
            name += " (" + t["source_name"] + ")"
        names.add(name)
        artist = artist_of(t["source_name"])
        e = {"id": mid, "name": name, "category": artist, "credit": artist,
             "size": round(width * t["texscale"] / 128.0, 3), "surface": surface_of(name), "maps": e_maps}
        friend = t["source_name"].lower().split("_")[0].split("-")[0]
        if friend in FRIENDS:                            # made by Getridou from a friend's photo
            e["photo"] = FRIENDS[friend]
        entries.append(e)
    lib_path = os.path.join(out_root, "library.json")
    lib = json.load(open(lib_path, encoding="utf-8"))
    keep = [e for e in lib["materials"] if not e["id"].startswith(("getridou_", "lurking_"))]
    entries.sort(key=lambda e: (e["category"] != "Getridou", e["id"]))
    lib["materials"] = keep + entries
    json.dump(lib, open(lib_path, "w", encoding="utf-8"), indent=2)
    print(f"imported {len(entries)} materials ({sum(1 for e in entries if e['credit'] == 'Getridou')} Getridou,"
          f" {sum(1 for e in entries if e['credit'] == 'LURKing')} LURKing), skipped {len(skipped)}: {skipped}")
    print("with glow:", sum(1 for e in entries if "glow" in e["maps"]), " with normal:",
          sum(1 for e in entries if "normal" in e["maps"]), " with roughness:", sum(1 for e in entries if "roughness" in e["maps"]))


if __name__ == "__main__":
    main()
