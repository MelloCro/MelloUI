"""The English lines the configurator and the installer draw: the keys of MelloUI's language tables (docs/plans/
languages.md; Core.lua's Languages section). Two sources:

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

    from strings import collect
    lines = collect(root)   -> [(english, where)], each line once, in the order found

Lines that are no prose (an id, a path, a number, a font object's name) are left out (Prose). Tools never ship.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(TOOLS, "lint"))

# the configurator's and the installer's own code: file -> the text tables whose every string is a line
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
}
# a section of a file the windows never draw (the slash commands' chat output, the probes): left out
SKIP_FROM = {
    "Core/Config.lua": "-- Slash commands",
}
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
    body, out, i = lit[1:-1], [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            d = body[i + 1]
            if d.isdigit():
                j = i + 1
                while j < len(body) and j < i + 4 and body[j].isdigit():
                    j += 1
                out.append(chr(int(body[i + 1:j])))
                i = j
                continue
            out.append(ESC.get(d, d))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


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


def Prose(s):
    """A line a player reads: letters, and either a space or a capital first letter; never an id, a path, a font
    object, a frame point or a colour code alone."""
    if not s or not re.search(r"[^\W\d_]", s):
        return False
    t = s.strip()
    if not t or PATHLIKE.search(t) and " " not in t:
        return False
    if t.startswith(("http://", "https://")) and " " not in t:
        return False
    if t.startswith("/"):                                   # a slash command: the same in every language
        return False
    if " " not in t:
        if t.isupper() or "_" in t:                        # LEFT, OVERLAY, PLAYER_LOGIN, ui-hud-atlas_names
            return False
        if not t[0].isupper():                              # ids: "config", "page", "unitframe"
            return False
        if re.match(r"^(Game|System|Number|Chat|Quest)Font", t) or re.match(r"^[A-Z][a-z]+[A-Z]\w*$", t):
            return False                                    # GameFontNormal, CamelCase ids (MelloUIConfigFrame)
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
    # a stack of open brackets: ("call", name, argindex) | ("table", fieldname-or-None, tablename-or-None)
    stack = []
    table_of = []   # the text table each open "{" belongs to (name or None), inherited inward
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
            stack.append(["table", None, 1])
        elif kind == "op" and text in ")}":
            if stack:
                top = stack.pop()
                if top[0] == "table" and table_of:
                    table_of.pop()
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
                if field and field.split(".")[-1] in FIELDS:
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
