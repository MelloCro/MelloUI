"""
Cut a release in one command: bump the TOC version, commit everything pending,
tag it and push. The GitHub Action then packages the addon and uploads it to
CurseForge and the GitHub release (see .github/workflows/release.yml).

    python Tools\release.py                 # patch bump: 0.13.1 -> 0.13.2
    python Tools\release.py minor           # 0.13.1 -> 0.14.0
    python Tools\release.py major           # 0.13.1 -> 1.0.0
    python Tools\release.py 0.15.3          # exact version
    python Tools\release.py -m "text"       # extra line for the commit message
    python Tools\release.py --dry-run       # show what would happen, change nothing
    python Tools\release.py --no-push       # commit and tag locally only

Learned map pins and routes are already baked into Media/RouteData.lua by the
baker, so they ship with whatever release comes next; nothing to do by hand.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TOC = os.path.join(ROOT, "MelloUI.toc")


def git(*args, capture=True):
    r = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=capture)
    if r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{(r.stderr or r.stdout or '').strip()}")
    return (r.stdout or "").strip()


def read_version():
    with open(TOC, encoding="utf-8") as fh:
        text = fh.read()
    m = re.search(r"^## Version:\s*(\d+)\.(\d+)\.(\d+)\s*$", text, re.M)
    if not m:
        sys.exit("no '## Version: X.Y.Z' line in MelloUI.toc")
    return text, tuple(int(x) for x in m.groups())


def bump(current, how):
    major, minor, patch = current
    if how == "major":
        return (major + 1, 0, 0)
    if how == "minor":
        return (major, minor + 1, 0)
    if how == "patch":
        return (major, minor, patch + 1)
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", how)
    if not m:
        sys.exit(f"'{how}' is not major/minor/patch or a version like 0.14.0")
    return tuple(int(x) for x in m.groups())


def release_notes(version):
    """The bullets of the version's CHANGELOG.md section, which the packager
    publishes as the release notes. The section must exist and be the newest."""
    changelog = os.path.join(ROOT, "CHANGELOG.md")
    with open(changelog, encoding="utf-8") as fh:
        text = fh.read()
    sections = re.findall(r"^## (\S+)[ \t]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not sections:
        sys.exit("CHANGELOG.md has no '## <version>' sections")
    top, body = sections[0]
    if top != version:
        sys.exit(f"the newest CHANGELOG.md section is '{top}', not '{version}'; add the version's bullets on top first")
    bullets = [line.rstrip() for line in body.splitlines() if line.strip()]
    if not bullets:
        sys.exit(f"the '## {version}' section of CHANGELOG.md is empty; add what changed")
    offending = [b for b in bullets if TOOL_TALK.search(b)]
    if offending:
        sys.exit("the release notes talk about the tools, not the addon -- CHANGELOG.md, and with it "
                 "GitHub, CurseForge and the Discord post, only say what changed in MelloUI itself:\n"
                 + "\n".join("  " + b[:160] for b in offending))
    return "\n".join(bullets)


# The release notes describe the ADDON and nothing else (user, 2026-09-23:
# "Changes to the tools, including /mkit and kitforge should be excluded from
# the changelog and releases, discord bot and github and curseforge should only
# state the changes in the MelloUI addon itself"). One CHANGELOG.md section
# feeds all three, so the check sits here, before anything is tagged. It names
# the tools that do not ship -- the kit editor and kitforge, MBot, the build
# scripts in Tools/, the release plumbing -- and refuses the release if a
# bullet mentions one; reword the bullet (or drop it) and run again.
TOOL_TALK = re.compile(
    r"/mkit|\bkitforge\b|MelloUIKitEditor|kit editor|editing tools?|development tools?|\bMBot\b"
    r"|Tools[\\/]|\.py\b|release\.py|release workflow|luacheck|\blint\b",
    re.I,
)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("how", nargs="?", default="patch", help="major | minor | patch (default) | X.Y.Z")
    ap.add_argument("-m", "--message", default="", help="extra text for the commit message")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-push", action="store_true")
    a = ap.parse_args()

    text, current = read_version()
    new = bump(current, a.how)
    if new <= current:
        sys.exit(f"{'.'.join(map(str, new))} is not newer than the current {'.'.join(map(str, current))}")
    version = ".".join(map(str, new))
    tag = "v" + version

    if git("tag", "--list", tag):
        sys.exit(f"tag {tag} already exists")
    notes = release_notes(version)
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch != "main":
        sys.exit(f"releases are cut from main; you are on {branch}")
    pending = git("status", "--short")

    print(f"{'.'.join(map(str, current))} -> {version}  (tag {tag}, branch {branch})")
    print("release notes (CHANGELOG.md):")
    print("  " + notes.replace("\n", "\n  "))
    if pending:
        print("pending changes that go into the release commit:")
        print("  " + pending.replace("\n", "\n  "))
    else:
        print("no pending changes; only the version bump is committed")
    if a.dry_run:
        print("dry run: nothing changed")
        return

    text = re.sub(r"^## Version:.*$", f"## Version: {version}", text, count=1, flags=re.M)
    with open(TOC, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)

    message = f"Release {version}"
    if a.message:
        message += "\n\n" + a.message
    git("add", "-A")
    git("commit", "-m", message)
    git("tag", "-a", tag, "-m", message)
    print(f"committed and tagged {tag}")
    if a.no_push:
        print("not pushed (--no-push). Later:  git push origin main --tags")
        return
    git("push", "origin", "main", "--tags", capture=False)
    remote = git("remote", "get-url", "origin").replace(".git", "")
    print(f"pushed. Watch the packager at {remote}/actions ; the release appears at {remote}/releases/tag/{tag}")


if __name__ == "__main__":
    main()
