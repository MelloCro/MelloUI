"""MelloUI's language tables (MelloUI_Languages/<code>.lua; docs/plans/languages.md): what is translated, what is
missing, and the files kept in one form.

A language file maps an English line (Tools/languages/strings.py collects them from the addon) to its translation:

    Lang:Add("deDE", {
        ["Enabled"] = "Aktiviert",
        ["Reset this page"] = "Diese Seite zurücksetzen", -- draft
    })

A line ending in `-- draft` is a machine draft no translator has checked yet; it shows in the game all the same.
A line the file lacks shows in English. The files are written by this tool only (one line per entry, the English
order, a comment per source); a translation of an English line the addon no longer has is kept at the file's end as a
comment ("stale"), never loaded.

    python Tools/languages/languages.py status                 every language: lines, translated, drafts, missing
    python Tools/languages/languages.py check                  the problems (placeholders, markup, a file that does
                                                               not load); exit 1 on any. Missing lines never fail.
    python Tools/languages/languages.py missing deDE           the English lines deDE lacks
    python Tools/languages/languages.py todo deDE out.json     those lines as a list to translate, with the game's own
                                                               words for the terms in them (glossary.py)
    python Tools/languages/languages.py add deDE in.json       {english: translation} merged in as drafts (a checked
                                                               line is never replaced), the file written again
    python Tools/languages/languages.py write deDE             the file written again in its one form
    ... --root DIR    another copy of the addon

Needs lupa. Tools never ship.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import strings as S  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = "MelloUI_Languages"
# the languages, in Core.lua's Languages section's LIST order (English is the source)
CODES = ["deDE", "frFR", "esES", "ptBR", "ruRU", "zhCN", "koKR"]
NAMES = {"deDE": "Deutsch", "frFR": "Français", "esES": "Español", "ptBR": "Português", "ruRU": "Русский",
         "zhCN": "简体中文", "koKR": "한국어"}

ENTRY = re.compile(r'^\t\["((?:\\.|[^"\\])*)"\] = "((?:\\.|[^"\\])*)",(\s*-- draft)?\s*$')
STALE = re.compile(r'^-- stale: \["((?:\\.|[^"\\])*)"\] = "((?:\\.|[^"\\])*)",(\s*-- draft)?\s*$')


def lua_quote(s):
    out = []
    for c in s:
        if c == "\\":
            out.append("\\\\")
        elif c == '"':
            out.append('\\"')
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        else:
            out.append(c)
    return "".join(out)


def path_of(root, code):
    return os.path.join(root, ADDON, code + ".lua")


def read(root, code):
    """{english: (translation, draft)} and {english: (translation, draft)} of the stale lines; {} for no file."""
    p = path_of(root, code)
    live, stale = {}, {}
    if not os.path.isfile(p):
        return live, stale
    with open(p, encoding="utf-8") as fh:
        for line in fh.read().split("\n"):
            m = ENTRY.match(line)
            if m:
                live[S.unquote('"' + m.group(1) + '"')] = (S.unquote('"' + m.group(2) + '"'), bool(m.group(3)))
                continue
            m = STALE.match(line)
            if m:
                stale[S.unquote('"' + m.group(1) + '"')] = (S.unquote('"' + m.group(2) + '"'), bool(m.group(3)))
    return live, stale


HEAD = '''-- MelloUI Languages: {name} ({code}). The configurator's and the installer's lines, English -> {name}.
-- Written by Tools/languages/languages.py from the addon's English and the translations; a line ending in
-- "-- draft" is a machine draft no translator has checked yet. A line missing here shows in English.
local Lang = MelloUI and MelloUI.Lang
if not (Lang and Lang:Wants("{code}")) then
	return
end
Lang:Add("{code}", {{
'''


def group_of(where):
    return where.split(":")[0]


def write(root, code, lines, live, stale):
    """The file in its one form: the English order, a comment per source, stale lines as comments at its end."""
    english = {s for s, _ in lines}
    out = [HEAD.format(name=NAMES[code], code=code)]
    last = None
    for s, where in lines:
        if s not in live:
            continue
        g = group_of(where)
        if g != last:
            out.append("\t-- %s\n" % g)
            last = g
        t, draft = live[s]
        out.append('\t["%s"] = "%s",%s\n' % (lua_quote(s), lua_quote(t), " -- draft" if draft else ""))
    out.append("})\n")
    gone = dict(stale)
    for s, v in live.items():
        if s not in english:
            gone[s] = v
    gone = {s: v for s, v in gone.items() if s not in english}
    if gone:
        out.append("\n-- No longer in the addon (kept for a line that comes back; never loaded):\n")
        for s in sorted(gone):
            t, draft = gone[s]
            out.append('-- stale: ["%s"] = "%s",%s\n' % (lua_quote(s), lua_quote(t), " -- draft" if draft else ""))
    os.makedirs(os.path.dirname(path_of(root, code)), exist_ok=True)
    with open(path_of(root, code), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("".join(out))


# ---------------------------------------------------------------------------------------------------------------
# the problems

# (no space flag: "60 % davon" is prose, never a format MelloUI writes)
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?[-+#0]*\d*(?:\.\d+)?([sdfgixXc])")
MARKUP = re.compile(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t|\|A[^|]*\|a|\|n")


def placeholders(s):
    """The format's arguments as (position, kind), in argument order: "%2$s" is position 2."""
    s = s.replace("%%", "")
    out, n = [], 0
    for m in PLACEHOLDER.finditer(s):
        if m.group(1):
            out.append((int(m.group(1)), m.group(2)))
        else:
            n += 1
            out.append((n, m.group(2)))
    return sorted(out)


def problems_of(en, tr):
    out = []
    if placeholders(en) != placeholders(tr):
        out.append("placeholders %s, the English has %s" % ([k for _, k in placeholders(tr)],
                                                         [k for _, k in placeholders(en)]))
    a, b = sorted(MARKUP.findall(en)), sorted(MARKUP.findall(tr))
    if a != b:
        out.append("markup %s, the English has %s" % (b, a))
    if not tr.strip():
        out.append("empty")
    return out


def loads(root, code):
    """None when the file loads in Lua (lupa 5.1) and builds its table; else why not."""
    p = path_of(root, code)
    if not os.path.isfile(p):
        return None
    import lupa.lua51 as L51
    lua = L51.LuaRuntime()
    with open(p, encoding="utf-8") as fh:
        src = fh.read()
    f = lua.eval("function(s, code) local f, e = loadstring(s, '@' .. code .. '.lua') if not f then return 'syntax: ' .. e end "
                 "local got MelloUI = { Lang = { Wants = function(_, c) return c == code end, "
                 "Add = function(_, c, t) got = type(t) == 'table' and c end } } "
                 "local ok, err = pcall(f) if not ok then return tostring(err) end "
                 "if got ~= code then return 'no Lang:Add(\"' .. code .. '\", {...})' end return nil end")
    return f(src, code)


def status(root, lines, codes=CODES):
    english = [s for s, _ in lines]
    rows, problems = [], []
    for code in codes:
        live, _ = read(root, code)
        why = loads(root, code)
        if why:
            problems.append("%s.lua does not load: %s" % (code, why))
        have = [s for s in english if s in live]
        drafts = sum(1 for s in have if live[s][1])
        stale = [s for s in live if s not in set(english)]
        for s in have:
            for p in problems_of(s, live[s][0]):
                problems.append("%s: %s -- %r" % (code, p, s[:70]))
        rows.append((code, len(english), len(have), drafts, len(english) - len(have), len(stale)))
    return rows, problems


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", choices=["status", "check", "missing", "todo", "add", "write"])
    ap.add_argument("code", nargs="?")
    ap.add_argument("file", nargs="?")
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    if a.what in ("missing", "todo", "add", "write") and a.code not in CODES:
        sys.exit("name a language: %s" % ", ".join(CODES))
    lines = S.collect(a.root)
    if a.what in ("status", "check"):
        rows, problems = status(a.root, lines)
        print("%-6s %6s %10s %7s %8s %6s" % ("", "lines", "translated", "drafts", "missing", "stale"))
        for code, n, have, drafts, missing, stale in rows:
            print("%-6s %6d %10d %7d %8d %6d" % (code, n, have, drafts, missing, stale))
        for p in problems:
            print("  " + p)
        print("languages: %d problem%s" % (len(problems), "" if len(problems) == 1 else "s"))
        return 1 if (a.what == "check" and problems) else 0
    live, stale = read(a.root, a.code)
    if a.what == "missing":
        for s, where in lines:
            if s not in live:
                print("%s\t%s" % (where, s.replace("\n", "\\n")))
        return 0
    if a.what == "todo":
        import glossary as G
        terms = G.terms_for([s for s, _ in lines if s not in live], a.code)
        todo = [{"en": s, "where": where, "terms": terms.get(s, {})} for s, where in lines if s not in live]
        out = a.file or ("%s_todo.json" % a.code)
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(todo, fh, ensure_ascii=False, indent=1)
        print("%d lines to translate -> %s" % (len(todo), out))
        return 0
    if a.what == "add":
        with open(a.file, encoding="utf-8") as fh:
            new = json.load(fh)
        english = {s for s, _ in lines}
        added = kept = unknown = bad = 0
        for en, tr in new.items():
            if en not in english:
                unknown += 1
                continue
            if not isinstance(tr, str) or problems_of(en, tr):
                bad += 1
                print("  not added (%s): %r" % ("; ".join(problems_of(en, tr)) if isinstance(tr, str) else "no text",
                                               en[:70]))
                continue
            if en in live and not live[en][1]:
                kept += 1   # (a checked line stays)
                continue
            live[en] = (tr, True)
            added += 1
        write(a.root, a.code, lines, live, stale)
        print("%s: %d drafts added, %d checked lines kept, %d unknown, %d refused" % (a.code, added, kept, unknown, bad))
        return 0
    if a.what == "write":
        write(a.root, a.code, lines, live, stale)
        print("%s written" % path_of(a.root, a.code))
        return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
