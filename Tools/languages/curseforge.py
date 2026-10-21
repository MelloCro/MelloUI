"""MelloUI's translations on CurseForge (the user's pick, 2026-10-20: translators work on CurseForge's localization
page; docs/plans/languages.md). CurseForge is the translators' workbench; the repository stays what ships: nothing is
substituted at packaging, so the release candidate that was tested is what goes out.

    python Tools/languages/curseforge.py push [--send]        the English lines as CurseForge's phrases (enUS), then
                                                              each language's drafts for the phrases CurseForge has no
                                                              translation of yet (a translator's line is never replaced)
    python Tools/languages/curseforge.py pull [--send]        CurseForge's translations into MelloUI_Languages/<code>.lua:
                                                              a line that differs from our draft was edited by a person
                                                              and loses its "-- draft" mark; a line equal to the draft
                                                              keeps it
    ... --project 1702190   (MelloUI's CurseForge project, the TOC's X-Curse-Project-ID)

Without --send nothing leaves this machine: the tool prints what it would send or fetch. --send needs the
CurseForge API token in the environment (CF_API_KEY, the one the release workflow uses; never in the project).
Every --send is an outward action: run it only when the user says so.

The API (CurseForge's authors API, the one BigWigs' packager reads):
    GET  https://wow.curseforge.com/api/projects/<id>/localization/export?lang=<code>&unlocalized=Ignore
    POST https://wow.curseforge.com/api/projects/<id>/localization/import   (form: metadata, localizations)
both with the header X-Api-Token. The phrases are keyed by their English (as MelloUI's tables are).
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import languages as L  # noqa: E402
import strings as S  # noqa: E402

SITE = "https://wow.curseforge.com/api/projects/%s/localization/%s"
LINE = re.compile(r'^L\["((?:\\.|[^"\\])*)"\]\s*=\s*"((?:\\.|[^"\\])*)"\s*$')


def table_additions(pairs):
    return "\n".join('L["%s"] = "%s"' % (L.lua_quote(k), L.lua_quote(v)) for k, v in pairs) + "\n"


def parse_additions(text):
    out = {}
    for line in text.split("\n"):
        m = LINE.match(line.strip())
        if m:
            out[S.unquote('"' + m.group(1) + '"')] = S.unquote('"' + m.group(2) + '"')
    return out


def token():
    t = os.environ.get("CF_API_KEY")
    if not t:
        sys.exit("CF_API_KEY is not set: the CurseForge API token (never written into the project)")
    return t


def export(project, code, send):
    url = (SITE % (project, "export")) + "?" + urllib.parse.urlencode({"lang": code, "unlocalized": "Ignore"})
    if not send:
        print("would fetch", url)
        return None
    req = urllib.request.Request(url, headers={"X-Api-Token": token(), "User-Agent": "MelloUI tools"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return parse_additions(r.read().decode("utf-8"))


def import_(project, code, pairs, send):
    meta = {"language": code, "namespace": "", "formatType": "TableAdditions", "missing-phrase-handling": "DoNothing"}
    body = table_additions(pairs)
    url = SITE % (project, "import")
    if not send:
        print("would send %d %s lines to %s" % (len(pairs), code, url))
        return
    boundary = "----MelloUI%d" % os.getpid()
    parts = []
    for name, value in (("metadata", json.dumps(meta)), ("localizations", body)):
        parts.append("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, name, value))
    data = ("".join(parts) + "--%s--\r\n" % boundary).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "X-Api-Token": token(), "User-Agent": "MelloUI tools",
        "Content-Type": "multipart/form-data; boundary=%s" % boundary})
    with urllib.request.urlopen(req, timeout=300) as r:
        print(code, r.status, r.read()[:200])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("what", choices=["push", "pull"])
    ap.add_argument("--send", action="store_true")
    ap.add_argument("--project", default="1702190")
    ap.add_argument("--root", default=L.ROOT)
    a = ap.parse_args()
    lines = S.collect(a.root)
    if a.what == "push":
        import_(a.project, "enUS", [(s, s) for s, _ in lines], a.send)
        for code in L.CODES:
            live, _ = L.read(a.root, code)
            have = export(a.project, code, a.send) or {}
            drafts = [(s, live[s][0]) for s, _ in lines if s in live and live[s][1] and s not in have]
            if drafts:
                import_(a.project, code, drafts, a.send)
        return 0
    for code in L.CODES:
        theirs = export(a.project, code, a.send)
        if theirs is None:
            continue
        live, stale = L.read(a.root, code)
        changed = 0
        for s, _ in lines:
            t = theirs.get(s)
            if t is None or L.problems_of(s, t):
                continue
            mine = live.get(s)
            if mine is None or mine[0] != t:
                live[s] = (t, False)
                changed += 1
        L.write(a.root, code, lines, live, stale)
        print("%s: %d lines from CurseForge" % (code, changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
