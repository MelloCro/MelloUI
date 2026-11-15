"""Custom Sounds' kit lists from this client's own sound table.

Modules/CustomSounds.lua mutes the game's sound FILES it replaces (FILES) and plays its own sound when the game's Lua
plays a KIT of such a file. A kit that plays a muted file and is not listed plays nothing at all: the lists must hold
every kit the client has on each file. They are written here from the client's SoundKitEntry (kit -> file), which
wow.export brings out with the other tables:

    python Tools/sfx_kits.py            the lists written into Modules/CustomSounds.lua (a file the table lacks: as it is)
    python Tools/sfx_kits.py --check    nothing written; fails when a list differs, a kit plays files of two sounds or
                                        groups and is not named in KITS, or a named kit's file has no row
    python Tools/sfx_kits.py --table <SoundKitEntry.csv>    another table than the workspace's

After a client update: export SoundKitEntry again, run this, then the suite's sound tests.
"""
import csv
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LUA = os.path.join(ROOT, "Modules", "CustomSounds.lua")
TABLE = os.path.join(ROOT, "Workspace", "GameData", "WoWExport", "db2_1.60", "SoundKitEntry.csv")
# a FILES row: [file] = { "Sound", "group", { kits }[, "action"] },   -- its name
ROW = re.compile(r'^(\t\[(\d+)\] = \{ "(\w+)", "(\w+)", )\{([^}\n]*)\}((?:, "\w+")? \},[^\n]*)$', re.M)
NAMED = re.compile(r'^\t\[(\d+)\] = \{ "\w+", "(\w+)"', re.M)   # a KITS row: its kit and its group
FILE_ID = re.compile(r"^\t\[(\d+)\] = \{", re.M)


def main(argv):
    check = "--check" in argv
    table = argv[argv.index("--table") + 1] if "--table" in argv else TABLE
    if not os.path.isfile(table):
        print("sfx_kits: no sound table at %s (export SoundKitEntry with wow.export)" % table)
        return 2
    by_file = {}
    with open(table, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            by_file.setdefault(int(r["FileDataID"]), set()).add(int(r["SoundKitID"]))
    src = open(LUA, encoding="utf-8", newline="").read()
    start = src.index("local FILES = {")
    end = src.index("\n}\n", start)
    block = src[start:end]
    kits_start = src.index("local KITS = {")
    named = {int(k): group for k, group in NAMED.findall(src[kits_start:start])}   # a KITS kit -> its group
    listed = set(int(f) for f in FILE_ID.findall(block))
    by_kit = {}
    for f, ks in by_file.items():
        for k in ks:
            by_kit.setdefault(k, set()).add(f)
    differ, sound_of, rows = [], {}, 0

    def row(m):
        nonlocal rows
        rows += 1
        file = int(m.group(2))
        have = by_file.get(file)
        old = [int(k) for k in m.group(5).replace(" ", "").split(",") if k]
        # (a kit named in KITS belongs to its KITS group: it is listed only under that group's files, so one switch
        # both mutes its file and picks its sound -- the money dialog's two kits play a coin file as well)
        group = m.group(4)
        new = sorted(k for k in have if named.get(k, group) == group) if have is not None else old
        action = re.search(r'"(\w+)"', m.group(6).split("--")[0])
        for k in (have if have is not None else old):
            sound_of.setdefault(k, set()).add((m.group(3), group, action.group(1) if action else ""))
        if new != old:
            differ.append((file, m.group(3), len(old), len(new)))
        return "%s{%s}%s" % (m.group(1), (" " + ", ".join(str(k) for k in new) + " ") if new else "", m.group(6))

    out = ROW.sub(row, block)
    # a kit on files of two different sounds would be placed by whichever file the game's table walk reaches last:
    # such a kit has to be named in KITS
    torn = sorted(k for k, s in sound_of.items() if len(s) > 1 and k not in named)
    for k in torn:
        print("  kit %d plays files of different sounds or groups %s: name it in KITS" % (k, sorted(sound_of[k])))
    # a named kit whose file is not muted would be heard twice, the game's sound and MelloUI's: the file needs a row
    bare = sorted((k, f) for k in named for f in by_kit.get(k, ()) if f not in listed)
    for k, f in bare:
        print("  kit %d (named in KITS) plays file %d, which FILES does not mute: give the file a row" % (k, f))
    torn = torn + bare
    if check:
        for file, sound, a, b in differ:
            print("  file %d (%s): %d kits listed, the client has %d" % (file, sound, a, b))
        print("sfx_kits: %d files, %d lists differ from the client's table, %d kits to name" % (rows, len(differ), len(torn)))
        return 1 if differ or torn else 0
    if differ:
        open(LUA, "w", encoding="utf-8", newline="").write(src[:start] + out + src[end:])
    print("sfx_kits: %d files, %d lists written, %d kits to name" % (rows, len(differ), len(torn)))
    return 1 if torn else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
