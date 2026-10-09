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

The companion addons ship in the same zip: every MelloUI_<x> folder at the
repository root with its own MelloUI_<x>.toc (MelloUI_Companion, Route's data;
and since 0.19.9 the feature addons, docs/plans/split-addons.md, e.g.
MelloUI_CombatText). The bump writes MelloUI.toc's Version and Interface into
every TOC, and the release is refused while a TOC lists a file that does not
exist, a companion does not depend on MelloUI, a data companion is not
load-on-demand, a feature addon (## X-MelloUI-Feature: <module>) is not the
one Core/Core.lua's MelloUI.Features names for it (or one listed there has no
folder), or .pkgmeta does not lift a companion out of the MelloUI folder.

The shipped Full experience (the "MelloUI" profile in Media/Profiles.lua,
which the installer applies) must be exactly what Tools/installer/bake_full.py
makes from its snapshot through the current code, and the file must hold no
other profile (the saved-profiles watcher keeps a player's own ones there):
the release runs `bake_full.py --check` and is refused otherwise.

Every option new since the previous release carries the release's New tag (the user's rule, 2026-09-26: every
new dropdown, slider, check box ... gets a "New" tag for its update, the old ones go): the release runs
`Tools/lint/check_new_tags.py --version <version>` and is refused on a new option without `new = "<version>"` or
an older one tagged so (and when it cannot check: a file or a module's OnInit that fails in its world, or a --fix
that would leave a file that does not compile -- every file is then put back); the tags of older versions are taken
out of the files (its --fix; a dry run only lists them), and go into the release commit.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TOC = os.path.join(ROOT, "MelloUI.toc")
PKGMETA = os.path.join(ROOT, ".pkgmeta")
FULL_BAKE = os.path.join(HERE, "installer", "bake_full.py")
NEW_TAGS = os.path.join(HERE, "lint", "check_new_tags.py")


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


def companions():
    """The companion addons that ship beside MelloUI: (folder, path of its TOC)."""
    out = []
    for name in sorted(os.listdir(ROOT)):
        toc = os.path.join(ROOT, name, name + ".toc")
        if name.startswith("MelloUI_") and os.path.isfile(toc):
            out.append((name, toc))
    return out


def toc_field(text, field):
    """A '## Field: value' line's value (MelloUI.toc starts with a BOM), or None."""
    m = re.search(r"^﻿?## " + re.escape(field) + r":[ \t]*(.*?)[ \t]*$", text, re.M)
    return m.group(1) if m else None


def toc_files(text):
    """The files a TOC lists, with forward slashes."""
    files = []
    for line in text.splitlines():
        line = line.strip().lstrip("﻿")
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def check_tocs(main_text):
    """Every file a TOC lists exists, every companion is load-on-demand on MelloUI and is lifted
    out of the MelloUI folder in the zip. Returns the companions and the problems found."""
    problems = []
    comps = companions()
    names = {name for name, _ in comps}
    # (0.19.9) the feature addons Core/Core.lua knows: { module: addon }
    with open(os.path.join(ROOT, "Core", "Core.lua"), encoding="utf-8") as fh:
        features = dict(re.findall(r'^\t(\w+) = \{ addon = "(MelloUI_\w+)"', fh.read(), re.M))
    seen_features = set()
    for f in toc_files(main_text):
        if f.split("/")[0] in names:
            problems.append(f"MelloUI.toc lists {f}: {f.split('/')[0]} is an addon of its own, its files go in its own TOC")
        elif not os.path.isfile(os.path.join(ROOT, f)):
            problems.append(f"MelloUI.toc lists {f}, which does not exist")
    for name, path in comps:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        for f in toc_files(text):
            if not os.path.isfile(os.path.join(ROOT, name, f)):
                problems.append(f"{name}.toc lists {f}, which does not exist")
        # (one module, or several of one addon: '## X-MelloUI-Feature: FrameEffects HealFlight')
        feature = toc_field(text, "X-MelloUI-Feature")
        # (a data companion loads on demand; a feature addon loads with MelloUI, at login)
        wants = (("Dependencies", "MelloUI"),) if feature else (("LoadOnDemand", "1"), ("Dependencies", "MelloUI"))
        for field, want in wants:
            if toc_field(text, field) != want:
                problems.append(f"{name}.toc needs '## {field}: {want}'")
        for module in (feature or "").split():
            if features.get(module) != name:
                problems.append(f"{name}.toc is the feature {module}, but Core/Core.lua's MelloUI.Features names "
                                f"{features.get(module) or 'no addon'} for it")
            seen_features.add(module)
        for field in ("Version", "Interface"):
            if toc_field(text, field) is None:
                problems.append(f"{name}.toc has no '## {field}:' line to keep in step with MelloUI.toc")
    for feature, addon in sorted(features.items()):
        if feature not in seen_features:
            problems.append(f"Core/Core.lua's MelloUI.Features lists {feature} ({addon}), which has no folder "
                            f"{addon}/{addon}.toc naming it on its '## X-MelloUI-Feature:' line")
    with open(PKGMETA, encoding="utf-8") as fh:
        meta = fh.read()
    for name in sorted(names):
        line = r"^[ \t]+MelloUI/" + re.escape(name) + r":[ \t]*" + re.escape(name) + r"[ \t]*$"
        if not re.search(line, meta, re.M):
            problems.append(f".pkgmeta does not move {name} out of MelloUI (move-folders: MelloUI/{name}: {name}); "
                            "the zip would carry it inside the MelloUI folder, where the client never finds it")
    for moved in re.findall(r"^[ \t]+MelloUI/(\S+?):", meta, re.M):
        if moved not in names:
            problems.append(f".pkgmeta moves MelloUI/{moved}, which is not a companion folder with its own TOC")
    return comps, problems


def check_full():
    """The shipped Full experience is the current bake and the only profile in Media/Profiles.lua
    (Tools/installer/bake_full.py --check, one load try). Returns (ok, lines): on success the bake's
    length and sha256, else what the check printed (the cause, the fix, what changed in Full)."""
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    try:
        r = subprocess.run([sys.executable, FULL_BAKE, "--check", "--tries", "1"], cwd=ROOT, env=env,
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, [f"the bake did not run: {exc}"]
    lines = [line.rstrip() for line in ((r.stdout or "") + (r.stderr or "")).splitlines() if line.strip()]
    if r.returncode != 0:
        return False, lines[-30:] or [f"bake_full.py --check exited {r.returncode}"]
    now = [line for line in lines if line.startswith("Full baked now:")]
    return True, [now[0].replace("Full baked now:", "").strip() if now else "up to date"]


def check_new_tags(version, fix):
    """Every option new since the previous release tagged new = version, no older one tagged so
    (Tools/lint/check_new_tags.py --version <version>, with --fix: the older versions' tags taken out of the
    files first). Returns (ok, lines): on success its summary and what it took out, else its problems."""
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    cmd = [sys.executable, NEW_TAGS, "--version", version] + (["--fix"] if fix else [])
    try:
        r = subprocess.run(cmd, cwd=ROOT, env=env, capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=900)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, [f"the check did not run: {exc}"]
    lines = [line.rstrip() for line in ((r.stdout or "") + (r.stderr or "")).splitlines() if line.strip()]
    keep = [line for line in lines if line.startswith(("FAIL", "stale", "gone", "--fix", "problems by file", "new tags:",
                                                        "check_new_tags could not check", "  "))]
    if r.returncode != 0:
        return False, keep or lines[-30:] or [f"check_new_tags.py exited {r.returncode}"]
    return True, keep or lines[-1:]


def write_tocs(edits, version, interface):
    """The Version and Interface lines of every TOC in `edits` ((path, label, text) each)."""
    for path, _, body in edits:
        # MelloUI.toc's BOM stays: read and written as utf-8, it is the first character
        body = re.sub(r"^(﻿?)## Version:.*$", lambda m: m.group(1) + "## Version: " + version, body, count=1, flags=re.M)
        body = re.sub(r"^(﻿?)## Interface:.*$", lambda m: m.group(1) + "## Interface: " + interface, body, count=1, flags=re.M)
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(body)


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
    comps, problems = check_tocs(text)
    if problems:
        sys.exit("the TOCs are not ready for a release:\n" + "\n".join("  " + p for p in problems))
    full_ok, full_lines = check_full()
    if not full_ok:
        sys.exit("the shipped Full experience (the \"MelloUI\" profile in Media/Profiles.lua) is not ready for a "
                 "release (python Tools/installer/bake_full.py --check):\n" + "\n".join("  " + p for p in full_lines))
    interface = toc_field(text, "Interface")
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
    # the New tags: this version's on every new option, the older ones taken out (not in a dry run)
    tags_ok, tags_lines = check_new_tags(version, fix=not a.dry_run)
    if not tags_ok:
        sys.exit(f"the New tags are not ready for {version} (python Tools/lint/check_new_tags.py --version "
                 f"{version}):\n" + "\n".join("  " + line for line in tags_lines))
    pending = git("status", "--short")

    print(f"{'.'.join(map(str, current))} -> {version}  (tag {tag}, branch {branch})")
    print("release notes (CHANGELOG.md):")
    print("  " + notes.replace("\n", "\n  "))
    if pending:
        print("pending changes that go into the release commit:")
        print("  " + pending.replace("\n", "\n  "))
    else:
        print("no pending changes; only the version bump is committed")
    # every TOC carries MelloUI's Version and Interface (in game, a companion
    # from another version is refused)
    edits = [(TOC, "MelloUI.toc", text)]
    for name, path in comps:
        with open(path, encoding="utf-8") as fh:
            edits.append((path, f"{name}/{name}.toc", fh.read()))
    for _, label, body in edits:
        print(f"{label}: Version {toc_field(body, 'Version')} -> {version}, Interface {toc_field(body, 'Interface')} -> {interface}")
    print(f"Full experience (Media/Profiles.lua \"MelloUI\"): the current bake, {full_lines[0]}")
    print("New tags: " + "\n  ".join(tags_lines))
    if a.dry_run:
        print("dry run: nothing changed")
        return

    write_tocs(edits, version, interface)

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
