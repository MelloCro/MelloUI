"""The saved-profiles writer of Tools/bake_routes.py never touches what ships.

  python Tools/installer/test_profiles_writer.py

The watcher (bake_routes.py --watch) keeps the player's own saved profiles
in Media/Profiles.lua. Run here on copies of that file (in a temporary
folder; the repository's file is only read), with saved profiles that hold
a player's own "MelloUI" and "Everything Off" besides their own ones:
  - the shipped "MelloUI" entry, the head (comments, `default`) and the tail
    come out byte for byte; a saved profile under a shipped name is skipped;
  - the player's own profiles are written, Lua 5.1 reads them back exactly
    (quotes, backslashes, a line break), sorted by name with the shipped one;
  - a profile deleted from the saved variables leaves the file; the shipped
    entries stay;
  - a second run with the same profiles does not write the file again;
  - an "Everything Off" line already in the file is kept as it is (the writer
    neither writes nor removes a shipped name);
  - a file in a layout the writer does not know is left alone;
  - the game's copy, missing, is made from the project's file (its head and
    shipped entries);
  - the whole watcher path, bake(): a saved MelloUI.lua in a stand-in WTF
    folder, both outputs redirected into the temporary folder;
  - bake_full.py --check names the player's own profile the watcher kept
    (a release would ship it) and nothing else;
  - the shipped names agree with bake_full.py and with Core's built-in profile.
"""
import os
import re
import shutil
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ADDON = os.path.dirname(TOOLS)
sys.path.insert(0, HERE)
sys.path.insert(0, TOOLS)
import bake_routes as R   # noqa: E402
import bake_full as F     # noqa: E402
import lupa.lua51 as L51  # noqa: E402

PROFILES = os.path.join(ADDON, "Media", "Profiles.lua")
fails = []


def check(cond, what):
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)
    return cond


def raw(path):
    with open(path, "rb") as fh:
        return fh.read()


def load(path):
    """(default, {name: text}) as Lua 5.1 reads the file."""
    lua = L51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(raw(path).decode("utf-8"))
    p = lua.globals().MelloUI_Profiles
    return p.default, {str(k): p.profiles[k] for k in p.profiles.keys()}


def shipped_line(src_bytes, name):
    for line in src_bytes.split(b"\n"):
        if line.startswith(b'\t\t["' + name.encode() + b'"] = '):
            return line
    return None


def head_of(src_bytes):
    i = src_bytes.index(b"\tprofiles = {\n") + len(b"\tprofiles = {\n")
    return src_bytes[:i]


def tail_of(src_bytes):
    return src_bytes[src_bytes.rindex(b"\t},\n}"):]


SAVED = {
    "MelloUI": "UIModifications.kitColours=swarm;!Chat=b1",          # the player's own older copy
    "Everything Off": "!Chat=b0;!Route=b0",                          # Core writes it at every login
    "Raid": "Chat.nameStyle=sfull;UIModifications.autoSnap=b1",
    'Odd "name" \\ here': 'Chat.x=s"quoted" and \\back\\slash\nand a line break',
}


def main():
    original = raw(PROFILES)
    orig_default, orig_profiles = load(PROFILES)
    full_line = shipped_line(original, "MelloUI")
    check(full_line is not None and set(orig_profiles) == {"MelloUI"},
          "the repository's Media/Profiles.lua holds the shipped \"MelloUI\" only (the test's starting point)")

    print("== the shipped names")
    check(set(F.SHIPPED_NAMES) <= set(R.SHIPPED_PROFILES), "bake_full.py's shipped names are among the writer's: %s"
          % sorted(R.SHIPPED_PROFILES))
    core = open(os.path.join(ADDON, "Core", "Core.lua"), encoding="utf-8").read()
    fresh = re.search(r'^MelloUI\.FRESH_PROFILE = "([^"]+)"', core, re.M)
    check(bool(fresh) and fresh.group(1) in R.SHIPPED_PROFILES,
          "Core's built-in profile (%s) is never written by the watcher" % (fresh and fresh.group(1)))

    with tempfile.TemporaryDirectory(prefix="profiles_writer_") as tmp:
        path = os.path.join(tmp, "Profiles.lua")
        shutil.copyfile(PROFILES, path)

        print("== the player's profiles into a copy of the shipped file")
        r = R.write_profiles(SAVED, path)
        after = raw(path)
        check(r is not None and r[0] == sorted(["Raid", 'Odd "name" \\ here']) and r[1] == ["MelloUI"],
              "written: the player's own two; kept: the shipped \"MelloUI\" (%s)" % (r,))
        check(shipped_line(after, "MelloUI") == full_line, "the shipped \"MelloUI\" line survives byte for byte")
        check(head_of(after) == head_of(original), "the head (comments and `default`) survives byte for byte")
        check(tail_of(after) == tail_of(original), "the tail survives byte for byte")
        check(shipped_line(after, "Everything Off") is None, "the saved \"Everything Off\" is not written")
        default, got = load(path)
        check(default == orig_default and got.get("MelloUI") == orig_profiles["MelloUI"],
              "Lua reads the same default and the same shipped Full (not the player's older copy)")
        check(got.get("Raid") == SAVED["Raid"] and got.get('Odd "name" \\ here') == SAVED['Odd "name" \\ here'],
              "Lua reads the player's profiles back exactly (quotes, backslashes, a line break)")
        names = re.findall(rb'^\t\t\["((?:[^"\\]|\\.)*)"\] = ', after, re.M)
        check(names == sorted(names) and len(names) == 3, "one line each, sorted by name with the shipped one: %s" % names)
        check(b"\r" not in after and after.endswith(b"}\n"), "line ends as the file had them")

        print("== again, then with a profile deleted")
        stamp = os.stat(path).st_mtime_ns
        os.utime(path, ns=(stamp - 5_000_000_000, stamp - 5_000_000_000))
        stamp = os.stat(path).st_mtime_ns
        R.write_profiles(SAVED, path)
        check(os.stat(path).st_mtime_ns == stamp and raw(path) == after, "the same profiles again: the file is not written")
        fewer = {k: v for k, v in SAVED.items() if k != "Raid"}
        R.write_profiles(fewer, path)
        third = raw(path)
        check(shipped_line(third, "Raid") is None and b"Odd" in third, "a profile deleted in game leaves the file")
        check(shipped_line(third, "MelloUI") == full_line and head_of(third) == head_of(original),
              "the shipped line and the head are still byte for byte the same")
        R.write_profiles({"MelloUI": "x", "Everything Off": "y"}, path)
        check(raw(path) == original, "with only shipped names saved, the file is the shipped file again, byte for byte")

        print("== an \"Everything Off\" line already in the file")
        eo_line = b'\t\t["Everything Off"] = "!Chat=b0",'
        with_eo = original.replace(full_line + b"\n", eo_line + b"\n" + full_line + b"\n")
        with open(path, "wb") as fh:
            fh.write(with_eo)
        R.write_profiles(SAVED, path)
        got_eo = raw(path)
        check(shipped_line(got_eo, "Everything Off") == eo_line and shipped_line(got_eo, "MelloUI") == full_line,
              "kept exactly as it was (the writer neither writes nor removes a shipped name)")

        print("== a file in another layout")
        odd = b"-- hand-made\nMelloUI_Profiles = { profiles = { MelloUI = \"x\" } }\n"
        with open(path, "wb") as fh:
            fh.write(odd)
        check(R.write_profiles(SAVED, path) is None and raw(path) == odd, "left alone: nothing written")
        broken = original.replace(full_line, full_line + b" -- note")
        with open(path, "wb") as fh:
            fh.write(broken)
        check(R.write_profiles(SAVED, path) is None and raw(path) == broken, "a line it cannot read: left alone")

        print("== the game's copy, missing")
        game_dir = os.path.join(tmp, "game", "Media")
        game = os.path.join(game_dir, "Profiles.lua")
        r = R.write_profiles(SAVED, game, template=PROFILES)
        made = raw(game) if os.path.isfile(game) else b""
        check(r is not None and shipped_line(made, "MelloUI") == full_line and head_of(made) == head_of(original)
              and shipped_line(made, "Raid") is not None, "made from the project's file: its head and shipped line, plus the player's")
        check(raw(PROFILES) == original, "the template (the repository's file) is only read")

        print("== the watcher's whole path (bake)")
        wtf = os.path.join(tmp, "WTF")
        sv_dir = os.path.join(wtf, "Account", "TEST", "SavedVariables")
        os.makedirs(sv_dir)
        body = "MelloUIDB = {\n\tdefaultProfile = \"Everything Off\",\n\tprofiles = {\n"
        for name, text in SAVED.items():
            body += "\t\t[%s] = %s,\n" % (lua_str(name), lua_str(text))
        body += "\t},\n}\nMelloUIRoutes = { graphs = {}, pins = {} }\n"
        with open(os.path.join(sv_dir, "MelloUI.lua"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(body)
        project = os.path.join(tmp, "project", "Media", "Profiles.lua")
        os.makedirs(os.path.dirname(project))
        shutil.copyfile(PROFILES, project)
        game_route = os.path.join(tmp, "game2", "Media", "RouteData.lua")
        os.makedirs(os.path.dirname(game_route))
        shutil.copyfile(PROFILES, os.path.join(os.path.dirname(game_route), "Profiles.lua"))
        saved_out, saved_route = R.PROFILES_OUT, R.PROJECT_OUT
        project_route = os.path.join(tmp, "project", "Media", "RouteData.lua")
        R.PROFILES_OUT, R.PROJECT_OUT = project, project_route
        try:
            R.bake(types.SimpleNamespace(wtf=wtf, game_out=game_route))
        finally:
            R.PROFILES_OUT, R.PROJECT_OUT = saved_out, saved_route
        for label, out in (("the project's", project), ("the game's", os.path.join(os.path.dirname(game_route), "Profiles.lua"))):
            b = raw(out)
            d, got = load(out)
            check(shipped_line(b, "MelloUI") == full_line and head_of(b) == head_of(original) and d == orig_default,
                  "%s file: the shipped line, the head and `default` byte for byte (the saved default not baked)" % label)
            check(got.get("Raid") == SAVED["Raid"] and "Everything Off" not in got,
                  "%s file: the player's profiles in, \"Everything Off\" out" % label)
        check(not os.path.exists(project_route) and not os.path.exists(game_route),
              "no route data written (none learned in the stand-in saved variables)")
        check(raw(PROFILES) == original, "the repository's Media/Profiles.lua is untouched")

        print("== the release check on the watcher's result")
        src = raw(project).decode("utf-8")
        m = F.B.profiles_line_re().search(src)
        probs = F.file_problems(src, m, orig_profiles["MelloUI"])
        check(len(probs) == 1 and "Raid" in probs[0] and "bake_routes.py" in probs[0],
              "bake_full.py --check names the player's own profiles (a release would ship them) and nothing else")

    print()
    print("%d checks failed" % len(fails) if fails else "all checks pass")
    sys.exit(1 if fails else 0)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


if __name__ == "__main__":
    main()
