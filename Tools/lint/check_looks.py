"""MelloUI's own parts and their two looks (docs/plans/game-look.md section 6; the user, 2026-10-01: with the reskin off
"that should follow all the features").

Every place a feature of MelloUI's OWN (not a game element the kit dresses) makes painted art is listed by feature:
a palette colour, MelloUI's font styling, a kit piece, the soft shade, a flat block of the own widget set, MelloUI's own
media. The rule: an own feature reaches its look only through MelloUI.Look (Core/GameLook.lua), which hands out the
game's twin with the reskin off. A painted call left in an own feature FAILS, named by file and line.

    python Tools/lint/check_looks.py            the check (exit 1 with FAIL lines)
    python Tools/lint/check_looks.py --list     the inventory: every feature, what it paints and how often
    python Tools/lint/check_looks.py --where    ... and every line
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# the features of MelloUI's own, by file (the engines that draw the looks themselves, and the kit panels that dress
# the game's own frames, are not here: they follow their own areas)
OWN = {
    "Widget column, reminders, widgets": ["Core/Reminders.lua", "Modules/Reminders.lua", "Modules/Widgets.lua"],
    "Voice Over": ["Modules/VoiceOver.lua"],
    "Damage meter": ["Modules/Meter.lua", "Modules/MeterBar.lua", "Modules/MeterHistory.lua", "Modules/MeterRaid.lua"],
    "Combat Text": ["Modules/CombatText.lua", "Core/Feed.lua"],
    "Gains": ["Modules/Gains.lua"],
    "Notices and centre text": ["Core/Notice.lua", "Core/CentreText.lua"],
    "Threat": ["Core/Threat.lua"],
    "Services": ["Modules/Services.lua"],
    "Route": ["Modules/Route.lua"],
    "Restock": ["Modules/Restock.lua"],
    "Swing Timers": ["Modules/SwingTimers.lua"],
    "Preview": ["Core/Preview.lua", "Core/ConfigPreview.lua"],
    "Configurator": ["Core/Config.lua", "Core/Tutorial.lua"],
    "Installer": ["Core/Installer.lua", "Core/InstallerWindow.lua"],
    "Edit Layout": ["Core/EditLayout.lua", "Core/EditLayoutBridge.lua", "Core/EditLayoutMovers.lua",
                    "Core/EditLayoutSnap.lua"],
    "Quest List": ["Modules/QuestList.lua", "Modules/QuestListMap.lua", "Modules/QuestListTips.lua"],
    "Quest Tracker": ["Modules/QuestTracker.lua"],
    "Party Markers": ["Modules/PartyMarkers.lua"],
    "Chat (its own parts)": ["Modules/Chat.lua"],
    "FPS / Latency": ["Modules/Stats.lua"],
}

KINDS = [
    ("palette colour", re.compile(r"\bW\.Paint\(|\bKit:Paint\(|MelloUI\.Palette\b|:PaletteCode\(")),
    ("font styling", re.compile(r"MelloUI:StyleFont\(|\bStyleText\(|:SetFont\(")),
    ("kit piece", re.compile(r"\bKit:(Replace|Slot|Strip|Apply|OwnWindow|Retile|Size)\(|:SetKit\(")),
    ("soft shade", re.compile(r"Shade:(Band|Glow)\(|:ShadeElement\(")),
    ("flat block", re.compile(r"\bW\.(Panel|Box|Solid|Edges)\(")),
    ("own control", re.compile(r"\bW\.(Button|Switch|Dropdown|Slider|Tabs|SearchBox|Card|NavRail|RowPlate|Tag|Row|"
                               r"Header|TrayBox|RoundIcon|Glyph|Pager|NumberBox|Rows)\(")),
    ("MelloUI media", re.compile(r"Media\\\\Textures|MEDIA \.\.")),
]


def code_lines(path):
    """the file's lines with comments taken out (a -- outside a string ends the code)"""
    out = []
    for n, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        code, quote, i = "", None, 0
        while i < len(line):
            ch = line[i]
            if quote:
                code += ch
                if ch == "\\":
                    code += line[i + 1:i + 2]
                    i += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
                code += ch
            elif line.startswith("--", i):
                break
            else:
                code += ch
            i += 1
        out.append((n, code))
    return out


def scan():
    found = {}   # feature -> [(file, line, kind, text)]
    for feature, files in OWN.items():
        rows = found.setdefault(feature, [])
        for rel in files:
            path = os.path.join(ROOT, rel)
            if not os.path.isfile(path):
                continue
            for n, code in code_lines(path):
                if "Look." in code or "Look:" in code:
                    continue   # (through the dispatcher)
                for kind, pat in KINDS:
                    if pat.search(code):
                        rows.append((rel, n, kind, code.strip()))
                        break
    return found


def main():
    found = scan()
    where = "--where" in sys.argv
    listing = "--list" in sys.argv or where
    total = sum(len(v) for v in found.values())
    if listing:
        print("MelloUI's own features and the painted art they make outside MelloUI.Look (%d places):\n" % total)
        for feature, rows in found.items():
            kinds = {}
            for _, _, kind, _ in rows:
                kinds[kind] = kinds.get(kind, 0) + 1
            files = ", ".join(os.path.basename(f) for f in OWN[feature])
            state = "game look ready" if not rows else "%d places" % len(rows)
            print("  %-36s %-16s %s" % (feature, state, ", ".join("%s %d" % kv for kv in sorted(kinds.items()))))
            print("  %-36s %s" % ("", files))
            if where:
                for rel, n, kind, text in rows:
                    print("      %s:%d  [%s]  %s" % (rel, n, kind, text[:100]))
        return 0
    bad = [(f, r) for f, rows in found.items() for r in rows]
    for feature, (rel, n, kind, text) in bad:
        print("FAIL  %s:%d  %s (%s) outside MelloUI.Look: %s" % (rel, n, kind, feature, text[:90]))
    print("%d own features, %d painted places outside MelloUI.Look" % (len(found), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
