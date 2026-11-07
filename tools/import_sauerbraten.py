"""Import the Cube 2: Sauerbraten texture packs whose licenses allow shipping them in MALLET.

    python tools/import_sauerbraten.py D:/Sauerbraten [materials folder]

Sauerbraten's README: its media "is not" free to reuse unless a pack's readme says so ("may be used for any purpose"
or similar). The packs below were checked one by one (2026-11-07); everything else stays out (no license file, only
for Sauerbraten / Quake maps, no editing or converting, or made from other people's textures). Notes per pack in
materials/SAUERBRATEN.txt, and each pack's own license file is copied next to its textures.

A texture's settings come from Sauerbraten's .cfg files (the pack's own, the bundled maps'): which normal /
specular / glow images go with it, its scale (texture 0 <file> rot x y <scale>, or texscale), the shader. Images no
.cfg uses are taken by their names. Size follows Sauerbraten: TEX_SCALE 8, one unit = one MALLET tick (0.125 m),
so a 512 px texture at scale 1 repeats every 8 m.
"""
import collections
import json
import os
import re
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from import_getridou import capped, grey, surface_of   # noqa: E402  (same conversion as Getridou's)

PACKS = {   # folder: (artist for the credit, license in short, license file(s) to copy, take normal/specular maps)
    "aard": ("Aardappel (Wouter van Oortmerssen)", "free to use in any way", ["readme.txt"], True),
    "cloward": ("Ben Cloward", "free for any project, personal or professional", ["readme.txt"], True),
    "drakker": ('David "Drakker" Pelletier', "public domain", ["license.txt"], True),
    "trak5": ("Georges 'TRaK' Grondin", "MIT", ["readme.txt"], True),
    "sheik": ("Fan|Sheik", "CC BY-SA 4.0", ["shktextures.txt"], True),
    "tomek": ("tomek", "CC BY", ["license.txt"], True),
    "painkillah": ("PainKillAH", "CC BY-NC-SA 2.5", ["PK_readme.txt"], True),
    "g_pack": ("Guilhem 'Gui' Bedos", "free for non-commercial use, with credit and its readme",
               ["g-pack_tex_sources_readme.txt"], True),
    "ik2k": ('Iikka "Fingers" Keranen', "free for non-commercial use and distribution, may be modified",
             ["ik2k_22feb01.txt"], True),
    # Rorschach's color maps only: the normal / specular / height maps in that folder are by Mayhem, unlicensed
    "rorschach": ("Kevin 'Rorshach' Johnstone", "convert to other engines freely, with credit (color maps only)",
                  ["rorschach_readme.txt"], False),
}
EXTRA_SUFFIX = re.compile(r"(_n|_nm|_local|_norm|normal|_s|_sm|_sc|_spec|specular|_h|_hm|depth|_height|_g|_gm|_glow|_mask|_ao)$",
                          re.IGNORECASE)
DIFFUSE_SUFFIX = re.compile(r"(_d|_cc|_diffuse|diffuse|_c|_col)$", re.IGNORECASE)


def parse_cfgs(root):
    """Every texture slot in every .cfg: [{"0": file, "n", "s", "g", "scale", "shader", "glowcolor", "specscale"}]."""
    slots = []
    for folder in ("packages", "data"):
        for dirpath, _, files in os.walk(os.path.join(root, folder)):
            for f in sorted(files):
                if not f.endswith(".cfg"):
                    continue
                shader, specscale, glowcolor, cur = "stdworld", 1.0, None, None
                for line in open(os.path.join(dirpath, f), encoding="latin-1"):
                    line = line.split("//")[0].strip()
                    m = re.match(r'setshader\s+"?([\w]+)', line)
                    if m:
                        shader, specscale, glowcolor = m.group(1), 1.0, None
                        continue
                    m = re.search(r'setshaderparam\s+"?specscale"?\s+([\d.]+)', line)
                    if m:
                        specscale = float(m.group(1))
                    m = re.search(r'setshaderparam\s+"?glowcolor"?\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', line)
                    if m:
                        glowcolor = tuple(float(x) for x in m.groups())
                    m = re.match(r'texture\s+(\S+)\s+"?([^"\s]+)"?\s*(.*)', line)
                    if m:
                        kind, path, rest = m.group(1), m.group(2).replace("\\", "/"), m.group(3).split()
                        if kind in ("0", "c"):
                            cur = {"0": path, "shader": shader, "specscale": specscale, "glowcolor": glowcolor,
                                   "scale": float(rest[3]) if len(rest) >= 4 and _num(rest[3]) else 1.0}
                            slots.append(cur)
                        elif cur is not None and kind in ("n", "s", "g", "z"):
                            cur.setdefault(kind, path)
                        continue
                    m = re.match(r"texscale\s+([\d.]+)", line)
                    if m and cur is not None:
                        cur["scale"] = float(m.group(1))
    return slots


def _num(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def nice_name(stem):
    s = re.sub(DIFFUSE_SUFFIX, "", stem).replace("-", " ").replace("_", " ").strip()
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    return s[:1].upper() + s[1:] if s else stem


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "D:/Sauerbraten"
    out_root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", "materials")
    pk = os.path.join(root, "packages")
    slots = parse_cfgs(root)
    by_diffuse = collections.defaultdict(list)
    for s in slots:
        by_diffuse[s["0"].lower()].append(s)
    used_as_extra = {s[k].lower() for s in slots for k in ("n", "s", "g", "z") if k in s}
    entries = []
    for pack, (artist, lic, lic_files, extras) in PACKS.items():
        folder = os.path.join(pk, pack)
        if not os.path.isdir(folder):
            continue
        images = []
        for dirpath, _, files in os.walk(folder):
            for f in sorted(files):
                if f.lower().endswith((".jpg", ".png", ".tga")):
                    images.append(os.path.relpath(os.path.join(dirpath, f), pk).replace("\\", "/"))
        names = set()
        for rel in images:
            stem = os.path.splitext(os.path.basename(rel))[0]
            if re.search(r"_(bk|dn|ft|lf|rt|up)$", stem) or "/env/" in rel.lower():
                continue                                  # skybox faces (custom skies come later)
            if rel.lower() in used_as_extra or (EXTRA_SUFFIX.search(stem) and rel.lower() not in by_diffuse):
                continue                                  # a normal / specular / height / glow map, not a texture
            cands = by_diffuse.get(rel.lower(), [])
            best = max(cands, key=lambda s: sum(1 for k in ("n", "s", "g") if k in s), default=None)
            scales = collections.Counter(s["scale"] for s in cands)
            t = dict(best) if best else {"0": rel, "shader": "stdworld", "specscale": 1.0, "glowcolor": None}
            t["scale"] = scales.most_common(1)[0][0] if scales else 1.0
            if not extras:
                for k in ("n", "s", "g", "z"):
                    t.pop(k, None)
            if best is None:                              # not in any .cfg: find its maps by name
                base = re.sub(DIFFUSE_SUFFIX, "", stem)
                for k, sufs in (("n", ("_n", "_nm", "_local", "Normal", "_normal")), ("s", ("_s", "_sm", "_sc", "Specular"))):
                    for suf in sufs:
                        for ext in (".jpg", ".png", ".tga"):
                            cand = os.path.dirname(rel) + "/" + base + suf + ext
                            if extras and os.path.isfile(os.path.join(pk, cand)):
                                t.setdefault(k, cand)
                if "s" in t:
                    t["shader"] = "bumpspecmapworld"
            mid = "sauer_" + re.sub(r"[^a-z0-9_]+", "_", (pack + "_" + stem).lower())
            d = os.path.join(out_root, mid)
            try:
                src = Image.open(os.path.join(pk, rel))
            except OSError:
                continue
            os.makedirs(d, exist_ok=True)
            color = capped(src.convert("RGB"))
            color.save(os.path.join(d, "color.jpg"), quality=88, optimize=True)
            prev = color.copy()
            prev.thumbnail((128, 128), Image.LANCZOS)
            prev.save(os.path.join(d, "preview.jpg"), quality=85, optimize=True)
            maps = {"color": "color.jpg"}
            if t.get("n") and os.path.isfile(os.path.join(pk, t["n"])) and "bump" in t.get("shader", "bump"):
                capped(Image.open(os.path.join(pk, t["n"])).convert("RGB")).save(os.path.join(d, "normal.jpg"), quality=90)
                maps["normal"] = "normal.jpg"
            if t.get("s") and os.path.isfile(os.path.join(pk, t["s"])) and "spec" in t.get("shader", "") and t["specscale"] > 0:
                s = capped(Image.open(os.path.join(pk, t["s"])).convert("L"))
                k = 0.75 * min(t["specscale"], 1.5)
                s.point(lambda v: int(round(255 * max(0.2, min(1.0, 1.0 - k * v / 255.0))))).save(
                    os.path.join(d, "roughness.jpg"), quality=85)
                maps["roughness"] = "roughness.jpg"
            gc = t.get("glowcolor")
            if t.get("g") and os.path.isfile(os.path.join(pk, t["g"])) and "glow" in t.get("shader", "") and (gc is None or max(gc) > 0):
                g = capped(Image.open(os.path.join(pk, t["g"])).convert("RGB"))
                if grey(g):
                    c = color.resize(g.size, Image.LANCZOS)
                    g = Image.composite(c, Image.new("RGB", c.size), g.convert("L"))
                g.save(os.path.join(d, "glow.jpg"), quality=88)
                maps["glow"] = "glow.jpg"
            name = nice_name(stem)
            if name in names:
                name += " (" + stem + ")"
            names.add(name)
            entries.append({"id": mid, "name": name, "category": "Sauerbraten · " + pack, "credit": artist,
                            "license": lic, "size": round(src.size[0] * float(t["scale"]) / 64.0, 3),
                            "surface": surface_of(name), "maps": maps})
        lic_dir = os.path.join(out_root, "sauerbraten_licenses", pack)
        os.makedirs(lic_dir, exist_ok=True)
        for lf in lic_files:
            if os.path.isfile(os.path.join(folder, lf)):
                shutil.copy(os.path.join(folder, lf), os.path.join(lic_dir, lf))
    lib_path = os.path.join(out_root, "library.json")
    lib = json.load(open(lib_path, encoding="utf-8"))
    lib["materials"] = [e for e in lib["materials"] if not e["id"].startswith("sauer_")] + entries
    json.dump(lib, open(lib_path, "w", encoding="utf-8"), indent=2)
    per = collections.Counter(e["category"] for e in entries)
    print(f"imported {len(entries)} Sauerbraten materials:", dict(per))
    print("with normal:", sum(1 for e in entries if "normal" in e["maps"]), " with roughness:",
          sum(1 for e in entries if "roughness" in e["maps"]), " with glow:", sum(1 for e in entries if "glow" in e["maps"]))


if __name__ == "__main__":
    main()
