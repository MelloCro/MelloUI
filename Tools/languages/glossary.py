"""The game's own words for the terms MelloUI's lines use (docs/plans/languages.md: game terms must match each
client's words). Blizzard's GlobalStrings for the client's build, per locale, from wago.tools (the client keeps them
in a DB2, not in the UI files the export holds):

    https://wago.tools/db2/GlobalStrings/csv?build=<build>&locale=<code>

cached in MelloUI-BuildData/cache/globalstrings/<build>/<code>.csv (Blizzard's data: local only, never in the
repository or a release). A term is a game string's whole English text (one to four words: "Action Bars", "Quest
Log", "Nameplates", "Edit Mode") found in a line as whole words; its translation is the same string's in the locale.

    python Tools/languages/glossary.py fetch [--build 1.60.1.70425]      the CSVs (once)
    python Tools/languages/glossary.py show deDE "Show the Action Bars"   the terms of a line
    from glossary import terms_for; terms_for(lines, "deDE") -> {line: {term: translation}}
"""
import csv
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path.insert(0, TOOLS)
try:
    from paths import CACHE  # noqa: E402
except Exception:  # pragma: no cover
    CACHE = os.path.join(os.path.dirname(os.path.dirname(TOOLS)), "MelloUI-BuildData", "cache")

BUILD = "1.60.1.70425"
LOCALES = ["enUS", "deDE", "frFR", "esES", "esMX", "ptBR", "ruRU", "zhCN", "koKR"]
URL = "https://wago.tools/db2/GlobalStrings/csv?build={build}&locale={code}"
csv.field_size_limit(10 ** 7)


def folder(build=BUILD):
    return os.path.join(CACHE, "globalstrings", build)


def fetch(build=BUILD):
    os.makedirs(folder(build), exist_ok=True)
    for code in LOCALES:
        out = os.path.join(folder(build), code + ".csv")
        if os.path.isfile(out) and os.path.getsize(out) > 100000:
            continue
        req = urllib.request.Request(URL.format(build=build, code=code), headers={"User-Agent": "MelloUI tools"})
        with urllib.request.urlopen(req, timeout=120) as r, open(out, "wb") as fh:
            fh.write(r.read())
        print("fetched", code, os.path.getsize(out))


def table(code, build=BUILD):
    """{BaseTag: text} of a locale."""
    p = os.path.join(folder(build), code + ".csv")
    if not os.path.isfile(p):
        raise SystemExit("no %s: python Tools/languages/glossary.py fetch" % p)
    with open(p, encoding="utf-8", newline="") as fh:
        return {row["BaseTag"]: row["TagText_lang"] for row in csv.DictReader(fh)}


_terms = {}


def terms(code, build=BUILD):
    """{english term: the locale's text}: the game strings of one to four words with no markup or placeholder whose
    English names one thing (the same English under several tags: the most common translation)."""
    key = (code, build)
    if key in _terms:
        return _terms[key]
    en, tr = table("enUS", build), table(code, build)
    votes = {}
    for tag, text in en.items():
        t = text.strip()
        if not t or "%" in t or "|" in t or "\\" in t or len(t) > 40 or not re.match(r"^[A-Z][A-Za-z'&\- ]+$", t):
            continue
        if len(t.split()) > 4 or tag not in tr or not tr[tag].strip():
            continue
        votes.setdefault(t, {}).setdefault(tr[tag].strip(), 0)
        votes[t][tr[tag].strip()] += 1
    out = {t: max(v.items(), key=lambda kv: kv[1])[0] for t, v in votes.items()}
    _terms[key] = out
    return out


def terms_for(lines, code, build=BUILD):
    """{line: {term: translation}} for the terms each line holds as whole words (longest first; a shorter term inside
    a longer one found is left out). Single common words are left out (Show, Hide, On ... their sense varies)."""
    t = terms(code, build)
    common = {"Show", "Hide", "On", "Off", "Yes", "No", "Okay", "Cancel", "Accept", "Close", "None", "All", "Other",
              "New", "Default", "Normal", "Small", "Large", "Left", "Right", "Top", "Bottom", "Center", "Size", "Name",
              "Level", "Text", "Done", "Back", "Next", "Reset", "Enable", "Disable", "Enabled", "Disabled", "Options"}
    keys = sorted((k for k in t if k not in common and (" " in k or len(k) > 4)), key=len, reverse=True)
    pats = [(k, re.compile(r"(?<![A-Za-z])" + re.escape(k) + r"(?![A-Za-z])")) for k in keys]
    out = {}
    for line in lines:
        found, taken = {}, []
        for k, p in pats:
            for m in p.finditer(line):
                span = m.span()
                if any(a <= span[0] and span[1] <= b for a, b in taken):
                    continue
                taken.append(span)
                found[k] = t[k]
        if found:
            out[line] = found
    return out


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "fetch":
        b = sys.argv[sys.argv.index("--build") + 1] if "--build" in sys.argv else BUILD
        fetch(b)
    elif len(sys.argv) >= 4 and sys.argv[1] == "show":
        for k, v in terms_for([sys.argv[3]], sys.argv[2]).get(sys.argv[3], {}).items():
            print("%s -> %s" % (k, v))
    else:
        print(__doc__)
