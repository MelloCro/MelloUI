"""Ratchet on the copy-paste the streamline audit found (2026-09-24).

Each check counts one duplication pattern in Core/*.lua and Modules/*.lua
(comments left out) against a ceiling kept below: the count on the day the
check came in. A count may only go down. The script fails when one goes UP,
which means a new copy of something a shared system already does (the rule
is one system per job: every window, the game's or MelloUI's own, uses the
same shared systems), and names the shared system to use instead. When a
count goes DOWN it passes and prints the ceiling to lower, so the gain is
kept.

Five more (0.15.0, 2026-09-28) count the seeds of the Gamepad UI freezes:
MelloUI code that writes the game's own menu, popup, layout or map-pool
state, or opens and closes the game's panels with no Gamepad UI check. With
the Gamepad UI on, the game's gamepad code then runs in MelloUI's execution:
a protected call is blocked, and the map's per-frame work is billed to
MelloUI's script time. They start at 0 (panel-call came down from 1 with
the Quest Tracker's right-click, 0.15.0).

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
# 2026-09-26, start at 0; 0.14.0's round 3: the hand-made shade partners, the
# screen-rect copies, Core/Shade.lua and the round's new files, and the
# meaning colours counted apart; the final round: Backup, CentreText and
# KitShade at 0). Lower one when the script says so; never
# raise one to make a copy pass.
CEILINGS = {
    "replace-fn": 50,
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
    "start-moving": 0,
    "animation-group": 3,
    "new-ticker": 9,
    "combat-guard": 1,
    "safe-standin": 0,
    "fn-standin": 0,
    "shared-standin": 23,
    "table-walk": 337,
    "addon-loaded": 33,
    "window-single": 9,
    "direct-sound": 0,
    "palette-guard": 0,
    "direct-shadow": 2,
    "screen-rect-copy": 5,
    "window-createframe": 0,
    "colour:Core/Core.lua": 1,
    "colour:Core/Backup.lua": 0,
    "colour:Core/CentreText.lua": 0,
    "colour:Core/Config.lua": 0,
    # the configurator rebuild (0.15.0): its layout data and its live preview
    # start at 0; Modules/DynamicUI.lua went with it
    "colour:Core/ConfigLayout.lua": 0,
    "colour:Core/ConfigPreview.lua": 0,
    "colour:Core/Widgets.lua": 0,
    "colour:Core/Shade.lua": 0,
    "colour:Core/Reminders.lua": 0,
    "colour:Modules/KitShade.lua": 0,
    "colour:Modules/KitWindow.lua": 0,
    "colour:Modules/ActionBarPanel.lua": 0,
    "colour:Modules/CastBarPanel.lua": 0,
    "colour:Core/Installer.lua": 0,
    "colour:Core/InstallerWindow.lua": 0,
    "colour:Modules/Chat.lua": 0,
    "colour:Modules/QuestListMap.lua": 0,
    "colour:Modules/QuestListPanel.lua": 0,
    "colour:Modules/QuestListTips.lua": 0,
    "colour:Modules/QuestTracker.lua": 0,
    "colour:Modules/Reminders.lua": 0,
    "colour:Modules/Restock.lua": 0,
    "colour:Modules/Route.lua": 0,
    "colour:Modules/Services.lua": 0,
    "colour:Modules/Stats.lua": 0,
    "colour:Modules/UIModifications.lua": 0,
    "colour:Modules/VoiceOver.lua": 0,
    "colour:Modules/WidgetPanel.lua": 0,
    "meaning:Modules/Chat.lua": 17,
    "meaning:Modules/VoiceOver.lua": 0,
    # the Gamepad UI freeze fix (0.15.0): 0 each (the tracker's right-click
    # to the quest on the map got its Gamepad UI check)
    "blizz-menu-button": 0,
    "blizz-popup": 0,
    "blizz-layout-field": 0,
    "panel-call": 0,
    "map-pool-call": 0,
    # Edit Layout (0.15.0): its three new files start at 0; its one key frame
    # and the secure buttons in their three homes
    "colour:Core/EditLayout.lua": 0,
    "colour:Core/EditLayoutMovers.lua": 0,
    "colour:Core/EditLayoutSnap.lua": 0,
    "key-propagate": 0,
    "secure-button": 0,
}

# Kit.lua from this line on is the kit demo and the slice test (/kitdemo,
# /kitwhat, /mellokit): developer windows, not the addon's own
KIT_DEMO = ("Modules/Kit.lua", "-- /kitdemo [scale]: one window with every block")

# The Gamepad UI checks' names: the game's panel openers, its popup
# functions (every one shows, hides, queues or defines a popup, or reads the
# popups the game shows: MelloUI asks in its own dialog), the fields the
# game's Layout reads, and the Gamepad UI test a panel call must follow
PANEL_CALLS = r"ShowUIPanel|HideUIPanel|OpenAllBags|CloseAllBags|ToggleGameMenu|QuestMapFrame_Open\w*"
POPUP_CALLS = r"StaticPopup_\w+"
LAYOUT_FIELDS = r"layoutIndex|topPadding|bottomPadding|leftPadding|rightPadding"
GAMEPAD_GUARD = r"\bGamepadUI\s*\(\s*\)"


def ref(names):
    """one of `names` as code names it: bare or after a dot or colon (Name,
    _G.Name, frame:Name), or as a string key (_G["Name"], frame['Name']). A
    name in any other string is none: a text, or hooksecurefunc("Name", ...)
    (the `bare` switch)"""
    return r"(?:\b(?:%s)\b|\[\s*[\"'](?:%s)[\"']\s*\])" % (names, names)


def handed_on(value):
    """`value` handed on (to pcall, a timer, ...), bare or looked up in a
    table (_G.Name, _G["Name"]); a type() test is no hand-on"""
    return r"(?<!type)(?<!type )\(\s*[\w.]*(?:%s)\s*[,)]|,\s*[\w.]*(?:%s)\s*[,)]" % (value, value)


# the game menu's AddButton, as a method (a local AddButton is MelloUI's own)
MENU_ADD = r"(?:[:.]AddButton\b|\[\s*[\"']AddButton[\"']\s*\])"


# name: (pattern, where, instead). where: None (every file), or a dict with
#   only  a list of files, or a regex the path must match
#   skip  files left out
#   unless  regexes: a file whose code (comments out) matches one is left out
#   demo  True: Kit.lua's demo region left out
#   bare  True: a match that starts inside a string is passed over (a name in
#         a text, or hooksecurefunc("Name", ...), is no call; a string key,
#         _G["Name"], starts at its bracket and counts)
#   guard  a regex: a match with a guard before it, in the innermost function
#          around it, is passed over (Source.guarded)
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
    "start-moving": (r"StartMoving", {"skip": ["Core/Core.lua"], "demo": True},
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
    # a shade partner made by hand, outside the kit and its shade system
    # (0.14.0: the nameplates' and the Route arrow's are the two left)
    "direct-shadow": (r"Kit:Shadow(?:Nine)?\(", {"skip": ["Modules/Kit.lua", "Modules/KitShade.lua"]},
                      "a partner made by hand: Kit:ShadeElement(root, area):Add(...) (Modules/KitShade.lua), which "
                      "keeps the area switches, the strength and the per-frame budget"),
    # a screen rect read by hand: GetRect in a pcall, then the same region's
    # effective scale within the next few lines (0.14.0: the hit tests and
    # the other sums that read the two are what is left)
    "screen-rect-copy": (r"pcall\((\w+)\.GetRect, \1\)(?:[^\n]*\n){0,4}?[^\n]*\b\1[:.]GetEffectiveScale", None,
                         "a screen rect read by hand: MelloUI.Safe.ScreenRect(region) (Core.lua), the one "
                         "screen-rect reader (left, bottom, right, top, or nil)"),
    # the game's CreateFrame called by a file that dresses a game window
    # (0.14.0: with the Gamepad UI on, the game's navigation walks a whole
    # open window for each frame made in it, in MelloUI's script time). A
    # file that binds Core's maker once is passed over; so is a HUD panel
    # (its registry entry's tab = "HUD": no window the navigation opens)
    "window-createframe": (r"\bCreateFrame\(",
                           {"only": r"^Modules/(\w+Panel|Kit|KitShade|QuestInk|QuestListMap|Route|VoiceOver"
                                    r"|UIModifications)\.lua$",
                            "unless": [r"^local CreateFrame = MelloUI\.Safe\.CreateFrame\b", r'\btab = "HUD"']},
                           "the game's CreateFrame in a file that dresses a window: bind Core's maker once at the "
                           "top, `local CreateFrame = MelloUI.Safe.CreateFrame` (Core.lua), which makes a frame "
                           "inside an open window without the game's gamepad navigation walking that window"),
    # the Gamepad UI freeze fix (0.15.0); each name also counts written as a
    # string key (ref). An entry added to the game's own menu (a method call,
    # or the method handed on as a value): AddButton writes the menu's layout
    # and button list, which its gamepad close reads
    "blizz-menu-button": (MENU_ADD + r"\s*\(|" + handed_on(r"[\w.]+" + MENU_ADD), {"bare": True},
                          "an entry in the game's own menu: MelloUI's own entry, MelloUIGameMenuButton "
                          "(Core/Config.lua), an own button under UIParent shown from "
                          "HookScript(GameMenuFrame, \"OnShow\") and never in the Gamepad UI"),
    # any of the game's popup functions called from MelloUI code (a call, or
    # the function handed on), and any use of the game's popup table: the
    # generic confirmations, the queue and AddDefinition end in
    # StaticPopup_Show too, and a hide runs the popup's gamepad close
    "blizz-popup": (ref(POPUP_CALLS) + r"\s*\(|" + handed_on(ref(POPUP_CALLS)) + "|" + ref("StaticPopupDialogs"),
                    {"bare": True},
                    "a game popup from MelloUI code: the own dialog, MelloUI:Confirm({ text, accept, cancel, "
                    "onAccept, onCancel }) (Modules/KitWindow.lua); with the Gamepad UI on a game popup runs the "
                    "game's popup and binding code in MelloUI's execution"),
    # a write of a field the game's Layout reads, on any frame (dot or
    # bracket form; a comparison is no write)
    "blizz-layout-field": (r"\.(?:%s)\s*=(?!=)|\[\s*[\"'](?:%s)[\"']\s*\]\s*=(?!=)" % (LAYOUT_FIELDS, LAYOUT_FIELDS),
                           {"bare": True},
                           "a layout field of the game's frames written by MelloUI: an own frame under UIParent, "
                           "placed by MelloUI (as the own menu entry, MelloUIGameMenuButton in Core/Config.lua)"),
    # a game panel opened or closed from MelloUI code (a call, or the
    # function handed on to pcall or a timer) with no MelloUI.Safe.GamepadUI()
    # check before it in the same function. A check in a function around it
    # does not count: a handler or a timer made there runs later, when the
    # Gamepad UI may have been turned on
    "panel-call": (ref(PANEL_CALLS) + r"\s*\(|" + handed_on(ref(PANEL_CALLS)),
                   {"bare": True, "guard": GAMEPAD_GUARD},
                   "a game panel opened or closed from MelloUI code with no Gamepad UI check: test "
                   "MelloUI.Safe.GamepadUI() (Core.lua) first, in the same function, and in the Gamepad UI leave "
                   "the window to the player (say what to do with MelloUI:Announce)"),
    # Edit Layout's keyboard (0.15.0): the one key frame, its keys propagated
    # but Esc and the arrows (spec 2.13)
    "key-propagate": (r"SetPropagateKeyboardInput|EnableKeyboard\(", {"skip": ["Core/EditLayout.lua"]},
                      "a keyboard handler: Edit Layout's key frame is MelloUI's only one (Core/EditLayout.lua)"),
    # secure buttons: the reminders' overlay, the tracker's item button, Edit
    # Layout's two Edit Mode buttons (0.15.0)
    "secure-button": (r"SecureActionButtonTemplate",
                      {"skip": ["Core/Reminders.lua", "Modules/QuestTracker.lua", "Core/EditLayoutBridge.lua"]},
                      "a secure button: made lazily out of combat, laid by rect on UIParent, one click phase "
                      "(Core/Reminders.lua's Attach / OverlayPlace, Core/EditLayoutBridge.lua)"),
    # the map's pin pool used from any file but the Quest List's marks: each
    # pool call marks the map's scroll state dirty from MelloUI code
    "map-pool-call": (ref(r"AcquirePin|RemovePin|RemoveAllPinsByTemplate|MarkCanvasDirty"),
                      {"bare": True, "skip": ["Modules/QuestListMap.lua"]},
                      "the map's pin pool outside the Quest List's marks (Modules/QuestListMap.lua, which "
                      "keep out of it in the Gamepad UI): MelloUI's own layer on the map canvas, as Route "
                      "draws its line"),
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


# The user's meaning colours (2026-09-26: the chat channels' tints and the
# Voice Over picture's state colours stay fixed under every palette). In an
# own window that has a `meaning:<file>` ceiling, a literal on a line marked
# with MEANING_MARK counts there instead of under `colour:<file>`: the two
# are held apart, so a new palette colour cannot hide among the meaning
# ones, and one more meaning colour raises its own count (the user's word
# first). In a file with no `meaning:` ceiling the mark changes nothing.
MEANING_MARK = "(meaning colour)"
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


def strip_comments(src, blank=False):
    """blank: strings too, each character a space (the newlines kept), so the
    result lines up with the plain strip character for character"""
    def keep(m):
        text = m.group(0)
        if text.startswith("--"):
            return "\n" * text.count("\n")
        if blank:
            return re.sub(r"[^\n]", " ", text)
        return text
    return TOKEN.sub(keep, src)


# the words that open and close a Lua block: function, if, do (for and while
# open theirs with do) and repeat open one; end and until close one
BLOCK_WORD = re.compile(r"\b(function|if|do|repeat|end|until)\b")


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
        self.bare = strip_comments(self.raw, blank=True)
        self._functions = None
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

    def functions(self):
        """[(start, end)] of every function in the file, by start"""
        if self._functions is None:
            stack, spans = [], []
            for m in BLOCK_WORD.finditer(self.bare):
                if m.group(1) in ("end", "until"):
                    if stack:
                        word, at = stack.pop()
                        if word == "function":
                            spans.append((at, m.end()))
                else:
                    stack.append((m.group(1), m.start()))
            self._functions = sorted(spans)
        return self._functions

    def guarded(self, pos, guard):
        """True when `guard` matches the code that runs on the way to pos: from
        the start of the innermost function around pos up to pos, the
        functions that end before pos left out (their code runs elsewhere). A
        guard after the call, in another function, or in a function around
        this one (it ran when this one was made, not when it runs) does not
        count; at the file's top level the top level is looked at."""
        spans = self.functions()
        around = [a for a, b in spans if a <= pos < b]
        i = max(around) if around else 0
        code = []
        for a, b in spans:
            if a >= i and b <= pos:
                code.append(self.bare[i:a])
                i = b
        code.append(self.bare[i:pos])
        return re.search(guard, "".join(code)) is not None


def applies(where, src):
    if not where:
        return True
    only = where.get("only")
    if only and not re.search(only, src.path):
        return False
    # a file whose source holds one of these is passed over whole
    for rx in where.get("unless", ()):
        if re.search(rx, src.code, re.M):
            return False
    return src.path not in where.get("skip", ())


def matches(name, sources):
    """[(path, line)] of every match of one check"""
    found = []
    if name.startswith("colour:") or name.startswith("meaning:"):
        kind, path = name.split(":", 1)
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
        found = sorted(hit for hit in found if hit[1] != skip)
        if "meaning:" + path not in CEILINGS:
            return found if kind == "colour" else []
        lines = src.raw.split("\n")
        return [hit for hit in found if (MEANING_MARK in lines[hit[1] - 1]) == (kind == "meaning")]
    pattern, where = CHECKS[name][0], CHECKS[name][1] or {}
    rx = re.compile(pattern, re.M)
    for src in sources.values():
        if not applies(where, src):
            continue
        for m in rx.finditer(src.code):
            line = src.line_of(m.start())
            if where.get("demo") and src.demo_from and line >= src.demo_from:
                continue
            if where.get("bare") and src.bare[m.start()] != src.code[m.start()]:
                continue
            if where.get("guard") and src.guarded(m.start(), where["guard"]):
                continue
            found.append((src.path, line))
    return sorted(found)


def instead(name):
    if name.startswith("colour:"):
        return ("a colour literal in an own window: MelloUI.Palette (Core.lua), a key painted with W.Paint / "
                "Kit:Paint; an invisible anchor is shell:Anchor (Modules/KitWindow.lua)")
    if name.startswith("meaning:"):
        return ("one more fixed meaning colour (a line marked %s): only with the user's word (the chat "
                "channels' tints and the Voice Over states stay fixed); any other colour is a MelloUI.Palette key"
                % MEANING_MARK)
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
