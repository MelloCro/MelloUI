"""The English lines MelloUI's windows draw through its translation: the keys of MelloUI's language tables (docs/plans/
languages.md; Core.lua's Languages section). Three sources:

  the running addon   every module's title, description and flavour; its options' name, desc, hint, wide, text,
                      choices (values: label, tooltip) and an include's own rows; Core/ConfigLayout.lua's groups,
                      pages (title, flavour, tabs, switch, picker), its sections and every R / Link line's own texts
                      (name, wide, when lines, also); MelloUI.Lang.TEXT. Read by loading the addon's files in the lupa
                      world Tools/lint/check_new_tags.py uses (its loader and OnInit run), so a schema made in code is
                      read as the configurator reads it.
  the windows' code   the string literals the configurator's and the installer's own code draws (FILES): the fields
                      of their text tables (TEXT, CHANGELOG ...: TABLES), the label fields of any table (FIELDS), and
                      the arguments of the calls that draw text (CALLS: W.Button's text, W.Header's, BarTip's, a
                      Lang.T / Lang.F ...). Adjacent literals joined by `..` are one line.
  every other window  (2.1.64) every Lua file the addon loads: the literals handed to a translation -- W.Tr, Lang.T,
                      Lang.F, a file's own name or function for one, a builder that translates (W.Button's text, a
                      row's label ...), MelloUI:Confirm's fields -- and the text tables, constants and fields handed to
                      one (`W.Tr(TEXT.sell)`: all of TEXT). See drawn(), above its rules.

    from strings import collect
    lines = collect(root)   -> [(english, where)], each line once, in the order found
    InCode(root, texts)     -> {english: file} of those texts still a literal in the addon's code (languages.py keeps
                               their translations live: a text the code reaches through data at run time)

Lines that are no prose (an id, a path, a number, a font object's name) are left out (Prose), and so is chat output
(MelloUI:Print, the copy window's dumps, Config.lua's slash commands: SKIP_FROM). Tools never ship.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(TOOLS, "lint"))

# the configurator's and the installer's own code: file -> the text tables whose every string is a line ("*": every
# literal of the file, a page's data file)
FILES = {
    "Core/Config.lua": ("TEXT", "CHANGELOG", "LINKS", "COMMANDS", "EDIT_LAYOUT", "PREVIEW", "PROFILES_META",
                        "HOME_FLAVOUR", "AREAS_REFUSED", "PROMPT", "HELP_NOTE", "NEW_LINE", "SETUP_LABELS"),
    "Core/Installer.lua": ("TEXT", "SETUPS", "STEPS"),
    "Core/InstallerWindow.lua": ("TEXT", "STEPS", "SETUPS", "REVIEW"),
    # (the parchment areas: the installer's Parchment step lists them by their labels)
    "Modules/UIModifications.lua": ("PARCHMENTS", "PARCHMENT_DESC"),
    "MelloUI_Oldschool/Modules/UIModificationsPainted.lua": ("SHEET_FIRST", "SHEETS_AFTER", "SHEET_DESC",
                                                             "CHARACTER_PARCHMENT"),
    "Core/Widgets.lua": ("TEXT", "NEW", "SHARED"),
    "Core/ConfigPreview.lua": ("TEXT",),
    "Modules/KitWindow.lua": (),
    "MelloUI_GroupFrames/GroupDesignerPage.lua": ("TEXT",),
    # (the designers' stages and the pages' own lists: their states' and indicators' labels)
    "Modules/ActionButtons.lua": ("TEXT",),
    "Modules/Nameplates.lua": ("TEXT",),
    "MelloUI_GroupFrames/GroupFrames.lua": (),
    # (1.2.4, an-06: the Level Up Card's window draws its texts through Tr)
    "Core/LevelCard.lua": (),
    # (2.1.55: the role picker's box and its on-screen lines)
    "Modules/RolePicker.lua": ("TEXT",),
    # (2.1.59: the mailbox's recipients; 2.1.62: its panel beside Send Mail, its title and its list)
    "Modules/MailRecipients.lua": ("TEXT",),
    # (2.1.64: the Addons page's own list -- what MelloUI does with each addon, its links, its jobs, the rows of what
    # it changed -- drawn by Core/AddonsPage.lua from this file: "*", every literal of the file)
    "Core/Integrations.lua": "*",
    # (2.1.64: lists other files draw -- the Spell Groups page's groups and orders, GroupSpellGroupsPage.lua; the map's
    # town marks' kinds, its layer menu)
    "MelloUI_GroupFrames/GroupSpellGroups.lua": (),
    "MelloUI_Map/MapTownMarks.lua": (),
}
# a section of a file the windows never draw (the slash commands' chat output, the probes): left out
SKIP_FROM = {
    "Core/Config.lua": "-- Slash commands",
}
# (a page's data file, FILES "*") the fields whose string is an id, never a line: a key, an option's id, a folder
IDS = {"key", "id", "folders", "folder", "url", "group", "arrow", "icon", "global", "addon", "kind", "type", "event"}
# fields whose string is a line wherever they stand
FIELDS = {"name", "desc", "text", "title", "label", "tip", "tooltip", "hint", "flavour", "line", "accept", "cancel",
          "heading", "noun", "wide", "note", "body", "lead", "switchLabel", "switchDesc", "default", "question", "tag"}
# calls whose argument at the position (1-based) is a line; "*" every argument
CALLS = {
    "T": "*", "Tr": "*", "Lang.T": "*", "Lang.F": (1,), "MelloUI.Lang.T": "*", "MelloUI.Lang.F": (1,),
    "W.Button": (2,), "W.Header": (3,), "W.Tag": (2,), "W.Text": (3,), "Text": (3,), "W.ShowTooltip": (2, 3, 4),
    "BarTip": (2, 3), "PageTip": (2, 3), "SetText": (1,), "AddLine": (1,), "MelloUI:Print": (1,),
    "MelloUI:Announce": (1,), "W.ToggleRow": (3, 4, 5), "W.SliderRow": (3, 4, 5), "W.DropdownRow": (3, 4, 5),
    "W.ButtonRow": (3, 4, 5, 6), "W.Row": (4, 5, 6), "W.LinkRow": (3,), "W.Card": (), "string.format": (1,),
    "Stage.Part": (2,), "CardHeading": (2,), "add": (2,),
}
# calls whose literals are lines whatever they look like (a marked text: "IMPORTANT")
MARKED = {"T", "Tr", "Lang.T", "Lang.F", "MelloUI.Lang.T", "MelloUI.Lang.F"}

TOKEN = re.compile(r"""
    (?P<comment>--\[(?P<eq>=*)\[.*?\](?P=eq)\]|--[^\n]*)
  | (?P<long>\[(?P<eq2>=*)\[.*?\](?P=eq2)\])
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<concat>\.\.)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*(?:\s*[.:]\s*[A-Za-z_][A-Za-z0-9_]*)*)
  | (?P<num>\d+(?:\.\d+)?)
  | (?P<op>[(){}\[\],=;+\-*/%#<>~^])
  | (?P<ws>\s+)
  | (?P<other>.)
""", re.S | re.X)

ESC = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
       "\n": "\n"}


def unquote(lit):
    # (2026-10-30: a decimal escape is one byte, as Lua reads it -- "\226\128\186" is the UTF-8 of one "›", never three
    # Latin-1 letters -- so the line is gathered as bytes and read as UTF-8 at the end)
    body, out, i = lit[1:-1], bytearray(), 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            d = body[i + 1]
            if d.isdigit():
                j = i + 1
                while j < len(body) and j < i + 4 and body[j].isdigit():
                    j += 1
                out.append(int(body[i + 1:j]) & 0xFF)
                i = j
                continue
            out += ESC.get(d, d).encode("utf-8")
            i += 2
            continue
        out += c.encode("utf-8")
        i += 1
    return out.decode("utf-8", errors="replace")


def tokens(src):
    for m in TOKEN.finditer(src):
        kind = m.lastgroup
        if kind in ("ws", "comment", "eq", "eq2"):
            continue
        text = m.group(kind)
        if kind == "name":
            text = re.sub(r"\s+", "", text)
        yield kind, text, m.start()


PATHLIKE = re.compile(r"[\\/]|^\||\.(lua|tga|blp|ttf|ogg|mp3)$", re.I)
# a slash command and its arguments ("/sfx play <name>", "/mello profile ...", "/vo stop | pause | skip"): the same in
# every language. A sentence that opens with one ("/mellobug's report now shows ...") is a line a player reads.
# (2.1.64: any number of arguments -- "/mello preview solo | party | raid | stop", Core/Preview.lua's usage)
SLASH = re.compile(r"^/[a-z]+(?: (?:[a-z]+|<[a-z]+>|\||\.\.\.))*$")
# a format's placeholders and colour codes ("/ %d": a slash and a count, the same in every language -- while "%s: %s"
# is a line: "%s : %s" in French, "%s：%s" in Chinese)
NOT_WORDS = re.compile(r"%(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?[sdfgixXc]|\|c[0-9a-fA-F]{8}|\|r")


def Prose(s):
    """A line a player reads: letters, and either a space or a capital first letter; never an id, a path, a font
    object, a frame point or a colour code alone."""
    if not s or not re.search(r"[^\W\d_]", s):
        return False
    t = s.strip()
    if t.startswith("/") and not re.search(r"[^\W\d_]", NOT_WORDS.sub("", t)):
        return False
    if not t or PATHLIKE.search(t) and " " not in t:
        return False
    if t.startswith(("http://", "https://")) and " " not in t:
        return False
    if SLASH.match(t):
        return False
    if " " not in t:
        if t.isupper() or "_" in t:                        # LEFT, OVERLAY, PLAYER_LOGIN, ui-hud-atlas_names
            return False
        if not t[0].isupper():                              # ids: "config", "page", "unitframe"
            return False
        if re.match(r"^(Game|System|Number|Chat|Quest)Font", t) or re.match(r"^[A-Z][a-z]+[A-Z]\w*$", t):
            return False                                    # GameFontNormal, CamelCase ids (MelloUIConfigFrame)
        if re.match(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$", t):
            return False                                    # an option's id: BagWindow.columns
    return True


def literals(path, rel, tables=()):
    """[(text, line no)] of the file's lines in their contexts (above)."""
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    stop = SKIP_FROM.get(rel)
    if stop and stop in src:
        src = src[:src.index(stop)]
    toks = list(tokens(src))
    out = []
    whole = tables == "*"
    tables = () if whole else tables
    # a stack of open brackets: ("call", name, argindex) | ("table", fieldname-or-None, tablename-or-None)
    stack = []
    table_of = []   # the text table each open "{" belongs to (name or None), inherited inward
    field_of = []   # the field each open "{" is the value of (`folders = {`; None)
    i, n = 0, len(toks)
    pending_field = None
    while i < n:
        kind, text, pos = toks[i]
        prev = toks[i - 1] if i > 0 else (None, None, 0)
        if kind == "op" and text == "(":
            name = prev[1] if prev[0] == "name" else None
            stack.append(["call", name, 1])
        elif kind == "op" and text == "{":
            # the table's own name: `NAME = {` / `local NAME = {` / a field `key = {`
            name = None
            if prev[1] == "=" and i >= 2 and toks[i - 2][0] == "name":
                name = toks[i - 2][1].split(".")[-1]
            inherited = table_of[-1] if table_of else None
            table_of.append(name if name in tables else inherited)
            field_of.append(name)
            stack.append(["table", None, 1])
        elif kind == "op" and text in ")}":
            if stack:
                top = stack.pop()
                if top[0] == "table" and table_of:
                    table_of.pop()
                    field_of.pop()
        elif kind == "op" and text == ",":
            if stack and stack[-1][0] == "call":
                stack[-1][2] += 1
        elif kind in ("str", "long"):
            # the whole constant: "a" .. "b" .. "c" (a constant joined with anything else is skipped)
            parts, j = [unquote(text) if kind == "str" else text[text.index("[", 1) + 1:text.rindex("]", 0, -1)]], i
            dynamic = False
            while j + 2 < n and toks[j + 1][1] == ".." and toks[j + 2][0] == "str":
                parts.append(unquote(toks[j + 2][1]))
                j += 2
            if j + 1 < n and toks[j + 1][1] == "..":
                dynamic = True
            if i >= 1 and toks[i - 1][1] == "..":
                dynamic = True
            value = "".join(parts)
            line = src.count("\n", 0, pos) + 1
            take = False
            marked = False
            if not dynamic:
                # its context: a field (`key = "..."`), a text table's entry, a call's argument, a top-level constant
                field = toks[i - 2][1] if i >= 2 and prev[1] == "=" and toks[i - 2][0] == "name" else None
                # (a call's argument: Global("Offhand"), pcall(LibStub, "AceAddon-3.0"); never `or (a and "x")`)
                in_call = stack and stack[-1][0] == "call" and stack[-1][1] not in KEYWORDS | {None}
                own = field or (field_of[-1] if stack and stack[-1][0] == "table" and field_of else None)
                if whole and not in_call:                     # a page's data file: all of it but its ids
                    take = prev[1] != "[" and (own or "").split(".")[-1] not in IDS
                elif field and field.split(".")[-1] in FIELDS:
                    take = True
                elif field and field.split(".")[-1] in tables:           # local HOME_FLAVOUR = "..."
                    take = True
                elif table_of and table_of[-1]:
                    take = True
                elif stack and stack[-1][0] == "call":
                    fn = stack[-1][1] or ""
                    want = CALLS.get(fn) or CALLS.get(fn.split(":")[-1] if ":" in fn else None)
                    if want == "*" or (want and stack[-1][2] in want):
                        take = True
                        marked = fn in MARKED
            # (a marked literal is a line whatever it looks like -- "installed", "IMPORTANT" -- unless it is the
            # other side of a comparison: `key == "hud"`)
            compared = prev[1] == "=" and i >= 2 and toks[i - 2][1] in ("=", "~", "<", ">")
            if take and not compared and (Prose(value) or (marked and re.search(r"[^\W\d_]{2}", value))):
                out.append((value, line))
            i = j
        i += 1
    return out


# ---------------------------------------------------------------------------------------------------------------
# Every other window (2.1.64; pull request #62 ran `write` on frFR and ~1,650 live French lines went stale): the bags,
# the map, the chat, Edit Layout, the Quest List ... draw their texts through the same translation, from files FILES
# never named. Not a list of files but a rule over every Lua file the addon loads (its TOC and the feature folders'):
# a line is a literal handed to a translation --
#   a translator: W.Tr, MelloUI.Widgets.Tr, Lang.T, Lang.F (TRANSLATORS), a file's own name for one (`local Tr =
#       MelloUI.Widgets.Tr`) and a file's own function that hands a parameter to one (Services' F, BagWindow's F,
#       Notice's Tr: TranslatorsOf), at that parameter's place;
#   a shared builder that passes its texts through W.Tr (DRAWN: W.Button's text, a row's label, hint and desc ...) and
#       the fields of a call's table it draws (DRAWN_FIELDS: MelloUI:Confirm's text, accept, cancel);
#   or any literal of a text table or a constant one of those is handed (`W.Tr(TEXT.title)`, `W.Button(f, TEXT.sell)`,
#       `W.Tr(KIND[v].note)`, `W.Tr(d)` of `for _, d in ipairs(DIETS)`: the whole TEXT, KIND and DIETS tables;
#       `W.Tr(IGNORE_ASK)`, `W.Tr(short)`: that constant's or variable's value), and of a field read through one
#       (`Tr(kind.label)`: every `label = "..."` of the file).
# Never MelloUI:Print's line nor MelloUI:ShowText's title: chat output and the copy window's dumps (a slash command's
# answer, a probe's, /melloperf's report) are no window text, though both hand them to the translation. A text the
# code reaches only through data at run time (`W.Tr(pin.data.title)` of Media/QuestListData.lua's transports) is not
# found here: languages.py keeps a translation whose English the addon's code still has (InCode) rather than turn it
# stale.

TRANSLATORS = {"W.Tr", "MelloUI.Widgets.Tr", "Widgets.Tr", "Lang.T", "Lang.F", "MelloUI.Lang.T", "MelloUI.Lang.F"}
DRAWN = {
    "W.Text": (3,), "W.Header": (3,), "W.Tag": (2,), "W.Button": (2,), "W.ShowTooltip": (2, 3, 4),
    "W.Row": (4, 5, 6), "W.ToggleRow": (3, 4, 5), "W.SliderRow": (3, 4, 5), "W.DropdownRow": (3, 4, 5),
    "W.ButtonRow": (3, 4, 5, 6), "MelloUI:Announce": (1,), "MelloUI:AnnounceWait": (1,),
}
DRAWN_FIELDS = {
    "MelloUI:Confirm": {"text", "accept", "cancel", "label"},
    "W.Card": {"title", "text"},
    "W.Dropdown": {"label"}, "W.DropdownRow": {"label"},
}
KEYWORDS = {"and", "or", "not", "return", "if", "elseif", "while", "until", "in", "then", "do", "local", "else",
            "repeat", "function", "nil", "true", "false", "end", "for", "break"}
FUNC = re.compile(r"^([ \t]*)(?:local[ \t]+)?(?:function[ \t]+([\w.:]+)[ \t]*|([\w.]+)[ \t]*=[ \t]*function[ \t]*)"
                  r"\(([^)]*)\)(.*)$", re.M)
ALIAS = re.compile(r"^[ \t]*(?:local[ \t]+)?([\w.]+(?:[ \t]*,[ \t]*[\w.]+)*)[ \t]*=[ \t]*([\w.:]+(?:[ \t]*,[ \t]*"
                   r"[\w.:]+)*)[ \t]*(?:--.*)?$", re.M)


def TranslatorsOf(src):
    """{name: "*" | {positions}} of the file's own translators: a name given a translator (`local Tr = W.Tr`) and a
    function that hands its parameter to one (positions 1-based, as called; a method's `self` not counted)."""
    found = {n: "*" for n in TRANSLATORS}
    funcs, closers = [], {}
    for m in FUNC.finditer(src):
        indent, name, params, rest = m.group(1), m.group(2) or m.group(3), m.group(4), m.group(5)
        start = m.end()
        if re.search(r"\bend\s*$", rest):                 # one line: local function Tr(s) return W.Tr(s) end
            body = rest
        else:
            if indent not in closers:
                closers[indent] = re.compile(r"^" + re.escape(indent) + r"end\b", re.M)
            close = closers[indent].search(src, start)
            body = src[start:close.start() if close else len(src)]
        funcs.append((name, [p.strip() for p in params.split(",") if p.strip()], body))
    changed = True
    while changed:
        changed = False
        for m in ALIAS.finditer(src):
            names = [x.strip() for x in m.group(1).split(",")]
            values = [x.strip() for x in m.group(2).split(",")]
            for n, v in zip(names, values):
                if found.get(v) == "*" and found.get(n) != "*":
                    found[n] = "*"
                    changed = True
        # (the names each body hands a translator first: one pattern a pass)
        handed = re.compile(r"(?<![\w.:])(?:%s)\s*\(\s*([A-Za-z_]\w*)\b"
                            % "|".join(re.escape(n) for n in sorted(found, key=len, reverse=True)))
        for name, params, body in funcs:
            key = (":" + name.split(":")[-1]) if ":" in name else name
            have = found.get(key)
            if have == "*":
                continue
            want = set(have or ())
            first = set(handed.findall(body))
            for k, p in enumerate(params, 1):
                if p != "..." and p in first:
                    want.add(k)
            if want and want != set(have or ()):
                found[key] = want
                changed = True
    return found


def drawn(path, rel):
    """[(text, line no)] of a file's literals handed to a translation (the rule above)."""
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    stop = SKIP_FROM.get(rel)
    if stop and stop in src:
        src = src[:src.index(stop)]
    found = TranslatorsOf(src)
    toks = list(tokens(src))
    n = len(toks)

    def spec_of(name):
        if not name:
            return None
        if name in found:
            return found[name]
        if ":" in name and (":" + name.split(":")[-1]) in found:
            return found[":" + name.split(":")[-1]]
        return DRAWN.get(name)

    def value_at(i):
        """the whole constant at token i ("a" .. "b"), its last token, and whether it is joined with anything else"""
        kind, text = toks[i][0], toks[i][1]
        parts, j = [unquote(text) if kind == "str" else text[text.index("[", 1) + 1:text.rindex("]", 0, -1)]], i
        while j + 2 < n and toks[j + 1][1] == ".." and toks[j + 2][0] == "str":
            parts.append(unquote(toks[j + 2][1]))
            j += 2
        dynamic = (j + 1 < n and toks[j + 1][1] == "..") or (i >= 1 and toks[i - 1][1] == "..")
        return "".join(parts), j, dynamic

    def plain(i):
        """not a key (`["x"] =`) and not the other side of a comparison (`key == "hud"`)"""
        if i >= 1 and toks[i - 1][1] == "[":
            return False
        return not (i >= 2 and toks[i - 1][1] == "=" and toks[i - 2][1] in ("=", "~", "<", ">"))

    out, names, fields_drawn = [], set(), set()
    # a name that stands for an entry of a table: `for _, d in ipairs(DIETS)`, `local kind = KINDS[key]`
    bound = {}
    for i in range(n - 3):
        if toks[i][1] == "for":
            j, vars_ = i + 1, []
            while j < n and toks[j][0] == "name" and toks[j][1] != "in":
                vars_.append(toks[j][1])
                j += 2 if j + 1 < n and toks[j + 1][1] == "," else 1
            if (j + 3 < n and toks[j][1] == "in" and toks[j + 1][1] in ("ipairs", "pairs") and toks[j + 2][1] == "("
                    and toks[j + 3][0] == "name" and vars_):
                bound[vars_[-1]] = toks[j + 3][1].replace(":", ".").split(".")[-1]
        elif (toks[i][1] == "local" and toks[i + 1][0] == "name" and toks[i + 2][1] == "=" and i + 4 < n
              and toks[i + 3][0] == "name" and toks[i + 4][1] == "["):
            bound[toks[i + 1][1]] = toks[i + 3][1].replace(":", ".").split(".")[-1]
    # pass 1: the literals handed to a translation, and the names of the tables and constants handed to one
    stack = []   # ["call", name, argindex] | ["group", translated, marked] | ["table", fields]

    def here():
        if not stack:
            return False, False, None
        top = stack[-1]
        if top[0] == "call":
            spec = spec_of(top[1])
            if spec == "*":
                return True, True, None
            return bool(spec and top[2] in spec), False, None
        if top[0] == "group":
            return top[1], top[2], None
        return False, False, top[1]

    i = 0
    while i < n:
        kind, text, pos = toks[i]
        prev = toks[i - 1] if i > 0 else (None, None, 0)
        if kind == "op" and text == "(":
            if prev[0] == "name" and prev[1] not in KEYWORDS:
                stack.append(["call", prev[1], 1])
            else:
                t, m, _ = here()
                stack.append(["group", t, m])
        elif kind == "op" and text == "{":
            fields = None
            if stack and stack[-1][0] == "call":
                fields = DRAWN_FIELDS.get(stack[-1][1])
            elif stack and stack[-1][0] == "table":
                fields = stack[-1][1]
            stack.append(["table", fields])
        elif kind == "op" and text in ")}":
            if stack:
                stack.pop()
        elif kind == "op" and text == ",":
            if stack and stack[-1][0] == "call":
                stack[-1][2] += 1
        elif kind == "name" and text not in KEYWORDS and not (i + 1 < n and toks[i + 1][1] == "("):
            translated, _, _ = here()
            if translated:
                parts = text.replace(":", ".").split(".")
                if i + 1 < n and toks[i + 1][1] == "[":
                    names.add(parts[-1])                      # TEXT[kind], KIND[v].note
                elif len(parts) > 1:
                    names.add(parts[-2])                      # TEXT.sell, M.TEXT.sell
                    if not parts[-2][:1].isupper():
                        fields_drawn.add(parts[-1])           # kind.label: every label = "..." of the file
                else:
                    names.add(parts[0])                       # IGNORE_ASK
                if parts[0] in bound:
                    names.add(bound[parts[0]])                # d of ipairs(DIETS): DIETS
        elif kind in ("str", "long"):
            value, j, dynamic = value_at(i)
            if not dynamic and plain(i):
                translated, marked, fields = here()
                field = toks[i - 2][1] if i >= 2 and prev[1] == "=" and toks[i - 2][0] == "name" else None
                take = translated or bool(fields and field in fields)
                if take and (Prose(value) or (marked and re.search(r"[^\W\d_]{2}", value))):
                    out.append((value, src.count("\n", 0, pos) + 1))
            i = j
        i += 1
    # pass 2: every literal of those tables (a name with a capital: TEXT, KIND, Fake.WHAT), of those constants and
    # variables' values (`local IGNORE_ASK = "..."`; `local short = plan.short == "bags" and "Not all of it fits." or
    # nil` given to a W.Tr(short)) and of the fields read through a translation (kind.label: `label = "..."`)
    tables = {x for x in names if x[:1].isupper()}
    depth, inside, parens = [], 0, 0     # depth: per open "{", whether it opened a text table
    assigned = None                      # the name a statement (outside any bracket) gives its value to

    def last(t):
        return t.replace(":", ".").split(".")[-1]

    for i in range(n):
        kind, text, pos = toks[i]
        prev = toks[i - 1] if i > 0 else (None, None, 0)
        if kind == "op" and text == "{":
            name = last(toks[i - 2][1]) if prev[1] == "=" and i >= 2 and toks[i - 2][0] == "name" else None
            mine = name in tables
            depth.append(mine)
            inside += mine
        elif kind == "op" and text == "}":
            if depth:
                inside -= depth.pop()
        elif kind == "op" and text in "()":
            parens = max(0, parens + (1 if text == "(" else -1))
        elif kind == "op" and text == "=" and not depth and not parens:
            if prev[1] not in ("=", "~", "<", ">") and not (i + 1 < n and toks[i + 1][1] == "="):
                assigned = last(prev[1]) if prev[0] == "name" else None
        elif kind == "name" and text in KEYWORDS - {"and", "or", "not", "nil", "true", "false"} and not depth:
            assigned = None
        elif kind in ("str", "long") and plain(i):
            value, _, dynamic = value_at(i)
            if dynamic:
                continue
            field = last(toks[i - 2][1]) if prev[1] == "=" and i >= 2 and toks[i - 2][0] == "name" else None
            value_of = assigned in names and not depth and not parens   # (a statement's value, never a field's)
            if (inside or value_of or field in fields_drawn) and Prose(value):
                out.append((value, src.count("\n", 0, pos) + 1))
    return out


def addon_files(root):
    """Every Lua file the addon loads: MelloUI.toc's and each feature folder's TOC's (never the language files)."""
    import features
    toc = []
    if os.path.isfile(os.path.join(root, "MelloUI.toc")):     # (a test's small addon may have none)
        with open(os.path.join(root, "MelloUI.toc"), encoding="utf-8-sig") as fh:
            toc = [line.strip().replace("\\", "/") for line in fh.read().split("\n")]
    out = [f for f in toc if f.endswith(".lua")] + features.feature_files(root)
    return [f for f in dict.fromkeys(out) if os.path.isfile(os.path.join(root, f))]


def InCode(root, wanted):
    """{english: file} of the texts of `wanted` that stand as a literal in the code the addon loads -- languages.py
    keeps a translation whose English is still there (reached through data at run time, past the rule above; a word
    Lang.F looks up: "on") rather than turn it stale."""
    out = {}
    wanted = set(wanted)
    if not wanted:
        return out
    for rel in addon_files(root):
        with open(os.path.join(root, rel), encoding="utf-8") as fh:
            src = fh.read()
        toks = list(tokens(src))
        for i, (kind, text, _) in enumerate(toks):
            if kind not in ("str", "long"):
                continue
            # (each literal, and the constant it opens: "a" .. "b")
            s = unquote(text) if kind == "str" else text[text.index("[", 1) + 1:text.rindex("]", 0, -1)]
            found = [s]
            j = i
            while j + 2 < len(toks) and toks[j + 1][1] == ".." and toks[j + 2][0] == "str":
                s += unquote(toks[j + 2][1])
                j += 2
                found.append(s)
            for s in found:
                if s in wanted and s not in out:
                    out[s] = rel
    return out


def runtime(root):
    """[(text, where)] from the running addon (the lupa world of check_new_tags)."""
    import check_new_tags as C
    import lupa.lua51 as L51
    IW, BW = C.lua_world()
    root = root.replace("\\", "/").rstrip("/") + "/"
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(IW.PRELUDE)
    loadf = lua.eval(C.LOADF)
    compile_only = lua.eval(C.COMPILE)
    ns = lua.eval("{}")
    with open(root + "Core/Core.lua", encoding="utf-8") as fh:
        e = loadf(fh.read(), "@Core/Core.lua", ns)
    if e:
        raise RuntimeError("Core/Core.lua does not load: %s" % e)
    lua.execute(BW.AFTER_CORE)
    lua.execute(C.AFTER_REGISTRY)
    with open(root + "MelloUI.toc", encoding="utf-8-sig") as fh:
        toc = [line.strip().replace("\\", "/") for line in fh.read().split("\n")]
    errs = {}
    for f in [line for line in toc if line.endswith(".lua") and line != "Core/Core.lua"] + C.feature_files(root):
        lua.globals().CURRENT_FILE = f
        try:
            with open(root + f, encoding="utf-8") as fh:
                src = fh.read()
        except FileNotFoundError:
            continue
        e = compile_only(src, "@" + f) if f == "Core/Perf.lua" else loadf(src, "@" + f, ns)
        if e:
            errs[f] = e
    if errs:
        raise RuntimeError("files do not load:\n" + "\n".join("  %s: %s" % (k, v[:200]) for k, v in sorted(errs.items())))
    init = lua.execute(C.INIT_ALL)
    if init:
        raise RuntimeError("module OnInit failed:\n" + str(init))
    rows = lua.execute(COLLECT)
    return [(rows[i][1], rows[i][2]) for i in range(1, len(rows) + 1)]


COLLECT = r'''
local M = _G.MelloUI
local out, seen = {}, {}
local function S(s, where)
  if type(s) == "string" and s ~= "" and not seen[s] then seen[s] = true; out[#out + 1] = { s, where } end
end
local FIELDS = { "name", "desc", "hint", "text", "wide", "label", "tooltip", "title", "flavour", "noun", "line",
  "heading", "switchLabel", "switchDesc" }
local function Opt(o, where, depth)
  if type(o) ~= "table" or depth > 4 then return end
  for _, k in ipairs(FIELDS) do S(rawget(o, k), where) end
  local v = rawget(o, "values")
  if type(v) == "table" then
    for _, e in ipairs(v) do
      -- (`own`: a name shown as it is in every language -- a font face's)
      if type(e) == "table" and not rawget(e, "own") then S(rawget(e, "label"), where); S(rawget(e, "tooltip"), where) end
    end
  end
end
for _, name in ipairs(M.moduleOrder or {}) do
  local m = M.modules[name]
  S(rawget(m, "title"), name); S(rawget(m, "desc"), name); S(rawget(m, "flavour"), name)
  -- (a folded feature's and a kit panel's own label and line: the installer's Features and Windows steps)
  for _, sub in ipairs({ "tweak", "window" }) do
    local t = rawget(m, sub)
    if type(t) == "table" then S(rawget(t, "label"), name); S(rawget(t, "desc"), name) end
  end
  for _, o in ipairs(type(m.options) == "table" and m.options or {}) do
    Opt(o, name, 1)
    if type(o) == "table" and o.type == "include" then
      for _, k in ipairs(type(o.keys) == "table" and o.keys or {}) do if type(k) == "table" then Opt(k, name, 2) end end
    end
  end
end
local L = M.ConfigLayout
if L then
  for _, s in ipairs(L.SECTIONS or {}) do S(s, "ConfigLayout") end
  for _, g in ipairs(L.groups or {}) do S(g.title, "ConfigLayout") end
  local keys = {}
  for key in pairs(L.pages or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  -- (a page's whole definition: the designers' elements and parts -- their labels, lines and locked notes)
  local WALK = { title = true, flavour = true, label = true, line = true, locked = true, desc = true, noun = true,
    tip = true, switchLabel = true, switchDesc = true, name = true, heading = true }
  local function Walk(t, depth, seenT)
    if type(t) ~= "table" or depth > 8 or seenT[t] then return end
    seenT[t] = true
    for k, v in pairs(t) do
      if type(v) == "string" and WALK[k] then S(v, "ConfigLayout") elseif type(v) == "table" then Walk(v, depth + 1, seenT) end
    end
  end
  for _, key in ipairs(keys) do Walk(L.pages[key], 1, {}) end
  for _, key in ipairs(keys) do
    local p = L.pages[key]
    S(p.title, "ConfigLayout"); S(p.flavour, "ConfigLayout"); S(p.switchLabel, "ConfigLayout"); S(p.switchDesc, "ConfigLayout")
    for _, t in ipairs(p.tabs or {}) do S(type(t) == "table" and (t.label or t.name) or t, "ConfigLayout") end
    if type(p.picker) == "table" then
      S(p.picker.label, "ConfigLayout"); S(p.picker.noun, "ConfigLayout")
      for _, pk in ipairs(p.picker.picks or {}) do S(pk.label, "ConfigLayout"); S(pk.desc, "ConfigLayout") end
    end
  end
  local function When(w)
    if type(w) ~= "table" then return end
    S(w.line, "ConfigLayout")
    for _, k in ipairs({ "any", "all" }) do for _, p in ipairs(w[k] or {}) do When(p) end end
  end
  local ok, err = pcall(L.Define, function(page, tab, section, what, extra)
      S(tab, "ConfigLayout"); S(section, "ConfigLayout")
      if type(extra) == "table" then
        S(extra.name, "ConfigLayout"); S(extra.wide, "ConfigLayout"); S(extra.plus, "ConfigLayout"); When(extra.when)
        S(extra.card, "ConfigLayout")
        if type(extra.sharedWith) == "table" then for _, n in ipairs(extra.sharedWith) do S(n, "ConfigLayout") end end
        if type(extra.also) == "table" then for _, t in pairs(extra.also) do S(t, "ConfigLayout") end end
        if type(extra.whenFor) == "table" then for _, w in pairs(extra.whenFor) do When(w) end end
      end
    end, function(page, tab, section, target, label, extra)
      S(label, "ConfigLayout"); if type(extra) == "table" then When(extra.when) end
    end)
  if not ok then error("ConfigLayout's Define failed: " .. tostring(err)) end
end
if M.Lang and M.Lang.TEXT then for _, v in pairs(M.Lang.TEXT) do S(v, "Language") end end
return out
'''


def collect(root):
    """[(english, where)]: the running addon's lines first, then the windows' code; each line once."""
    seen, out = set(), []

    def add(s, where):
        if s not in seen and Prose(s):
            seen.add(s)
            out.append((s, where))

    for s, where in runtime(root):
        add(s, where)
    for rel, tables in FILES.items():
        path = os.path.join(root, rel)
        if os.path.isfile(path):
            for s, line in literals(path, rel, tables):
                if s not in seen and s.strip():
                    seen.add(s)
                    out.append((s, "%s:%d" % (rel, line)))
    # (2.1.64) every other window's lines: the literals handed to a translation, in the files the addon loads
    for rel in addon_files(root):
        for s, line in drawn(os.path.join(root, rel), rel):
            if s not in seen and s.strip():
                seen.add(s)
                out.append((s, "%s:%d" % (rel, line)))
    return out


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=os.path.dirname(TOOLS))
    ap.add_argument("--from", dest="only", help="only the lines whose source starts with this")
    a = ap.parse_args()
    lines = collect(a.root)
    for s, where in lines:
        if not a.only or where.startswith(a.only):
            print("%s\t%s" % (where, s.replace("\n", "\\n")))
    print("%d lines, %d characters" % (len(lines), sum(len(s) for s, _ in lines)), file=sys.stderr)
