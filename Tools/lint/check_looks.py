"""MelloUI's one look: the guard (docs/plans/one-look-build.md section 7, stage E; docs/plans/onelook-e-plans/E4v2.md).

Since onelook stage C MelloUI's own parts wear one look, the modern one. What 0.17.1-0.21 built for the reskin switched
off -- MelloUI.Look's game halves, the 'own' area and its switches, W.Game, the plain shell, the game's art on MelloUI's
own parts -- is removed in stage E. This guard finds what is left of that game look and keeps anything new from coming
in. (It replaced 0.17.1's rule "an own part reaches its look only through MelloUI.Look", whose `look-ok:` exemption and
Look.Hide band rule went with it, onelook E4-1.)

The two kinds of "off" (CLAUDE.md): `Look:On` / `GA.Game` off = the game look, which GOES (families 1, 2, 3 and 5);
`Kit:IsOn(cover)` / `KitOn()` off = MelloUI's plain palette look under Oldschool's covers, which STAYS (family 4 only
counts it, so no new cover branch comes into an own part before stage I moves them to MelloUI_Oldschool).

The files: Core/*.lua, Modules/*.lua and every feature addon's TOC-listed Lua files (Tools/lint/features.py), as
check_panels.py scans them. Comments never count (strings do); family 5 reads the raw lines. The classes:
  SHARED     the shared systems (GameLook, Widgets, KitWindow, Core, Kit)
  OWN        MelloUI's own parts, by feature (Group Frames included: the user, 2026-10-15, own frames stay)
  ENHANCERS  the core modules of stage D that enhance game elements (unit frames, action bars, backdrops, the minimap,
             the quest pages, Edit Layout's windows, the nameplates' band): families 1, 3 and 5 only
  the rest   the kit's panels (Modules/*Panel.lua that dress the game's windows, NameplatePanel included), the kit's
             engines and the other modules: families 1, 3 and 5 and the coverage rule; never families 2 and 4

THE FAMILIES (a hit is one match on one line):
  api      (1) every file. A removed MelloUI.Look API: `MelloUI.Look`, `ns.MelloUI.Look`, Core.lua's `self.Look` or
           a name the file binds to one of them (`local [a, ]Look = [x, ]MelloUI.Look`, multi-assign included; a
           binding to MelloUI.CentreLook or a file's own `local Look = {...}` is never one), then `.` or `:` and a key
           outside FINAL (onelook/lookcore K1's set); `.Art("k")` / `.ART.k` for a k outside KEPT_ART. The game
           look's identifiers (IDENTIFIERS). In Core/GameLook.lua: a `function Look.X` / `Look.X =` (or a key of
           `local Look = {...}`) outside FINAL, and a Look.ART key outside KEPT_ART. (`local GameLook =` is no hit.)
  art      (2) OWN files and GameLook / Widgets / KitWindow: a game art name of GAME_ART in the code.
  area     (3) every file. The dead areas' topics ("look:own|questTracker|questList|loot") and Kit:IsOn of them; in
           Modules/Kit.lua a Kit.Areas LIST entry with `module =`, `switch =` or `showcase =`, and a read of
           area.module / area.switch / area.showcase.
  cover    (4) OWN files only: Kit:IsOn(, KitOn(, IsCovered(, MelloUI:On("look:<other>" or "look:" .., MelloUI:On(
           "cover" and :OnCover( -- Oldschool's handshakes in MelloUI's own parts. A per-file ceiling that stays after
           G2, until stage I.
  hygiene  (5) raw lines. A `look-ok:` marker in any file; in OWN files and GameLook / Widgets / KitWindow the game-look
           comment phrases ("the reskin off: the game's", "the game's look with the reskin off", "game twin", "the
           tracker's look off: the game's").

ESCAPE: a line holding `onelook-allow: <why>` is never counted. --list lists those lines, and the `oldschool-hook:`
lines (cover-gated kit art in an own part, for stage I's guard).
COVERAGE: a file that names MelloUI.Look outside OWN, SHARED and ENHANCERS is "unclassified" and FAILs.
CEILINGS: 'family:file' -> the count measured at landing (--counts, on a clean export of the commit being made). A
count above its ceiling FAILs with every line; a count below prints the ceiling to lower (no failure): the lead lowers
them per batch (one editor of this file at a time).
SUMMARY: `one look: N leftovers, C cover branches, K over their ceiling, L to lower, U unclassified` (N = families 1,
2, 3 and 5; C = family 4). Exit 1 when K or U is above 0.

GAME_ART is frozen from d2664da (MelloUI.Look.ART's game names, Widgets' GA block of E2's list, KitWindow's BuildPlain,
TOOLTIP_DEFAULT_*). It holds no Waypoint-MapPin-* (map pins and chat labels are content; Look.Art('mapPin') is family
1), no template but BuildPlain's ButtonFrameTemplateNoPortrait, no TempPortraitAlphaMask, no MiniMap-TrackingBorder (the
round rim) and no UI-HUD-CoolDownManager-Bar.

History:
  G1 (onelook E4-1, 2026-10-15): this guard, in ratchet mode: every family counted against the ceilings taken at
     landing, so E1 / E3 can delete their Look.Hide lines and look-ok markers in any order (each only lowers a count).
  G2 (E4-6, last): families 1, 2, 3 and 5 lose their ceilings (any hit FAILs; the suite needs '0 leftovers'); family
     4 keeps its per-file ceilings until stage I.

    python Tools/lint/check_looks.py              the guard (exit 1 on a rise or an unclassified file)
    python Tools/lint/check_looks.py --list       the inventory: the classes, every file's counts, the escape and
                                                  oldschool-hook lines
    python Tools/lint/check_looks.py --where      ... and every line
    python Tools/lint/check_looks.py --counts     today's counts as CEILINGS
    ... --root DIR                                another copy of the addon
"""
import bisect
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DIRS = ("Core", "Modules")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from features import feature_files  # noqa: E402  (the feature addons' files, checked as Modules/)

# ---------------------------------------------------------------------------------------------------------------- classes
# the shared systems: they paint for every part (W.Paint / Kit:Paint, the widget set, the shell, the kit)
SHARED = ["Core/GameLook.lua", "Core/Widgets.lua", "Modules/KitWindow.lua", "Core/Core.lua", "Modules/Kit.lua",
          "Modules/KitPainted.lua"]

# MelloUI's own parts, by feature ("<folder>/*": every Lua file a feature addon's TOC lists)
OWN = {
    "Widget column, reminders, widgets": ["Core/Reminders.lua", "Modules/Reminders.lua", "Modules/Widgets.lua"],
    "Widget panel": ["Modules/WidgetPanel.lua"],
    "Voice Over": ["MelloUI_VoiceOver/VoiceOver.lua"],
    "Damage meter": ["Modules/Meter.lua", "Modules/MeterBar.lua", "Modules/MeterHistory.lua", "Modules/MeterRaid.lua"],
    "Combat Text": ["MelloUI_CombatText/CombatText.lua", "Core/Feed.lua"],
    "Gains": ["Modules/Gains.lua"],
    "Notices and centre text": ["Core/Notice.lua", "Core/CentreText.lua"],
    "Threat": ["Core/Threat.lua"],
    "Services": ["Modules/Services.lua"],
    "Route": ["MelloUI_Route/Route.lua", "MelloUI_Route/RouteRecorder.lua"],
    "Restock": ["Modules/Restock.lua"],
    "Swing Timers": ["Modules/SwingTimers.lua"],
    "Preview": ["Core/Preview.lua", "Core/ConfigPreview.lua"],
    "Configurator": ["Core/Config.lua", "Core/Tutorial.lua"],
    "Installer": ["Core/Installer.lua", "Core/InstallerWindow.lua"],
    "Edit Layout": ["Core/EditLayout.lua", "Core/EditLayoutBridge.lua", "Core/EditLayoutMovers.lua",
                    "Core/EditLayoutSnap.lua"],
    "Quest List": ["MelloUI_QuestList/QuestList.lua", "MelloUI_QuestList/QuestListMap.lua",
                   "MelloUI_QuestList/QuestListTips.lua", "MelloUI_QuestList/QuestListObjectives.lua",
                   "MelloUI_QuestList/QuestListPanel.lua"],
    "Quest Tracker": ["Modules/QuestTracker.lua"],
    "Party Markers": ["Modules/PartyMarkers.lua"],
    "Chat (its own parts)": ["MelloUI_Chat/Chat.lua", "MelloUI_Chat/ChatView.lua", "MelloUI_Chat/ChatWhispers.lua"],
    "FPS / Latency": ["Modules/Stats.lua"],
    "Bag window": ["Modules/BagWindow.lua"],
    "Discard": ["Modules/Discard.lua"],
    "Probes": ["Modules/AuraProbe.lua", "Modules/HealProbe.lua"],
    "Personal Display": ["MelloUI_PersonalDisplay/*"],
    "Group Frames": ["MelloUI_GroupFrames/*"],   # (the user, 2026-10-15: own frames stay, the solo frame too)
    "Frame Effects": ["MelloUI_FrameEffects/*"],
}

# the core modules of stage D that enhance the game's own elements: no ratchet, no art scan (stage I never drives them
# to 0); families 1, 3 and 5 still read them. Their cover reads are D5's handshakes.
ENHANCERS = ["Modules/UnitFrames.lua", "Modules/ActionBars.lua", "Core/Backdrop.lua", "Modules/MinimapPanel.lua",
             "Modules/QuestPages.lua", "Core/EditLayoutWindows.lua", "Modules/Nameplates.lua",
             "Modules/PlateImpact.lua"]   # (0.25.0: Impact Effects on the game's nameplates, beside Nameplates.lua)

# the shared files family 2 reads beside the own parts (Kit.lua and the kit's panels never: the painted skins of the
# game's windows name the game's art by design)
ART_TOO = ["Core/GameLook.lua", "Core/Widgets.lua", "Modules/KitWindow.lua"]

# ------------------------------------------------------------------------------------------------------------ the rules
# MelloUI.Look's keys after stage E: onelook/lookcore K1's set (docs/plans/onelook-e-plans/E1v2.md: no AREA, On, Watch,
# Hide, Show, Only, Pieces, Panel, Bar, GameFrame(Shown), GameBar(Parts), GameSwing(Parts), ColumnButton(Plate) ...)
FINAL = ("Art", "ART", "Palette", "Text", "Tint", "RoleColour", "Colour", "Paint", "Unpaint", "Solid", "Mark", "Plate",
         "Ring", "RingState", "Count", "CountShown", "ClassIcon", "Outline", "Shadow")
KEPT_ART = ("rareMark", "rareEliteMark")   # (the Rare Alert's crest: the game's own rank icons)
DEAD_AREAS = ("own", "questTracker", "questList", "loot")   # (always on since stage C; their entries go in stage I)

# the game look's identifiers (family 1): (what, the pattern, a word the file must hold for the pattern to be tried).
# The word must be in EVERY match (a speed gate only): a word some match lacks hides that match in each file without
# it (W.PanelLook under 'Game', E4-1 review 2026-10-15). The self-test's G6 checks every name a label lists.
IDENTIFIERS = [
    ("GA.Game / GA.OnLook / GA.PlainField", r"\bGA\.(?:Game|OnLook|PlainField)\b", "GA."),
    ("W.Game / W.FollowGame", r"\b(?:W|Widgets)\.(?:Game|FollowGame)\b", "Game"),
    ("W.PanelLook", r"\b(?:W|Widgets)\.PanelLook\b", "PanelLook"),
    ("melloGame*", r"\bmelloGame\w*", "melloGame"),
    (":SetPlain(", r":\s*SetPlain\s*\(", "SetPlain"),
    ("BuildPlain / BuildPlainLook", r"\bBuildPlain(?:Look)?\b", "BuildPlain"),
    ("COLUMNS.game", r"\bCOLUMNS\.game\b", "COLUMNS"),
    ("KitCovers", r"\bKitCovers\b", "KitCovers"),
    ("gameGem", r"\bgameGem\b", "gameGem"),
    ("Beacon.painted", r"\bBeacon\.painted\b", "painted"),
    ("BAR_GAME", r"\bBAR_GAME\b", "BAR_GAME"),
    ("Kit:Showcase", r"\bKit\s*[.:]\s*Showcase\b", "Showcase"),
    ("showcaseOn", r"\bshowcaseOn\b", "showcaseOn"),
]
IDENTIFIERS = [(what, re.compile(p), word) for what, p, word in IDENTIFIERS]

# the game look's art (family 2), frozen from d2664da: (name, a regex rather than a plain name)
GAME_ART = [
    # MelloUI.Look.ART's game names (Core/GameLook.lua)
    (r"Tooltip-NineSlice-\w+", True),   # (the 9 pieces of the game tooltip's frame)
    ("ui-damagemeters-bar-shadowbg", False), ("ui-damagemeters-bar-shadowedge", False),
    ("Navigation-Tracked-Icon", False), ("Navigation-Tracked-Arrow", False),
    ("optionsicon-brown", False),
    ("UI-Frame-InnerTopLeft", False), ("UI-Frame-InnerTopRight", False), ("UI-Frame-InnerBotLeftCorner", False),
    ("UI-Frame-InnerBotRight", False), ("UI-Frame-InnerTopTile", False), ("UI-Frame-InnerBotTile", False),
    ("UI-Frame-InnerLeftTile", False), ("UI-Frame-InnerRightTile", False),
    ("UI-Background-Marble", False), ("UI-Classes-Circles", False),
    ("Options_List_Active", False), ("Options_List_Hover", False),
    ("chatframe-button-up", False), ("chatframe-button-highlight", False),
    ("ui-swingtimerbar-background", False), ("ui-swingtimerbar-frame", False),
    ("ui-swingtimerbar-filling-mainhand", False), ("ui-swingtimerbar-filling-offhand", False),
    ("ui-swingtimerbar-filling-ranged", False),
    # Widgets' GA block (Core/Widgets.lua; gone in E2, f253824): the game's switch, dropdown, slider, close and search
    ("checkbox-minimal", False), ("checkmark-minimal", False), ("checkmark-minimal-disabled", False),
    ("common-dropdown-textholder", False), ("common-dropdown-a-button", False),
    ("common-dropdown-a-button-hover", False), ("common-dropdown-a-button-disabled", False),
    ("Minimal_SliderBar_Button", False), ("Minimal_SliderBar_Left", False), ("Minimal_SliderBar_Right", False),
    ("Minimal_SliderBar_Middle", False),
    ("RedButton-Exit", False), ("RedButton-Exit-Disabled", False), ("RedButton-exit-pressed", False),
    ("RedButton-Highlight", False),
    ("common-search-border-left", False), ("common-search-border-middle", False), ("common-search-border-right", False),
    # KitWindow's BuildPlain (Modules/KitWindow.lua; gone in E2): the game's own window frame
    ("NineSliceUtil", False), ("UI-Frame-TopTileStreaks", False), ("ButtonFrameTemplateNoPortrait", False),
    # the game tooltip's colours (GameLook's game palette)
    (r"TOOLTIP_DEFAULT_\w+", True),
]
# a name stands alone: not inside a longer name ("_" / "!" prefixes of the atlases and a path's "\\" may stand before)
ART_RX = re.compile(r"(?<![A-Za-z0-9-])(?:%s)(?![\w-])" % "|".join(n if rx else re.escape(n) for n, rx in GAME_ART),
                    re.I)

# the game-look comment phrases (family 5)
PHRASES = re.compile(r"the reskin off: the game[’']s|the game[’']s look with the reskin off|game twin"
                     r"|the tracker[’']s look off: the game[’']s", re.I)
MARKER = re.compile(r"(?<![\w-])look-ok:")
ESCAPE = "onelook-allow:"
HOOK = "oldschool-hook:"

FAMILIES = ("api", "art", "area", "cover", "hygiene")
INSTEAD = {
    "api": "MelloUI.Look keeps only its painted helpers (FINAL: Palette, Text, Tint, Paint, Plate, Ring, Mark, ...; Art "
           "for the rare crests): paint through them, W.Paint / Kit:Paint, and drop the game branch",
    "art": "the game's own art in MelloUI's parts: the modern look's flat pieces (W.*), the palette, MelloUI's media",
    "area": "a dead area (own, questTracker, questList and loot are always on since stage C) or a dead Kit.Areas kind "
            "(module, switch, showcase): drop the branch",
    "cover": "one more cover branch in an own part: Oldschool's handshakes stay as they are (stage I moves them to "
             "MelloUI_Oldschool); MelloUI's own parts wear one look",
    "hygiene": "a look-ok marker or a game-look comment: say what the line does today (or `onelook-allow: <why>`)",
}

# the ceilings: the counts at landing (G1, onelook E4-1, 2026-10-15: --counts on a clean `git archive` of 492aae6, and
# where the worktree's uncommitted work moved a leftover, the higher of the two, so either order of landing is green);
# a family:file not listed has 0. Lower one when the guard says so; never raise one to let a leftover pass.
CEILINGS = {
    # api
    "api:Core/GameLook.lua": 55,
    "api:Core/Installer.lua": 2,
    "api:Core/InstallerWindow.lua": 2,
    "api:Core/Notice.lua": 0,
    "api:Core/Reminders.lua": 0,
    "api:MelloUI_Chat/Chat.lua": 0,
    "api:MelloUI_CombatText/CombatText.lua": 0,
    "api:MelloUI_Route/Route.lua": 0,
    "api:Modules/BagWindow.lua": 0,
    "api:Modules/Gains.lua": 0,
    "api:Modules/Kit.lua": 4,
    "api:Modules/Meter.lua": 0,
    "api:Modules/MeterBar.lua": 0,
    "api:Modules/MeterHistory.lua": 0,
    "api:Modules/QuestTracker.lua": 0,
    # art
    "art:Core/GameLook.lua": 36,
    # area
    "area:Core/Reminders.lua": 0,
    "area:Core/Widgets.lua": 1,   # (0 at 492aae6; the tree's Kit:Paint move brings Kit.lua's 'look:own' here)
    "area:MelloUI_Chat/Chat.lua": 0,
    "area:MelloUI_QuestList/QuestListMap.lua": 0,
    "area:Modules/Kit.lua": 7,   # (7 once that move lands)
    "area:Modules/QuestTracker.lua": 0,
    "area:Modules/Stats.lua": 0,
    # cover (stays after G2, until stage I)
    "cover:Core/Reminders.lua": 12,
    "cover:MelloUI_Chat/Chat.lua": 7,
    "cover:MelloUI_Chat/ChatView.lua": 1,
    "cover:Modules/BagWindow.lua": 2,
    "cover:Modules/QuestTracker.lua": 0,
    "cover:Modules/Restock.lua": 2,
    "cover:Modules/Services.lua": 5,
    "cover:Modules/WidgetPanel.lua": 2,
    # hygiene
    "hygiene:Core/CentreText.lua": 1,
    "hygiene:Core/Config.lua": 2,
    "hygiene:Core/EditLayoutMovers.lua": 1,
    "hygiene:Core/InstallerWindow.lua": 1,
    "hygiene:Core/Notice.lua": 2,
    "hygiene:Core/Reminders.lua": 6,
    "hygiene:Core/Widgets.lua": 1,
    "hygiene:MelloUI_Chat/Chat.lua": 4,
    "hygiene:MelloUI_CombatText/CombatText.lua": 0,
    "hygiene:MelloUI_GroupFrames/GroupButton.lua": 2,
    "hygiene:MelloUI_GroupFrames/GroupDesignerPage.lua": 4,
    "hygiene:MelloUI_GroupFrames/GroupLooks.lua": 8,
    "hygiene:MelloUI_GroupFrames/GroupSolo.lua": 1,
    "hygiene:MelloUI_QuestList/QuestListMap.lua": 1,
    "hygiene:MelloUI_Route/Route.lua": 4,
    "hygiene:MelloUI_VoiceOver/VoiceOver.lua": 1,
    "hygiene:Modules/AuraProbe.lua": 1,
    "hygiene:Modules/BagWindow.lua": 1,
    "hygiene:Modules/Gains.lua": 0,
    "hygiene:Modules/HealProbe.lua": 2,
    "hygiene:Modules/MeterBar.lua": 2,
    "hygiene:Modules/MeterRaid.lua": 0,
    "hygiene:Modules/QuestTracker.lua": 3,
    "hygiene:Modules/Services.lua": 3,
    "hygiene:Modules/Stats.lua": 0,
    "hygiene:Modules/SwingTimers.lua": 2,
    "hygiene:Modules/UnitFramePanel.lua": 1,
    "hygiene:Modules/Widgets.lua": 0,
}

# --------------------------------------------------------------------------------------------------------- the sources
TOKEN = re.compile(r"""
    --\[(?P<ceq>=*)\[.*?\](?P=ceq)\]     # a long comment
  | --[^\n]*                             # a line comment
  | \[(?P<seq>=*)\[.*?\](?P=seq)\]       # a long string
  | "(?:\\.|[^"\\\n])*"?                 # a quoted string
  | '(?:\\.|[^'\\\n])*'?
""", re.S | re.X)


def blank(raw):
    """(code, bare): the comments as spaces (the newlines kept), and in bare the strings too, character for character
    as long as raw (so a position is the same in all three)"""
    code, bare, last = [], [], 0
    for m in TOKEN.finditer(raw):
        text = m.group(0)
        code.append(raw[last:m.start()])
        bare.append(raw[last:m.start()])
        spaces = re.sub(r"[^\n]", " ", text) if "\n" in text else " " * len(text)
        if text.startswith("--"):
            code.append(spaces)
        else:
            code.append(text)
        bare.append(spaces)
        last = m.end()
    code.append(raw[last:])
    bare.append(raw[last:])
    return "".join(code), "".join(bare)


def code_lines(path):
    """the file's lines with comments taken out (strings kept): [(line number, code)]"""
    with open(path, encoding="utf-8") as fh:
        code, _ = blank(fh.read().replace("\r\n", "\n"))
    return [(n, line.rstrip()) for n, line in enumerate(code.split("\n"), 1)]


def read_raw(root, path):
    with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
        return fh.read().replace("\r\n", "\n")


class Source:
    def __init__(self, root, path, raw=None):
        self.raw = read_raw(root, path) if raw is None else raw
        self.path = path
        self.code, self.bare = blank(self.raw)
        self.lines = self.raw.split("\n")
        self.starts = [0] + [m.end() for m in re.finditer("\n", self.raw)]

    def line_of(self, pos):
        return bisect.bisect_right(self.starts, pos)

    def in_code(self, pos):
        """pos starts code, not a string"""
        return self.bare[pos] == self.code[pos]


def lua_files(root):
    for d in DIRS:
        folder = os.path.join(root, d)
        if not os.path.isdir(folder):
            sys.exit("no %s folder in %s: --root names the addon's folder" % (d, root))
        for name in sorted(os.listdir(folder)):
            if name.endswith(".lua"):
                yield d + "/" + name
    for path in feature_files(root):
        yield path


def classes(paths):
    """{path: (class, feature)} for the scanned files; the entries of OWN / SHARED / ENHANCERS no file answers"""
    out, missing = {}, []

    def put(entry, cls, feature):
        if entry.endswith("/*"):
            hits = [p for p in paths if p.startswith(entry[:-1])]
        else:
            hits = [entry] if entry in paths else []
        if not hits:
            missing.append("%s (%s)" % (entry, cls))
        for p in hits:
            if p in out:
                sys.exit("check_looks: %s is in two classes (%s and %s): fix the lists" % (p, out[p][0], cls))
            out[p] = (cls, feature)

    for f in SHARED:
        put(f, "SHARED", "")
    for feature, files in OWN.items():
        for f in files:
            put(f, "OWN", feature)
    for f in ENHANCERS:
        put(f, "ENHANCER", "")
    return out, missing


# --------------------------------------------------------------------------------------------------------- the families
LOCAL = re.compile(r"\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=(?!=)")
CLOSE = {"(": ")", "[": "]", "{": "}"}


def split_exprs(code, pos, limit=4000):
    """the expression list from pos: split at the commas outside brackets and strings, up to the statement's end (a
    line end or a ';' outside brackets)"""
    out, cur, stack, quote, i, end = [], [], [], None, pos, min(len(code), pos + limit)
    while i < end:
        ch = code[i]
        if quote:
            cur.append(ch)
            if ch == "\\":
                cur.append(code[i + 1:i + 2])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            cur.append(ch)
        elif ch in CLOSE:
            stack.append(CLOSE[ch])
            cur.append(ch)
        elif stack and ch == stack[-1]:
            stack.pop()
            cur.append(ch)
        elif not stack and ch in "\n;":
            break
        elif not stack and ch == ",":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    out.append("".join(cur))
    return [e.strip() for e in out]


def look_sources(path):
    """the expressions that are MelloUI.Look in this file"""
    found = {"MelloUI.Look", "ns.MelloUI.Look"}
    if path == "Core/Core.lua":
        found.add("self.Look")   # (Core.lua's methods: self is MelloUI)
    return found


def aliases_of(src):
    """the names this file binds to MelloUI.Look (`local Look = MelloUI.Look`, `local W, Look = x, MelloUI.Look`)"""
    sources, out = look_sources(src.path), set()
    for m in LOCAL.finditer(src.bare):
        eol = src.code.find("\n", m.end())
        if "Look" not in src.code[m.end():eol if eol >= 0 else len(src.code)]:
            continue   # (a binding names its source on its own line)
        names = [n.strip() for n in m.group(1).split(",")]
        for name, expr in zip(names, split_exprs(src.code, m.end())):
            if re.sub(r"\s+", "", expr) in sources:
                out.add(name)
    return out


ART_ARG = re.compile(r"\s*\(\s*([\"'])(\w+)\1")
ART_KEY = re.compile(r"\s*(?:\.\s*([A-Za-z_]\w*)|\[\s*([\"'])(\w+)\2\s*\])")


def table_keys(src, open_pos):
    """[(key, pos)] of the `key =` fields of the table constructor whose '{' is at open_pos (its own level only)"""
    out, depth, i, bare = [], 0, open_pos, src.bare
    field = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)")
    while i < len(bare):
        ch = bare[i]
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
            if depth == 0:
                break
        elif depth == 1 and (ch.isalpha() or ch == "_") and not (bare[i - 1].isalnum() or bare[i - 1] in "_."):
            m = field.match(bare, i)
            if m:
                out.append((m.group(1), i))
                i = m.end()
                continue
        i += 1
    return out


def family_api(src, hit):
    aliases = aliases_of(src)
    heads = [r"MelloUI\s*\.\s*Look", r"ns\s*\.\s*MelloUI\s*\.\s*Look"]
    if src.path == "Core/Core.lua":
        heads.append(r"self\s*\.\s*Look")
    heads += [re.escape(a) for a in sorted(aliases)]
    rx = re.compile(r"(?<![\w.:])(?:%s)\s*[.:]\s*([A-Za-z_]\w*)" % "|".join(heads))
    for m in rx.finditer(src.bare):
        key = m.group(1)
        if key == "Art":
            a = ART_ARG.match(src.code, m.end())
            if a and a.group(2) not in KEPT_ART:
                hit("api", m.start(), 'Look.Art("%s")' % a.group(2))
        elif key == "ART":
            a = ART_KEY.match(src.code, m.end())
            k = a and (a.group(1) or a.group(3))
            if k and k not in KEPT_ART:
                hit("api", m.start(), "Look.ART.%s" % k)
        elif key not in FINAL:
            hit("api", m.start(), "Look.%s (removed)" % key)
    for what, rx, word in IDENTIFIERS:
        for m in (rx.finditer(src.code) if word in src.code else ()):
            if src.in_code(m.start()):
                hit("api", m.start(), what)
    if src.path == "Core/GameLook.lua":
        for m in re.finditer(r"(?m)^[ \t]*function\s+Look\s*[.:]\s*([A-Za-z_]\w*)", src.bare):
            if m.group(1) not in FINAL:
                hit("api", m.start(1), "defines Look.%s" % m.group(1))
        for m in re.finditer(r"(?m)^[ \t]*Look\s*\.\s*([A-Za-z_]\w*)\s*=(?!=)\s*(\{)?", src.bare):
            if m.group(1) not in FINAL:
                hit("api", m.start(1), "defines Look.%s" % m.group(1))
            elif m.group(1) == "ART" and m.group(2):
                for key, pos in table_keys(src, m.start(2)):
                    if key not in KEPT_ART:
                        hit("api", pos, "Look.ART.%s" % key)
        for m in re.finditer(r"(?m)^[ \t]*Look\s*\.\s*ART\s*(?:\.\s*([A-Za-z_]\w*)|\[\s*([\"'])(\w+)\2\s*\])\s*=(?!=)",
                             src.code):
            key = m.group(1) or m.group(3)
            if key not in KEPT_ART and src.in_code(m.start()):
                hit("api", m.start(), "Look.ART.%s" % key)
        for m in re.finditer(r"(?m)^[ \t]*local\s+Look\s*=\s*(\{)", src.bare):
            for key, pos in table_keys(src, m.start(1)):
                if key not in FINAL:
                    hit("api", pos, "defines Look.%s" % key)


DEAD = "|".join(DEAD_AREAS)
TOPIC = re.compile(r"([\"'])look:(?:%s)\1" % DEAD)
DEAD_ISON = re.compile(r"\bKit\s*:\s*IsOn\s*\(\s*([\"'])(?:%s)\1" % DEAD)


def family_area(src, hit):
    for m in TOPIC.finditer(src.code):
        hit("area", m.start(), "the topic %s" % m.group(0))
    for m in DEAD_ISON.finditer(src.code):
        if src.in_code(m.start()):
            hit("area", m.start(), "Kit:IsOn of a dead area")
    if src.path != "Modules/Kit.lua":
        return
    at = src.bare.find("Kit.Areas = {}")
    lst = re.compile(r"\blocal\s+LIST\s*=\s*(\{)").search(src.bare, max(at, 0))
    if at >= 0 and lst:
        depth, i = 0, lst.start(1)
        while i < len(src.bare):   # (to the LIST constructor's own '}')
            if src.bare[i] in "({[":
                depth += 1
            elif src.bare[i] in ")}]":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        rx = re.compile(r"\b(module|switch|showcase)\s*=(?!=)")
        for m in rx.finditer(src.bare, lst.start(1), i + 1):
            hit("area", m.start(), "a Kit.Areas entry's `%s =`" % m.group(1))
    for m in re.finditer(r"\barea\s*\.\s*(module|switch|showcase)\b", src.bare):
        hit("area", m.start(), "reads area.%s" % m.group(1))


COVER = [
    ("Kit:IsOn(", re.compile(r"\bKit\s*:\s*IsOn\s*\(")),
    ("KitOn(", re.compile(r"\bKitOn\s*\(")),
    ("IsCovered(", re.compile(r"\bIsCovered\s*\(")),
    ("the bus's look: topics", re.compile(r"\bMelloUI\s*:\s*On\s*\(\s*([\"'])look:([^\"'\n]*)\1")),
    ('the bus\'s "cover"', re.compile(r"\bMelloUI\s*:\s*On\s*\(\s*([\"'])cover\1")),
    (":OnCover(", re.compile(r":\s*OnCover\s*\(")),
]


def family_cover(src, hit):
    for what, rx in COVER:
        for m in rx.finditer(src.code):
            if not src.in_code(m.start()):
                continue
            if what == "Kit:IsOn(" and DEAD_ISON.match(src.code, m.start()):
                continue   # (family 3's)
            if what == "the bus's look: topics" and m.group(2) in DEAD_AREAS:
                continue   # (family 3's)
            hit("cover", m.start(), what)


_MEMO = {}   # (path, class, text) -> one file's results (onelook/guard reruns the guard on copies a line apart)


def scan_file(root, path, kind):
    """one file: (src, {(family, path): [(line, what, text)]}, the unclassified line or None, escapes, hooks)"""
    raw = read_raw(root, path)
    key = (path, kind, raw)
    if key in _MEMO:
        return _MEMO[key]
    src = Source(root, path, raw)
    hits, escapes, hooks, unclassified = {}, [], [], None
    for n, text in (enumerate(src.lines, 1) if ESCAPE in raw or HOOK in raw else ()):
        if ESCAPE in text:
            escapes.append((path, n, text.strip()))
        if HOOK in text:
            hooks.append((path, n, text.strip()))

    def hit(family, pos, what):
        n = src.line_of(pos)
        text = src.lines[n - 1]
        if ESCAPE in text:
            return
        hits.setdefault((family, path), []).append((n, what, text.strip()))

    family_api(src, hit)
    if kind == "OWN" or path in ART_TOO:
        for m in ART_RX.finditer(src.code):
            hit("art", m.start(), m.group(0))
    family_area(src, hit)
    if kind == "OWN":
        family_cover(src, hit)
    for what, rx in (("a look-ok: marker", MARKER),
                     ("a game-look comment", PHRASES if kind == "OWN" or path in ART_TOO else None)):
        seen = set()
        for m in (rx.finditer(raw) if rx else ()):
            n = src.line_of(m.start())
            if n not in seen:   # (one per line)
                seen.add(n)
                hit("hygiene", m.start(), what)
    if kind is None:
        m = re.search(r"\bMelloUI\s*\.\s*Look\b", src.bare)
        if m:
            unclassified = src.line_of(m.start())
    _MEMO[key] = (src, hits, unclassified, escapes, hooks)
    return _MEMO[key]


def scan(root):
    """(hits, sources, classes, missing, unclassified, escapes, hooks); hits: {(family, path): [(line, what, text)]}"""
    paths = list(lua_files(root))
    cls, missing = classes(set(paths))
    hits, sources, unclassified, escapes, hooks = {}, {}, [], [], []
    for path in paths:
        src, mine, line, esc, hk = scan_file(root, path, cls.get(path, (None, ""))[0])
        sources[path] = src
        hits.update(mine)
        escapes += esc
        hooks += hk
        if line:
            unclassified.append((path, line))
    return hits, sources, cls, missing, unclassified, escapes, hooks


def counts_of(hits):
    order = {f: i for i, f in enumerate(FAMILIES)}
    return {"%s:%s" % key: len(rows) for key, rows in sorted(hits.items(), key=lambda kv: (order[kv[0][0]], kv[0][1]))}


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else ROOT
    hits, sources, cls, missing, unclassified, escapes, hooks = scan(root)
    counts = counts_of(hits)
    if "--counts" in argv:
        print("CEILINGS = {")
        for name, n in counts.items():
            print('    "%s": %d,' % (name, n))
        print("}")
        return 0
    where = "--where" in argv
    if "--list" in argv or where:
        print("The one look: what is left of the game look, by file (api, art, area and hygiene are leftovers; cover is "
              "the ratchet of Oldschool's cover branches in MelloUI's own parts)\n")
        print("  %-9s %-46s %5s %5s %5s %5s %7s" % ("class", "file", "api", "art", "area", "cover", "hygiene"))
        for path in sources:
            row = [counts.get("%s:%s" % (f, path), 0) for f in FAMILIES]
            if not any(row):
                continue
            print("  %-9s %-46s %5d %5d %5d %5d %7d" % ((cls.get(path, ("-",))[0], path) + tuple(row)))
            if where:
                for f in FAMILIES:
                    for n, what, text in sorted(hits.get((f, path), [])):
                        print("      %s:%d  [%s: %s]  %s" % (path, n, f, what, text[:110]))
        per = {}
        for path, (kind, _) in cls.items():
            per[kind] = per.get(kind, 0) + 1
        print("\n  scanned: %d files (%s; the rest: %d)" % (
            len(sources), ", ".join("%s %d" % kv for kv in sorted(per.items())), len(sources) - len(cls)))
        for entry in missing:
            print("  note: no file answers %s" % entry)
        print("\n  escape lines (%s):" % ESCAPE)
        for path, n, text in escapes:
            print("      %s:%d  %s" % (path, n, text[:110]))
        print("  oldschool-hook lines (%s, for stage I):" % HOOK)
        for path, n, text in hooks:
            print("      %s:%d  %s" % (path, n, text[:110]))
    over, lower = 0, []
    for name in sorted(set(counts) | set(CEILINGS), key=lambda k: (FAMILIES.index(k.split(":", 1)[0]), k)):
        n, ceiling = counts.get(name, 0), CEILINGS.get(name, 0)
        if n > ceiling:
            over += 1
            family, path = name.split(":", 1)
            print("FAIL  %s %d > ceiling %d" % (name, n, ceiling))
            for line, what, text in sorted(hits.get((family, path), [])):
                print("      %s:%d  [%s]  %s" % (path, line, what, text[:100]))
            print("      the one look: %s" % INSTEAD[family])
        elif n < ceiling:
            lower.append((name, ceiling, n))
    for path, line in unclassified:
        print("FAIL  unclassified: %s names MelloUI.Look (line %d): put it in OWN, SHARED or ENHANCERS in "
              "Tools/lint/check_looks.py" % (path, line))
    for family in FAMILIES:
        mine = {name: n for name, n in counts.items() if name.startswith(family + ":")}
        risen = sum(1 for name, n in mine.items() if n > CEILINGS.get(name, 0))
        print("%-5s %-8s %4d in %d files%s" % ("over" if risen else "ok", family, sum(mine.values()), len(mine),
                                              "   (Oldschool's handshakes in own parts: until stage I)"
                                              if family == "cover" else ""))
    for name, ceiling, n in lower:
        print('lower CEILINGS["%s"] from %d to %d in Tools/lint/check_looks.py: the gain is kept' % (name, ceiling, n))
    left = sum(n for name, n in counts.items() if not name.startswith("cover:"))
    cover = sum(n for name, n in counts.items() if name.startswith("cover:"))
    print("one look: %d leftovers, %d cover branches, %d over their ceiling, %d to lower, %d unclassified"
          % (left, cover, over, len(lower), len(unclassified)))
    return 1 if over or unclassified else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
