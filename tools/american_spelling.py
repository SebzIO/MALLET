"""MALLET is written in American English (the author is American). This rewrites British spellings in on-screen
text, comments and docs - never in code names (functions, variables, constants), which only programmers see.

    python tools/american_spelling.py [--check]     (--check: list what would change, change nothing)
"""
import os
import re
import subprocess
import sys

WORDS = {
    "centre": "center", "centres": "centers", "centred": "centered", "centring": "centering",
    "colour": "color", "colours": "colors", "coloured": "colored", "colouring": "coloring", "recolour": "recolor",
    "metre": "meter", "metres": "meters", "grey": "gray", "greyish": "grayish",
    "behaviour": "behavior", "behaviours": "behaviors",
    "neighbour": "neighbor", "neighbours": "neighbors", "neighbouring": "neighboring",
    "maximise": "maximize", "maximised": "maximized", "maximises": "maximizes", "maximising": "maximizing",
    "minimise": "minimize", "minimised": "minimized",
    "travelled": "traveled", "travelling": "traveling", "modelled": "modeled", "modelling": "modeling",
    "labelled": "labeled", "labelling": "labeling", "licence": "license", "licences": "licenses",
    "favourite": "favorite", "organise": "organize", "organised": "organized", "recognise": "recognize",
    "recognised": "recognized", "optimise": "optimize", "optimised": "optimized", "cancelled": "canceled",
    "analyse": "analyze", "realise": "realize", "realised": "realized", "catalogue": "catalog",
}
PATTERN = re.compile(r"\b(" + "|".join(sorted(WORDS, key=len, reverse=True)) + r")\b(?!\()", re.IGNORECASE)   # (word( = a function name)
TEXT_EXT = (".md", ".txt")
CODE_EXT = (".gd", ".gdshader")
SKIP = ("materials/library.json",)
SKIP_DIRS = ("addons/",)               # third-party code stays exactly as its authors wrote it


def fix_word(m):
    w = m.group(0)
    new = WORDS[w.lower()]
    if w.isupper():
        return new.upper()
    if w[0].isupper():
        return new[0].upper() + new[1:]
    return new


def fix_text(s):
    return PATTERN.sub(fix_word, s)


def fix_code_line(line):
    """Only inside "strings", 'strings' and # comments."""
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "#":
            out.append(fix_text(line[i:]))
            break
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            out.append(c + fix_text(line[i + 1:j]) + (c if j < n else ""))
            i = j + 1
            continue
        if c == "/" and line[i:i + 2] == "//":             # shader comments
            out.append(fix_text(line[i:]))
            break
        j = i
        while j < n and line[j] not in "#\"'/":
            j += 1
        if j == i:
            j += 1
        out.append(line[i:j])
        i = j
    return "".join(out)


def main():
    check = "--check" in sys.argv
    root = os.path.join(os.path.dirname(__file__), "..")
    files = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=root).stdout.split("\n")
    total = 0
    for f in files:
        if not f or f.startswith("materials/") and not f.endswith((".txt", ".md")) or f in SKIP or f.startswith(SKIP_DIRS):
            continue
        if not f.endswith(TEXT_EXT + CODE_EXT):
            continue
        p = os.path.join(root, f)
        s = open(p, encoding="utf-8").read()
        if f.endswith(CODE_EXT):
            n = "\n".join(fix_code_line(l) for l in s.split("\n"))
        else:
            n = fix_text(s)
        if n != s:
            changed = sum(1 for a, b in zip(s.split("\n"), n.split("\n")) if a != b)
            total += changed
            print(f"{changed:4d}  {f}")
            if not check:
                open(p, "w", encoding="utf-8", newline="").write(n)
    print(("would change" if check else "changed"), total, "lines")


if __name__ == "__main__":
    main()
