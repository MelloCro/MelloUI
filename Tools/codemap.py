"""Write docs/CODEMAP.md: a map of the addon's Lua for finding code without reading whole files.

For every Lua file (in the TOC's load order, then the companion and the data files) it lists
the file's size and purpose, its section banners, and its top-level functions with their line
numbers and the first line of the comment above each. Grep the map, then read only the lines you
need. Run it again after adding, moving or renaming functions:

    python Tools/codemap.py            write the map
    python Tools/codemap.py --check    exit 1 when the map is out of date (nothing written)

docs/CODEMAP.md and docs/CODEMAP-FUNCTIONS.md are generated and gitignored.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "CODEMAP.md")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lint"))
from features import feature_folders  # noqa: E402  (0.19.9: the feature addons, mapped as MelloUI's own)
FOLDERS = ["Core", "Modules", "MelloUI_Companion"] + feature_folders(ROOT) + ["Media"]
# data files: listed with their size only (tables, no code worth mapping)
DATA_LINES = 4000
DESC_MAX = 110
PURPOSE_MAX = 220

FUNC_PATTERNS = [
    re.compile(r"^(\s*)local\s+function\s+([\w.:]+)\s*\("),
    re.compile(r"^(\s*)function\s+([\w.:]+)\s*\("),
    re.compile(r"^(\s*)local\s+([\w]+)\s*=\s*function\s*\("),
    re.compile(r"^(\s*)([\w.:]+(?:\[[^\]]+\])?)\s*=\s*function\s*\("),
]
BANNER = re.compile(r"^--\s*[-=]{8,}\s*$")


def toc_order():
    """the Lua files in MelloUI.toc's order (and MelloUI_Companion's), repo-relative with forward slashes"""
    order = []
    tocs = [("MelloUI.toc", ""), ("MelloUI_Companion/MelloUI_Companion.toc", "MelloUI_Companion/")]
    tocs += [("%s/%s.toc" % (f, f), f + "/") for f in feature_folders(ROOT)]
    for toc, base in tocs:
        path = os.path.join(ROOT, toc)
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if line and not line.startswith("#") and line.lower().endswith(".lua"):
                order.append(base + line.replace("\\", "/"))
    return order


def all_lua():
    found = []
    for folder in FOLDERS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, folder)):
            for name in files:
                if name.lower().endswith(".lua"):
                    found.append(os.path.relpath(os.path.join(dirpath, name), ROOT).replace("\\", "/"))
    order = toc_order()
    rank = {p: i for i, p in enumerate(order)}
    return sorted(found, key=lambda p: (rank.get(p, len(order)), p))


def clean_comment(line):
    s = line.strip()
    s = re.sub(r"^--+\s?", "", s)
    s = re.sub(r"^\[\[|\]\]$", "", s)
    return s.strip()


def purpose(lines):
    """the first paragraph of the file's header comment that is not its "MelloUI - Name" title"""
    paras, cur = [], []
    started = False
    for raw in lines[:80]:
        s = raw.strip()
        if not s.startswith("--"):
            if started:
                break
            continue
        started = True
        c = "" if BANNER.match(s) else clean_comment(s)
        if c:
            cur.append(c)
        elif cur:
            paras.append(cur)
            cur = []
    if cur:
        paras.append(cur)
    paras = [p for p in paras if not (len(p) == 1 and re.match(r"^MelloUI\s*[-:]", p[0]))]
    if not paras:
        return ""
    out = " ".join(paras[0])
    return out if len(out) <= PURPOSE_MAX else out[:PURPOSE_MAX - 3].rstrip() + "..."


def comment_above(lines, i):
    """the first line of the contiguous comment block right above line i (0-based)"""
    j = i - 1
    block = []
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("--") and not BANNER.match(s):
            block.append(clean_comment(s))
            j -= 1
            continue
        break
    block = [b for b in reversed(block) if b]
    if not block:
        return ""
    d = block[0]
    if len(block) > 1 and len(d) < 50:
        d = d + " " + block[1]
    return d if len(d) <= DESC_MAX else d[:DESC_MAX - 3].rstrip() + "..."


def sections(lines):
    """banner titles: a comment title line between two banner lines (or right after one)"""
    out = []
    for i, raw in enumerate(lines):
        if BANNER.match(raw.strip()) and i + 1 < len(lines):
            t = lines[i + 1].strip()
            if t.startswith("--") and not BANNER.match(t):
                title = clean_comment(t)
                if title and i > 5:
                    out.append((i + 2, title[:90]))
    return out


def functions(lines):
    out = []
    for i, raw in enumerate(lines):
        if raw.lstrip().startswith("--"):
            continue
        for pat in FUNC_PATTERNS:
            m = pat.match(raw)
            if m:
                indent = m.group(1).replace("    ", "\t")
                # top level, or one step in (a do ... end block, a module table's methods)
                if len(indent) <= 1:
                    out.append((i + 1, m.group(2), comment_above(lines, i)))
                break
    return out


def build():
    """(the overview: every file, its purpose and sections; the functions: every file's function list)"""
    files = all_lua()
    overview = [
        "# MelloUI code map",
        "",
        "Generated by `python Tools/codemap.py`; do not edit. Every Lua file in the TOC's load order: its size,",
        "its purpose and its sections (`L123` = line 123). The functions are in docs/CODEMAP-FUNCTIONS.md:",
        "grep that for a name, then read only those lines.",
        "",
    ]
    funcs_out = [
        "# MelloUI functions",
        "",
        "Generated by `python Tools/codemap.py`; do not edit. Each file's top-level functions (and those one",
        "level in: a `do ... end` block) with their line and the first line of the comment above them.",
        "",
    ]
    for rel in files:
        path = os.path.join(ROOT, rel)
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
        n = len(lines)
        funcs = functions(lines)
        is_data = rel.startswith("Media/") and (n > DATA_LINES or len(funcs) < 3)
        p = purpose(lines)
        overview.append("## `%s` (%d lines%s)" % (rel, n, ", data" if is_data else ""))
        if p:
            overview.append(p)
        if is_data:
            overview.append("")
            continue
        secs = sections(lines)
        if secs:
            overview.append("Sections: " + "; ".join("L%d %s" % s for s in secs))
        overview.append("")
        funcs_out.append("## %s" % rel)
        for ln, name, desc in funcs:
            funcs_out.append("- L%d `%s`%s" % (ln, name, (" " + desc) if desc else ""))
        funcs_out.append("")
    return "\n".join(overview) + "\n", "\n".join(funcs_out) + "\n"


OUT_FUNCS = os.path.join(ROOT, "docs", "CODEMAP-FUNCTIONS.md")


def main():
    texts = build()
    outs = (OUT, OUT_FUNCS)
    if "--check" in sys.argv:
        for out, text in zip(outs, texts):
            old = open(out, encoding="utf-8").read() if os.path.exists(out) else ""
            if old != text:
                print("%s is out of date: run python Tools/codemap.py" % os.path.relpath(out, ROOT))
                sys.exit(1)
        print("the code map is up to date")
        return
    for out, text in zip(outs, texts):
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print("wrote %s: %d KB" % (os.path.relpath(out, ROOT).replace("\\", "/"), len(text.encode("utf-8")) // 1024))


if __name__ == "__main__":
    main()
