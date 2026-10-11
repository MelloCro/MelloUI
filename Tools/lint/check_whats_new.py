"""
The configurator's What's new (Core/Config.lua's CHANGELOG table, Home's card)
kept in step with CHANGELOG.md (the user, 2026-10-11: "you need to update
'whats new' section in the Configurator, and keep it updated" -- "keep only the
last 5 whats new sections"; it had stopped at 0.18.1 while 0.20.1 was being
made). It holds the five newest CHANGELOG.md sections, newest first, no more:
the version in the works on top as soon as its section is, the oldest dropped
as a new one comes in. The newest entry fits Home's column (at most 12 lines,
1900 characters), and like the release notes it speaks of the addon only (no
tools: release.py's TOOL_TALK).

    python Tools/lint/check_whats_new.py                 # the check (the suite runs it)
    python Tools/lint/check_whats_new.py --version X.Y.Z # and the top is X.Y.Z (release.py runs it)

Exit 0 and "what's new: up to date" when it holds; 1 and each problem when not.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
KEEP = 5                     # the user: "keep only the last 5"
MAX_LINES, MAX_CHARS = 12, 1900   # the newest entry, in Home's one-column card

# the same words release.py refuses in the release notes
TOOL_TALK = re.compile(
    r"/mkit|\bkitforge\b|MelloUIKitEditor|kit editor|editing tools?|development tools?|\bMBot\b"
    r"|Tools[\\/]|\.py\b|release\.py|release workflow|luacheck|\blint\b",
    re.I,
)


def changelog_versions():
    with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as fh:
        return re.findall(r"^## (\S+)[ \t]*$", fh.read(), re.M)


def whats_new():
    """[(version, [line, ...]), ...] from Config.lua's CHANGELOG table, in its order"""
    with open(os.path.join(ROOT, "Core", "Config.lua"), encoding="utf-8") as fh:
        src = fh.read().replace("\r\n", "\n")
    start = src.find("\nlocal CHANGELOG = {\n")
    if start < 0:
        return None
    end = src.find("\n}\n", start)
    block = src[start:end]
    out = []
    for m in re.finditer(r'\{ version = "([^"]+)", lines = \{\n(.*?)\n\t\} \},', block, re.S):
        out.append((m.group(1), re.findall(r'^\t\t"(.*)",$', m.group(2), re.M)))
    return out


def problems(version=None):
    found = []
    md = changelog_versions()
    news = whats_new()
    if news is None:
        return ["Core/Config.lua has no 'local CHANGELOG = {' table"]
    if not md:
        return ["CHANGELOG.md has no '## <version>' sections"]
    have = [v for v, _ in news]
    want = md[:KEEP]
    if have != want:
        found.append("What's new holds %s; it should hold CHANGELOG.md's %d newest, %s (newest first: add the new "
                     "version on top, drop the oldest)" % (", ".join(have) or "nothing", len(want), ", ".join(want)))
    if version and md[0] != version:
        found.append("CHANGELOG.md's newest section is %s, not %s" % (md[0], version))
    if version and (not have or have[0] != version):
        found.append("What's new's newest entry is %s, not %s" % (have[0] if have else "none", version))
    for v, lines in news:
        if not lines:
            found.append("What's new's %s entry has no lines" % v)
        for line in lines:
            if TOOL_TALK.search(line):
                found.append("What's new's %s entry talks about the tools: %s" % (v, line[:120]))
    if news:
        v, lines = news[0]
        chars = sum(len(line) for line in lines)
        if len(lines) > MAX_LINES or chars > MAX_CHARS:
            found.append("What's new's newest entry (%s) is %d lines, %d characters: at most %d and %d fit Home's "
                         "column" % (v, len(lines), chars, MAX_LINES, MAX_CHARS))
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", help="the version being released: What's new's top entry must be it")
    a = ap.parse_args()
    found = problems(a.version)
    if found:
        print("what's new: %d problem%s" % (len(found), "" if len(found) == 1 else "s"))
        for p in found:
            print("  " + p)
        sys.exit(1)
    news = whats_new()
    print("what's new: up to date (%s)" % ", ".join(v for v, _ in news))


if __name__ == "__main__":
    main()
