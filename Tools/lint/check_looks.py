"""MelloUI's own parts and their two looks (docs/plans/game-look.md section 6; the user, 2026-10-01: with the reskin off
"that should follow all the features").

Every place a feature of MelloUI's OWN (not a game element the kit dresses) makes painted art is listed by feature:
a palette colour, MelloUI's font styling, a kit piece, the soft shade, a flat block of the own widget set, MelloUI's own
media. The rule: an own feature reaches its look only through MelloUI.Look (Core/GameLook.lua), which hands out the
game's twin with the reskin off. A painted call left in an own feature FAILS, named by file and line.

Since wave 4 the shared systems follow the look by themselves, so a call through them has its game twin (FOLLOWS, not
counted): a palette key painted through the one registry (W.Paint / Kit:Paint read MelloUI.Look.Palette), the widget
set's controls, panels, trays and blocks (W.*: their game art at the switch), the window shell (Kit:OwnWindow), a kit
replacement or rim the area switches (Kit:Replace, SetKit, W.RoundIcon), the UI shade (Kit:ShadeElement: its own
areas), MelloUI:StyleFont (the Fonts module styles the game's own fonts the same way). What is painted only (FAILS):
a palette colour read straight (MelloUI.Palette, not Look.Palette), MelloUI's own media, a kit piece put on a texture
by hand (Kit:Apply / Slot / Strip), a soft band or glow no Look block hides. A line that is right as it is says why
with a "look-ok:" comment (a meaning colour, a dressing of the game's own texts under its own switch).

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
    "Voice Over": ["MelloUI_VoiceOver/VoiceOver.lua"],
    "Damage meter": ["Modules/Meter.lua", "Modules/MeterBar.lua", "Modules/MeterHistory.lua", "Modules/MeterRaid.lua"],
    "Combat Text": ["MelloUI_CombatText/CombatText.lua", "Core/Feed.lua"],
    "Gains": ["Modules/Gains.lua"],
    "Notices and centre text": ["Core/Notice.lua", "Core/CentreText.lua"],
    "Threat": ["Core/Threat.lua"],
    "Services": ["Modules/Services.lua"],
    "Route": ["MelloUI_Route/Route.lua"],
    "Restock": ["Modules/Restock.lua"],
    "Swing Timers": ["Modules/SwingTimers.lua"],
    "Preview": ["Core/Preview.lua", "Core/ConfigPreview.lua"],
    "Configurator": ["Core/Config.lua", "Core/Tutorial.lua"],
    "Installer": ["Core/Installer.lua", "Core/InstallerWindow.lua"],
    "Edit Layout": ["Core/EditLayout.lua", "Core/EditLayoutBridge.lua", "Core/EditLayoutMovers.lua",
                    "Core/EditLayoutSnap.lua"],
    "Quest List": ["MelloUI_QuestList/QuestList.lua", "MelloUI_QuestList/QuestListMap.lua", "MelloUI_QuestList/QuestListTips.lua"],
    "Quest Tracker": ["Modules/QuestTracker.lua"],
    "Party Markers": ["Modules/PartyMarkers.lua"],
    "Chat (its own parts)": ["MelloUI_Chat/Chat.lua"],
    "FPS / Latency": ["Modules/Stats.lua"],
}

# painted only: these FAIL (unless the line says "look-ok:")
KINDS = [
    ("palette read", re.compile(r"(?<!Look\.)\bMelloUI\.Palette\b(?!\s*=)")),
    ("kit art by hand", re.compile(r"\bKit:(Slot|Strip|Apply)\(")),
    ("soft shade", re.compile(r"Shade:(Band|Glow)\(")),
    ("MelloUI media", re.compile(r"Media\\\\Textures|MEDIA \.\.")),
]
# through the shared systems: their game twins come with the switch (counted for the inventory, never failed)
FOLLOWS = [
    ("palette key", re.compile(r"\bW\.Paint\(|\bKit:Paint\(|:PaletteCode\(")),
    ("font styling", re.compile(r"MelloUI:StyleFont\(|\bStyleText\(|:SetFont\(")),
    ("kit replacement", re.compile(r"\bKit:(Replace|OwnWindow|Retile|Size)\(|:SetKit\(|:ShadeElement\(")),
    ("widget set", re.compile(r"\bW\.(Panel|Box|Solid|Edges|Button|Switch|Dropdown|Slider|Tabs|SearchBox|Card|NavRail|"
                              r"RowPlate|Tag|Row|Header|TrayBox|RoundIcon|Glyph|Pager|NumberBox|Rows)\(")),
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


# a band or glow kept in a name (row.band = ..., local band = ...): the painted look's only when the file hands that
# name to a Look block (Look.Hide / Look.Show), or the line is a Look block's own
BAND_NAME = re.compile(r"(?:local\s+)?([\w.]+)\s*=\s*[\w.]*Shade:(?:Band|Glow)\(")


def hidden_by_look(text, name):
    short = name.split(".")[-1]
    return re.search(r"Look\.(?:Hide|Show)\(\s*[\w.]*\b%s\b" % re.escape(short), text) is not None


def scan():
    found = {}     # feature -> [(file, line, kind, text)]: painted only
    follows = {}   # feature -> {kind: count}: through the shared systems
    for feature, files in OWN.items():
        rows = found.setdefault(feature, [])
        kinds = follows.setdefault(feature, {})
        for rel in files:
            path = os.path.join(ROOT, rel)
            if not os.path.isfile(path):
                continue
            raw = open(path, encoding="utf-8").read().split("\n")
            text = "\n".join(raw)
            for n, code in code_lines(path):
                if "look-ok:" in raw[n - 1]:
                    continue   # (said why at the line)
                if "Look." in code or "Look:" in code:
                    continue   # (through the dispatcher)
                hit = None
                for kind, pat in KINDS:
                    if pat.search(code):
                        hit = kind
                        break
                if hit == "soft shade":
                    m = BAND_NAME.search(code)
                    if m and hidden_by_look(text, m.group(1)):
                        hit = None
                if hit:
                    rows.append((rel, n, hit, code.strip()))
                    continue
                for kind, pat in FOLLOWS:
                    if pat.search(code):
                        kinds[kind] = kinds.get(kind, 0) + 1
                        break
    return found, follows


def main():
    found, follows = scan()
    where = "--where" in sys.argv
    listing = "--list" in sys.argv or where
    total = sum(len(v) for v in found.values())
    if listing:
        print("MelloUI's own features: what is still painted only (%d places), and what follows the look through the "
              "shared systems\n" % total)
        for feature, rows in found.items():
            kinds = {}
            for _, _, kind, _ in rows:
                kinds[kind] = kinds.get(kind, 0) + 1
            files = ", ".join(os.path.basename(f) for f in OWN[feature])
            state = "game look ready" if not rows else "%d painted only" % len(rows)
            print("  %-36s %-18s %s" % (feature, state, ", ".join("%s %d" % kv for kv in sorted(kinds.items()))))
            through = follows.get(feature) or {}
            if through:
                print("  %-36s %-18s %s" % ("", "follows", ", ".join("%s %d" % kv for kv in sorted(through.items()))))
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
