"""The New tags' release check (the user's rule, 2026-09-26: "every new Dropdown menu, every new slider, every new
checkbox etc needs to get a "New" tag for people to easly navigate to that option to test it out in the
Configurator, every next update, the old "New" tags are being removed and reapplied to the new stuff").

An option names the update it came with (`new = "X.Y.Z"`, docs/WINDOW-RULES.md section 6) and the configurator
tags it New while that update runs. This check compares every option of the tree with the previous release's:

  schema options   every module's `options` as the configurator lays them (after UI Modifications has filled
                   its registry rows and every module's OnInit has run: Reminders lays Restock's rows), read by
                   loading the addon's files in a lupa world on the installer tools' stand-ins
                   (Tools/installer/world.py), for the tree and for the previous release's files (git archive).
                   An option is its declaring module and its key ("Tweaks.centreTextShade"), or its name when it
                   has no key ("Restock:Restock List"), and its kind: a key whose kind changed (a switch become a
                   dropdown) is a new option. A module is "module:<Name>"; a NEW module with a page of its own
                   and no option of its own tagged needs its registry `new` (its page title and side-list entry).
                   A file that does not load, or a module's OnInit that fails, stops the check (exit 2): the
                   options it would have laid cannot be counted. An option in MOVED was a control of another kind
                   in the previous release (0.15.0: Dynamic UI Modification's own rows of 0.14.0, now UI
                   Modifications' definitions) and counts as existing.
  own rows         the configurator's own controls (Core/Config.lua: Home, the Profiles page, the top bar),
                   found where they are built: a control builder's call (W.ToggleRow, W.SliderRow, W.DropdownRow,
                   W.ButtonRow, W.Switch, W.Dropdown, W.Slider, W.Button) named by its label (a string, or a field
                   the file spells out once, as TEXT's `switch = "..."`) or, for a bare control, its parent; a
                   CreateFrame("Button" | "CheckButton" | "EditBox" | "Slider" | "DropdownButton") named by the
                   text it is given (`x:SetText("Load")`) or the field it is kept in (`row.default`); and the
                   entries of an OWN_LISTS list by their key. A button made by W.Button and one made by
                   CreateFrame("Button") (the flat look laid on it by W.FlatButton) are the same kind here, so a
                   button remade the other way is not a new one. Such a control is tagged when
                   its call -- or the code since the control built before it -- holds `new = "X.Y.Z"`, hands a
                   version to RowOpts / W.NewTag / W.Badge / W.ButtonTag, or names a table whose literal holds
                   one (Home's PROFILE_DD, BACKUP_TAG, EDIT_LAYOUT); or when a W.NewTag / W.Badge / W.ButtonTag
                   after it, before the next control, names it. A call whose label is `opt.<field>`, or a layout
                   row's `r.name` (0.15.0: the pages are laid from Core/ConfigLayout.lua, each row a module's
                   setting), is the schema's own row, counted above. The configurator's page tools -- controls
                   that are no option (PAGE_TOOLS: a picker, Copy from, Apply to all, Reset this page, Home's
                   jumps to the Look page) -- are never New-tagged. Every other Core/ or Modules/ file that builds
                   controls with
                   the widget set must be listed in NOT_CONFIGURATOR (why its controls are not the
                   configurator's): an unknown one fails, so a new home of options is never skipped.

Versions: the current one is --version (Tools/release.py passes the version it releases), else the TOC's when no
tag v<TOC> exists yet, else CHANGELOG.md's newest section when it is newer than the TOC (the update being made,
the TOC keeping the last release's number until the release bumps it). The previous release is --previous, else
the newest v* tag below the current version.

It FAILS (exit 1, the problems listed and counted by file) on
  - a new option without new == the current version (none, or another version),
  - an option the previous release had, tagged new == the current version or a later one,
  - a new module with a page and nothing on it tagged,
  - a Core/ or Modules/ file that builds controls and is in neither OWN_FILES nor NOT_CONFIGURATOR.
Tags of older versions are stale: reported, never failed. Options the previous release had and the tree has not
are listed ("gone"), never failed. --fix takes every `new = "X.Y.Z"` older than the current version out of Core/
and Modules/ -- a table field, a line of its own `x.new = "..."`, a version handed by position to RowOpts /
W.NewTag / W.Badge / W.ButtonTag -- names any other one it finds for a hand, compiles every file it changed (and
puts them all back, exit 2, if one does not compile), and checks again.

    python Tools/lint/check_new_tags.py                      the working tree against the previous release
    python Tools/lint/check_new_tags.py --version 0.14.0     against the release before 0.14.0
    python Tools/lint/check_new_tags.py --fix                the stale tags taken out of the files, then checked
    ... --root DIR      another copy of the addon (a git repository with the release tags)
    ... --previous REF  compare with REF instead of the previous release tag
    ... --list          every option and its tag

The last line reads "new tags: N problems (...)", or "new tags: not checked" (exit 2). Tools never ship; needs
lupa (as Tools/installer/bake_full.py).
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
REPO = os.path.dirname(TOOLS)

# the own rows: the files, their control builders (name -> the argument that names the control, 1-based), and
# the lists whose entries are rows of their own
BUILDERS = {"W.ToggleRow": 3, "W.SliderRow": 3, "W.DropdownRow": 3, "W.ButtonRow": 3,
            "W.Switch": 1, "W.Dropdown": 1, "W.Slider": 1, "W.Button": 2}
OWN_FILES = {
    "Core/Config.lua": {},
}
# (0.15.0: Modules/DynamicUI.lua and its PARCHMENTS and LAYOUT lists went with the configurator rebuild; their rows
# are UI Modifications' definitions, laid out on the Look and element pages -- MOVED below)
OWN_LISTS = {}
# a hand-made control: CreateFrame of one of these kinds (a tab is a page's section, not an option)
CONTROL_TYPES = ("Button", "CheckButton", "EditBox", "Slider", "DropdownButton")
# the other files that build controls with the widget set, and why theirs are not the configurator's options
NOT_CONFIGURATOR = {
    "Core/Widgets.lua": "the builders themselves",
    "Core/InstallerWindow.lua": "the installer's own window and steps (not the configurator)",
    "Modules/Restock.lua": "the Restock List window and the shop's list (the Reminders page's Restock List button, "
                           "a schema option, opens them)",
    "Modules/KitWindow.lua": "the own confirm dialog's answer buttons (MelloUI:Confirm), not options",
    "Core/Core.lua": "the copy window's Import button (MelloUI:ShowPaste), not an option",
    "Modules/Services.lua": "the Services menu's Stop route button (it ends the route), not an option",
    "Modules/RouteRecorder.lua": "the road recorder's window (a developer tool, /route record): its city switches and "
                                 "buttons record roads, not options",
    "Core/EditLayout.lua": "Edit Layout's own control bar and right-click box: a mode's controls, not options",
    "Core/EditLayoutMovers.lua": "Edit Layout's plates: a mode's controls, not options",
    "Core/EditLayoutBridge.lua": "the Edit Mode bridge's buttons (Move via Edit Mode, the button on Edit Mode): a mode's "
                                 "controls, not options",
    "Modules/MeterHistory.lua": "the Fight History window's Clear button and tabs (the Damage Meter page's Fight History "
                                "option, a schema option, switches the window)",
    "Core/Preview.lua": "the preview's Stop button and its list's rows (the top bar's Preview button, New-tagged in "
                        "Core/Config.lua, opens them): a scene's controls, not options",
}
# the controls an OWN_FILES file builds that are no option of the configurator, and why (never New-tagged)
NOT_OPTIONS = {
    "Core/Config.lua:Button(MelloUI)": "MelloUI's own entry at the game's Escape menu (it opens the configurator)",
}
# the configurator's page tools (0.15.0, the rebuild): controls of a page that are no option -- they set nothing of
# their own, they pick, copy, reset or jump -- so they never carry a New tag (the rebuild's own texts say so), by
# their id in this check: why
PAGE_TOOLS = {
    "Core/Config.lua:W.Dropdown(line)": "a picker page's picker (the frame, bar or window the page's rows are for)",
    "Core/Config.lua:W.Dropdown(line)#2": "a picker page's Copy from (copies the page's per-pick settings between "
                                          "picks)",
    "Core/Config.lua:Button(All)": "Apply to all on a row per pick (writes the pick's value into the row's other keys)",
    "Core/Config.lua:Button(Reset this page)": "Reset this page (puts the page's settings back to their defaults)",
    "Core/Config.lua:Button(Change…)#2": "Your setup's second Change… (Home's palette and Kit Colours rows jump "
                                          "to their one place on the Look page)",
}
# a control builder's call whose label is the schema's own row: `opt.<field>` (the old pages' builders), a layout
# row's `r.name` (the rebuild's element pages: Core/ConfigLayout.lua's rows, each a module's setting)
SCHEMA_LABEL = re.compile(r"opt\.|r\.name$")
# the kinds that are one kind here: a W.Button is a Button (W.FlatButton lays the same look on a hand-made one)
SAME_KIND = {"W.Button": "Button"}
# schema options that were controls of another kind in the previous release, so they count as existing (untagged; a
# New tag on one fails as on any old option): (the update they moved in, why). 0.15.0, the configurator rebuild:
# Dynamic UI Modification's own rows of 0.14.0 (its palette, borders and Kit Colours, parchment sheets and UI shade
# areas, built by its window) are UI Modifications' option definitions, laid out on the Look page
_DUI_ROW = ((0, 15, 0), "a row of Dynamic UI Modification's own window in 0.14.0; a UI Modifications definition since "
                        "the configurator rebuild")
MOVED = dict.fromkeys(
    ["UIModifications." + k for k in
     ["palette", "kitColours", "buttonBorder", "sideTabBorder", "barBorder", "nameplateBorder", "roundBorder",
      "auraBorder"]
     + ["parchment_" + a for a in ("tracker", "questTracker", "chat", "whisper", "meter", "character", "tooltip",
                                   "dialog")]
     + ["shade_" + a for a in ("windows", "actionbars", "castbars", "unitframes", "chat", "bags", "minimap", "tracker",
                               "buffs", "widgets", "nameplates")]],
    _DUI_ROW)
FOLDERS = ("Core", "Modules")


class CheckError(Exception):
    """The check could not run (a file that does not load, no release to compare with): exit 2, never a pass."""


VERSION_LIT = r'"(\d+\.\d+(?:\.\d+)?)"'
TAG_RE = re.compile(r'\bnew\s*=\s*' + VERSION_LIT)
# a version handed by position: the builder -> the argument that is the version (1-based)
TAG_CALLS = {"RowOpts": 2, "W.NewTag": 3, "W.Badge": 2, "W.ButtonTag": 2}
TAG_CALL_RE = re.compile(r"(?<![\w.:])(RowOpts|W\.NewTag|W\.Badge|W\.ButtonTag)\s*\(")
# the widget set's control builders, wherever they are called (a file building controls)
BUILDER_USE_RE = re.compile(r"(?<![\w.:])(?:W|MelloUI\.Widgets)\.(ToggleRow|SliderRow|DropdownRow|ButtonRow|Row|Switch|"
                            r"Dropdown|Slider|Button|DropdownMenu)\s*\(")


# ---------------------------------------------------------------------------------------------------------------
# versions


def vtuple(text):
    """ "0.14.0", "v0.14.0", "0.14.0-rc5", "0.14" -> (0, 14, 0); None when it names no version."""
    m = re.match(r"^\s*v?(\d+)\.(\d+)(?:\.(\d+))?", str(text or ""), re.I)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def vtext(t):
    return "%d.%d.%d" % t


def git(root, *args, binary=False):
    r = subprocess.run(["git", *args], cwd=root, capture_output=True)
    if r.returncode != 0:
        raise CheckError("git %s failed in %s: %s" % (" ".join(args), root, r.stderr.decode("utf-8", "replace").strip()))
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def toc_version(root):
    with open(os.path.join(root, "MelloUI.toc"), encoding="utf-8-sig") as fh:
        m = re.search(r"^## Version:\s*(\S+)", fh.read(), re.M)
    return vtuple(m.group(1)) if m else None


def changelog_version(root):
    path = os.path.join(root, "CHANGELOG.md")
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        m = re.search(r"^## (\S+)", fh.read(), re.M)
    return vtuple(m.group(1)) if m else None


def release_tags(root):
    out = {}
    for name in git(root, "tag", "--list", "v*").split():
        t = vtuple(name)
        if t and re.fullmatch(r"v\d+\.\d+(\.\d+)?", name):
            out[t] = name
    return out


def versions(root, version=None, previous=None):
    """(current version tuple, the previous release's ref, its label)"""
    tags = release_tags(root)
    if version:
        current = vtuple(version)
        if not current:
            raise CheckError("--version %r names no version" % version)
    else:
        toc = toc_version(root)
        if not toc:
            raise CheckError("MelloUI.toc has no '## Version:' line")
        current = toc
        if toc in tags:
            # released already: the update being made is CHANGELOG.md's newest section, when newer
            log = changelog_version(root)
            if log and log > toc:
                current = log
    if previous:
        return current, previous, previous
    older = [t for t in tags if t < current]
    if not older:
        raise CheckError("no release tag (v*) below %s to compare with" % vtext(current))
    ref = tags[max(older)]
    return current, ref, ref


# ---------------------------------------------------------------------------------------------------------------
# the schema options: the addon's files in a lupa world


def lua_world():
    """The installer tools' stand-ins (Tools/installer/world.py PRELUDE, bakeworld's Core set-up)."""
    sys.path.insert(0, os.path.join(TOOLS, "installer"))
    sys.path.insert(0, TOOLS)
    try:
        import world as IW  # noqa: E402
        import bakeworld as BW  # noqa: E402
    except ImportError as exc:
        raise CheckError("the check needs lupa and Tools/installer (%s): pip install lupa" % exc)
    return IW, BW


# a file's body under an instruction budget and a pcall; unlike the bake's loader, a body cut by the budget is an
# error too (what it would have registered after that point is missing)
LOADF = r'''function(src, name, ns)
  local f, e = loadstring(src, name)
  if not f then return "SYNTAX " .. e end
  debug.sethook(function() error("__budget") end, "", 50000000)
  local ok, err = pcall(f, "MelloUI", ns)
  debug.sethook()
  if not ok then
    if tostring(err):find("__budget") then return "its body ran past the instruction budget" end
    return tostring(err)
  end
  return nil
end'''

COMPILE = r'''function(src, name)
  local f, e = loadstring(src, name)
  return f and "" or tostring(e)
end'''

AFTER_REGISTRY = r'''
FILE_OF, CURRENT_FILE = {}, "?"
local M = _G.MelloUI
local reg = M.RegisterModule
M.RegisterModule = function(self, name, module)
    FILE_OF[name] = CURRENT_FILE
    return reg(self, name, module)
end
'''

# every module's OnInit, as at login (UI Modifications fills its registry rows, Reminders lays Restock's), each
# under an instruction budget and a pcall; an OnInit that fails (or runs past the budget) is returned: the rows it
# would have laid are missing, so the check cannot count them
INIT_ALL = r'''
local M = _G.MelloUI
local errs = {}
for _, name in ipairs(M.moduleOrder or {}) do
    local module = M.modules[name]
    local init = type(module) == "table" and rawget(module, "OnInit")
    if type(init) == "function" then
        debug.sethook(function() error("__budget") end, "", 20000000)
        local ok, err = pcall(init, module, M:GetModuleDB(name))
        debug.sethook()
        if not ok then
            errs[#errs + 1] = name .. ": " .. (tostring(err):find("__budget") and "ran past the instruction budget"
                or tostring(err))
        end
    end
end
if (ERRORS or 0) > 0 then
    errs[#errs + 1] = "the error handler caught " .. ERRORS .. " error(s), the last: " .. tostring(LASTERROR)
end
return table.concat(errs, "\n")
'''


def option_id(declared, owner, key, name):
    base = declared + (">" + owner if owner else "")
    return base + ("." + key if key is not None else ":" + name)


def load_schema(root, what="the tree"):
    """{id: record} of the tree's schema options and modules; CheckError when a file does not load or a module's
    OnInit fails."""
    import lupa.lua51 as L51
    IW, BW = lua_world()
    root = root.replace("\\", "/").rstrip("/") + "/"
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(IW.PRELUDE)
    loadf = lua.eval(LOADF)
    compile_only = lua.eval(COMPILE)
    ns = lua.eval("{}")
    errs = {}
    with open(root + "Core/Core.lua", encoding="utf-8") as fh:
        e = loadf(fh.read(), "@Core/Core.lua", ns)
    if e:
        raise CheckError("Core/Core.lua does not load in %s (%s): %s" % (what, root, e))
    lua.execute(BW.AFTER_CORE)
    lua.execute(AFTER_REGISTRY)
    with open(root + "MelloUI.toc", encoding="utf-8-sig") as fh:
        toc = [line.strip().replace("\\", "/") for line in fh.read().split("\n")]
    for f in [line for line in toc if line.endswith(".lua") and line != "Core/Core.lua"]:
        lua.globals().CURRENT_FILE = f
        try:
            with open(root + f, encoding="utf-8") as fh:
                src = fh.read()
        except FileNotFoundError:
            continue
        if f == "Core/Perf.lua":
            e = compile_only(src, "@" + f)   # (the world stands in for it: compiled only)
        else:
            e = loadf(src, "@" + f, ns)
        if e:
            errs[f] = e
    if errs:
        raise CheckError("files do not load in %s (%s) -- a file mid-edit? run again once it is whole:\n%s"
                         % (what, root, "\n".join("  %s: %s" % (k, v[:200]) for k, v in sorted(errs.items()))))
    init_errs = lua.execute(INIT_ALL)
    if init_errs:
        raise CheckError("module OnInit failed in %s (%s): the rows it lays cannot be counted -- give the stand-in "
                         "world what it needs (Tools/installer/world.py) or fix the module:\n%s"
                         % (what, root, "\n".join("  " + line[:240] for line in str(init_errs).split("\n"))))
    lua.globals().PYID = lambda d, o, k, n: option_id(d, o, k, n)
    rows = lua.execute(COLLECT)
    out = {}
    for i in range(1, len(rows) + 1):
        r = rows[i]
        rec = {k: (r[k] if r[k] is not None else "") for k in ("id", "kind", "label", "new", "file", "declared")}
        rec["page"] = r["page"] or ""
        rec["source"] = "schema" if rec["kind"] != "module" else "module"
        out.setdefault(rec["id"], rec)
    return out


# what the configurator lays, per module: its entry, then its options (an include's inline rows are the
# including module's), each named by option_id
COLLECT = r'''
local M = _G.MelloUI
local out = {}
local SKIP = { header = true, subheader = true, include = true }
local function Add(declared, opt)
    if type(opt) ~= "table" or opt.type == nil or SKIP[opt.type] or opt.slot then return end
    local id = PYID(declared, opt.module, opt.key ~= nil and tostring(opt.key) or nil, tostring(opt.name or opt.text))
    out[#out + 1] = { id = id, kind = tostring(opt.type), label = tostring(opt.name or opt.text or ""),
        new = opt.new ~= nil and tostring(opt.new) or "", file = FILE_OF[declared] or "?", page = "",
        declared = declared }
end
for _, name in ipairs(M.moduleOrder or {}) do
    local module = M.modules[name]
    out[#out + 1] = { id = "module:" .. name, kind = "module", label = tostring(module.title or name),
        new = module.new ~= nil and tostring(module.new) or "", file = FILE_OF[name] or "?",
        page = (module.group and not module.hidden) and "yes" or "", declared = name }
    for _, opt in ipairs(type(module.options) == "table" and module.options or {}) do
        if type(opt) == "table" and opt.type == "include" then
            -- (an include's inline rows are the including module's: declared here; an entry that IS one of the
            -- included module's own options -- Reminders lays Restock's that way -- is that module's, counted there)
            local inc = M.modules[opt.module]
            local own = {}
            for _, o in ipairs(inc and type(inc.options) == "table" and inc.options or {}) do own[o] = true end
            for _, k in ipairs(type(opt.keys) == "table" and opt.keys or {}) do
                if type(k) == "table" and not own[k] then Add(name, k) end
            end
        else
            Add(name, opt)
        end
    end
end
return out
'''


# ---------------------------------------------------------------------------------------------------------------
# the own rows: read from the source


def scan(src):
    """(the source with its comments blanked -- strings kept, newlines and offsets kept --, [(start, end)] of its
    string literals)"""
    out = list(src)
    strings = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "-" and src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:i + 64])
            if m:
                end = src.find("]" + m.group(1) + "]", i)
                end = n if end < 0 else end + len(m.group(1)) + 2
            else:
                end = src.find("\n", i)
                end = n if end < 0 else end
            for k in range(i, end):
                if out[k] != "\n":
                    out[k] = " "
            i = end
        elif c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            strings.append((i, j + 1))
            i = j + 1
        elif c == "[" and re.match(r"\[(=*)\[", src[i:i + 64]):
            m = re.match(r"\[(=*)\[", src[i:i + 64])
            end = src.find("]" + m.group(1) + "]", i)
            end = n if end < 0 else end + len(m.group(1)) + 2
            strings.append((i, end))
            i = end
        else:
            i += 1
    return "".join(out), strings


def code_only(src):
    """The source with its comments blanked (strings kept; newlines and offsets kept)."""
    return scan(src)[0]


def in_string(strings, pos):
    for s, e in strings:
        if s <= pos < e:
            return True
        if s > pos:
            return False
    return False


def call_spans(code, start):
    """From the '(' at `start`: ([(s, e)] of the arguments split at the top level, stripped; the index after the
    ')')."""
    depth, i, n = 0, start, len(code)
    spans, cur = [], None

    def close(k):
        if cur is not None:
            s, e = cur, k
            while s < e and code[s].isspace():
                s += 1
            while e > s and code[e - 1].isspace():
                e -= 1
            spans.append((s, e))

    while i < n:
        c = code[i]
        if c in "\"'":
            j = i + 1
            while j < n and code[j] != c and code[j] != "\n":
                j += 2 if code[j] == "\\" else 1
            if cur is None and depth == 1:
                cur = i
            i = j + 1
            continue
        if c in "({[":
            depth += 1
            if depth == 1:
                cur = i + 1
                i += 1
                continue
        elif c in ")}]":
            depth -= 1
            if depth == 0:
                close(i)
                if len(spans) == 1 and spans[0][0] == spans[0][1]:
                    spans = []   # (no arguments)
                return spans, i + 1
        elif c == "," and depth == 1:
            close(i)
            cur = i + 1
        i += 1
    return spans, n


def call_args(code, start):
    """From the '(' at `start`: (the arguments split at the top level, the index after the ')')."""
    spans, end = call_spans(code, start)
    return [code[s:e] for s, e in spans], end


def table_literal(code, name):
    """The text of `local NAME = { ... }` (or `NAME = {`) in the code, or None."""
    m = re.search(r"(?:^|[^\w.])" + re.escape(name) + r"\s*=\s*\{", code)
    if not m:
        return None
    start = m.end() - 1
    _, end = call_args(code, start)
    return code[start:end]


def named_tag(code, name):
    lit = table_literal(code, name)
    m = TAG_RE.search(lit) if lit else None
    return m.group(1) if m else ""


def call_tag(code, text):
    """A version handed by position to RowOpts / W.NewTag / W.Badge / W.ButtonTag in `text`: its literal, or the
    `new` of the table it names (`BACKUP_TAG.new`)."""
    for m in TAG_CALL_RE.finditer(text):
        args, _ = call_args(text, m.end() - 1)
        k = TAG_CALLS[m.group(1)]
        if len(args) >= k:
            arg = " ".join(args[k - 1].split())
            lit = re.fullmatch(VERSION_LIT, arg)
            if lit:
                return lit.group(1)
            named = re.fullmatch(r"([A-Za-z_]\w*)\.new", arg)
            if named and named_tag(code, named.group(1)):
                return named_tag(code, named.group(1))
    return ""


def tag_of(code, text):
    """The version a piece of code tags: `new = "X.Y.Z"` in it, a version handed to a tag builder, or a table
    literal it names that holds `new`."""
    m = TAG_RE.search(text)
    if m:
        return m.group(1)
    v = call_tag(code, text)
    if v:
        return v
    for name in re.findall(r"\b([A-Z_][A-Za-z0-9_]*)\b", text):
        v = named_tag(code, name)
        if v:
            return v
    return ""


def tag_after(code, text, target):
    """A W.NewTag / W.Badge / W.ButtonTag in `text` (the code after a control) that names `target` (the variable
    or field the control is kept in): the version it tags."""
    if not target:
        return ""
    pat = re.compile(r"(?<![\w.])" + re.escape(target) + r"(?!\w)")
    for m in TAG_CALL_RE.finditer(text):
        if m.group(1) == "RowOpts":
            continue
        args, end = call_args(text, m.end() - 1)
        if any(pat.search(a) for a in args):
            v = tag_of(code, text[m.start():end])
            if v:
                return v
    return ""


def label_of(code, expr):
    expr = " ".join(expr.split())
    m = re.fullmatch(r'"((?:[^"\\]|\\.)*)"', expr)
    if m:
        return m.group(1)
    m = re.fullmatch(r"[A-Za-z_][\w]*\.([A-Za-z_]\w*)", expr) or re.fullmatch(r'[A-Za-z_]\w*\["([A-Za-z_]\w*)"\]', expr)
    if m:
        found = set(re.findall(r"\b" + re.escape(m.group(1)) + r'\s*=\s*"((?:[^"\\]|\\.)*)"', code))
        if len(found) == 1:
            return found.pop()
    return expr


TARGET_RE = re.compile(r"(?:local\s+)?([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*=\s*$")


def target_of(code, pos):
    """The variable or field a call at `pos` is kept in (`local b = ...`, `row.load = ...`), or ""."""
    line_start = code.rfind("\n", 0, pos) + 1
    m = TARGET_RE.search(code[line_start:pos])
    return re.sub(r"\s+", "", m.group(1)) if m else ""


def own_sites(code, local):
    """The control call sites of a file's code, in order: (start, end, kind, label expression, target, schema)."""
    builders = dict(BUILDERS)
    builders.update(local)
    names = "|".join(re.escape(b) for b in sorted(builders, key=len, reverse=True))
    sites = []
    for m in re.finditer(r"(?<![\w.:])(" + names + r")\s*\(", code):
        before = code[max(0, m.start() - 40):m.start()]
        if re.search(r"function\s+$", before):
            continue   # (its definition)
        args, end = call_args(code, m.end() - 1)
        if end <= m.end():
            continue
        at = builders[m.group(1)]
        expr = args[at - 1] if len(args) >= at else ""
        sites.append((m.start(), end, m.group(1), expr, target_of(code, m.start()), bool(SCHEMA_LABEL.match(expr))))
    kinds = "|".join(CONTROL_TYPES)
    for m in re.finditer(r'(?<![\w.:])CreateFrame\s*\(\s*"(' + kinds + r')"', code):
        args, end = call_args(code, m.end() - len(m.group(0)) + m.group(0).index("("))
        template = args[3] if len(args) >= 4 else ""
        if "Tab" in template:
            continue   # (a page's tab: a section, not an option)
        target = target_of(code, m.start())
        sites.append((m.start(), end, m.group(1), None, target, False))
    sites.sort()
    return sites


def own_rows(root):
    """{id: record} of the configurator's own controls and Dynamic UI's (see the header)."""
    out = {}
    for rel, local in OWN_FILES.items():
        path = os.path.join(root, rel)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as fh:
            code = code_only(fh.read())
        sites = own_sites(code, local)
        prev_end = 0
        seen = {}
        for i, (start, end, kind, expr, target, schema) in enumerate(sites):
            nxt = sites[i + 1][0] if i + 1 < len(sites) else len(code)
            if schema:
                prev_end = end
                continue   # (a schema option's own row: counted with the schema)
            if expr is None:
                # a hand-made control: named by the text it is given before the next control, else its field
                label = target or "?"
                if target:
                    st = re.search(re.escape(target).replace(r"\.", r"\s*\.\s*") + r'\s*:\s*SetText\s*\(\s*("(?:[^"\\]|\\.)*")',
                                   code[end:nxt])
                    if st:
                        label = label_of(code, st.group(1))
            else:
                label = label_of(code, expr)
            kind = SAME_KIND.get(kind, kind)
            base = "%s:%s(%s)" % (rel, kind, label)
            seen[base] = seen.get(base, 0) + 1
            rid = base if seen[base] == 1 else "%s#%d" % (base, seen[base])
            if rid in NOT_OPTIONS or rid in PAGE_TOOLS:
                prev_end = end
                continue
            # the code since the control before it, within the function it is built in; then the code after it,
            # up to the next function, for a tag call that names it
            funcs = [f.start() for f in re.finditer(r"\bfunction\b", code[:start])]
            since = max(prev_end, funcs[-1] if funcs else 0)
            after_fn = re.search(r"\bfunction\b", code[end:])
            until = end + after_fn.start() if after_fn else len(code)
            new = (tag_of(code, code[start:end]) or tag_of(code, code[since:end])
                   or tag_after(code, code[end:until], target))
            out[rid] = {"id": rid, "kind": kind, "label": label, "new": new, "file": rel, "source": "own", "page": "",
                        "declared": rel}
            prev_end = end
        for listname in OWN_LISTS.get(rel, []):
            lit = table_literal(code, listname)
            if not lit:
                continue
            args, _ = call_args(lit, 0)
            for entry in args:
                if not entry.startswith("{"):
                    continue
                mod = re.search(r'\bmodule\s*=\s*"([^"]*)"', entry)
                key = re.search(r'\bkey\s*=\s*"([^"]*)"', entry) or re.search(r'"([^"]*)"', entry)
                if not key:
                    continue
                name = (mod.group(1) + "." if mod else "") + key.group(1)
                rid = "%s:%s[%s]" % (rel, listname, name)
                m2 = TAG_RE.search(entry)
                out[rid] = {"id": rid, "kind": listname, "label": name, "new": m2.group(1) if m2 else "",
                            "file": rel, "source": "own", "page": "", "declared": rel}
    return out


def lua_files(root):
    for folder in FOLDERS:
        base = os.path.join(root, folder)
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            if name.endswith(".lua"):
                yield folder + "/" + name, os.path.join(base, name)


def unlisted(root):
    """[(file, id, text)]: a Core/ or Modules/ file that builds controls with the widget set and is in neither
    OWN_FILES nor NOT_CONFIGURATOR (whose new controls this check would never see)."""
    out = []
    for rel, path in lua_files(root):
        if rel in OWN_FILES or rel in NOT_CONFIGURATOR:
            continue
        with open(path, encoding="utf-8") as fh:
            code = code_only(fh.read())
        m = BUILDER_USE_RE.search(code)
        if m:
            line = code.count("\n", 0, m.start()) + 1
            out.append((rel, "controls:" + rel, "builds controls (W.%s, line %d) that this check does not know: add "
                        "it to OWN_FILES in Tools/lint/check_new_tags.py (configurator options: their new ones need "
                        "New tags) or to NOT_CONFIGURATOR, with why" % (m.group(1), line)))
    return out


# ---------------------------------------------------------------------------------------------------------------
# the comparison


def inventory(root, what="the tree"):
    inv = load_schema(root, what)
    inv.update(own_rows(root))
    return inv


def export(root, ref, dest):
    data = git(root, "archive", "--format=tar", ref, binary=True)
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        members = [m for m in t.getmembers() if m.name.endswith((".lua", ".toc", ".md"))]
        try:
            t.extractall(dest, members=members, filter="data")
        except TypeError:
            t.extractall(dest, members=members)


def compare(cur, old, current, ref="the previous release"):
    """(problems, stale, new ids, gone): each problem / stale / gone (file, id, text)."""
    problems, stale, fresh, gone = [], [], [], []
    cv = vtext(current)
    # the modules that declare an option tagged with the current version (a new page with one needs no own tag)
    tagged_by = {r["declared"] for r in cur.values() if r["source"] == "schema" and r["new"]
                 and vtuple(r["new"]) == current}
    for rid in sorted(cur):
        r = cur[rid]
        tag = vtuple(r["new"]) if r["new"] else None
        prev = old.get(rid)
        if prev is None and rid in MOVED and current >= MOVED[rid][0]:
            prev = {"kind": r["kind"]}   # (a control of another kind in the previous release: see MOVED)
        was = prev["kind"] if prev else None
        is_new = prev is None or was != r["kind"]
        what = '%s "%s"' % (r["kind"], r["label"])
        if prev is not None and was != r["kind"]:
            what += ", a %s in %s" % (was, ref)
        if is_new:
            fresh.append(rid)
        if tag and tag < current:
            stale.append((r["file"], rid, '%s (%s) has new = "%s", older than %s: --fix takes it out'
                          % (rid, what, r["new"], cv)))
        if r["kind"] == "module":
            if is_new:
                if tag is not None and tag != current:
                    problems.append((r["file"], rid, '%s (%s) is new since the previous release but tagged new = "%s", '
                                     'not "%s"' % (rid, what, r["new"], cv)))
                elif tag is None and r["page"] and r["declared"] not in tagged_by:
                    problems.append((r["file"], rid, '%s (%s) is a new page with nothing on it tagged: add new = "%s" '
                                     'to its RegisterModule' % (rid, what, cv)))
            elif tag is not None and tag >= current:
                problems.append((r["file"], rid, '%s (%s) was in the previous release but is tagged new = "%s": take the '
                                 'tag out' % (rid, what, r["new"])))
            continue
        if is_new:
            if tag is None:
                problems.append((r["file"], rid, '%s (%s) is new since the previous release and has no New tag: '
                                 'add new = "%s"' % (rid, what, cv)))
            elif tag != current:
                problems.append((r["file"], rid, '%s (%s) is new since the previous release but tagged new = "%s", '
                                 'not "%s"' % (rid, what, r["new"], cv)))
        elif tag is not None and tag >= current:
            problems.append((r["file"], rid, '%s (%s) was in the previous release but is tagged new = "%s": take the '
                             'tag out' % (rid, what, r["new"])))
    for rid in sorted(set(old) - set(cur)):
        r = old[rid]
        gone.append((r["file"], rid, '%s (%s "%s", %s) was in %s and is not in this tree'
                     % (rid, r["kind"], r["label"], r["file"], ref)))
    return problems, stale, fresh, gone


# ---------------------------------------------------------------------------------------------------------------
# --fix


DOTTED_LINE_RE = re.compile(r'[ \t]*[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*|\s*\[[^\]\n]*\])*\s*\.\s*new\s*=\s*'
                            + VERSION_LIT + r'\s*;?[ \t]*')


def prev_char(code, pos):
    """(the last character before `pos` that is not white space, its index), or ("", -1)."""
    j = pos - 1
    while j >= 0 and code[j].isspace():
        j -= 1
    return (code[j], j) if j >= 0 else ("", -1)


def next_char(code, pos):
    j = pos
    while j < len(code) and code[j].isspace():
        j += 1
    return (code[j], j) if j < len(code) else ("", len(code))


def whole_line(code, start, end):
    """(start, end) grown to the whole line(s) when nothing but white space (or a comment) is left on them."""
    ls = code.rfind("\n", 0, start) + 1
    le = code.find("\n", end)
    le = len(code) if le < 0 else le
    if code[ls:start].strip() == "" and code[end:le].strip() == "":
        return ls, min(le + 1, len(code))
    return start, end


def stale_edits(text, current):
    """([(start, end, replacement)], [(line, text)] left for a hand) for the tags older than `current` in a file."""
    code, strings = scan(text)
    edits, left = [], []

    def stale(v):
        t = vtuple(v)
        return t is not None and t < current

    def line_of(pos):
        return code.count("\n", 0, pos) + 1

    for m in re.finditer(r'\bnew\s*=\s*' + VERSION_LIT, code):
        if not stale(m.group(1)) or in_string(strings, m.start()):
            continue
        s, e = m.start(), m.end()
        before = code[s - 1] if s > 0 else ""
        if before in ".:" or (before.isspace() and prev_char(code, s)[0] in ".:"):
            # `x.new = "..."`: a statement; taken out only as a line of its own
            ls = code.rfind("\n", 0, s) + 1
            le = code.find("\n", e)
            le = len(code) if le < 0 else le
            if DOTTED_LINE_RE.fullmatch(code[ls:le]):
                edits.append((ls, min(le + 1, len(code)), ""))
            else:
                left.append((line_of(s), text[ls:le].strip()))
            continue
        p, pj = prev_char(code, s)
        if p not in "{,;" or p == "":
            # (not a table field: `local new = ...`, a statement)
            ls = code.rfind("\n", 0, s) + 1
            le = code.find("\n", e)
            left.append((line_of(s), text[ls:(len(code) if le < 0 else le)].strip()))
            continue
        nc, nj = next_char(code, e)
        if nc in ",;":
            # `new = "...",` : the field and its separator
            k = nj + 1
            while k < len(code) and code[k] in " \t":
                k += 1
            span = whole_line(code, s, k)
        elif p == ",":
            # `..., new = "..." }` : the separator before it and the field
            span = (pj, e)
            span = whole_line(code, *span) if code[pj + 1:s].strip() == "" and "\n" not in code[pj:s] else span
        else:
            # `{ new = "..." }`
            k = e
            while k < len(code) and code[k] in " \t":
                k += 1
            span = whole_line(code, s, k)
        edits.append((span[0], span[1], ""))
    for m in TAG_CALL_RE.finditer(code):
        if in_string(strings, m.start()):
            continue
        spans, _ = call_spans(code, m.end() - 1)
        k = TAG_CALLS[m.group(1)]
        if len(spans) < k:
            continue
        a, b = spans[k - 1]
        lit = re.fullmatch(VERSION_LIT, code[a:b])
        if not (lit and stale(lit.group(1))):
            continue
        if len(spans) == k:
            edits.append((spans[k - 2][1], b, ""))   # (the last argument: it and the comma before it)
        else:
            edits.append((a, b, "nil"))              # (a later one follows: its place kept)
    return edits, left


def fix_stale(root, current, compile_check=None):
    """Every tag older than the current version taken out of Core/ and Modules/ (see the header): (the number taken
    out, the files changed, [(file, line, text)] left for a hand). A changed file that does not compile puts every
    file back and raises CheckError."""
    removed, changed, left, originals = 0, [], [], {}
    for rel, path in lua_files(root):
        with open(path, encoding="utf-8", newline="") as fh:
            text = fh.read()
        edits, keep = stale_edits(text, current)
        left += [(rel, line, t) for line, t in keep]
        if not edits:
            continue
        new, last, applied = text, None, []
        for s, e, rep in sorted(edits, reverse=True):
            if last is not None and e > last:
                continue   # (overlaps the one after it: already taken)
            new = new[:s] + rep + new[e:]
            last = s
            applied.append((s, e, rep))
            removed += 1
        # A tag taken out of the middle of a line leaves the space before it at the line's end (0.15.0's release
        # commit got 25 luacheck W612 warnings that way): the lines an edit touched lose their trailing blanks.
        for s, _, _ in applied:
            pos = s - sum((ej - sj) - len(rj) for sj, ej, rj in applied if ej <= s)
            end = new.find("\n", pos)
            end = len(new) if end < 0 else end
            body_end = end - 1 if end > 0 and new[end - 1] == "\r" else end
            cut = body_end
            while cut > 0 and new[cut - 1] in " \t" and new[cut - 1] != "\n":
                cut -= 1
            if cut < body_end:
                new = new[:cut] + new[body_end:]
        if new != text:
            originals[path] = text
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(new)
            changed.append(rel)
    if changed:
        broken = []
        check = compile_check or lua_compiler()
        for rel in changed:
            with open(os.path.join(root, rel), encoding="utf-8") as fh:
                err = check(fh.read(), "@" + rel)
            if err:
                broken.append("  %s: %s" % (rel, err))
        if broken:
            for path, text in originals.items():
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(text)
            raise CheckError("--fix would leave files that do not compile, so every file is as it was; take these "
                             "tags out by hand:\n" + "\n".join(broken))
    return removed, changed, left


def lua_compiler():
    import lupa.lua51 as L51
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    compile_only = lua.eval(COMPILE)
    return lambda src, name: compile_only(src, name) or ""


# ---------------------------------------------------------------------------------------------------------------


def run(root, version=None, previous=None, fix=False, list_all=False):
    current, ref, label = versions(root, version, previous)
    print("check_new_tags: %s against %s (%s)" % (vtext(current), label, root))
    tmp = tempfile.mkdtemp(prefix="newtags_")
    try:
        export(root, ref, tmp)
        old = inventory(tmp, "the previous release (%s)" % label)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    cur = inventory(root)
    if fix:
        removed, changed, left = fix_stale(root, current)
        if removed:
            print("--fix: %d stale tag%s taken out of %s" % (removed, "" if removed == 1 else "s", ", ".join(changed)))
            cur = inventory(root)
        else:
            print("--fix: no stale tags")
        for f, line, text in left:
            print("--fix left %s:%d (not a table field, a line of its own or a version handed by position): %s -- "
                  "take it out by hand" % (f, line, text[:160]))
    problems, stale, fresh, gone = compare(cur, old, current, label)
    problems += unlisted(root)
    if list_all:
        for rid in sorted(cur):
            r = cur[rid]
            print("  %-4s %-40s %s  new=%s" % ("NEW" if rid in fresh else "", r["file"], rid, r["new"] or "-"))
    counts = {}
    for src in ("schema", "module", "own"):
        rows = [r for r in cur.values() if r["source"] == src]
        counts[src] = (len(rows), sum(1 for r in rows if r["id"] in fresh),
                       sum(1 for r in rows if r["new"] and vtuple(r["new"]) == current))
    print("  schema options %d (%d new since %s, %d tagged %s); modules %d (%d new); own rows %d (%d new, %d tagged)"
          % (counts["schema"][0], counts["schema"][1], label, counts["schema"][2], vtext(current),
             counts["module"][0], counts["module"][1], counts["own"][0], counts["own"][1], counts["own"][2]))
    for _, _, text in gone:
        print("gone   " + text)
    for _, _, text in stale:
        print("stale  " + text)
    for f, _, text in problems:
        print("FAIL   %s: %s" % (f, text))
    byfile = {}
    for f, _, _ in problems:
        byfile[f] = byfile.get(f, 0) + 1
    if byfile:
        print("problems by file: " + ", ".join("%s %d" % (f, n) for f, n in sorted(byfile.items())))
    print("new tags: %d problem%s (%d options, %d new since %s, %d stale, %d gone)"
          % (len(problems), "" if len(problems) == 1 else "s", len(cur), len(fresh), label, len(stale), len(gone)))
    return 1 if problems else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", help="the version being released (default: the TOC's, or CHANGELOG.md's newest)")
    ap.add_argument("--previous", help="the ref to compare with (default: the newest v* tag below the version)")
    ap.add_argument("--root", default=REPO, help="the addon's folder (a git repository)")
    ap.add_argument("--fix", action="store_true", help="take the stale tags out of the files")
    ap.add_argument("--list", action="store_true", help="every option and its tag")
    a = ap.parse_args()
    try:
        code = run(os.path.abspath(a.root), a.version, a.previous, a.fix, a.list)
    except CheckError as exc:
        print("check_new_tags could not check: %s" % exc)
        print("new tags: not checked")
        code = 2
    sys.exit(code)


if __name__ == "__main__":
    main()
