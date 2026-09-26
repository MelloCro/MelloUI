"""Ratchet on the copy-paste the streamline audit found (2026-09-24).

Each check counts one duplication pattern in Core/*.lua and Modules/*.lua
(comments left out) against a ceiling kept below: the count on the day the
check came in. A count may only go down. The script fails when one goes UP,
which means a new copy of something a shared system already does (the rule
is one system per job: every window, the game's or MelloUI's own, uses the
same shared systems), and names the shared system to use instead. When a
count goes DOWN it passes and prints the ceiling to lower, so the gain is
kept.

    python Tools/lint/check_panels.py              all checks (exit 1 on a rise)
    python Tools/lint/check_panels.py --list NAME  every match of one check
    python Tools/lint/check_panels.py --counts     today's counts as CEILINGS
    ... --root DIR                                 another copy of the addon

Plain Python 3, no packages. The Lint workflow (.github/workflows/lint.yml)
runs it on every push beside luacheck.
"""
import bisect
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DIRS = ("Core", "Modules")

# The ceilings: today's counts (wave 3 of the hardening release, 2026-09-25;
# the own-window shell and the widget set of the configurator build,
# 2026-09-26, start at 0). Lower one when the script says so; never raise
# one to make a copy pass.
CEILINGS = {
    "replace-fn": 51,
    "follow-fn": 15,
    "later-pending": 0,
    "portrait-759": 5,
    "medallion-to-ring": 6,
    "fit-icon-rim": 13,
    "border-listener": 15,
    "secret-helper": 0,
    "plain-helper": 0,
    "self-hook": 0,
    "dump-slash": 57,
    "start-moving": 1,
    "animation-group": 4,
    "new-ticker": 9,
    "combat-guard": 1,
    "safe-standin": 0,
    "fn-standin": 0,
    "shared-standin": 23,
    "table-walk": 337,
    "addon-loaded": 33,
    "window-single": 10,
    "direct-sound": 0,
    "palette-guard": 6,
    "colour:Core/Core.lua": 2,
    "colour:Core/Config.lua": 0,
    "colour:Core/Widgets.lua": 0,
    "colour:Modules/KitWindow.lua": 0,
    "colour:Core/Installer.lua": 0,
    "colour:Core/InstallerWindow.lua": 0,
    "colour:Modules/Chat.lua": 24,
    "colour:Modules/DynamicUI.lua": 8,
    "colour:Modules/QuestListMap.lua": 4,
    "colour:Modules/QuestListPanel.lua": 8,
    "colour:Modules/QuestTracker.lua": 10,
    "colour:Modules/Route.lua": 2,
    "colour:Modules/Services.lua": 3,
    "colour:Modules/Stats.lua": 1,
    "colour:Modules/UIModifications.lua": 13,
    "colour:Modules/VoiceOver.lua": 9,
}

# Kit.lua from this line on is the kit demo and the slice test (/kitdemo,
# /kitwhat, /mellokit): developer windows, not the addon's own
KIT_DEMO = ("Modules/Kit.lua", "-- /kitdemo [scale]: one window with every block")

# name: (pattern, where, instead). where: None (every file), or a dict with
#   only  a list of files, or a regex the path must match
#   skip  files left out
#   demo  True: Kit.lua's demo region left out
CHECKS = {
    "replace-fn": (r"^local function Replace\(", None,
                   "a panel's own Replace: Kit:Replace with the panel's skin (one shared panel skin is audit rank 15)"),
    "follow-fn": (r"^local function Follow\(", None,
                  "a panel's own Follow: the kit's rep follows its region itself (one shared Follow is audit rank 15)"),
    "later-pending": (r"laterPending", None,
                      "a hand-made next-frame coalescer: Kit:NextFrame(key, fn), fn bound once"),
    "portrait-759": (r"SetSize\(w \* 0\.759", None,
                     "an inline portrait fit: Kit:FitPortrait"),
    "medallion-to-ring": (r"MEDALLION_TO_RING *=", {"skip": ["Modules/Kit.lua"]},
                          "a copy of the kit's medallion ratio: Kit:FitPortrait / the kit's own constant"),
    "fit-icon-rim": (r"^local function FitIconRim\(", None,
                     "a panel's own icon-rim fit: Kit:SlotStone / the kit's rim helpers"),
    "border-listener": (r'OnBorderChanged\("button"', None,
                        "one more Button Border listener per panel: Kit:SlotStone refits on the border itself"),
    "secret-helper": (r"local function (?:Secret|IsSecret)\(|local (?:Secret|IsSecret)\s*=\s*function\b", None,
                      "an own secret test: MelloUI.Safe.IsSecret (Core.lua)"),
    "plain-helper": (r"local function Plain\(", None,
                     "an own Plain: MelloUI.Safe.Value / .Number / .Text (Core.lua)"),
    "self-hook": (r"hooksecurefunc\((?:MelloUI|Kit|MelloUI\.Kit)\s*,", None,
                  "a hook on MelloUI's own methods: the settings bus, MelloUI:On(topic, fn, owner)"),
    "dump-slash": (r"SLASH_MELLO\w*DUMP1", None,
                   "one more /xxdump command: a mode of the shared dump (Kit:DumpWindow)"),
    "start-moving": (r"StartMoving", {"skip": ["Core/Core.lua", "Modules/UIModifications.lua"], "demo": True},
                     "a window dragging itself: MelloUI:RegisterMover (Core.lua) and the position store"),
    "animation-group": (r"CreateAnimationGroup", {"skip": ["Core/Anim.lua"]},
                        "a raw AnimationGroup: MelloUI.Anim (Anim:PlayGroup, Reduce Motion aware)"),
    "new-ticker": (r"NewTicker\(", {"skip": ["Core/Perf.lua"]},
                   "one more ticker: an event, Kit:NextFrame or a shared job"),
    "combat-guard": (r"if Kit\.WhenOutOfCombat then|Kit and Kit\.WhenOutOfCombat", None,
                     "a guard around Kit:WhenOutOfCombat: the kit is always loaded, call it"),
    "safe-standin": (r"MelloUI\.Safe and MelloUI\.Safe\.", None,
                     "a stand-in for MelloUI.Safe: bind it plainly, `local Secret = MelloUI.Safe.IsSecret`"),
    "fn-standin": (r"or function\(v\)", None,
                   "a stand-in body: bind MelloUI.Safe plainly (Core.lua loads first)"),
    "shared-standin": (r"Perf\.Shared or function", None,
                       "a stand-in for Perf.Shared: every Perf:Scope has it (scope.Shared)"),
    "table-walk": (r"\{ *\S+:Get(?:Regions|Children)\(\) *\}", None,
                   "a table made per walk: select('#', frame:GetRegions()) and select(i, ...)"),
    "addon-loaded": (r'RegisterEvent\("ADDON_LOADED"\)', {"only": r"^Modules/\w+Panel\.lua$"},
                     "one more private ADDON_LOADED frame: name the addon in the registry's window.addon "
                     "(one shared load hook is audit rank 15)"),
    "window-single": (r'NineSlice[^\n]*prefix = "window/single"', None,
                      "a hand-set frame prefix: Kit.framePrefix (the kit's frame family, set with its tuning)"),
    # any call of PlaySound, whatever its argument (a conditional one too), and
    # PlaySound handed on as a value (pcall(PlaySound, ...)). None is kept:
    # the notice's chimes are PlayUISound kinds too (0.13.7)
    "direct-sound": (r"\bPlaySound\s*\(|[(,]\s*PlaySound\s*[,)]", {"skip": ["Core/Core.lua"]},
                     "a UI sound played directly: MelloUI:PlayUISound(kind) (Core.lua), so Custom Sounds sees it"),
    # the guard, and a literal fallback behind a palette colour
    "palette-guard": (r"MelloUI\.Palette and |Palette\.\w+\s+or\s*\{", None,
                      "a guard or a fallback on MelloUI.Palette: it is defined in Core.lua, which loads first"),
}

# Own windows: MelloUI's windows, whose colours come from the palette only
# (WINDOW-RULES, Own windows). A numeric colour literal is a colour call with
# three number literals (the white 1, 1, 1 reset apart) or a { r, g, b }
# table of three numbers 0..1, at least one with a fraction.
OWN_WINDOWS = [key.split(":", 1)[1] for key in CEILINGS if key.startswith("colour:")]

# The one exempt line: shell:Anchor's texture in the own-window shell, the
# only invisible anchor an own window has (an alpha-0 solid handed to
# Kit:Replace where a widget has no region of its own; WINDOW-RULES 6). It
# is exempt by its marker comment, in that file only, and only while the
# marker stands on ONE line there: a second marked line makes both count.
EXEMPT = {"Modules/KitWindow.lua": "-- ratchet-ok: the shell's invisible anchor"}


def exempt_line(src):
    """the line number the file's marker exempts, or None"""
    marker = EXEMPT.get(src.path)
    if not marker:
        return None
    marked = [i + 1 for i, text in enumerate(src.raw.split("\n")) if marker in text]
    return marked[0] if len(marked) == 1 else None
NUM = r"(-?\d*\.?\d+)"
COLOUR_CALL = re.compile(r"\b(?:SetColorTexture|SetTextColor|SetVertexColor|SetBackdropColor|SetBackdropBorderColor"
                         r"|SetShadowColor|SetStatusBarColor|CreateColor)\(\s*" + NUM + r"\s*,\s*" + NUM + r"\s*,\s*" + NUM)
COLOUR_TABLE = re.compile(r"\{\s*" + NUM + r"\s*,\s*" + NUM + r"\s*,\s*" + NUM + r"\s*\}")

# comments out, strings and line numbers kept
TOKEN = re.compile(r"""
    --\[(?P<ceq>=*)\[.*?\](?P=ceq)\]     # a long comment
  | --[^\n]*                             # a line comment
  | \[(?P<seq>=*)\[.*?\](?P=seq)\]       # a long string
  | "(?:\\.|[^"\\\n])*"?                 # a quoted string
  | '(?:\\.|[^'\\\n])*'?
""", re.S | re.X)


def strip_comments(src):
    def keep(m):
        text = m.group(0)
        if text.startswith("--"):
            return "\n" * text.count("\n")
        return text
    return TOKEN.sub(keep, src)


def lua_files(root):
    for d in DIRS:
        folder = os.path.join(root, d)
        if not os.path.isdir(folder):
            sys.exit("no %s folder in %s: --root names the addon's folder" % (d, root))
        for name in sorted(os.listdir(folder)):
            if name.endswith(".lua"):
                yield d + "/" + name


class Source:
    def __init__(self, root, path):
        with open(os.path.join(root, path), encoding="utf-8") as fh:
            self.raw = fh.read().replace("\r\n", "\n")
        self.path = path
        self.code = strip_comments(self.raw)
        self.starts = [0] + [i + 1 for i, c in enumerate(self.code) if c == "\n"]
        self.demo_from = None
        if path == KIT_DEMO[0]:
            i = self.raw.find(KIT_DEMO[1])
            if i >= 0:
                self.demo_from = self.raw.count("\n", 0, i) + 1

    def line_of(self, pos):
        return bisect.bisect_right(self.starts, pos)

    def line_text(self, n):
        return self.raw.split("\n")[n - 1].strip()


def applies(where, src):
    if not where:
        return True
    only = where.get("only")
    if only and not re.search(only, src.path):
        return False
    return src.path not in where.get("skip", ())


def matches(name, sources):
    """[(path, line)] of every match of one check"""
    found = []
    if name.startswith("colour:"):
        path = name.split(":", 1)[1]
        src = sources.get(path)
        if src is None:
            return found
        skip = exempt_line(src)
        for m in COLOUR_CALL.finditer(src.code):
            if not all(float(v) == 1 for v in m.groups()):
                found.append((path, src.line_of(m.start())))
        for m in COLOUR_TABLE.finditer(src.code):
            vals = [float(v) for v in m.groups()]
            if all(0 <= v <= 1 for v in vals) and any(v != int(v) for v in vals):
                found.append((path, src.line_of(m.start())))
        return sorted(hit for hit in found if hit[1] != skip)
    pattern, where = CHECKS[name][0], CHECKS[name][1]
    rx = re.compile(pattern, re.M)
    for src in sources.values():
        if not applies(where, src):
            continue
        for m in rx.finditer(src.code):
            line = src.line_of(m.start())
            if where and where.get("demo") and src.demo_from and line >= src.demo_from:
                continue
            found.append((src.path, line))
    return sorted(found)


def instead(name):
    if name.startswith("colour:"):
        return ("a colour literal in an own window: MelloUI.Palette (Core.lua), a key painted with W.Paint / "
                "Kit:Paint; an invisible anchor is shell:Anchor (Modules/KitWindow.lua)")
    return CHECKS[name][2]


def main(argv):
    root = argv[argv.index("--root") + 1] if "--root" in argv else ROOT
    sources = {path: Source(root, path) for path in lua_files(root)}
    if "--list" in argv:
        name = argv[argv.index("--list") + 1]
        if name not in CEILINGS:
            print("no check named %r; the checks: %s" % (name, ", ".join(CEILINGS)))
            return 2
        for path, line in matches(name, sources):
            print("%s:%d: %s" % (path, line, sources[path].line_text(line)))
        return 0
    counts = {name: len(matches(name, sources)) for name in CEILINGS}
    if "--counts" in argv:
        print("CEILINGS = {")
        for name, n in counts.items():
            print('    "%s": %d,' % (name, n))
        print("}")
        return 0
    rises, lower = 0, []
    for name, ceiling in CEILINGS.items():
        n = counts[name]
        if n > ceiling:
            rises += 1
            print("FAIL  %-34s %4d > ceiling %d" % (name, n, ceiling))
            print("      use instead: %s" % instead(name))
            per = {}
            for path, _ in matches(name, sources):
                per[path] = per.get(path, 0) + 1
            print("      in: " + ", ".join("%s %d" % (p, c) for p, c in sorted(per.items())))
            print("      every match: python Tools/lint/check_panels.py --list %s" % name)
        elif n < ceiling:
            lower.append((name, ceiling, n))
            print("ok    %-34s %4d   (ceiling %d)" % (name, n, ceiling))
        else:
            print("ok    %-34s %4d" % (name, n))
    for name, ceiling, n in lower:
        print('lower CEILINGS["%s"] from %d to %d in Tools/lint/check_panels.py: the gain is kept' % (name, ceiling, n))
    print("%d checks, %d over their ceiling, %d to lower" % (len(CEILINGS), rises, len(lower)))
    return 1 if rises else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
