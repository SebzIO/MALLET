"""Import Getridou's texture pack (Cube 2: Sauerbraten .tex materials) into MALLET's material library.

Only Getridou's own materials (getridou_*) are taken: the pack also holds textures by other artists (LURKing, cynthia,
azzie, arcabal, and some without a name) whose permission we don't have. See materials/GETRIDOU.txt.

    python tools/import_getridou.py D:/getridou [materials folder]

For each material (its .tex file says which images it uses):
  diffuse  -> color.jpg            (largest side capped at 1024 px, like the rest of the library)
  normal   -> normal.jpg
  specular -> roughness.jpg        (roughness = 1 - 0.75 x specular x specscale; no specular = matte)
  glow     -> glow.jpg             (only when the .tex shader glows and its glowcolor isn't black; a grey glow
                                    mask takes the colour texture's colours, so a green lamp glows green)
  preview.jpg (128 px) for the texture browser
Size (metres one repeat covers) follows Sauerbraten exactly: TEX_SCALE 8, one Sauerbraten unit = one MALLET tick
(0.125 m), so size = width_px x texscale / 64 (a 1024 px texture repeats every 16 m).
Height (displacement), ambient occlusion and environment-map settings aren't used (MALLET has no parallax yet).
"""
import json
import os
import re
import sys

from PIL import Image

MAX = 1024
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


def nice_name(mid):
    s = mid[len("getridou_"):].replace("_", " ")
    s = re.sub(r"(\D)(\d+)$", r"\1 \2", s)
    return s[:1].upper() + s[1:]


def surface_of(name):
    low = name.lower()
    for words, surf in SURFACES:
        if any(w in low for w in words):
            return surf
    return "concrete"


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "D:/getridou"
    out_root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "materials")
    files = set(os.listdir(src))
    found = {}
    for f in sorted(files):
        if f.startswith("getridou_") and f.endswith(".tex"):
            found[f[:-4]] = parse_tex(os.path.join(src, f))
    for f in sorted(files):                              # images with no .tex (e.g. sydtile11): default settings
        m = re.match(r"(getridou_.+)-diffuse\.png$", f)
        if m and m.group(1) not in found:
            base = m.group(1)
            maps = {"0": f}
            for key, kind in (("n", "normal"), ("s", "specular"), ("g", "glow")):
                if f"{base}-{kind}.png" in files:
                    maps[key] = f"{base}-{kind}.png"
            found[base] = {"maps": maps, "shader": "bumpspecmapworld", "texscale": 1.0, "glowcolor": None, "specscale": 1.0}
    entries, skipped = [], []
    for mid, t in sorted(found.items()):
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
        name = nice_name(mid)
        entries.append({"id": mid, "name": name, "category": "Getridou", "credit": "Getridou",
                        "size": round(width * t["texscale"] / 64.0, 3), "surface": surface_of(name), "maps": e_maps})
    lib_path = os.path.join(out_root, "library.json")
    lib = json.load(open(lib_path, encoding="utf-8"))
    keep = [e for e in lib["materials"] if not e["id"].startswith("getridou_")]
    lib["materials"] = keep + entries
    json.dump(lib, open(lib_path, "w", encoding="utf-8"), indent=2)
    print(f"imported {len(entries)} Getridou materials, skipped {len(skipped)}: {skipped}")
    print("with glow:", sum(1 for e in entries if "glow" in e["maps"]), " with normal:",
          sum(1 for e in entries if "normal" in e["maps"]), " with roughness:", sum(1 for e in entries if "roughness" in e["maps"]))


if __name__ == "__main__":
    main()
